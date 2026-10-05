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
        .frame(width: 500, height: 560)
        .onDisappear {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

#Preview {
    SettingsView(store: TodoStore())
}
