import SwiftUI
import AppKit

enum PanelTab: String, CaseIterable, Identifiable, Codable, Sendable {
    case all, mine, review, issues, stats
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: return "All"
        case .mine: return "Mine"
        case .review: return "Review"
        case .issues: return "Issues"
        case .stats: return "Stats"
        }
    }
    var accent: Color? {
        switch self {
        case .review: return Theme.amber
        default:      return nil
        }
    }

    var hiddenStorageKey: String { "gitbar.tabs.hidden.\(rawValue)" }
}

private struct PanelListEntry: Identifiable, Hashable {
    let id: String
    let htmlURL: String
}

private struct TabSectionRows: Identifiable {
    let section: GitbarSection
    let rows: [GHIssue]
    var id: UUID { section.id }
}

struct PanelView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var updater: Updater
    @Environment(\.colorScheme) private var colorScheme
    @State private var tab: PanelTab = .all
    @State private var selectedIndex: Int = 0
    @State private var editorState: SectionEditorMode?
    @State private var managingSections: Bool = false
    @FocusState private var listKeyboardFocused: Bool

    @AppStorage(PanelTab.all.hiddenStorageKey)    private var hideAll = false
    @AppStorage(PanelTab.mine.hiddenStorageKey)   private var hideMine = false
    @AppStorage(PanelTab.review.hiddenStorageKey) private var hideReview = false
    @AppStorage(PanelTab.issues.hiddenStorageKey) private var hideIssues = false
    @AppStorage(PanelTab.stats.hiddenStorageKey)  private var hideStats = false

    /// Tabs the user hasn't hidden, in the canonical `PanelTab.allCases` order.
    /// Always returns at least `[.all]` — the panel won't render with zero tabs even
    /// if `UserDefaults` somehow ends up with every tab flagged hidden.
    private var visibleTabs: [PanelTab] {
        let visible = PanelTab.allCases.filter { !isHidden($0) }
        return visible.isEmpty ? [.all] : visible
    }

    private func isHidden(_ t: PanelTab) -> Bool {
        switch t {
        case .all:    return hideAll
        case .mine:   return hideMine
        case .review: return hideReview
        case .issues: return hideIssues
        case .stats:  return hideStats
        }
    }

    /// Stable string that changes whenever any tab visibility flag flips, so a single
    /// `onChange` can re-clamp the active tab when the visible set shrinks.
    private var visibilitySignature: String {
        visibleTabs.map(\.rawValue).joined(separator: ",")
    }

    private var isOverlayActive: Bool { managingSections || editorState != nil }
    private let panelWidth: CGFloat = 520
    private let panelHeight: CGFloat = 620

    let onOpenSettings: () -> Void

    var body: some View {
        panelChrome
            .frame(width: panelWidth, height: panelHeight)
            .background(panelBackdrop)
            .focusable()
            .focused($listKeyboardFocused)
            .focusEffectDisabled()
            .onAppear {
                if store.hasToken { store.refresh() }
                listKeyboardFocused = true
                clampActiveTabToVisible()
                store.isStatsTabActive = (tab == .stats)
            }
            .onChange(of: tab) { _, new in
                store.isStatsTabActive = (new == .stats)
                selectedIndex = 0
                clampSelection()
            }
            .onChange(of: visibilitySignature) { _, _ in
                clampActiveTabToVisible()
            }
            .onChange(of: listSignature) { _, _ in
                clampSelection()
            }
            .onKeyPress { handleKeyPress($0) }
    }

    private var panelBackdrop: some View {
        ZStack {
            VisualEffect(material: .menu)
            if colorScheme == .dark {
                Color.black.opacity(0.2)
            }
        }
    }

    private var panelDivider: some View {
        Rectangle()
            .fill(Theme.hairline(colorScheme))
            .frame(height: 1)
    }

    @ViewBuilder
    private var panelChrome: some View {
        VStack(spacing: 0) {
            if !isOverlayActive {
                tabBar
                    .animation(.easeInOut(duration: 0.16), value: tab)
                panelDivider
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(overlayIdentity)
                .transition(.opacity)
            if !isOverlayActive {
                panelDivider
                footer
            }
        }
    }

    private var overlayIdentity: String {
        if editorState != nil { return "editor" }
        if managingSections { return "manager" }
        return tab.rawValue
    }

    private func handleKeyPress(_ press: KeyPress) -> KeyPress.Result {
        if press.modifiers == .command {
            switch press.key {
            case KeyEquivalent("1"): return selectTabKeyboard(.all)
            case KeyEquivalent("2"): return selectTabKeyboard(.mine)
            case KeyEquivalent("3"): return selectTabKeyboard(.review)
            case KeyEquivalent("4"): return selectTabKeyboard(.issues)
            case KeyEquivalent("5"): return selectTabKeyboard(.stats)
            default: break
            }
        }

        switch press.key {
        case .upArrow: return handleUpArrow()
        case .downArrow: return handleDownArrow()
        case .leftArrow: return handleLeftArrow()
        case .rightArrow: return handleRightArrow()
        case .return: return handleReturn()
        default: return .ignored
        }
    }

    private var listSignature: String {
        let customIssueIds = store.issuesBySectionId
            .sorted { $0.key.uuidString < $1.key.uuidString }
            .map { "\($0.key.uuidString):\($0.value.map(\.id))" }
            .joined(separator: ",")
        return "\(tab.rawValue)|\(store.myPRs.map(\.id))|\(store.reviewRequests.map(\.id))|\(store.reviewedByMePRs.map(\.id))|\(store.issues.map(\.id))|\(store.sections(for: .mine).map(\.id.uuidString))|\(store.sections(for: .review).map(\.id.uuidString))|\(store.sections(for: .issues).map(\.id.uuidString))|\(customIssueIds)"
    }

    private let allTabPreviewLimit = 5

    private var navigableItems: [PanelListEntry] {
        switch tab {
        case .stats:
            return []
        case .all:
            var rows: [PanelListEntry] = []
            rows.append(contentsOf: store.myPRs.prefix(allTabPreviewLimit).map { PanelListEntry(id: "all-m-\($0.id)", htmlURL: $0.htmlUrl) })
            rows.append(contentsOf: store.reviewRequests.prefix(allTabPreviewLimit).map { PanelListEntry(id: "all-r-\($0.id)", htmlURL: $0.htmlUrl) })
            rows.append(contentsOf: store.issues.prefix(allTabPreviewLimit).map { PanelListEntry(id: "all-i-\($0.id)", htmlURL: $0.htmlUrl) })
            return rows
        case .mine:
            return sectionEntries(for: .mine, sourceRows: store.myPRs)
        case .review:
            return sectionEntries(for: .review, sourceRows: store.reviewTabSourceRows)
        case .issues:
            return sectionEntries(for: .issues, sourceRows: store.issues)
        }
    }

    private func sectionEntries(for tab: PanelTab, sourceRows: [GHIssue]) -> [PanelListEntry] {
        var items: [PanelListEntry] = []
        for sectionRows in renderedSections(for: tab, sourceRows: sourceRows) {
            guard !sectionRows.section.collapsed else { continue }
            items.append(contentsOf: sectionRows.rows.map {
                PanelListEntry(id: "sec-\(sectionRows.section.id.uuidString)-\($0.id)", htmlURL: $0.htmlUrl)
            })
        }
        items.append(contentsOf: unmatchedRows(for: tab, sourceRows: sourceRows).map {
            PanelListEntry(id: "all-\(tab.rawValue)-\($0.id)", htmlURL: $0.htmlUrl)
        })
        return items
    }

    private func renderedSections(for tab: PanelTab, sourceRows: [GHIssue]) -> [TabSectionRows] {
        store.sections(for: tab)
            .filter { $0.visibility != .hidden }
            .map { section in
                let rows = rowsForSection(section, sourceRows: sourceRows)
                return TabSectionRows(section: section, rows: sort(rows, by: section.sort))
            }
            .filter { !$0.rows.isEmpty }
    }

    /// Rows for a single section. Issues-tab sections read remotely-fetched rows from the store
    /// (each section runs its filters as a GitHub search). PR-tab sections filter `sourceRows`
    /// locally via the matcher, with the Review tab splitting between the review-request queue
    /// and reviewed-by-me PRs depending on the section's conditions.
    private func rowsForSection(_ section: GitbarSection, sourceRows: [GHIssue]) -> [GHIssue] {
        if section.tab == .issues {
            return store.issuesBySectionId[section.id] ?? []
        }
        let effectiveSource = sectionSource(for: section, tabSource: sourceRows)
        return effectiveSource.filter {
            SectionMatcher.matches(
                section: section,
                row: $0,
                viewerLogin: store.myLogin,
                metadata: store.prRowMetadata[$0.id],
                reviewState: reviewState(for: $0, section: section)
            )
        }
    }

    private func sectionSource(for section: GitbarSection, tabSource: [GHIssue]) -> [GHIssue] {
        guard section.tab == .review else { return tabSource }
        return section.targetsReviewedByMe ? store.reviewedByMePRs : store.reviewRequests
    }

    private func reviewState(for row: GHIssue, section: GitbarSection) -> String? {
        section.targetsReviewedByMe
            ? store.viewerReviewState[row.id]
            : store.myPRReviewState[row.id]
    }

    private func unmatchedRows(for tab: PanelTab, sourceRows: [GHIssue]) -> [GHIssue] {
        let matchedIDs = Set(
            renderedSections(for: tab, sourceRows: sourceRows)
                .flatMap(\.rows)
                .map(\.id)
        )
        // On the Review tab, the catch-all only surfaces PRs awaiting your review.
        // Reviewed-by-me PRs only belong in their dedicated sections (e.g. Waiting on author).
        let eligible: [GHIssue] = tab == .review ? store.reviewRequests : sourceRows
        return eligible.filter { !matchedIDs.contains($0.id) }
    }

    private func sort(_ rows: [GHIssue], by choice: SortChoice) -> [GHIssue] {
        switch choice {
        case .updatedDesc:
            return rows.sorted { $0.updated > $1.updated }
        case .updatedAsc:
            return rows.sorted { $0.updated < $1.updated }
        case .repo:
            return rows.sorted {
                if $0.repoFull == $1.repoFull { return $0.updated > $1.updated }
                return $0.repoFull.localizedCaseInsensitiveCompare($1.repoFull) == .orderedAscending
            }
        }
    }

    private func clampSelection() {
        let n = navigableItems.count
        guard n > 0 else { return }
        if selectedIndex < 0 { selectedIndex = 0 }
        if selectedIndex >= n { selectedIndex = n - 1 }
    }

    private func moveSelection(_ delta: Int) {
        let items = navigableItems
        guard !items.isEmpty else { return }
        selectedIndex = max(0, min(items.count - 1, selectedIndex + delta))
    }

    private func openSelected() {
        let items = navigableItems
        guard selectedIndex >= 0, selectedIndex < items.count else { return }
        let url = items[selectedIndex].htmlURL
        if let u = URL(string: url) { NSWorkspace.shared.open(u) }
    }

    private func switchToTab(_ t: PanelTab) {
        withAnimation(.easeInOut(duration: 0.18)) {
            tab = t
            selectedIndex = 0
            clampSelection()
        }
    }

    private func cycleTab(_ delta: Int) {
        let all = visibleTabs
        guard let i = all.firstIndex(of: tab) else {
            if let first = all.first { switchToTab(first) }
            return
        }
        let n = all.count
        guard n > 0 else { return }
        let next = ((i + delta) % n + n) % n
        switchToTab(all[next])
    }

    private func selectTabKeyboard(_ t: PanelTab) -> KeyPress.Result {
        // Visibility is presentational; ⌘1…5 still jumps directly to any tab.
        switchToTab(t)
        return .handled
    }

    private func clampActiveTabToVisible() {
        let visible = visibleTabs
        if !visible.contains(tab), let first = visible.first {
            tab = first
            selectedIndex = 0
        }
    }

    private func handleUpArrow() -> KeyPress.Result {
        if navigableItems.isEmpty {
            cycleTab(-1)
            return .handled
        }
        moveSelection(-1)
        return .handled
    }

    private func handleDownArrow() -> KeyPress.Result {
        if navigableItems.isEmpty {
            cycleTab(1)
            return .handled
        }
        moveSelection(1)
        return .handled
    }

    private func handleLeftArrow() -> KeyPress.Result {
        if tab == .stats || navigableItems.isEmpty {
            cycleTab(-1)
            return .handled
        }
        return .ignored
    }

    private func handleRightArrow() -> KeyPress.Result {
        if tab == .stats || navigableItems.isEmpty {
            cycleTab(1)
            return .handled
        }
        return .ignored
    }

    private func handleReturn() -> KeyPress.Result {
        guard tab != .stats, !navigableItems.isEmpty else { return .ignored }
        openSelected()
        return .handled
    }

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(visibleTabs) { t in
                tabButton(t)
            }
            Spacer(minLength: 4)
            Menu {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { managingSections = true }
                } label: {
                    Text("View filters")
                }
                if canCreateSectionForCurrentTab {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { editorState = .create(tab) }
                    } label: {
                        Text("Create filter in \(tab.label)")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 20)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Filters")
            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Settings (⌘,)")
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private var canCreateSectionForCurrentTab: Bool {
        switch tab {
        case .mine, .review, .issues: return true
        case .all, .stats: return false
        }
    }

    private func tabButton(_ t: PanelTab) -> some View {
        let c = count(for: t)
        let selected = tab == t
        return Button {
            switchToTab(t)
        } label: {
            HStack(spacing: 5) {
                Text(t.label)
                    .font(.system(size: 11.5, weight: .semibold))
                if c > 0 {
                    Text("\(c)")
                        .font(.system(size: 9.5, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(t.accent ?? .secondary)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 14, minHeight: 14)
                        .background(
                            (t.accent ?? Color.primary).opacity(t.accent == nil ? 0.08 : 0.16),
                            in: RoundedRectangle(cornerRadius: 4)
                        )
                }
            }
            .foregroundStyle(selected ? .primary : .secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(selected ? Theme.surfaceHi(colorScheme) : .clear,
                        in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        if let mode = editorState {
            SectionEditorView(
                mode: mode,
                onSave: { section in
                    switch mode {
                    case .create: store.addSection(section)
                    case .edit: store.updateSection(section)
                    }
                    withAnimation(.easeInOut(duration: 0.18)) { editorState = nil }
                },
                onDelete: {
                    if case .edit(let section) = mode, !section.isDefault {
                        store.deleteSection(id: section.id, tab: section.tab)
                    }
                    withAnimation(.easeInOut(duration: 0.18)) { editorState = nil }
                },
                onCancel: { withAnimation(.easeInOut(duration: 0.18)) { editorState = nil } }
            )
        } else if managingSections {
            SectionsManagerView(
                onCreate: { targetTab in
                    withAnimation(.easeInOut(duration: 0.18)) { editorState = .create(targetTab) }
                },
                onEdit: { section in
                    withAnimation(.easeInOut(duration: 0.18)) { editorState = .edit(section) }
                },
                onBack: { withAnimation(.easeInOut(duration: 0.18)) { managingSections = false } }
            )
            .environmentObject(store)
        } else if tab == .stats {
            StatsView()
        } else if !store.hasToken {
            EmptyTokenState(onOpenSettings: onOpenSettings)
        } else if let err = store.errorMessage,
                  store.myPRs.isEmpty,
                  store.reviewRequests.isEmpty,
                  store.reviewedByMePRs.isEmpty,
                  store.issues.isEmpty {
            errorState(err)
        } else if isEmpty {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if tab == .all, showMine, !store.myPRs.isEmpty {
                            SectionHeader(
                                icon: .gitPullRequest,
                                title: "My pull requests",
                                count: store.myPRs.count,
                                accent: .secondary
                            )
                            ForEach(Array(store.myPRs.prefix(allTabPreviewLimit))) { pr in
                                PRRow(
                                    pr: pr,
                                    showAuthor: true,
                                    reviewState: store.myPRReviewState[pr.id],
                                    metadata: store.prRowMetadata[pr.id],
                                    isSelected: isEntrySelected("all-m-\(pr.id)")
                                )
                                .id("all-m-\(pr.id)")
                            }
                            if store.myPRs.count > allTabPreviewLimit, !isHidden(.mine) {
                                viewAllButton(destination: .mine, remaining: store.myPRs.count - allTabPreviewLimit)
                            }
                        }
                        if tab == .all, showReview, !store.reviewRequests.isEmpty {
                            SectionHeader(
                                icon: .circleDotDashed,
                                title: "Awaiting your review",
                                count: store.reviewRequests.count,
                                accent: Theme.amber
                            )
                            ForEach(Array(store.reviewRequests.prefix(allTabPreviewLimit))) { pr in
                                PRRow(
                                    pr: pr,
                                    showAuthor: true,
                                    metadata: store.prRowMetadata[pr.id],
                                    isSelected: isEntrySelected("all-r-\(pr.id)")
                                )
                                .id("all-r-\(pr.id)")
                            }
                            if store.reviewRequests.count > allTabPreviewLimit, !isHidden(.review) {
                                viewAllButton(destination: .review, remaining: store.reviewRequests.count - allTabPreviewLimit)
                            }
                        }
                        if tab == .all, showIssues, !store.issues.isEmpty {
                            SectionHeader(
                                icon: .circleDot,
                                title: "Assigned issues",
                                count: store.issues.count,
                                accent: Theme.green
                            )
                            ForEach(Array(store.issues.prefix(allTabPreviewLimit))) { issue in
                                IssueRow(issue: issue, isSelected: isEntrySelected("all-i-\(issue.id)"))
                                    .id("all-i-\(issue.id)")
                            }
                            if store.issues.count > allTabPreviewLimit, !isHidden(.issues) {
                                viewAllButton(destination: .issues, remaining: store.issues.count - allTabPreviewLimit)
                            }
                        }
                        if tab == .mine {
                            sectionDrivenList(tab: .mine, sourceRows: store.myPRs, showAuthor: true)
                        }
                        if tab == .review {
                            sectionDrivenList(tab: .review, sourceRows: store.reviewTabSourceRows, showAuthor: true)
                        }
                        if tab == .issues {
                            sectionDrivenIssues(tab: .issues, sourceRows: store.issues)
                        }
                        Color.clear.frame(height: 6)
                    }
                    .padding(.top, 2)
                }
                .onChange(of: selectedIndex) { _, new in
                    guard tab != .stats, !navigableItems.isEmpty else { return }
                    guard new >= 0, new < navigableItems.count else { return }
                    let id = navigableItems[new].id
                    withAnimation(.easeInOut(duration: 0.12)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
    }

    private func isEntrySelected(_ entryID: String) -> Bool {
        guard !navigableItems.isEmpty,
              selectedIndex >= 0,
              selectedIndex < navigableItems.count else { return false }
        return navigableItems[selectedIndex].id == entryID
    }

    @ViewBuilder
    private func sectionDrivenList(tab: PanelTab, sourceRows: [GHIssue], showAuthor: Bool) -> some View {
        let sections = renderedSections(for: tab, sourceRows: sourceRows)
        ForEach(sections) { sectionRows in
            sectionHeader(tab: tab, section: sectionRows.section, count: sectionRows.rows.count)
            if !sectionRows.section.collapsed {
                ForEach(sectionRows.rows) { row in
                    PRRow(
                        pr: row,
                        showAuthor: showAuthor,
                        reviewState: reviewState(for: row, section: sectionRows.section),
                        reviewIsViewer: sectionRows.section.targetsReviewedByMe,
                        metadata: store.prRowMetadata[row.id],
                        isSelected: isEntrySelected("sec-\(sectionRows.section.id.uuidString)-\(row.id)")
                    )
                    .id("sec-\(sectionRows.section.id.uuidString)-\(row.id)")
                }
            }
        }

        let unmatched = unmatchedRows(for: tab, sourceRows: sourceRows)
        if !unmatched.isEmpty {
            SectionHeader(
                icon: .circleDotDashed,
                title: "All",
                count: unmatched.count,
                accent: .secondary
            )
            ForEach(unmatched) { row in
                PRRow(
                    pr: row,
                    showAuthor: showAuthor,
                    reviewState: store.myPRReviewState[row.id],
                    metadata: store.prRowMetadata[row.id],
                    isSelected: isEntrySelected("all-\(tab.rawValue)-\(row.id)")
                )
                .id("all-\(tab.rawValue)-\(row.id)")
            }
        }
    }

    @ViewBuilder
    private func sectionDrivenIssues(tab: PanelTab, sourceRows: [GHIssue]) -> some View {
        let sections = renderedSections(for: tab, sourceRows: sourceRows)
        ForEach(sections) { sectionRows in
            sectionHeader(tab: tab, section: sectionRows.section, count: sectionRows.rows.count)
            if !sectionRows.section.collapsed {
                ForEach(sectionRows.rows) { row in
                    IssueRow(
                        issue: row,
                        isSelected: isEntrySelected("sec-\(sectionRows.section.id.uuidString)-\(row.id)")
                    )
                    .id("sec-\(sectionRows.section.id.uuidString)-\(row.id)")
                }
            }
        }

        let unmatched = unmatchedRows(for: tab, sourceRows: sourceRows)
        if !unmatched.isEmpty {
            SectionHeader(
                icon: .circleDotDashed,
                title: "All",
                count: unmatched.count,
                accent: .secondary
            )
            ForEach(unmatched) { row in
                IssueRow(
                    issue: row,
                    isSelected: isEntrySelected("all-\(tab.rawValue)-\(row.id)")
                )
                .id("all-\(tab.rawValue)-\(row.id)")
            }
        }
    }

    private func viewAllButton(destination: PanelTab, remaining: Int) -> some View {
        Button {
            switchToTab(destination)
        } label: {
            HStack(spacing: 6) {
                Text("View all \(destination.label.lowercased()) (\(remaining) more)")
                    .font(.system(size: 10.5, weight: .medium))
                Image(systemName: "arrow.right")
                    .font(.system(size: 9.5, weight: .semibold))
            }
            .foregroundStyle(Theme.blue)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .padding(.top, 2)
        .padding(.bottom, 4)
    }

    private func sectionHeader(tab: PanelTab, section: GitbarSection, count: Int) -> some View {
        HStack(spacing: 6) {
            if let icon = section.icon, !icon.isEmpty {
                Text(icon).font(.system(size: 12))
            }
            Text(section.name.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            if section.contributesToBadge {
                Text("\(count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Theme.surfaceHi(colorScheme), in: Capsule())
            }
            Spacer()
            Menu {
                ForEach(SortChoice.allCases, id: \.rawValue) { choice in
                    Button(choice.label) {
                        store.updateSectionSort(tab: tab, id: section.id, sort: choice)
                    }
                }
            } label: {
                Text(section.sort.label)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Theme.meta)
            }
            .menuStyle(.borderlessButton)
            Menu {
                Button("Edit…") {
                    withAnimation(.easeInOut(duration: 0.18)) { editorState = .edit(section) }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 18)
            Button {
                store.toggleSectionCollapsed(tab: tab, id: section.id)
            } label: {
                Image(systemName: section.collapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                avatar
                Text("@\(store.myLogin ?? "signed out")")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if store.isLoading {
                    ProgressView().controlSize(.small).frame(width: 14, height: 14)
                } else {
                    Button(action: {
                        store.refresh()
                        if tab == .stats {
                            Task { await store.loadStats(range: store.lastStatsRange) }
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Refresh (⌘R)")
                }
                legend("↑↓", "select")
                legend("↵", "open")
                legend("esc", "close")
            }
            HStack(alignment: .bottom, spacing: 12) {
                if updater.hasUpdate, let url = updater.releaseURL, let tag = updater.latestTag {
                    updateLink(tag: tag, url: url)
                } else if let version = updater.currentVersion {
                    Text("v\(version)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.faint)
                }
                Spacer(minLength: 8)
                Text("⌘1–5 tabs · ⌘, settings · ⌘R refresh · ⌘W close · ⌘Q quit")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Theme.faint)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private func legend(_ k: String, _ l: String) -> some View {
        HStack(spacing: 4) {
            Kbd(text: k)
            Text(l).font(.system(size: 10.5)).foregroundStyle(Theme.meta)
        }
    }

    private func updateLink(tag: String, url: URL) -> some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            HStack(spacing: 4) {
                Circle().fill(Theme.blue).frame(width: 4, height: 4)
                Text("Update \(tag)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.blue)
            }
        }
        .buttonStyle(.plain)
        .help("A new Gitbar release is available — open release notes")
    }

    private var avatar: some View {
        let initials = String((store.myLogin ?? "?").prefix(2)).uppercased()
        return Group {
            if let url = store.avatarURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        avatarPlaceholder(initials: initials)
                    case .empty:
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 20, height: 20)
                    @unknown default:
                        avatarPlaceholder(initials: initials)
                    }
                }
                .frame(width: 20, height: 20)
                .clipShape(Circle())
            } else {
                avatarPlaceholder(initials: initials)
            }
        }
    }

    private func avatarPlaceholder(initials: String) -> some View {
        Text(initials)
            .font(.system(size: 9.5, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(
                LinearGradient(
                    colors: [Theme.blue, Theme.lilac],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                in: Circle()
            )
    }

    private func count(for t: PanelTab) -> Int {
        switch t {
        case .all:    return store.myPRs.count + store.reviewRequests.count + store.issues.count
        case .mine:   return store.myPRs.count
        case .review: return store.reviewRequests.count
        case .issues: return store.issues.count
        case .stats:  return 0
        }
    }

    private var showMine:   Bool { tab == .all || tab == .mine }
    private var showReview: Bool { tab == .all || tab == .review }
    private var showIssues: Bool { tab == .all || tab == .issues }

    private var isEmpty: Bool {
        let customIssueRowCount = store.issuesBySectionId.values.reduce(0) { $0 + $1.count }
        return
            (tab == .all    && store.myPRs.isEmpty && store.reviewRequests.isEmpty && store.issues.isEmpty) ||
            (tab == .mine   && store.myPRs.isEmpty) ||
            (tab == .review && store.reviewRequests.isEmpty && store.reviewedByMePRs.isEmpty) ||
            (tab == .issues && store.issues.isEmpty && customIssueRowCount == 0)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 22))
                .foregroundStyle(Theme.faint)
            Text("Nothing here")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Text("You're all caught up.")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.meta)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func errorState(_ err: String) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 22))
                .foregroundStyle(Theme.amber)
            Text("Couldn't load")
                .font(.system(size: 13, weight: .semibold))
            Text(err)
                .font(.system(size: 11))
                .foregroundStyle(Theme.meta)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button("Retry", action: store.refresh)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

struct EmptyTokenState: View {
    let onOpenSettings: () -> Void
    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "key.horizontal")
                .font(.system(size: 26))
                .foregroundStyle(Theme.amber)
            Text("Add a GitHub token")
                .font(.system(size: 14, weight: .semibold))
            Text("Gitbar needs a personal access token to read PRs and issues.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Open settings", action: onOpenSettings)
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
