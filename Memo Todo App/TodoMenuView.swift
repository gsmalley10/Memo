import SwiftUI

/// The panel's contents. Spacing follows the design mock; the comments give the target
/// positions in points from the panel's left edge.
struct TodoMenuView: View {
    @Bindable var store: TodoStore
    let panelState: PanelState

    /// Keyed by category ID; nil is the uncategorized add field.
    @State private var newItemTitles: [TaskCategory.ID?: String] = [:]
    @State private var newItemPriority: TaskPriority = .medium
    @FocusState private var focusedAddField: AddField?

    @State private var editingItemID: TodoItem.ID?
    @State private var editingTitle = ""
    @FocusState private var focusedItemID: TodoItem.ID?

    @State private var datePickerItemID: TodoItem.ID?
    @State private var hoveredItemID: TodoItem.ID?

    @Environment(\.openSettings) private var openSettings

    private func displayedItems(in category: TaskCategory?) -> [TodoItem] {
        let items = store.items(in: category)
        guard store.completedTaskBehavior == .hideImmediately else { return items }
        return items.filter { !$0.isCompleted }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    uncategorizedSection

                    ForEach(store.categories) { category in
                        categorySection(category)
                            .padding(.top, 8.25)
                    }
                }
                .reorderContainer(for: TodoItem.self) { difference in
                    applyReorder(difference)
                }
                .padding(.top, 7)
                .padding(.bottom, 8)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: panelState.maxListHeight)
            .fixedSize(horizontal: false, vertical: true)

            Button(action: { store.undo() }) { EmptyView() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!store.canUndo)
                .frame(width: 0, height: 0)
                .opacity(0)

            Button(action: { NSApplication.shared.terminate(nil) }) { EmptyView() }
                .keyboardShortcut("q")
                .frame(width: 0, height: 0)
                .opacity(0)
        }
        .onChange(of: focusedItemID) { oldValue, newValue in
            guard let editingItemID, oldValue == editingItemID, newValue != editingItemID,
                  let item = store.items.first(where: { $0.id == editingItemID }) else { return }
            commitEdit(for: item)
        }
        .onAppear {
            newItemPriority = store.defaultPriority
        }
        .onReceive(NotificationCenter.default.publisher(for: .memoOpenSettings)) { _ in
            openSettings()
        }
    }

    /// Tasks without a category sit above the categories, with no header.
    private var uncategorizedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(displayedItems(in: nil)) { item in
                row(for: item)
            }
            .reorderable()

            addRow(for: nil)
        }
    }

    @ViewBuilder
    private func categorySection(_ category: TaskCategory) -> some View {
        let isCollapsed = store.collapsedCategoryIDs.contains(category.id)

        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(category, isCollapsed: isCollapsed)

            if !isCollapsed {
                ForEach(displayedItems(in: category)) { item in
                    row(for: item)
                }
                .reorderable()

                addRow(for: category)
            }
        }
    }

    // Chevron centred at x 20.25, name at x 32.5, rule running to x 336.
    private func sectionHeader(_ category: TaskCategory, isCollapsed: Bool) -> some View {
        let openCount = store.items(in: category).filter { !$0.isCompleted }.count

        return Button {
            withAnimation(.snappy(duration: 0.2)) {
                store.toggleCollapsed(category)
            }
        } label: {
            HStack(spacing: 0) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(category.color.color.opacity(0.6))
                    .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                    .frame(width: 7)

                Text(category.displayName.uppercased())
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.2)
                    .foregroundStyle(category.color.color)
                    .padding(.leading, 8.75)

                Text("\(openCount)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.leading, 5.5)

                Rectangle()
                    .fill(Theme.rule)
                    .frame(height: 1)
                    .padding(.leading, 7)
            }
            .padding(.leading, 16.75)
            .padding(.trailing, 14.5)
            .frame(height: 25.5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // Plus centred on the checkbox column, placeholder at x 41.
    private func addRow(for category: TaskCategory?) -> some View {
        let field = AddField(category)

        return HStack(spacing: 0) {
            Image(systemName: "plus")
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(category?.color.color.opacity(0.6) ?? Theme.secondaryText)
                .frame(width: 14)

            TextField(
                "",
                text: newItemTitleBinding(for: category),
                prompt: Text(category.map { "add to \($0.displayName.lowercased())..." } ?? "add task...")
                    .foregroundStyle(Theme.placeholderText)
            )
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(Theme.primaryText)
            .focused($focusedAddField, equals: field)
            .onSubmit { addItem(to: category) }
            .padding(.leading, 11.5)

            if store.showPriority, focusedAddField == field {
                priorityMenu
            }
        }
        .padding(.leading, 8.5)
        .padding(.trailing, 8)
        .frame(height: 30)
        .padding(.horizontal, 7)
        .padding(.top, 2)
    }

    private var priorityMenu: some View {
        Menu {
            Picker("Priority", selection: $newItemPriority) {
                ForEach(TaskPriority.allCases) { priority in
                    Text(priority.label).tag(priority)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Circle()
                .fill(newItemPriority.color)
                .frame(width: 8, height: 8)
                .padding(4)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Priority: \(newItemPriority.label)")
    }

    // 30pt rows: 14pt checkbox at x 15.5, title at x 41.
    private func row(for item: TodoItem) -> some View {
        HStack(spacing: 0) {
            Button {
                store.toggle(item)
            } label: {
                ZStack {
                    if item.isCompleted {
                        Circle()
                            .fill(Theme.checkboxFill)
                        Image(systemName: "checkmark")
                            .font(.system(size: 5.5, weight: .heavy))
                            .foregroundStyle(Theme.checkmark)
                    } else {
                        Circle()
                            .strokeBorder(Theme.checkboxStroke, lineWidth: 1.5)
                    }
                }
                .frame(width: 14, height: 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if store.showPriority {
                Circle()
                    .fill(item.priority.color)
                    .frame(width: 8, height: 8)
                    .padding(.leading, 11.5)
            }

            Group {
                if editingItemID == item.id {
                    TextField("Title", text: $editingTitle)
                        .textFieldStyle(.plain)
                        .foregroundStyle(Theme.primaryText)
                        .focused($focusedItemID, equals: item.id)
                        .onSubmit { commitEdit(for: item) }
                } else {
                    Text(item.title)
                        .strikethrough(item.isCompleted, color: Theme.completedText)
                        .foregroundStyle(item.isCompleted ? Theme.completedText : Theme.primaryText)
                        .contentShape(Rectangle())
                        .onTapGesture { startEditing(item) }
                }
            }
            .font(.system(size: 14))
            .padding(.leading, store.showPriority ? 8 : 11.5)

            Spacer(minLength: 8)

            if store.showDueDates {
                Button {
                    datePickerItemID = item.id
                } label: {
                    if let dueDate = item.dueDate {
                        Text(Self.dueDateLabel(dueDate))
                            .font(.system(size: 11))
                            .foregroundStyle(item.isOverdue ? CategoryColor.red.color : Theme.secondaryText)
                    } else {
                        Image(systemName: "calendar.badge.plus")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.secondaryText)
                            .opacity(0.6)
                    }
                }
                .buttonStyle(.plain)
                .popover(isPresented: Binding(
                    get: { datePickerItemID == item.id },
                    set: { if !$0 { datePickerItemID = nil } }
                )) {
                    dueDatePicker(for: item)
                }
                .padding(.trailing, 8)
            }

            Button {
                store.delete(item)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(hoveredItemID == item.id ? 1 : 0)
            .allowsHitTesting(hoveredItemID == item.id)
        }
        .padding(.vertical, 6)
        .padding(.leading, 8.5)
        .padding(.trailing, 8)
        .frame(minHeight: 30)
        .hoverHighlight()
        .padding(.horizontal, 7)
        .onHover { isHovered in
            if isHovered {
                hoveredItemID = item.id
            } else if hoveredItemID == item.id {
                hoveredItemID = nil
            }
        }
    }

    private func dueDatePicker(for item: TodoItem) -> some View {
        VStack(spacing: 8) {
            DatePicker(
                "Due Date",
                selection: Binding(
                    get: { item.dueDate ?? Date() },
                    set: { store.setDueDate(of: item, to: $0) }
                ),
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()

            Button("Clear Due Date") {
                store.setDueDate(of: item, to: nil)
                datePickerItemID = nil
            }
            .disabled(item.dueDate == nil)
        }
        .padding(12)
    }

    private static func dueDateLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    private func newItemTitleBinding(for category: TaskCategory?) -> Binding<String> {
        Binding(
            get: { newItemTitles[category?.id, default: ""] },
            set: { newItemTitles[category?.id] = $0 }
        )
    }

    private func addItem(to category: TaskCategory?) {
        store.addItem(newItemTitles[category?.id, default: ""], priority: newItemPriority, category: category)
        newItemTitles[category?.id] = ""
        newItemPriority = store.defaultPriority
        focusedAddField = AddField(category)
    }

    private func startEditing(_ item: TodoItem) {
        editingItemID = item.id
        editingTitle = item.title
        focusedItemID = item.id
    }

    private func commitEdit(for item: TodoItem) {
        store.updateTitle(of: item, to: editingTitle)
        if editingItemID == item.id {
            editingItemID = nil
        }
    }

    private func applyReorder(_ difference: ReorderDifference<TodoItem.ID, ReorderableSingleCollectionIdentifier>) {
        let movingIDs = Set(difference.sources)
        guard !movingIDs.isEmpty else { return }

        var moved: [TodoItem] = []
        store.items.removeAll { item in
            guard movingIDs.contains(item.id) else { return false }
            moved.append(item)
            return true
        }

        switch difference.destination.position {
        case .before(let id):
            // Dropping onto a task in another category (or none) moves the dragged tasks there.
            if let target = store.items.first(where: { $0.id == id }) {
                for index in moved.indices {
                    moved[index].categoryID = target.categoryID
                }
            }
            let index = store.items.firstIndex { $0.id == id } ?? store.items.endIndex
            store.items.insert(contentsOf: moved, at: index)
        case .end:
            store.items.append(contentsOf: moved)
        }
    }
}

/// Identifies an "add" field for focus: one per category, plus the uncategorized one.
private enum AddField: Hashable {
    case uncategorized
    case category(TaskCategory.ID)

    init(_ category: TaskCategory?) {
        self = category.map { .category($0.id) } ?? .uncategorized
    }
}

private struct HoverHighlight: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isHovered ? Theme.hover : Color.clear)
            )
            .onHover { isHovered = $0 }
    }
}

private extension View {
    func hoverHighlight() -> some View {
        modifier(HoverHighlight())
    }
}

#Preview {
    PanelChrome(state: PanelState()) {
        TodoMenuView(store: TodoStore(), panelState: PanelState())
    }
}
