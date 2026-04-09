//
//  MathPDFUITests.swift
//  MathPDFUITests
//
//  Created by Zihong Lin on 4/5/26.
//

import XCTest

final class MathPDFUITests: XCTestCase {
    private var app: XCUIApplication!
    private var fixturePath: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("pdfs for testing/ell_curves.pdf")
            .path
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        if app?.state == .runningForeground || app?.state == .runningBackground {
            app.terminate()
        }
        app = nil
    }

    private var rendererExperiment: String {
        ProcessInfo.processInfo.environment["MATHPDF_UI_RENDERER_EXPERIMENT"] ?? "production"
    }

    private var expectedDiagnosticsSubstrings: [String] {
        guard let rawValue = ProcessInfo.processInfo.environment["MATHPDF_UI_EXPECT_CONTAINS"] else {
            return []
        }

        return rawValue
            .split(separator: ";")
            .map { String($0) }
            .filter { !$0.isEmpty }
    }

    @MainActor
    func testLaunchesFixtureAndShowsRenderedNote() throws {
        app.launchEnvironment["MATHPDF_OPEN_DOCUMENT"] = fixturePath
        app.launch()

        XCTAssertEqual(app.state, .runningForeground)

        let noteRow = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "This is a test comment")).firstMatch
        XCTAssertTrue(noteRow.waitForExistence(timeout: 10))
        noteRow.click()

        let renderedTitle = app.staticTexts["rendered-note-title"]
        XCTAssertTrue(renderedTitle.waitForExistence(timeout: 5))

        let metadata = app.staticTexts["rendered-note-metadata"]
        XCTAssertTrue(metadata.exists)
        XCTAssertTrue(metadata.label.contains("Page 1"))

        let renderedContent = app.otherElements["rendered-note-content"]
        XCTAssertTrue(renderedContent.exists)

        XCTAssertFalse(app.staticTexts["raw-note-title"].exists)
    }

    @MainActor
    func testRendererDiagnosticsProbe() throws {
        app.launchEnvironment["MATHPDF_OPEN_DOCUMENT"] = fixturePath
        app.launchArguments += ["--renderer-diagnostics", "--renderer-experiment", rendererExperiment]
        app.launch()

        XCTAssertEqual(app.state, .runningForeground)

        let noteRow = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "This is a test comment")).firstMatch
        XCTAssertTrue(noteRow.waitForExistence(timeout: 10))
        noteRow.click()

        let diagnostics = app.staticTexts["renderer-diagnostics"]
        XCTAssertTrue(diagnostics.waitForExistence(timeout: 10))

        let diagnosticsText = waitForStableDiagnostics(from: diagnostics)
        print("Renderer diagnostics (\(rendererExperiment)):\n\(diagnosticsText)")

        XCTAssertTrue(diagnosticsText.contains("experiment: \(rendererExperiment)"), diagnosticsText)
        XCTAssertFalse(diagnosticsText.contains("state: <empty>"), diagnosticsText)

        for expected in expectedDiagnosticsSubstrings {
            XCTAssertTrue(diagnosticsText.contains(expected), diagnosticsText)
        }
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            app.launch()
            app.terminate()
        }
    }

    private func waitForStableDiagnostics(from element: XCUIElement, timeout: TimeInterval = 8) -> String {
        let deadline = Date().addingTimeInterval(timeout)
        var latest = element.label

        while Date() < deadline {
            latest = element.label
            if latest.contains("state: rendered")
                || latest.contains("state: raw")
                || latest.contains("state: text")
                || latest.contains("webContentTerminated: true") {
                return latest
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }

        return latest
    }
}
