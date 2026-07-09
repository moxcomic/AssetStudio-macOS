import Foundation

struct AssetRow: Identifiable, Hashable, Codable, Sendable {
    let id: Int
    let name: String
    let container: String
    let type: String
    let pathId: Int64
    let size: Int64
    let sourceFile: String
}
