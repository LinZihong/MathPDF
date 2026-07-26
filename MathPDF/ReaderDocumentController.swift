import Combine
import PDFKit

@MainActor
final class ReaderDocumentController: ObservableObject {
    @Published var sidebarMode: ReaderSidebarMode = .contents
    @Published var notes: [AnnotationNote] = []
    @Published var outline: [DocumentOutlineItem] = []
    @Published var selectedNoteID: AnnotationNote.ID?
    @Published var navigationRequest: ReaderNavigationRequest?
    @Published var isPreambleInspectorPresented = false
    @Published var searchText = ""
    @Published var readerTool: ReaderTool = .browse
    @Published var highlightColor: AnnotationColorChoice = .yellow
    @Published var annotationAuthoringNotice: AnnotationAuthoringNotice?
    @Published private(set) var pendingPresentedNoteID: AnnotationNote.ID?
    @Published private(set) var presentedNoteID: AnnotationNote.ID?

    let document: MathPDFDocument
    let readerProxy = PDFViewProxy()

    private var cancellables: Set<AnyCancellable> = []

    init(document: MathPDFDocument) {
        self.document = document
        rebuildIndex()

        document.annotationChanges
            .sink { [weak self] _ in
                self?.rebuildNotes()
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        document.preambleChanges
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        readerProxy.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    func rebuildIndex() {
        outline = PDFNoteExtractor.extractOutline(from: document.pdfDocument)
        rebuildNotes()
    }

    private func rebuildNotes() {
        notes = PDFNoteExtractor.extractNotes(from: document.pdfDocument)
        let noteIDs = Set(notes.map(\.id))
        if let selectedNoteID, !noteIDs.contains(selectedNoteID) {
            self.selectedNoteID = nil
        }
        if let pendingPresentedNoteID, !noteIDs.contains(pendingPresentedNoteID) {
            self.pendingPresentedNoteID = nil
        }
        if let presentedNoteID, !noteIDs.contains(presentedNoteID) {
            self.presentedNoteID = nil
        }
    }

    func selectNote(_ note: AnnotationNote) {
        let wasAlreadySelected = selectedNoteID == note.id
        selectedNoteID = note.id
        if wasAlreadySelected {
            guard pendingPresentedNoteID != note.id, presentedNoteID != note.id else { return }
        }
        navigateToNote(note)
    }

    func annotationPresentationChanged(noteID: AnnotationNote.ID, isPresented: Bool) {
        if isPresented {
            presentedNoteID = noteID
            if pendingPresentedNoteID == noteID {
                pendingPresentedNoteID = nil
            }
        } else if presentedNoteID == noteID {
            presentedNoteID = nil
            if pendingPresentedNoteID == nil, selectedNoteID == noteID {
                selectedNoteID = nil
            }
        }
    }

    func selectNote(id: AnnotationNote.ID?) {
        guard let id else {
            selectedNoteID = nil
            return
        }
        guard let note = notes.first(where: { $0.id == id }) else { return }
        selectNote(note)
    }

    func navigateToNote(_ note: AnnotationNote) {
        let request = ReaderNavigationRequest(
            token: UUID(),
            pageIndex: note.pageIndex,
            point: nil,
            bounds: note.bounds,
            noteID: note.id,
            opensNote: !note.trimmedContents.isEmpty,
            startsEditing: false,
            annotation: note.annotation
        )
        navigationRequest = request
        pendingPresentedNoteID = request.opensNote ? note.id : nil
    }

    func presentNote(_ note: AnnotationNote, startsEditing: Bool) {
        selectedNoteID = notes.contains(where: { $0.id == note.id }) ? note.id : nil
        navigationRequest = ReaderNavigationRequest(
            token: UUID(),
            pageIndex: note.pageIndex,
            point: nil,
            bounds: note.bounds,
            noteID: note.id,
            opensNote: true,
            startsEditing: startsEditing,
            annotation: note.annotation
        )
        pendingPresentedNoteID = note.id
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
            startsEditing: false,
            annotation: nil
        )
    }

    func annotationActivated(_ annotation: PDFAnnotation) -> AnnotationNote? {
        guard let note = note(for: annotation, includeEmptyContents: true) else { return nil }
        selectedNoteID = notes.contains(where: { $0.id == note.id }) ? note.id : nil
        return note
    }

    var canAuthorAnnotations: Bool {
        document.editingError == nil
    }

    var annotationAuthoringUnavailableReason: String? {
        document.editingError?.localizedDescription
    }

    func capabilities(for annotation: PDFAnnotation) -> AnnotationNoteCapabilities {
        let canEdit = document.canEdit(annotation)
        let canChangeColor = document.canChangeColor(of: annotation)
        return AnnotationNoteCapabilities(
            canEditContents: canEdit,
            canDelete: canEdit,
            canChangeColor: canChangeColor,
            editingUnavailableReason: document.editingUnavailableReason(for: annotation),
            colorUnavailableReason: document.colorEditingUnavailableReason(for: annotation)
        )
    }

    func togglePreambleInspector() {
        isPreambleInspectorPresented.toggle()
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
        if selectedNoteID == note.id {
            selectedNoteID = nil
        }
    }

    func addHighlight(undoManager: UndoManager?) -> PDFAnnotation? {
        guard let selection = readerProxy.currentSelection else { return nil }
        annotationAuthoringNotice = nil
        return addHighlight(from: selection, undoManager: undoManager)
    }

    func addHighlightWithNote(undoManager: UndoManager?) -> PDFAnnotation? {
        guard let selection = readerProxy.currentSelection else { return nil }
        return addHighlightWithNote(from: selection, undoManager: undoManager)
    }

    func addHighlightWithNote(
        from selection: PDFSelection,
        undoManager: UndoManager?
    ) -> PDFAnnotation? {
        annotationAuthoringNotice = nil
        let pageIDs = Set(selection.pages.map(ObjectIdentifier.init))
        guard pageIDs.count == 1 else {
            annotationAuthoringNotice = .multiPageHighlightNote
            return nil
        }
        return addHighlight(from: selection, undoManager: undoManager)
    }

    func addHighlight(
        from selection: PDFSelection,
        undoManager: UndoManager?
    ) -> PDFAnnotation? {
        let annotation = document.addHighlight(
            from: selection,
            color: highlightColor.nsColor,
            undoManager: undoManager
        )
        if annotation != nil {
            readerProxy.clearSelection()
        }
        return annotation
    }

    func search() {
        readerProxy.find(searchText)
    }
}
