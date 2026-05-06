import Foundation

/// AI review CLIs gitbar can hand a PR diff off to. Detection is a one-shot
/// `command -v <bin>` against the user's login shell — same pattern as
/// `GHCLIAuth.locate()` so what gitbar resolves matches what the user's
/// terminal sees.
enum AIReviewer: String, CaseIterable {
    case claude
    case codex

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex:  return "Codex"
        }
    }
}

struct AIReviewers: Equatable {
    var claude: Bool
    var codex: Bool

    static let none = AIReviewers(claude: false, codex: false)

    var any: Bool { claude || codex }

    func isInstalled(_ reviewer: AIReviewer) -> Bool {
        switch reviewer {
        case .claude: return claude
        case .codex:  return codex
        }
    }

    /// Resolve each reviewer's binary off-main; returns a fresh `AIReviewers`
    /// snapshot. Cheap (two short-lived shell calls), safe to call on launch
    /// and on focus regain.
    static func detect() async -> AIReviewers {
        async let claude = isExecutable("claude")
        async let codex  = isExecutable("codex")
        return AIReviewers(claude: await claude, codex: await codex)
    }

    private static func isExecutable(_ name: String) async -> Bool {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
                proc.arguments = ["-lc", "command -v \(name)"]
                let out = Pipe()
                proc.standardOutput = out
                proc.standardError = Pipe()
                do {
                    try proc.run()
                    proc.waitUntilExit()
                    let data = out.fileHandleForReading.readDataToEndOfFile()
                    let path = String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let ok = !path.isEmpty
                        && FileManager.default.isExecutableFile(atPath: path)
                    cont.resume(returning: ok)
                } catch {
                    cont.resume(returning: false)
                }
            }
        }
    }
}
