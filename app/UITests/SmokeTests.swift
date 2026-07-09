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
}
