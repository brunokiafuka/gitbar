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
        readRoot().github.token
    }

    static func saveToken(_ token: String) throws {
        var root = readRoot()
        root.github.token = token
        try writeRoot(root)
    }

    static func readSectionsWithMigration() -> [PanelTab: [GitbarSection]] {
        var root = readRoot()
        if root.sections == nil && root.sectionsSeeded != true {
            root.sections = GitbarSection.seededDefaults()
            root.sectionsSeeded = true
            try? writeRoot(root)
        }
        return root.sections ?? [:]
    }

    static func saveSections(_ sections: [PanelTab: [GitbarSection]]) throws {
        var root = readRoot()
        root.sections = sections
        root.sectionsSeeded = true
        try writeRoot(root)
    }

    static func withConfigMutation(_ mutate: (inout ConfigRoot) -> Void) throws {
        var root = readRoot()
        mutate(&root)
        try writeRoot(root)
    }
}

private extension Config {
    static func readRoot() -> ConfigRoot {
        guard let data = try? Data(contentsOf: configURL) else {
            return ConfigRoot()
        }
        let decoder = JSONDecoder()
        if let root = try? decoder.decode(ConfigRoot.self, from: data) {
            return root
        }
        return ConfigRoot()
    }

    static func writeRoot(_ root: ConfigRoot) throws {
        let url = configURL
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let out = try encoder.encode(root)
        try out.write(to: url, options: .atomic)
    }
}

struct ConfigRoot: Codable {
    struct GitHubConfig: Codable {
        var token: String?
    }

    var github: GitHubConfig = .init()
    var sections: [PanelTab: [GitbarSection]]?
    var sectionsSeeded: Bool?
}
