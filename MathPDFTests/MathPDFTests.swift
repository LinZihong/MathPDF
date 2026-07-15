import CoreGraphics
import CoreText
import Foundation
import PDFKit
import Testing
import UniformTypeIdentifiers
import WebKit
@testable import MathPDF

@Suite("Math preamble")
struct MathPreambleCompilerTests {
    @Test
    func compilesTheApprovedDocumentSubset() {
        let compilation = MathPreambleCompiler.compile(#"""
        \usepackage{amsmath}
        \newcommand{\Q}{\mathbb{Q}}
        \newcommand{\PP}{\mathbb{P}}
        \newcommand{\norm}[1]{\left\lVert #1\right\rVert}
        \DeclareMathOperator{\Spec}{Spec}
        """#)

        #expect(compilation.macros["\\Q"] == "\\mathbb{Q}")
        #expect(compilation.macros["\\PP"] == "\\mathbb{P}")
        #expect(compilation.macros["\\norm"] == "\\left\\lVert #1\\right\\rVert")
        #expect(compilation.macros["\\Spec"] == "\\operatorname{Spec}")
        #expect(compilation.ignoredLineNumbers == [1])
        #expect(compilation.invalidLineNumbers.isEmpty)
    }

    @Test
    func renewCommandWinsAndUnsupportedLinesRemainIgnored() {
        let compilation = MathPreambleCompiler.compile(#"""
        \newcommand{\Q}{old}
        \renewcommand{\Q}{new}
        \newtheorem{theorem}{Theorem}
        """#)

        #expect(compilation.macros["\\Q"] == "new")
        #expect(compilation.ignoredLineNumbers == [3])
    }

    @Test
    func reportsMalformedSupportedDeclarationsPrecisely() {
        let compilation = MathPreambleCompiler.compile(#"""
        \newcommand{\Q}
        \DeclareMathOperator{Spec}
        """#)

        #expect(compilation.invalidLineNumbers == [1, 2])
        #expect(compilation.macros.isEmpty)
    }
}

@Suite("Math rendering", .serialized)
struct MathNoteRendererTests {
    @Test
    func recognizesAllSupportedDelimiterFamilies() {
        #expect(MathNoteRenderer.hasMathMarkup(in: "$x$"))
        #expect(MathNoteRenderer.hasMathMarkup(in: "$$x$$"))
        #expect(MathNoteRenderer.hasMathMarkup(in: "\\(x\\)"))
        #expect(MathNoteRenderer.hasMathMarkup(in: "\\[x\\]"))
        #expect(!MathNoteRenderer.hasMathMarkup(in: "The price is $5."))
    }

    @MainActor
    @Test
    func includesDocumentMacrosWithoutAllowingScriptTermination() async throws {
        let rendered = try MathNoteRenderer.renderedDocument(
            rawText: #"Use $\Q$ safely. </script><script>window.pwned=true</script>"#,
            preamble: #"""
            \newcommand{\Q}{\mathbb{Q}}
            \newcommand{\evil}{</script><script>window.macroPwned=true</script>}
            """#,
            assetDirectoryURL: katexAssetURL,
            debugSettings: .init(experiment: .production, diagnosticsEnabled: false)
        )

        #expect(rendered.html.contains(#""\\Q":"\\mathbb{Q}""#))
        #expect(rendered.html.contains("\\u003C\\/script\\u003E\\u003Cscript\\u003Ewindow.pwned=true"))
        #expect(rendered.html.contains("\\u003C\\/script\\u003E\\u003Cscript\\u003Ewindow.macroPwned=true"))

        let snapshot = try await WebRendererProbe.snapshot(of: rendered)
        #expect(!snapshot.pageWasCompromised)
        #expect(!snapshot.macroWasCompromised)
    }

    @MainActor
    @Test
    func rendersApprovedMacroAndKeepsBrokenMathReadable() async throws {
        let valid = try MathNoteRenderer.renderedDocument(
            rawText: #"A rational point lies in $\Q$."#,
            preamble: #"\newcommand{\Q}{\mathbb{Q}}"#,
            assetDirectoryURL: katexAssetURL,
            debugSettings: .init(experiment: .production, diagnosticsEnabled: false)
        )
        let validSnapshot = try await WebRendererProbe.snapshot(of: valid)
        #expect(validSnapshot.renderState == "rendered")
        #expect(validSnapshot.katexCount > 0)
        #expect(validSnapshot.innerText.contains("rational point"))

        let broken = try MathNoteRenderer.renderedDocument(
            rawText: "Broken $a^n text",
            assetDirectoryURL: katexAssetURL,
            debugSettings: .init(experiment: .production, diagnosticsEnabled: false)
        )
        let brokenSnapshot = try await WebRendererProbe.snapshot(of: broken)
        #expect(["raw", "text"].contains(brokenSnapshot.renderState))
        #expect(brokenSnapshot.innerText.contains("Broken $a^n text"))
    }
}

@MainActor
@Suite("PDF note semantics")
struct PDFNoteExtractorTests {
    @Test
    func keepsStandaloneTextNotesEvenWhenTheyResembleHighlights() throws {
        let document = TestPDFFactory.document(pageCount: 2)
        let page = try #require(document.page(at: 0))
        let highlight = TestPDFFactory.annotation(.highlight, contents: "same note", bounds: .init(x: 80, y: 600, width: 150, height: 18))
        let text = TestPDFFactory.annotation(.text, contents: "same note", bounds: .init(x: 235, y: 620, width: 24, height: 24))
        let popup = TestPDFFactory.annotation(.popup, contents: "same note", bounds: .init(x: 260, y: 560, width: 180, height: 120))
        let empty = TestPDFFactory.annotation(.text, contents: "  ", bounds: .init(x: 40, y: 40, width: 24, height: 24))
        [highlight, text, popup, empty].forEach(page.addAnnotation)

        let notes = PDFNoteExtractor.extractNotes(from: document)
        #expect(notes.count == 2)
        #expect(notes.map(\.annotationType) == ["Highlight", "Text"])
        #expect(notes.allSatisfy { $0.contents == "same note" })
    }

    @Test
    func includesBareHighlightsUsingTheirSelectedSourceText() throws {
        let document = TestPDFFactory.textDocument("A rational point lies on the curve.")
        let page = try #require(document.page(at: 0))
        let selection = try #require(page.selection(for: NSRange(location: 2, length: 14)))
        let highlight = TestPDFFactory.annotation(
            .highlight,
            contents: "",
            bounds: selection.bounds(for: page)
        )
        page.addAnnotation(highlight)

        let note = try #require(PDFNoteExtractor.extractNotes(from: document).first)
        #expect(note.annotationType == "Highlight")
        #expect(note.trimmedContents.isEmpty)
        #expect(note.trimmedSourceText.contains("rational point"))
    }

    @Test
    func extractsNestedOutlineDestinations() throws {
        let document = TestPDFFactory.document(pageCount: 3)
        let page = try #require(document.page(at: 2))
        let root = PDFOutline()
        let chapter = PDFOutline()
        chapter.label = "Chapter"
        let section = PDFOutline()
        section.label = "Section"
        section.destination = PDFDestination(page: page, at: CGPoint(x: 0, y: 700))
        chapter.insertChild(section, at: 0)
        root.insertChild(chapter, at: 0)
        document.outlineRoot = root

        let outline = PDFNoteExtractor.extractOutline(from: document)
        #expect(outline.first?.title == "Chapter")
        #expect(outline.first?.children.first?.title == "Section")
        #expect(outline.first?.children.first?.pageIndex == 2)
    }
}

@MainActor
@Suite("Document editing")
struct MathPDFDocumentTests {
    @Test
    func deletingDuringAnEditDoesNotLeakItsUndoBaselineAfterRestore() throws {
        let document = MathPDFDocument()
        let page = try #require(document.pdfDocument.page(at: 0))
        let note = TestPDFFactory.annotation(
            .text,
            contents: "before",
            bounds: .init(x: 70, y: 600, width: 24, height: 24)
        )
        page.addAnnotation(note)
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false

        #expect(document.updateContentsDuringEditing(of: note, to: "typed before delete"))
        undoManager.beginUndoGrouping()
        document.removeAnnotation(note, undoManager: undoManager)
        undoManager.endUndoGrouping()
        undoManager.undo()
        #expect(note.page === page)
        #expect(note.contents == "typed before delete")

        #expect(document.updateContentsDuringEditing(of: note, to: "second edit"))
        undoManager.beginUndoGrouping()
        document.commitContentsEditingTransaction(
            of: note,
            from: "typed before delete",
            undoManager: undoManager
        )
        undoManager.endUndoGrouping()
        undoManager.undo()

        #expect(note.contents == "typed before delete")
    }

    @Test
    func editingHighlightCreatesAStandardsPopupAndRemainsUndoable() throws {
        let document = MathPDFDocument()
        let page = try #require(document.pdfDocument.page(at: 0))
        let highlight = TestPDFFactory.annotation(.highlight, contents: "before", bounds: .init(x: 70, y: 600, width: 120, height: 18))
        page.addAnnotation(highlight)
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false

        undoManager.beginUndoGrouping()
        document.updateContents(of: highlight, to: "after", undoManager: undoManager)
        undoManager.endUndoGrouping()
        #expect(highlight.contents == "after")
        let popup = try #require(document.popupCompanion(for: highlight))
        #expect(!page.annotations.contains { $0 === popup })
        #expect(popup.page == nil)
        #expect(popup.contents == nil)
        #expect(highlight.popup == nil)
        #expect(page.annotations.filter { $0.type == "Text" }.isEmpty)

        undoManager.undo()
        #expect(highlight.contents == "before")
        undoManager.redo()
        #expect(highlight.contents == "after")
    }

    @Test
    func editingKeepsContentsOnTheOwnerAndPreservesTheExistingPopup() throws {
        let document = MathPDFDocument()
        let page = try #require(document.pdfDocument.page(at: 0))
        let highlight = TestPDFFactory.annotation(.highlight, contents: "before", bounds: .init(x: 70, y: 600, width: 120, height: 18))
        let popup = TestPDFFactory.annotation(.popup, contents: "before", bounds: .init(x: 220, y: 520, width: 180, height: 120))
        page.addAnnotation(highlight)
        page.addAnnotation(popup)
        highlight.popup = popup

        document.updateContents(of: highlight, to: "after", undoManager: nil)
        #expect(highlight.contents == "after")
        #expect(popup.contents == nil)
        #expect(document.popupCompanion(for: highlight) === popup)
        #expect(highlight.popup == nil)
        #expect(!page.annotations.contains { $0 === popup })
        #expect(page.annotations.filter { $0.type == "Text" }.isEmpty)
    }

    @Test
    func activeEditingUpdatesSnapshotsImmediatelyAndCommitsOneDocumentUndo() throws {
        let document = MathPDFDocument()
        let page = try #require(document.pdfDocument.page(at: 0))
        let highlight = TestPDFFactory.annotation(
            .highlight,
            contents: "before",
            bounds: .init(x: 70, y: 600, width: 120, height: 18)
        )
        page.addAnnotation(highlight)
        let initialRevision = document.annotationRevision

        #expect(document.updateContentsDuringEditing(of: highlight, to: "during"))
        #expect(highlight.contents == "during")
        #expect(document.annotationRevision == initialRevision)
        let autosaveReload = try MathPDFDocument(data: document.serializedData())
        #expect(PDFNoteExtractor.extractNotes(from: autosaveReload.pdfDocument).first?.contents == "during")

        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        undoManager.beginUndoGrouping()
        document.commitContentsEditingTransaction(
            of: highlight,
            from: "before",
            undoManager: undoManager
        )
        undoManager.endUndoGrouping()

        #expect(document.annotationRevision == initialRevision + 1)
        #expect(undoManager.canUndo)
        undoManager.undo()
        #expect(highlight.contents == "before")
        undoManager.redo()
        #expect(highlight.contents == "during")
    }

    @Test
    func activeImportedEditUndoRestoresRawOwnerMetadataAndLeavesPopupPrivateStateNeutral() throws {
        let source = TestPDFFactory.rawPopupGraph(
            shape: .reciprocal,
            includeNames: false,
            includePopupSentinels: true,
            includeOwnerSentinels: true
        )
        let originalOwner = try TestPDFFactory.rawFirstOwnerState(in: source)
        let originalPopup = try TestPDFFactory.rawPopupState(in: source)
        #expect(originalOwner.modificationDate == "D:20260713010101Z")
        #expect(originalOwner.richContents == "owner-rich")

        let document = try MathPDFDocument(data: source)
        let page = try #require(document.pdfDocument.page(at: 0))
        let highlight = try #require(page.annotations.first { $0.type == "Highlight" })

        #expect(document.updateContentsDuringEditing(of: highlight, to: "edited during typing"))
        let edited = try document.serializedData()
        let editedOwner = try TestPDFFactory.rawFirstOwnerState(in: edited)
        #expect(editedOwner.contents == "edited during typing")
        #expect(editedOwner.modificationDate != originalOwner.modificationDate)
        #expect(editedOwner.richContents == nil)
        #expect(try TestPDFFactory.rawPopupState(in: edited) == originalPopup)

        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        undoManager.beginUndoGrouping()
        document.commitContentsEditingTransaction(
            of: highlight,
            from: "owner note",
            undoManager: undoManager
        )
        undoManager.endUndoGrouping()

        undoManager.undo()
        let undone = try document.serializedData()
        #expect(try TestPDFFactory.rawFirstOwnerState(in: undone) == originalOwner)
        #expect(try TestPDFFactory.rawPopupState(in: undone) == originalPopup)

        undoManager.redo()
        let redone = try document.serializedData()
        #expect(try TestPDFFactory.rawFirstOwnerState(in: redone) == editedOwner)
        #expect(try TestPDFFactory.rawPopupState(in: redone) == originalPopup)
    }

    @Test
    func textNotePlacementAndPreambleRoundTripSemantically() throws {
        let document = MathPDFDocument()
        let page = try #require(document.pdfDocument.page(at: 0))
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        undoManager.beginUndoGrouping()
        let note = try #require(document.addTextNote(
            on: page,
            at: CGPoint(x: 100, y: 140),
            undoManager: undoManager
        ))
        document.updateContents(of: note, to: #"Point in $\Q$"#, undoManager: undoManager)
        undoManager.endUndoGrouping()
        document.preamble = #"\newcommand{\Q}{\mathbb{Q}}"#

        let reloaded = try MathPDFDocument(data: document.serializedData())
        let reloadedNotes = PDFNoteExtractor.extractNotes(from: reloaded.pdfDocument)
        #expect(reloadedNotes.count == 1)
        #expect(reloadedNotes.first?.contents == #"Point in $\Q$"#)
        #expect(abs((reloadedNotes.first?.bounds.midX ?? 0) - 100) < 1)
        #expect(reloaded.preamble == #"\newcommand{\Q}{\mathbb{Q}}"#)
        let reloadedPage = try #require(reloaded.pdfDocument.page(at: 0))
        let reloadedText = try #require(reloadedPage.annotations.first { $0.type == "Text" })
        let reloadedPopup = try #require(reloaded.popupCompanion(for: reloadedText))
        #expect(!reloadedPage.annotations.contains { $0 === reloadedPopup })
        #expect(reloadedText.popup == nil)
    }

    @Test
    func textNotesAreClampedInsideThePageCropBox() throws {
        let document = MathPDFDocument()
        let page = try #require(document.pdfDocument.page(at: 0))
        let cropBox = page.bounds(for: .cropBox)

        let below = try #require(document.addTextNote(
            on: page,
            at: CGPoint(x: cropBox.minX - 500, y: cropBox.minY - 500),
            undoManager: nil
        ))
        let above = try #require(document.addTextNote(
            on: page,
            at: CGPoint(x: cropBox.maxX + 500, y: cropBox.maxY + 500),
            undoManager: nil
        ))

        #expect(cropBox.contains(below.bounds))
        #expect(cropBox.contains(above.bounds))
    }

    @Test
    func multilineSelectionCreatesOneInteroperableHighlightPerPage() throws {
        let pdfDocument = TestPDFFactory.textDocument("First line of mathematics\nSecond line of mathematics")
        let data = try #require(pdfDocument.dataRepresentation())
        let document = try MathPDFDocument(data: data)
        let page = try #require(document.pdfDocument.page(at: 0))
        let pageString = try #require(page.string)
        let selection = try #require(page.selection(for: NSRange(location: 0, length: pageString.utf16.count)))

        let highlight = try #require(document.addHighlight(from: selection, undoManager: nil))

        #expect(page.annotations.filter { $0.type == "Highlight" }.count == 1)
        #expect((highlight.quadrilateralPoints?.count ?? 0) >= 8)
        #expect(PDFNoteExtractor.extractNotes(from: document.pdfDocument).count == 1)
    }

    @Test
    func multiPageHighlightCreationUndoAndRedoAsOneAction() throws {
        let source = TestPDFFactory.textDocument(pages: ["first page", "second page"])
        let document = try MathPDFDocument(data: try #require(source.dataRepresentation()))
        let firstPage = try #require(document.pdfDocument.page(at: 0))
        let secondPage = try #require(document.pdfDocument.page(at: 1))
        let firstSelection = try #require(firstPage.selection(for: NSRange(location: 0, length: 5)))
        let secondSelection = try #require(secondPage.selection(for: NSRange(location: 0, length: 6)))
        let combinedSelection = PDFSelection(document: document.pdfDocument)
        combinedSelection.add(firstSelection)
        combinedSelection.add(secondSelection)
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false

        undoManager.beginUndoGrouping()
        _ = try #require(document.addHighlight(from: combinedSelection, undoManager: undoManager))
        undoManager.endUndoGrouping()
        #expect(firstPage.annotations.filter { $0.type == "Highlight" }.count == 1)
        #expect(secondPage.annotations.filter { $0.type == "Highlight" }.count == 1)

        undoManager.undo()
        #expect(firstPage.annotations.allSatisfy { $0.type != "Highlight" })
        #expect(secondPage.annotations.allSatisfy { $0.type != "Highlight" })
        #expect(undoManager.canRedo)

        undoManager.redo()
        #expect(firstPage.annotations.filter { $0.type == "Highlight" }.count == 1)
        #expect(secondPage.annotations.filter { $0.type == "Highlight" }.count == 1)
        #expect(undoManager.canUndo)

        let reloaded = try MathPDFDocument(data: document.serializedData())
        #expect(reloaded.pdfDocument.page(at: 0)?.annotations.filter { $0.type == "Highlight" }.count == 1)
        #expect(reloaded.pdfDocument.page(at: 1)?.annotations.filter { $0.type == "Highlight" }.count == 1)
    }

    @Test
    func editingPreservesUnrelatedMetadataPagesAndAnnotations() throws {
        let source = TestPDFFactory.document(pageCount: 2)
        var attributes = source.documentAttributes ?? [:]
        attributes[PDFDocumentAttribute.keywordsAttribute.rawValue] = ["research", "algebraic geometry"]
        attributes[PDFDocumentAttribute.titleAttribute.rawValue] = "A preserved research PDF"
        source.documentAttributes = attributes
        let sourceFirstPage = try #require(source.page(at: 0))
        let sourceSecondPage = try #require(source.page(at: 1))
        sourceFirstPage.rotation = 90
        sourceSecondPage.setBounds(CGRect(x: 18, y: 24, width: 540, height: 720), for: .cropBox)

        let widget = TestPDFFactory.annotation(.widget, contents: "", bounds: .init(x: 100, y: 180, width: 180, height: 28))
        widget.widgetFieldType = .text
        widget.fieldName = "researcher"
        widget.widgetStringValue = "Sofia Kovalevskaya"
        sourceSecondPage.addAnnotation(widget)

        let outlineRoot = PDFOutline()
        let section = PDFOutline()
        section.label = "Preserved section"
        section.destination = PDFDestination(page: sourceSecondPage, at: CGPoint(x: 18, y: 744))
        outlineRoot.insertChild(section, at: 0)
        source.outlineRoot = outlineRoot

        // Seed the standalone Text note through MathPDF rather than PDFKit's
        // serializer. PDFKit can emit a malformed Popup /Parent for a newly
        // inserted Text annotation, which would make the fixture invalid before
        // the preservation behavior under test begins.
        let seededDocument = try MathPDFDocument(data: try #require(source.dataRepresentation()))
        let seededSecondPage = try #require(seededDocument.pdfDocument.page(at: 1))
        let seededNote = try #require(seededDocument.addTextNote(
            on: seededSecondPage,
            at: CGPoint(x: 72, y: 72),
            undoManager: nil
        ))
        seededDocument.updateContents(of: seededNote, to: "keep me", undoManager: nil)

        let document = try MathPDFDocument(data: seededDocument.serializedData())
        let firstPage = try #require(document.pdfDocument.page(at: 0))
        let highlight = TestPDFFactory.annotation(.highlight, contents: "before", bounds: .init(x: 80, y: 600, width: 160, height: 18))
        let popup = TestPDFFactory.annotation(.popup, contents: "before", bounds: .init(x: 260, y: 500, width: 180, height: 120))
        firstPage.addAnnotation(highlight)
        firstPage.addAnnotation(popup)
        highlight.popup = popup
        highlight.userName = "Emmy Noether"

        document.updateContents(of: highlight, to: "after", undoManager: nil)
        document.preamble = #"\newcommand{\Q}{\mathbb{Q}}"#

        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MathPDFTests-(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let savedURL = temporaryDirectory.appendingPathComponent("round-trip.pdf")
        try document.serializedData().write(to: savedURL, options: .atomic)
        let reloaded = try MathPDFDocument(data: Data(contentsOf: savedURL))

        #expect(reloaded.pdfDocument.pageCount == 2)
        let reloadedKeywords = reloaded.pdfDocument.documentAttributes?[PDFDocumentAttribute.keywordsAttribute.rawValue] as? [String]
        #expect(reloadedKeywords?.contains("research") == true)
        #expect(reloadedKeywords?.contains("algebraic geometry") == true)
        #expect(reloaded.pdfDocument.documentAttributes?[PDFDocumentAttribute.titleAttribute.rawValue] as? String == "A preserved research PDF")
        #expect(reloaded.preamble == #"\newcommand{\Q}{\mathbb{Q}}"#)

        let savedFirstPage = try #require(reloaded.pdfDocument.page(at: 0))
        let savedSecondPage = try #require(reloaded.pdfDocument.page(at: 1))
        let savedHighlight = try #require(savedFirstPage.annotations.first { $0.type == "Highlight" })
        #expect(savedHighlight.contents == "after")
        #expect(savedHighlight.userName == "Emmy Noether")
        let savedPopup = try #require(reloaded.popupCompanion(for: savedHighlight))
        #expect(!savedFirstPage.annotations.contains { $0 === savedPopup })
        #expect(savedHighlight.popup == nil)
        #expect(savedFirstPage.annotations.filter { $0.type == "Text" }.isEmpty)
        #expect(savedFirstPage.rotation == 90)
        #expect(savedSecondPage.bounds(for: .cropBox) == CGRect(x: 18, y: 24, width: 540, height: 720))
        #expect(savedSecondPage.annotations.contains { $0.type == "Text" && $0.contents == "keep me" })
        let savedWidget = try #require(savedSecondPage.annotations.first { $0.type == "Widget" })
        #expect(savedWidget.widgetFieldType == .text)
        #expect(savedWidget.fieldName == "researcher")
        #expect(savedWidget.widgetStringValue == "Sofia Kovalevskaya")
        #expect(reloaded.pdfDocument.outlineRoot?.child(at: 0)?.label == "Preserved section")
        #expect(reloaded.pdfDocument.outlineRoot?.child(at: 0)?.destination?.page === savedSecondPage)
    }

    @Test
    func popupCompanionRoundTripsReciprocallyWithoutMutatingLiveTopology() throws {
        let document = MathPDFDocument()
        let page = try #require(document.pdfDocument.page(at: 0))
        let sourceHighlight = TestPDFFactory.annotation(.highlight, contents: "before", bounds: .init(x: 80, y: 600, width: 160, height: 18))
        let sourcePopup = TestPDFFactory.annotation(.popup, contents: "before", bounds: .init(x: 260, y: 500, width: 180, height: 120))
        page.addAnnotation(sourceHighlight)
        page.addAnnotation(sourcePopup)
        sourceHighlight.popup = sourcePopup

        document.updateContents(of: sourceHighlight, to: "after", undoManager: nil)
        #expect(sourcePopup.contents == nil)

        let data = try document.serializedData()
        #expect(document.popupCompanion(for: sourceHighlight) === sourcePopup)
        #expect(sourceHighlight.popup == nil)
        #expect(!page.annotations.contains { $0 === sourcePopup })

        let reloaded = try MathPDFDocument(data: data)
        let savedPage = try #require(reloaded.pdfDocument.page(at: 0))
        let savedHighlight = try #require(savedPage.annotations.first { $0.type == "Highlight" })
        #expect(savedHighlight.contents == "after")
        let savedPopup = try #require(reloaded.popupCompanion(for: savedHighlight))
        #expect(!savedPage.annotations.contains { $0 === savedPopup })
        #expect(savedHighlight.popup == nil)
    }

    @Test
    func noOpSnapshotIsByteIdenticalAndDirtySnapshotIsCachedPerRevision() throws {
        let sourceDocument = TestPDFFactory.document(pageCount: 2)
        let sourceData = try #require(sourceDocument.dataRepresentation())
        let document = try MathPDFDocument(data: sourceData)

        #expect(try document.serializedData() == sourceData)
        #expect(try document.serializedData() == sourceData)

        let page = try #require(document.pdfDocument.page(at: 0))
        let highlight = TestPDFFactory.annotation(
            .highlight,
            contents: "",
            bounds: .init(x: 80, y: 600, width: 160, height: 18)
        )
        page.addAnnotation(highlight)
        document.updateContents(of: highlight, to: "a new note", undoManager: nil)

        let first = try document.serializedData()
        let second = try document.serializedData()
        #expect(first == second)
        #expect(first != sourceData)

        let reloaded = try MathPDFDocument(data: first)
        let savedPage = try #require(reloaded.pdfDocument.page(at: 0))
        let savedHighlight = try #require(savedPage.annotations.first { $0.type == "Highlight" })
        _ = try #require(reloaded.popupCompanion(for: savedHighlight))
        #expect(savedHighlight.popup == nil)
    }

    @Test
    func repeatedSaveDeleteUndoRedoPreservesExactAnnotationIdentity() throws {
        let source = TestPDFFactory.document(pageCount: 1)
        let sourcePage = try #require(source.page(at: 0))
        let sharedBounds = CGRect(x: 80, y: 600, width: 160, height: 18)
        let first = TestPDFFactory.annotation(.highlight, contents: "", bounds: sharedBounds)
        let second = TestPDFFactory.annotation(.highlight, contents: "", bounds: sharedBounds)
        sourcePage.addAnnotation(first)
        sourcePage.addAnnotation(second)

        let document = try MathPDFDocument(data: try #require(source.dataRepresentation()))
        let page = try #require(document.pdfDocument.page(at: 0))
        let importedHighlights = page.annotations.filter { $0.type == "Highlight" }
        #expect(importedHighlights.count == 2)
        let importedFirst = try #require(importedHighlights.first)
        let importedSecond = try #require(importedHighlights.last)
        document.updateContents(of: importedFirst, to: "same", undoManager: nil)
        document.updateContents(of: importedSecond, to: "same", undoManager: nil)

        let nameKey = PDFAnnotationKey(rawValue: "/NM")
        let firstName = try #require(importedFirst.value(forAnnotationKey: nameKey) as? String)
        let secondName = try #require(importedSecond.value(forAnnotationKey: nameKey) as? String)
        #expect(firstName != secondName)

        document.updateContents(of: importedSecond, to: "second v1", undoManager: nil)
        let firstRevision = try document.serializedData()
        try assertHighlightGraph(
            in: firstRevision,
            expected: [firstName: "same", secondName: "second v1"]
        )

        document.updateContents(of: importedSecond, to: "second v2", undoManager: nil)
        let secondRevision = try document.serializedData()
        try assertHighlightGraph(
            in: secondRevision,
            expected: [firstName: "same", secondName: "second v2"]
        )

        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        undoManager.beginUndoGrouping()
        document.removeAnnotation(importedSecond, undoManager: undoManager)
        undoManager.endUndoGrouping()
        let deletedRevision = try document.serializedData()
        try assertHighlightGraph(in: deletedRevision, expected: [firstName: "same"])

        undoManager.undo()
        let restoredRevision = try document.serializedData()
        try assertHighlightGraph(
            in: restoredRevision,
            expected: [firstName: "same", secondName: "second v2"]
        )

        undoManager.redo()
        let redoneRevision = try document.serializedData()
        try assertHighlightGraph(in: redoneRevision, expected: [firstName: "same"])

        // Earlier snapshots remain independent immutable revisions.
        try assertHighlightGraph(
            in: firstRevision,
            expected: [firstName: "same", secondName: "second v1"]
        )
    }

    @Test
    func changingHighlightColorNeverClearsItsAttachedNote() throws {
        let source = TestPDFFactory.textDocument("color-safe source")
        let document = try MathPDFDocument(data: try #require(source.dataRepresentation()))
        let selection = try #require(
            document.pdfDocument.findString("color-safe", withOptions: []).first
        )
        let highlight = try #require(document.addHighlight(from: selection, undoManager: nil))
        document.updateContents(of: highlight, to: "color-safe note", undoManager: nil)
        let nameKey = PDFAnnotationKey(rawValue: "/NM")
        let name = try #require(highlight.value(forAnnotationKey: nameKey) as? String)
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        undoManager.beginUndoGrouping()
        document.updateHighlightColor(of: highlight, to: .systemGreen, undoManager: undoManager)
        undoManager.endUndoGrouping()

        #expect(undoManager.canUndo)
        #expect(highlight.color == .systemGreen)
        #expect(highlight.contents == "color-safe note")
        try assertHighlightGraph(
            in: document.serializedData(),
            expected: [name: "color-safe note"]
        )

        undoManager.undo()
        #expect(highlight.contents == "color-safe note")
        try assertHighlightGraph(
            in: document.serializedData(),
            expected: [name: "color-safe note"]
        )
    }

    @Test
    func recoloringAnImportedHighlightDropsItsStaleAppearanceStream() throws {
        let source = TestPDFFactory.rawHighlightWithAppearance()
        #expect(try TestPDFFactory.rawFirstHighlightHasAppearance(in: source))
        let document = try MathPDFDocument(data: source)
        let page = try #require(document.pdfDocument.page(at: 0))
        let highlight = try #require(page.annotations.first { $0.type == "Highlight" })

        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        undoManager.beginUndoGrouping()
        #expect(document.canChangeColor(of: highlight))
        #expect(document.updateHighlightColor(of: highlight, to: .systemGreen, undoManager: undoManager))
        undoManager.endUndoGrouping()

        let saved = try document.serializedData()
        #expect(!(try TestPDFFactory.rawFirstHighlightHasAppearance(in: saved)))
        try assertHighlightGraph(in: saved, expected: ["appearance-owner": "owner note"])
        let reloaded = try MathPDFDocument(data: saved)
        let reloadedPage = try #require(reloaded.pdfDocument.page(at: 0))
        let reloadedHighlight = try #require(
            reloadedPage.annotations.first { $0.type == "Highlight" }
        )
        #expect(AnnotationColorChoice.nearest(to: reloadedHighlight.color) == .green)

        undoManager.undo()
        let undone = try document.serializedData()
        #expect(try TestPDFFactory.rawFirstHighlightHasAppearance(in: undone))
        let undoReload = try MathPDFDocument(data: undone)
        let undoPage = try #require(undoReload.pdfDocument.page(at: 0))
        let undoHighlight = try #require(undoPage.annotations.first { $0.type == "Highlight" })
        #expect(AnnotationColorChoice.nearest(to: undoHighlight.color) == .yellow)
        try assertHighlightGraph(in: undone, expected: ["appearance-owner": "owner note"])
    }

    @Test
    func editingPreservesAnImportedPopupColorThroughTheRawWriter() throws {
        let document = try MathPDFDocument(data: TestPDFFactory.rawPopupGraphWithMismatchedColor())
        let page = try #require(document.pdfDocument.page(at: 0))
        let highlight = try #require(page.annotations.first { $0.type == "Highlight" })

        #expect(document.updateContents(of: highlight, to: "edited owner note", undoManager: nil))
        let saved = try document.serializedData()
        let savedPopupColor = try TestPDFFactory.rawFirstPopupColor(in: saved)
        #expect(savedPopupColor == [1, 0, 0])
        try assertHighlightGraph(in: saved, expected: ["raw-owner": "edited owner note"])
    }

    @Test
    func colorUndoRestoresThePopupsIndependentColorAndAppearance() throws {
        let source = TestPDFFactory.rawPopupGraphWithMismatchedColor()
        let originalPopup = try TestPDFFactory.rawPopupState(in: source)
        #expect(originalPopup.color == [1, 0, 0])
        #expect(originalPopup.hasAppearance)

        let document = try MathPDFDocument(data: source)
        let page = try #require(document.pdfDocument.page(at: 0))
        let highlight = try #require(page.annotations.first { $0.type == "Highlight" })
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        undoManager.beginUndoGrouping()
        #expect(document.updateHighlightColor(
            of: highlight,
            to: NSColor.systemGreen,
            undoManager: undoManager
        ))
        undoManager.endUndoGrouping()
        undoManager.undo()

        let undone = try document.serializedData()
        let restoredPopup = try TestPDFFactory.rawPopupState(in: undone)
        #expect(restoredPopup.contents == originalPopup.contents)
        #expect(restoredPopup.modificationDate == originalPopup.modificationDate)
        #expect(restoredPopup.flags == originalPopup.flags)
        #expect(restoredPopup.isOpen == originalPopup.isOpen)
        #expect(restoredPopup.hasAppearance == originalPopup.hasAppearance)
        #expect(restoredPopup.sentinel == originalPopup.sentinel)
        #expect(restoredPopup.name == originalPopup.name)
        #expect(restoredPopup.richContents == originalPopup.richContents)
        #expect(restoredPopup.color == originalPopup.color)
    }

    @Test
    func editingOwnerPreservesImportedPopupPrivateMetadata() throws {
        let source = TestPDFFactory.rawPopupGraph(
            shape: .reciprocal,
            includeNames: false,
            includePopupSentinels: true,
            includeOwnerSentinels: true
        )
        let originalPopup = try TestPDFFactory.rawPopupState(in: source)
        let document = try MathPDFDocument(data: source)
        let page = try #require(document.pdfDocument.page(at: 0))
        let highlight = try #require(page.annotations.first { $0.type == "Highlight" })

        #expect(document.updateContents(of: highlight, to: "edited owner note", undoManager: nil))
        let saved = try document.serializedData()

        #expect(try TestPDFFactory.rawPopupState(in: saved) == originalPopup)
        let savedOwner = try TestPDFFactory.rawFirstOwnerState(in: saved)
        #expect(savedOwner.contents == "edited owner note")
        #expect(savedOwner.richContents == nil)
    }

    @Test
    func editSaveUndoSaveRestoresOwnerStateAndKeepsPopupPrivateStateNeutral() throws {
        let source = TestPDFFactory.rawPopupGraph(
            shape: .reciprocal,
            includeNames: false,
            includePopupSentinels: true,
            includeOwnerSentinels: true
        )
        let originalOwner = try TestPDFFactory.rawFirstOwnerState(in: source)
        let originalPopup = try TestPDFFactory.rawPopupState(in: source)
        let document = try MathPDFDocument(data: source)
        let page = try #require(document.pdfDocument.page(at: 0))
        let highlight = try #require(page.annotations.first { $0.type == "Highlight" })
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false

        undoManager.beginUndoGrouping()
        #expect(document.updateContents(of: highlight, to: "edited owner note", undoManager: undoManager))
        undoManager.endUndoGrouping()
        let edited = try document.serializedData()
        let editedOwner = try TestPDFFactory.rawFirstOwnerState(in: edited)
        #expect(editedOwner.contents == "edited owner note")
        #expect(editedOwner.richContents == nil)
        #expect(editedOwner.name != nil)
        #expect(try TestPDFFactory.rawPopupState(in: edited) == originalPopup)

        undoManager.undo()
        let undone = try document.serializedData()
        #expect(try TestPDFFactory.rawFirstOwnerState(in: undone) == originalOwner)
        #expect(try TestPDFFactory.rawPopupState(in: undone) == originalPopup)
        try assertSingleReciprocalAnnotation(
            in: undone,
            ownerSubtype: "Highlight",
            contents: "owner note"
        )

        undoManager.redo()
        let redone = try document.serializedData()
        #expect(try TestPDFFactory.rawFirstOwnerState(in: redone) == editedOwner)
        #expect(try TestPDFFactory.rawPopupState(in: redone) == originalPopup)
    }

    @Test
    func editUndoRestoresAnImportedOwnerWithoutAPopup() throws {
        let source = TestPDFFactory.rawOwnerWithoutPopup()
        let originalOwner = try TestPDFFactory.rawFirstOwnerState(in: source)
        let document = try MathPDFDocument(data: source)
        let page = try #require(document.pdfDocument.page(at: 0))
        let highlight = try #require(page.annotations.first { $0.type == "Highlight" })
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false

        undoManager.beginUndoGrouping()
        #expect(document.updateContents(of: highlight, to: "edited owner note", undoManager: undoManager))
        undoManager.endUndoGrouping()
        let edited = try document.serializedData()
        try assertSingleReciprocalAnnotation(
            in: edited,
            ownerSubtype: "Highlight",
            contents: "edited owner note"
        )

        undoManager.undo()
        let undone = try document.serializedData()
        #expect(try TestPDFFactory.rawFirstOwnerState(in: undone) == originalOwner)
        #expect(try TestPDFFactory.rawAnnotationSubtypes(in: undone) == ["Highlight"])

        undoManager.redo()
        try assertSingleReciprocalAnnotation(
            in: document.serializedData(),
            ownerSubtype: "Highlight",
            contents: "edited owner note"
        )
    }

    @Test
    func newlyCreatedAnnotationsPreserveLiveAnnotsOrder() throws {
        let document = MathPDFDocument()
        let page = try #require(document.pdfDocument.page(at: 0))
        var annotations: [PDFAnnotation] = []
        for index in 0..<4 {
            let annotation = TestPDFFactory.annotation(
                .square,
                contents: "square-\(index)",
                bounds: CGRect(x: 80 + index, y: 500, width: 40, height: 40)
            )
            page.addAnnotation(annotation)
            #expect(document.updateContents(
                of: annotation,
                to: "registered-square-\(index)",
                undoManager: nil
            ))
            annotations.append(annotation)
        }

        let nameKey = PDFAnnotationKey(rawValue: "/NM")
        let reverseNameOrder = Array(annotations.reversed())
        for annotation in annotations {
            page.removeAnnotation(annotation)
        }
        for annotation in reverseNameOrder {
            page.addAnnotation(annotation)
        }
        let expectedNames = reverseNameOrder.compactMap {
            $0.value(forAnnotationKey: nameKey) as? String
        }

        #expect(try TestPDFFactory.rawAnnotationNames(in: document.serializedData()) == expectedNames)
    }

    @Test
    func visibleReorderPreservesInterleavedHiddenPopupSlot() throws {
        let document = try MathPDFDocument(
            data: TestPDFFactory.rawPopupGraph(shape: .reciprocal)
        )
        let page = try #require(document.pdfDocument.page(at: 0))
        let owner = try #require(page.annotations.first { $0.type == "Highlight" })
        var squares: [PDFAnnotation] = []
        for index in 0..<2 {
            let square = TestPDFFactory.annotation(
                .square,
                contents: "square-\(index)",
                bounds: CGRect(x: 80 + index * 50, y: 500, width: 40, height: 40)
            )
            page.addAnnotation(square)
            #expect(document.updateContents(
                of: square,
                to: "registered-square-\(index)",
                undoManager: nil
            ))
            squares.append(square)
        }

        for annotation in [owner] + squares {
            page.removeAnnotation(annotation)
        }
        for annotation in [squares[1], owner, squares[0]] {
            page.addAnnotation(annotation)
        }
        // Re-adding a PDFKit owner may also reinsert its attached Popup into
        // the page graph. Route one ordinary product mutation through the
        // document so the test's runtime graph matches MathPDF's invariant
        // before it asserts how the hidden slot is serialized.
        #expect(document.updateContents(
            of: owner,
            to: "owner note after visible reorder",
            undoManager: nil
        ))
        // The direct remove/re-add above is intentionally outside MathPDF's
        // mutation API. Normalize the synthetic presentation graph exactly as
        // the document does on load before exercising order reconciliation.
        for popup in page.annotations where popup.type == "Popup" {
            page.removeAnnotation(popup)
        }
        #expect(page.annotations.allSatisfy { $0.type != "Popup" })

        let nameKey = PDFAnnotationKey(rawValue: "/NM")
        let firstSquareName = try #require(
            squares[0].value(forAnnotationKey: nameKey) as? String
        )
        let secondSquareName = try #require(
            squares[1].value(forAnnotationKey: nameKey) as? String
        )
        #expect(
            try TestPDFFactory.rawAnnotationNames(in: document.serializedData())
                == [secondSquareName, "raw-popup", "raw-owner", firstSquareName]
        )

        document.removeAnnotation(squares[1], undoManager: nil)
        for annotation in [owner, squares[0]] {
            page.removeAnnotation(annotation)
        }
        for annotation in [squares[0], owner] {
            page.addAnnotation(annotation)
        }
        #expect(
            try TestPDFFactory.rawAnnotationNames(in: document.serializedData())
                == ["raw-popup", firstSquareName, "raw-owner"]
        )
    }

    @Test
    func lockedOwnerOrPopupRefusesMutationAndSurvivesAnUnrelatedSave() throws {
        for lockedPart in [LockedAnnotationPart.owner, .popup] {
            let source = TestPDFFactory.rawLockedPopupGraph(lockedPart)
            let originalOwner = try TestPDFFactory.rawFirstOwnerState(in: source)
            let originalPopup = try TestPDFFactory.rawPopupState(in: source)
            let document = try MathPDFDocument(data: source)
            let page = try #require(document.pdfDocument.page(at: 0))
            let highlight = try #require(page.annotations.first { $0.type == "Highlight" })

            #expect(!document.canEdit(highlight))
            #expect(!document.canChangeColor(of: highlight))
            #expect(!document.updateContents(of: highlight, to: "must not change", undoManager: nil))
            #expect(!document.updateHighlightColor(of: highlight, to: .systemGreen, undoManager: nil))
            document.removeAnnotation(highlight, undoManager: nil)
            #expect(page.annotations.contains { $0 === highlight })

            document.preamble = #"\newcommand{\Q}{\mathbb{Q}}"#
            let saved = try document.serializedData()
            #expect(try TestPDFFactory.rawFirstOwnerState(in: saved) == originalOwner)
            #expect(try TestPDFFactory.rawPopupState(in: saved) == originalPopup)
        }
    }

    @Test
    func oneSidedImportedPopupGraphsRepairWithoutChangingOwnerContents() throws {
        for shape in [PopupGraphShape.ownerOnly, .parentOnly] {
            let source = TestPDFFactory.rawPopupGraph(shape: shape)
            let document = try MathPDFDocument(data: source)
            let page = try #require(document.pdfDocument.page(at: 0))
            let highlight = try #require(page.annotations.first { $0.type == "Highlight" })
            #expect(highlight.contents == "owner note")
            #expect(document.editingError == nil)

            document.preamble = #"\newcommand{\Q}{\mathbb{Q}}"#
            let saved = try document.serializedData()
            let reloaded = try MathPDFDocument(data: saved)
            let savedPage = try #require(reloaded.pdfDocument.page(at: 0))
            let savedHighlight = try #require(
                savedPage.annotations.first { $0.type == "Highlight" }
            )
            _ = try #require(reloaded.popupCompanion(for: savedHighlight))
            #expect(savedHighlight.contents == "owner note")
            #expect(savedHighlight.popup == nil)
        }
    }

    @Test
    func exactLegacyOrphanRepairIsRuntimeOnlyUntilADirtySave() throws {
        let source = TestPDFFactory.rawLegacyOrphanGraph()
        let document = try MathPDFDocument(data: source)
        #expect(document.editingError == nil)

        let page = try #require(document.pdfDocument.page(at: 0))
        let highlight = try #require(page.annotations.first { $0.type == "Highlight" })
        _ = try #require(document.popupCompanion(for: highlight))
        #expect(highlight.contents == "legacy owner note")
        #expect(page.annotations.allSatisfy { $0.type != "Popup" })
        #expect(highlight.popup == nil)

        // Load-time inferred edges are deliberately pending persistence work,
        // not a user-visible document mutation. The cached no-op snapshot must
        // therefore remain the exact source revision.
        #expect(try document.serializedData() == source)
        #expect(try document.serializedData() == source)

        document.preamble = #"\newcommand{\Q}{\mathbb{Q}}"#
        let saved = try document.serializedData()
        #expect(saved != source)
        try assertSingleReciprocalAnnotation(
            in: saved,
            ownerSubtype: "Highlight",
            contents: "legacy owner note"
        )
        let reloaded = try MathPDFDocument(data: saved)
        let savedPage = try #require(reloaded.pdfDocument.page(at: 0))
        #expect(savedPage.annotations.filter { $0.type == "Text" }.isEmpty)
    }

    @Test
    func ambiguousLegacyOrphanRemainsReadOnly() throws {
        let source = TestPDFFactory.rawLegacyOrphanGraph(ambiguous: true)
        let document = try MathPDFDocument(data: source)
        #expect(document.editingError?.localizedDescription.contains("orphan Popup") == true)

        // Read-only inspection still has a byte-identical no-op path.
        #expect(try document.serializedData() == source)
        document.preamble = #"\newcommand{\Q}{\mathbb{Q}}"#
        do {
            _ = try document.serializedData()
            Issue.record("An ambiguous orphan Popup was serialized instead of rejected.")
        } catch {
            #expect(error.localizedDescription.contains("orphan Popup"))
        }
    }

    @Test
    func exactOffAnnotsPopupCloneRepairsOnDirtySaveWithoutDuplication() throws {
        let source = TestPDFFactory.rawOffAnnotsPopupCloneGraph()
        let document = try MathPDFDocument(data: source)
        #expect(document.editingError == nil)

        let page = try #require(document.pdfDocument.page(at: 0))
        let owner = try #require(page.annotations.first { $0.type == "Text" })
        _ = try #require(document.popupCompanion(for: owner))
        #expect(page.annotations.filter { $0.type == "Text" }.count == 1)
        #expect(page.annotations.filter { $0.type == "Popup" }.isEmpty)
        #expect(owner.popup == nil)

        #expect(try document.serializedData() == source)
        document.preamble = #"\newcommand{\Q}{\mathbb{Q}}"#
        let saved = try document.serializedData()
        try assertSingleReciprocalAnnotation(
            in: saved,
            ownerSubtype: "Text",
            contents: "off-array owner note"
        )
        let popupState = try TestPDFFactory.rawPopupState(in: saved)
        #expect(popupState.contents == "popup-private")
        #expect(popupState.modificationDate == "D:20260714010101Z")
        #expect(popupState.flags == 4)
        #expect(popupState.isOpen)
        #expect(popupState.hasAppearance)
        #expect(popupState.sentinel == "keep-me")
        #expect(popupState.name != nil)
    }

    @Test
    func nearCloneOffAnnotsPopupRemainsReadOnly() throws {
        let document = try MathPDFDocument(
            data: TestPDFFactory.rawOffAnnotsPopupCloneGraph(cloneMatches: false)
        )
        #expect(document.editingError?.localizedDescription.contains("unsupported off-page") == true)
        document.preamble = #"\newcommand{\Q}{\mathbb{Q}}"#

        do {
            _ = try document.serializedData()
            Issue.record("A near-clone off-/Annots Popup was serialized instead of rejected.")
        } catch {
            #expect(error.localizedDescription.contains("unsupported off-page"))
        }
    }

    @Test
    func deleteUndoPreservesImportedPopupMetadataWithoutInventingNames() throws {
        let source = TestPDFFactory.rawPopupGraph(
            shape: .reciprocal,
            includeNames: false,
            includePopupSentinels: true
        )
        let originalState = try TestPDFFactory.rawPopupState(in: source)
        let document = try MathPDFDocument(data: source)
        let page = try #require(document.pdfDocument.page(at: 0))
        let highlight = try #require(page.annotations.first { $0.type == "Highlight" })
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        undoManager.beginUndoGrouping()
        document.removeAnnotation(highlight, undoManager: undoManager)
        undoManager.endUndoGrouping()
        undoManager.undo()

        #expect(highlight.contents == "owner note")
        let saved = try document.serializedData()
        let savedState = try TestPDFFactory.rawPopupState(in: saved)
        #expect(savedState == originalState)
    }

    @Test
    func duplicateDurableAnnotationNamesFailClosed() throws {
        let document = try MathPDFDocument(data: TestPDFFactory.rawDuplicateNameGraph())
        #expect(document.editingError?.localizedDescription.contains("not unique") == true)
        document.preamble = #"\newcommand{\Q}{\mathbb{Q}}"#

        do {
            _ = try document.serializedData()
            Issue.record("A duplicate /NM graph was serialized instead of rejected.")
        } catch {
            #expect(error.localizedDescription.contains("not unique"))
        }
    }

    @Test
    func durableAnnotationNamesMayRepeatOnDifferentPages() throws {
        let source = TestPDFFactory.rawCrossPageDuplicateNames()
        let document = try MathPDFDocument(data: source)
        #expect(document.editingError == nil)
        #expect(try document.serializedData() == source)

        document.preamble = #"\newcommand{\Q}{\mathbb{Q}}"#
        let saved = try document.serializedData()
        let reloaded = try MathPDFDocument(data: saved)
        #expect(reloaded.editingError == nil)
        #expect(reloaded.pdfDocument.pageCount == 2)
        let nameKey = PDFAnnotationKey(rawValue: "/NM")
        for pageIndex in 0..<2 {
            let page = try #require(reloaded.pdfDocument.page(at: pageIndex))
            let annotation = try #require(page.annotations.first { $0.type == "Highlight" })
            #expect(annotation.value(forAnnotationKey: nameKey) as? String == "reused-across-pages")
        }
    }

    @Test
    func interleavedDocumentsNeverLeakAnnotationOrPreambleState() throws {
        let firstDocument = MathPDFDocument()
        let secondDocument = MathPDFDocument()
        let firstPage = try #require(firstDocument.pdfDocument.page(at: 0))
        let secondPage = try #require(secondDocument.pdfDocument.page(at: 0))
        let firstNote = try #require(firstDocument.addTextNote(
            on: firstPage,
            at: CGPoint(x: 100, y: 140),
            undoManager: nil
        ))
        let secondNote = try #require(secondDocument.addTextNote(
            on: secondPage,
            at: CGPoint(x: 180, y: 220),
            undoManager: nil
        ))

        firstDocument.preamble = #"\newcommand{\A}{A}"#
        secondDocument.preamble = #"\newcommand{\B}{B}"#
        firstDocument.updateContents(of: firstNote, to: "A1", undoManager: nil)
        let a1 = try firstDocument.serializedData()
        secondDocument.updateContents(of: secondNote, to: "B1", undoManager: nil)
        let b1 = try secondDocument.serializedData()
        firstDocument.updateContents(of: firstNote, to: "A2", undoManager: nil)
        let a2 = try firstDocument.serializedData()
        secondDocument.updateContents(of: secondNote, to: "B2", undoManager: nil)
        let b2 = try secondDocument.serializedData()

        try assertSingleTextNote(in: a1, contents: "A1", preamble: #"\newcommand{\A}{A}"#)
        try assertSingleTextNote(in: b1, contents: "B1", preamble: #"\newcommand{\B}{B}"#)
        try assertSingleTextNote(in: a2, contents: "A2", preamble: #"\newcommand{\A}{A}"#)
        try assertSingleTextNote(in: b2, contents: "B2", preamble: #"\newcommand{\B}{B}"#)
    }

    @Test
    func untrackedPDFKitMutationFailsClosed() throws {
        let document = MathPDFDocument()
        let page = try #require(document.pdfDocument.page(at: 0))
        page.addAnnotation(TestPDFFactory.annotation(
            .widget,
            contents: "untracked",
            bounds: CGRect(x: 80, y: 80, width: 120, height: 24)
        ))
        document.preamble = #"\newcommand{\Q}{\mathbb{Q}}"#

        do {
            _ = try document.serializedData()
            Issue.record("An untracked PDFKit mutation was serialized instead of rejected.")
        } catch let error as PDFPersistenceError {
            guard case let .mappingFailed(reason) = error else {
                Issue.record("Unexpected persistence error: \(error)")
                return
            }
            #expect(reason.contains("untracked Widget"))
        }
    }

    @Test
    func directlyRemovedTrackedAnnotationFailsClosed() throws {
        let document = MathPDFDocument()
        let page = try #require(document.pdfDocument.page(at: 0))
        let annotation = TestPDFFactory.annotation(
            .square,
            contents: "tracked",
            bounds: CGRect(x: 80, y: 80, width: 40, height: 40)
        )
        page.addAnnotation(annotation)
        #expect(document.updateContents(of: annotation, to: "registered", undoManager: nil))
        page.removeAnnotation(annotation)

        do {
            _ = try document.serializedData()
            Issue.record("A directly removed tracked annotation was silently resurrected.")
        } catch let error as PDFPersistenceError {
            guard case let .mappingFailed(reason) = error else {
                Issue.record("Unexpected persistence error: \(error)")
                return
            }
            #expect(reason.contains("visible annotation set changed"))
        }
    }

    @Test
    func directlyMovedTrackedAnnotationFailsClosed() throws {
        let source = try #require(TestPDFFactory.document(pageCount: 2).dataRepresentation())
        let document = try MathPDFDocument(data: source)
        let firstPage = try #require(document.pdfDocument.page(at: 0))
        let secondPage = try #require(document.pdfDocument.page(at: 1))
        let annotation = TestPDFFactory.annotation(
            .square,
            contents: "tracked",
            bounds: CGRect(x: 80, y: 80, width: 40, height: 40)
        )
        firstPage.addAnnotation(annotation)
        #expect(document.updateContents(of: annotation, to: "registered", undoManager: nil))
        firstPage.removeAnnotation(annotation)
        secondPage.addAnnotation(annotation)

        do {
            _ = try document.serializedData()
            Issue.record("A directly moved tracked annotation was serialized on two pages.")
        } catch let error as PDFPersistenceError {
            guard case let .mappingFailed(reason) = error else {
                Issue.record("Unexpected persistence error: \(error)")
                return
            }
            #expect(reason.contains("moved from page 1 to page 2"))
        }
    }

    @Test
    func importsPreambleFromExternallyAuthoredStringKeyedMetadata() throws {
        let base = MathPDFDocument()
        let source = #"\newcommand{\Q}{\mathbb{Q}}"#
        let encoded = try #require(source.data(using: .utf8)).base64EncodedString()
        var attributes = base.pdfDocument.documentAttributes ?? [:]
        attributes[PDFDocumentAttribute.keywordsAttribute.rawValue] = [
            "research",
            "MathPDF-Preamble-v1:" + encoded,
        ]
        base.pdfDocument.documentAttributes = attributes

        let imported = try MathPDFDocument(data: try #require(base.pdfDocument.dataRepresentation()))
        #expect(imported.preamble == source)

        let reloaded = try MathPDFDocument(data: imported.serializedData())
        let keywords = reloaded.pdfDocument.documentAttributes?[PDFDocumentAttribute.keywordsAttribute.rawValue] as? [String]
        #expect(reloaded.preamble == source)
        #expect(keywords?.contains("research") == true)
        #expect(keywords?.filter { $0.hasPrefix("MathPDF-Preamble-v1:") }.count == 1)
    }

    @Test
    func corruptInputFailsWithoutProducingAPartialDocument() {
        #expect(throws: CocoaError.self) {
            _ = try MathPDFDocument(data: Data("not a PDF".utf8))
        }
    }

    private func assertHighlightGraph(
        in data: Data,
        expected: [String: String]
    ) throws {
        let reloaded = try #require(PDFDocument(data: data))
        let page = try #require(reloaded.page(at: 0))
        let highlights = page.annotations.filter { $0.type == "Highlight" }
        let popups = page.annotations.filter { $0.type == "Popup" }
        #expect(highlights.count == expected.count)
        #expect(popups.count == expected.count)

        let nameKey = PDFAnnotationKey(rawValue: "/NM")
        for highlight in highlights {
            let name = try #require(highlight.value(forAnnotationKey: nameKey) as? String)
            #expect(highlight.contents == expected[name])
            let popup = try #require(highlight.popup)
            #expect(page.annotations.contains { $0 === popup })
            #expect((popup.value(forAnnotationKey: .parent) as? PDFAnnotation) === highlight)
        }
    }

    private func assertSingleReciprocalAnnotation(
        in data: Data,
        ownerSubtype: String,
        contents: String
    ) throws {
        let reloaded = try #require(PDFDocument(data: data))
        let page = try #require(reloaded.page(at: 0))
        let owners = page.annotations.filter { $0.type == ownerSubtype }
        let popups = page.annotations.filter { $0.type == "Popup" }
        #expect(owners.count == 1)
        #expect(popups.count == 1)
        let owner = try #require(owners.first)
        let popup = try #require(popups.first)
        #expect(owner.contents == contents)
        #expect(owner.popup === popup)
        #expect((popup.value(forAnnotationKey: .parent) as? PDFAnnotation) === owner)
    }

    private func assertSingleTextNote(
        in data: Data,
        contents: String,
        preamble: String
    ) throws {
        let reloaded = try #require(PDFDocument(data: data))
        let page = try #require(reloaded.page(at: 0))
        let notes = page.annotations.filter { $0.type == "Text" }
        #expect(notes.count == 1)
        let note = try #require(notes.first)
        #expect(note.contents == contents)
        let popup = try #require(note.popup)
        #expect(page.annotations.filter { $0.type == "Popup" }.count == 1)
        #expect((popup.value(forAnnotationKey: .parent) as? PDFAnnotation) === note)
        let mathDocument = try MathPDFDocument(data: data)
        #expect(mathDocument.preamble == preamble)
    }
}

@MainActor
@Suite("Reader state")
struct ReaderDocumentControllerTests {
    @Test
    func highlightWithNoteRejectsAMultiPageSelectionBeforeMutation() throws {
        let source = TestPDFFactory.textDocument(pages: ["first page", "second page"])
        let data = try #require(source.dataRepresentation())
        let document = try MathPDFDocument(data: data)
        let firstPage = try #require(document.pdfDocument.page(at: 0))
        let secondPage = try #require(document.pdfDocument.page(at: 1))
        let firstSelection = try #require(firstPage.selection(for: NSRange(location: 0, length: 5)))
        let secondSelection = try #require(secondPage.selection(for: NSRange(location: 0, length: 6)))
        let combinedSelection = PDFSelection(document: document.pdfDocument)
        combinedSelection.add(firstSelection)
        combinedSelection.add(secondSelection)
        let controller = ReaderDocumentController(document: document)

        let created = controller.addHighlightWithNote(
            from: combinedSelection,
            undoManager: nil
        )

        #expect(created == nil)
        #expect(controller.annotationAuthoringNotice == .multiPageHighlightNote)
        #expect(firstPage.annotations.allSatisfy { $0.type != "Highlight" })
        #expect(secondPage.annotations.allSatisfy { $0.type != "Highlight" })
    }

    @Test
    func pageActivationNeverCreatesANavigationRequest() throws {
        let document = MathPDFDocument()
        let page = try #require(document.pdfDocument.page(at: 0))
        let annotation = TestPDFFactory.annotation(.text, contents: "visible", bounds: .init(x: 90, y: 500, width: 24, height: 24))
        page.addAnnotation(annotation)
        let controller = ReaderDocumentController(document: document)

        let note = try #require(controller.annotationActivated(annotation))
        #expect(controller.selectedNoteID == note.id)
        #expect(controller.navigationRequest == nil)

        controller.selectNote(note)
        #expect(controller.navigationRequest?.opensNote == true)
        #expect(controller.navigationRequest?.pageIndex == 0)
        #expect(controller.navigationRequest?.bounds == annotation.bounds)
        #expect(controller.navigationRequest?.startsEditing == false)

        controller.presentNote(note, startsEditing: true)
        #expect(controller.navigationRequest?.opensNote == true)
        #expect(controller.navigationRequest?.startsEditing == true)
        #expect(controller.navigationRequest?.annotation === annotation)
    }

    @Test
    func activationSelectsTheExactAnnotationWhenContentsMatch() throws {
        let document = MathPDFDocument()
        let page = try #require(document.pdfDocument.page(at: 0))
        let first = TestPDFFactory.annotation(.text, contents: "same", bounds: .init(x: 90, y: 500, width: 24, height: 24))
        let second = TestPDFFactory.annotation(.text, contents: "same", bounds: .init(x: 490, y: 80, width: 24, height: 24))
        page.addAnnotation(first)
        page.addAnnotation(second)
        let controller = ReaderDocumentController(document: document)

        let activated = try #require(controller.annotationActivated(second))
        #expect(activated.annotation === second)
        #expect(activated.bounds == second.bounds)
        #expect(controller.selectedNoteID == activated.id)
        #expect(controller.selectedNoteID != controller.notes.first { $0.annotation === first }?.id)

        document.updateContents(of: second, to: "changed", undoManager: nil)
        #expect(controller.selectedNoteID == activated.id)
        #expect(controller.notes.first { $0.annotation === second }?.contents == "changed")
    }

    @Test
    func deletingTheSelectedNoteClearsSelectionAndUndoRestoresTheNote() throws {
        let document = MathPDFDocument()
        let page = try #require(document.pdfDocument.page(at: 0))
        let annotation = TestPDFFactory.annotation(.text, contents: "delete me", bounds: .init(x: 90, y: 500, width: 24, height: 24))
        page.addAnnotation(annotation)
        let controller = ReaderDocumentController(document: document)
        let note = try #require(controller.annotationActivated(annotation))
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false

        undoManager.beginUndoGrouping()
        controller.removeNote(note, undoManager: undoManager)
        undoManager.endUndoGrouping()

        #expect(controller.selectedNoteID == nil)
        #expect(controller.notes.isEmpty)

        undoManager.undo()
        #expect(controller.notes.count == 1)
        #expect(controller.notes.first?.annotation === annotation)
        #expect(controller.selectedNoteID == nil)
    }

    @Test
    func sidebarIDSelectionNavigatesButProgrammaticActivationDoesNot() throws {
        let document = MathPDFDocument()
        let page = try #require(document.pdfDocument.page(at: 0))
        let first = TestPDFFactory.annotation(
            .text,
            contents: "first",
            bounds: .init(x: 90, y: 500, width: 24, height: 24)
        )
        let second = TestPDFFactory.annotation(
            .text,
            contents: "second",
            bounds: .init(x: 120, y: 500, width: 24, height: 24)
        )
        page.addAnnotation(first)
        page.addAnnotation(second)
        let controller = ReaderDocumentController(document: document)
        let firstNote = try #require(controller.notes.first { $0.annotation === first })
        let secondNote = try #require(controller.notes.first { $0.annotation === second })

        _ = controller.annotationActivated(first)
        #expect(controller.selectedNoteID == firstNote.id)
        #expect(controller.navigationRequest == nil)

        controller.selectNote(id: secondNote.id)
        #expect(controller.selectedNoteID == secondNote.id)
        #expect(controller.navigationRequest?.noteID == secondNote.id)
        #expect(controller.navigationRequest?.opensNote == true)
    }

    @Test
    func sidebarReactivationWaitsUntilTheSelectedSurfaceIsClosed() throws {
        let document = MathPDFDocument()
        let page = try #require(document.pdfDocument.page(at: 0))
        let annotation = TestPDFFactory.annotation(
            .text,
            contents: "same row",
            bounds: .init(x: 90, y: 500, width: 24, height: 24)
        )
        page.addAnnotation(annotation)
        let controller = ReaderDocumentController(document: document)
        let note = try #require(controller.notes.first)

        controller.selectNote(note)
        let firstToken = try #require(controller.navigationRequest?.token)
        #expect(controller.pendingPresentedNoteID == note.id)

        controller.selectNote(note)
        #expect(controller.navigationRequest?.token == firstToken)

        controller.annotationPresentationChanged(noteID: note.id, isPresented: true)
        #expect(controller.pendingPresentedNoteID == nil)
        #expect(controller.presentedNoteID == note.id)
        controller.selectNote(note)
        #expect(controller.navigationRequest?.token == firstToken)

        controller.annotationPresentationChanged(noteID: note.id, isPresented: false)
        controller.selectNote(note)
        #expect(controller.navigationRequest?.token != firstToken)
        #expect(controller.pendingPresentedNoteID == note.id)
    }

    @Test
    func documentWindowsKeepIndependentReaderAndDocumentState() throws {
        let firstDocument = MathPDFDocument()
        let secondDocument = MathPDFDocument()
        let firstPage = try #require(firstDocument.pdfDocument.page(at: 0))
        let secondPage = try #require(secondDocument.pdfDocument.page(at: 0))
        let firstAnnotation = TestPDFFactory.annotation(.text, contents: "first", bounds: .init(x: 90, y: 500, width: 24, height: 24))
        let secondAnnotation = TestPDFFactory.annotation(.text, contents: "second", bounds: .init(x: 90, y: 500, width: 24, height: 24))
        firstPage.addAnnotation(firstAnnotation)
        secondPage.addAnnotation(secondAnnotation)
        let first = ReaderDocumentController(document: firstDocument)
        let second = ReaderDocumentController(document: secondDocument)
        first.sidebarMode = .notes
        first.searchText = "Berkovich"
        first.readerTool = .textNote
        firstDocument.preamble = #"\newcommand{\Q}{\mathbb{Q}}"#
        firstDocument.updateContents(of: firstAnnotation, to: "changed first", undoManager: nil)
        first.isPreambleInspectorPresented = true

        #expect(second.sidebarMode == .contents)
        #expect(second.searchText.isEmpty)
        #expect(second.readerTool == .browse)
        #expect(secondDocument.preamble.isEmpty)
        #expect(second.notes.first?.contents == "second")
        #expect(second.selectedNoteID == nil)
        #expect(!second.isPreambleInspectorPresented)
    }
}

@MainActor
@Suite("Reader viewport")
struct ReaderViewportTests {
    @Test
    func replacingTheDocumentClearsSearchStateFromThePreviousDocument() throws {
        let firstDocument = TestPDFFactory.textDocument("alpha")
        let secondDocument = TestPDFFactory.textDocument("beta")
        let view = PDFView(frame: CGRect(x: 0, y: 0, width: 800, height: 640))
        view.document = firstDocument
        let proxy = PDFViewProxy()
        proxy.attach(view)
        proxy.find("alpha")
        #expect(proxy.searchQuery == "alpha")

        view.document = secondDocument
        proxy.attach(view)

        #expect(proxy.searchQuery.isEmpty)
        #expect(!proxy.isSearching)
        #expect(proxy.searchResultCount == 0)
        #expect(proxy.searchResultIndex == 0)
    }

    @Test
    func revealingAComfortablyVisibleTargetIsAnExactViewportNoOp() throws {
        let document = TestPDFFactory.document(pageCount: 2)
        let view = PDFView(frame: CGRect(x: 0, y: 0, width: 800, height: 640))
        view.displayMode = .singlePageContinuous
        view.displaysPageBreaks = true
        view.document = document
        view.autoScales = false
        view.scaleFactor = 1.25
        view.layoutSubtreeIfNeeded()

        let documentView = try #require(view.documentView)
        let visibleBefore = documentView.visibleRect
        let visibleCenterInPDFView = view.convert(
            CGPoint(x: visibleBefore.midX, y: visibleBefore.midY),
            from: documentView
        )
        let page = try #require(view.page(for: visibleCenterInPDFView, nearest: true))
        let centerOnPage = view.convert(visibleCenterInPDFView, to: page)
        let target = CGRect(x: centerOnPage.x - 2, y: centerOnPage.y - 2, width: 4, height: 4)
        let pageBefore = view.currentPage
        let scaleBefore = view.scaleFactor

        view.reveal(target, on: page, padding: 24)

        #expect(view.currentPage === pageBefore)
        #expect(view.scaleFactor == scaleBefore)
        #expect(documentView.visibleRect.origin == visibleBefore.origin)
    }

    @Test
    func sidebarRevealUpdatesThePageWithoutChangingScale() throws {
        let document = TestPDFFactory.document(pageCount: 3)
        let view = PDFView(frame: CGRect(x: 0, y: 0, width: 800, height: 640))
        view.displayMode = .singlePageContinuous
        view.displaysPageBreaks = true
        view.document = document
        view.autoScales = false
        view.scaleFactor = 1
        view.layoutSubtreeIfNeeded()

        let originalPage = try #require(document.page(at: 0))
        let targetPage = try #require(document.page(at: 2))
        #expect(view.currentPage === originalPage)
        let originalScale = view.scaleFactor

        view.reveal(CGRect(x: 70, y: 600, width: 120, height: 20), on: targetPage, padding: 24)
        #expect(view.currentPage === targetPage)
        #expect(view.scaleFactor == originalScale)
    }

    @Test
    func samePageSidebarRevealCreatesABackDestination() throws {
        let document = TestPDFFactory.document(pageCount: 1)
        let view = PDFView(frame: CGRect(x: 0, y: 0, width: 600, height: 320))
        view.displayMode = .singlePageContinuous
        view.displaysPageBreaks = true
        view.document = document
        view.autoScales = false
        view.scaleFactor = 1
        view.layoutSubtreeIfNeeded()

        let page = try #require(document.page(at: 0))
        let documentView = try #require(view.documentView)
        let originBefore = documentView.visibleRect.origin
        let scaleBefore = view.scaleFactor

        view.reveal(CGRect(x: 60, y: 24, width: 100, height: 18), on: page, padding: 24)

        #expect(view.canGoBack)
        #expect(documentView.visibleRect.origin != originBefore)
        #expect(view.scaleFactor == scaleBefore)
        let revealedOrigin = documentView.visibleRect.origin

        view.goBack(nil)
        #expect(abs(documentView.visibleRect.origin.y - originBefore.y) <= 12)
        #expect(view.scaleFactor == scaleBefore)

        view.goForward(nil)
        #expect(abs(documentView.visibleRect.origin.y - revealedOrigin.y) <= 12)
        #expect(view.scaleFactor == scaleBefore)
    }
}

@MainActor
@Suite("Reader annotation ownership")
struct ReaderAnnotationOwnershipTests {
    @Test
    func noteActivationReservesOnlyAnUnmodifiedSingleClick() {
        #expect(AnnotationActivationGesturePolicy.interceptsForNoteActivation(
            clickCount: 1,
            modifierFlags: []
        ))
        #expect(!AnnotationActivationGesturePolicy.interceptsForNoteActivation(
            clickCount: 2,
            modifierFlags: []
        ))
        #expect(!AnnotationActivationGesturePolicy.interceptsForNoteActivation(
            clickCount: 3,
            modifierFlags: []
        ))
        for modifier: NSEvent.ModifierFlags in [.shift, .control, .option, .command] {
            #expect(!AnnotationActivationGesturePolicy.interceptsForNoteActivation(
                clickCount: 1,
                modifierFlags: modifier
            ))
        }
    }

    @Test
    func openEditingSessionReconcilesDocumentUndoWithoutLosingFocus() {
        var liveUpdates: [String] = []
        let session = AnnotationNoteEditingSession(
            contents: "before",
            color: AnnotationColorChoice.yellow.nsColor,
            startsEditing: true,
            onLiveUpdate: { liveUpdates.append($0); return true },
            onCommit: { _ in },
            onEditingChanged: { _ in }
        )

        session.replaceDraft(with: "draft")
        session.acceptColorChange(.green)
        session.reconcileDocumentState(
            contents: "restored",
            color: AnnotationColorChoice.yellow.nsColor
        )

        #expect(session.isEditing)
        #expect(session.draft == "restored")
        #expect(session.selectedColor == .yellow)
        #expect(liveUpdates == ["draft"])
        session.finishEditing()
        #expect(!session.isEditing)
    }

    @Test
    func activatingAnExistingEmptyAnnotationOpensReadFirst() throws {
        #expect(!AnnotationSurfaceEditingPolicy.startsEditing(
            noteContents: "",
            canEditContents: true,
            requested: false
        ))
        #expect(AnnotationSurfaceEditingPolicy.startsEditing(
            noteContents: "",
            canEditContents: true,
            requested: true
        ))
    }

    @Test
    func presentationGraphOmitsPopupWhileSavedGraphRemainsReciprocal() throws {
        let mathDocument = try MathPDFDocument(
            data: TestPDFFactory.rawPopupGraph(shape: .reciprocal)
        )
        let livePage = try #require(mathDocument.pdfDocument.page(at: 0))
        let liveHighlight = try #require(
            livePage.annotations.first { $0.type == "Highlight" }
        )
        let hiddenPopup = try #require(mathDocument.popupCompanion(for: liveHighlight))

        #expect(livePage.annotations.allSatisfy { $0.type != "Popup" })
        #expect(hiddenPopup.page == nil)
        #expect(liveHighlight.popup == nil)

        mathDocument.preamble = #"\newcommand{\Q}{\mathbb{Q}}"#
        let saved = try mathDocument.serializedData()
        let diskDocument = try #require(PDFDocument(data: saved))
        let diskPage = try #require(diskDocument.page(at: 0))
        let diskHighlight = try #require(
            diskPage.annotations.first { $0.type == "Highlight" }
        )
        let diskPopup = try #require(diskHighlight.popup)

        #expect(diskPage.annotations.filter { $0.type == "Popup" }.count == 1)
        #expect(diskPage.annotations.contains { $0 === diskPopup })
        #expect((diskPopup.value(forAnnotationKey: .parent) as? PDFAnnotation) === diskHighlight)
        #expect(diskPage.annotations.allSatisfy { $0.type != "Text" })
    }

    @Test
    func configuredReaderKeepsDocumentSuppressedPopupState() throws {
        let mathDocument = try MathPDFDocument(
            data: TestPDFFactory.rawPopupGraph(
                shape: .reciprocal,
                includePopupSentinels: true
            )
        )
        let document = mathDocument.pdfDocument
        let page = try #require(document.page(at: 0))
        let highlight = try #require(page.annotations.first { $0.type == "Highlight" })
        let popup = try #require(mathDocument.popupCompanion(for: highlight))
        #expect(!popup.isOpen)
        #expect(!page.annotations.contains { $0 === popup })
        #expect(popup.page == nil)
        #expect(highlight.popup == nil)

        let container = ReaderContainerView(frame: CGRect(x: 0, y: 0, width: 800, height: 640))
        container.configure(
            document: document,
            proxy: PDFViewProxy(),
            noteForAnnotation: { annotation in
                PDFNoteExtractor.note(for: annotation, pageIndex: 0, includeEmptyContents: true)
            },
            capabilitiesForAnnotation: { annotation in
                AnnotationNoteCapabilities(
                    canEditContents: mathDocument.canEdit(annotation),
                    canDelete: mathDocument.canEdit(annotation),
                    canChangeColor: mathDocument.canChangeColor(of: annotation),
                    editingUnavailableReason: nil,
                    colorUnavailableReason: nil
                )
            },
            onUpdateNote: { _, _ in true },
            onCommitNoteEdit: { _, _ in },
            onDeleteNote: { _ in },
            onUpdateColor: { _, _, _ in true },
            onCancelTextNote: {},
            onCreateTextNote: { _, _ in nil },
            preamble: "",
            annotationRevision: mathDocument.annotationRevision,
            enforceRuntimeAnnotationPresentation: mathDocument.enforceRuntimeAnnotationPresentation
        )

        #expect(!popup.isOpen)
        #expect(highlight.popup == nil)
        #expect(page.annotations.allSatisfy { $0.type != "Popup" })
        #expect(PDFNoteExtractor.extractNotes(from: document).count == 1)

        // Model PDFKit's observed lazy reinsertion after an unrelated page
        // operation. The reader's layout guard must remove the native Popup
        // again while keeping the reciprocal owner edge in persistence only.
        page.addAnnotation(popup)
        highlight.popup = popup
        _ = popup.setValue(highlight, forAnnotationKey: .parent)
        #expect(page.annotations.contains { $0 === popup })
        container.needsLayout = true
        container.layoutSubtreeIfNeeded()
        #expect(page.annotations.allSatisfy { $0.type != "Popup" })
        #expect(highlight.popup == nil)
        #expect(mathDocument.popupCompanion(for: highlight) === popup)
    }
}

private enum PopupGraphShape {
    case ownerOnly
    case parentOnly
    case reciprocal
}

private enum LockedAnnotationPart: Equatable {
    case owner
    case popup
}

private struct RawPopupState: Equatable {
    let contents: String?
    let modificationDate: String?
    let flags: Int
    let isOpen: Bool
    let hasAppearance: Bool
    let sentinel: String?
    let name: String?
    let richContents: String?
    let color: [Double]
}

private struct RawOwnerState: Equatable {
    let contents: String?
    let modificationDate: String?
    let richContents: String?
    let name: String?
    let flags: Int
    let sentinel: String?
    let hasPopup: Bool
}

@MainActor
private enum TestPDFFactory {
    static func document(pageCount: Int) -> PDFDocument {
        let data = NSMutableData()
        let consumer = CGDataConsumer(data: data)!
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = CGContext(consumer: consumer, mediaBox: &box, nil)!
        for _ in 0..<pageCount {
            context.beginPDFPage(nil)
            context.endPDFPage()
        }
        context.closePDF()
        return PDFDocument(data: data as Data)!
    }

    static func textDocument(_ text: String) -> PDFDocument {
        textDocument(pages: [text])
    }

    static func textDocument(pages: [String]) -> PDFDocument {
        let data = NSMutableData()
        let consumer = CGDataConsumer(data: data)!
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = CGContext(consumer: consumer, mediaBox: &box, nil)!
        for text in pages {
            context.beginPDFPage(nil)
            let attributed = NSAttributedString(
                string: text,
                attributes: [
                    NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 16, nil),
                    NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1),
                ]
            )
            let framesetter = CTFramesetterCreateWithAttributedString(attributed)
            let path = CGPath(rect: CGRect(x: 72, y: 500, width: 468, height: 200), transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(), path, nil)
            CTFrameDraw(frame, context)
            context.endPDFPage()
        }
        context.closePDF()
        return PDFDocument(data: data as Data)!
    }

    static func annotation(_ subtype: PDFAnnotationSubtype, contents: String, bounds: CGRect) -> PDFAnnotation {
        let annotation = PDFAnnotation(bounds: bounds, forType: subtype, withProperties: nil)
        annotation.contents = contents
        return annotation
    }

    static func rawPopupGraph(
        shape: PopupGraphShape,
        includeNames: Bool = true,
        includePopupSentinels: Bool = false,
        includeOwnerSentinels: Bool = false
    ) -> Data {
        let ownerEdge = shape == .parentOnly ? "" : "/Popup 6 0 R"
        let parentEdge = shape == .ownerOnly ? "" : "/Parent 5 0 R"
        let ownerName = includeNames ? "/NM (raw-owner)" : ""
        let popupName = includeNames ? "/NM (raw-popup)" : ""
        let popupSentinels = includePopupSentinels
            ? "/Contents (popup-private) /M (D:20260714010101Z) /RC (popup-rich) /C [1 0 0] /F 4 /Open true /AP << /N 7 0 R >> /XMathPDFSentinel (keep-me)"
            : ""
        let ownerSentinels = includeOwnerSentinels
            ? "/M (D:20260713010101Z) /RC (owner-rich) /XMathPDFOwnerSentinel (keep-owner)"
            : ""

        var objects = [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << >> /Contents 4 0 R /Annots [5 0 R 6 0 R] >>",
            "<< /Length 0 >>\nstream\n\nendstream",
            "<< /Type /Annot /Subtype /Highlight /Rect [80 600 240 618] /QuadPoints [80 618 240 618 80 600 240 600] /Contents (owner note) /C [1 1 0] \(ownerName) \(ownerEdge) \(ownerSentinels) >>",
            "<< /Type /Annot /Subtype /Popup /Rect [250 500 430 620] \(popupName) \(parentEdge) \(popupSentinels) >>",
        ]
        if includePopupSentinels {
            objects.append(
                "<< /Type /XObject /Subtype /Form /BBox [0 0 10 10] /Resources << >> /Length 0 >>\nstream\n\nendstream"
            )
        }
        return rawPDF(objects: objects)
    }

    static func rawOwnerWithoutPopup() -> Data {
        rawPDF(objects: [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << >> /Contents 4 0 R /Annots [5 0 R] >>",
            "<< /Length 0 >>\nstream\n\nendstream",
            "<< /Type /Annot /Subtype /Highlight /Rect [80 600 240 618] /QuadPoints [80 618 240 618 80 600 240 600] /Contents (owner note) /C [1 1 0] /M (D:20260713010101Z) /RC (owner-rich) /XMathPDFOwnerSentinel (keep-owner) >>",
        ])
    }

    static func rawLockedPopupGraph(_ lockedPart: LockedAnnotationPart) -> Data {
        let ownerFlags = lockedPart == .owner ? 64 : 4
        let popupFlags = lockedPart == .popup ? 64 : 4
        return rawPDF(objects: [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << >> /Contents 4 0 R /Annots [5 0 R 6 0 R] >>",
            "<< /Length 0 >>\nstream\n\nendstream",
            "<< /Type /Annot /Subtype /Highlight /Rect [80 600 240 618] /QuadPoints [80 618 240 618 80 600 240 600] /Contents (locked owner note) /NM (locked-owner) /C [1 1 0] /F \(ownerFlags) /Popup 6 0 R /XMathPDFOwnerSentinel (keep-owner) >>",
            "<< /Type /Annot /Subtype /Popup /Rect [250 500 430 620] /NM (locked-popup) /C [1 0 0] /F \(popupFlags) /Parent 5 0 R /Contents (popup-private) /M (D:20260714010101Z) /RC (popup-rich) /Open true /XMathPDFSentinel (keep-me) >>",
        ])
    }

    static func rawLegacyOrphanGraph(ambiguous: Bool = false) -> Data {
        let owner = "<< /Type /Annot /Subtype /Highlight /Rect [80 600 240 618] /QuadPoints [80 618 240 618 80 600 240 600] /Contents (legacy owner note) /C [1 1 0] /F 4 /AP << /N \(ambiguous ? 8 : 7) 0 R >> >>"
        let popup = "<< /Type /Annot /Subtype /Popup /Rect [244 622 316 658] /C [1 1 0] /F 4 /M (D:20260714010101Z) >>"

        if ambiguous {
            return rawPDF(objects: [
                "<< /Type /Catalog /Pages 2 0 R >>",
                "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
                "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << >> /Contents 4 0 R /Annots [5 0 R 6 0 R 7 0 R] >>",
                "<< /Length 0 >>\nstream\n\nendstream",
                owner,
                popup,
                "<< /Type /Annot /Subtype /Highlight /Rect [80 600 240 618] /QuadPoints [80 618 240 618 80 600 240 600] /Contents (second possible owner) /C [1 1 0] /F 4 /AP << /N 8 0 R >> >>",
                "<< /Type /XObject /Subtype /Form /BBox [0 0 160 18] /Resources << >> /Length 0 >>\nstream\n\nendstream",
            ])
        }

        return rawPDF(objects: [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << >> /Contents 4 0 R /Annots [5 0 R 6 0 R] >>",
            "<< /Length 0 >>\nstream\n\nendstream",
            owner,
            popup,
            "<< /Type /XObject /Subtype /Form /BBox [0 0 160 18] /Resources << >> /Length 0 >>\nstream\n\nendstream",
        ])
    }

    static func rawOffAnnotsPopupCloneGraph(cloneMatches: Bool = true) -> Data {
        let owner = "<< /Type /Annot /Subtype /Text /Rect [80 600 104 624] /Contents (off-array owner note) /NM (off-array-owner) /Popup 6 0 R /F 4 /C [1 1 0] >>"
        let clone = cloneMatches
            ? owner
            : "<< /Type /Annot /Subtype /Text /Rect [80 600 104 624] /Contents (off-array owner note) /NM (off-array-owner) /Popup 6 0 R /F 4 /C [1 1 0] /Subj (near clone only) >>"
        return rawPDF(objects: [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << >> /Contents 4 0 R /Annots [5 0 R] >>",
            "<< /Length 0 >>\nstream\n\nendstream",
            owner,
            "<< /Type /Annot /Subtype /Popup /Rect [110 520 290 640] /Parent 7 0 R /Contents (popup-private) /NM (off-array-popup) /M (D:20260714010101Z) /F 4 /Open true /AP << /N 8 0 R >> /XMathPDFSentinel (keep-me) >>",
            clone,
            "<< /Type /XObject /Subtype /Form /BBox [0 0 10 10] /Resources << >> /Length 0 >>\nstream\n\nendstream",
        ])
    }

    static func rawCrossPageDuplicateNames() -> Data {
        rawPDF(objects: [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R 5 0 R] /Count 2 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << >> /Contents 4 0 R /Annots [7 0 R] >>",
            "<< /Length 0 >>\nstream\n\nendstream",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << >> /Contents 6 0 R /Annots [8 0 R] >>",
            "<< /Length 0 >>\nstream\n\nendstream",
            "<< /Type /Annot /Subtype /Highlight /Rect [80 600 240 618] /Contents (first page) /NM (reused-across-pages) >>",
            "<< /Type /Annot /Subtype /Highlight /Rect [80 560 240 578] /Contents (second page) /NM (reused-across-pages) >>",
        ])
    }

    static func rawDuplicateNameGraph() -> Data {
        rawPDF(objects: [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << >> /Contents 4 0 R /Annots [5 0 R 6 0 R 7 0 R 8 0 R] >>",
            "<< /Length 0 >>\nstream\n\nendstream",
            "<< /Type /Annot /Subtype /Highlight /Rect [80 600 240 618] /Contents (first) /NM (duplicate-owner) /Popup 6 0 R >>",
            "<< /Type /Annot /Subtype /Popup /Rect [250 500 430 620] /NM (popup-one) /Parent 5 0 R >>",
            "<< /Type /Annot /Subtype /Highlight /Rect [80 560 240 578] /Contents (second) /NM (duplicate-owner) /Popup 8 0 R >>",
            "<< /Type /Annot /Subtype /Popup /Rect [250 440 430 560] /NM (popup-two) /Parent 7 0 R >>",
        ])
    }

    static func rawPopupGraphWithMismatchedColor() -> Data {
        rawPDF(objects: [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << >> /Contents 4 0 R /Annots [5 0 R 6 0 R] >>",
            "<< /Length 0 >>\nstream\n\nendstream",
            "<< /Type /Annot /Subtype /Highlight /Rect [80 600 240 618] /QuadPoints [80 618 240 618 80 600 240 600] /Contents (owner note) /C [1 1 0] /NM (raw-owner) /Popup 6 0 R >>",
            "<< /Type /Annot /Subtype /Popup /Rect [250 500 430 620] /C [1 0 0] /NM (raw-popup) /Parent 5 0 R /AP << /N 7 0 R >> >>",
            "<< /Type /XObject /Subtype /Form /BBox [0 0 180 120] /Resources << >> /Length 0 >>\nstream\n\nendstream",
        ])
    }

    static func rawHighlightWithAppearance() -> Data {
        rawPDF(objects: [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << >> /Contents 4 0 R /Annots [5 0 R] >>",
            "<< /Length 0 >>\nstream\n\nendstream",
            "<< /Type /Annot /Subtype /Highlight /Rect [80 600 240 618] /QuadPoints [80 618 240 618 80 600 240 600] /Contents (owner note) /C [1 1 0] /NM (appearance-owner) /AP << /N 6 0 R >> >>",
            "<< /Type /XObject /Subtype /Form /BBox [0 0 160 18] /Resources << >> /Length 0 >>\nstream\n\nendstream",
        ])
    }

    static func rawPopupState(in data: Data) throws -> RawPopupState {
        let provider = try #require(CGDataProvider(data: data as CFData))
        let document = try #require(CGPDFDocument(provider))
        let page = try #require(document.page(at: 1))
        let pageDictionary = try #require(page.dictionary)
        var annotations: CGPDFArrayRef?
        let hasAnnotations = "Annots".withCString {
            CGPDFDictionaryGetArray(pageDictionary, $0, &annotations)
        }
        #expect(hasAnnotations)
        let annotationArray = try #require(annotations)

        for index in 0..<CGPDFArrayGetCount(annotationArray) {
            var dictionary: CGPDFDictionaryRef?
            guard CGPDFArrayGetDictionary(annotationArray, index, &dictionary),
                  let dictionary,
                  dictionaryName(dictionary, key: "Subtype") == "Popup"
            else { continue }

            var flags: CGPDFInteger = 0
            _ = "F".withCString { CGPDFDictionaryGetInteger(dictionary, $0, &flags) }
            var isOpen: CGPDFBoolean = 0
            _ = "Open".withCString { CGPDFDictionaryGetBoolean(dictionary, $0, &isOpen) }
            var appearance: CGPDFDictionaryRef?
            let hasAppearance = "AP".withCString {
                CGPDFDictionaryGetDictionary(dictionary, $0, &appearance)
            }
            var nameObject: CGPDFObjectRef?
            _ = "NM".withCString { CGPDFDictionaryGetObject(dictionary, $0, &nameObject) }
            return RawPopupState(
                contents: dictionaryString(dictionary, key: "Contents"),
                modificationDate: dictionaryString(dictionary, key: "M"),
                flags: flags,
                isOpen: isOpen != 0,
                hasAppearance: hasAppearance,
                sentinel: dictionaryString(dictionary, key: "XMathPDFSentinel"),
                name: dictionaryString(dictionary, key: "NM"),
                richContents: dictionaryString(dictionary, key: "RC"),
                color: dictionaryNumberArray(dictionary, key: "C")
            )
        }
        Issue.record("The raw fixture has no Popup annotation.")
        return RawPopupState(
            contents: nil,
            modificationDate: nil,
            flags: 0,
            isOpen: false,
            hasAppearance: false,
            sentinel: nil,
            name: nil,
            richContents: nil,
            color: []
        )
    }

    static func rawFirstOwnerState(in data: Data) throws -> RawOwnerState {
        let provider = try #require(CGDataProvider(data: data as CFData))
        let document = try #require(CGPDFDocument(provider))
        let page = try #require(document.page(at: 1))
        let pageDictionary = try #require(page.dictionary)
        var annotations: CGPDFArrayRef?
        let hasAnnotations = "Annots".withCString {
            CGPDFDictionaryGetArray(pageDictionary, $0, &annotations)
        }
        #expect(hasAnnotations)
        let annotationArray = try #require(annotations)

        for index in 0..<CGPDFArrayGetCount(annotationArray) {
            var dictionary: CGPDFDictionaryRef?
            guard CGPDFArrayGetDictionary(annotationArray, index, &dictionary),
                  let dictionary,
                  dictionaryName(dictionary, key: "Subtype") != "Popup"
            else { continue }
            var flags: CGPDFInteger = 0
            _ = "F".withCString { CGPDFDictionaryGetInteger(dictionary, $0, &flags) }
            var popupObject: CGPDFObjectRef?
            let hasPopup = "Popup".withCString {
                CGPDFDictionaryGetObject(dictionary, $0, &popupObject)
            }
            return RawOwnerState(
                contents: dictionaryString(dictionary, key: "Contents"),
                modificationDate: dictionaryString(dictionary, key: "M"),
                richContents: dictionaryString(dictionary, key: "RC"),
                name: dictionaryString(dictionary, key: "NM"),
                flags: flags,
                sentinel: dictionaryString(dictionary, key: "XMathPDFOwnerSentinel"),
                hasPopup: hasPopup
            )
        }
        Issue.record("The raw fixture has no owning annotation.")
        return RawOwnerState(
            contents: nil,
            modificationDate: nil,
            richContents: nil,
            name: nil,
            flags: 0,
            sentinel: nil,
            hasPopup: false
        )
    }

    static func rawAnnotationSubtypes(in data: Data) throws -> [String] {
        let provider = try #require(CGDataProvider(data: data as CFData))
        let document = try #require(CGPDFDocument(provider))
        let page = try #require(document.page(at: 1))
        let pageDictionary = try #require(page.dictionary)
        var annotations: CGPDFArrayRef?
        #expect("Annots".withCString { CGPDFDictionaryGetArray(pageDictionary, $0, &annotations) })
        let annotationArray = try #require(annotations)
        return (0..<CGPDFArrayGetCount(annotationArray)).compactMap { index in
            var dictionary: CGPDFDictionaryRef?
            guard CGPDFArrayGetDictionary(annotationArray, index, &dictionary),
                  let dictionary else { return nil }
            return dictionaryName(dictionary, key: "Subtype")
        }
    }

    static func rawAnnotationNames(in data: Data) throws -> [String] {
        let provider = try #require(CGDataProvider(data: data as CFData))
        let document = try #require(CGPDFDocument(provider))
        let page = try #require(document.page(at: 1))
        let pageDictionary = try #require(page.dictionary)
        var annotations: CGPDFArrayRef?
        #expect("Annots".withCString { CGPDFDictionaryGetArray(pageDictionary, $0, &annotations) })
        let annotationArray = try #require(annotations)
        return (0..<CGPDFArrayGetCount(annotationArray)).compactMap { index in
            var dictionary: CGPDFDictionaryRef?
            guard CGPDFArrayGetDictionary(annotationArray, index, &dictionary),
                  let dictionary else { return nil }
            return dictionaryString(dictionary, key: "NM")
        }
    }

    static func rawFirstHighlightHasAppearance(in data: Data) throws -> Bool {
        let provider = try #require(CGDataProvider(data: data as CFData))
        let document = try #require(CGPDFDocument(provider))
        let page = try #require(document.page(at: 1))
        let pageDictionary = try #require(page.dictionary)
        var annotations: CGPDFArrayRef?
        let hasAnnotations = "Annots".withCString {
            CGPDFDictionaryGetArray(pageDictionary, $0, &annotations)
        }
        #expect(hasAnnotations)
        let annotationArray = try #require(annotations)

        for index in 0..<CGPDFArrayGetCount(annotationArray) {
            var dictionary: CGPDFDictionaryRef?
            guard CGPDFArrayGetDictionary(annotationArray, index, &dictionary),
                  let dictionary,
                  dictionaryName(dictionary, key: "Subtype") == "Highlight"
            else { continue }
            var appearance: CGPDFDictionaryRef?
            return "AP".withCString {
                CGPDFDictionaryGetDictionary(dictionary, $0, &appearance)
            }
        }
        Issue.record("The raw fixture has no Highlight annotation.")
        return false
    }

    static func rawFirstPopupColor(in data: Data) throws -> [Double] {
        let provider = try #require(CGDataProvider(data: data as CFData))
        let document = try #require(CGPDFDocument(provider))
        let page = try #require(document.page(at: 1))
        let pageDictionary = try #require(page.dictionary)
        var annotations: CGPDFArrayRef?
        let hasAnnotations = "Annots".withCString {
            CGPDFDictionaryGetArray(pageDictionary, $0, &annotations)
        }
        #expect(hasAnnotations)
        let annotationArray = try #require(annotations)

        for index in 0..<CGPDFArrayGetCount(annotationArray) {
            var dictionary: CGPDFDictionaryRef?
            guard CGPDFArrayGetDictionary(annotationArray, index, &dictionary),
                  let dictionary,
                  dictionaryName(dictionary, key: "Subtype") == "Popup"
            else { continue }
            var color: CGPDFArrayRef?
            let hasColor = "C".withCString {
                CGPDFDictionaryGetArray(dictionary, $0, &color)
            }
            guard hasColor, let color else { return [] }
            return (0..<CGPDFArrayGetCount(color)).map { component in
                var value: CGPDFReal = 0
                _ = CGPDFArrayGetNumber(color, component, &value)
                return Double(value)
            }
        }
        Issue.record("The raw fixture has no Popup annotation.")
        return []
    }

    private static func rawPDF(objects: [String]) -> Data {
        var data = Data("%PDF-1.7\n".utf8)
        var offsets = [0]
        for (index, object) in objects.enumerated() {
            offsets.append(data.count)
            data.append(contentsOf: "\(index + 1) 0 obj\n\(object)\nendobj\n".utf8)
        }
        let xrefOffset = data.count
        data.append(contentsOf: "xref\n0 \(objects.count + 1)\n".utf8)
        data.append(contentsOf: "0000000000 65535 f \n".utf8)
        for offset in offsets.dropFirst() {
            data.append(contentsOf: String(format: "%010d 00000 n \n", offset).utf8)
        }
        data.append(contentsOf: "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xrefOffset)\n%%EOF\n".utf8)
        return data
    }

    private static func dictionaryName(
        _ dictionary: CGPDFDictionaryRef,
        key: String
    ) -> String? {
        var value: UnsafePointer<CChar>?
        let found = key.withCString {
            CGPDFDictionaryGetName(dictionary, $0, &value)
        }
        return found ? value.map(String.init(cString:)) : nil
    }

    private static func dictionaryString(
        _ dictionary: CGPDFDictionaryRef,
        key: String
    ) -> String? {
        var value: CGPDFStringRef?
        let found = key.withCString {
            CGPDFDictionaryGetString(dictionary, $0, &value)
        }
        guard found, let value else { return nil }
        return CGPDFStringCopyTextString(value) as String?
    }

    private static func dictionaryNumberArray(
        _ dictionary: CGPDFDictionaryRef,
        key: String
    ) -> [Double] {
        var array: CGPDFArrayRef?
        let found = key.withCString {
            CGPDFDictionaryGetArray(dictionary, $0, &array)
        }
        guard found, let array else { return [] }
        return (0..<CGPDFArrayGetCount(array)).map { index in
            var value: CGPDFReal = 0
            _ = CGPDFArrayGetNumber(array, index, &value)
            return Double(value)
        }
    }

}

private var katexAssetURL: URL {
    let sourceAssets = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("MathPDF/KaTeX", isDirectory: true)
    let candidates = [Bundle.main.resourceURL, sourceAssets].compactMap { $0 }
    return candidates.first {
        FileManager.default.fileExists(atPath: $0.appendingPathComponent("katex.min.css").path)
    } ?? sourceAssets
}

@MainActor
private enum WebRendererProbe {
    static func snapshot(of renderedDocument: MathRenderedDocument) async throws -> WebRendererSnapshot {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .init(x: 0, y: 0, width: 480, height: 320), configuration: configuration)
        let delegate = NavigationDelegate()
        webView.navigationDelegate = delegate
        webView.loadHTMLString(renderedDocument.html, baseURL: renderedDocument.baseURL)
        try await delegate.waitForFinish()

        var renderState = ""
        for _ in 0..<30 {
            renderState = try await webView.javaScriptString("document.body.dataset.renderState || ''")
            if !renderState.isEmpty, renderState != "loading" { break }
            await Task.yield()
        }

        return WebRendererSnapshot(
            renderState: renderState,
            katexCount: try await webView.javaScriptInt("Number(document.body.dataset.katexCount || 0)"),
            innerText: try await webView.javaScriptString("document.body.innerText"),
            pageWasCompromised: try await webView.javaScriptBool("Boolean(window.pwned)"),
            macroWasCompromised: try await webView.javaScriptBool("Boolean(window.macroPwned)")
        )
    }
}

private struct WebRendererSnapshot {
    let renderState: String
    let katexCount: Int
    let innerText: String
    let pageWasCompromised: Bool
    let macroWasCompromised: Bool
}

@MainActor
private final class NavigationDelegate: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?
    private var finishedResult: Result<Void, Error>?

    func waitForFinish() async throws {
        if let finishedResult {
            return try finishedResult.get()
        }
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finishedResult = .success(())
        continuation?.resume(returning: ())
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finishedResult = .failure(error)
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finishedResult = .failure(error)
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

@MainActor
private extension WKWebView {
    func javaScriptString(_ script: String) async throws -> String {
        try await evaluateJavaScript(script) as? String ?? ""
    }

    func javaScriptInt(_ script: String) async throws -> Int {
        try await evaluateJavaScript(script) as? Int ?? 0
    }

    func javaScriptBool(_ script: String) async throws -> Bool {
        try await evaluateJavaScript(script) as? Bool ?? false
    }
}
