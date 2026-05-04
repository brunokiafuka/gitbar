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

enum ReviewedByMeStateValue: String, Codable, CaseIterable, Equatable, Sendable {
    case approved = "APPROVED"
    case changesRequested = "CHANGES_REQUESTED"
    case commented = "COMMENTED"

    var label: String {
        switch self {
        case .approved: return "Approved"
        case .changesRequested: return "Changes requested"
        case .commented: return "Commented"
        }
    }
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
    case reviewedByMeState(op: SectionSetOp, values: [ReviewedByMeStateValue])
    case reviewedBy(op: SectionEqOp, login: String)

    private enum CodingKeys: String, CodingKey {
        case kind, op, values, login, repos, isDraft, name, isOn
    }

    private enum Kind: String, Codable {
        case prStatus, author, reviewer, repository, ciStatus, draft
        case label, assignee, hasMergeConflict, reviewedByMeState
        case reviewedBy
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
        case .reviewedByMeState:
            self = .reviewedByMeState(
                op: try c.decode(SectionSetOp.self, forKey: .op),
                values: try c.decode([ReviewedByMeStateValue].self, forKey: .values)
            )
        case .reviewedBy:
            self = .reviewedBy(
                op: try c.decode(SectionEqOp.self, forKey: .op),
                login: try c.decode(String.self, forKey: .login)
            )
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
        case .reviewedByMeState(let op, let values):
            try c.encode(Kind.reviewedByMeState, forKey: .kind)
            try c.encode(op, forKey: .op)
            try c.encode(values, forKey: .values)
        case .reviewedBy(let op, let login):
            try c.encode(Kind.reviewedBy, forKey: .kind)
            try c.encode(op, forKey: .op)
            try c.encode(login, forKey: .login)
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

    /// True when any filter uses a `.reviewedByMeState` condition — such sections draw from
    /// the "reviewed-by-me" source rather than the review-request queue.
    var targetsReviewedByMe: Bool {
        filters.contains { f in
            f.conditions.contains { c in
                if case .reviewedByMeState = c { return true }
                return false
            }
        }
    }

    /// True when any filter has a scoping condition (repo / author / assignee / label / reviewer)
    /// with a non-empty value. On the Review tab this widens the section to a per-section
    /// GitHub search instead of filtering the local review queue.
    var hasScopingCondition: Bool {
        filters.contains { f in f.conditions.contains(where: { $0.isScoping }) }
    }

    /// Some default sections are non-actionable by definition — the ball is in someone
    /// else's court — and must never feed badge counts even if a stored config flips the
    /// flag on. Today: the seeded "Waiting on author". Count/chip-render paths read this
    /// so a stale config or accidental toggle can't pull these back into the badge.
    var effectiveContributesToBadge: Bool {
        if id == GitbarSection.waitingOnAuthorDefaultID { return false }
        return contributesToBadge
    }

    /// UI gate for the editor's badge toggle. Mirrors the runtime lock so we don't expose
    /// a control that has no effect.
    var canEditContributesToBadge: Bool {
        id != GitbarSection.waitingOnAuthorDefaultID
    }
}

extension SectionCondition {
    /// Conditions that scope what GitHub returns (repo / author / assignee / label / reviewer
    /// / reviewedBy). Their presence on a Review section flips it from queue-filtering to
    /// widened search.
    var isScoping: Bool {
        switch self {
        case .repository(_, let repos):
            return repos.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        case .author(_, let login):
            return !login.trimmingCharacters(in: .whitespaces).isEmpty
        case .assignee(_, let login):
            return !login.trimmingCharacters(in: .whitespaces).isEmpty
        case .label(_, let name):
            return !name.trimmingCharacters(in: .whitespaces).isEmpty
        case .reviewer(_, let login):
            return !login.trimmingCharacters(in: .whitespaces).isEmpty
        case .reviewedBy(_, let login):
            return !login.trimmingCharacters(in: .whitespaces).isEmpty
        case .prStatus, .ciStatus, .draft, .hasMergeConflict, .reviewedByMeState:
            return false
        }
    }

    /// Conditions whose evaluation requires per-PR metadata not fetched for outside-queue rows.
    /// On widened Review sections these are display-only — the editor flags them with a warning
    /// and the runtime ignores them (matcher isn't run on widened sections).
    var requiresFetchedMetadata: Bool {
        switch self {
        case .ciStatus, .hasMergeConflict, .reviewedByMeState:
            return true
        case .prStatus, .author, .assignee, .repository, .label, .reviewer, .draft, .reviewedBy:
            return false
        }
    }
}

extension GitbarSection {
    /// Stable id for the seeded "Waiting on author" section so settings can locate it after edits.
    static let waitingOnAuthorDefaultID = UUID(uuidString: "D1D49A31-7B2E-4A07-8F2C-7E2A5E6E6E01")!
    /// Stable id for the seeded "Assigned issues" section so migrations can locate it after edits.
    static let assignedIssuesDefaultID = UUID(uuidString: "D1D49A31-7B2E-4A07-8F2C-7E2A5E6E6E03")!

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
            GitbarSection(
                id: waitingOnAuthorDefaultID,
                name: "Waiting on author",
                tab: .review,
                repos: .defaults,
                filters: [SectionFilter(conditions: [
                    .reviewedByMeState(op: .includes, values: ReviewedByMeStateValue.allCases)
                ])],
                visibility: .visible,
                contributesToBadge: false,
                sort: .updatedDesc,
                collapsed: false,
                order: 3,
                isDefault: true
            ),
        ]
    }

    static func seededIssues() -> [GitbarSection] {
        [
            GitbarSection(
                id: assignedIssuesDefaultID,
                name: "Assigned issues",
                tab: .issues,
                repos: .defaults,
                filters: [SectionFilter(conditions: [.prStatus(op: .includes, values: [.open])])],
                visibility: .visible,
                contributesToBadge: true,
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
                let resolved = resolveLogin(login, viewerLogin: viewerLogin)
                let equals = row.user.login.caseInsensitiveCompare(resolved) == .orderedSame
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
                let has: Bool
                if isUnassignedSentinel(login) {
                    has = (row.assignees ?? []).isEmpty
                } else {
                    let needle = resolveLogin(login, viewerLogin: viewerLogin).lowercased()
                    has = (row.assignees ?? []).contains { $0.login.lowercased() == needle }
                }
                return includesEval(op: op, inSet: has)
            case .hasMergeConflict(let expected):
                let actual = metadata?.hasMergeConflict ?? false
                return actual == expected
            case .reviewedByMeState(let op, let values):
                guard let raw = reviewState,
                      let state = ReviewedByMeStateValue(rawValue: raw) else {
                    return op == .excludes
                }
                let has = values.contains(state)
                return includesEval(op: op, inSet: has)
            case .reviewedBy(let op, let login):
                // `reviewedBy` is a scoping condition — sections carrying it widen to a remote
                // search and the matcher isn't run for them. For arbitrary logins we have no
                // local signal; the only login we can answer for is the viewer (`@me`), via the
                // existing `reviewState` lookup.
                let resolved = resolveLogin(login, viewerLogin: viewerLogin)
                guard let me = viewerLogin,
                      resolved.caseInsensitiveCompare(me) == .orderedSame else {
                    return false
                }
                let actuallyReviewed = reviewState != nil
                return op == .is_ ? actuallyReviewed : !actuallyReviewed
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

    fileprivate static func resolveLogin(_ login: String, viewerLogin: String?) -> String {
        let trimmed = login.trimmingCharacters(in: .whitespaces)
        if trimmed.lowercased() == "@me", let me = viewerLogin { return me }
        return trimmed
    }

    fileprivate static func isUnassignedSentinel(_ login: String) -> Bool {
        let v = login.trimmingCharacters(in: .whitespaces).lowercased()
        return v == "@none" || v == "unassigned"
    }
}

// MARK: - Remote search translation (issues tab)

extension GitbarSection {
    /// Translates this section's filters into GitHub issue-search queries.
    /// Each `SectionFilter` (OR'd at the section level) becomes one query whose
    /// conditions (AND'd) are emitted as qualifiers. Sections without any
    /// scoping condition (repo/label/author/assignee) implicitly scope to the
    /// viewer (`assignee:@me`) so the remote result stays tractable.
    func remoteIssueSearchQueries() -> [String] {
        guard tab == .issues, !filters.isEmpty else { return [] }
        return filters.map { filter in
            var parts: [String] = ["type:issue"]
            var hasScoping = false
            var hasState = false
            for cond in filter.conditions {
                switch cond {
                case .prStatus(let op, let values):
                    // Issues only expose open/closed; legacy `.merging` + `.merged` collapse to `.closed`.
                    let wanted: Set<SectionPRStatusValue> = Set(values.map { v -> SectionPRStatusValue in
                        switch v {
                        case .merging, .merged, .closed: return .closed
                        case .open: return .open
                        }
                    })
                    let target = op == .includes
                        ? wanted
                        : Set<SectionPRStatusValue>([.open, .closed]).subtracting(wanted)
                    // Any state condition counts as a user-set state preference, even if
                    // the target set is {open, closed} (== "any state", no qualifier needed).
                    hasState = true
                    if target == [.open] {
                        parts.append("state:open")
                    } else if target == [.closed] {
                        parts.append("state:closed")
                    }
                case .author(let op, let login):
                    let value = login.trimmingCharacters(in: .whitespaces)
                    guard !value.isEmpty else { break }
                    parts.append(op == .is_ ? "author:\(value)" : "-author:\(value)")
                    hasScoping = true
                case .assignee(let op, let login):
                    if SectionMatcher.isUnassignedSentinel(login) {
                        parts.append(op == .includes ? "no:assignee" : "assignee:*")
                    } else {
                        let value = login.trimmingCharacters(in: .whitespaces)
                        guard !value.isEmpty else { break }
                        parts.append(op == .includes ? "assignee:\(value)" : "-assignee:\(value)")
                    }
                    hasScoping = true
                case .repository(let op, let repos):
                    for repo in repos where !repo.trimmingCharacters(in: .whitespaces).isEmpty {
                        parts.append(op == .includes ? "repo:\(repo)" : "-repo:\(repo)")
                    }
                    hasScoping = true
                case .label(let op, let name):
                    let trimmed = name.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { break }
                    let qualifier = trimmed.contains(" ") ? "\"\(trimmed)\"" : trimmed
                    parts.append(op == .includes ? "label:\(qualifier)" : "-label:\(qualifier)")
                    hasScoping = true
                case .reviewer, .ciStatus, .draft, .hasMergeConflict, .reviewedByMeState,
                     .reviewedBy:
                    // Either not expressible in the issue search API, or not exposed on the
                    // Issues tab editor; local matcher will evaluate if applicable.
                    break
                }
            }
            if !hasScoping { parts.append("assignee:@me") }
            if !hasState { parts.append("state:open") }
            parts.append("sort:updated-desc")
            return parts.joined(separator: " ")
        }
    }
}

// MARK: - Remote search translation (review tab, widened)

extension GitbarSection {
    /// Translates a Review-tab section's filters into per-section PR-search queries.
    /// Only emitted when the section has a scoping condition (`hasScopingCondition`); otherwise
    /// the section continues to filter the local review queue. Filters within a widened section
    /// that lack their own scoping qualifier fall back to `review-requested:@me` so the
    /// non-scoped filter still represents the user's review queue. Defaults to `state:open`.
    func remoteReviewSearchQueries() -> [String] {
        guard tab == .review, hasScopingCondition else { return [] }
        return filters.map { filter in
            var parts: [String] = ["type:pr"]
            var hasScoping = false
            var hasState = false
            for cond in filter.conditions {
                switch cond {
                case .prStatus(let op, let values):
                    let wanted: Set<SectionPRStatusValue> = Set(values.map { v -> SectionPRStatusValue in
                        switch v {
                        case .merging, .merged, .closed: return .closed
                        case .open: return .open
                        }
                    })
                    let target = op == .includes
                        ? wanted
                        : Set<SectionPRStatusValue>([.open, .closed]).subtracting(wanted)
                    hasState = true
                    if target == [.open] {
                        parts.append("state:open")
                    } else if target == [.closed] {
                        parts.append("state:closed")
                    }
                case .author(let op, let login):
                    let value = login.trimmingCharacters(in: .whitespaces)
                    guard !value.isEmpty else { break }
                    parts.append(op == .is_ ? "author:\(value)" : "-author:\(value)")
                    hasScoping = true
                case .assignee(let op, let login):
                    if SectionMatcher.isUnassignedSentinel(login) {
                        parts.append(op == .includes ? "no:assignee" : "assignee:*")
                        hasScoping = true
                    } else {
                        let value = login.trimmingCharacters(in: .whitespaces)
                        guard !value.isEmpty else { break }
                        parts.append(op == .includes ? "assignee:\(value)" : "-assignee:\(value)")
                        hasScoping = true
                    }
                case .repository(let op, let repos):
                    for repo in repos where !repo.trimmingCharacters(in: .whitespaces).isEmpty {
                        parts.append(op == .includes ? "repo:\(repo)" : "-repo:\(repo)")
                        hasScoping = true
                    }
                case .label(let op, let name):
                    let trimmed = name.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { break }
                    let qualifier = trimmed.contains(" ") ? "\"\(trimmed)\"" : trimmed
                    parts.append(op == .includes ? "label:\(qualifier)" : "-label:\(qualifier)")
                    hasScoping = true
                case .reviewer(let op, let login):
                    let value = login.trimmingCharacters(in: .whitespaces)
                    guard !value.isEmpty else { break }
                    parts.append(op == .includes ? "review-requested:\(value)" : "-review-requested:\(value)")
                    hasScoping = true
                case .draft(let isDraft):
                    parts.append(isDraft ? "draft:true" : "draft:false")
                case .reviewedBy(let op, let login):
                    let value = login.trimmingCharacters(in: .whitespaces)
                    guard !value.isEmpty else { break }
                    parts.append(op == .is_ ? "reviewed-by:\(value)" : "-reviewed-by:\(value)")
                    hasScoping = true
                case .ciStatus, .hasMergeConflict, .reviewedByMeState:
                    // Not expressible in the issue-search API — runtime ignores these on widened
                    // sections and the editor surfaces a warning row.
                    break
                }
            }
            if !hasScoping { parts.append("review-requested:@me") }
            if !hasState { parts.append("state:open") }
            parts.append("sort:updated-desc")
            return parts.joined(separator: " ")
        }
    }
}
