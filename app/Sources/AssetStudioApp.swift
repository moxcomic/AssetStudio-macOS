import SwiftUI
import AppKit

@main
struct AssetStudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var controller = EngineController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(controller)
                .task { await controller.startEngineIfNeeded() }
                .onAppear { appDelegate.controller = controller }
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

/// Terminates the engine child on app quit. `EngineClient.shutdown()` is async,
/// so we defer termination via `.terminateLater` and reply once cleanup finishes
/// — the idiomatic macOS hook for async teardown (no main-thread blocking).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var controller: EngineController?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let controller, controller.engineClient() != nil else { return .terminateNow }
        Task {
            await controller.shutdownEngine()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
