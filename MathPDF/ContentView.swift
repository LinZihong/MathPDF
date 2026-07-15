import PDFKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var controller: ReaderDocumentController
    let fileURL: URL?

    @Environment(\.undoManager) private var undoManager
    @State private var pageField = "1"

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
                onUpdateNote: updateNote,
                onCommitNoteEdit: commitNoteEdit,
                onDeleteNote: deleteNote,
                onUpdateColor: updateColor,
                onCancelTextNote: { controller.readerTool = .browse },
                onCreateTextNote: createTextNote,
                onAnnotationPresentationChanged: controller.annotationPresentationChanged,
                enforceRuntimeAnnotationPresentation: controller.document.enforceRuntimeAnnotationPresentation
            )
        }
        .navigationSplitViewStyle(.balanced)
        .inspector(isPresented: $controller.isPreambleInspectorPresented) {
            PreambleInspectorView(document: controller.document)
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
        .focusedSceneValue(\.pdfViewProxy, controller.readerProxy)
        .focusedSceneValue(
            \.readerCommandContext,
            ReaderCommandContext(togglePreambleInspector: controller.togglePreambleInspector)
        )
        .navigationTitle(fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled PDF")
        .navigationSubtitle(
            "Page \(controller.readerProxy.pageIndex + 1) of \(max(controller.readerProxy.pageCount, 1))"
        )
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

    private func updateNote(_ note: AnnotationNote, contents: String) -> Bool {
        controller.document.updateContentsDuringEditing(
            of: note.annotation,
            to: contents
        )
    }

    private func commitNoteEdit(_ note: AnnotationNote, originalContents: String) {
        controller.document.commitContentsEditingTransaction(
            of: note.annotation,
            from: originalContents,
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
