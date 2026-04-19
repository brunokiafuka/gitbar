import Foundation
import Combine

extension Notification.Name {
    static let gitbarStoreDidUpdate = Notification.Name("gitbarStoreDidUpdate")
}

@MainActor
final class Store: ObservableObject {
    @Published var myPRs: [GHIssue] = []
    @Published var reviewRequests: [GHIssue] = []
    @Published var issues: [GHIssue] = []
    /// From `GET /user` when the token is valid; cleared on sign-out.
    @Published private(set) var viewer: GHViewer?
    /// Latest aggregated review state per PR (`GHIssue.id`) for the user's own PRs, e.g. `CHANGES_REQUESTED`.
    @Published var myPRReviewState: [Int: String] = [:]
    /// CI status, diff stats, merge conflict — from `GET /repos/.../pulls/{n}` + check-runs.
    @Published var prRowMetadata: [Int: PRRowMetadata] = [:]
    @Published var isLoading = false
    @Published var lastRefreshed: Date?
    @Published var errorMessage: String?
    @Published var token: String?

    /// Stats tab (`StatsLoader` + GitHub Search / events).
    @Published private(set) var statsSnapshot: StatsSnapshot?
    @Published var statsLoading = false
    @Published var statsError: String?
    /// Last range used for `loadStats` (for ⌘R / footer refresh while Stats is open).
    private(set) var lastStatsRange: StatsRange = .today
    /// Set by `PanelView` — stats are not polled; reload only when this tab is active and the user refreshes.
    var isStatsTabActive = false

    private var refreshTask: Task<Void, Never>?
    private var pollTimer: Timer?

    init() {
        self.token = Config.resolveToken()
    }

    var hasToken: Bool {
        guard let t = token else { return false }
        return !t.isEmpty
    }

    var myLogin: String? {
        if let login = viewer?.login { return login }
        return myPRs.first?.user.login
    }

    var avatarURL: URL? {
        guard let s = viewer?.avatarUrl, let u = URL(string: s) else { return nil }
        return u
    }

    /// Open PRs you authored whose latest review outcome is changes requested.
    var myPRsNeedingChanges: [GHIssue] {
        myPRs.filter { myPRReviewState[$0.id] == "CHANGES_REQUESTED" }
    }

    func refresh() {
        refreshTask?.cancel()
        refreshTask = Task { await self.runRefresh() }
    }

    func loadStats(range: StatsRange) async {
        lastStatsRange = range
        guard let token, !token.isEmpty else {
            statsSnapshot = nil
            statsError = "No GitHub token configured"
            return
        }
        guard let login = viewer?.login ?? myLogin else {
            statsSnapshot = nil
            statsError = nil
            return
        }
        statsLoading = true
        statsError = nil
        defer { statsLoading = false }
        let client = GitHubClient(token: token)
        do {
            statsSnapshot = try await StatsLoader.load(client: client, login: login, range: range)
        } catch {
            statsSnapshot = nil
            statsError = error.localizedDescription
        }
    }

    private func runRefresh() async {
        guard let token, !token.isEmpty else {
            self.errorMessage = "No GitHub token configured"
            return
        }
        self.isLoading = true
        defer { self.isLoading = false }
        let client = GitHubClient(token: token)
        do {
            async let a = client.myPRs()
            async let b = client.reviewRequests()
            async let c = client.assignedIssues()
            async let v = client.viewer()
            let (prs, reviews, iss) = try await (a, b, c)
            self.myPRs = prs
            self.reviewRequests = reviews
            self.issues = iss
            self.myPRReviewState = await Self.fetchMyPRReviewStates(client: client, prs: prs)
            self.prRowMetadata = await Self.fetchPRRowMetadata(client: client, mine: prs, reviewQueue: reviews)
            if let viewer = try? await v {
                self.viewer = viewer
            }
            self.errorMessage = nil
            self.lastRefreshed = Date()
            NotificationCenter.default.post(name: .gitbarStoreDidUpdate, object: self)
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    func updateToken(_ newToken: String) {
        let trimmed = newToken.trimmingCharacters(in: .whitespacesAndNewlines)
        self.token = trimmed
        do { try Config.saveToken(trimmed) } catch {
            self.errorMessage = "Failed to save token: \(error.localizedDescription)"
            return
        }
        if trimmed.isEmpty {
            viewer = nil
            myPRs = []
            reviewRequests = []
            issues = []
            myPRReviewState = [:]
            prRowMetadata = [:]
            statsSnapshot = nil
            statsError = nil
            errorMessage = nil
            lastRefreshed = nil
        }
        reconfigurePollingFromDefaults()
        if !trimmed.isEmpty {
            refresh()
        }
    }

    /// Applies `UserDefaults` key `gitbar.refreshInterval` (30s / 60s / 5m / manual).
    func reconfigurePollingFromDefaults() {
        guard hasToken else {
            stopPolling()
            return
        }
        let raw = UserDefaults.standard.string(forKey: "gitbar.refreshInterval") ?? "60s"
        switch raw {
        case "30s":  startPolling(every: 30)
        case "60s":  startPolling(every: 60)
        case "5m":   startPolling(every: 300)
        case "manual": stopPolling()
        default:     startPolling(every: 60)
        }
    }

    func startPolling(every seconds: TimeInterval) {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private static func fetchMyPRReviewStates(client: GitHubClient, prs: [GHIssue]) async -> [Int: String] {
        guard !prs.isEmpty else { return [:] }
        return await withTaskGroup(of: (Int, String?).self) { group in
            for pr in prs {
                group.addTask {
                    let repo = pr.repoFull
                    guard !repo.isEmpty else { return (pr.id, nil) }
                    do {
                        let state = try await client.reviewsLatestState(repo: repo, pr: pr.number)
                        return (pr.id, state)
                    } catch {
                        return (pr.id, nil)
                    }
                }
            }
            var out: [Int: String] = [:]
            for await (id, state) in group {
                if let state { out[id] = state }
            }
            return out
        }
    }

    private static func fetchPRRowMetadata(client: GitHubClient, mine: [GHIssue], reviewQueue: [GHIssue]) async -> [Int: PRRowMetadata] {
        var seen = Set<Int>()
        var list: [GHIssue] = []
        for pr in mine + reviewQueue where pr.isPR {
            if seen.insert(pr.id).inserted { list.append(pr) }
        }
        guard !list.isEmpty else { return [:] }
        return await withTaskGroup(of: (Int, PRRowMetadata?).self) { group in
            for pr in list {
                group.addTask {
                    let repo = pr.repoFull
                    guard !repo.isEmpty else { return (pr.id, nil) }
                    do {
                        let detail = try await client.pullRequestDetail(repo: repo, number: pr.number)
                        var ci: CIPillKind = .unknown
                        do {
                            let runs = try await client.checkRuns(repo: repo, headSha: detail.head.sha)
                            ci = GitHubClient.ciKind(from: runs)
                        } catch {
                            ci = .unknown
                        }
                        let conflict = detail.mergeableState?.lowercased() == "dirty"
                        return (
                            pr.id,
                            PRRowMetadata(
                                ci: ci,
                                additions: detail.additions,
                                deletions: detail.deletions,
                                hasMergeConflict: conflict
                            )
                        )
                    } catch {
                        return (pr.id, nil)
                    }
                }
            }
            var out: [Int: PRRowMetadata] = [:]
            for await (id, meta) in group {
                if let meta { out[id] = meta }
            }
            return out
        }
    }
}
