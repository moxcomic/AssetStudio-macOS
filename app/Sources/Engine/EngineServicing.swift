import Foundation

/// The engine surface `EngineController` depends on. `EngineClient` conforms;
/// tests inject a fake. Methods are `async` so an `actor` (EngineClient) can
/// witness them across its isolation boundary; the streams are witnessed by the
/// actor's nonisolated `Sendable` `let`s.
protocol EngineServicing: Sendable {
    func initialize() async throws -> InitializeResult
    func load(paths: [String], unityVersion: String?, loadAll: Bool) async throws -> LoadResult
    func list(offset: Int, limit: Int) async throws -> ListResult
    func reset() async throws
    func preview(id: Int) async throws -> PreviewResult
    func export(_ params: ExportParams) async throws -> ExportResult
    func startExport(_ params: ExportParams) async throws -> EngineClient.InFlightExport
    func cancel(requestID: Int) async
    func shutdown() async
    var notifications: AsyncStream<EngineNotification> { get }
    var processExited: AsyncStream<Int32> { get }
}
