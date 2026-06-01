import SwiftUI

@main
struct WindLabMacApp: App {
    var body: some Scene {
        WindowGroup("WindLab") {
            ContentView()
                .frame(minWidth: 1180, minHeight: 760)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Windographer File...") {
                    NotificationCenter.default.post(name: .openWindogRequested, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            CommandMenu("Revise") {
                Button("Undo Flag Change") {}
                Button("Apply Revision") {}
            }

            CommandMenu("Flag") {
                Button("Flag Calm Data") {}
                Button("Clear Flags") {}
            }

            CommandMenu("Analyze") {
                Button("Wind Shear Profile") {}
                Button("Monthly Means") {}
                Button("Diurnal Profile") {}
            }

            CommandMenu("Compare") {
                Button("Compare Sensors") {}
            }
        }
    }
}
