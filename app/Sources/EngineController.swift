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
    var rows: [AssetRow] = []
    var searchText = ""
    var selectedType: String? = nil
    var selection: AssetRow.ID? = nil
    var sortOrder: [KeyPathComparator<AssetRow>] = [KeyPathComparator(\.name)]
    var errorToast: String? = nil

    var typeCounts: [(type: String, count: Int)] {
        Dictionary(grouping: rows, by: \.type)
            .map { (type: $0.key, count: $0.value.count) }
            .sorted { $0.type < $1.type }
    }

    var visibleRows: [AssetRow] {
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
        return out.sorted(using: sortOrder)
    }
}
