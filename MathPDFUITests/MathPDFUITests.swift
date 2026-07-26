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
        let yellow = element("note-color-yellow")
        let green = element("note-color-green")
        XCTAssertTrue(yellow.waitForExistence(timeout: 5))
        XCTAssertEqual(yellow.value as? String, "Selected")
        XCTAssertTrue(green.exists)
        XCTAssertFalse(windowTitleContains("Edited"))
        green.click()
        XCTAssertEqual(green.value as? String, "Selected")
        XCTAssertTrue(waitForWindowTitle(toContain: "Edited"))
        attachMathPDFWindow(named: "note-recolored-green")
        app.typeKey("z", modifierFlags: .command)
        let undoRestoredVisibleColor = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "Selected"),
            object: yellow
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [undoRestoredVisibleColor], timeout: 5),
            .completed,
            "Undo must refresh the open surface to the document's restored color"
        )
        XCTAssertTrue(
            waitForWindowTitle(toExclude: "Edited"),
            "Undoing back to the saved state must clear the document's Edited status"
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
        let editor = element("note-editor")
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        let editorBaseline = editor.value as? String
        XCTAssertFalse(windowTitleContains("Edited"))
        editor.click()
        editor.typeText(" Additional detail.")
        XCTAssertTrue(
            waitForWindowTitle(toContain: "Edited"),
            "An uncommitted note draft must participate in native document dirty state"
        )
        app.typeKey("z", modifierFlags: .command)
        XCTAssertEqual(
            editor.value as? String,
            editorBaseline,
            "Typing Undo must restore the exact open-editor buffer"
        )
        XCTAssertTrue(
            waitForWindowTitle(toExclude: "Edited"),
            "Typing Undo inside the note editor must return the draft transaction to baseline"
        )
        editor.typeText(" Additional detail.")
        XCTAssertTrue(waitForWindowTitle(toContain: "Edited"))
        app.buttons["note-done"].click()
        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(
            waitForWindowTitle(toExclude: "Edited"),
            "Undoing the committed note edit back to the saved state must clear Edited"
        )

        app.buttons["Close Note"].click()
        let placeNote = element("place-note")
        XCTAssertTrue(placeNote.waitForExistence(timeout: 5))
        XCTAssertEqual(placeNote.value as? String, "Inactive")
        placeNote.click()
        XCTAssertEqual(placeNote.value as? String, "Active")
        placeNote.click()
        XCTAssertEqual(placeNote.value as? String, "Inactive")

        app.menuBars.menuBarItems["Math"].click()
        app.menuItems["Math Macros…"].click()
        XCTAssertTrue(app.staticTexts["Math Macros"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Document settings"].exists)
        let preambleEditor = element("preamble-editor")
        XCTAssertTrue(preambleEditor.waitForExistence(timeout: 5))
        let preambleBaseline = preambleEditor.value as? String
        preambleEditor.click()
        preambleEditor.typeText("\\newcommand{\\Q}{\\mathbb{Q}}")
        XCTAssertTrue(
            waitForWindowTitle(toContain: "Edited"),
            "Macro typing must use the focused document's native dirty state"
        )
        app.typeKey("z", modifierFlags: .command)
        XCTAssertEqual(
            preambleEditor.value as? String,
            preambleBaseline,
            "One native typing Undo must restore the exact macro source"
        )
        XCTAssertTrue(
            waitForWindowTitle(toExclude: "Edited"),
            "One native typing Undo must not compete with a second model-level undo"
        )
    }

    @MainActor
    func testCommandFFindsTextAtTheDefaultWindowSize() {
        XCTAssertTrue(element("pdf-reader").waitForExistence(timeout: 8))

        app.typeKey("f", modifierFlags: .command)
        let searchField = app.searchFields["Search PDF"].firstMatch
        XCTAssertTrue(
            searchField.waitForExistence(timeout: 5),
            "Command-F must present native PDF search without resizing the window"
        )
        XCTAssertTrue(searchField.isHittable)

        searchField.typeText("rational")
        searchField.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(
            app.staticTexts["1 of 1"].waitForExistence(timeout: 5),
            "Native search must expose a truthful result count"
        )
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

    private func windowTitleContains(_ text: String) -> Bool {
        (app.windows.firstMatch.title as String).contains(text)
    }

    private func waitForWindowTitle(toContain text: String, timeout: TimeInterval = 5) -> Bool {
        let window = app.windows.firstMatch
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "title CONTAINS %@", text),
            object: window
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitForWindowTitle(toExclude text: String, timeout: TimeInterval = 5) -> Bool {
        let window = app.windows.firstMatch
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "NOT title CONTAINS %@", text),
            object: window
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
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
