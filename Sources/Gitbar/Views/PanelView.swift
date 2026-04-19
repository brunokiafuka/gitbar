import SwiftUI
import AppKit

enum PanelTab: String, CaseIterable, Identifiable {
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
}

private enum PanelListEntry: Identifiable, Hashable {
    case mine(GHIssue)
    case review(GHIssue)
    case issue(GHIssue)

    var id: String {
        switch self {
        case .mine(let i): return "m-\(i.id)"
        case .review(let i): return "r-\(i.id)"
        case .issue(let i): return "i-\(i.id)"
        }
    }

    var htmlURL: String {
        switch self {
        case .mine(let i), .review(let i), .issue(let i):
            return i.htmlUrl
        }
    }
}

struct PanelView: View {
    @EnvironmentObject var store: Store
    @Environment(\.colorScheme) private var colorScheme
    @State private var tab: PanelTab = .all
    @State private var selectedIndex: Int = 0
    @FocusState private var listKeyboardFocused: Bool

    let onOpenSettings: () -> Void

    var body: some View {
        panelChrome
            .frame(width: 440, height: 580)
            .background(panelBackdrop)
            .focusable()
            .focused($listKeyboardFocused)
            .focusEffectDisabled()
            .onAppear {
                if store.hasToken { store.refresh() }
                listKeyboardFocused = true
                store.isStatsTabActive = (tab == .stats)
            }
            .onChange(of: tab) { _, new in
                store.isStatsTabActive = (new == .stats)
                selectedIndex = 0
                clampSelection()
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
            tabBar
                .animation(.easeInOut(duration: 0.16), value: tab)
            panelDivider
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(tab)
                .transition(.opacity)
            panelDivider
            footer
        }
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
        "\(tab.rawValue)|\(store.myPRs.map(\.id))|\(store.reviewRequests.map(\.id))|\(store.issues.map(\.id))"
    }

    private var navigableItems: [PanelListEntry] {
        switch tab {
        case .stats:
            return []
        case .all:
            var rows: [PanelListEntry] = []
            rows.append(contentsOf: store.myPRs.map { .mine($0) })
            rows.append(contentsOf: store.reviewRequests.map { .review($0) })
            rows.append(contentsOf: store.issues.map { .issue($0) })
            return rows
        case .mine:
            return store.myPRs.map { .mine($0) }
        case .review:
            return store.reviewRequests.map { .review($0) }
        case .issues:
            return store.issues.map { .issue($0) }
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
        let all = PanelTab.allCases
        guard let i = all.firstIndex(of: tab) else { return }
        let n = all.count
        let next = ((i + delta) % n + n) % n
        switchToTab(all[next])
    }

    private func selectTabKeyboard(_ t: PanelTab) -> KeyPress.Result {
        switchToTab(t)
        return .handled
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
            ForEach(PanelTab.allCases) { t in
                tabButton(t)
            }
            Spacer(minLength: 4)
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
        if tab == .stats {
            StatsView()
        } else if !store.hasToken {
            EmptyTokenState(onOpenSettings: onOpenSettings)
        } else if let err = store.errorMessage,
                  store.myPRs.isEmpty,
                  store.reviewRequests.isEmpty,
                  store.issues.isEmpty {
            errorState(err)
        } else if isEmpty {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if showMine, !store.myPRs.isEmpty {
                            SectionHeader(
                                icon: .gitPullRequest,
                                title: "My pull requests",
                                count: store.myPRs.count,
                                accent: .secondary
                            )
                            ForEach(store.myPRs) { pr in
                                PRRow(
                                    pr: pr,
                                    showAuthor: false,
                                    reviewState: store.myPRReviewState[pr.id],
                                    metadata: store.prRowMetadata[pr.id],
                                    isSelected: isEntrySelected(.mine(pr))
                                )
                                .id(PanelListEntry.mine(pr).id)
                            }
                        }
                        if showReview, !store.reviewRequests.isEmpty {
                            SectionHeader(
                                icon: .circleDotDashed,
                                title: "Awaiting your review",
                                count: store.reviewRequests.count,
                                accent: Theme.amber
                            )
                            ForEach(store.reviewRequests) { pr in
                                PRRow(
                                    pr: pr,
                                    showAuthor: true,
                                    metadata: store.prRowMetadata[pr.id],
                                    isSelected: isEntrySelected(.review(pr))
                                )
                                .id(PanelListEntry.review(pr).id)
                            }
                        }
                        if showIssues, !store.issues.isEmpty {
                            SectionHeader(
                                icon: .circleDot,
                                title: "Assigned issues",
                                count: store.issues.count,
                                accent: Theme.green
                            )
                            ForEach(store.issues) { issue in
                                IssueRow(issue: issue, isSelected: isEntrySelected(.issue(issue)))
                                    .id(PanelListEntry.issue(issue).id)
                            }
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

    private func isEntrySelected(_ entry: PanelListEntry) -> Bool {
        guard !navigableItems.isEmpty,
              selectedIndex >= 0,
              selectedIndex < navigableItems.count else { return false }
        return navigableItems[selectedIndex].id == entry.id
    }

    private var footer: some View {
        VStack(alignment: .trailing, spacing: 4) {
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
            Text("⌘1–5 tabs · ⌘, settings · ⌘R refresh · ⌘W close · ⌘Q quit")
                .font(.system(size: 9.5))
                .foregroundStyle(Theme.faint)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
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
        (tab == .all    && store.myPRs.isEmpty && store.reviewRequests.isEmpty && store.issues.isEmpty) ||
        (tab == .mine   && store.myPRs.isEmpty) ||
        (tab == .review && store.reviewRequests.isEmpty) ||
        (tab == .issues && store.issues.isEmpty)
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
