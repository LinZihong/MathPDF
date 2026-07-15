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
        let popup = try #require(highlight.popup)
        #expect(page.annotations.contains { $0 === popup })
        #expect(popup.contents == nil)
        #expect((popup.value(forAnnotationKey: .parent) as? PDFAnnotation) === highlight)
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
        #expect(highlight.popup === popup)
        #expect((popup.value(forAnnotationKey: .parent) as? PDFAnnotation) === highlight)
        #expect(page.annotations.filter { $0.type == "Text" }.isEmpty)
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
        let reloadedPopup = try #require(reloadedText.popup)
        #expect(reloadedPage.annotations.contains { $0 === reloadedPopup })
        #expect((reloadedPopup.value(forAnnotationKey: .parent) as? PDFAnnotation) === reloadedText)
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
        let savedPopup = try #require(savedHighlight.popup)
        #expect(savedFirstPage.annotations.contains { $0 === savedPopup })
        #expect((savedPopup.value(forAnnotationKey: .parent) as? PDFAnnotation) === savedHighlight)
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
        #expect(sourceHighlight.popup === sourcePopup)
        #expect(page.annotations.contains { $0 === sourcePopup })

        let reloaded = try MathPDFDocument(data: data)
        let savedPage = try #require(reloaded.pdfDocument.page(at: 0))
        let savedHighlight = try #require(savedPage.annotations.first { $0.type == "Highlight" })
        #expect(savedHighlight.contents == "after")
        let savedPopup = try #require(savedHighlight.popup)
        #expect(savedPage.annotations.contains { $0 === savedPopup })
        #expect((savedPopup.value(forAnnotationKey: .parent) as? PDFAnnotation) === savedHighlight)
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
        let savedPopup = try #require(savedHighlight.popup)
        #expect((savedPopup.value(forAnnotationKey: .parent) as? PDFAnnotation) === savedHighlight)
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
        let reloaded = try MathPDFDocument(data: data)
        let page = try #require(reloaded.pdfDocument.page(at: 0))
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

    private func assertSingleTextNote(
        in data: Data,
        contents: String,
        preamble: String
    ) throws {
        let reloaded = try MathPDFDocument(data: data)
        let page = try #require(reloaded.pdfDocument.page(at: 0))
        let notes = page.annotations.filter { $0.type == "Text" }
        #expect(notes.count == 1)
        let note = try #require(notes.first)
        #expect(note.contents == contents)
        let popup = try #require(note.popup)
        #expect(page.annotations.filter { $0.type == "Popup" }.count == 1)
        #expect((popup.value(forAnnotationKey: .parent) as? PDFAnnotation) === note)
        #expect(reloaded.preamble == preamble)
    }
}

@MainActor
@Suite("Reader state")
struct ReaderDocumentControllerTests {
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
    func deletingTheSelectedInspectorNoteClearsTransientStateAndUndoRestoresTheNote() throws {
        let document = MathPDFDocument()
        let page = try #require(document.pdfDocument.page(at: 0))
        let annotation = TestPDFFactory.annotation(.text, contents: "delete me", bounds: .init(x: 90, y: 500, width: 24, height: 24))
        page.addAnnotation(annotation)
        let controller = ReaderDocumentController(document: document)
        let note = try #require(controller.annotationActivated(annotation))
        controller.pin(note, startsEditing: true)
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false

        undoManager.beginUndoGrouping()
        controller.removeNote(note, undoManager: undoManager)
        undoManager.endUndoGrouping()

        #expect(controller.selectedNoteID == nil)
        #expect(controller.notes.isEmpty)
        if case .note = controller.inspectorDestination {
            Issue.record("Deleting the active note must close its inspector")
        }

        undoManager.undo()
        #expect(controller.notes.count == 1)
        #expect(controller.notes.first?.annotation === annotation)
        #expect(controller.selectedNoteID == nil)
        if controller.inspectorDestination != nil {
            Issue.record("Undo may restore the note, but it must not reopen stale transient UI")
        }
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
        first.pin(try #require(first.notes.first), startsEditing: true)

        #expect(second.sidebarMode == .contents)
        #expect(second.searchText.isEmpty)
        #expect(second.readerTool == .browse)
        #expect(secondDocument.preamble.isEmpty)
        #expect(second.notes.first?.contents == "second")
        #expect(second.selectedNoteID == nil)
        if second.inspectorDestination != nil {
            Issue.record("A document window must not inherit another window's inspector")
        }
    }
}

@MainActor
@Suite("Reader viewport")
struct ReaderViewportTests {
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
}

@MainActor
@Suite("Reader annotation ownership")
struct ReaderAnnotationOwnershipTests {
    @Test
    func loadingADocumentClosesItsNativePDFPopupState() throws {
        let document = TestPDFFactory.document(pageCount: 1)
        let page = try #require(document.page(at: 0))
        let highlight = TestPDFFactory.annotation(.highlight, contents: "one note", bounds: .init(x: 80, y: 600, width: 160, height: 18))
        let popup = TestPDFFactory.annotation(.popup, contents: "one note", bounds: .init(x: 260, y: 500, width: 180, height: 120))
        page.addAnnotation(highlight)
        page.addAnnotation(popup)
        highlight.popup = popup
        popup.isOpen = true

        let container = ReaderContainerView(frame: CGRect(x: 0, y: 0, width: 800, height: 640))
        container.configure(
            document: document,
            proxy: PDFViewProxy(),
            noteForAnnotation: { annotation in
                PDFNoteExtractor.note(for: annotation, pageIndex: 0, includeEmptyContents: true)
            },
            onUpdateNote: { _, _ in },
            onPinNote: { _, _ in },
            onCancelTextNote: {},
            onCreateTextNote: { _, _ in nil },
            preamble: ""
        )

        #expect(!popup.isOpen)
        #expect(!highlight.popup!.isOpen)
        #expect(PDFNoteExtractor.extractNotes(from: document).count == 1)
    }
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
        let data = NSMutableData()
        let consumer = CGDataConsumer(data: data)!
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = CGContext(consumer: consumer, mediaBox: &box, nil)!
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
        context.closePDF()
        return PDFDocument(data: data as Data)!
    }

    static func annotation(_ subtype: PDFAnnotationSubtype, contents: String, bounds: CGRect) -> PDFAnnotation {
        let annotation = PDFAnnotation(bounds: bounds, forType: subtype, withProperties: nil)
        annotation.contents = contents
        return annotation
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
