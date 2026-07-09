import Foundation

actor EngineClient {
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
        guard FileManager.default.isExecutableFile(atPath: engineURL.path) else {
            throw EngineError(code: "ENGINE_MISSING", message: "engine not found at \(engineURL.path)")
        }
        process.executableURL = engineURL
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let (bytes, byteCont) = AsyncStream.makeStream(of: Data.self)
        stdoutPipe.fileHandleForReading.readabilityHandler = { fh in
            let data = fh.availableData
            if data.isEmpty { byteCont.finish() } else { byteCont.yield(data) }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { fh in
            let data = fh.availableData
            guard !data.isEmpty else { return }
            let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .newlines)
            if !text.isEmpty { NSLog("[engine] %@", text) }
        }
        process.terminationHandler = { [weak self] p in
            let code = p.terminationStatus
            Task { await self?.handleExit(code) }
        }
        try process.run()
        state = .running
        Task { [weak self] in
            for await chunk in bytes { await self?.ingest(chunk) }
        }
    }

    private func handleExit(_ code: Int32) {
        state = .exited(code)
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
        guard let obj = try? JSONSerialization.jsonObject(with: frame) as? [String: Any] else { return }
        if let id = obj["id"] as? Int, obj["method"] == nil {
            guard let cont = pending.removeValue(forKey: id) else { return }
            if let err = obj["error"] as? [String: Any] {
                let message = err["message"] as? String ?? "unknown engine error"
                let code = ((err["data"] as? [String: Any])?["code"] as? String) ?? "ENGINE_ERROR"
                cont.resume(throwing: EngineError(code: code, message: message))
            } else if let result = obj["result"],
                      let data = try? JSONSerialization.data(withJSONObject: result) {
                cont.resume(returning: data)
            } else {
                cont.resume(returning: Data("{}".utf8))   // null/absent result
            }
        } else if let method = obj["method"] as? String {
            guard let params = obj["params"],
                  let data = try? JSONSerialization.data(withJSONObject: params) else { return }
            let decoder = JSONDecoder()
            switch method {
            case "progress":
                if let note = try? decoder.decode(ProgressNote.self, from: data) {
                    notifyCont.yield(.progress(note))
                }
            case "log":
                if let note = try? decoder.decode(LogNote.self, from: data) {
                    notifyCont.yield(.log(note))
                }
            default: break
            }
        }
    }

    private func allocateID() -> Int {
        defer { nextID += 1 }
        return nextID
    }

    private func emit<P: Encodable>(id: Int, method: String, params: P) throws {
        let body = try JSONEncoder().encode(RPCRequest(id: id, method: method, params: params))
        var out = Data("Content-Length: \(body.count)\r\n\r\n".utf8)
        out.append(body)
        stdinPipe.fileHandleForWriting.write(out)
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
    func cancel(requestID: Int) {
        struct CancelParams: Encodable { let id: Int }
        struct Note<T: Encodable>: Encodable {
            let jsonrpc = "2.0"; let method: String; let params: T
        }
        if let body = try? JSONEncoder().encode(Note(method: "$/cancelRequest", params: CancelParams(id: requestID))) {
            var out = Data("Content-Length: \(body.count)\r\n\r\n".utf8)
            out.append(body)
            stdinPipe.fileHandleForWriting.write(out)
        }
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

/// JSON-RPC 2.0 request envelope. Declared at file scope because Swift forbids a
/// generic type nested inside the generic `emit` function. `jsonrpc` carries a
/// default value, so it is omitted from the memberwise initializer but still
/// encoded on the wire.
private struct RPCRequest<T: Encodable>: Encodable {
    let jsonrpc = "2.0"
    let id: Int
    let method: String
    let params: T
}
