import Foundation

enum Config {
    static var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gitbar/config.json")
    }

    /// Token is read only from `~/.gitbar/config.json` → `github.token` (see `saveToken`).
    static func resolveToken() -> String? {
        let t = readStoredToken()?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (t?.isEmpty ?? true) ? nil : t
    }

    static func readStoredToken() -> String? {
        guard
            let data = try? Data(contentsOf: configURL),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let gh = obj["github"] as? [String: Any],
            let token = gh["token"] as? String
        else { return nil }
        return token
    }

    static func saveToken(_ token: String) throws {
        let url = configURL
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var root: [String: Any] = [:]
        if let data = try? Data(contentsOf: url),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            root = existing
        }
        var gh = (root["github"] as? [String: Any]) ?? [:]
        gh["token"] = token
        root["github"] = gh
        let out = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        )
        try out.write(to: url, options: .atomic)
    }
}
