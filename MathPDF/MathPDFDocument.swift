import CoreGraphics
import Combine
import Foundation
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

final class MathPDFDocument: ReferenceFileDocument, ObservableObject {
    typealias Snapshot = Data

    static var readableContentTypes: [UTType] { [.pdf] }
    static var writableContentTypes: [UTType] { [.pdf] }

    @Published private(set) var pdfDocument: PDFDocument
    @Published private(set) var annotationRevision = 0
    @Published var preamble: String {
        didSet {
            guard preamble != oldValue else { return }
            applyPreambleMetadata()
        }
    }

    // PDFKit exposes document-attribute keys from externally-authored PDFs as
    // String-backed AnyHashable values, even though it also defines the
    // PDFDocumentAttribute wrapper. String keys keep pypdf, Preview, and
    // PDFKit-authored files on the same interoperable path.
    private static let legacyPreambleKey = "MathPDFPreamble"
    private static let keywordsKey = PDFDocumentAttribute.keywordsAttribute.rawValue
    private static let preambleKeywordPrefix = "MathPDF-Preamble-v1:"

    init() {
        let data = Self.blankPDFData()
        pdfDocument = PDFDocument(data: data) ?? PDFDocument()
        preamble = ""
    }

    init(data: Data) throws {
        guard let document = PDFDocument(data: data) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        pdfDocument = document
        preamble = Self.readPreamble(from: document)
    }

    required init(configuration: ReadConfiguration) throws {
        guard
            let data = configuration.file.regularFileContents,
            let document = PDFDocument(data: data)
        else {
            throw CocoaError(.fileReadCorruptFile)
        }

        pdfDocument = document
        preamble = Self.readPreamble(from: document)
    }

    func snapshot(contentType: UTType) throws -> Data {
        applyPreambleMetadata()
        synchronizePopupContentsBeforeSerialization()
        guard
            let sourceData = pdfDocument.dataRepresentation(),
            let serializableCopy = PDFDocument(data: sourceData)
        else {
            throw CocoaError(.fileWriteUnknown)
        }

        // PDFKit does not reliably preserve /Popup + /Parent relationships when
        // writing an edited document. A dropped relationship leaves a visible,
        // orphaned Popup annotation alongside MathPDF's owned note surface.
        // Normalize only the serialized copy: the owning annotation keeps the
        // interoperable plain-text Contents value, while companion Popup objects
        // are omitted so Preview and other readers cannot present duplicates.
        Self.removePopupCompanions(from: serializableCopy)
        guard let normalizedData = serializableCopy.dataRepresentation() else {
            throw CocoaError(.fileWriteUnknown)
        }
        return normalizedData
    }

    func serializedData() throws -> Data {
        try snapshot(contentType: .pdf)
    }

#if DEBUG
    func loadUITestFixtureIfRequested(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) {
        let requestedByEnvironment = environment["MATHPDF_UI_FIXTURE"] == "annotated-reader"
        let requestedByArgument = arguments.contains("--annotated-reader-fixture")
        guard requestedByEnvironment || requestedByArgument else { return }
        guard let fixture = PDFDocument(data: Self.uiTestFixtureData()) else { return }
        objectWillChange.send()
        pdfDocument = fixture
        preamble = #"\newcommand{\Q}{\mathbb{Q}}"#
        annotationRevision &+= 1
    }
#endif

    func fileWrapper(snapshot: Data, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: snapshot)
    }

    func updateContents(
        of annotation: PDFAnnotation,
        to contents: String,
        undoManager: UndoManager?
    ) {
        let previous = annotation.contents ?? ""
        guard previous != contents else { return }

        undoManager?.registerUndo(withTarget: self) { document in
            document.updateContents(of: annotation, to: previous, undoManager: undoManager)
        }
        undoManager?.setActionName("Edit Note")

        objectWillChange.send()
        annotation.contents = contents
        annotation.modificationDate = Date()
        synchronizePopup(for: annotation)
        annotationRevision &+= 1
    }

    func addTextNote(
        on page: PDFPage,
        at point: CGPoint,
        undoManager: UndoManager?
    ) -> PDFAnnotation {
        let cropBox = page.bounds(for: .cropBox)
        let center = CGPoint(
            x: min(max(point.x, cropBox.minX + 12), cropBox.maxX - 12),
            y: min(max(point.y, cropBox.minY + 12), cropBox.maxY - 12)
        )
        let bounds = CGRect(x: center.x - 12, y: center.y - 12, width: 24, height: 24)
        let annotation = PDFAnnotation(bounds: bounds, forType: .text, withProperties: nil)
        annotation.color = .systemYellow
        annotation.contents = ""
        annotation.modificationDate = Date()

        objectWillChange.send()
        page.addAnnotation(annotation)
        annotationRevision &+= 1

        undoManager?.registerUndo(withTarget: self) { document in
            document.removeAnnotation(annotation, undoManager: undoManager)
        }
        undoManager?.setActionName("Add Note")
        return annotation
    }

    func addHighlight(
        from selection: PDFSelection,
        undoManager: UndoManager?
    ) -> PDFAnnotation? {
        var pageLines: [ObjectIdentifier: (page: PDFPage, bounds: [CGRect])] = [:]
        var pageOrder: [ObjectIdentifier] = []

        for lineSelection in selection.selectionsByLine() {
            for page in lineSelection.pages {
                let bounds = lineSelection.bounds(for: page)
                guard !bounds.isEmpty else { continue }
                let key = ObjectIdentifier(page)
                if pageLines[key] == nil {
                    pageLines[key] = (page, [])
                    pageOrder.append(key)
                }
                pageLines[key]?.bounds.append(bounds)
            }
        }

        var created: [PDFAnnotation] = []

        for key in pageOrder {
            guard let (page, lineBounds) = pageLines[key],
                  let annotationBounds = lineBounds.reduce(nil as CGRect?, { partial, bounds in
                      partial.map { $0.union(bounds) } ?? bounds
                  })
            else { continue }

            let annotation = PDFAnnotation(bounds: annotationBounds, forType: .highlight, withProperties: nil)
            annotation.color = .systemYellow.withAlphaComponent(0.45)
            annotation.modificationDate = Date()
            annotation.quadrilateralPoints = lineBounds.flatMap { bounds in
                let left = bounds.minX - annotationBounds.minX
                let right = bounds.maxX - annotationBounds.minX
                let bottom = bounds.minY - annotationBounds.minY
                let top = bounds.maxY - annotationBounds.minY
                return [
                    NSValue(point: CGPoint(x: left, y: top)),
                    NSValue(point: CGPoint(x: right, y: top)),
                    NSValue(point: CGPoint(x: left, y: bottom)),
                    NSValue(point: CGPoint(x: right, y: bottom)),
                ]
            }
            page.addAnnotation(annotation)
            created.append(annotation)
        }

        guard let first = created.first else { return nil }
        objectWillChange.send()
        annotationRevision &+= 1

        undoManager?.registerUndo(withTarget: self) { document in
            for annotation in created {
                document.removeAnnotation(annotation, undoManager: nil)
            }
        }
        undoManager?.setActionName("Highlight")
        return first
    }

    func removeAnnotation(_ annotation: PDFAnnotation, undoManager: UndoManager?) {
        guard let page = annotation.page else { return }
        objectWillChange.send()
        page.removeAnnotation(annotation)
        annotationRevision &+= 1

        undoManager?.registerUndo(withTarget: self) { document in
            document.restoreAnnotation(annotation, to: page, undoManager: undoManager)
        }
        undoManager?.setActionName("Delete Note")
    }

    private func restoreAnnotation(
        _ annotation: PDFAnnotation,
        to page: PDFPage,
        undoManager: UndoManager?
    ) {
        objectWillChange.send()
        page.addAnnotation(annotation)
        annotationRevision &+= 1
        undoManager?.registerUndo(withTarget: self) { document in
            document.removeAnnotation(annotation, undoManager: undoManager)
        }
    }

    private func synchronizePopup(for annotation: PDFAnnotation) {
        guard annotation.type?.caseInsensitiveCompare("Highlight") == .orderedSame else {
            annotation.popup?.contents = annotation.contents
            return
        }

        if let popup = annotation.popup {
            popup.contents = annotation.contents
            popup.modificationDate = annotation.modificationDate
        }
    }

    private func synchronizePopupContentsBeforeSerialization() {
        for pageIndex in 0..<pdfDocument.pageCount {
            guard let page = pdfDocument.page(at: pageIndex) else { continue }
            for annotation in page.annotations {
                guard let popup = annotation.popup else { continue }
                if (annotation.contents ?? "").isEmpty,
                   let popupContents = popup.contents,
                   !popupContents.isEmpty {
                    annotation.contents = popupContents
                }
            }
        }
    }

    private static func removePopupCompanions(from document: PDFDocument) {
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            for annotation in page.annotations where
                annotation.type?.caseInsensitiveCompare("Popup") == .orderedSame
            {
                page.removeAnnotation(annotation)
            }
        }
    }

    private func applyPreambleMetadata() {
        var attributes = pdfDocument.documentAttributes ?? [:]
        attributes.removeValue(forKey: Self.legacyPreambleKey)

        var keywords: [String]
        if let values = attributes[Self.keywordsKey] as? [String] {
            keywords = values
        } else if let value = attributes[Self.keywordsKey] as? String {
            keywords = [value]
        } else {
            keywords = []
        }
        keywords.removeAll { $0.hasPrefix(Self.preambleKeywordPrefix) }
        if !preamble.isEmpty, let data = preamble.data(using: .utf8) {
            keywords.append(Self.preambleKeywordPrefix + data.base64EncodedString())
        }
        attributes[Self.keywordsKey] = keywords
        pdfDocument.documentAttributes = attributes
    }

    private static func readPreamble(from document: PDFDocument) -> String {
        let attributes = document.documentAttributes ?? [:]
        if let legacy = attributes[legacyPreambleKey] as? String {
            return legacy
        }
        let keywords: [String]
        if let values = attributes[keywordsKey] as? [String] {
            keywords = values
        } else if let value = attributes[keywordsKey] as? String {
            keywords = [value]
        } else {
            keywords = []
        }
        guard let keyword = keywords.first(where: { $0.hasPrefix(preambleKeywordPrefix) }) else {
            return ""
        }
        let encoded = String(keyword.dropFirst(preambleKeywordPrefix.count))
        guard
            let data = Data(base64Encoded: encoded),
            let source = String(data: data, encoding: .utf8)
        else { return "" }
        return source
    }

    private static func blankPDFData() -> Data {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data) else { return Data() }
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return Data() }
        context.beginPDFPage(nil)
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

#if DEBUG
    private static func uiTestFixtureData() -> Data {
        let base = PDFDocument(data: blankPDFData(pageCount: 3)) ?? PDFDocument()
        guard
            let first = base.page(at: 0),
            let second = base.page(at: 1),
            let third = base.page(at: 2)
        else { return Data() }

        let highlight = PDFAnnotation(
            bounds: CGRect(x: 90, y: 650, width: 180, height: 22),
            forType: .highlight,
            withProperties: nil
        )
        highlight.contents = #"A point of $\Q$"#
        highlight.color = .systemYellow.withAlphaComponent(0.5)
        second.addAnnotation(highlight)

        let text = PDFAnnotation(
            bounds: CGRect(x: 510, y: 60, width: 24, height: 24),
            forType: .text,
            withProperties: nil
        )
        text.contents = "Edge note"
        third.addAnnotation(text)

        let outlineRoot = PDFOutline()
        let chapter = PDFOutline()
        chapter.label = "Test chapter"
        chapter.destination = PDFDestination(page: first, at: CGPoint(x: 0, y: 792))
        outlineRoot.insertChild(chapter, at: 0)
        base.outlineRoot = outlineRoot
        return base.dataRepresentation() ?? Data()
    }

    private static func blankPDFData(pageCount: Int) -> Data {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data) else { return Data() }
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return Data() }
        for _ in 0..<pageCount {
            context.beginPDFPage(nil)
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }
#endif
}
