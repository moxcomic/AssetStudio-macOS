import SwiftUI
import Observation

enum ExportPhase: Equatable {
    case idle
    case running(current: Int, total: Int)
    case finished(ExportSummary)
}

struct ExportSummary: Equatable, Identifiable {
    let id = UUID()
    let exported: Int
    let skipped: Int
    let errors: [ExportErrorEntry]
    let destination: URL
    var cancelled = false
    static func == (l: Self, r: Self) -> Bool {
        l.exported == r.exported && l.skipped == r.skipped
            && l.errors.map(\.id) == r.errors.map(\.id) && l.destination == r.destination
            && l.cancelled == r.cancelled
    }
}

@MainActor
@Observable
final class ExportCoordinator {
    var phase: ExportPhase = .idle
    /// Non-nil drives the report sheet via `.sheet(item:)` — no fragile
    /// showReport/phase pattern-match coupling.
    var report: ExportSummary? = nil
    /// True from Cancel-clicked until the export resolves — for the HUD button.
    var cancelling = false
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
        cancelling = false
        let d = UserDefaults.standard
        let params = ExportParams(ids: ids, mode: mode, destDir: dest.path,
                                  groupBy: d.string(forKey: "export.groupBy") ?? "containerPath",
                                  imageFormat: d.string(forKey: "export.imageFormat") ?? "png")
        phase = .running(current: 0, total: ids.count)
        Task {
            let summary: ExportSummary
            do {
                let flight = try await client.startExport(params)
                self.inFlight = flight
                let result = try await flight.result.value
                summary = ExportSummary(exported: result.exported, skipped: result.skipped,
                                        errors: result.errors, destination: dest)
            } catch let e as EngineError where e.code == "CANCELLED" {
                // First-class outcome — a deliberate cancel is not a failure.
                summary = ExportSummary(exported: 0, skipped: 0, errors: [],
                                        destination: dest, cancelled: true)
            } catch {
                let msg = (error as? EngineError)?.errorDescription ?? error.localizedDescription
                summary = ExportSummary(exported: 0, skipped: 0,
                    errors: [ExportErrorEntry(id: -1, name: "export", message: msg)], destination: dest)
            }
            self.inFlight = nil
            self.cancelling = false
            self.phase = .finished(summary)
            self.report = summary
        }
    }

    func updateProgress(_ note: ProgressNote) {
        if case .running = phase, note.token == "export" {
            phase = .running(current: note.current, total: note.total)
        }
    }

    func cancel() {
        guard let flight = inFlight, let client = currentController?.engineClient() else { return }
        cancelling = true
        Task { await client.cancel(requestID: flight.requestID) }
    }

    func acknowledge() {
        report = nil
        phase = .idle
    }
}
