import SwiftUI
import Observation

enum ExportPhase: Equatable {
    case idle
    case running(current: Int, total: Int)
    case finished(ExportSummary)
}

struct ExportSummary: Equatable {
    let exported: Int
    let skipped: Int
    let errors: [ExportErrorEntry]
    let destination: URL
    static func == (l: Self, r: Self) -> Bool {
        l.exported == r.exported && l.skipped == r.skipped
            && l.errors.map(\.id) == r.errors.map(\.id) && l.destination == r.destination
    }
}

@MainActor
@Observable
final class ExportCoordinator {
    var phase: ExportPhase = .idle
    var showReport = false
    @ObservationIgnored private var inFlight: EngineClient.InFlightExport? = nil
    @ObservationIgnored var currentController: EngineController? = nil

    /// Prompts for a destination directory, then hands off to `start`.
    func begin(ids: [Int], mode: String, controller: EngineController) {
        guard !ids.isEmpty, case .idle = phase, controller.engineClient() != nil else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        start(ids: ids, mode: mode, controller: controller, destination: dest)
    }

    /// Destination-driven export (no panel) — the seam that tests drive directly.
    func start(ids: [Int], mode: String, controller: EngineController, destination dest: URL) {
        guard !ids.isEmpty, case .idle = phase, let client = controller.engineClient() else { return }
        currentController = controller
        let d = UserDefaults.standard
        let params = ExportParams(ids: ids, mode: mode, destDir: dest.path,
                                  groupBy: d.string(forKey: "export.groupBy") ?? "containerPath",
                                  imageFormat: d.string(forKey: "export.imageFormat") ?? "png")
        phase = .running(current: 0, total: ids.count)
        Task {
            do {
                let flight = try await client.startExport(params)
                self.inFlight = flight
                let result = try await flight.result.value
                self.phase = .finished(ExportSummary(exported: result.exported, skipped: result.skipped,
                                                     errors: result.errors, destination: dest))
            } catch {
                let msg = (error as? EngineError)?.errorDescription ?? error.localizedDescription
                self.phase = .finished(ExportSummary(exported: 0, skipped: 0,
                    errors: [ExportErrorEntry(id: -1, name: "export", message: msg)], destination: dest))
            }
            self.inFlight = nil
            self.showReport = true
        }
    }

    func updateProgress(_ note: ProgressNote) {
        if case .running = phase, note.token == "export" {
            phase = .running(current: note.current, total: note.total)
        }
    }

    func cancel() {
        guard let flight = inFlight, let client = currentController?.engineClient() else { return }
        Task { await client.cancel(requestID: flight.requestID) }
    }

    func acknowledge() { showReport = false; phase = .idle }
}
