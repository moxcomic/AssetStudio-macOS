import SwiftUI
import AppKit

@main
struct AssetStudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var controller = EngineController()
    @State private var exporter = ExportCoordinator()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(controller)
                .environment(exporter)
                .task {
                    controller.onExportProgress = { [weak exporter] note in exporter?.updateProgress(note) }
                    exporter.currentController = controller
                    await controller.startEngineIfNeeded()
                }
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
            CommandMenu("Export") {
                Button("Export Selected…") { exportSelected("convert") }
                    .keyboardShortcut("e")
                    .disabled(controller.selection == nil)
                Button("Export Filtered…") {
                    exporter.begin(ids: controller.visibleRows.map(\.id), mode: "convert", controller: controller)
                }
                .disabled(controller.visibleRows.isEmpty)
                Button("Export All…") {
                    exporter.begin(ids: controller.rows.map(\.id), mode: "convert", controller: controller)
                }
                .disabled(controller.rows.isEmpty)
                Divider()
                Button("Export Raw Selected…") { exportSelected("raw") }
                    .disabled(controller.selection == nil)
                Button("Dump Selected…") { exportSelected("dump") }
                    .disabled(controller.selection == nil)
            }
        }

        Settings {
            SettingsView()
        }
    }

    private func exportSelected(_ mode: String) {
        let ids = controller.selection.map { [$0] } ?? []
        exporter.begin(ids: ids, mode: mode, controller: controller)
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
