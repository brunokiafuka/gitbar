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
        var dirty = false
        if root.sections == nil && root.sectionsSeeded != true {
            root.sections = GitbarSection.seededDefaults()
            root.sectionsSeeded = true
            dirty = true
        }
        if var sections = root.sections {
            var review = sections[.review] ?? []
            var changed = false
            // Drop the previously-seeded "Approved" section now that Waiting on author covers approved reviews.
            let approvedLegacyID = UUID(uuidString: "D1D49A31-7B2E-4A07-8F2C-7E2A5E6E6E02")!
            if let idx = review.firstIndex(where: { $0.id == approvedLegacyID }) {
                review.remove(at: idx)
                changed = true
            }
            let seeded = GitbarSection.seededReview()
            if !review.contains(where: { $0.id == GitbarSection.waitingOnAuthorDefaultID }) {
                if let template = seeded.first(where: { $0.id == GitbarSection.waitingOnAuthorDefaultID }) {
                    var toAdd = template
                    toAdd.order = (review.map(\.order).max() ?? -1) + 1
                    review.append(toAdd)
                    changed = true
                }
            } else if let idx = review.firstIndex(where: { $0.id == GitbarSection.waitingOnAuthorDefaultID }) {
                // Upgrade existing default section to include `.approved` if it still carries the prior default set.
                let legacyDefault = Set<ReviewedByMeStateValue>([.changesRequested, .commented])
                let conditions = review[idx].filters.flatMap(\.conditions)
                for cond in conditions {
                    if case let .reviewedByMeState(op, values) = cond, Set(values) == legacyDefault {
                        review[idx].filters = [SectionFilter(conditions: [
                            .reviewedByMeState(op: op, values: ReviewedByMeStateValue.allCases)
                        ])]
                        changed = true
                        break
                    }
                }
            }
            if changed {
                sections[.review] = review
                root.sections = sections
                dirty = true
            }
        }
        if dirty { try? writeRoot(root) }
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
