import XCTest

final class SmokeTests: XCTestCase {
    func testLoadsFixtureAndShowsRows() throws {
        let app = XCUIApplication()
        let root = URL(fileURLWithPath: #filePath)          // …/app/UITests/SmokeTests.swift
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fixture = root.appendingPathComponent("fixtures/char_118_yuki.ab").path
        app.launchEnvironment["ASSETSTUDIO_AUTOLOAD"] = fixture
        // Deliberately do NOT set ASSETSTUDIO_ENGINE_PATH: the launched app resolves
        // its engine via Bundle.main.resourceURL/engine/AssetStudioEngine — the
        // EMBEDDED engine that #19's post-build step copies into the built .app. This
        // exercises the exact resolution path the shipped dist/AssetStudio.app uses,
        // so a broken embed (wrong subpath, lost +x bit, missing sibling dylibs) fails
        // THIS gate instead of shipping an "Engine Not Found" app.
        app.launch()

        let status = app.staticTexts["statusText"]
        XCTAssertTrue(status.waitForExistence(timeout: 60), "statusText never appeared")
        // SwiftUI exposes a Text's content as the accessibility *value* (its label is
        // empty) once the Text carries an accessibilityIdentifier — read value first.
        func statusString() -> String { (status.value as? String) ?? status.label }
        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline {
            if statusString().contains("35 of 35") { break }
            usleep(300_000)
        }
        XCTAssertTrue(statusString().contains("35 of 35"),
                      "expected 35 assets loaded, saw: '\(statusString())'")
        XCTAssertTrue(app.tables.firstMatch.exists || app.outlines.firstMatch.exists,
                      "asset table not found")
    }

    /// Proves a Texture2D decodes through the EMBEDDED engine + its vendored native
    /// texture decoder in the shipped layout — the app's whole point. Non-vacuous:
    /// if the native didn't resolve, the engine returns none/error → the preview
    /// lands in .none/.failed → `previewImage` never appears → this fails.
    func testTextureDecodesThroughEmbeddedEngine() throws {
        let app = XCUIApplication()
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        app.launchEnvironment["ASSETSTUDIO_AUTOLOAD"] = root.appendingPathComponent("fixtures/xinzexi_2_n_tex").path
        // No ASSETSTUDIO_ENGINE_PATH → embedded engine (shipped path).
        app.launch()

        let status = app.staticTexts["statusText"]
        XCTAssertTrue(status.waitForExistence(timeout: 60), "statusText never appeared")
        func statusString() -> String { (status.value as? String) ?? status.label }
        let d1 = Date().addingTimeInterval(60)
        while Date() < d1 {
            let s = statusString()
            if !s.isEmpty && !s.contains("0 of 0") { break }
            usleep(300_000)
        }
        XCTAssertFalse(statusString().isEmpty || statusString().contains("0 of 0"),
                       "no assets loaded: '\(statusString())'")

        // Select a Texture2D row from the asset table (identifier from Task 2), which
        // scopes the "Texture2D" match to the table and excludes the sidebar's entry.
        let assetTable = app.tables["assetTable"]
        let table = assetTable.waitForExistence(timeout: 30) ? assetTable : app.outlines["assetTable"]
        XCTAssertTrue(table.waitForExistence(timeout: 10), "assetTable not found")
        let texCell = table.staticTexts["Texture2D"].firstMatch
        XCTAssertTrue(texCell.waitForExistence(timeout: 30), "Texture2D row never appeared")
        texCell.click()

        // Success signal: the decoded texture renders as an image.
        XCTAssertTrue(app.images["previewImage"].waitForExistence(timeout: 30),
                      "texture preview image did not appear — native decode likely failed")
        XCTAssertFalse(app.staticTexts["Preview Failed"].exists, "preview reported failure")
        XCTAssertFalse(app.staticTexts["No visual preview for this type yet"].exists,
                       "texture fell back to no-preview — decode failed")
    }
}
