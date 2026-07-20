import SwiftUI

@MainActor
final class WindLabFileOpenCoordinator: ObservableObject {
    static let shared = WindLabFileOpenCoordinator()

    @Published private(set) var openPanelRequestID = 0
    @Published private(set) var saveRequestID = 0
    @Published private(set) var saveAsRequestID = 0
    @Published var requestedURL: URL?
    @Published private(set) var recentFiles: [URL]

    private let recentFilesKey = "recentWindogFiles"

    private init() {
        let paths = UserDefaults.standard.stringArray(forKey: recentFilesKey) ?? []
        recentFiles = paths.map(URL.init(fileURLWithPath:))
    }

    func requestOpenPanel() {
        openPanelRequestID += 1
    }

    func requestSave() {
        saveRequestID += 1
    }

    func requestSaveAs() {
        saveAsRequestID += 1
    }

    func open(_ url: URL) {
        requestedURL = url
    }

    func noteOpened(_ url: URL) {
        let fileURL = url.standardizedFileURL
        recentFiles.removeAll { $0.standardizedFileURL.path == fileURL.path }
        recentFiles.insert(fileURL, at: 0)
        recentFiles = Array(recentFiles.prefix(10))
        UserDefaults.standard.set(recentFiles.map(\.path), forKey: recentFilesKey)
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
                    fileOpenCoordinator.requestOpenPanel()
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("Save") {
                    fileOpenCoordinator.requestSave()
                }
                .keyboardShortcut("s", modifiers: .command)

                Button("Save As...") {
                    fileOpenCoordinator.requestSaveAs()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Menu("Open Recent") {
                    if fileOpenCoordinator.recentFiles.isEmpty {
                        Text("No Recent Files")
                    } else {
                        ForEach(fileOpenCoordinator.recentFiles, id: \.self) { url in
                            Button(url.lastPathComponent) {
                                fileOpenCoordinator.open(url)
                            }
                            .help(url.path)
                        }
                    }
                }
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
