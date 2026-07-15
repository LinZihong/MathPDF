import CoreGraphics
import CoreText
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
            markSerializationDirty()
        }
    }

    private var originalData: Data
    private var serializationRevision = 0
    private var cachedSnapshotRevision: Int?
    private var cachedSnapshotData: Data?
    private var popupDiskStates: [ObjectIdentifier: PDFPopupDiskState] = [:]
    private var persistenceSession: PDFAnnotationPersistenceSession
    private var activeNoteEditStates: [ObjectIdentifier: NoteEditState] = [:]

    private struct NoteEditState {
        let contents: String?
        let modificationDate: Date?
        let richContents: String?
        let durableName: String?
        let popup: PDFAnnotation?
        let popupDiskState: PDFPopupDiskState?
    }

    private struct AnnotationRemovalState {
        let annotation: PDFAnnotation
        let page: PDFPage
        let popup: PDFAnnotation?
        let popupDiskState: PDFPopupDiskState?
    }

    private struct HighlightColorState {
        let ownerColor: NSColor
        let popupColor: NSColor?
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
        let document = PDFDocument(data: data) ?? PDFDocument()
        pdfDocument = document
        originalData = data
        cachedSnapshotRevision = 0
        cachedSnapshotData = data
        preamble = ""
        persistenceSession = PDFAnnotationPersistenceSession(
            sourceData: data,
            document: document
        )
        captureAndSuppressPopupPresentation()
    }

    init(data: Data) throws {
        guard let document = PDFDocument(data: data) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        pdfDocument = document
        originalData = data
        cachedSnapshotRevision = 0
        cachedSnapshotData = data
        preamble = Self.readPreamble(from: document)
        persistenceSession = PDFAnnotationPersistenceSession(
            sourceData: data,
            document: document
        )
        captureAndSuppressPopupPresentation()
    }

    required init(configuration: ReadConfiguration) throws {
        guard
            let data = configuration.file.regularFileContents,
            let document = PDFDocument(data: data)
        else {
            throw CocoaError(.fileReadCorruptFile)
        }

        pdfDocument = document
        originalData = data
        cachedSnapshotRevision = 0
        cachedSnapshotData = data
        preamble = Self.readPreamble(from: document)
        persistenceSession = PDFAnnotationPersistenceSession(
            sourceData: data,
            document: document
        )
        captureAndSuppressPopupPresentation()
    }

    func snapshot(contentType: UTType) throws -> Data {
        if cachedSnapshotRevision == serializationRevision, let cachedSnapshotData {
            return cachedSnapshotData
        }
        if let editingError = editingError {
            throw editingError
        }

        // PDFKit can lazily put an attached Popup back into `page.annotations`
        // after unrelated owner/page operations. Reassert the runtime/persisted
        // graph split at the serialization boundary so a transient native
        // marker can neither leak into PDFView nor make an otherwise valid
        // save fail merely because PDFKit re-presented the companion.
        suppressPopupPresentation()

        let data = try persistenceSession.serializedData(
            document: pdfDocument,
            preamble: preamble
        )
        try PDFAnnotationInteroperability.validate(
            serializedData: data,
            against: pdfDocument,
            logicalAnnotationsByPage: persistenceSession.logicalAnnotationsByPage(
                in: pdfDocument
            ),
            logicalPopupEdges: persistenceSession.logicalPopupEdges()
        )
        cachedSnapshotRevision = serializationRevision
        cachedSnapshotData = data
        return data
    }

    func serializedData() throws -> Data {
        try snapshot(contentType: .pdf)
    }

#if DEBUG
    private static func uiTestDocumentIfRequested(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> MathPDFDocument? {
        let requestedByEnvironment = environment["MATHPDF_UI_FIXTURE"] == "annotated-reader"
        let requestedByArgument = arguments.contains("--annotated-reader-fixture")
        guard requestedByEnvironment || requestedByArgument else { return nil }
        return try? MathPDFDocument(data: uiTestFixtureData())
    }
#endif

    static func newDocumentForCurrentProcess() -> MathPDFDocument {
#if DEBUG
        if let fixture = uiTestDocumentIfRequested() {
            return fixture
        }
#endif
        return MathPDFDocument()
    }

    func fileWrapper(snapshot: Data, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: snapshot)
    }

    var editingError: Error? {
        persistenceSession.editingError
    }

    func canEdit(_ annotation: PDFAnnotation) -> Bool {
        persistenceSession.canEdit(annotation)
    }

    func canChangeColor(of annotation: PDFAnnotation) -> Bool {
        persistenceSession.canChangeColor(of: annotation)
    }

    func popupCompanion(for annotation: PDFAnnotation) -> PDFAnnotation? {
        persistenceSession.popupCompanion(for: annotation)
    }

    /// PDFKit may lazily reinsert attached Popup companions into a page after
    /// unrelated layout or annotation work. The reciprocal objects stay in
    /// the persistence session, but the live PDFView graph must never contain
    /// them or it can draw a second native affordance beside MathPDF's badge.
    func enforceRuntimeAnnotationPresentation() {
        suppressPopupPresentation()
    }

    func editingUnavailableReason(for annotation: PDFAnnotation) -> String? {
        if let editingError {
            return editingError.localizedDescription
        }
        guard canEdit(annotation) else {
            return "This annotation is locked or cannot be changed safely."
        }
        return nil
    }

    func colorEditingUnavailableReason(for annotation: PDFAnnotation) -> String? {
        if let reason = editingUnavailableReason(for: annotation) {
            return reason
        }
        guard canChangeColor(of: annotation) else {
            return "This imported annotation has an appearance that MathPDF must preserve."
        }
        return nil
    }

    @discardableResult
    func updateContents(
        of annotation: PDFAnnotation,
        to contents: String,
        undoManager: UndoManager?
    ) -> Bool {
        guard canEdit(annotation) else { return false }
        trackAnnotationIfNeeded(annotation)
        let previous = annotation.contents ?? ""
        guard previous != contents else { return true }
        let previousState = noteEditState(for: annotation)

        undoManager?.registerUndo(withTarget: self) { document in
            document.restoreNoteEditState(
                previousState,
                of: annotation,
                undoManager: undoManager
            )
        }
        undoManager?.setActionName("Edit Note")

        objectWillChange.send()
        annotation.contents = contents
        annotation.modificationDate = Date()
        annotation.removeValue(forAnnotationKey: PDFAnnotationKey(rawValue: "/RC"))
        persistenceSession.markContentsChanged(on: annotation)
        updatePopupCompanion(for: annotation)
        recordAnnotationMutation()
        return true
    }

    /// Keeps the PDF model and autosave snapshot current while a note editor is
    /// active, without creating one document-undo entry per keystroke.
    @discardableResult
    func updateContentsDuringEditing(
        of annotation: PDFAnnotation,
        to contents: String
    ) -> Bool {
        guard canEdit(annotation) else { return false }
        trackAnnotationIfNeeded(annotation)
        let previous = annotation.contents ?? ""
        guard previous != contents else { return true }
        let identifier = ObjectIdentifier(annotation)
        if activeNoteEditStates[identifier] == nil {
            activeNoteEditStates[identifier] = noteEditState(for: annotation)
        }

        objectWillChange.send()
        annotation.contents = contents
        annotation.modificationDate = Date()
        annotation.removeValue(forAnnotationKey: PDFAnnotationKey(rawValue: "/RC"))
        persistenceSession.markContentsChanged(on: annotation)
        updatePopupCompanion(for: annotation)
        markSerializationDirty()
        return true
    }

    func commitContentsEditingTransaction(
        of annotation: PDFAnnotation,
        from originalContents: String,
        undoManager: UndoManager?
    ) {
        guard canEdit(annotation) else { return }
        let currentContents = annotation.contents ?? ""
        let identifier = ObjectIdentifier(annotation)
        let originalState = activeNoteEditStates.removeValue(forKey: identifier)
            ?? noteEditState(for: annotation, replacingContentsWith: originalContents)
        guard currentContents != originalContents else {
            // Typing back to the original string must also restore `/M`, `/RC`,
            // durable identity, and any Popup created during the transaction.
            restoreNoteEditState(originalState, of: annotation, undoManager: nil)
            return
        }

        undoManager?.registerUndo(withTarget: self) { document in
            document.restoreNoteEditState(
                originalState,
                of: annotation,
                undoManager: undoManager
            )
        }
        undoManager?.setActionName("Edit Note")
        recordAnnotationMutation()
    }

    func addTextNote(
        on page: PDFPage,
        at point: CGPoint,
        undoManager: UndoManager?
    ) -> PDFAnnotation? {
        guard editingError == nil else { return nil }
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
        let pageIndex = pdfDocument.index(for: page)
        persistenceSession.registerCreated(annotation, pageIndex: pageIndex)
        if let popup = annotation.popup {
            persistenceSession.registerCreated(popup, pageIndex: pageIndex)
            persistenceSession.markPopupEdge(owner: annotation, popup: popup)
            popupDiskStates[ObjectIdentifier(popup)] = PDFPopupDiskState(
                flags: 0,
                isOpen: false
            )
            suppressPopupPresentation()
        }
        recordAnnotationMutation()

        undoManager?.registerUndo(withTarget: self) { document in
            document.removeAnnotation(annotation, undoManager: undoManager)
        }
        undoManager?.setActionName("Add Note")
        return annotation
    }

    func addHighlight(
        from selection: PDFSelection,
        color: NSColor = NSColor(
            calibratedRed: 0.980392,
            green: 0.803922,
            blue: 0.352941,
            alpha: 1
        ),
        undoManager: UndoManager?
    ) -> PDFAnnotation? {
        guard editingError == nil else { return nil }
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
            annotation.color = color
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
            persistenceSession.registerCreated(
                annotation,
                pageIndex: pdfDocument.index(for: page)
            )
            created.append(annotation)
        }

        guard let first = created.first else { return nil }
        objectWillChange.send()
        recordAnnotationMutation()

        undoManager?.registerUndo(withTarget: self) { document in
            document.removeAnnotationGroup(
                created,
                undoManager: undoManager,
                actionName: "Highlight"
            )
        }
        undoManager?.setActionName("Highlight")
        return first
    }

    private func removeAnnotationGroup(
        _ annotations: [PDFAnnotation],
        undoManager: UndoManager?,
        actionName: String
    ) {
        let states = annotations.compactMap { annotation -> AnnotationRemovalState? in
            guard canEdit(annotation), let page = annotation.page else { return nil }
            let popup = persistenceSession.popupCompanion(for: annotation)
            return AnnotationRemovalState(
                annotation: annotation,
                page: page,
                popup: popup,
                popupDiskState: popup.flatMap { popupDiskStates[ObjectIdentifier($0)] }
            )
        }
        guard states.count == annotations.count else { return }

        objectWillChange.send()
        for state in states {
            activeNoteEditStates.removeValue(forKey: ObjectIdentifier(state.annotation))
            if let popup = state.popup {
                persistenceSession.detachPopup(popup, from: state.annotation)
                popupDiskStates.removeValue(forKey: ObjectIdentifier(popup))
            }
            state.page.removeAnnotation(state.annotation)
            persistenceSession.markDeleted(state.annotation)
        }
        recordAnnotationMutation()

        undoManager?.registerUndo(withTarget: self) { document in
            document.restoreAnnotationGroup(
                states,
                undoManager: undoManager,
                actionName: actionName
            )
        }
        undoManager?.setActionName(actionName)
    }

    private func restoreAnnotationGroup(
        _ states: [AnnotationRemovalState],
        undoManager: UndoManager?,
        actionName: String
    ) {
        objectWillChange.send()
        for state in states {
            state.page.addAnnotation(state.annotation)
            persistenceSession.markRestored(state.annotation)
            if let popup = state.popup {
                persistenceSession.markRestored(popup)
                persistenceSession.restorePopupEdge(owner: state.annotation, popup: popup)
                if let popupDiskState = state.popupDiskState {
                    popupDiskStates[ObjectIdentifier(popup)] = popupDiskState
                }
            }
        }
        suppressPopupPresentation()
        recordAnnotationMutation()

        undoManager?.registerUndo(withTarget: self) { document in
            document.removeAnnotationGroup(
                states.map(\.annotation),
                undoManager: undoManager,
                actionName: actionName
            )
        }
        undoManager?.setActionName(actionName)
    }

    func removeAnnotation(_ annotation: PDFAnnotation, undoManager: UndoManager?) {
        guard canEdit(annotation) else { return }
        guard let page = annotation.page else { return }
        // Deletion owns the current contents. If an inline editor was still
        // active, its old baseline must not leak through delete/undo into the
        // next editing transaction on this restored annotation.
        activeNoteEditStates.removeValue(forKey: ObjectIdentifier(annotation))
        objectWillChange.send()
        let attachedPopup = persistenceSession.popupCompanion(for: annotation)
        let popupDiskState = attachedPopup.flatMap { popupDiskStates[ObjectIdentifier($0)] }
        let popup = attachedPopup
        if let popup {
            persistenceSession.detachPopup(popup, from: annotation)
            popupDiskStates.removeValue(forKey: ObjectIdentifier(popup))
        }
        page.removeAnnotation(annotation)
        persistenceSession.markDeleted(annotation)
        recordAnnotationMutation()

        undoManager?.registerUndo(withTarget: self) { document in
            document.restoreAnnotation(
                annotation,
                popup: popup,
                popupDiskState: popupDiskState,
                to: page,
                undoManager: undoManager
            )
        }
        undoManager?.setActionName(
            annotation.type == "Highlight" ? "Delete Highlight" : "Delete Note"
        )
    }

    private func restoreAnnotation(
        _ annotation: PDFAnnotation,
        popup: PDFAnnotation?,
        popupDiskState: PDFPopupDiskState?,
        to page: PDFPage,
        undoManager: UndoManager?
    ) {
        objectWillChange.send()
        page.addAnnotation(annotation)
        persistenceSession.markRestored(annotation)
        if let popup {
            persistenceSession.markRestored(popup)
            persistenceSession.restorePopupEdge(owner: annotation, popup: popup)
            if let popupDiskState {
                popupDiskStates[ObjectIdentifier(popup)] = popupDiskState
            }
            suppressPopupPresentation()
        } else {
            updatePopupCompanion(for: annotation)
        }
        recordAnnotationMutation()
        undoManager?.registerUndo(withTarget: self) { document in
            document.removeAnnotation(annotation, undoManager: undoManager)
        }
    }

    @discardableResult
    func updateHighlightColor(
        of annotation: PDFAnnotation,
        to color: NSColor,
        undoManager: UndoManager?
    ) -> Bool {
        guard persistenceSession.canChangeColor(of: annotation) else { return false }
        // A commented highlight must have its standard Popup companion before
        // any dirty save, even when the imported graph omitted it.
        updatePopupCompanion(for: annotation)
        let popup = persistenceSession.popupCompanion(for: annotation)
        return applyHighlightColorState(
            HighlightColorState(
                ownerColor: color,
                popupColor: popup.map { _ in color }
            ),
            to: annotation,
            undoManager: undoManager
        )
    }

    @discardableResult
    private func applyHighlightColorState(
        _ state: HighlightColorState,
        to annotation: PDFAnnotation,
        undoManager: UndoManager?
    ) -> Bool {
        guard persistenceSession.canChangeColor(of: annotation) else { return false }
        let popup = persistenceSession.popupCompanion(for: annotation)
        let previous = HighlightColorState(
            ownerColor: annotation.color,
            popupColor: popup.map { persistenceSession.popupColor(for: $0) }
        )
        guard previous.ownerColor != state.ownerColor
                || previous.popupColor != state.popupColor else { return true }

        undoManager?.registerUndo(withTarget: self) { document in
            document.applyHighlightColorState(
                previous,
                to: annotation,
                undoManager: undoManager
            )
        }
        undoManager?.setActionName("Change Highlight Color")

        objectWillChange.send()
        annotation.color = state.ownerColor
        annotation.removeValue(forAnnotationKey: .appearanceDictionary)
        annotation.modificationDate = Date()
        persistenceSession.markColorChanged(on: annotation)
        if let popup, let popupColor = state.popupColor {
            popup.color = popupColor
            popup.removeValue(forAnnotationKey: .appearanceDictionary)
            persistenceSession.markPopupColorChanged(on: popup, to: popupColor)
        }
        recordAnnotationMutation()
        suppressPopupPresentation()
        return true
    }

    private func updatePopupCompanion(for annotation: PDFAnnotation) {
        guard
            annotation.type?.caseInsensitiveCompare("Highlight") == .orderedSame,
            let page = annotation.page
        else { return }

        if (annotation.contents ?? "").isEmpty {
            if let popup = persistenceSession.popupCompanion(for: annotation) {
                persistenceSession.detachPopup(popup, from: annotation)
                popupDiskStates.removeValue(forKey: ObjectIdentifier(popup))
            }
            return
        }

        let popup: PDFAnnotation
        if let existing = persistenceSession.popupCompanion(for: annotation) {
            popup = existing
        } else if let transient = annotation.popup {
            // PDFKit or an importing caller may attach a companion before the
            // owner enters MathPDF's persistence model. Adopt that exact
            // object once, then the suppression boundary severs both live
            // pointers so it cannot become a second viewer affordance.
            popup = transient
            persistenceSession.registerCreated(
                transient,
                pageIndex: pdfDocument.index(for: page)
            )
        } else if let detached = persistenceSession.takeDetachedPopup(for: annotation) {
            popup = detached
        } else {
            popup = PDFAnnotationInteroperability.makePopupCompanion(for: annotation, on: page)
            persistenceSession.registerCreated(
                popup,
                pageIndex: pdfDocument.index(for: page)
            )
        }
        // An imported Popup is opaque companion-private state. Owner text is
        // authoritative, but an ordinary owner edit must not erase or normalize
        // imported `/Contents`, `/M`, `/RC`, `/AP`, color, or unknown keys.
        // MathPDF defaults apply only to a companion created by this session.
        if !persistenceSession.isImported(popup) {
            let ownerContents = annotation.contents
            popup.contents = nil
            popup.color = annotation.color
            popup.modificationDate = annotation.modificationDate
            annotation.contents = ownerContents
        }
        if case nil = popupDiskStates[ObjectIdentifier(popup)] {
            popupDiskStates[ObjectIdentifier(popup)] = PDFPopupDiskState(flags: 0, isOpen: false)
        }
        persistenceSession.markPopupEdge(owner: annotation, popup: popup)
        suppressPopupPresentation()
    }

    private func noteEditState(
        for annotation: PDFAnnotation,
        replacingContentsWith contents: String? = nil
    ) -> NoteEditState {
        let popup = persistenceSession.popupCompanion(for: annotation)
        return NoteEditState(
            contents: contents ?? annotation.contents,
            modificationDate: annotation.modificationDate,
            richContents: persistenceSession.richContents(of: annotation),
            durableName: annotation.value(
                forAnnotationKey: PDFAnnotationKey(rawValue: "/NM")
            ) as? String,
            popup: popup,
            popupDiskState: popup.flatMap { popupDiskStates[ObjectIdentifier($0)] }
        )
    }

    private func restoreNoteEditState(
        _ state: NoteEditState,
        of annotation: PDFAnnotation,
        undoManager: UndoManager?
    ) {
        guard canEdit(annotation) else { return }
        let inverse = noteEditState(for: annotation)
        undoManager?.registerUndo(withTarget: self) { document in
            document.restoreNoteEditState(inverse, of: annotation, undoManager: undoManager)
        }
        undoManager?.setActionName("Edit Note")

        objectWillChange.send()
        restorePopupTopology(state, of: annotation)
        annotation.contents = state.contents
        annotation.modificationDate = state.modificationDate
        setOptionalAnnotationString(
            state.richContents,
            key: PDFAnnotationKey(rawValue: "/RC"),
            on: annotation
        )
        persistenceSession.restoreRichContents(state.richContents, on: annotation)
        setOptionalAnnotationString(
            state.durableName,
            key: PDFAnnotationKey(rawValue: "/NM"),
            on: annotation
        )
        persistenceSession.markContentsStateRestored(on: annotation)
        recordAnnotationMutation()
    }

    private func restorePopupTopology(
        _ state: NoteEditState,
        of annotation: PDFAnnotation
    ) {
        let desiredPopup = state.popup
        if let currentPopup = persistenceSession.popupCompanion(for: annotation),
           currentPopup !== desiredPopup {
            persistenceSession.detachPopup(currentPopup, from: annotation)
            popupDiskStates.removeValue(forKey: ObjectIdentifier(currentPopup))
        }

        guard let desiredPopup,
              persistenceSession.popupCompanion(for: annotation) !== desiredPopup,
              annotation.page != nil else { return }
        persistenceSession.markRestored(desiredPopup)
        persistenceSession.restorePopupEdge(owner: annotation, popup: desiredPopup)
        if let popupDiskState = state.popupDiskState {
            popupDiskStates[ObjectIdentifier(desiredPopup)] = popupDiskState
        }
        suppressPopupPresentation()
    }

    private func setOptionalAnnotationString(
        _ value: String?,
        key: PDFAnnotationKey,
        on annotation: PDFAnnotation
    ) {
        if let value {
            _ = annotation.setValue(value, forAnnotationKey: key)
        } else {
            annotation.removeValue(forAnnotationKey: key)
        }
    }

    private func trackAnnotationIfNeeded(_ annotation: PDFAnnotation) {
        guard let page = annotation.page else { return }
        persistenceSession.registerCreated(
            annotation,
            pageIndex: pdfDocument.index(for: page)
        )
    }

    private func captureAndSuppressPopupPresentation() {
        popupDiskStates = PDFAnnotationInteroperability.capturePopupDiskStates(in: pdfDocument)
        suppressPopupPresentation()
    }

    private func suppressPopupPresentation() {
        PDFAnnotationInteroperability.suppressPopupPresentation(
            in: pdfDocument,
            states: &popupDiskStates
        )
        persistenceSession.suppressPopupPresentation(in: pdfDocument)
    }

    private func recordAnnotationMutation() {
        annotationRevision &+= 1
        markSerializationDirty()
    }

    private func markSerializationDirty() {
        serializationRevision &+= 1
        cachedSnapshotRevision = nil
        cachedSnapshotData = nil
    }

    private func applyPreambleMetadata() {
        persistenceSession.markMetadataChanged()
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
    static func uiTestFixtureData() -> Data {
        let base = PDFDocument(data: uiTestBasePDFData()) ?? PDFDocument()
        guard
            let first = base.page(at: 0),
            base.page(at: 1) != nil,
            base.page(at: 2) != nil
        else { return Data() }

        let outlineRoot = PDFOutline()
        let chapter = PDFOutline()
        chapter.label = "Test chapter"
        chapter.destination = PDFDestination(page: first, at: CGPoint(x: 0, y: 792))
        outlineRoot.insertChild(chapter, at: 0)
        base.outlineRoot = outlineRoot

        // PDFKit's serializer can emit malformed Popup /Parent references for
        // newly authored annotations. Build the page/outline skeleton with
        // PDFKit, then seed annotations through MathPDF's production writer so
        // the UI fixture exercises the same valid graph as the real app.
        guard
            let baseData = base.dataRepresentation(),
            let seeded = try? MathPDFDocument(data: baseData),
            let second = seeded.pdfDocument.page(at: 1),
            let third = seeded.pdfDocument.page(at: 2),
            let secondPageText = second.string,
            let selection = second.selection(
                for: NSRange(location: 0, length: secondPageText.utf16.count)
            ),
            let highlight = seeded.addHighlight(from: selection, undoManager: nil)
        else { return Data() }

        seeded.updateContents(
            of: highlight,
            to: #"A point of $\Q$"#,
            undoManager: nil
        )
        seeded.preamble = #"\newcommand{\Q}{\mathbb{Q}}"#

        if let textNote = seeded.addTextNote(
            on: third,
            at: CGPoint(x: 522, y: 72),
            undoManager: nil
        ) {
            seeded.updateContents(of: textNote, to: "Edge note", undoManager: nil)
        }

        return (try? seeded.serializedData()) ?? Data()
    }

    private static func uiTestBasePDFData() -> Data {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data) else { return Data() }
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return Data() }

        let font = CTFontCreateWithName("Helvetica" as CFString, 16, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(
            string: "A point of rational numbers",
            attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]
        ))

        for pageIndex in 0..<3 {
            context.beginPDFPage(nil)
            if pageIndex == 1 {
                context.textPosition = CGPoint(x: 90, y: 650)
                CTLineDraw(line, context)
            }
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
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
