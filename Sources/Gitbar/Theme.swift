import SwiftUI
import AppKit

struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .menu
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blendingMode
        v.state = .active
        v.isEmphasized = true
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

enum Theme {
    static let green = Color(nsColor: .systemGreen)
    static let red   = Color(nsColor: .systemRed)
    static let amber = Color(nsColor: .systemOrange)
    static let blue  = Color(nsColor: .systemBlue)
    static let lilac = Color(nsColor: .systemIndigo)
    static let slate = Color(nsColor: .systemGray)
    /// Highlight for “current” activity bar (mint on dark UI).
    static let mint = Color(red: 0.45, green: 0.92, blue: 0.78)

    /// Metadata and secondary lines — system secondary label reads better than SwiftUI `.tertiary` on dark charcoal.
    static let meta = Color(nsColor: .secondaryLabelColor)
    /// Least prominent text (hints, legends); still uses `tertiaryLabelColor` for proper contrast.
    static let faint = Color(nsColor: .tertiaryLabelColor)

    static func surface(_ scheme: ColorScheme) -> Color {
        switch scheme {
        case .dark: return Color.white.opacity(0.04)
        case .light: return Color.black.opacity(0.042)
        @unknown default: return Color.black.opacity(0.042)
        }
    }

    static func surfaceHi(_ scheme: ColorScheme) -> Color {
        switch scheme {
        case .dark: return Color.white.opacity(0.085)
        case .light: return Color.black.opacity(0.085)
        @unknown default: return Color.black.opacity(0.085)
        }
    }

    static func hairline(_ scheme: ColorScheme) -> Color {
        switch scheme {
        case .dark: return Color.white.opacity(0.12)
        case .light: return Color.black.opacity(0.08)
        @unknown default: return Color.black.opacity(0.08)
        }
    }

    static func glyphFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.08)
    }

    /// Inactive bar segments / streak dots (replaces `Color.primary.opacity` so dark panels don’t wash out).
    static func barInactive(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.18)
    }

    static let mono     = Font.system(.caption, design: .monospaced)
    static let monoTiny = Font.system(size: 10.5, design: .monospaced)
}
