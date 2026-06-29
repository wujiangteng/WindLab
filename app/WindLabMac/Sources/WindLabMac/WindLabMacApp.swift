import SwiftUI

@MainActor
final class WindLabFileOpenCoordinator: ObservableObject {
    static let shared = WindLabFileOpenCoordinator()

    @Published var requestedURL: URL?

    func open(_ url: URL) {
        requestedURL = url
    }
}

@MainActor
final class WindLabAppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        WindLabFileOpenCoordinator.shared.open(url)
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        guard let filename = filenames.first else {
            sender.reply(toOpenOrPrint: .failure)
            return
        }

        WindLabFileOpenCoordinator.shared.open(URL(fileURLWithPath: filename))
        NSApp.activate(ignoringOtherApps: true)
        sender.reply(toOpenOrPrint: .success)
    }
}

@main
struct WindLabMacApp: App {
    @NSApplicationDelegateAdaptor(WindLabAppDelegate.self) private var appDelegate
    @StateObject private var fileOpenCoordinator = WindLabFileOpenCoordinator.shared

    var body: some Scene {
        WindowGroup("WindLab") {
            ContentView()
                .environmentObject(fileOpenCoordinator)
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
