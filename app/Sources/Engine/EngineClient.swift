import Foundation

/// JSON-RPC 2.0 client over a child engine process's stdio (LSP-style framing).
///
/// Lifecycle contract: an `EngineClient` is **single-use**. Call `start` exactly
/// once; a second `start`, or a restart after the process exits, throws
/// `ENGINE_ALREADY_STARTED` because the underlying `Process` cannot be reused —
/// create a fresh instance to restart. `shutdown()` is **required** before
/// dropping a running client: there is no `deinit` teardown, so dropping a
/// running client without `shutdown()` leaks the child process and its reader
/// sources. (Best-effort teardown, a SIGKILL fallback, and per-request timeouts
/// are Task 7's lifecycle work.)
actor EngineClient: EngineServicing {
    enum State { case notStarted, running, exited(Int32) }

    private let process = Process()
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private var parser = FrameParser()
    private var nextID = 1
    private var pending: [Int: CheckedContinuation<Data, Error>] = [:]
    private(set) var state: State = .notStarted

    let notifications: AsyncStream<EngineNotification>
    private let notifyCont: AsyncStream<EngineNotification>.Continuation
    let processExited: AsyncStream<Int32>
    private let exitCont: AsyncStream<Int32>.Continuation

    init() {
        (notifications, notifyCont) = AsyncStream.makeStream(of: EngineNotification.self)
        (processExited, exitCont) = AsyncStream.makeStream(of: Int32.self)
    }

    static func defaultEngineURL() -> URL? {
        if let env = ProcessInfo.processInfo.environment["ASSETSTUDIO_ENGINE_PATH"] {
            return URL(fileURLWithPath: env)
        }
        return Bundle.main.resourceURL?
            .appendingPathComponent("engine/AssetStudioEngine")
    }

    func start(engineURL: URL) throws {
        guard case .notStarted = state else {
            throw EngineError(code: "ENGINE_ALREADY_STARTED",
                              message: "EngineClient is single-use; create a new instance to restart")
        }
        guard FileManager.default.isExecutableFile(atPath: engineURL.path) else {
            throw EngineError(code: "ENGINE_MISSING", message: "engine not found at \(engineURL.path)")
        }
        process.executableURL = engineURL
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let (bytes, byteCont) = AsyncStream.makeStream(of: Data.self)
        // Self-clear at EOF (empty availableData). Otherwise the dispatch read
        // source stays armed after the engine exits and fires continuously with
        // empty data, pinning a core. Clearing here — rather than in handleExit —
        // also avoids dropping a final buffered stdout frame still queued in the
        // pipe when termination is observed.
        stdoutPipe.fileHandleForReading.readabilityHandler = { fh in
            let data = fh.availableData
            if data.isEmpty {
                fh.readabilityHandler = nil
                byteCont.finish()
            } else {
                byteCont.yield(data)
            }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { fh in
            let data = fh.availableData
            guard !data.isEmpty else { fh.readabilityHandler = nil; return }
            let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .newlines)
            if !text.isEmpty { NSLog("[engine] %@", text) }
        }
        process.terminationHandler = { [weak self] p in
            let code = p.terminationStatus
            Task { await self?.handleExit(code) }
        }
        do {
            try process.run()
        } catch {
            // Back out partial setup so a failed launch leaves no armed reader
            // sources or termination handler behind.
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            process.terminationHandler = nil
            byteCont.finish()
            throw error
        }
        // Do not regress out of .exited: a near-instant termination handler is
        // serialized behind this actor-isolated call and will set .exited only
        // after start() returns, so advance to .running only from .notStarted.
        if case .notStarted = state { state = .running }
        Task { [weak self] in
            for await chunk in bytes { await self?.ingest(chunk) }
        }
    }

    private func handleExit(_ code: Int32) {
        state = .exited(code)
        // Ordering caveat (deferred): a final buffered response may still be
        // in-flight in the byte stream when we fail pending requests here, so an
        // in-flight call can surface ENGINE_EXITED instead of its real result.
        // Task 7's supervision UX covers the user-visible effect.
        for (_, cont) in pending {
            cont.resume(throwing: EngineError(code: "ENGINE_EXITED", message: "engine exited (\(code))"))
        }
        pending.removeAll()
        exitCont.yield(code)
    }

    private func ingest(_ chunk: Data) {
        for frame in parser.feed(chunk) { route(frame) }
    }

    private func route(_ frame: Data) {
        switch Self.decode(frame) {
        case let .response(id, result):
            pending.removeValue(forKey: id)?.resume(returning: result)
        case let .failure(id, error):
            pending.removeValue(forKey: id)?.resume(throwing: error)
        case let .notification(note):
            notifyCont.yield(note)
        case .ignored:
            break
        }
    }

    /// Pure classification + decode of one inbound JSON-RPC frame. Extracted from
    /// `route` so the highest-risk demux logic — success vs. error, `data.code`
    /// fallback, null/absent result, Int64 fidelity, and notification decode — is
    /// unit-testable without a live engine. Touches no actor state.
    static func decode(_ frame: Data) -> RPCInbound {
        guard let obj = try? JSONSerialization.jsonObject(with: frame) as? [String: Any] else {
            return .ignored
        }
        if let id = obj["id"] as? Int, obj["method"] == nil {
            if let err = obj["error"] as? [String: Any] {
                let message = err["message"] as? String ?? "unknown engine error"
                let code = ((err["data"] as? [String: Any])?["code"] as? String) ?? "ENGINE_ERROR"
                return .failure(id: id, error: EngineError(code: code, message: message))
            }
            // Success. A missing or null `result` (e.g. workspace/reset) normalizes
            // to `{}` so EmptyResult decodes. Re-serialize with `.fragmentsAllowed`
            // so a scalar/null top-level never triggers JSONSerialization's
            // *uncatchable* "Invalid top-level type" ObjC exception — a `try?`
            // cannot catch it, so it would otherwise crash the app (SIGABRT).
            guard let result = obj["result"], !(result is NSNull) else {
                return .response(id: id, result: Data("{}".utf8))
            }
            if let data = try? JSONSerialization.data(withJSONObject: result, options: .fragmentsAllowed) {
                return .response(id: id, result: data)
            }
            return .response(id: id, result: Data("{}".utf8))
        } else if let method = obj["method"] as? String {
            guard let rawParams = obj["params"], !(rawParams is NSNull),
                  let data = try? JSONSerialization.data(withJSONObject: rawParams, options: .fragmentsAllowed) else {
                return .ignored
            }
            let decoder = JSONDecoder()
            switch method {
            case "progress":
                if let note = try? decoder.decode(ProgressNote.self, from: data) {
                    return .notification(.progress(note))
                }
            case "log":
                if let note = try? decoder.decode(LogNote.self, from: data) {
                    return .notification(.log(note))
                }
            default:
                break
            }
            return .ignored
        }
        return .ignored
    }

    private func allocateID() -> Int {
        defer { nextID += 1 }
        return nextID
    }

    /// Frames `body` with a Content-Length header and writes it to engine stdin.
    /// Uses the throwing `write(contentsOf:)`: the non-throwing `write(_:)` raises
    /// an uncatchable ObjC exception on a broken pipe (SIGABRT), whereas this
    /// surfaces a catchable Swift error we can funnel back to the caller.
    private func writeFrame(_ body: Data) throws {
        var out = Data("Content-Length: \(body.count)\r\n\r\n".utf8)
        out.append(body)
        try stdinPipe.fileHandleForWriting.write(contentsOf: out)
    }

    private func emit<P: Encodable>(id: Int, method: String, params: P) throws {
        let body = try JSONEncoder().encode(RPCRequest(id: id, method: method, params: params))
        try writeFrame(body)
    }

    private func request<P: Encodable, R: Decodable>(_ method: String, _ params: P, as _: R.Type) async throws -> R {
        guard case .running = state else {
            throw EngineError(code: "ENGINE_NOT_RUNNING", message: "engine process is not running")
        }
        let id = allocateID()
        let data: Data = try await withCheckedThrowingContinuation { cont in
            pending[id] = cont                 // register FIRST (no await between this and emit)
            do { try emit(id: id, method: method, params: params) }
            catch {
                pending.removeValue(forKey: id)
                cont.resume(throwing: error)
            }
        }
        return try JSONDecoder().decode(R.self, from: data)
    }

    /// JSON-RPC cancellation for a long-running request (StreamJsonRpc convention).
    /// Best-effort: guarded on `.running`, and the write is `try?`-swallowed to
    /// tolerate the TOCTOU window where the engine dies before the write lands.
    func cancel(requestID: Int) {
        guard case .running = state else { return }
        struct CancelParams: Encodable { let id: Int }
        guard let body = try? JSONEncoder().encode(
            RPCNotification(method: "$/cancelRequest", params: CancelParams(id: requestID))
        ) else { return }
        try? writeFrame(body)
    }

    // MARK: typed API
    func initialize() async throws -> InitializeResult {
        try await request("initialize", EmptyParams(), as: InitializeResult.self)
    }
    func load(paths: [String], unityVersion: String? = nil, loadAll: Bool = false) async throws -> LoadResult {
        try await request("workspace/load",
                          LoadParams(paths: paths, unityVersion: unityVersion, loadAll: loadAll),
                          as: LoadResult.self)
    }
    func reset() async throws {
        _ = try await request("workspace/reset", EmptyParams(), as: EmptyResult.self)
    }
    func list(offset: Int, limit: Int) async throws -> ListResult {
        try await request("assets/list", ListParams(offset: offset, limit: limit), as: ListResult.self)
    }
    func preview(id: Int) async throws -> PreviewResult {
        try await request("assets/preview", PreviewParams(id: id), as: PreviewResult.self)
    }
    func export(_ params: ExportParams) async throws -> ExportResult {
        try await request("assets/export", params, as: ExportResult.self)
    }

    func shutdown() {
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        if process.isRunning { process.terminate() }
    }
}

/// JSON-RPC 2.0 request envelope. File scope because Swift forbids a generic type
/// nested inside the generic `emit` function. `jsonrpc` is a defaulted `let`: it
/// is omitted from the memberwise initializer but still encoded on the wire.
private struct RPCRequest<T: Encodable>: Encodable {
    let jsonrpc = "2.0"
    let id: Int
    let method: String
    let params: T
}

/// JSON-RPC 2.0 notification envelope (no `id`, no response expected).
private struct RPCNotification<T: Encodable>: Encodable {
    let jsonrpc = "2.0"
    let method: String
    let params: T
}

/// One classified inbound JSON-RPC frame — the pure result of `EngineClient.decode`.
enum RPCInbound: Sendable {
    case response(id: Int, result: Data)
    case failure(id: Int, error: EngineError)
    case notification(EngineNotification)
    case ignored
}
