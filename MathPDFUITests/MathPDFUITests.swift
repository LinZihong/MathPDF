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

        let rawText = app.staticTexts["raw-note-content"]
        XCTAssertTrue(rawText.exists)
        XCTAssertTrue(rawText.label.contains("$a$"))
        XCTAssertTrue(rawText.label.contains("\\[ a^n + b^n = c^n \\]"))

        let renderedContent = app.otherElements["rendered-note-content"]
        XCTAssertTrue(renderedContent.exists)
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            app.launch()
            app.terminate()
        }
    }
}
