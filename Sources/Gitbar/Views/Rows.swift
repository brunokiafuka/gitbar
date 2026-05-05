import SwiftUI
import AppKit

// MARK: - CI pill (left column)

struct CIPill: View {
    let kind: CIPillKind

    var body: some View {
        let (icon, label, color): (String, String, Color) = {
            switch kind {
            case .fail: return ("xmark", "fail", Theme.red)
            case .pass: return ("checkmark", "pass", Theme.green)
            case .running: return ("arrow.triangle.2.circlepath", "running", Theme.amber)
            case .unknown: return ("minus", "—", Theme.slate)
            }
        }()

        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .bold))
                .symbolRenderingMode(.hierarchical)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 5)
        .frame(height: 16)
        .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: 4))
    }
}

struct StateChip: View {
    let systemImage: String
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage).font(.system(size: 8, weight: .bold))
            Text(label).font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 5)
        .frame(height: 16)
        .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - PR row

struct PRRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var store: Store
    let pr: GHIssue
    let showAuthor: Bool
    /// Latest review aggregate for your own PRs (`CHANGES_REQUESTED`, `APPROVED`, …).
    var reviewState: String? = nil
    /// When true, `reviewState` represents the viewer's own review (label as "you X").
    /// When false, it's an aggregate of reviews left on the PR by others.
    var reviewIsViewer: Bool = false
    /// CI, diff, merge conflict from REST; nil if still loading or request failed.
    var metadata: PRRowMetadata? = nil
    var isSelected: Bool = false
    @State private var hovered = false

    var body: some View {
        Button(action: openInBrowser) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let ci = metadata?.ci, ci != .unknown {
                        CIPill(kind: ci)
                    }
                    if pr.isDraft {
                        draftBadge
                    }
                    Text(pr.title)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                    Spacer(minLength: 4)
                    Text("#\(pr.number)")
                        .font(Theme.monoTiny)
                        .foregroundStyle(Theme.meta)
                }
                HStack(alignment: .center, spacing: 6) {
                    Text(pr.repoShort)
                        .font(Theme.monoTiny)
                        .foregroundStyle(.secondary)

                    if showAuthor {
                        Text("·").foregroundStyle(Theme.faint.opacity(0.9))
                        AssigneeChip(login: pr.user.login, avatarUrl: pr.user.avatarUrl)
                    }

                    if metadata?.hasMergeConflict == true {
                        Text("·").foregroundStyle(Theme.faint.opacity(0.9))
                        HStack(spacing: 3) {
                            LucideRepoIconView(icon: .gitMergeConflict, size: 11, color: Theme.amber)
                            Text("conflict")
                                .font(.system(size: 9.5, weight: .medium))
                        }
                        .foregroundStyle(Theme.amber)
                    }

                    if let m = metadata {
                        Text("·").foregroundStyle(Theme.faint.opacity(0.9))
                        HStack(spacing: 4) {
                            Text("+\(m.additions)")
                                .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                                .foregroundStyle(Theme.green)
                            Text("-\(m.deletions)")
                                .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                                .foregroundStyle(Color(red: 0.92, green: 0.35, blue: 0.45))
                        }
                    }

                    if pr.comments > 0 {
                        Text("·").foregroundStyle(Theme.faint.opacity(0.9))
                        HStack(spacing: 3) {
                            LucideRepoIconView(icon: .messageSquareDiff, size: 11, color: .secondary)
                            Text("\(pr.comments)").font(.system(size: 9.5))
                        }
                        .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 4)

                    Text(RelativeTime.short(pr.updated))
                        .font(.system(size: 9.5))
                        .foregroundStyle(Theme.meta)
                }
                if let pill = reviewPillConfig {
                    reviewPill(pill)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(rowBackground, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Theme.blue.opacity(isSelected ? 0.55 : 0), lineWidth: isSelected ? 1.25 : 0)
            )
            .opacity(pr.isDraft ? 0.85 : 1)
            .padding(.horizontal, 6)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .background(RightAnchoredContextMenuPresenter(makeMenu: makeContextMenu))
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(ActionMenuItem(title: "Open in GitHub", systemImage: "arrow.up.right.square") {
            openInBrowser()
        })
        if store.aiReviewers.any {
            menu.addItem(.separator())
            if store.aiReviewers.claude {
                menu.addItem(ActionMenuItem(title: "Review with Claude", systemImage: "terminal") {
                    AIReviewLauncher.review(pr: pr, with: .claude)
                })
            }
            if store.aiReviewers.codex {
                menu.addItem(ActionMenuItem(title: "Review with Codex", systemImage: "terminal") {
                    AIReviewLauncher.review(pr: pr, with: .codex)
                })
            }
        }
        return menu
    }

    private var draftBadge: some View {
        HStack(spacing: 4) {
            LucideRepoIconView(icon: .gitPullRequestDraft, size: 11, color: Theme.slate)
            Text("draft")
                .font(.system(size: 9, weight: .bold))
        }
        .foregroundStyle(Theme.slate)
        .padding(.horizontal, 5)
        .frame(height: 14)
        .background(Theme.slate.opacity(0.14), in: RoundedRectangle(cornerRadius: 4))
    }

    /// Shared per-state style for the review pill rendered on the third row.
    private struct ReviewPillConfig {
        let label: String
        let color: Color
        let icon: LucideRepoIcon
    }

    /// Pill config for the current review state. On viewer-review rows (Review tab)
    /// we label what the viewer left, or render nothing if they haven't reviewed.
    /// On aggregate rows (Mine tab) we render the PR's latest review outcome, including
    /// a "pending" fallback when no review has been submitted yet.
    private var reviewPillConfig: ReviewPillConfig? {
        if reviewIsViewer {
            switch reviewState {
            case "APPROVED": return .init(label: "you approved", color: Theme.green, icon: .circleCheck)
            case "CHANGES_REQUESTED": return .init(label: "you requested changes", color: Theme.red, icon: .alertOctagon)
            case "COMMENTED": return .init(label: "you commented", color: Theme.amber, icon: .messageSquare)
            default: return nil
            }
        } else {
            switch reviewState {
            case "APPROVED": return .init(label: "approved", color: Theme.green, icon: .circleCheck)
            case "CHANGES_REQUESTED": return .init(label: "changes requested", color: Theme.red, icon: .alertOctagon)
            case "COMMENTED": return .init(label: "commented", color: Theme.amber, icon: .messageSquare)
            default: return .init(label: "pending", color: Theme.slate, icon: .circleDotDashed)
            }
        }
    }

    @ViewBuilder
    private func reviewPill(_ config: ReviewPillConfig) -> some View {
        HStack(spacing: 4) {
            LucideRepoIconView(icon: config.icon, size: 10, color: config.color)
            Text(config.label)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(config.color)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(config.color.opacity(0.14), in: Capsule(style: .continuous))
    }

    private var rowBackground: Color {
        (hovered || isSelected) ? Theme.surfaceHi(colorScheme) : .clear
    }

    private func openInBrowser() {
        if let u = URL(string: pr.htmlUrl) { NSWorkspace.shared.open(u) }
    }
}

private struct RightAnchoredContextMenuPresenter: NSViewRepresentable {
    let makeMenu: () -> NSMenu

    func makeNSView(context: Context) -> RightAnchoredContextMenuView {
        let view = RightAnchoredContextMenuView()
        view.makeMenu = makeMenu
        return view
    }

    func updateNSView(_ nsView: RightAnchoredContextMenuView, context: Context) {
        nsView.makeMenu = makeMenu
    }
}

private final class RightAnchoredContextMenuView: NSView {
    var makeMenu: (() -> NSMenu)?
    private var rightClickMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshMonitor()
    }

    deinit {
        if let rightClickMonitor {
            NSEvent.removeMonitor(rightClickMonitor)
        }
    }

    private func refreshMonitor() {
        if let rightClickMonitor {
            NSEvent.removeMonitor(rightClickMonitor)
            self.rightClickMonitor = nil
        }

        guard window != nil else { return }
        rightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown]) { [weak self] event in
            guard let self, let window = self.window, event.window === window else { return event }

            let point = self.convert(event.locationInWindow, from: nil)
            guard self.bounds.contains(point) else { return event }

            self.showMenu()
            return nil
        }
    }

    private func showMenu() {
        guard let menu = makeMenu?(), !menu.items.isEmpty else { return }
        let anchor = NSPoint(x: bounds.maxX - 1, y: bounds.maxY)
        menu.popUp(positioning: nil, at: anchor, in: self)
    }
}

private final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, systemImage: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
        image = NSImage(systemSymbolName: systemImage, accessibilityDescription: title)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func run() {
        handler()
    }
}

// MARK: - Issue row

struct IssueRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let issue: GHIssue
    var isSelected: Bool = false
    @State private var hovered = false

    var body: some View {
        Button(action: openInBrowser) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(issue.title)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                    Spacer(minLength: 4)
                    Text("#\(issue.number)")
                        .font(Theme.monoTiny)
                        .foregroundStyle(Theme.meta)
                }
                FlowLayout(spacing: 6, rowSpacing: 4) {
                    Text(issue.repoShort)
                        .font(Theme.monoTiny)
                        .foregroundStyle(.secondary)

                    let assignees = issue.assignees ?? []
                    dotSeparator
                    if let first = assignees.first {
                        if assignees.count > 1 {
                            HStack(spacing: 4) {
                                AssigneeChip(login: first.login, avatarUrl: first.avatarUrl)
                                OverflowPill(count: assignees.count - 1)
                            }
                            .tooltip(assignees.map { "@\($0.login)" }.joined(separator: ", "))
                        } else {
                            AssigneeChip(login: first.login, avatarUrl: first.avatarUrl)
                        }
                    } else {
                        UnassignedChip()
                    }

                    if !issue.labels.isEmpty {
                        dotSeparator
                        ForEach(issue.labels.prefix(2)) { label in
                            LabelPill(label: label)
                        }
                        if issue.labels.count > 2 {
                            OverflowPill(count: issue.labels.count - 2)
                        }
                    }

                    if issue.comments > 0 {
                        dotSeparator
                        HStack(spacing: 3) {
                            LucideRepoIconView(icon: .messageSquareDiff, size: 11, color: .secondary)
                            Text("\(issue.comments)").font(.system(size: 9.5))
                        }
                        .foregroundStyle(.secondary)
                    }

                    dotSeparator
                    Text(RelativeTime.short(issue.updated))
                        .font(.system(size: 9.5))
                        .foregroundStyle(Theme.meta)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(rowBackground, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Theme.blue.opacity(isSelected ? 0.55 : 0), lineWidth: isSelected ? 1.25 : 0)
            )
            .padding(.horizontal, 6)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }

    private var rowBackground: Color {
        (hovered || isSelected) ? Theme.surfaceHi(colorScheme) : .clear
    }

    private var dotSeparator: some View {
        Text("·").foregroundStyle(Theme.faint.opacity(0.9))
    }

    private func openInBrowser() {
        if let u = URL(string: issue.htmlUrl) { NSWorkspace.shared.open(u) }
    }
}
