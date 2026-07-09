import XCTest
@testable import AssetStudio

/// In-memory EngineServicing fake so controller behavior (pagination, toast,
/// exit handling) is testable without a live engine process.
actor FakeEngine: EngineServicing {
    let notifications: AsyncStream<EngineNotification>
    private let notifyCont: AsyncStream<EngineNotification>.Continuation
    let processExited: AsyncStream<Int32>
    private let exitCont: AsyncStream<Int32>.Continuation

    private let loadResult: LoadResult
    private let pages: [ListResult]
    private var listCalls = 0
    private(set) var shutdownCalled = false

    // Optional gate so a test can park load() mid-flight (generation-guard test).
    private let gateLoad: Bool
    private(set) var loadEntered = false
    private var gateWaiter: CheckedContinuation<Void, Never>?

    // Optional preview scripting + gate (preview-expiry / preview-supersession tests).
    private let previewResult: PreviewResult
    private let gatePreview: Bool
    private(set) var previewEntered = false
    private var previewGateWaiter: CheckedContinuation<Void, Never>?

    // Export scripting + gate (export coordinator tests).
    private let exportResult: ExportResult
    private let exportError: EngineError?
    private let gateExport: Bool
    private(set) var exportStarted = false
    private(set) var cancelledRequestID: Int? = nil
    private var exportGateWaiter: CheckedContinuation<Void, Never>?

    init(loadResult: LoadResult, pages: [ListResult], gateLoad: Bool = false,
         previewResult: PreviewResult = PreviewResult(kind: "none", path: nil, text: nil,
             meta: PreviewMeta(name: "", type: "", container: "", pathId: 0, size: 0, extra: [:])),
         gatePreview: Bool = false,
         exportResult: ExportResult = ExportResult(exported: 0, skipped: 0, errors: []),
         exportError: EngineError? = nil,
         gateExport: Bool = false) {
        (notifications, notifyCont) = AsyncStream.makeStream(of: EngineNotification.self)
        (processExited, exitCont) = AsyncStream.makeStream(of: Int32.self)
        self.loadResult = loadResult
        self.pages = pages
        self.gateLoad = gateLoad
        self.previewResult = previewResult
        self.gatePreview = gatePreview
        self.exportResult = exportResult
        self.exportError = exportError
        self.gateExport = gateExport
    }

    func initialize() async throws -> InitializeResult {
        InitializeResult(engineVersion: "fake", coreVersion: "fake",
                         natives: NativeCaps(texture: true, fbx: true, fmod: true))
    }
    func load(paths: [String], unityVersion: String?, loadAll: Bool) async throws -> LoadResult {
        loadEntered = true
        if gateLoad {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in gateWaiter = cont }
        }
        return loadResult
    }

    func openGate() {
        gateWaiter?.resume()
        gateWaiter = nil
    }
    func list(offset: Int, limit: Int) async throws -> ListResult {
        defer { listCalls += 1 }
        return listCalls < pages.count ? pages[listCalls] : ListResult(total: pages.last?.total ?? 0, rows: [])
    }
    func reset() async throws {}
    func preview(id: Int) async throws -> PreviewResult {
        previewEntered = true
        if gatePreview {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in previewGateWaiter = cont }
        }
        return previewResult
    }

    func openPreviewGate() {
        previewGateWaiter?.resume()
        previewGateWaiter = nil
    }
    func export(_ params: ExportParams) async throws -> ExportResult {
        ExportResult(exported: 0, skipped: 0, errors: [])
    }
    func cancel(requestID: Int) async { cancelledRequestID = requestID }
    func shutdown() async { shutdownCalled = true }

    func startExport(_ params: ExportParams) async throws -> EngineClient.InFlightExport {
        exportStarted = true
        let result = exportResult
        let error = exportError
        let gate = gateExport
        return EngineClient.InFlightExport(requestID: 777, result: Task { [weak self] in
            if gate { await self?.awaitExportGate() }
            if let error { throw error }
            return result
        })
    }

    private func awaitExportGate() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in exportGateWaiter = cont }
    }
    func openExportGate() {
        exportGateWaiter?.resume()
        exportGateWaiter = nil
    }

    func emitExit(_ code: Int32) { exitCont.yield(code) }
}

@MainActor
final class EngineControllerServiceTests: XCTestCase {
    private func row(_ id: Int, _ name: String, _ type: String) -> AssetRow {
        AssetRow(id: id, name: name, container: "c/\(name)", type: type,
                 pathId: Int64(id), size: 100, sourceFile: "f.assets")
    }

    private func meta(_ pathId: Int64) -> PreviewMeta {
        PreviewMeta(name: "n", type: "Texture2D", container: "c", pathId: pathId, size: 10, extra: [:])
    }

    func testPaginationAccumulatesAcrossPages() async {
        let page0 = ListResult(total: 3, rows: [row(1, "a", "Texture2D"), row(2, "b", "Texture2D")])
        let page1 = ListResult(total: 3, rows: [row(3, "c", "Mesh")])
        let fake = FakeEngine(loadResult: LoadResult(loadedFiles: 1, assetCount: 3, unityVersion: "2020.1"),
                              pages: [page0, page1])
        let controller = EngineController(injectedClient: fake)
        await controller.openFiles([URL(fileURLWithPath: "/tmp/x")])
        XCTAssertEqual(controller.rows.count, 3)
        XCTAssertEqual(controller.rows.map(\.id).sorted(), [1, 2, 3])
        XCTAssertEqual(controller.unityVersion, "2020.1")
        XCTAssertEqual(controller.state, .ready)
        XCTAssertNil(controller.errorToast)
    }

    func testZeroLoadedFilesShowsToast() async {
        let fake = FakeEngine(loadResult: LoadResult(loadedFiles: 0, assetCount: 0, unityVersion: nil),
                              pages: [ListResult(total: 0, rows: [])])
        let controller = EngineController(injectedClient: fake)
        await controller.openFiles([URL(fileURLWithPath: "/tmp/none")])
        XCTAssertTrue(controller.rows.isEmpty)
        XCTAssertEqual(controller.state, .ready)
        XCTAssertEqual(controller.errorToast, "No loadable Unity files found in the selection.")
    }

    func testEngineExitClearsClientAndToasts() async {
        let fake = FakeEngine(loadResult: LoadResult(loadedFiles: 1, assetCount: 1, unityVersion: "x"),
                              pages: [ListResult(total: 1, rows: [row(1, "a", "Texture2D")])])
        let controller = EngineController(injectedClient: fake)
        await controller.startEngineIfNeeded()
        XCTAssertNotNil(controller.engineClient())
        await fake.emitExit(42)
        for _ in 0..<400 {                                   // poll up to ~2s for the exit listener
            if controller.engineClient() == nil { break }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertNil(controller.engineClient())
        XCTAssertEqual(controller.state, .idle)
        XCTAssertNotNil(controller.errorToast)
    }

    func testSupersededLoadWritesNothing() async {
        // Load A parks inside the gated load(); a reset bumps loadGeneration while A
        // is suspended, so when A resumes it must observe the newer generation and
        // leave rows/state/unityVersion untouched.
        let fake = FakeEngine(loadResult: LoadResult(loadedFiles: 1, assetCount: 2, unityVersion: "A-version"),
                              pages: [ListResult(total: 2, rows: [row(1, "a", "Texture2D"), row(2, "b", "Texture2D")])],
                              gateLoad: true)
        let controller = EngineController(injectedClient: fake)
        let loadA = Task { await controller.openFiles([URL(fileURLWithPath: "/tmp/a")]) }

        for _ in 0..<400 {                                   // wait until A is parked inside load()
            if await fake.loadEntered { break }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        await controller.resetWorkspace()                    // bumps loadGeneration, clears workspace
        await fake.openGate()                                // let A resume
        await loadA.value

        XCTAssertTrue(controller.rows.isEmpty, "superseded load must not populate rows")
        XCTAssertEqual(controller.state, .idle, "reset's state must survive the superseded load")
        XCTAssertNil(controller.unityVersion, "superseded load must not set unityVersion")
    }

    func testImagePreviewMissingFileFails() async {
        // Engine reports an image preview but the temp file is gone (expired): the
        // NSImage load fails and the pane lands in .failed instead of crashing.
        let bogus = PreviewResult(kind: "image", path: "/nonexistent/preview.png", text: nil, meta: meta(7))
        let fake = FakeEngine(loadResult: LoadResult(loadedFiles: 1, assetCount: 1, unityVersion: "x"),
                              pages: [ListResult(total: 1, rows: [row(7, "t", "Texture2D")])],
                              previewResult: bogus)
        let controller = EngineController(injectedClient: fake)
        await controller.startEngineIfNeeded()
        controller.selection = 7
        controller.selectionChanged()
        for _ in 0..<400 {
            if case .failed = controller.preview { break }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        guard case .failed = controller.preview else {
            return XCTFail("expected .failed, got \(controller.preview)")
        }
    }

    func testTextPreviewInlineLandsInTextState() async {
        let txt = PreviewResult(kind: "text", path: nil, text: "hello\nworld", meta: meta(11))
        let fake = FakeEngine(loadResult: LoadResult(loadedFiles: 1, assetCount: 1, unityVersion: "x"),
                              pages: [ListResult(total: 1, rows: [row(11, "t", "TextAsset")])],
                              previewResult: txt)
        let controller = EngineController(injectedClient: fake)
        await controller.startEngineIfNeeded()
        controller.selection = 11
        controller.selectionChanged()
        for _ in 0..<400 {
            if case .text = controller.preview { break }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        guard case .text(let s, let m) = controller.preview else {
            return XCTFail("expected .text, got \(controller.preview)")
        }
        XCTAssertEqual(s, "hello\nworld")
        XCTAssertEqual(m.pathId, 11)
    }

    func testSupersededPreviewWritesNothing() async {
        // A preview parks in the gated preview(); a reset bumps the generation and
        // cancels the task, so on resume it must not overwrite the reset's .empty.
        let img = PreviewResult(kind: "image", path: "/nonexistent/preview.png", text: nil, meta: meta(9))
        let fake = FakeEngine(loadResult: LoadResult(loadedFiles: 1, assetCount: 1, unityVersion: "x"),
                              pages: [ListResult(total: 1, rows: [row(9, "t", "Texture2D")])],
                              previewResult: img, gatePreview: true)
        let controller = EngineController(injectedClient: fake)
        await controller.startEngineIfNeeded()
        controller.selection = 9
        controller.selectionChanged()                        // preview = .loading, parks in preview()
        for _ in 0..<400 {
            if await fake.previewEntered { break }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        await controller.resetWorkspace()                    // bumps generation, cancels task, preview = .empty
        await fake.openPreviewGate()                         // let the preview task resume
        for _ in 0..<20 { try? await Task.sleep(nanoseconds: 5_000_000) }   // let it run to completion
        XCTAssertEqual(controller.preview, .empty, "superseded preview must not overwrite the reset state")
    }

    // MARK: Export coordinator

    private func settle(_ cond: () async -> Bool) async {
        for _ in 0..<400 {
            if await cond() { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    func testExportCoordinatorFinishesWithSummary() async {
        let fake = FakeEngine(loadResult: LoadResult(loadedFiles: 1, assetCount: 3, unityVersion: "x"),
                              pages: [ListResult(total: 0, rows: [])],
                              exportResult: ExportResult(exported: 5, skipped: 1, errors: []))
        let controller = EngineController(injectedClient: fake)
        await controller.startEngineIfNeeded()
        let exporter = ExportCoordinator()
        exporter.start(ids: [1, 2, 3], mode: "convert", controller: controller,
                       destination: URL(fileURLWithPath: "/tmp/export-test"))
        await settle { if case .finished = exporter.phase { return true }; return false }
        guard case .finished(let summary) = exporter.phase else {
            return XCTFail("expected .finished, got \(exporter.phase)")
        }
        XCTAssertEqual(summary.exported, 5)
        XCTAssertEqual(summary.skipped, 1)
        XCTAssertTrue(summary.errors.isEmpty)
        XCTAssertTrue(exporter.showReport)
    }

    func testExportCoordinatorSurfacesEngineError() async {
        let fake = FakeEngine(loadResult: LoadResult(loadedFiles: 1, assetCount: 1, unityVersion: "x"),
                              pages: [ListResult(total: 0, rows: [])],
                              exportError: EngineError(code: "CANCELLED", message: "export cancelled"))
        let controller = EngineController(injectedClient: fake)
        await controller.startEngineIfNeeded()
        let exporter = ExportCoordinator()
        exporter.start(ids: [1], mode: "convert", controller: controller,
                       destination: URL(fileURLWithPath: "/tmp/export-test"))
        await settle { if case .finished = exporter.phase { return true }; return false }
        guard case .finished(let summary) = exporter.phase else {
            return XCTFail("expected .finished, got \(exporter.phase)")
        }
        XCTAssertEqual(summary.exported, 0)
        XCTAssertEqual(summary.errors.count, 1)
        XCTAssertTrue(summary.errors[0].message.contains("CANCELLED"))
    }

    func testExportCoordinatorCancelSendsRequestID() async {
        let fake = FakeEngine(loadResult: LoadResult(loadedFiles: 1, assetCount: 3, unityVersion: "x"),
                              pages: [ListResult(total: 0, rows: [])],
                              gateExport: true)
        let controller = EngineController(injectedClient: fake)
        await controller.startEngineIfNeeded()
        let exporter = ExportCoordinator()
        exporter.start(ids: [1, 2, 3], mode: "convert", controller: controller,
                       destination: URL(fileURLWithPath: "/tmp/export-test"))
        await settle { await fake.exportStarted }
        for _ in 0..<10 { try? await Task.sleep(nanoseconds: 5_000_000) }   // let the coordinator record inFlight
        exporter.cancel()
        await settle { await fake.cancelledRequestID != nil }
        await fake.openExportGate()   // let the export finish so nothing dangles
        let cancelled = await fake.cancelledRequestID
        XCTAssertEqual(cancelled, 777)
    }
}
