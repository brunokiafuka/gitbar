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
    /// Issues fetched per custom section in the Issues tab (keyed by section id).
    /// Populated when a user-created section's filters translate to a GitHub search.
    /// The default "Assigned issues" section is not in this map — it reads from `issues`.
    @Published var issuesBySectionId: [UUID: [GHIssue]] = [:]
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
    @Published var sectionsByTab: [PanelTab: [GitbarSection]] = [:]

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
        self.sectionsByTab = Config.readSectionsWithMigration()
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

    var badgeCount: Int {
        myPRs.count + reviewRequests.count + issues.count
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
            let issueSections = self.sectionsByTab[.issues] ?? []
            self.issuesBySectionId = await Self.fetchIssueSections(client: client, sections: issueSections)
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
            issuesBySectionId = [:]
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

    func sections(for tab: PanelTab) -> [GitbarSection] {
        (sectionsByTab[tab] ?? []).sorted(by: { $0.order < $1.order })
    }

    func updateSection(_ section: GitbarSection) {
        var next = sectionsByTab
        var list = next[section.tab] ?? []
        if let idx = list.firstIndex(where: { $0.id == section.id }) {
            list[idx] = section
            next[section.tab] = list
            sectionsByTab = next
            try? Config.saveSections(next)
            if section.tab == .issues { refresh() }
        }
    }

    func addSection(_ section: GitbarSection) {
        var next = sectionsByTab
        var list = next[section.tab] ?? []
        var toInsert = section
        toInsert.order = (list.map(\.order).max() ?? -1) + 1
        list.append(toInsert)
        next[section.tab] = list
        sectionsByTab = next
        try? Config.saveSections(next)
        if toInsert.tab == .issues { refresh() }
    }

    func deleteSection(id: UUID, tab: PanelTab) {
        var next = sectionsByTab
        guard var list = next[tab] else { return }
        // Default sections are structural; refuse deletion even if called directly.
        guard list.first(where: { $0.id == id })?.isDefault != true else { return }
        list.removeAll { $0.id == id }
        next[tab] = list
        sectionsByTab = next
        try? Config.saveSections(next)
        if tab == .issues { issuesBySectionId.removeValue(forKey: id) }
    }

    /// Moves `id` within `tab`. When `targetID` is nil, appends to the end.
    /// Ignores moves from other tabs (cross-tab drag not supported in v1).
    func reorderSection(in tab: PanelTab, moving id: UUID, before targetID: UUID?) {
        var next = sectionsByTab
        guard var list = next[tab],
              let fromIdx = list.firstIndex(where: { $0.id == id }) else { return }
        let moved = list.remove(at: fromIdx)
        if let targetID, let targetIdx = list.firstIndex(where: { $0.id == targetID }) {
            list.insert(moved, at: targetIdx)
        } else {
            list.append(moved)
        }
        for i in list.indices { list[i].order = i }
        next[tab] = list
        sectionsByTab = next
        try? Config.saveSections(next)
    }

    func toggleSectionCollapsed(tab: PanelTab, id: UUID) {
        var next = sectionsByTab
        guard var list = next[tab],
              let idx = list.firstIndex(where: { $0.id == id }) else { return }
        list[idx].collapsed.toggle()
        next[tab] = list
        sectionsByTab = next
        try? Config.saveSections(next)
    }

    func updateSectionSort(tab: PanelTab, id: UUID, sort: SortChoice) {
        var next = sectionsByTab
        guard var list = next[tab],
              let idx = list.firstIndex(where: { $0.id == id }) else { return }
        list[idx].sort = sort
        next[tab] = list
        sectionsByTab = next
        try? Config.saveSections(next)
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

    private static func fetchIssueSections(
        client: GitHubClient,
        sections: [GitbarSection]
    ) async -> [UUID: [GHIssue]] {
        guard !sections.isEmpty else { return [:] }
        return await withTaskGroup(of: (UUID, [GHIssue]).self) { group in
            for section in sections {
                let queries = section.remoteIssueSearchQueries()
                guard !queries.isEmpty else { continue }
                group.addTask {
                    var seen = Set<Int>()
                    var merged: [GHIssue] = []
                    for q in queries {
                        let rows: [GHIssue]
                        do {
                            rows = try await client.searchIssues(q: q, perPage: 50)
                        } catch {
                            rows = []
                        }
                        for row in rows where seen.insert(row.id).inserted {
                            merged.append(row)
                        }
                    }
                    return (section.id, merged)
                }
            }
            var out: [UUID: [GHIssue]] = [:]
            for await (id, rows) in group {
                out[id] = rows
            }
            return out
        }
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
