import SwiftUI

enum SectionEditorMode: Equatable {
    case create(PanelTab)
    case edit(GitbarSection)

    var tab: PanelTab {
        switch self {
        case .create(let t): return t
        case .edit(let s): return s.tab
        }
    }

    var section: GitbarSection? {
        switch self {
        case .create: return nil
        case .edit(let s): return s
        }
    }
}

struct SectionEditorView: View {
    let mode: SectionEditorMode
    let onSave: (GitbarSection) -> Void
    let onDelete: (() -> Void)?
    let onCancel: () -> Void

    @State private var showDeleteConfirm = false

    @Environment(\.colorScheme) private var colorScheme

    @State private var name: String
    @State private var icon: String?
    @State private var visibility: SectionVisibility
    @State private var contributesToBadge: Bool
    @State private var filters: [FilterDraft]
    @State private var requestEmojiPicker: Bool = false

    private let contentHorizontalPadding: CGFloat = 16
    private let conditionFieldWidth: CGFloat = 132
    private let operatorWidth: CGFloat = 64
    private let conditionValueWidth: CGFloat = 160
    init(
        mode: SectionEditorMode,
        onSave: @escaping (GitbarSection) -> Void,
        onDelete: (() -> Void)? = nil,
        onCancel: @escaping () -> Void
    ) {
        self.mode = mode
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel

        switch mode {
        case .create:
            _name = State(initialValue: "")
            _icon = State(initialValue: nil)
            _visibility = State(initialValue: .visible)
            _contributesToBadge = State(initialValue: true)
            _filters = State(initialValue: [FilterDraft(defaultCondition: Self.defaultCondition(for: mode.tab))])
        case .edit(let section):
            _name = State(initialValue: section.name)
            _icon = State(initialValue: section.icon)
            _visibility = State(initialValue: section.visibility)
            _contributesToBadge = State(initialValue: section.contributesToBadge)
            let existing = section.filters.map { FilterDraft(from: $0, tab: mode.tab) }
            _filters = State(initialValue: existing.isEmpty ? [FilterDraft()] : existing)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.hairline(colorScheme))
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if showsDefaultIssuesNotice {
                        defaultIssuesNotice
                    }
                    if showsReviewWideningNotice {
                        reviewWideningNotice
                    }
                    nameSection
                    repositoriesSection
                    filtersSection
                    visibilitySection
                    badgeSection
                }
                .padding(.horizontal, contentHorizontalPadding)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .alert("Delete filter?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) { onDelete?() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("\"\(name)\" will be removed. This can't be undone.")
            }
            .frame(maxWidth: .infinity)
            Divider().overlay(Theme.hairline(colorScheme))
            footer
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                onCancel()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Back")

            Text(mode.section == nil ? "Create filter" : "Update \"\(name)\"")
                .font(.system(size: 13, weight: .semibold))
            Text("· \(mode.tab.label)")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var showsDefaultIssuesNotice: Bool {
        mode.tab == .issues && (mode.section?.isDefault ?? false)
    }

    /// True when the live filter draft has any scoping condition (repo/author/assignee/label/reviewer)
    /// with a non-empty value. Drives the widening notice and the editor's metadata-field hiding.
    private var isReviewWidened: Bool {
        mode.tab == .review && filters.contains { f in
            f.conditions.contains(where: { $0.isScopingDraft })
        }
    }

    private var showsReviewWideningNotice: Bool { isReviewWidened }

    private var defaultIssuesNotice: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.blue)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text("Built-in filter — scoped to issues assigned to you.")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("For custom scopes (a specific repo, label, or another user), create a new filter. You can hide this one under Visibility.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.meta)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Theme.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8).stroke(Theme.blue.opacity(0.25), lineWidth: 0.5)
        )
    }

    private var reviewWideningNotice: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.blue)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text("Filtering sections")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Adding a scoping filter (Repository, Author, Assignee, Label, Reviewer, Reviewed by) extends this section to show all matching PRs across that scope, not just PRs awaiting your review.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.meta)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Theme.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8).stroke(Theme.blue.opacity(0.25), lineWidth: 0.5)
        )
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("Section name")
            HStack(spacing: 6) {
                ZStack {
                    EmojiCaptureField(selected: $icon, requestFocus: $requestEmojiPicker)
                        .frame(width: 1, height: 1)
                        .opacity(0.01)
                        .allowsHitTesting(false)

                    Button {
                        requestEmojiPicker = true
                    } label: {
                        Group {
                            if let icon, !icon.isEmpty {
                                Text(icon).font(.system(size: 16))
                            } else {
                                Image(systemName: "face.smiling")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Theme.meta)
                            }
                        }
                        .frame(width: 28, height: 22)
                        .background(Theme.surfaceHi(colorScheme), in: RoundedRectangle(cornerRadius: 5))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(Theme.hairline(colorScheme), lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Pick emoji (⌃⌘Space works too)")
                    .contextMenu {
                        if icon != nil {
                            Button("Remove icon") { icon = nil }
                        }
                    }
                }
                .fixedSize()

                TextField("e.g. Assigned to me", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var repositoriesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("Repositories")
            HStack {
                Text("Default repos")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Coming soon")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.meta)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.surfaceHi(colorScheme), in: Capsule())
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Theme.surfaceHi(colorScheme).opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6).stroke(Theme.hairline(colorScheme), lineWidth: 0.5)
            )
        }
    }

    private var filtersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("Filters")
            Text("Rows inside a filter are ANDed; filters are ORed.")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.meta)
            if mode.tab == .issues, !(mode.section?.isDefault ?? false) {
                Text("Runs as a GitHub search. Scope with a repo, label, author, or assignee — otherwise defaults to issues assigned to you.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.meta)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if mode.tab == .review {
                Text("Review sections show open PRs unless you add a Status filter.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.meta)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 8) {
                ForEach(Array(filters.enumerated()), id: \.element.id) { filterIndex, filter in
                    filterGroup(filterIndex: filterIndex, filter: filter)
                    if filterIndex < filters.count - 1 {
                        Text("OR")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(Theme.meta)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 2)
                    }
                }
            }

            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        filters.append(FilterDraft())
                    }
                } label: {
                    Label("Add filter", systemImage: "plus")
                        .font(.system(size: 11.5))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.blue)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.blue.opacity(0.12), in: Capsule())

                Spacer()
            }
        }
    }

    @ViewBuilder
    private func filterGroup(filterIndex: Int, filter: FilterDraft) -> some View {
        VStack(spacing: 6) {
            ForEach(Array(filter.conditions.enumerated()), id: \.element.id) { conditionIndex, _ in
                conditionRow(filterIndex: filterIndex, conditionIndex: conditionIndex, isFirstInFilter: conditionIndex == 0)
                    .transition(.asymmetric(
                        insertion: AnyTransition.opacity.combined(with: .move(edge: .top)),
                        removal: AnyTransition.opacity
                    ))
            }
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        filters[filterIndex].conditions.append(ConditionDraft())
                    }
                } label: {
                    Label("Add condition", systemImage: "plus")
                        .font(.system(size: 11.5))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.blue)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.blue.opacity(0.12), in: Capsule())

                if filters.count > 1 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            _ = filters.remove(at: filterIndex)
                        }
                    } label: {
                        Text("Remove filter")
                            .font(.system(size: 11.5))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.top, 2)
        }
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(Theme.surfaceHi(colorScheme))
                .opacity(0.2)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8).stroke(Theme.hairline(colorScheme), lineWidth: 0.5)
        )
    }

    private var visibilitySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("Visibility")
            Picker("", selection: $visibility) {
                Text("Visible").tag(SectionVisibility.visible)
                Text("Collapsed by default").tag(SectionVisibility.collapsedByDefault)
                Text("Hidden").tag(SectionVisibility.hidden)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .frame(maxWidth: 260, alignment: .leading)
            Text(visibilityHint)
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.meta)
        }
    }

    private var badgeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("Count pill")
            Toggle(isOn: $contributesToBadge) {
                Text("Show a count pill on this section's header")
                    .font(.system(size: 11.5))
            }
            .toggleStyle(.checkbox)
        }
    }

    @ViewBuilder
    private func conditionRow(filterIndex: Int, conditionIndex: Int, isFirstInFilter: Bool) -> some View {
        let binding = conditionBinding(filterIndex: filterIndex, conditionIndex: conditionIndex)
        let currentField = binding.wrappedValue.field
        let stale = isReviewWidened && Self.metadataDependentFields.contains(currentField)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(isFirstInFilter ? "Where" : "And")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .trailing)

                Picker("", selection: binding.field) {
                    ForEach(visibleFields(currentField: currentField)) { field in
                        Text(field.label(for: mode.tab)).tag(field)
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(width: conditionFieldWidth)

                operatorPicker(for: binding)
                valueEditor(for: binding)
                    .frame(width: conditionValueWidth, alignment: .leading)

                Button {
                    if filters[filterIndex].conditions.count > 1 {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            _ = filters[filterIndex].conditions.remove(at: conditionIndex)
                        }
                    }
                } label: {
                    Image(systemName: "minus.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(filters[filterIndex].conditions.count > 1 ? Color.secondary : Color.secondary.opacity(0.3))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .disabled(filters[filterIndex].conditions.count <= 1)
                .help(filters[filterIndex].conditions.count > 1 ? "Remove condition" : "At least one condition is required")
            }
            if stale {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(Theme.amber)
                    Text("Won't apply on widened sections — remove or drop the scoping filter to re-enable.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.meta)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // Align the warning under the field picker: 42 ("Where" label width) + 8 (HStack spacing).
                .padding(.leading, 50)
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
        .background(Theme.surfaceHi(colorScheme).opacity(0.28), in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6).stroke(Theme.hairline(colorScheme), lineWidth: 0.5)
        )
    }

    /// Fields the picker should show. Hides metadata-dependent fields on widened Review
    /// sections, but keeps the row's *current* field in the menu so existing instances
    /// remain editable (and the warning row above it stays meaningful).
    private func visibleFields(currentField: ConditionDraft.Field) -> [ConditionDraft.Field] {
        let all = Self.availableFields(for: mode.tab)
        guard isReviewWidened else { return all }
        return all.filter { field in
            !Self.metadataDependentFields.contains(field) || field == currentField
        }
    }

    private func conditionBinding(filterIndex: Int, conditionIndex: Int) -> Binding<ConditionDraft> {
        Binding(
            get: { filters[filterIndex].conditions[conditionIndex] },
            set: { filters[filterIndex].conditions[conditionIndex] = $0 }
        )
    }

    @ViewBuilder
    private func operatorPicker(for binding: Binding<ConditionDraft>) -> some View {
        switch binding.wrappedValue.field {
        case .prStatus, .ciStatus, .reviewer, .assignee, .repository, .label, .reviewedByMeState:
            Picker("", selection: binding.setOp) {
                Text("is").tag(SectionSetOp.includes)
                Text("is not").tag(SectionSetOp.excludes)
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(width: operatorWidth)
        case .author, .reviewedBy:
            Picker("", selection: binding.eqOp) {
                Text("is").tag(SectionEqOp.is_)
                Text("is not").tag(SectionEqOp.isNot)
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(width: operatorWidth)
        case .draft, .mergeConflict:
            Text("is")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: operatorWidth, alignment: .center)
        }
    }

    @ViewBuilder
    private func valueEditor(for binding: Binding<ConditionDraft>) -> some View {
        switch binding.wrappedValue.field {
        case .prStatus:
            multiSelectMenu(
                title: summary(
                    for: binding.wrappedValue.prStatuses.map(\.rawValue),
                    placeholder: "Select status"
                ),
                all: SectionPRStatusValue.allCases.filter { $0 != .merging }.map { ($0, $0.rawValue) },
                selection: binding.prStatuses
            )
        case .ciStatus:
            multiSelectMenu(
                title: summary(
                    for: binding.wrappedValue.ciStatuses.map { $0.rawValue.capitalized },
                    placeholder: "Select CI"
                ),
                all: CIPillKind.allCases.map { ($0, $0.rawValue.capitalized) },
                selection: binding.ciStatuses
            )
        case .author:
            TextField("login or @me", text: binding.authorLogin)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .frame(maxWidth: .infinity)
        case .reviewer:
            TextField("GitHub username", text: binding.reviewerLogin)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .frame(maxWidth: .infinity)
        case .assignee:
            TextField("login, @me, or @none", text: binding.assigneeLogin)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .frame(maxWidth: .infinity)
        case .repository:
            TextField("owner/repo (comma-separated)", text: binding.repositoryText)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .frame(maxWidth: .infinity)
        case .label:
            TextField("e.g. bug, frontend", text: binding.labelName)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .frame(maxWidth: .infinity)
        case .draft:
            Picker("", selection: binding.isDraftValue) {
                Text("a draft").tag(true)
                Text("not a draft").tag(false)
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 130)
        case .mergeConflict:
            Picker("", selection: binding.hasMergeConflictValue) {
                Text("conflicting").tag(true)
                Text("not conflicting").tag(false)
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 150)
        case .reviewedByMeState:
            multiSelectMenu(
                title: summary(
                    for: binding.wrappedValue.reviewedByMeStates.map(\.label),
                    placeholder: "Select review"
                ),
                all: ReviewedByMeStateValue.allCases.map { ($0, $0.label) },
                selection: binding.reviewedByMeStates
            )
        case .reviewedBy:
            TextField("login or @me", text: binding.reviewedByLogin)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .frame(maxWidth: .infinity)
        }
    }

    private func multiSelectMenu<T: Hashable>(
        title: String,
        all: [(T, String)],
        selection: Binding<Set<T>>
    ) -> some View {
        Menu {
            ForEach(all, id: \.0) { (value, label) in
                Button {
                    if selection.wrappedValue.contains(value) {
                        selection.wrappedValue.remove(value)
                    } else {
                        selection.wrappedValue.insert(value)
                    }
                } label: {
                    HStack {
                        Image(systemName: selection.wrappedValue.contains(value) ? "checkmark.square.fill" : "square")
                        Text(label)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 11.5))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 140, alignment: .leading)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Theme.surfaceHi(colorScheme), in: RoundedRectangle(cornerRadius: 5))
        .overlay(
            RoundedRectangle(cornerRadius: 5).stroke(Theme.hairline(colorScheme), lineWidth: 0.5)
        )
    }

    private func summary(for items: [String], placeholder: String) -> String {
        guard !items.isEmpty else { return placeholder }
        if items.count <= 2 { return items.joined(separator: ", ") }
        return "\(items.count) selected"
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if canDelete {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Text("Delete")
                        .font(.system(size: 11.5))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.red.opacity(0.9))
            }
            Spacer()
            Button("Cancel") { onCancel() }
                .controlSize(.small)
            Button("Save") { attemptSave() }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, contentHorizontalPadding)
        .padding(.vertical, 8)
    }

    private var canDelete: Bool {
        onDelete != nil && (mode.section?.isDefault == false)
    }

    private var canSave: Bool {
        let parsed = filters.map { draft in
            draft.conditions.compactMap { $0.toCondition() }
        }
        let hasInvalid = parsed.contains { $0.isEmpty } || parsed.count != filters.count
        let mismatchedCounts = zip(parsed, filters).contains { $0.count != $1.conditions.count }
        return !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !filters.isEmpty
            && !hasInvalid
            && !mismatchedCounts
    }

    private func attemptSave() {
        let parsedFilters = filters.compactMap { draft -> SectionFilter? in
            let conditions = draft.conditions.compactMap { $0.toCondition() }
            guard !conditions.isEmpty, conditions.count == draft.conditions.count else { return nil }
            return SectionFilter(conditions: conditions)
        }
        guard parsedFilters.count == filters.count else { return }

        switch mode {
        case .create(let tab):
            let created = GitbarSection(
                id: UUID(),
                name: name.trimmingCharacters(in: .whitespaces),
                icon: icon,
                tab: tab,
                repos: .defaults,
                filters: parsedFilters,
                visibility: visibility,
                contributesToBadge: contributesToBadge,
                sort: .updatedDesc,
                collapsed: visibility == .collapsedByDefault,
                order: 0
            )
            onSave(created)
        case .edit(let section):
            var updated = section
            updated.name = name.trimmingCharacters(in: .whitespaces)
            updated.icon = icon
            updated.filters = parsedFilters
            updated.visibility = visibility
            updated.contributesToBadge = contributesToBadge
            onSave(updated)
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.primary.opacity(0.8))
    }

    fileprivate static func defaultCondition(for tab: PanelTab) -> ConditionDraft {
        switch tab {
        case .issues:
            var draft = ConditionDraft()
            draft.field = .assignee
            return draft
        case .mine, .review, .all, .stats:
            return ConditionDraft()
        }
    }

    fileprivate static func availableFields(for tab: PanelTab) -> [ConditionDraft.Field] {
        switch tab {
        case .issues:
            return [.prStatus, .author, .assignee, .repository, .label]
        case .mine:
            return [.prStatus, .author, .assignee, .repository, .label, .ciStatus, .draft]
        case .review:
            return [.prStatus, .author, .assignee, .repository, .label, .reviewer, .reviewedBy, .ciStatus, .draft, .reviewedByMeState]
        case .all, .stats:
            return [.prStatus, .author, .repository, .label]
        }
    }

    /// Fields hidden from the picker on a widened Review-tab section because they require
    /// per-PR metadata that isn't fetched for outside-queue PRs. Existing instances of these
    /// on a now-widened section render an inline warning row instead.
    fileprivate static let metadataDependentFields: Set<ConditionDraft.Field> = [
        .ciStatus, .mergeConflict, .reviewedByMeState
    ]

    private var visibilityHint: String {
        switch visibility {
        case .visible: return "Section shows expanded in the tab."
        case .collapsedByDefault: return "Section shows collapsed until you expand it."
        case .hidden: return "Section doesn't render in the panel."
        }
    }
}

struct FilterDraft: Identifiable, Equatable {
    var id: UUID = UUID()
    var conditions: [ConditionDraft] = [ConditionDraft()]

    init() {}

    init(defaultCondition: ConditionDraft) {
        conditions = [defaultCondition]
    }

    init(from filter: SectionFilter, tab: PanelTab) {
        let allowed = Set(SectionEditorView.availableFields(for: tab))
        let existing = filter.conditions.map(ConditionDraft.init(from:)).map { draft in
            var normalized = draft
            if !allowed.contains(normalized.field) {
                normalized.field = SectionEditorView.defaultCondition(for: tab).field
            }
            return normalized
        }
        conditions = existing.isEmpty ? [ConditionDraft()] : existing
    }
}

struct ConditionDraft: Identifiable, Equatable {
    var id: UUID = UUID()
    var field: Field = .prStatus
    var setOp: SectionSetOp = .includes
    var eqOp: SectionEqOp = .is_
    var prStatuses: Set<SectionPRStatusValue> = [.open]
    var ciStatuses: Set<CIPillKind> = [.fail]
    var authorLogin: String = ""
    var reviewerLogin: String = ""
    var assigneeLogin: String = ""
    var repositoryText: String = ""
    var labelName: String = ""
    var isDraftValue: Bool = true
    var hasMergeConflictValue: Bool = true
    var reviewedByMeStates: Set<ReviewedByMeStateValue> = [.changesRequested, .commented]
    var reviewedByLogin: String = "@me"

    enum Field: String, CaseIterable, Identifiable, Hashable {
        case prStatus, author, reviewer, assignee, repository, label, ciStatus, draft, mergeConflict, reviewedByMeState
        case reviewedBy

        var id: String { rawValue }
        func label(for tab: PanelTab) -> String {
            switch self {
            case .prStatus: return tab == .issues ? "Issue status" : "PR status"
            case .author: return "Author"
            case .reviewer: return "Direct reviewer"
            case .assignee: return "Assignee"
            case .repository: return "Repository"
            case .label: return "Label"
            case .ciStatus: return "CI status"
            case .draft: return "Draft"
            case .mergeConflict: return "Merge conflict"
            case .reviewedByMeState: return "Your review"
            case .reviewedBy: return "Reviewed by"
            }
        }
    }

    init() {}

    init(from condition: SectionCondition) {
        switch condition {
        case .prStatus(let op, let values):
            field = .prStatus
            setOp = op
            prStatuses = Set(values)
        case .author(let op, let login):
            field = .author
            eqOp = op
            authorLogin = login
        case .reviewer(let op, let login):
            field = .reviewer
            setOp = op
            reviewerLogin = login
        case .ciStatus(let op, let values):
            field = .ciStatus
            setOp = op
            ciStatuses = Set(values)
        case .draft(let isDraft):
            field = .draft
            isDraftValue = isDraft
        case .label(let op, let name):
            field = .label
            setOp = op
            labelName = name
        case .assignee(let op, let login):
            field = .assignee
            setOp = op
            assigneeLogin = login
        case .repository(let op, let repos):
            field = .repository
            setOp = op
            repositoryText = repos.joined(separator: ", ")
        case .hasMergeConflict(let isOn):
            field = .mergeConflict
            hasMergeConflictValue = isOn
        case .reviewedByMeState(let op, let values):
            field = .reviewedByMeState
            setOp = op
            reviewedByMeStates = Set(values)
        case .reviewedBy(let op, let login):
            field = .reviewedBy
            eqOp = op
            reviewedByLogin = login
        }
    }

    /// True when this draft would produce a scoping condition (repo / author / assignee /
    /// label / reviewer / reviewedBy) with a non-empty value. Mirrors `SectionCondition.isScoping`
    /// for the editor's live state — used to flip the widening notice and metadata-field hiding
    /// as the user types.
    var isScopingDraft: Bool {
        switch field {
        case .repository:
            return repositoryText
                .split(separator: ",")
                .contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        case .author:
            return !authorLogin.trimmingCharacters(in: .whitespaces).isEmpty
        case .assignee:
            return !assigneeLogin.trimmingCharacters(in: .whitespaces).isEmpty
        case .label:
            return !labelName.trimmingCharacters(in: .whitespaces).isEmpty
        case .reviewer:
            return !reviewerLogin.trimmingCharacters(in: .whitespaces).isEmpty
        case .reviewedBy:
            return !reviewedByLogin.trimmingCharacters(in: .whitespaces).isEmpty
        case .prStatus, .ciStatus, .draft, .mergeConflict, .reviewedByMeState:
            return false
        }
    }

    func toCondition() -> SectionCondition? {
        switch field {
        case .prStatus:
            guard !prStatuses.isEmpty else { return nil }
            return .prStatus(op: setOp, values: Array(prStatuses))
        case .author:
            let trimmed = authorLogin.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            return .author(op: eqOp, login: trimmed)
        case .reviewer:
            let trimmed = reviewerLogin.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            return .reviewer(op: setOp, login: trimmed)
        case .ciStatus:
            guard !ciStatuses.isEmpty else { return nil }
            return .ciStatus(op: setOp, values: Array(ciStatuses))
        case .draft:
            return .draft(is: isDraftValue)
        case .label:
            let trimmed = labelName.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            return .label(op: setOp, name: trimmed)
        case .assignee:
            let trimmed = assigneeLogin.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            return .assignee(op: setOp, login: trimmed)
        case .repository:
            let repos = repositoryText
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard !repos.isEmpty else { return nil }
            return .repository(op: setOp, repos: repos)
        case .mergeConflict:
            return .hasMergeConflict(is: hasMergeConflictValue)
        case .reviewedByMeState:
            guard !reviewedByMeStates.isEmpty else { return nil }
            return .reviewedByMeState(op: setOp, values: Array(reviewedByMeStates))
        case .reviewedBy:
            let trimmed = reviewedByLogin.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            return .reviewedBy(op: eqOp, login: trimmed)
        }
    }
}
