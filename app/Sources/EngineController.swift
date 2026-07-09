import SwiftUI
import Observation

enum WorkspaceState: Equatable {
    case idle
    case loading(current: Int, total: Int)
    case ready
}

@MainActor
@Observable
final class EngineController {
    var state: WorkspaceState = .idle

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

    var errorToast: String? = nil

    /// Assets matching the current type filter and search text, sorted by
    /// `sortOrder`. Memoized: recomputed only when an input changes (`rows`,
    /// `searchText`, `selectedType`, `sortOrder`), so reads from `body` are O(1)
    /// and typing no longer re-filters/re-sorts twice per render.
    private(set) var visibleRows: [AssetRow] = []

    /// `(type, count)` pairs over all loaded `rows`, sorted by type. Memoized:
    /// recomputed only when `rows` changes, so selecting a sidebar type does not
    /// re-group the whole array.
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
}
