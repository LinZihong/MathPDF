import XCTest

final class MathPDFUITestsLaunchTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchProducesAUsableDocumentWindow() {
        let app = XCUIApplication()
        app.launchEnvironment["MATHPDF_UI_FIXTURE"] = "annotated-reader"
        app.launchArguments += [
            "-ApplePersistenceIgnoreState", "YES",
            "-NSDocumentReopenSavedDocuments", "NO",
            "-NSQuitAlwaysKeepsWindows", "NO"
        ]
        app.launch()
        defer {
            if app.state == .runningForeground || app.state == .runningBackground {
                app.activate()
                app.typeKey("q", modifierFlags: .command)
                if !app.wait(for: .notRunning, timeout: 5) {
                    app.terminate()
                }
            }
        }

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["pdf-reader"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.toolbars.firstMatch.exists)
    }
}
