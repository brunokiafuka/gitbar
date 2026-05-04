import SwiftUI

struct SectionsManagerView: View {
    let onCreate: (PanelTab) -> Void
    let onEdit: (GitbarSection) -> Void
    let onBack: () -> Void

    @EnvironmentObject var store: Store
    @Environment(\.colorScheme) private var colorScheme
    @State private var dropTargetID: UUID?
    @State private var dropAppendTab: PanelTab?
    @State private var pendingDelete: GitbarSection?

    private let tabs: [PanelTab] = [.mine, .review, .issues]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.hairline(colorScheme))
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(tabs) { tab in
                        tabGroup(for: tab)
                    }
                    Color.clear.frame(height: 6)
                }
                .padding(14)
            }
        }
        .alert("Delete filter?", isPresented: deleteAlertBinding, presenting: pendingDelete) { section in
            Button("Delete", role: .destructive) {
                store.deleteSection(id: section.id, tab: section.tab)
            }
            Button("Cancel", role: .cancel) {}
        } message: { section in
            Text("\"\(section.name)\" will be removed. This can't be undone.")
        }
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Back")

            Text("Manage sections")
                .font(.system(size: 13, weight: .semibold))
            Text("Create and edit filters by tab")
                .font(.system(size: 11))
                .foregroundStyle(Theme.meta)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func tabGroup(for tab: PanelTab) -> some View {
        let sections = store.sections(for: tab)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(tab.label.uppercased())
                    .font(.system(size: 9.5, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Theme.meta)
                Text("\(sections.count)")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(Theme.meta)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Theme.surfaceHi(colorScheme), in: Capsule())
                Spacer()
                Button {
                    onCreate(tab)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Add")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(Theme.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.blue.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .help("New section in \(tab.label)")
            }
            if sections.isEmpty {
                emptyRow(tab: tab)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                        row(section)
                        if index < sections.count - 1 {
                            Divider().overlay(Theme.hairline(colorScheme))
                        }
                    }
                    appendDropZone(tab: tab)
                }
                .background(Theme.surfaceHi(colorScheme).opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Theme.hairline(colorScheme), lineWidth: 0.5)
                )
            }
        }
    }

    @ViewBuilder
    private func appendDropZone(tab: PanelTab) -> some View {
        let targeted = dropAppendTab == tab
        Rectangle()
            .fill(targeted ? Theme.blue.opacity(0.15) : Color.clear)
            .frame(height: targeted ? 10 : 4)
            .overlay(alignment: .top) {
                if targeted {
                    Rectangle().fill(Theme.blue).frame(height: 2)
                }
            }
            .dropDestination(for: String.self) { items, _ in
                guard let str = items.first,
                      let id = UUID(uuidString: str) else { return false }
                store.reorderSection(in: tab, moving: id, before: nil)
                return true
            } isTargeted: { isIn in
                if isIn { dropAppendTab = tab }
                else if dropAppendTab == tab { dropAppendTab = nil }
            }
    }

    @ViewBuilder
    private func row(_ section: GitbarSection) -> some View {
        let isTarget = dropTargetID == section.id
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.meta.opacity(0.7))
                .frame(width: 12)
            if let icon = section.icon, !icon.isEmpty {
                Text(icon)
                    .font(.system(size: 14))
                    .frame(width: 18)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(section.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                Text(summary(for: section))
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.meta)
            }
            Spacer(minLength: 8)
            if section.isDefault {
                pill("Default", color: Theme.blue)
            }
            if section.effectiveContributesToBadge {
                pill("Badge", color: Theme.amber)
            }
            visibilityMenu(for: section)
            Menu {
                Button("Edit…") { onEdit(section) }
                if !section.isDefault {
                    Divider()
                    Button("Delete", role: .destructive) {
                        pendingDelete = section
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.faint)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .overlay(alignment: .top) {
            if isTarget {
                Rectangle().fill(Theme.blue).frame(height: 2)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onEdit(section) }
        .draggable(section.id.uuidString)
        .dropDestination(for: String.self) { items, _ in
            guard let str = items.first,
                  let id = UUID(uuidString: str),
                  id != section.id else { return false }
            store.reorderSection(in: section.tab, moving: id, before: section.id)
            return true
        } isTargeted: { isIn in
            if isIn { dropTargetID = section.id }
            else if dropTargetID == section.id { dropTargetID = nil }
        }
    }

    @ViewBuilder
    private func visibilityMenu(for section: GitbarSection) -> some View {
        Menu {
            ForEach(SectionVisibility.allCases, id: \.self) { option in
                Button {
                    updateVisibility(for: section, to: option)
                } label: {
                    if section.visibility == option {
                        Label(visibilityLabel(option), systemImage: "checkmark")
                    } else {
                        Text(visibilityLabel(option))
                    }
                }
            }
        } label: {
            pill(visibilityLabel(section.visibility), color: .secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func updateVisibility(for section: GitbarSection, to visibility: SectionVisibility) {
        guard section.visibility != visibility else { return }
        var updated = section
        updated.visibility = visibility
        switch visibility {
        case .visible: updated.collapsed = false
        case .collapsedByDefault: updated.collapsed = true
        case .hidden: break
        }
        store.updateSection(updated)
    }

    private func pill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.14), in: Capsule())
    }

    private func emptyRow(tab: PanelTab) -> some View {
        Button {
            onCreate(tab)
        } label: {
            HStack {
                Image(systemName: "plus.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.meta)
                Text("No sections yet - create one")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.meta)
                Spacer()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(Theme.surfaceHi(colorScheme).opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Theme.hairline(colorScheme), style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
        )
        .buttonStyle(.plain)
    }

    private func summary(for section: GitbarSection) -> String {
        let count = section.filters.first?.conditions.count ?? 0
        switch count {
        case 0: return "No conditions"
        case 1: return "1 condition"
        default: return "\(count) conditions"
        }
    }

    private func visibilityLabel(_ v: SectionVisibility) -> String {
        switch v {
        case .visible: return "Visible"
        case .collapsedByDefault: return "Collapsed"
        case .hidden: return "Hidden"
        }
    }
}
