import Foundation

enum StatsRange: String, CaseIterable, Identifiable {
    case today
    case thisWeek

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .thisWeek: return "This week"
        }
    }
}

struct StatsSnapshot: Equatable {
    /// Seven equal buckets over the rolling 24h window ending now (oldest → newest).
    var activityBuckets: [Int]
    var activityBucketLabels: [String]

    var prsMerged: Int
    var prsMergedTrend: Int?

    var prsReviewed: Int
    var prsReviewedTrend: Int?

    var issuesClosed: Int
    var issuesClosedTrend: Int?

    var commits: Int
    var commitsTrend: Int?

    /// Median minutes from PR open → merge. Nil when fewer than 3 merged PRs — a sample that small isn't a "typical."
    var typicalMergeMinutes: Int?
    /// Prior window's median, for computing absolute deltas in the UI.
    /// Percent change would blow up on small bases (3 min → 66 min reads as "+2100%" and tells you nothing).
    var typicalMergeMinutesPrev: Int?
    /// Number of merged PRs backing the median — surfaced so the UI can disclose sample size.
    var mergeSampleSize: Int

    var commitStreakDays: Int
    /// Last 7 calendar days (oldest → newest); whether you had ≥1 commit that day.
    var lastSevenDaysCommitted: [Bool]
}

enum StatsLoader {
    private static let dayFmt: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar.current
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static func dayString(_ date: Date) -> String {
        dayFmt.string(from: date)
    }

    private static func parseGHDate(_ s: String) -> Date? {
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: s) { return d }
        f1.formatOptions = [.withInternetDateTime]
        if let d = f1.date(from: s) { return d }
        return nil
    }

    private static let isoFmt: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func isoTs(_ d: Date) -> String { isoFmt.string(from: d) }

    private static func mergedPRQuery(author: String, when: String) -> String {
        "type:pr is:merged author:\(author) merged:\(when)"
    }

    private static func reviewedMergedQuery(login: String, when: String) -> String {
        "type:pr is:merged reviewed-by:\(login) merged:\(when)"
    }

    private static func closedIssuesQuery(login: String, when: String) -> String {
        "type:issue is:closed assignee:\(login) closed:\(when)"
    }

    private static func commitsRangeQuery(author: String, when: String) -> String {
        "author:\(author) committer-date:\(when)"
    }

    /// Rolling 24h activity from `/user/events`.
    private static func activityBuckets(events: [GHUserEvent], now: Date = Date()) -> ([Int], [String]) {
        let window: TimeInterval = 24 * 3600
        let start = now.addingTimeInterval(-window)
        var buckets = Array(repeating: 0, count: 7)
        let slice = window / 7

        let labelFmt = DateFormatter()
        labelFmt.locale = Locale(identifier: "en_US_POSIX")
        labelFmt.timeZone = TimeZone.current
        labelFmt.dateFormat = "ha"

        let labels: [String] = (0..<7).map { i in
            if i == 6 { return "now" }
            let t = start.addingTimeInterval(slice * Double(i))
            return labelFmt.string(from: t).lowercased()
        }

        for ev in events {
            guard let t = parseGHDate(ev.createdAt), t >= start, t <= now else { continue }
            let idx = min(6, max(0, Int((t.timeIntervalSince(start)) / slice)))
            buckets[idx] += 1
        }

        return (buckets, labels)
    }

    /// Returns the median open→merge time and the sample size that fed it.
    /// Median is nil when fewer than 3 PRs merged — one outlier dominates smaller samples.
    private static func mergeTimings(issues: [GHIssue]) -> (median: Int?, sampleSize: Int) {
        var minutes: [Double] = []
        for i in issues where i.isPR {
            guard let createdS = i.createdAt, let mergedS = i.pullRequest?.mergedAt,
                  let c = parseGHDate(createdS), let m = parseGHDate(mergedS), m > c
            else { continue }
            minutes.append(m.timeIntervalSince(c) / 60)
        }
        let n = minutes.count
        guard n >= 3 else { return (nil, n) }
        minutes.sort()
        let mid = minutes[n / 2]
        let median = n.isMultiple(of: 2) ? (minutes[n / 2 - 1] + mid) / 2 : mid
        return (Int(median.rounded()), n)
    }

    /// Local calendar days (yyyy-MM-dd) that had at least one push (proxy for “committed”), from the public event timeline.
    private static func pushContributionDays(_ events: [GHUserEvent], calendar: Calendar) -> Set<String> {
        var days = Set<String>()
        for ev in events where ev.type == "PushEvent" {
            guard let t = parseGHDate(ev.createdAt) else { continue }
            days.insert(dayString(calendar.startOfDay(for: t)))
        }
        return days
    }

    private static func commitStreakDays(pushDays: Set<String>, calendar: Calendar, now: Date) -> Int {
        let todayStart = calendar.startOfDay(for: now)
        var startOffset = 0
        if !pushDays.contains(dayString(todayStart)) {
            startOffset = 1
        }
        var streak = 0
        for offset in startOffset..<120 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: todayStart) else { break }
            if pushDays.contains(dayString(day)) {
                streak += 1
            } else {
                break
            }
        }
        return streak
    }

    private static func lastSevenDaysPushDots(pushDays: Set<String>, calendar: Calendar, now: Date) -> [Bool] {
        let todayStart = calendar.startOfDay(for: now)
        var out: [Bool] = []
        for offset in (0..<7).reversed() {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: todayStart) else { continue }
            out.append(pushDays.contains(dayString(day)))
        }
        return out
    }

    static func load(client: GitHubClient, login: String, range: StatsRange) async throws -> StatsSnapshot {
        let cal = Calendar.current
        let now = Date()
        let todayStart = cal.startOfDay(for: now)
        let todayStr = dayString(todayStart)

        // For `.today` we match UP TO THE CURRENT MOMENT on both sides — otherwise today (partial) vs yesterday (full 24h)
        // makes every morning look like a regression. `.thisWeek` stays day-aligned since the framing is calendar-ish.
        let curWhen: String
        let prevWhen: String
        switch range {
        case .today:
            let priorStart = cal.date(byAdding: .day, value: -1, to: todayStart)!
            let priorEnd = cal.date(byAdding: .day, value: -1, to: now)!
            curWhen = "\(isoTs(todayStart))..\(isoTs(now))"
            prevWhen = "\(isoTs(priorStart))..\(isoTs(priorEnd))"
        case .thisWeek:
            let wStart = cal.date(byAdding: .day, value: -6, to: todayStart)!
            let pStart = cal.date(byAdding: .day, value: -13, to: todayStart)!
            let pEnd = cal.date(byAdding: .day, value: -7, to: todayStart)!
            curWhen = "\(dayString(wStart))..\(todayStr)"
            prevWhen = "\(dayString(pStart))..\(dayString(pEnd))"
        }

        // One request first (event timeline); streak/dots use PushEvents from this feed — avoids N× commit search calls.
        let evList = try await client.userEvents(username: login, perPage: 100)
        let (buckets, labels) = activityBuckets(events: evList, now: now)
        let pushDays = pushContributionDays(evList, calendar: cal)
        let streakDays = commitStreakDays(pushDays: pushDays, calendar: cal, now: now)
        let sevenDots = lastSevenDaysPushDots(pushDays: pushDays, calendar: cal, now: now)

        // Serialize Search API calls to stay under GitHub secondary rate limits (parallel bursts → 403).
        let prsMerged = try await client.searchIssuesTotalCount(q: mergedPRQuery(author: login, when: curWhen))
        let prsReviewed = try await client.searchIssuesTotalCount(q: reviewedMergedQuery(login: login, when: curWhen))
        let issuesClosed = try await client.searchIssuesTotalCount(q: closedIssuesQuery(login: login, when: curWhen))
        let commits = try await client.searchCommitsTotalCount(q: commitsRangeQuery(author: login, when: curWhen))

        let prsMergedP = try await client.searchIssuesTotalCount(q: mergedPRQuery(author: login, when: prevWhen))
        let prsReviewedP = try await client.searchIssuesTotalCount(q: reviewedMergedQuery(login: login, when: prevWhen))
        let issuesClosedP = try await client.searchIssuesTotalCount(q: closedIssuesQuery(login: login, when: prevWhen))
        let commitsP = try await client.searchCommitsTotalCount(q: commitsRangeQuery(author: login, when: prevWhen))

        let mi = try await client.searchIssues(q: mergedPRQuery(author: login, when: curWhen), perPage: 30)
        let mip = try await client.searchIssues(q: mergedPRQuery(author: login, when: prevWhen), perPage: 30)
        let cur = mergeTimings(issues: mi)
        let prev = mergeTimings(issues: mip)

        return StatsSnapshot(
            activityBuckets: buckets,
            activityBucketLabels: labels,
            prsMerged: prsMerged,
            prsMergedTrend: prsMerged - prsMergedP,
            prsReviewed: prsReviewed,
            prsReviewedTrend: prsReviewed - prsReviewedP,
            issuesClosed: issuesClosed,
            issuesClosedTrend: issuesClosed - issuesClosedP,
            commits: commits,
            commitsTrend: commits - commitsP,
            typicalMergeMinutes: cur.median,
            typicalMergeMinutesPrev: prev.median,
            mergeSampleSize: cur.sampleSize,
            commitStreakDays: streakDays,
            lastSevenDaysCommitted: sevenDots
        )
    }
}
