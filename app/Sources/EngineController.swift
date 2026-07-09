import SwiftUI
import Observation

enum WorkspaceState: Equatable {
    case idle
    case engineMissing(String)
    case loading(current: Int, total: Int)
    case ready
}

@MainActor
@Observable
final class EngineController {
    var state: WorkspaceState = .idle
    var errorToast: String? = nil
    var capabilities: InitializeResult? = nil
    var unityVersion: String? = nil
    var onExportProgress: ((ProgressNote) -> Void)? = nil   // Task 10 wires this

    // MARK: Memoized data pipeline (didSet → recompute) — preserved from Task 2.

    /// All assets in the loaded workspace. Assigning triggers a recompute of the
    /// memoized `typeCounts` and `visibleRows`.
    var rows: [AssetRow] = [] {
        didSet {
            recomputeTypeCounts()
            recomputeVisible()
        }
    }

    var searchText = "" {
        didSet { recomputeVisible() }
    }

    var selectedType: String? = nil {
        didSet { recomputeVisible() }
    }

    var selection: AssetRow.ID? = nil

    var sortOrder: [KeyPathComparator<AssetRow>] = [KeyPathComparator(\.name)] {
        didSet { recomputeVisible() }
    }

    /// Assets matching the current type filter and search text, sorted by
    /// `sortOrder`. Memoized: recomputed only when an input changes (`rows`,
    /// `searchText`, `selectedType`, `sortOrder`), so reads from `body` are O(1).
    private(set) var visibleRows: [AssetRow] = []

    /// `(type, count)` pairs over all loaded `rows`, sorted by type. Memoized:
    /// recomputed only when `rows` changes.
    private(set) var typeCounts: [(type: String, count: Int)] = []

    private func recomputeVisible() {
        var out = rows
        if let t = selectedType { out = out.filter { $0.type == t } }
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            out = out.filter {
                $0.name.lowercased().contains(q)
                    || $0.container.lowercased().contains(q)
                    || String($0.pathId).contains(q)
            }
        }
        visibleRows = out.sorted(using: sortOrder)
    }

    private func recomputeTypeCounts() {
        typeCounts = Dictionary(grouping: rows, by: \.type)
            .map { (type: $0.key, count: $0.value.count) }
            .sorted { $0.type < $1.type }
    }

    // MARK: Engine lifecycle + data flow.

    private var client: EngineClient? = nil

    func engineClient() -> EngineClient? { client }

    func startEngineIfNeeded() async {
        guard client == nil else { return }
        guard let url = EngineClient.defaultEngineURL() else {
            state = .engineMissing("engine URL unavailable"); return
        }
        // EngineClient is single-use: every (re)start constructs a fresh instance.
        let c = EngineClient()
        do {
            try await c.start(engineURL: url)
            client = c
            capabilities = try await c.initialize()
            listenForNotifications(c)
            listenForExit(c)
        } catch {
            state = .engineMissing(error.localizedDescription)
        }
    }

    private func listenForNotifications(_ c: EngineClient) {
        Task { [weak self] in
            for await note in c.notifications {
                guard let self else { return }
                switch note {
                case .progress(let p) where p.token == "load":
                    if case .loading = self.state { self.state = .loading(current: p.current, total: p.total) }
                case .progress(let p) where p.token == "export":
                    self.onExportProgress?(p)
                case .log(let l) where l.level == "error":
                    NSLog("[engine:error] %@", l.message)
                default: break
                }
            }
        }
    }

    private func listenForExit(_ c: EngineClient) {
        Task { [weak self] in
            for await code in c.processExited {
                guard let self else { return }
                self.client = nil
                self.errorToast = "Engine exited unexpectedly (code \(code)). It will relaunch on the next load."
                self.state = .idle
            }
        }
    }

    func openFiles(_ urls: [URL]) async {
        await startEngineIfNeeded()
        guard let c = client else { return }
        state = .loading(current: 0, total: 0)
        selection = nil
        rows = []
        do {
            let load = try await c.load(paths: urls.map(\.path))
            unityVersion = load.unityVersion
            var all: [AssetRow] = []
            var offset = 0
            while true {
                let page = try await c.list(offset: offset, limit: 5000)
                all.append(contentsOf: page.rows)
                offset += page.rows.count
                if offset >= page.total || page.rows.isEmpty { break }
            }
            rows = all
            state = .ready
            if load.loadedFiles == 0 {
                errorToast = "No loadable Unity files found in the selection."
            }
        } catch {
            state = rows.isEmpty ? .idle : .ready
            errorToast = error.localizedDescription
        }
    }

    func presentOpenPanel(directories: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = !directories
        panel.canChooseDirectories = directories
        panel.allowsMultipleSelection = true
        panel.prompt = "Load"
        if panel.runModal() == .OK {
            let urls = panel.urls
            Task { await self.openFiles(urls) }
        }
    }

    func resetWorkspace() async {
        rows = []; selection = nil; unityVersion = nil; state = .idle
        if let c = client { try? await c.reset() }
    }
}
