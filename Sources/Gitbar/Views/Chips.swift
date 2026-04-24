import SwiftUI

enum PRStatus {
    case draft, needsReview, approved, changesRequested, merged

    var label: String {
        switch self {
        case .draft: return "draft"
        case .needsReview: return "needs review"
        case .approved: return "approved"
        case .changesRequested: return "changes"
        case .merged: return "merged"
        }
    }

    var color: Color {
        switch self {
        case .draft: return Theme.slate
        case .needsReview: return Theme.amber
        case .approved: return Theme.green
        case .changesRequested: return Theme.red
        case .merged: return Theme.lilac
        }
    }
}

struct PRStatusChip: View {
    let status: PRStatus
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(status.color).frame(width: 6, height: 6)
            Text(status.label)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(status.color)
    }
}

struct AssigneeChip: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var store: Store
    let login: String

    private var displayText: String {
        if let me = store.myLogin, login.caseInsensitiveCompare(me) == .orderedSame {
            return "@me"
        }
        return "@\(login)"
    }

    var body: some View {
        Text(displayText)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Theme.surfaceHi(colorScheme), in: RoundedRectangle(cornerRadius: 4))
    }
}

struct OverflowPill: View {
    @Environment(\.colorScheme) private var colorScheme
    let count: Int

    var body: some View {
        Text("+\(count)")
            .font(.system(size: 10, weight: .semibold).monospacedDigit())
            .foregroundStyle(Theme.meta)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Theme.surfaceHi(colorScheme).opacity(0.7), in: RoundedRectangle(cornerRadius: 4))
    }
}

struct UnassignedChip: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "person.crop.circle.dashed")
                .font(.system(size: 9, weight: .semibold))
            Text("unassigned")
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(Theme.amber)
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background(Theme.amber.opacity(0.14), in: RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Theme.amber.opacity(0.35), style: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
        )
    }
}

/// Wraps children onto multiple lines when they don't fit in one row. macOS 13+.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var rowSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = rows(maxWidth: maxWidth, subviews: subviews)
        let totalHeight = rows.reduce(0) { $0 + $1.height } + max(0, CGFloat(rows.count - 1)) * rowSpacing
        let usedWidth = rows.map(\.width).max() ?? 0
        return CGSize(width: min(usedWidth, maxWidth.isFinite ? maxWidth : usedWidth), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = rows(maxWidth: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y + (row.height - item.size.height) / 2),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + spacing
            }
            y += row.height + rowSpacing
        }
    }

    private struct RowItem { let index: Int; let size: CGSize }
    private struct Row { var items: [RowItem]; var height: CGFloat; var width: CGFloat }

    private func rows(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var out: [Row] = []
        var current = Row(items: [], height: 0, width: 0)
        for (i, sub) in subviews.enumerated() {
            let size = sub.sizeThatFits(.unspecified)
            let projected = current.items.isEmpty ? size.width : current.width + spacing + size.width
            if !current.items.isEmpty, projected > maxWidth {
                out.append(current)
                current = Row(items: [RowItem(index: i, size: size)], height: size.height, width: size.width)
            } else {
                current.items.append(RowItem(index: i, size: size))
                current.height = max(current.height, size.height)
                current.width = projected
            }
        }
        if !current.items.isEmpty { out.append(current) }
        return out
    }
}

struct LabelPill: View {
    @Environment(\.colorScheme) private var colorScheme
    let label: GHLabel

    var body: some View {
        Text(label.name.lowercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(fg)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(bg, in: RoundedRectangle(cornerRadius: 4))
    }

    private var tuple: (Color, Color) {
        switch label.name.lowercased() {
        case "p0":
            return (Theme.red, Theme.red.opacity(0.16))
        case "bug":
            return (Theme.red.opacity(0.85), Theme.red.opacity(0.12))
        case "enhancement":
            return (Theme.lilac, Theme.lilac.opacity(0.16))
        default:
            return hexLabel(label.color)
        }
    }

    private var fg: Color { tuple.0 }
    private var bg: Color { tuple.1 }

    private func hexLabel(_ hex: String) -> (Color, Color) {
        guard hex.count == 6, let v = UInt32(hex, radix: 16) else {
            return (.secondary, Theme.surfaceHi(colorScheme))
        }
        let r = Double((v >> 16) & 0xff) / 255
        let g = Double((v >> 8) & 0xff) / 255
        let b = Double(v & 0xff) / 255
        let base = Color(red: r, green: g, blue: b)
        return (base, base.opacity(0.18))
    }
}

struct SectionHeader: View {
    @Environment(\.colorScheme) private var colorScheme
    let icon: LucideRepoIcon
    let title: String
    let count: Int
    let accent: Color

    var body: some View {
        HStack(spacing: 6) {
            LucideRepoIconView(icon: icon, size: 13, color: accent)
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            Text("\(count)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Theme.surfaceHi(colorScheme), in: Capsule())
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }
}

struct Kbd: View {
    @Environment(\.colorScheme) private var colorScheme
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 3)
            .frame(minWidth: 15, minHeight: 15)
            .background(Theme.surfaceHi(colorScheme), in: RoundedRectangle(cornerRadius: 3))
    }
}
