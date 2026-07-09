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

    init(loadResult: LoadResult, pages: [ListResult], gateLoad: Bool = false) {
        (notifications, notifyCont) = AsyncStream.makeStream(of: EngineNotification.self)
        (processExited, exitCont) = AsyncStream.makeStream(of: Int32.self)
        self.loadResult = loadResult
        self.pages = pages
        self.gateLoad = gateLoad
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
        PreviewResult(kind: "none", path: nil, text: nil,
                      meta: PreviewMeta(name: "", type: "", container: "", pathId: 0, size: 0, extra: [:]))
    }
    func export(_ params: ExportParams) async throws -> ExportResult {
        ExportResult(exported: 0, skipped: 0, errors: [])
    }
    func cancel(requestID: Int) async {}
    func shutdown() async { shutdownCalled = true }

    func emitExit(_ code: Int32) { exitCont.yield(code) }
}

@MainActor
final class EngineControllerServiceTests: XCTestCase {
    private func row(_ id: Int, _ name: String, _ type: String) -> AssetRow {
        AssetRow(id: id, name: name, container: "c/\(name)", type: type,
                 pathId: Int64(id), size: 100, sourceFile: "f.assets")
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
}
