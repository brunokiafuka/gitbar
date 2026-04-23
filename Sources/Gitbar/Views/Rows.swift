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
    @EnvironmentObject var store: Store
    @Environment(\.colorScheme) private var colorScheme
    let pr: GHIssue
    let showAuthor: Bool
    /// Latest review aggregate for your own PRs (`CHANGES_REQUESTED`, `APPROVED`, …).
    var reviewState: String? = nil
    /// CI, diff, merge conflict from REST; nil if still loading or request failed.
    var metadata: PRRowMetadata? = nil
    var isSelected: Bool = false
    @State private var hovered = false
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
                            Text("@\(pr.user.login)")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }

                        if !showAuthor {
                            Text("·").foregroundStyle(Theme.faint.opacity(0.9))
                            reviewStatusView
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
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                        Text("Details")
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, expanded ? 6 : 8)

            if expanded {
                Divider()
                    .overlay(Theme.hairline(colorScheme))
                    .padding(.horizontal, 10)
                actionRow
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            }
        }
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.blue.opacity(isSelected ? 0.55 : 0), lineWidth: isSelected ? 1.25 : 0)
        )
        .opacity(pr.isDraft ? 0.85 : 1)
        .padding(.horizontal, 6)
        .onHover { hovered = $0 }
    }

    @ViewBuilder
    private var actionRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button("Open in GitHub", action: openInBrowser)
                    .buttonStyle(.borderless)

                if pr.isDraft {
                    Button {
                        Task { await store.markReady(pr: pr) }
                    } label: {
                        if store.isPRActionInFlight(.markReady, for: pr) {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 14, height: 14)
                        } else {
                            Text("Mark Ready")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(store.isPRActionInFlight(.markReady, for: pr))
                } else if canShowMergeButton {
                    Button {
                        Task { await store.merge(pr: pr) }
                    } label: {
                        if store.isPRActionInFlight(.merge, for: pr) {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 14, height: 14)
                        } else {
                            Text("Merge")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(store.isPRActionInFlight(.merge, for: pr) || !canMerge)
                }
                Spacer(minLength: 0)
            }

            if let error = store.prActionError(.markReady, for: pr) ?? store.prActionError(.merge, for: pr) {
                Text(error)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.red)
                    .lineLimit(2)
            } else if !pr.isDraft, !canMerge, let reason = mergeDisabledReason {
                Text(reason)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.meta)
                    .lineLimit(2)
            }
        }
    }

    private var canMerge: Bool {
        guard !pr.isDraft else { return false }
        guard let state = metadata?.mergeableState else { return false }
        return state == "clean" || state == "has_hooks"
    }

    private var canShowMergeButton: Bool {
        guard !pr.isDraft else { return false }
        return metadata?.canUserMerge != false
    }

    private var mergeDisabledReason: String? {
        guard !pr.isDraft else { return nil }
        switch metadata?.mergeableState {
        case "blocked":
            return "Merge blocked by required checks, reviews, or branch rules."
        case "dirty":
            return "Merge unavailable due to merge conflicts."
        case "behind":
            return "Branch is behind base; update this PR before merging."
        case "unstable":
            return "Required checks are failing or pending."
        case "draft":
            return "Draft pull requests cannot be merged."
        case "unknown", nil:
            return "Mergeability is still being calculated by GitHub."
        default:
            return "Merge is currently unavailable for this pull request."
        }
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

    @ViewBuilder
    private var reviewStatusView: some View {
        HStack(spacing: 4) {
            if reviewState == "APPROVED" || reviewState == "CHANGES_REQUESTED" {
                Circle()
                    .fill(reviewDotColor)
                    .frame(width: 6, height: 6)
            } else {
                LucideRepoIconView(icon: .circleDotDashed, size: 11, color: reviewLineColor)
            }
            Text(reviewLineLabel)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(reviewLineColor)
        }
    }

    private var reviewLineLabel: String {
        switch reviewState {
        case "APPROVED": return "approved"
        case "CHANGES_REQUESTED": return "changes"
        default: return "pending"
        }
    }

    private var reviewLineColor: Color {
        switch reviewState {
        case "APPROVED": return Theme.green
        case "CHANGES_REQUESTED": return Theme.red
        default: return Theme.slate
        }
    }

    private var reviewDotColor: Color {
        reviewLineColor
    }

    private var rowBackground: Color {
        (hovered || isSelected) ? Theme.surfaceHi(colorScheme) : .clear
    }

    private func openInBrowser() {
        if let u = URL(string: pr.htmlUrl) { NSWorkspace.shared.open(u) }
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
                HStack(spacing: 6) {
                    Text(issue.repoShort)
                        .font(Theme.monoTiny)
                        .foregroundStyle(.secondary)
                    Text("·").foregroundStyle(Theme.faint.opacity(0.9))
                    ForEach(issue.labels.prefix(3)) { label in
                        LabelPill(label: label)
                    }
                    Spacer()
                    if issue.comments > 0 {
                        HStack(spacing: 3) {
                            LucideRepoIconView(icon: .messageSquareDiff, size: 11, color: .secondary)
                            Text("\(issue.comments)").font(.system(size: 9.5))
                        }
                        .foregroundStyle(.secondary)
                    }
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

    private func openInBrowser() {
        if let u = URL(string: issue.htmlUrl) { NSWorkspace.shared.open(u) }
    }
}
