import XCTest

final class SmokeTests: XCTestCase {
    func testLoadsFixtureAndShowsRows() throws {
        let app = XCUIApplication()
        let root = URL(fileURLWithPath: #filePath)          // …/app/UITests/SmokeTests.swift
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fixture = root.appendingPathComponent("fixtures/char_118_yuki.ab").path
        app.launchEnvironment["ASSETSTUDIO_AUTOLOAD"] = fixture
        let enginePath = root.appendingPathComponent("engine/publish/AssetStudioEngine").path
        if FileManager.default.isExecutableFile(atPath: enginePath) {
            app.launchEnvironment["ASSETSTUDIO_ENGINE_PATH"] = enginePath
        } // else: the embedded engine from #19's post-build step is used
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
