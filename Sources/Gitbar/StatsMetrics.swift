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

    /// Median minutes from PR open → merge for your merged PRs in the window (proxy for “pace”).
    var avgMergeMinutes: Int?
    /// Fractional change vs prior window; negative = faster merges.
    var avgMergePercentVsPrior: Double?

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

    private static func mergedPRQuery(author: String, startDay: String, endDay: String) -> String {
        "type:pr is:merged author:\(author) merged:\(startDay)..\(endDay)"
    }

    private static func reviewedMergedQuery(login: String, startDay: String, endDay: String) -> String {
        "type:pr is:merged reviewed-by:\(login) merged:\(startDay)..\(endDay)"
    }

    private static func closedIssuesQuery(login: String, startDay: String, endDay: String) -> String {
        "type:issue is:closed assignee:\(login) closed:\(startDay)..\(endDay)"
    }

    private static func commitsRangeQuery(author: String, startDay: String, endDay: String) -> String {
        "author:\(author) committer-date:\(startDay)..\(endDay)"
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

    private static func medianMergeMinutes(issues: [GHIssue]) -> Int? {
        var minutes: [Double] = []
        for i in issues where i.isPR {
            guard let createdS = i.createdAt, let mergedS = i.pullRequest?.mergedAt,
                  let c = parseGHDate(createdS), let m = parseGHDate(mergedS), m > c
            else { continue }
            minutes.append(m.timeIntervalSince(c) / 60)
        }
        guard !minutes.isEmpty else { return nil }
        minutes.sort()
        return Int(minutes[minutes.count / 2])
    }

    private static func percentChange(oldMinutes: Int?, newMinutes: Int?) -> Double? {
        guard let o = oldMinutes, let n = newMinutes, o > 0 else { return nil }
        return Double(n - o) / Double(o) * 100
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

        let dCur0: String
        let dCur1: String
        let dPrev0: String
        let dPrev1: String

        switch range {
        case .today:
            dCur0 = todayStr
            dCur1 = todayStr
            let yStart = cal.date(byAdding: .day, value: -1, to: todayStart)!
            let yStr = dayString(yStart)
            dPrev0 = yStr
            dPrev1 = yStr
        case .thisWeek:
            let wStart = cal.date(byAdding: .day, value: -6, to: todayStart)!
            dCur0 = dayString(wStart)
            dCur1 = todayStr
            let pStart = cal.date(byAdding: .day, value: -13, to: todayStart)!
            let pEnd = cal.date(byAdding: .day, value: -7, to: todayStart)!
            dPrev0 = dayString(pStart)
            dPrev1 = dayString(pEnd)
        }

        // One request first (event timeline); streak/dots use PushEvents from this feed — avoids N× commit search calls.
        let evList = try await client.userEvents(username: login, perPage: 100)
        let (buckets, labels) = activityBuckets(events: evList, now: now)
        let pushDays = pushContributionDays(evList, calendar: cal)
        let streakDays = commitStreakDays(pushDays: pushDays, calendar: cal, now: now)
        let sevenDots = lastSevenDaysPushDots(pushDays: pushDays, calendar: cal, now: now)

        // Serialize Search API calls to stay under GitHub secondary rate limits (parallel bursts → 403).
        let prsMerged = try await client.searchIssuesTotalCount(q: mergedPRQuery(author: login, startDay: dCur0, endDay: dCur1))
        let prsReviewed = try await client.searchIssuesTotalCount(q: reviewedMergedQuery(login: login, startDay: dCur0, endDay: dCur1))
        let issuesClosed = try await client.searchIssuesTotalCount(q: closedIssuesQuery(login: login, startDay: dCur0, endDay: dCur1))
        let commits = try await client.searchCommitsTotalCount(q: commitsRangeQuery(author: login, startDay: dCur0, endDay: dCur1))

        let prsMergedP = try await client.searchIssuesTotalCount(q: mergedPRQuery(author: login, startDay: dPrev0, endDay: dPrev1))
        let prsReviewedP = try await client.searchIssuesTotalCount(q: reviewedMergedQuery(login: login, startDay: dPrev0, endDay: dPrev1))
        let issuesClosedP = try await client.searchIssuesTotalCount(q: closedIssuesQuery(login: login, startDay: dPrev0, endDay: dPrev1))
        let commitsP = try await client.searchCommitsTotalCount(q: commitsRangeQuery(author: login, startDay: dPrev0, endDay: dPrev1))

        let mergeSampleQ = mergedPRQuery(author: login, startDay: dCur0, endDay: dCur1)
        let mergeSamplePrevQ = mergedPRQuery(author: login, startDay: dPrev0, endDay: dPrev1)
        let mi = try await client.searchIssues(q: mergeSampleQ, perPage: 30)
        let mip = try await client.searchIssues(q: mergeSamplePrevQ, perPage: 30)
        let avgMerge = medianMergeMinutes(issues: mi)
        let avgMergePrev = medianMergeMinutes(issues: mip)
        let mergePct = percentChange(oldMinutes: avgMergePrev, newMinutes: avgMerge)

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
            avgMergeMinutes: avgMerge,
            avgMergePercentVsPrior: mergePct,
            commitStreakDays: streakDays,
            lastSevenDaysCommitted: sevenDots
        )
    }
}
