import Foundation

struct AssetRow: Identifiable, Hashable, Codable, Sendable {
    /// Engine-assigned surrogate key. Contract: unique and stable for the
    /// lifetime of a loaded workspace — `Table` selection and diffing depend on
    /// it not colliding or changing across sort/filter. The underlying Unity
    /// identity is `sourceFile` + `pathId`; `id` is a flattened stand-in the
    /// engine hands out per loaded workspace (a later data-wiring wave must
    /// preserve this contract when it populates rows).
    let id: Int
    let name: String
    let container: String
    let type: String
    let pathId: Int64
    let size: Int64
    let sourceFile: String
}
