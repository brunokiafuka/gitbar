import AppKit
import Foundation

/// Terminal emulators gitbar can hand a command off to. v1 covers Terminal.app
/// and iTerm2 via their AppleScript bridges. Picker is exposed in Settings;

enum TerminalApp: String, CaseIterable, Identifiable, Equatable {
    case terminal
    case iterm2

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .terminal: return "Terminal"
        case .iterm2:   return "iTerm2"
        }
    }

    var bundleID: String {
        switch self {
        case .terminal: return "com.apple.Terminal"
        case .iterm2:   return "com.googlecode.iterm2"
        }
    }

    /// True when an app with this bundle ID is registered with LaunchServices.
    func isInstalled() -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    /// Hands `command` to the terminal. Returns false on failure so the caller
    /// can surface an alert. Always runs on the main actor — AppleScript and
    /// NSWorkspace expect that.
    @MainActor
    func launch(command: String) -> Bool {
        switch self {
        case .terminal: return launchTerminal(command: command)
        case .iterm2:   return launchITerm2(command: command)
        }
    }

    // MARK: - Per-terminal launchers

    @MainActor
    private func launchTerminal(command: String) -> Bool {
        // `do script` before `activate`: when Terminal isn't running, the Apple
        // Event launches it silently and runs the command in a single window.
        // Activating first would open the user's startup window before
        // `do script` makes a second one.
        runAppleScript("""
        tell application "Terminal"
            do script \(appleScriptString(command))
            activate
        end tell
        """)
    }

    @MainActor
    private func launchITerm2(command: String) -> Bool {
        runAppleScript("""
        tell application "iTerm"
            activate
            set newWindow to (create window with default profile)
            tell current session of newWindow
                write text \(appleScriptString(command))
            end tell
        end tell
        """)
    }

    // MARK: - Helpers

    @MainActor
    private func runAppleScript(_ source: String) -> Bool {
        guard let script = NSAppleScript(source: source) else { return false }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        return error == nil
    }

    private func appleScriptString(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

extension TerminalApp {
    /// User's stored choice from Settings. Empty/unrecognized → nil (Terminal.app
    /// fallback at the call site).
    static let userDefaultsKey = "gitbar.aiReviewTerminal"

    static var preferred: TerminalApp? {
        guard let raw = UserDefaults.standard.string(forKey: userDefaultsKey),
              let app = TerminalApp(rawValue: raw) else { return nil }
        return app
    }

    /// The terminal gitbar would actually launch right now: the user's pick if
    /// it's still installed, otherwise Terminal.app.
    static var effective: TerminalApp {
        let chosen = preferred ?? .terminal
        return chosen.isInstalled() ? chosen : .terminal
    }
}
