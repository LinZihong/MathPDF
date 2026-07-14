import XCTest

final class MathPDFUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["MATHPDF_UI_FIXTURE"] = "annotated-reader"
        app.launchArguments += [
            "-ApplePersistenceIgnoreState", "YES",
            "-NSDocumentReopenSavedDocuments", "NO",
            "-NSQuitAlwaysKeepsWindows", "NO"
        ]
        app.launch()
    }

    override func tearDownWithError() throws {
        quitAppIfRunning()
        app = nil
    }

    @MainActor
    func testReaderShellAndExactlyOneRenderedNoteSurface() {
        XCTAssertTrue(element("pdf-reader").waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["/ 3"].waitForExistence(timeout: 8))

        showHighlightsAndNotes()
        let note = element("note-row-1-highlight")
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        note.click()

        XCTAssertTrue(element("note-rendered-content").waitForExistence(timeout: 8))
        XCTAssertEqual(app.popovers.count, 1, "One annotation must never produce competing PDFKit and MathPDF popovers")
        XCTAssertTrue(app.buttons["note-edit"].exists)
        XCTAssertEqual(app.textFields["Page number"].value as? String, "2")
    }

    @MainActor
    func testNoteEditingAndDocumentPreambleAreDirectlyReachable() {
        showHighlightsAndNotes()
        let note = element("note-row-1-highlight")
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        note.click()
        XCTAssertTrue(app.buttons["note-edit"].waitForExistence(timeout: 8))
        app.buttons["note-edit"].click()
        XCTAssertTrue(element("note-editor").waitForExistence(timeout: 5))

        app.buttons["Close Inspector"].click()
        app.buttons["Document Preamble"].click()
        XCTAssertTrue(app.staticTexts["Math Macros"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Stored in this PDF"].exists)
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func quitAppIfRunning() {
        guard app?.state == .runningForeground || app?.state == .runningBackground else { return }
        app.activate()
        app.typeKey("q", modifierFlags: .command)
        if !app.wait(for: .notRunning, timeout: 5) {
            app.terminate()
        }
    }

    private func showHighlightsAndNotes() {
        let menu = app.menuButtons["sidebar-content-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.click()
        let item = app.menuItems["Highlights and Notes"]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.click()
    }
}
