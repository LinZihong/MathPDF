import Combine
import PDFKit

enum ReaderInspectorDestination {
    case note(AnnotationNote, startsEditing: Bool)
    case preamble
}

@MainActor
final class ReaderDocumentController: ObservableObject {
    @Published var sidebarMode: ReaderSidebarMode = .contents
    @Published var notes: [AnnotationNote] = []
    @Published var outline: [DocumentOutlineItem] = []
    @Published var selectedNoteID: AnnotationNote.ID?
    @Published var navigationRequest: ReaderNavigationRequest?
    @Published var inspectorDestination: ReaderInspectorDestination?
    @Published var searchText = ""
    @Published var readerTool: ReaderTool = .browse

    let document: MathPDFDocument
    let readerProxy = PDFViewProxy()

    private var cancellables: Set<AnyCancellable> = []

    init(document: MathPDFDocument) {
        self.document = document
        rebuildIndex()

        document.$annotationRevision
            .dropFirst()
            .sink { [weak self] _ in self?.rebuildIndex() }
            .store(in: &cancellables)

        readerProxy.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    func rebuildIndex() {
        notes = PDFNoteExtractor.extractNotes(from: document.pdfDocument)
        outline = PDFNoteExtractor.extractOutline(from: document.pdfDocument)
        if let selectedNoteID, !notes.contains(where: { $0.id == selectedNoteID }) {
            self.selectedNoteID = nil
        }
        if case let .note(pinnedNote, startsEditing) = inspectorDestination,
           let refreshed = note(for: pinnedNote.annotation, includeEmptyContents: true) {
            inspectorDestination = .note(refreshed, startsEditing: startsEditing)
        } else if case .note = inspectorDestination {
            inspectorDestination = nil
        }
    }

    func selectNote(_ note: AnnotationNote) {
        selectedNoteID = note.id
        navigationRequest = ReaderNavigationRequest(
            token: UUID(),
            pageIndex: note.pageIndex,
            point: nil,
            bounds: note.bounds,
            noteID: note.id,
            opensNote: !note.trimmedContents.isEmpty,
            annotation: note.annotation
        )
    }

    func selectOutline(_ item: DocumentOutlineItem) {
        guard let pageIndex = item.pageIndex else { return }
        navigationRequest = ReaderNavigationRequest(
            token: UUID(),
            pageIndex: pageIndex,
            point: item.point,
            bounds: nil,
            noteID: nil,
            opensNote: false,
            annotation: nil
        )
    }

    func annotationActivated(_ annotation: PDFAnnotation) -> AnnotationNote? {
        guard let note = note(for: annotation, includeEmptyContents: true) else { return nil }
        selectedNoteID = notes.contains(where: { $0.id == note.id }) ? note.id : nil
        return note
    }

    func pin(_ note: AnnotationNote, startsEditing: Bool = false) {
        inspectorDestination = .note(note, startsEditing: startsEditing)
    }

    func togglePreambleInspector() {
        if case .preamble = inspectorDestination {
            inspectorDestination = nil
        } else {
            inspectorDestination = .preamble
        }
    }

    func note(for annotation: PDFAnnotation, includeEmptyContents: Bool) -> AnnotationNote? {
        guard
            let page = annotation.page,
            document.pdfDocument.index(for: page) >= 0
        else { return nil }
        return PDFNoteExtractor.note(
            for: annotation,
            pageIndex: document.pdfDocument.index(for: page),
            includeEmptyContents: includeEmptyContents
        )
    }

    func addTextNote(on page: PDFPage, at point: CGPoint, undoManager: UndoManager?) -> PDFAnnotation? {
        let annotation = document.addTextNote(on: page, at: point, undoManager: undoManager)
        readerTool = .browse
        return annotation
    }

    func removeNote(_ note: AnnotationNote, undoManager: UndoManager?) {
        document.removeAnnotation(note.annotation, undoManager: undoManager)
        if case let .note(pinnedNote, _) = inspectorDestination, pinnedNote.id == note.id {
            inspectorDestination = nil
        }
        if selectedNoteID == note.id {
            selectedNoteID = nil
        }
    }

    func addHighlight(undoManager: UndoManager?) -> PDFAnnotation? {
        guard let selection = readerProxy.currentSelection else { return nil }
        let annotation = document.addHighlight(from: selection, undoManager: undoManager)
        if annotation != nil {
            readerProxy.clearSelection()
        }
        return annotation
    }

    func search() {
        readerProxy.find(searchText)
    }
}
