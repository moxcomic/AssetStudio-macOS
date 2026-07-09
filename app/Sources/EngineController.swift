import SwiftUI
import Observation

enum WorkspaceState: Equatable {
    case idle
    case engineMissing(String)
    case loading(current: Int, total: Int)
    case ready
}

enum PreviewState: Equatable {
    case empty
    case loading
    case image(NSImage, PreviewMeta)
    case text(String, PreviewMeta)
    case none(PreviewMeta)
    case failed(String)

    static func == (l: Self, r: Self) -> Bool {
        switch (l, r) {
        case (.empty, .empty), (.loading, .loading): true
        case (.image(let a, let m1), .image(let b, let m2)): a === b && m1.pathId == m2.pathId
        case (.text(let a, let m1), .text(let b, let m2)): a == b && m1.pathId == m2.pathId
        case (.none(let m1), .none(let m2)): m1.pathId == m2.pathId
        case (.failed(let a), .failed(let b)): a == b
        default: false
        }
    }
}

@MainActor
@Observable
final class EngineController {
    var state: WorkspaceState = .idle
    var errorToast: String? = nil
    var capabilities: InitializeResult? = nil
    var unityVersion: String? = nil

    /// Detail-pane preview for the current selection. Driven by `selectionChanged()`.
    var preview: PreviewState = .empty

    /// Assign with `[weak self]` inside the closure to avoid a retain cycle:
    /// the controller owns the client whose notifications feed this back. (Task 10)
    var onExportProgress: ((ProgressNote) -> Void)? = nil

    /// assets/list page size — one place to tune the pagination granularity.
    private static let pageSize = 5000

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
    /// `sortOrder`. Memoized: recomputed only when an input changes.
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

    @ObservationIgnored private var client: (any EngineServicing)? = nil
    @ObservationIgnored private let injectedClient: (any EngineServicing)?

    /// Monotonic token: bumped whenever a load or reset starts. Any in-flight
    /// `openFiles` compares its captured token before each post-`await` mutation
    /// and bails if a newer load/reset superseded it, so results from a stale
    /// engine workspace can never overwrite the current one.
    @ObservationIgnored private var loadGeneration = 0

    /// The in-flight preview request; cancelled and replaced on each selection change.
    @ObservationIgnored private var previewTask: Task<Void, Never>? = nil

    init(injectedClient: (any EngineServicing)? = nil) {
        self.injectedClient = injectedClient
    }

    func engineClient() -> (any EngineServicing)? { client }

    func startEngineIfNeeded() async {
        guard client == nil else { return }
        let c: any EngineServicing
        if let injected = injectedClient {
            c = injected
        } else {
            guard let url = EngineClient.defaultEngineURL() else {
                state = .engineMissing("engine URL unavailable"); return
            }
            // EngineClient is single-use: every (re)start constructs a fresh instance.
            let real = EngineClient()
            do {
                try await real.start(engineURL: url)
            } catch {
                state = .engineMissing(error.localizedDescription); return
            }
            c = real
        }
        do {
            capabilities = try await c.initialize()   // assign client only once usable
            client = c
            listenForNotifications(c)
            listenForExit(c)
        } catch {
            // initialize() failed after a successful start(): terminate the child
            // now, else it is orphaned for the app's lifetime (client stays nil, so
            // the app-quit shutdownEngine() could never reach it).
            await c.shutdown()
            state = .engineMissing(error.localizedDescription)
        }
    }

    private func listenForNotifications(_ c: any EngineServicing) {
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

    private func listenForExit(_ c: any EngineServicing) {
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
        loadGeneration += 1
        let gen = loadGeneration
        state = .loading(current: 0, total: 0)
        do {
            let load = try await c.load(paths: urls.map(\.path), unityVersion: nil, loadAll: false)
            guard gen == loadGeneration else { return }
            var all: [AssetRow] = []
            var offset = 0
            while true {
                let page = try await c.list(offset: offset, limit: Self.pageSize)
                guard gen == loadGeneration else { return }   // a newer load/reset superseded us
                all.append(contentsOf: page.rows)
                offset += page.rows.count
                if offset >= page.total || page.rows.isEmpty { break }
            }
            guard gen == loadGeneration else { return }
            // Clear/replace only on success, so a failed reload preserves the
            // previously loaded workspace instead of wiping it.
            selection = nil
            previewTask?.cancel()
            preview = .empty
            rows = all
            unityVersion = load.unityVersion
            state = .ready
            if load.loadedFiles == 0 {
                errorToast = "No loadable Unity files found in the selection."
            }
        } catch {
            guard gen == loadGeneration else { return }
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
        // Bump the token first so any in-flight openFiles bails instead of
        // resuming and silently undoing this reset.
        loadGeneration += 1
        rows = []
        selection = nil
        previewTask?.cancel()
        preview = .empty
        unityVersion = nil
        state = .idle
        if let c = client { try? await c.reset() }
    }

    /// Terminate the engine child cleanly. Called at app quit (see AppDelegate).
    func shutdownEngine() async {
        await client?.shutdown()
        client = nil
    }

    /// Requests a preview for the current selection, coalescing rapid changes
    /// (each call cancels the prior request) and dropping results from a stale
    /// selection or a superseded workspace generation. A missing temp file (the
    /// engine deletes preview paths on the next load/reset) surfaces as an
    /// expired-preview state rather than a hard error.
    func selectionChanged() {
        previewTask?.cancel()
        guard let id = selection, let c = client else { preview = .empty; return }
        preview = .loading
        let gen = loadGeneration
        previewTask = Task { [weak self] in
            do {
                let r = try await c.preview(id: id)
                guard !Task.isCancelled, let self, gen == self.loadGeneration else { return }
                switch r.kind {
                case "image":
                    if let path = r.path, let img = NSImage(contentsOfFile: path) {
                        self.preview = .image(img, r.meta)
                    } else {
                        self.preview = .failed("Preview expired — reselect the asset")
                    }
                case "text":
                    if let inline = r.text {
                        self.preview = .text(inline, r.meta)
                    } else if let path = r.path,
                              let s = try? String(contentsOfFile: path, encoding: .utf8) {
                        self.preview = .text(s, r.meta)
                    } else {
                        self.preview = .failed("Preview expired — reselect the asset")
                    }
                default:
                    self.preview = .none(r.meta)
                }
            } catch is CancellationError {
            } catch {
                guard let self, !Task.isCancelled, gen == self.loadGeneration else { return }
                self.preview = .failed(error.localizedDescription)
            }
        }
    }
}
