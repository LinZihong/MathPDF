import PDFKit
import Combine
import SwiftUI

struct ContentView: View {
    @ObservedObject var controller: ReaderDocumentController
    let fileURL: URL?

    @Environment(\.undoManager) private var undoManager
    @State private var pageField = "1"
    @State private var isSearchPresented = false
    @StateObject private var documentWindowState = DocumentWindowState()
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        NavigationSplitView {
            ReaderSidebar(controller: controller)
                .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 340)
        } detail: {
            PDFReaderView(
                document: controller.document.pdfDocument,
                annotationRevision: controller.document.annotationRevision,
                navigationRequest: controller.navigationRequest,
                tool: controller.readerTool,
                preamble: controller.document.preamble,
                proxy: controller.readerProxy,
                noteForAnnotation: controller.annotationActivated,
                capabilitiesForAnnotation: controller.capabilities,
                onCommitNoteEdit: commitNoteEdit,
                onDeleteNote: deleteNote,
                onUpdateColor: updateColor,
                onCancelTextNote: { controller.readerTool = .browse },
                onCreateTextNote: createTextNote,
                onCreateHighlight: createHighlight,
                onAnnotationPresentationChanged: controller.annotationPresentationChanged,
                enforceRuntimeAnnotationPresentation: controller.document.enforceRuntimeAnnotationPresentation
            )
        }
        .navigationSplitViewStyle(.balanced)
        .inspector(isPresented: $controller.isPreambleInspectorPresented) {
            PreambleInspectorView(
                controller: controller,
                onDocumentChange: documentWindowState.recordChange
            )
                .inspectorColumnWidth(min: 270, ideal: 330, max: 440)
        }
        .toolbar {
            ReaderToolbar(
                controller: controller,
                pageField: $pageField,
                onHighlight: addHighlight,
                onHighlightWithNote: addHighlightWithNote,
                onToggleTextNote: toggleTextNoteTool
            )
        }
        .searchable(
            text: $controller.searchText,
            isPresented: $isSearchPresented,
            placement: .toolbar,
            prompt: "Search PDF"
        )
        .searchFocused($isSearchFocused)
        .onSubmit(of: .search) {
            controller.search()
        }
        .onChange(of: controller.searchText) { _, searchText in
            searchTextChanged(searchText)
        }
        .focusedSceneValue(\.pdfViewProxy, controller.readerProxy)
        .focusedSceneValue(
            \.readerCommandContext,
            ReaderCommandContext(
                togglePreambleInspector: controller.togglePreambleInspector,
                focusSearch: focusSearch
            )
        )
        .navigationTitle(fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled PDF")
        .navigationSubtitle(navigationSubtitle)
        .background {
            WindowDocumentEditedObserver(state: documentWindowState)
                .frame(width: 0, height: 0)
        }
        .alert(item: $controller.annotationAuthoringNotice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .onReceive(controller.readerProxy.$pageIndex) { pageIndex in
            pageField = String(pageIndex + 1)
        }
    }

    private func focusSearch() {
        isSearchPresented = true
        DispatchQueue.main.async {
            isSearchFocused = true
        }
    }

    private var navigationSubtitle: String {
        let page = controller.readerProxy.pageIndex + 1
        let count = max(controller.readerProxy.pageCount, 1)
        return "Page \(page) of \(count)" + (documentWindowState.isEdited ? " — Edited" : "")
    }

    private func searchTextChanged(_ searchText: String) {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            controller.search()
        }
    }

    private func addHighlight() {
        _ = controller.addHighlight(undoManager: undoManager)
    }

    private func addHighlightWithNote() {
        guard
            let annotation = controller.addHighlightWithNote(undoManager: undoManager),
            let note = controller.annotationActivated(annotation)
        else { return }
        controller.presentNote(note, startsEditing: true)
    }

    private func toggleTextNoteTool() {
        controller.readerTool = controller.readerTool == .textNote ? .browse : .textNote
    }

    private func commitNoteEdit(
        _ note: AnnotationNote,
        originalContents: String,
        contents: String
    ) -> Bool {
        guard contents != originalContents else { return true }
        return controller.document.updateContents(
            of: note.annotation,
            to: contents,
            undoManager: undoManager
        )
    }

    private func deleteNote(_ note: AnnotationNote) {
        controller.removeNote(note, undoManager: undoManager)
    }

    private func updateColor(
        _ note: AnnotationNote,
        color: AnnotationColorChoice,
        undoManager: UndoManager?
    ) -> Bool {
        controller.document.updateHighlightColor(
            of: note.annotation,
            to: color.nsColor,
            undoManager: undoManager
        )
    }

    private func createTextNote(on page: PDFPage, at point: CGPoint) -> AnnotationNote? {
        guard let annotation = controller.addTextNote(
            on: page,
            at: point,
            undoManager: undoManager
        ) else { return nil }
        return controller.annotationActivated(annotation)
    }

    private func createHighlight(
        from selection: PDFSelection,
        withNote: Bool
    ) -> PDFAnnotation? {
        if withNote {
            return controller.addHighlightWithNote(
                from: selection,
                undoManager: undoManager
            )
        }
        return controller.addHighlight(from: selection, undoManager: undoManager)
    }
}

@MainActor
final class DocumentWindowState: ObservableObject {
    @Published private(set) var isEdited = false

    private weak var window: NSWindow?
    private var observation: NSKeyValueObservation?

    func attach(to window: NSWindow?) {
        guard self.window !== window else { return }
        observation = nil
        self.window = window
        guard let window else {
            isEdited = false
            return
        }
        isEdited = window.isDocumentEdited
        observation = window.observe(\.isDocumentEdited, options: [.new]) {
            [weak self] _, change in
            MainActor.assumeIsolated {
                self?.isEdited = change.newValue ?? false
            }
        }
    }

    func recordChange() {
        if let document = window?.windowController?.document {
            document.updateChangeCount(.changeDone)
        } else {
            window?.isDocumentEdited = true
        }
    }
}

private struct WindowDocumentEditedObserver: NSViewRepresentable {
    @ObservedObject var state: DocumentWindowState

    func makeNSView(context: Context) -> DocumentEditedTrackingView {
        DocumentEditedTrackingView(onWindowChange: state.attach)
    }

    func updateNSView(_ view: DocumentEditedTrackingView, context: Context) {
        view.onWindowChange = state.attach
        state.attach(to: view.window)
    }
}

private final class DocumentEditedTrackingView: NSView {
    var onWindowChange: (NSWindow?) -> Void

    init(onWindowChange: @escaping (NSWindow?) -> Void) {
        self.onWindowChange = onWindowChange
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange(window)
    }
}

struct PDFViewProxyFocusedKey: FocusedValueKey {
    typealias Value = PDFViewProxy
}

extension FocusedValues {
    var pdfViewProxy: PDFViewProxy? {
        get { self[PDFViewProxyFocusedKey.self] }
        set { self[PDFViewProxyFocusedKey.self] = newValue }
    }
}
