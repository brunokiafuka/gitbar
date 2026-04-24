import Foundation

struct GHUser: Decodable, Hashable {
    let login: String
    let avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case login
        case avatarUrl = "avatar_url"
    }
}

/// `GET /user` — authenticated GitHub account (login + avatar).
struct GHViewer: Decodable, Hashable {
    let login: String
    let avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case login
        case avatarUrl = "avatar_url"
    }
}

private struct GHAPIErrorBody: Decodable {
    let message: String?
}

private struct GHMergeResponse: Decodable {
    let merged: Bool
    let message: String?
}

struct GHLabel: Decodable, Hashable, Identifiable {
    let id: Int
    let name: String
    let color: String
}

struct GHPullRequestRef: Decodable, Hashable {
    let htmlUrl: String
    let mergedAt: String?

    enum CodingKeys: String, CodingKey {
        case htmlUrl = "html_url"
        case mergedAt = "merged_at"
    }
}

struct GHIssue: Decodable, Identifiable, Hashable {
    let id: Int
    let number: Int
    let title: String
    let state: String
    let htmlUrl: String
    let repositoryUrl: String
    let user: GHUser
    let labels: [GHLabel]
    let assignees: [GHUser]?
    let draft: Bool?
    let pullRequest: GHPullRequestRef?
    /// Present on search/API responses; used for stats (merge latency).
    let createdAt: String?
    let updatedAt: String
    let comments: Int

    enum CodingKeys: String, CodingKey {
        case id, number, title, state, labels, assignees, draft, user, comments
        case htmlUrl = "html_url"
        case repositoryUrl = "repository_url"
        case pullRequest = "pull_request"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var isPR: Bool { pullRequest != nil }
    var isDraft: Bool { draft == true }

    var repoFull: String {
        let parts = repositoryUrl.split(separator: "/")
        guard parts.count >= 2 else { return "" }
        return "\(parts[parts.count - 2])/\(parts[parts.count - 1])"
    }

    var repoShort: String {
        String(repoFull.split(separator: "/").last ?? "")
    }

    var updated: Date {
        ISO8601DateFormatter().date(from: updatedAt) ?? Date()
    }
}

struct GHSearchResponse: Decodable {
    let totalCount: Int
    let items: [GHIssue]

    enum CodingKeys: String, CodingKey {
        case totalCount = "total_count"
        case items
    }
}

struct GHCommitsSearchResponse: Decodable {
    let totalCount: Int

    enum CodingKeys: String, CodingKey {
        case totalCount = "total_count"
    }
}

/// `GET /user/events` — minimal fields for activity buckets.
struct GHUserEvent: Decodable {
    let type: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case type
        case createdAt = "created_at"
    }
}

struct GHReview: Decodable {
    let state: String // APPROVED, CHANGES_REQUESTED, COMMENTED, DISMISSED, PENDING
    let submittedAt: String?

    enum CodingKeys: String, CodingKey {
        case state
        case submittedAt = "submitted_at"
    }
}

// MARK: - Pull request detail + CI (for rich rows)

struct GHPullRequestDetail: Decodable {
    let additions: Int
    let deletions: Int
    let mergeable: Bool?
    let mergeableState: String?
    let head: GHCommitRef

    enum CodingKeys: String, CodingKey {
        case additions, deletions, mergeable, head
        case mergeableState = "mergeable_state"
    }
}

struct GHCommitRef: Decodable {
    let sha: String
}

struct GHCheckRunsResponse: Decodable {
    let checkRuns: [GHCheckRun]

    enum CodingKeys: String, CodingKey {
        case checkRuns = "check_runs"
    }
}

struct GHCheckRun: Decodable {
    let status: String
    let conclusion: String?
}

private struct GHRepoResponse: Decodable {
    let permissions: GHRepoPermissions?
}

private struct GHRepoPermissions: Decodable {
    let push: Bool?
}

/// CI aggregate for the menu bar row (left pill).
enum CIPillKind: String, Codable, Equatable, Sendable, Hashable, CaseIterable {
    case pass
    case fail
    case running
    case unknown
}

/// Extra fields for `PRRow` (CI, diff, merge conflict); keyed by `GHIssue.id`.
struct PRRowMetadata: Equatable, Sendable {
    var ci: CIPillKind
    var additions: Int
    var deletions: Int
    var hasMergeConflict: Bool
    var mergeableState: String?
    var canUserMerge: Bool
}

enum GHError: LocalizedError {
    case http(Int, String)
    case network(String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .http(let code, let body): return "HTTP \(code): \(body)"
        case .network(let m): return "Network: \(m)"
        case .decoding(let m): return "Decode: \(m)"
        }
    }
}

actor GitHubClient {
    private let token: String
    private let session: URLSession
    private let base = URL(string: "https://api.github.com")!

    init(token: String) {
        self.token = token
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: cfg)
    }

    func viewer() async throws -> GHViewer {
        let url = base.appendingPathComponent("user")
        let data = try await get(url: url)
        return try JSONDecoder().decode(GHViewer.self, from: data)
    }

    func myPRs() async throws -> [GHIssue] {
        try await search(q: "type:pr state:open author:@me sort:updated-desc")
    }

    func reviewRequests() async throws -> [GHIssue] {
        try await search(q: "type:pr state:open review-requested:@me sort:updated-desc")
    }

    func assignedIssues() async throws -> [GHIssue] {
        try await search(q: "type:issue state:open assignee:@me sort:updated-desc")
    }

    func reviewsLatestState(repo: String, pr: Int) async throws -> String? {
        let url = reposURL(repo: repo, path: ["pulls", "\(pr)", "reviews"])
        let data = try await get(url: url)
        let reviews = try JSONDecoder().decode([GHReview].self, from: data)
        let rank: [String: Int] = [
            "CHANGES_REQUESTED": 3, "APPROVED": 2, "COMMENTED": 1, "PENDING": 0, "DISMISSED": 0
        ]
        return reviews
            .max(by: { (rank[$0.state] ?? 0) < (rank[$1.state] ?? 0) })?
            .state
    }

    func pullRequestDetail(repo: String, number: Int) async throws -> GHPullRequestDetail {
        let url = reposURL(repo: repo, path: ["pulls", "\(number)"])
        let data = try await get(url: url)
        return try JSONDecoder().decode(GHPullRequestDetail.self, from: data)
    }

    func checkRuns(repo: String, headSha: String) async throws -> [GHCheckRun] {
        var comps = URLComponents(
            url: reposURL(repo: repo, path: ["commits", headSha, "check-runs"]),
            resolvingAgainstBaseURL: false
        )!
        comps.queryItems = [URLQueryItem(name: "per_page", value: "100")]
        guard let url = comps.url else { throw GHError.network("bad check-runs URL") }
        let data = try await get(url: url)
        return try JSONDecoder().decode(GHCheckRunsResponse.self, from: data).checkRuns
    }

    func canUserPushToRepo(_ repo: String) async throws -> Bool? {
        let url = reposURL(repo: repo, path: [])
        let data = try await get(url: url)
        let decoded = try JSONDecoder().decode(GHRepoResponse.self, from: data)
        return decoded.permissions?.push
    }

    func markReadyForReview(repo: String, number: Int) async throws {
        let url = reposURL(repo: repo, path: ["pulls", "\(number)"])
        let body = try JSONSerialization.data(withJSONObject: ["draft": false], options: [])
        _ = try await send(url: url, method: "PATCH", body: body)
    }

    func mergePullRequestSquash(repo: String, number: Int, commitTitle: String? = nil, commitMessage: String? = nil) async throws {
        let url = reposURL(repo: repo, path: ["pulls", "\(number)", "merge"])
        var payload: [String: Any] = ["merge_method": "squash"]
        if let commitTitle, !commitTitle.isEmpty {
            payload["commit_title"] = commitTitle
        }
        if let commitMessage, !commitMessage.isEmpty {
            payload["commit_message"] = commitMessage
        }
        let body = try JSONSerialization.data(withJSONObject: payload, options: [])
        let data = try await send(url: url, method: "PUT", body: body)
        let decoded = try JSONDecoder().decode(GHMergeResponse.self, from: data)
        if !decoded.merged {
            throw GHError.http(409, decoded.message ?? "GitHub did not merge this pull request")
        }
    }

    /// Maps GitHub check runs to a single CI pill for the row.
    nonisolated static func ciKind(from runs: [GHCheckRun]) -> CIPillKind {
        guard !runs.isEmpty else { return .unknown }
        let busyStatuses = Set(["queued", "in_progress", "waiting", "requested", "pending"])
        if runs.contains(where: { busyStatuses.contains($0.status) }) {
            return .running
        }
        let completed = runs.filter { $0.status == "completed" }
        let failed = completed.filter { r in
            switch r.conclusion {
            case "failure", "timed_out", "cancelled", "action_required": return true
            default: return false
            }
        }
        if !failed.isEmpty { return .fail }
        guard !completed.isEmpty else { return .unknown }
        let ok = completed.allSatisfy { r in
            switch r.conclusion {
            case "success", "skipped", "neutral": return true
            default: return false
            }
        }
        return ok ? .pass : .unknown
    }

    private func reposURL(repo: String, path: [String]) -> URL {
        var u = base
        u = u.appendingPathComponent("repos")
        for segment in repo.split(separator: "/") {
            u = u.appendingPathComponent(String(segment))
        }
        for p in path {
            u = u.appendingPathComponent(p)
        }
        return u
    }

    private func search(q: String) async throws -> [GHIssue] {
        try await searchIssues(q: q, perPage: 50)
    }

    /// `GET /search/issues` — total count only (per_page minimal).
    func searchIssuesTotalCount(q: String) async throws -> Int {
        let data = try await searchIssuesData(q: q, perPage: 1)
        return try JSONDecoder().decode(GHSearchResponse.self, from: data).totalCount
    }

    /// Sample issues/PRs for merge-time averaging.
    func searchIssues(q: String, perPage: Int) async throws -> [GHIssue] {
        let data = try await searchIssuesData(q: q, perPage: perPage)
        do {
            return try JSONDecoder().decode(GHSearchResponse.self, from: data).items
        } catch {
            throw GHError.decoding(String(describing: error))
        }
    }

    private func searchIssuesData(q: String, perPage: Int) async throws -> Data {
        var comps = URLComponents(
            url: base.appendingPathComponent("search/issues"),
            resolvingAgainstBaseURL: false
        )!
        comps.queryItems = [
            URLQueryItem(name: "q", value: q),
            URLQueryItem(name: "per_page", value: "\(min(max(perPage, 1), 100))")
        ]
        guard let url = comps.url else { throw GHError.network("bad search URL") }
        return try await get(url: url)
    }

    /// `GET /search/commits`
    func searchCommitsTotalCount(q: String) async throws -> Int {
        var comps = URLComponents(
            url: base.appendingPathComponent("search/commits"),
            resolvingAgainstBaseURL: false
        )!
        comps.queryItems = [
            URLQueryItem(name: "q", value: q),
            URLQueryItem(name: "per_page", value: "1")
        ]
        guard let url = comps.url else { throw GHError.network("bad commits search URL") }
        let data = try await get(url: url)
        do {
            return try JSONDecoder().decode(GHCommitsSearchResponse.self, from: data).totalCount
        } catch {
            throw GHError.decoding(String(describing: error))
        }
    }

    /// Recent activity for a user (`GET /users/{username}/events`). Authenticated as that user, private events are included.
    func userEvents(username: String, perPage: Int) async throws -> [GHUserEvent] {
        var u = base
        u = u.appendingPathComponent("users")
        u = u.appendingPathComponent(username)
        u = u.appendingPathComponent("events")
        var comps = URLComponents(url: u, resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "per_page", value: "\(min(max(perPage, 1), 100))")]
        guard let url = comps.url else { throw GHError.network("bad events URL") }
        let data = try await get(url: url)
        do {
            return try JSONDecoder().decode([GHUserEvent].self, from: data)
        } catch {
            throw GHError.decoding(String(describing: error))
        }
    }

    private func get(url: URL) async throws -> Data {
        try await send(url: url, method: "GET", body: nil)
    }

    private func send(url: URL, method: String, body: Data?) async throws -> Data {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.httpBody = body
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        req.setValue("gitbar/0.1", forHTTPHeaderField: "User-Agent")
        if body != nil {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse else {
                throw GHError.network("no response")
            }
            if !(200..<300).contains(http.statusCode) {
                let snippet: String
                if let err = try? JSONDecoder().decode(GHAPIErrorBody.self, from: data),
                   let m = err.message, !m.isEmpty {
                    snippet = m
                } else {
                    snippet = String(data: data, encoding: .utf8).map { String($0.prefix(200)) } ?? ""
                }
                throw GHError.http(http.statusCode, snippet)
            }
            return data
        } catch let err as GHError {
            throw err
        } catch {
            throw GHError.network(error.localizedDescription)
        }
    }
}

enum RelativeTime {
    static func short(_ date: Date, now: Date = Date()) -> String {
        let s = Int(max(0, now.timeIntervalSince(date)))
        switch s {
        case ..<60:     return "\(max(s, 1))s"
        case ..<3600:   return "\(s / 60)m"
        case ..<86_400: return "\(s / 3600)h"
        case ..<604_800: return "\(s / 86_400)d"
        default:        return "\(s / 604_800)w"
        }
    }
}
