import SwiftUI

// MARK: - Lucide icons (github.dev naming) — 24×24, stroke 2

/// Icons from [Lucide](https://lucide.dev/icons/) — stroke-only, matches `stroke-width="2"` at 24px.
enum LucideRepoIcon: Hashable, Sendable {
    case gitMergeConflict
    case gitPullRequest
    case gitPullRequestClosed
    case gitPullRequestDraft
    case circleDotDashed
    case circleDot
    case messageSquareDiff
    /// Stats / KPIs
    case circleCheck
    case eye
    case gitCommitHorizontal
    case timer
    case flame
    case alertOctagon
    case messageSquare
}

struct LucideRepoIconView: View {
    let icon: LucideRepoIcon
    var size: CGFloat = 14
    var color: Color = .primary

    private var strokeWidth: CGFloat { size * (2 / 24) }

    private var strokeStyle: StrokeStyle {
        StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round)
    }

    var body: some View {
        Group {
            switch icon {
            case .circleDotDashed:
                ZStack {
                    Circle()
                        .stroke(
                            color,
                            style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round, dash: [strokeWidth * 2.2, strokeWidth * 1.8])
                        )
                        .frame(width: size * 20 / 24, height: size * 20 / 24)
                    Circle()
                        .stroke(color, lineWidth: strokeWidth)
                        .frame(width: size * 2 / 24, height: size * 2 / 24)
                }
            case .gitMergeConflict:
                LucideGitMergeConflictShape().stroke(style: strokeStyle).foregroundStyle(color)
            case .gitPullRequest:
                LucideGitPullRequestShape().stroke(style: strokeStyle).foregroundStyle(color)
            case .gitPullRequestClosed:
                LucideGitPullRequestClosedShape().stroke(style: strokeStyle).foregroundStyle(color)
            case .gitPullRequestDraft:
                LucideGitPullRequestDraftShape().stroke(style: strokeStyle).foregroundStyle(color)
            case .circleDot:
                LucideCircleDotShape().stroke(style: strokeStyle).foregroundStyle(color)
            case .messageSquareDiff:
                LucideMessageSquareDiffShape().stroke(style: strokeStyle).foregroundStyle(color)
            case .circleCheck:
                LucideCircleCheckShape().stroke(style: strokeStyle).foregroundStyle(color)
            case .eye:
                LucideEyeShape().stroke(style: strokeStyle).foregroundStyle(color)
            case .gitCommitHorizontal:
                LucideGitCommitHorizontalShape().stroke(style: strokeStyle).foregroundStyle(color)
            case .timer:
                LucideTimerShape().stroke(style: strokeStyle).foregroundStyle(color)
            case .flame:
                LucideFlameShape().stroke(style: strokeStyle).foregroundStyle(color)
            case .alertOctagon:
                LucideAlertOctagonShape().stroke(style: strokeStyle).foregroundStyle(color)
            case .messageSquare:
                LucideMessageSquareShape().stroke(style: strokeStyle).foregroundStyle(color)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Shapes (viewBox 0…24)

private struct LucideGitMergeConflictShape: Shape {
    func path(in rect: CGRect) -> Path {
        let P = { LucideGithubPath.P($0, $1, rect) }
        var p = Path()
        p.move(to: P(12, 6))
        p.addLine(to: P(16, 6))
        p.addLine(to: P(18, 8))
        p.addLine(to: P(18, 15))
        p.move(to: P(6, 12))
        p.addLine(to: P(6, 21))
        p.move(to: P(9, 3))
        p.addLine(to: P(3, 9))
        p.move(to: P(9, 9))
        p.addLine(to: P(3, 3))
        p.addEllipse(in: LucideGithubPath.ellipse(cx: 18, cy: 18, r: 3, rect: rect))
        return p
    }
}

private struct LucideGitPullRequestShape: Shape {
    func path(in rect: CGRect) -> Path {
        let P = { LucideGithubPath.P($0, $1, rect) }
        var p = Path()
        p.addEllipse(in: LucideGithubPath.ellipse(cx: 18, cy: 18, r: 3, rect: rect))
        p.addEllipse(in: LucideGithubPath.ellipse(cx: 6, cy: 6, r: 3, rect: rect))
        p.move(to: P(13, 6))
        p.addLine(to: P(16, 6))
        p.addLine(to: P(18, 8))
        p.addLine(to: P(18, 15))
        p.move(to: P(6, 9))
        p.addLine(to: P(6, 21))
        return p
    }
}

private struct LucideGitPullRequestClosedShape: Shape {
    func path(in rect: CGRect) -> Path {
        let P = { LucideGithubPath.P($0, $1, rect) }
        var p = Path()
        p.addEllipse(in: LucideGithubPath.ellipse(cx: 6, cy: 6, r: 3, rect: rect))
        p.move(to: P(6, 9))
        p.addLine(to: P(6, 21))
        p.move(to: P(21, 3))
        p.addLine(to: P(15, 9))
        p.move(to: P(21, 9))
        p.addLine(to: P(15, 3))
        p.move(to: P(18, 11.5))
        p.addLine(to: P(18, 15))
        p.addEllipse(in: LucideGithubPath.ellipse(cx: 18, cy: 18, r: 3, rect: rect))
        return p
    }
}

private struct LucideGitPullRequestDraftShape: Shape {
    func path(in rect: CGRect) -> Path {
        let P = { LucideGithubPath.P($0, $1, rect) }
        var p = Path()
        p.addEllipse(in: LucideGithubPath.ellipse(cx: 18, cy: 18, r: 3, rect: rect))
        p.addEllipse(in: LucideGithubPath.ellipse(cx: 6, cy: 6, r: 3, rect: rect))
        p.move(to: P(18, 6))
        p.addLine(to: P(18, 5))
        p.move(to: P(18, 11))
        p.addLine(to: P(18, 10))
        p.move(to: P(6, 9))
        p.addLine(to: P(6, 21))
        return p
    }
}

private struct LucideCircleDotShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addEllipse(in: LucideGithubPath.ellipse(cx: 12, cy: 12, r: 10, rect: rect))
        p.addEllipse(in: LucideGithubPath.ellipse(cx: 12, cy: 12, r: 1, rect: rect))
        return p
    }
}

private struct LucideCircleCheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        let P = { LucideGithubPath.P($0, $1, rect) }
        var p = Path()
        p.addEllipse(in: LucideGithubPath.ellipse(cx: 12, cy: 12, r: 10, rect: rect))
        p.move(to: P(9, 12))
        p.addLine(to: P(11, 14))
        p.addLine(to: P(15, 10))
        return p
    }
}

private struct LucideEyeShape: Shape {
    func path(in rect: CGRect) -> Path {
        let P = { LucideGithubPath.P($0, $1, rect) }
        var p = Path()
        p.move(to: P(2, 12))
        p.addCurve(to: P(22, 12), control1: P(8, 4), control2: P(16, 4))
        p.addCurve(to: P(2, 12), control1: P(16, 20), control2: P(8, 20))
        p.addEllipse(in: LucideGithubPath.ellipse(cx: 12, cy: 12, r: 3, rect: rect))
        return p
    }
}

private struct LucideGitCommitHorizontalShape: Shape {
    func path(in rect: CGRect) -> Path {
        let P = { LucideGithubPath.P($0, $1, rect) }
        var p = Path()
        p.addEllipse(in: LucideGithubPath.ellipse(cx: 12, cy: 12, r: 3, rect: rect))
        p.move(to: P(3, 12))
        p.addLine(to: P(9, 12))
        p.move(to: P(15, 12))
        p.addLine(to: P(21, 12))
        return p
    }
}

private struct LucideTimerShape: Shape {
    func path(in rect: CGRect) -> Path {
        let P = { LucideGithubPath.P($0, $1, rect) }
        var p = Path()
        p.move(to: P(10, 2))
        p.addLine(to: P(14, 2))
        p.move(to: P(12, 14))
        p.addLine(to: P(15, 11))
        p.addEllipse(in: LucideGithubPath.ellipse(cx: 12, cy: 14, r: 8, rect: rect))
        return p
    }
}

private struct LucideFlameShape: Shape {
    func path(in rect: CGRect) -> Path {
        let P = { LucideGithubPath.P($0, $1, rect) }
        var p = Path()
        p.move(to: P(12, 3))
        p.addCurve(to: P(19, 15), control1: P(16, 8), control2: P(19, 11))
        p.addCurve(to: P(12, 21), control1: P(19, 18), control2: P(16, 21))
        p.addCurve(to: P(5, 15), control1: P(8, 21), control2: P(5, 18))
        p.addCurve(to: P(12, 3), control1: P(5, 11), control2: P(8, 8))
        return p
    }
}

private struct LucideMessageSquareDiffShape: Shape {
    func path(in rect: CGRect) -> Path {
        let P = { LucideGithubPath.P($0, $1, rect) }
        let sc = LucideGithubPath.scale(rect)
        let ox = rect.midX - 12 * sc
        let oy = rect.midY - 12 * sc
        var p = Path()
        let br = CGRect(x: ox + 3 * sc, y: oy + 3 * sc, width: 18 * sc, height: 15 * sc)
        p.addPath(Path(roundedRect: br, cornerRadius: 2 * sc))
        p.move(to: P(10, 15))
        p.addLine(to: P(14, 15))
        p.move(to: P(10, 9))
        p.addLine(to: P(14, 9))
        p.move(to: P(12, 7))
        p.addLine(to: P(12, 11))
        return p
    }
}

private enum LucideGithubPath {
    static func scale(_ rect: CGRect) -> CGFloat { min(rect.width, rect.height) / 24 }

    static func P(_ x: CGFloat, _ y: CGFloat, _ rect: CGRect) -> CGPoint {
        let sc = scale(rect)
        let ox = rect.midX - 12 * sc
        let oy = rect.midY - 12 * sc
        return CGPoint(x: ox + x * sc, y: oy + y * sc)
    }

    static func ellipse(cx: CGFloat, cy: CGFloat, r: CGFloat, rect: CGRect) -> CGRect {
        let sc = scale(rect)
        let ox = rect.midX - 12 * sc
        let oy = rect.midY - 12 * sc
        return CGRect(x: ox + (cx - r) * sc, y: oy + (cy - r) * sc, width: 2 * r * sc, height: 2 * r * sc)
    }
}

private struct LucideAlertOctagonShape: Shape {
    func path(in rect: CGRect) -> Path {
        let P = { LucideGithubPath.P($0, $1, rect) }
        var p = Path()
        // Octagon outline
        p.move(to: P(7.86, 2))
        p.addLine(to: P(16.14, 2))
        p.addLine(to: P(22, 7.86))
        p.addLine(to: P(22, 16.14))
        p.addLine(to: P(16.14, 22))
        p.addLine(to: P(7.86, 22))
        p.addLine(to: P(2, 16.14))
        p.addLine(to: P(2, 7.86))
        p.closeSubpath()
        // Exclamation stem
        p.move(to: P(12, 8))
        p.addLine(to: P(12, 12))
        // Exclamation dot (small line segment so stroke renders)
        p.move(to: P(12, 16))
        p.addLine(to: P(12.01, 16))
        return p
    }
}

private struct LucideMessageSquareShape: Shape {
    func path(in rect: CGRect) -> Path {
        let P = { LucideGithubPath.P($0, $1, rect) }
        var p = Path()
        // Rounded-corner speech bubble: M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z
        p.move(to: P(21, 15))
        p.addQuadCurve(to: P(19, 17), control: P(21, 17))
        p.addLine(to: P(7, 17))
        p.addLine(to: P(3, 21))
        p.addLine(to: P(3, 5))
        p.addQuadCurve(to: P(5, 3), control: P(3, 3))
        p.addLine(to: P(19, 3))
        p.addQuadCurve(to: P(21, 5), control: P(21, 3))
        p.closeSubpath()
        return p
    }
}
