import Foundation

struct NativeCaps: Codable, Sendable { let texture: Bool; let fbx: Bool; let fmod: Bool }
struct InitializeResult: Codable, Sendable {
    let engineVersion: String; let coreVersion: String; let natives: NativeCaps
}
struct LoadParams: Codable, Sendable {
    let paths: [String]; let unityVersion: String?; let loadAll: Bool
}
struct LoadResult: Codable, Sendable {
    let loadedFiles: Int; let assetCount: Int; let unityVersion: String?
}
struct ListParams: Codable, Sendable { let offset: Int; let limit: Int }
struct ListResult: Codable, Sendable { let total: Int; let rows: [AssetRow] }
struct PreviewParams: Codable, Sendable { let id: Int }
struct PreviewMeta: Codable, Sendable {
    let name: String; let type: String; let container: String
    let pathId: Int64; let size: Int64; let extra: [String: String]
}
struct PreviewResult: Codable, Sendable {
    let kind: String; let path: String?; let text: String?; let meta: PreviewMeta
}
struct ExportParams: Codable, Sendable {
    let ids: [Int]; let mode: String; let destDir: String
    let groupBy: String; let imageFormat: String
}
struct ExportErrorEntry: Codable, Sendable, Identifiable {
    let id: Int; let name: String; let message: String
}
struct ExportResult: Codable, Sendable {
    let exported: Int; let skipped: Int; let errors: [ExportErrorEntry]
}
struct ProgressNote: Codable, Sendable {
    let token: String; let current: Int; let total: Int; let message: String?
}
struct LogNote: Codable, Sendable { let level: String; let message: String }
struct EmptyParams: Codable, Sendable { init() {} }
struct EmptyResult: Codable, Sendable {}

enum EngineNotification: Sendable {
    case progress(ProgressNote)
    case log(LogNote)
}

struct EngineError: Error, LocalizedError, Sendable {
    let code: String
    let message: String
    var errorDescription: String? { "\(message) [\(code)]" }
}
