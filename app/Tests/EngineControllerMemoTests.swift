import XCTest
@testable import AssetStudio

/// Insurance against a future toolchain changing @Observable + didSet macro
/// behavior: asserts each EngineController input recomputes the memoized
/// derived state (visibleRows / typeCounts).
@MainActor
final class EngineControllerMemoTests: XCTestCase {
    private func sampleRows() -> [AssetRow] {
        [
            AssetRow(id: 1, name: "alpha", container: "c/a", type: "Texture2D",
                     pathId: 100, size: 10, sourceFile: "a.assets"),
            AssetRow(id: 2, name: "beta", container: "c/b", type: "TextAsset",
                     pathId: 200, size: 20, sourceFile: "a.assets"),
            AssetRow(id: 3, name: "gamma", container: "c/g", type: "Texture2D",
                     pathId: 300, size: 30, sourceFile: "b.assets"),
        ]
    }

    func testRowsAssignmentRecomputesDerivedState() {
        let c = EngineController()
        XCTAssertTrue(c.visibleRows.isEmpty)
        XCTAssertTrue(c.typeCounts.isEmpty)
        c.rows = sampleRows()
        XCTAssertEqual(c.visibleRows.count, 3)
        XCTAssertEqual(c.visibleRows.map(\.name), ["alpha", "beta", "gamma"])  // default sort: name asc
        XCTAssertEqual(c.typeCounts.map { $0.type }, ["TextAsset", "Texture2D"])
        XCTAssertEqual(c.typeCounts.first { $0.type == "Texture2D" }?.count, 2)
    }

    func testTypeFilterRecomputesVisibleRows() {
        let c = EngineController()
        c.rows = sampleRows()
        c.selectedType = "Texture2D"
        XCTAssertEqual(c.visibleRows.count, 2)
        XCTAssertTrue(c.visibleRows.allSatisfy { $0.type == "Texture2D" })
    }

    func testSearchTextRecomputesVisibleRows() {
        let c = EngineController()
        c.rows = sampleRows()
        c.searchText = "beta"
        XCTAssertEqual(c.visibleRows.map(\.name), ["beta"])
        c.searchText = "200"                              // matches on pathId substring
        XCTAssertEqual(c.visibleRows.map(\.name), ["beta"])
    }

    func testSortOrderRecomputesVisibleRows() {
        let c = EngineController()
        c.rows = sampleRows()
        c.sortOrder = [KeyPathComparator(\AssetRow.name, order: .reverse)]
        XCTAssertEqual(c.visibleRows.map(\.name), ["gamma", "beta", "alpha"])
    }
}
