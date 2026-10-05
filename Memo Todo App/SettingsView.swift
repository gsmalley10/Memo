import SwiftUI

struct SettingsView: View {
    @Bindable var store: TodoStore

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at Startup", isOn: $store.launchAtStartup)
                    .toggleStyle(.checkbox)
                Toggle("Show Counter in Menu Bar", isOn: $store.showCounter)
                    .toggleStyle(.checkbox)
                Toggle("Play Sound on Task Completion", isOn: $store.playSoundOnCompletion)
                    .toggleStyle(.checkbox)

                Slider(value: $store.soundVolume, in: 0...1) {
                    Text("Sound Volume")
                }
                .disabled(!store.playSoundOnCompletion)
            }

            Section("Categories") {
                ForEach($store.categories) { $category in
                    categoryRow($category)
                }

                Button("Add Category") {
                    store.addCategory()
                }
            }

            Section("Features") {
                Toggle("Show Priority", isOn: $store.showPriority)
                    .toggleStyle(.checkbox)
                Toggle("Show Due Dates", isOn: $store.showDueDates)
                    .toggleStyle(.checkbox)
            }

            Section("Task Defaults") {
                Picker("Menu Bar Icon", selection: $store.menuBarIconStyle) {
                    ForEach(MenuBarIconStyle.allCases) { style in
                        Label {
                            Text(style.label)
                        } icon: {
                            if let systemImageName = style.systemImageName {
                                Image(systemName: systemImageName)
                            } else {
                                Image("MenuBarIcon")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 16, height: 16)
                            }
                        }
                        .tag(style)
                    }
                }

                if store.showPriority {
                    Picker("Default Priority", selection: $store.defaultPriority) {
                        ForEach(TaskPriority.allCases) { priority in
                            Label {
                                Text(priority.label)
                            } icon: {
                                Circle()
                                    .fill(priority.color)
                                    .frame(width: 8, height: 8)
                            }
                            .tag(priority)
                        }
                    }
                }

                Picker("When Task Completed", selection: $store.completedTaskBehavior) {
                    ForEach(CompletedTaskBehavior.allCases) { behavior in
                        Text(behavior.label).tag(behavior)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
        .onDisappear {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private func categoryRow(_ category: Binding<TaskCategory>) -> some View {
        HStack(spacing: 8) {
            Menu {
                Picker("Color", selection: category.color) {
                    ForEach(CategoryColor.allCases) { color in
                        Text(color.label).tag(color)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                Circle()
                    .fill(category.wrappedValue.color.color)
                    .frame(width: 12, height: 12)
                    .padding(2)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Color")

            TextField("Category Name", text: category.name)
                .textFieldStyle(.roundedBorder)
                .labelsHidden()

            Button {
                store.removeCategory(category.wrappedValue)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Remove Category (its tasks become uncategorized)")
        }
    }
}

#Preview {
    SettingsView(store: TodoStore())
}
