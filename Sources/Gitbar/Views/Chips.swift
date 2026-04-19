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
