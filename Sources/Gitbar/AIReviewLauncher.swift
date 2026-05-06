import AppKit
import Foundation

/// Builds the per-CLI shell command for "review this PR" and hands it to the
/// user's chosen terminal emulator.
///
/// Claude path: `claude '/review <pr-html-url>'` — Claude's own slash command
/// fetches the diff, so gitbar doesn't need to pipe one. Interactive — the
/// user can ask follow-ups in the same session.
///
/// Codex path: `gh pr diff <num> -R <owner>/<repo> | codex exec '<prompt>'` —
/// non-interactive print mode. Codex doesn't have an equivalent slash command
/// and `exec` is the form we know reads piped stdin reliably.
@MainActor
enum AIReviewLauncher {
    /// Used by the Codex path. Hard-coded; a "customize prompt" setting is a
    /// follow-up if demand materializes.
    static let codexPrompt =
        "Review this PR diff. Surface bugs, regressions, and concerns. Be concise."

    static func review(pr: GHIssue, with reviewer: AIReviewer) {
        let command: String
        switch reviewer {
        case .claude:
            command = "claude \(shellSingleQuote("/review \(pr.htmlUrl)"))"
        case .codex:
            let repo = pr.repoFull
            guard !repo.isEmpty else {
                presentFailure("Couldn't determine the PR's repository.")
                return
            }
            command = "gh pr diff \(pr.number) -R \(repo) | codex exec \(shellSingleQuote(codexPrompt))"
        }

        let chosen = TerminalApp.effective
        if !chosen.launch(command: command) {
            presentFailure("Couldn't open \(chosen.displayName).")
        }
    }

    /// Wrap `s` in single quotes for POSIX shells. Embedded single quotes are
    /// closed-escaped-reopened (`'\''`).
    private static func shellSingleQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func presentFailure(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}
