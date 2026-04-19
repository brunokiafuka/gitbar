import AppKit
import SwiftUI

// MARK: - Lucide `git-graph` (24×24 viewBox, stroke-only — matches lucide.dev)

/// Vector icon for the **menu bar** status item (not the in-panel tabs).
struct LucideGitGraphIcon: View {
    var size: CGFloat = 16

    var body: some View {
        LucideGitGraphShape()
            .stroke(style: StrokeStyle(lineWidth: size * (2 / 24), lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
    }
}

private struct LucideGitGraphShape: Shape {
    func path(in rect: CGRect) -> Path {
        let sc = min(rect.width, rect.height) / 24
        let ox = rect.midX - 12 * sc
        let oy = rect.midY - 12 * sc
        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: ox + x * sc, y: oy + y * sc)
        }

        var p = Path()

        p.addEllipse(in: CGRect(x: ox + 2 * sc, y: oy + 3 * sc, width: 6 * sc, height: 6 * sc))

        p.move(to: P(5, 9))
        p.addLine(to: P(5, 15))

        p.addEllipse(in: CGRect(x: ox + 2 * sc, y: oy + 15 * sc, width: 6 * sc, height: 6 * sc))

        p.move(to: P(12, 3))
        p.addLine(to: P(12, 21))

        p.addEllipse(in: CGRect(x: ox + 16 * sc, y: oy + 3 * sc, width: 6 * sc, height: 6 * sc))

        let c = P(10, 9)
        let r = 9 * sc
        let a1 = atan2(CGFloat(15.7 - 9), CGFloat(16 - 10))
        let a2 = atan2(CGFloat(0), CGFloat(19 - 10))
        p.move(to: P(16, 15.7))
        p.addArc(center: c, radius: r, startAngle: .radians(a1), endAngle: .radians(a2), clockwise: true)

        return p
    }
}

// MARK: - NSStatusItem image

enum GitbarMenuBarIcon {
    /// Template image for `NSStatusItem` — single color, adapts to light/dark menu bar.
    @MainActor
    static func gitGraphTemplate(pointSize: CGFloat = 13) -> NSImage {
        let view = LucideGitGraphIcon(size: pointSize)
            .foregroundStyle(Color.black)
            .frame(width: pointSize, height: pointSize)
            .drawingGroup()

        let renderer = ImageRenderer(content: view)
        renderer.scale = max(2.0, NSScreen.main?.backingScaleFactor ?? 2.0)
        renderer.proposedSize = ProposedViewSize(width: pointSize, height: pointSize)

        if let ns = renderer.nsImage {
            ns.isTemplate = true
            return ns
        }
        if let cg = renderer.cgImage {
            let img = NSImage(cgImage: cg, size: NSSize(width: pointSize, height: pointSize))
            img.isTemplate = true
            return img
        }

        let fallback = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: "Gitbar")!
        fallback.isTemplate = true
        return fallback
    }
}
