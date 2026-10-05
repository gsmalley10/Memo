import AppKit
import Observation
import ServiceManagement

@Observable
final class TodoStore {
    var items: [TodoItem] = [] {
        didSet { save() }
    }

    var categories: [TaskCategory] = [] {
        didSet { saveCategories() }
    }

    var collapsedCategoryIDs: Set<TaskCategory.ID> {
        didSet {
            guard collapsedCategoryIDs != oldValue else { return }
            UserDefaults.standard.set(collapsedCategoryIDs.map(\.uuidString), forKey: collapsedCategoryIDsKey)
        }
    }

    var launchAtStartup: Bool {
        didSet {
            guard launchAtStartup != oldValue else { return }
            setLaunchAtStartup(launchAtStartup)
        }
    }

    var menuBarIconStyle: MenuBarIconStyle {
        didSet {
            guard menuBarIconStyle != oldValue else { return }
            UserDefaults.standard.set(menuBarIconStyle.rawValue, forKey: menuBarIconStyleKey)
        }
    }

    var showCounter: Bool {
        didSet {
            guard showCounter != oldValue else { return }
            UserDefaults.standard.set(showCounter, forKey: showCounterKey)
        }
    }

    var defaultPriority: TaskPriority {
        didSet {
            guard defaultPriority != oldValue else { return }
            UserDefaults.standard.set(defaultPriority.rawValue, forKey: defaultPriorityKey)
        }
    }

    var showPriority: Bool {
        didSet {
            guard showPriority != oldValue else { return }
            UserDefaults.standard.set(showPriority, forKey: showPriorityKey)
        }
    }

    var showDueDates: Bool {
        didSet {
            guard showDueDates != oldValue else { return }
            UserDefaults.standard.set(showDueDates, forKey: showDueDatesKey)
        }
    }

    var completedTaskBehavior: CompletedTaskBehavior {
        didSet {
            guard completedTaskBehavior != oldValue else { return }
            UserDefaults.standard.set(completedTaskBehavior.rawValue, forKey: completedTaskBehaviorKey)
        }
    }

    var playSoundOnCompletion: Bool {
        didSet {
            guard playSoundOnCompletion != oldValue else { return }
            UserDefaults.standard.set(playSoundOnCompletion, forKey: playSoundOnCompletionKey)
        }
    }

    var soundVolume: Double {
        didSet {
            guard soundVolume != oldValue else { return }
            UserDefaults.standard.set(soundVolume, forKey: soundVolumeKey)
        }
    }

    var completedCount: Int {
        items.filter(\.isCompleted).count
    }


    private static let maxUndoDepth = 20
    private var undoStack: [[TodoItem]] = []

    private let defaultsKey = "todoItems"
    private let categoriesKey = "categories"
    private let collapsedCategoryIDsKey = "collapsedCategoryIDs"
    private let menuBarIconStyleKey = "menuBarIconStyle"
    private let showCounterKey = "showCounter"
    private let defaultPriorityKey = "defaultPriority"
    private let showPriorityKey = "showPriority"
    private let showDueDatesKey = "showDueDates"
    private let completedTaskBehaviorKey = "completedTaskBehavior"
    private let playSoundOnCompletionKey = "playSoundOnCompletion"
    private let soundVolumeKey = "soundVolume"
    @ObservationIgnored
    private lazy var completionSound = NSSound(named: "Glass")

    init() {
        launchAtStartup = SMAppService.mainApp.status == .enabled
        if let rawValue = UserDefaults.standard.string(forKey: menuBarIconStyleKey),
           let style = MenuBarIconStyle(rawValue: rawValue) {
            menuBarIconStyle = style
        } else {
            menuBarIconStyle = .custom
        }
        showCounter = UserDefaults.standard.object(forKey: showCounterKey) as? Bool ?? true
        if let rawValue = UserDefaults.standard.string(forKey: defaultPriorityKey),
           let priority = TaskPriority(rawValue: rawValue) {
            defaultPriority = priority
        } else {
            defaultPriority = .medium
        }
        showPriority = UserDefaults.standard.object(forKey: showPriorityKey) as? Bool ?? true
        showDueDates = UserDefaults.standard.object(forKey: showDueDatesKey) as? Bool ?? true
        if let rawValue = UserDefaults.standard.string(forKey: completedTaskBehaviorKey),
           let behavior = CompletedTaskBehavior(rawValue: rawValue) {
            completedTaskBehavior = behavior
        } else {
            completedTaskBehavior = .keepInPlace
        }
        playSoundOnCompletion = UserDefaults.standard.object(forKey: playSoundOnCompletionKey) as? Bool ?? false
        soundVolume = UserDefaults.standard.object(forKey: soundVolumeKey) as? Double ?? 1.0
        let collapsed = UserDefaults.standard.stringArray(forKey: collapsedCategoryIDsKey) ?? []
        collapsedCategoryIDs = Set(collapsed.compactMap(UUID.init(uuidString:)))
        loadCategories()
        load()
        clearMissingCategories()
    }

    func addItem(_ title: String, priority: TaskPriority, category: TaskCategory?) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        items.append(TodoItem(title: trimmed, priority: priority, categoryID: category?.id))
    }

    /// Tasks in the category, or the uncategorized tasks when `category` is nil. A task whose
    /// category no longer exists (e.g. restored by undo) counts as uncategorized.
    func items(in category: TaskCategory?) -> [TodoItem] {
        if let category {
            return items.filter { $0.categoryID == category.id }
        }
        let validIDs = Set(categories.map(\.id))
        return items.filter { item in
            item.categoryID.map { !validIDs.contains($0) } ?? true
        }
    }

    func addCategory() {
        let usedColors = Set(categories.map(\.color))
        let color = CategoryColor.allCases.first { !usedColors.contains($0) }
            ?? CategoryColor.allCases[categories.count % CategoryColor.allCases.count]
        categories.append(TaskCategory(name: "New Category", color: color))
    }

    /// Removes the category; its tasks become uncategorized.
    func removeCategory(_ category: TaskCategory) {
        categories.removeAll { $0.id == category.id }
        for index in items.indices where items[index].categoryID == category.id {
            items[index].categoryID = nil
        }
        collapsedCategoryIDs.remove(category.id)
    }

    func toggleCollapsed(_ category: TaskCategory) {
        if collapsedCategoryIDs.contains(category.id) {
            collapsedCategoryIDs.remove(category.id)
        } else {
            collapsedCategoryIDs.insert(category.id)
        }
    }

    func toggle(_ item: TodoItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isCompleted.toggle()
        let isNowCompleted = items[index].isCompleted

        if isNowCompleted, playSoundOnCompletion {
            playCompletionSound()
        }

        if isNowCompleted, completedTaskBehavior == .moveToBottom {
            let moved = items.remove(at: index)
            items.append(moved)
        }
    }

    func delete(_ item: TodoItem) {
        pushUndoSnapshot()
        items.removeAll { $0.id == item.id }
    }

    func clearCompleted() {
        pushUndoSnapshot()
        items.removeAll { $0.isCompleted }
    }

    var canUndo: Bool { !undoStack.isEmpty }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        items = previous
    }

    private func pushUndoSnapshot() {
        undoStack.append(items)
        if undoStack.count > Self.maxUndoDepth {
            undoStack.removeFirst()
        }
    }

    func updateTitle(of item: TodoItem, to newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].title = trimmed
    }

    func setDueDate(of item: TodoItem, to date: Date?) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].dueDate = date.map { Calendar.current.startOfDay(for: $0) }
    }

    private func playCompletionSound() {
        guard let completionSound else { return }
        completionSound.stop()
        completionSound.volume = Float(soundVolume)
        completionSound.play()
    }

    private func setLaunchAtStartup(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to update launch at startup: \(error)")
        }
    }

    /// Tasks pointing at a category that no longer exists become uncategorized.
    private func clearMissingCategories() {
        let validIDs = Set(categories.map(\.id))
        let isOrphaned: (TodoItem) -> Bool = { item in
            item.categoryID.map { !validIDs.contains($0) } ?? false
        }
        guard items.contains(where: isOrphaned) else { return }
        for index in items.indices where isOrphaned(items[index]) {
            items[index].categoryID = nil
        }
    }

    private func saveCategories() {
        guard let data = try? JSONEncoder().encode(categories) else { return }
        UserDefaults.standard.set(data, forKey: categoriesKey)
    }

    private func loadCategories() {
        if let data = UserDefaults.standard.data(forKey: categoriesKey),
           let decoded = try? JSONDecoder().decode([TaskCategory].self, from: data) {
            categories = decoded
        } else {
            categories = TaskCategory.defaults
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([TodoItem].self, from: data) else {
            items = []
            return
        }
        items = decoded
    }
}
