import SwiftUI

@main
struct AssetStudioApp: App {
    @State private var controller = EngineController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(controller)
                .task { await controller.startEngineIfNeeded() }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Files…") { controller.presentOpenPanel(directories: false) }
                    .keyboardShortcut("o")
                Button("Open Folder…") { controller.presentOpenPanel(directories: true) }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                Divider()
                Button("Reset Workspace") { Task { await controller.resetWorkspace() } }
                    .keyboardShortcut("w", modifiers: [.command, .option])
            }
        }
    }
}
