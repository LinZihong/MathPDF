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
        XCTAssertEqual(
            app.descendants(matching: .any).matching(identifier: "annotation-note-surface").count,
            1,
            "One annotation must produce one MathPDF reading surface"
        )
        XCTAssertEqual(app.popovers.count, 0, "The integrated note surface must not compete with a PDFKit popover")
        XCTAssertTrue(app.buttons["note-edit"].exists)
        attachMathPDFWindow(named: "note-reading-surface")
        let noteActions = app.menuButtons["note-actions"]
        XCTAssertTrue(noteActions.waitForExistence(timeout: 5))
        XCTAssertEqual(noteActions.value as? String, "Yellow")
        noteActions.click()
        let green = app.menuItems["Green"]
        XCTAssertTrue(green.waitForExistence(timeout: 5))
        green.click()
        XCTAssertEqual(noteActions.value as? String, "Green")
        attachMathPDFWindow(named: "note-recolored-green")
        app.typeKey("z", modifierFlags: .command)
        let undoRestoredVisibleColor = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "Yellow"),
            object: noteActions
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [undoRestoredVisibleColor], timeout: 5),
            .completed,
            "Undo must refresh the open surface to the document's restored color"
        )
        XCTAssertEqual(app.textFields["Page number"].value as? String, "2")
        let badge = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Comment on highlight, page 2")
        ).firstMatch
        XCTAssertTrue(
            badge.exists,
            "A commented highlight must remain discoverable on the page"
        )

        app.buttons["Close Note"].click()
        XCTAssertFalse(element("annotation-note-surface").exists)
        badge.click()
        XCTAssertTrue(
            element("note-rendered-content").waitForExistence(timeout: 5),
            "The on-page comment affordance must open its note without the sidebar"
        )
        app.buttons["Close Note"].click()
        note.click()
        XCTAssertTrue(
            element("note-rendered-content").waitForExistence(timeout: 5),
            "Clicking an already-selected sidebar row must reopen its note"
        )
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

        app.buttons["Close Note"].click()
        app.menuBars.menuBarItems["Math"].click()
        app.menuItems["Math Macros…"].click()
        XCTAssertTrue(app.staticTexts["Math Macros"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Document settings"].exists)
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func attachMathPDFWindow(named name: String) {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.exists)
        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
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
