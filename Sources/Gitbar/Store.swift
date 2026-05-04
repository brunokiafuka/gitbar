import Foundation
import Combine

extension Notification.Name {
    static let gitbarStoreDidUpdate = Notification.Name("gitbarStoreDidUpdate")
}

@MainActor
final class Store: ObservableObject {
    @Published var myPRs: [GHIssue] = []
    @Published var reviewRequests: [GHIssue] = []
    @Published var reviewedByMePRs: [GHIssue] = []
    @Published var issues: [GHIssue] = []
    /// Rows fetched per section that runs as a per-section GitHub search (keyed by section id).
    /// Populated for: every Issues-tab section whose filters translate to a search query, and
    /// every Review-tab section whose filters carry a scoping condition (`hasScopingCondition`).
    /// Sections that filter the local queue (default "Assigned issues", default Review sections)
    /// are not in this map.
    @Published var customSectionRows: [UUID: [GHIssue]] = [:]
    /// From `GET /user` when the token is valid; cleared on sign-out.
    @Published private(set) var viewer: GHViewer?
    /// Latest aggregated review state per PR (`GHIssue.id`) for the user's own PRs, e.g. `CHANGES_REQUESTED`.
    @Published var myPRReviewState: [Int: String] = [:]
    /// Viewer's own most-recent review state per PR id for PRs the viewer has reviewed (others' PRs).
    @Published var viewerReviewState: [Int: String] = [:]
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

    /// Aggregate count of actionable PRs/issues — the union of rows from every visible
    /// section (across all tabs) whose `contributesToBadge` is on. Drives the menu-bar
    /// tray icon. Same source as the panel's tab badges so both surfaces agree.
    var badgeCount: Int { actionableCount(for: .all) }

    /// Union of review-requested and reviewed-by-me PRs (deduped by id, request wins).
    var reviewTabSourceRows: [GHIssue] {
        var seen = Set<Int>()
        var out: [GHIssue] = []
        for pr in reviewRequests where seen.insert(pr.id).inserted { out.append(pr) }
        for pr in reviewedByMePRs where seen.insert(pr.id).inserted { out.append(pr) }
        return out
    }

    /// Per-tab data source for section-driven layouts.
    func tabSourceRows(_ tab: PanelTab) -> [GHIssue] {
        switch tab {
        case .mine:        return myPRs
        case .review:      return reviewTabSourceRows
        case .issues:      return issues
        case .all, .stats: return []
        }
    }

    /// Rows belonging to a section, matching the panel's render logic exactly:
    /// remote-fetched rows for issues + scoped review sections, otherwise the matcher
    /// against the appropriate local queue.
    func rows(for section: GitbarSection) -> [GHIssue] {
        if section.tab == .issues {
            return customSectionRows[section.id] ?? []
        }
        if section.tab == .review, section.hasScopingCondition {
            return customSectionRows[section.id] ?? []
        }
        let source: [GHIssue] = section.tab == .review
            ? (section.targetsReviewedByMe ? reviewedByMePRs : reviewRequests)
            : tabSourceRows(section.tab)
        return source.filter {
            SectionMatcher.matches(
                section: section,
                row: $0,
                viewerLogin: myLogin,
                metadata: prRowMetadata[$0.id],
                reviewState: section.targetsReviewedByMe
                    ? viewerReviewState[$0.id]
                    : myPRReviewState[$0.id]
            )
        }
    }

    /// Union of row IDs from every section in `tab` that contributes to the badge.
    /// Hidden sections are skipped — they're not visible to the user, so they don't count.
    private func actionableRowIDs(in tab: PanelTab) -> Set<Int> {
        guard tab != .all, tab != .stats else { return [] }
        var ids = Set<Int>()
        for section in sections(for: tab)
            where section.effectiveContributesToBadge && section.visibility != .hidden
        {
            ids.formUnion(rows(for: section).map(\.id))
        }
        return ids
    }

    /// Deduped actionable rows for `tab`, in the order they appear across the contributing
    /// sections. The All tab uses this to render a flat "Pull requests" / "Issues" listing
    /// without re-implementing the matcher.
    func actionableRows(in tab: PanelTab) -> [GHIssue] {
        guard tab != .all, tab != .stats else { return [] }
        var seen = Set<Int>()
        var out: [GHIssue] = []
        for section in sections(for: tab)
            where section.effectiveContributesToBadge && section.visibility != .hidden
        {
            for row in rows(for: section) where seen.insert(row.id).inserted {
                out.append(row)
            }
        }
        return out
    }

    /// Tab-level actionable count. `.all` unions across mine/review/issues so a PR that
    /// surfaces in two places (e.g. a custom Review section + Mine) is only counted once.
    func actionableCount(for tab: PanelTab) -> Int {
        switch tab {
        case .all:
            var ids = Set<Int>()
            ids.formUnion(actionableRowIDs(in: .mine))
            ids.formUnion(actionableRowIDs(in: .review))
            ids.formUnion(actionableRowIDs(in: .issues))
            return ids.count
        case .stats:
            return 0
        case .mine, .review, .issues:
            return actionableRowIDs(in: tab).count
        }
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
            async let d = client.reviewedByMe()
            async let v = client.viewer()
            let (prs, reviews, iss, reviewedMe) = try await (a, b, c, d)
            let viewerResult = try? await v
            if let viewerResult {
                self.viewer = viewerResult
            }
            self.myPRs = prs
            self.reviewRequests = reviews
            self.issues = iss
            // Exclude PRs still in the review-request queue; those are "needs your review", not "waiting on author".
            let pendingIDs = Set(reviews.map(\.id))
            let reviewedOnly = reviewedMe.filter { !pendingIDs.contains($0.id) }
            self.reviewedByMePRs = reviewedOnly
            self.myPRReviewState = await Self.fetchMyPRReviewStates(client: client, prs: prs)
            if let viewerLogin = viewerResult?.login ?? self.viewer?.login {
                self.viewerReviewState = await Self.fetchViewerReviewStates(client: client, prs: reviewedOnly, viewer: viewerLogin)
            } else {
                self.viewerReviewState = [:]
            }
            let customRowSections = (self.sectionsByTab[.issues] ?? [])
                + (self.sectionsByTab[.review] ?? []).filter { $0.hasScopingCondition }
            self.customSectionRows = await Self.fetchCustomSectionRows(client: client, sections: customRowSections)
            self.prRowMetadata = await Self.fetchPRRowMetadata(client: client, mine: prs, reviewQueue: reviews + reviewedOnly)
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
            reviewedByMePRs = []
            issues = []
            customSectionRows = [:]
            myPRReviewState = [:]
            viewerReviewState = [:]
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
            if section.tab == .issues || section.tab == .review { refresh() }
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
        if toInsert.tab == .issues || toInsert.tab == .review { refresh() }
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
        if tab == .issues || tab == .review { customSectionRows.removeValue(forKey: id) }
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

    private static func fetchCustomSectionRows(
        client: GitHubClient,
        sections: [GitbarSection]
    ) async -> [UUID: [GHIssue]] {
        guard !sections.isEmpty else { return [:] }
        return await withTaskGroup(of: (UUID, [GHIssue]).self) { group in
            for section in sections {
                let queries: [String]
                switch section.tab {
                case .issues: queries = section.remoteIssueSearchQueries()
                case .review: queries = section.remoteReviewSearchQueries()
                default: queries = []
                }
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

    private static func fetchViewerReviewStates(client: GitHubClient, prs: [GHIssue], viewer: String) async -> [Int: String] {
        guard !prs.isEmpty else { return [:] }
        return await withTaskGroup(of: (Int, String?).self) { group in
            for pr in prs {
                group.addTask {
                    let repo = pr.repoFull
                    guard !repo.isEmpty else { return (pr.id, nil) }
                    do {
                        let state = try await client.viewerLatestReviewState(repo: repo, pr: pr.number, viewer: viewer)
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
