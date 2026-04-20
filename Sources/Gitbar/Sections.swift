import Foundation

enum RepoScope: Codable, Equatable, Sendable {
    case defaults
    case explicit([String])
}

enum SectionVisibility: String, Codable, CaseIterable, Equatable, Sendable {
    case visible
    case collapsedByDefault
    case hidden
}

enum SortChoice: String, Codable, CaseIterable, Equatable, Sendable {
    case updatedDesc
    case updatedAsc
    case repo

    var label: String {
        switch self {
        case .updatedDesc: return "Newest"
        case .updatedAsc: return "Oldest"
        case .repo: return "Repo"
        }
    }
}

struct SectionFilter: Codable, Equatable, Sendable {
    var conditions: [SectionCondition]
}

enum SectionSetOp: String, Codable, Equatable, Sendable {
    case includes
    case excludes
}

enum SectionEqOp: String, Codable, Equatable, Sendable {
    case is_
    case isNot
}

enum SectionPRStatusValue: String, Codable, CaseIterable, Equatable, Sendable {
    case open = "Open"
    case closed = "Closed"
    case merged = "Merged"
    case merging = "Merging"
}

enum SectionCondition: Codable, Equatable, Sendable {
    case prStatus(op: SectionSetOp, values: [SectionPRStatusValue])
    case author(op: SectionEqOp, login: String)
    case reviewer(op: SectionSetOp, login: String)
    case repository(op: SectionSetOp, repos: [String])
    case ciStatus(op: SectionSetOp, values: [CIPillKind])
    case draft(is: Bool)
    case label(op: SectionSetOp, name: String)
    case assignee(op: SectionSetOp, login: String)
    case hasMergeConflict(is: Bool)

    private enum CodingKeys: String, CodingKey {
        case kind, op, values, login, repos, isDraft, name, isOn
    }

    private enum Kind: String, Codable {
        case prStatus, author, reviewer, repository, ciStatus, draft
        case label, assignee, hasMergeConflict
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .kind)
        switch kind {
        case .prStatus:
            self = .prStatus(
                op: try c.decode(SectionSetOp.self, forKey: .op),
                values: try c.decode([SectionPRStatusValue].self, forKey: .values)
            )
        case .author:
            self = .author(
                op: try c.decode(SectionEqOp.self, forKey: .op),
                login: try c.decode(String.self, forKey: .login)
            )
        case .reviewer:
            self = .reviewer(
                op: try c.decode(SectionSetOp.self, forKey: .op),
                login: try c.decode(String.self, forKey: .login)
            )
        case .repository:
            self = .repository(
                op: try c.decode(SectionSetOp.self, forKey: .op),
                repos: try c.decode([String].self, forKey: .repos)
            )
        case .ciStatus:
            self = .ciStatus(
                op: try c.decode(SectionSetOp.self, forKey: .op),
                values: try c.decode([CIPillKind].self, forKey: .values)
            )
        case .draft:
            self = .draft(is: try c.decode(Bool.self, forKey: .isDraft))
        case .label:
            self = .label(
                op: try c.decode(SectionSetOp.self, forKey: .op),
                name: try c.decode(String.self, forKey: .name)
            )
        case .assignee:
            self = .assignee(
                op: try c.decode(SectionSetOp.self, forKey: .op),
                login: try c.decode(String.self, forKey: .login)
            )
        case .hasMergeConflict:
            self = .hasMergeConflict(is: try c.decode(Bool.self, forKey: .isOn))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .prStatus(let op, let values):
            try c.encode(Kind.prStatus, forKey: .kind)
            try c.encode(op, forKey: .op)
            try c.encode(values, forKey: .values)
        case .author(let op, let login):
            try c.encode(Kind.author, forKey: .kind)
            try c.encode(op, forKey: .op)
            try c.encode(login, forKey: .login)
        case .reviewer(let op, let login):
            try c.encode(Kind.reviewer, forKey: .kind)
            try c.encode(op, forKey: .op)
            try c.encode(login, forKey: .login)
        case .repository(let op, let repos):
            try c.encode(Kind.repository, forKey: .kind)
            try c.encode(op, forKey: .op)
            try c.encode(repos, forKey: .repos)
        case .ciStatus(let op, let values):
            try c.encode(Kind.ciStatus, forKey: .kind)
            try c.encode(op, forKey: .op)
            try c.encode(values, forKey: .values)
        case .draft(let isDraft):
            try c.encode(Kind.draft, forKey: .kind)
            try c.encode(isDraft, forKey: .isDraft)
        case .label(let op, let name):
            try c.encode(Kind.label, forKey: .kind)
            try c.encode(op, forKey: .op)
            try c.encode(name, forKey: .name)
        case .assignee(let op, let login):
            try c.encode(Kind.assignee, forKey: .kind)
            try c.encode(op, forKey: .op)
            try c.encode(login, forKey: .login)
        case .hasMergeConflict(let isOn):
            try c.encode(Kind.hasMergeConflict, forKey: .kind)
            try c.encode(isOn, forKey: .isOn)
        }
    }
}

struct GitbarSection: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var name: String
    var icon: String? = nil
    var tab: PanelTab
    var repos: RepoScope
    var filters: [SectionFilter]
    var visibility: SectionVisibility
    var contributesToBadge: Bool
    var sort: SortChoice
    var collapsed: Bool
    var order: Int
    var isDefault: Bool = false
}

extension GitbarSection {
    static func seededDefaults() -> [PanelTab: [GitbarSection]] {
        [
            .mine: seededMine(),
            .review: seededReview(),
            .issues: seededIssues(),
        ]
    }

    static func seededMine() -> [GitbarSection] {
        [
            GitbarSection(
                id: UUID(),
                name: "Needs changes",
                tab: .mine,
                repos: .defaults,
                filters: [SectionFilter(conditions: [.prStatus(op: .includes, values: [.open])])],
                visibility: .visible,
                contributesToBadge: true,
                sort: .updatedDesc,
                collapsed: false,
                order: 0,
                isDefault: true
            ),
            GitbarSection(
                id: UUID(),
                name: "Drafts",
                tab: .mine,
                repos: .defaults,
                filters: [SectionFilter(conditions: [.draft(is: true)])],
                visibility: .collapsedByDefault,
                contributesToBadge: false,
                sort: .updatedDesc,
                collapsed: true,
                order: 1,
                isDefault: true
            ),
            GitbarSection(
                id: UUID(),
                name: "CI failing",
                tab: .mine,
                repos: .defaults,
                filters: [SectionFilter(conditions: [.ciStatus(op: .includes, values: [.fail])])],
                visibility: .visible,
                contributesToBadge: true,
                sort: .updatedDesc,
                collapsed: false,
                order: 2,
                isDefault: true
            ),
        ]
    }

    static func seededReview() -> [GitbarSection] {
        [
            GitbarSection(
                id: UUID(),
                name: "Ready",
                tab: .review,
                repos: .defaults,
                filters: [SectionFilter(conditions: [.draft(is: false)])],
                visibility: .visible,
                contributesToBadge: true,
                sort: .updatedDesc,
                collapsed: false,
                order: 0,
                isDefault: true
            ),
            GitbarSection(
                id: UUID(),
                name: "Drafts",
                tab: .review,
                repos: .defaults,
                filters: [SectionFilter(conditions: [.draft(is: true)])],
                visibility: .collapsedByDefault,
                contributesToBadge: false,
                sort: .updatedDesc,
                collapsed: true,
                order: 1,
                isDefault: true
            ),
            GitbarSection(
                id: UUID(),
                name: "Blocked on CI",
                tab: .review,
                repos: .defaults,
                filters: [SectionFilter(conditions: [.ciStatus(op: .includes, values: [.fail, .running])])],
                visibility: .visible,
                contributesToBadge: false,
                sort: .updatedDesc,
                collapsed: false,
                order: 2,
                isDefault: true
            ),
        ]
    }

    static func seededIssues() -> [GitbarSection] {
        [
            GitbarSection(
                id: UUID(),
                name: "Assigned issues",
                tab: .issues,
                repos: .defaults,
                filters: [SectionFilter(conditions: [.prStatus(op: .includes, values: [.open])])],
                visibility: .visible,
                contributesToBadge: false,
                sort: .updatedDesc,
                collapsed: false,
                order: 0,
                isDefault: true
            ),
        ]
    }
}

struct SectionMatcher {
    static func matches(
        section: GitbarSection,
        row: GHIssue,
        viewerLogin: String?,
        metadata: PRRowMetadata?,
        reviewState: String?
    ) -> Bool {
        if section.filters.isEmpty { return false }
        return section.filters.contains { allConditionsMatch($0.conditions, row: row, viewerLogin: viewerLogin, metadata: metadata, reviewState: reviewState) }
    }

    private static func allConditionsMatch(
        _ conditions: [SectionCondition],
        row: GHIssue,
        viewerLogin: String?,
        metadata: PRRowMetadata?,
        reviewState: String?
    ) -> Bool {
        guard !conditions.isEmpty else { return false }
        return conditions.allSatisfy { condition in
            switch condition {
            case .prStatus(let op, let values):
                let status = issueStatus(row: row)
                // `.merging` was a broken legacy value; treat it as `.merged` for old configs.
                let normalizedValues = Set(values.map { $0 == .merging ? .merged : $0 })
                return includesEval(op: op, inSet: normalizedValues.contains(status))
            case .author(let op, let login):
                let equals = row.user.login.caseInsensitiveCompare(login) == .orderedSame
                return op == .is_ ? equals : !equals
            case .reviewer:
                // Requested-reviewers aren't exposed by the search API; this filter
                // cannot be evaluated reliably, so it never matches.
                return false
            case .repository(let op, let repos):
                let repo = row.repoFull.lowercased()
                let has = repos.map { $0.lowercased() }.contains(repo)
                return includesEval(op: op, inSet: has)
            case .ciStatus(let op, let values):
                let ci = metadata?.ci ?? .unknown
                return includesEval(op: op, inSet: values.contains(ci))
            case .draft(let isDraft):
                return row.isDraft == isDraft
            case .label(let op, let name):
                let needle = name.lowercased()
                let has = row.labels.contains { $0.name.lowercased() == needle }
                return includesEval(op: op, inSet: has)
            case .assignee(let op, let login):
                let needle = login.lowercased()
                let has = (row.assignees ?? []).contains { $0.login.lowercased() == needle }
                return includesEval(op: op, inSet: has)
            case .hasMergeConflict(let expected):
                let actual = metadata?.hasMergeConflict ?? false
                return actual == expected
            }
        }
    }

    private static func includesEval(op: SectionSetOp, inSet: Bool) -> Bool {
        op == .includes ? inSet : !inSet
    }

    private static func issueStatus(row: GHIssue) -> SectionPRStatusValue {
        if row.state.lowercased() == "open" { return .open }
        return row.pullRequest?.mergedAt != nil ? .merged : .closed
    }
}
