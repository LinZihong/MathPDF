import AppKit
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
                .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 350)
        } detail: {
            PDFReaderView(
                document: controller.document.pdfDocument,
                navigationRequest: controller.navigationRequest,
                tool: controller.readerTool,
                preamble: controller.document.preamble,
                proxy: controller.readerProxy,
                noteForAnnotation: controller.annotationActivated,
                onUpdateNote: updateNote,
                onPinNote: { note, startsEditing in
                    controller.pin(note, startsEditing: startsEditing)
                },
                onCancelTextNote: { controller.readerTool = .browse },
                onCreateTextNote: createTextNote
            )
            .accessibilityIdentifier("pdf-reader")
        }
        .navigationSplitViewStyle(.balanced)
        .inspector(isPresented: inspectorIsPresented) {
            ReaderInspector(controller: controller, onUpdateNote: updateNote)
                .inspectorColumnWidth(min: 260, ideal: 330, max: 480)
        }
        .toolbar { readerToolbar }
        .controlSize(.large)
        .focusedSceneValue(\.pdfViewProxy, controller.readerProxy)
        .navigationTitle(fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled PDF")
        .navigationSubtitle(
            "Page \(controller.readerProxy.pageIndex + 1) of \(max(controller.readerProxy.pageCount, 1))"
        )
        .onReceive(controller.readerProxy.$pageIndex) { pageIndex in
            pageField = String(pageIndex + 1)
        }
        .alert("MathPDF Couldn't Open This PDF", isPresented: .constant(false)) { }
    }

    @ToolbarContentBuilder
    private var readerToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button {
                controller.readerProxy.goBack()
            } label: {
                Label("Back", systemImage: "chevron.left")
                    .frame(minWidth: 32, minHeight: 32)
            }
            .disabled(!controller.readerProxy.canGoBack)
            .help("Back")

            Button {
                controller.readerProxy.goForward()
            } label: {
                Label("Forward", systemImage: "chevron.right")
                    .frame(minWidth: 32, minHeight: 32)
            }
            .disabled(!controller.readerProxy.canGoForward)
            .help("Forward")
        }

        if #available(macOS 26.0, *) {
            ToolbarSpacer(.fixed, placement: .navigation)
        }

        ToolbarItem(placement: .principal) {
            HStack(spacing: 4) {
                TextField("Page", text: $pageField)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 42)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .onSubmit {
                        if let page = Int(pageField) {
                            controller.readerProxy.goToPage(page - 1)
                        }
                    }
                    .accessibilityLabel("Page number")

            }
            .fixedSize()
            .help("Go to Page")
        }

        ToolbarItem(placement: .principal) {
            ControlGroup {
            Button {
                controller.readerProxy.zoomOut()
            } label: {
                Label("Zoom Out", systemImage: "minus.magnifyingglass")
                    .frame(minWidth: 32, minHeight: 32)
            }
            .help("Zoom Out")

            Menu {
                Button("Actual Size") { controller.readerProxy.actualSize() }
                Button("Fit Page") { controller.readerProxy.fitPage() }
                Button("Fit Width") { controller.readerProxy.fitWidth() }
            } label: {
                Text(controller.readerProxy.scaleLabel)
                    .monospacedDigit()
                    .frame(minWidth: 52, minHeight: 32)
            }
            .help("Zoom")

            Button {
                controller.readerProxy.zoomIn()
            } label: {
                Label("Zoom In", systemImage: "plus.magnifyingglass")
                    .frame(minWidth: 32, minHeight: 32)
            }
            .help("Zoom In")
            }
            .controlGroupStyle(.navigation)
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                _ = controller.addHighlight(undoManager: undoManager)
            } label: {
                Label("Highlight Selection", systemImage: "highlighter")
                    .frame(minWidth: 32, minHeight: 32)
            }
            .disabled(!controller.readerProxy.selectionAvailable)
            .help("Highlight Selection")

            Button {
                if controller.readerProxy.selectionAvailable,
                   let annotation = controller.addHighlight(undoManager: undoManager),
                   let note = controller.annotationActivated(annotation) {
                    controller.pin(note, startsEditing: true)
                } else {
                    controller.readerTool = controller.readerTool == .textNote ? .browse : .textNote
                }
            } label: {
                Label("Add Note", systemImage: controller.readerTool == .textNote ? "note.text.badge.plus.fill" : "note.text.badge.plus")
                    .frame(minWidth: 32, minHeight: 32)
            }
            .help(controller.readerTool == .textNote ? "Cancel Adding Note" : "Add Note")

            Button {
                controller.togglePreambleInspector()
            } label: {
                Label("Document Preamble", systemImage: "function")
                    .frame(minWidth: 32, minHeight: 32)
            }
            .help("Document Preamble")
        }

        ToolbarItem(placement: .primaryAction) {
            HStack(spacing: 8) {
                Group {
                    if searchStatusIsCurrent, let searchStatus = controller.readerProxy.searchStatus {
                        HStack(spacing: 2) {
                            Text(searchStatus)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .fixedSize()

                            Button {
                                controller.readerProxy.findPrevious()
                            } label: {
                                Label("Previous Search Result", systemImage: "chevron.up")
                            }
                            .disabled(controller.readerProxy.searchResultCount == 0)

                            Button {
                                controller.readerProxy.findNext()
                            } label: {
                                Label("Next Search Result", systemImage: "chevron.down")
                            }
                            .disabled(controller.readerProxy.searchResultCount == 0)
                        }
                        .controlSize(.small)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 110, alignment: .trailing)

                NativeSearchField(text: $controller.searchText, onSubmit: controller.search)
                    .frame(width: 180, height: 32)
                    .accessibilityIdentifier("document-search")
            }
        }
    }

    private var inspectorIsPresented: Binding<Bool> {
        Binding(
            get: { controller.inspectorDestination != nil },
            set: { isPresented in
                if !isPresented {
                    controller.inspectorDestination = nil
                }
            }
        )
    }

    private var searchStatusIsCurrent: Bool {
        controller.searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(controller.readerProxy.searchQuery) == .orderedSame
    }

    private func updateNote(_ note: AnnotationNote, contents: String) {
        controller.document.updateContents(
            of: note.annotation,
            to: contents,
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

private struct NativeSearchField: NSViewRepresentable {
    @Binding var text: String
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSSearchField {
        let searchField = NSSearchField()
        searchField.placeholderString = "Search"
        searchField.sendsWholeSearchString = true
        searchField.delegate = context.coordinator
        searchField.target = context.coordinator
        searchField.action = #selector(Coordinator.submit(_:))
        searchField.setAccessibilityIdentifier("document-search")
        context.coordinator.attach(searchField)
        return searchField
    }

    func updateNSView(_ searchField: NSSearchField, context: Context) {
        context.coordinator.parent = self
        if searchField.stringValue != text {
            searchField.stringValue = text
        }
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: NativeSearchField
        private weak var searchField: NSSearchField?
        private var focusObserver: NSObjectProtocol?

        init(parent: NativeSearchField) {
            self.parent = parent
        }

        deinit {
            if let focusObserver {
                NotificationCenter.default.removeObserver(focusObserver)
            }
        }

        func attach(_ searchField: NSSearchField) {
            self.searchField = searchField
            focusObserver = NotificationCenter.default.addObserver(
                forName: .focusMathPDFSearch,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let searchField = self?.searchField, searchField.window?.isKeyWindow == true else { return }
                searchField.window?.makeFirstResponder(searchField)
            }
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let searchField = notification.object as? NSSearchField else { return }
            parent.text = searchField.stringValue
        }

        @objc func submit(_ sender: NSSearchField) {
            parent.text = sender.stringValue
            parent.onSubmit()
        }
    }
}

extension Notification.Name {
    static let focusMathPDFSearch = Notification.Name("MathPDF.focusDocumentSearch")
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

private struct ReaderSidebar: View {
    @ObservedObject var controller: ReaderDocumentController
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        VStack(spacing: 0) {
            Menu {
                Picker("Sidebar Content", selection: $controller.sidebarMode) {
                    ForEach(ReaderSidebarMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(controller.sidebarMode.rawValue)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(.rect)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .accessibilityLabel("Sidebar Content")
            .accessibilityIdentifier("sidebar-content-menu")
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .frame(height: 40)

            switch controller.sidebarMode {
            case .contents:
                contents
            case .notes:
                notes
            }
        }
        .background(.thinMaterial)
    }

    @ViewBuilder
    private var contents: some View {
        if controller.outline.isEmpty {
            ContentUnavailableView(
                "No Table of Contents",
                systemImage: "list.bullet.indent",
                description: Text("This PDF does not include an outline.")
            )
        } else {
            List {
                OutlineGroup(controller.outline, children: \.optionalChildren) { item in
                    Button {
                        controller.selectOutline(item)
                    } label: {
                        Text(item.title)
                            .lineLimit(2)
                            .padding(.leading, 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.pageIndex.map { "\(item.title), page \($0 + 1)" } ?? item.title)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder
    private var notes: some View {
        if controller.notes.isEmpty {
            ContentUnavailableView(
                "No Notes",
                systemImage: "note.text",
                description: Text("Highlights with comments and box notes appear here.")
            )
        } else {
            List(selection: sidebarSelection) {
                ForEach(controller.notes) { note in
                    NoteSidebarRow(
                        note: note,
                        isSelected: controller.selectedNoteID == note.id
                    )
                    .tag(note.id)
                    .contextMenu {
                        Button("Delete Note", role: .destructive) {
                            controller.removeNote(note, undoManager: undoManager)
                        }
                    }
                    .accessibilityLabel("Page \(note.pageIndex + 1), \(note.sidebarPreview)")
                    .accessibilityIdentifier("note-row-\(note.pageIndex)-\(note.annotationType.lowercased())")
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .onDeleteCommand {
                guard
                    let selectedNoteID = controller.selectedNoteID,
                    let note = controller.notes.first(where: { $0.id == selectedNoteID })
                else { return }
                controller.removeNote(note, undoManager: undoManager)
            }
        }
    }

    private var sidebarSelection: Binding<AnnotationNote.ID?> {
        Binding(
            get: { controller.selectedNoteID },
            set: { selection in
                guard let selection,
                      let note = controller.notes.first(where: { $0.id == selection })
                else {
                    controller.selectedNoteID = nil
                    return
                }
                controller.selectNote(note)
            }
        )
    }
}

private struct NoteSidebarRow: View {
    let note: AnnotationNote
    let isSelected: Bool

    private var annotationColor: Color {
        Color(nsColor: note.annotation.color)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Page \(note.pageIndex + 1)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                Spacer(minLength: 6)
                if let author = note.author {
                    Text(author)
                        .font(.caption)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(annotationColor)
                    .frame(width: 3)

                VStack(alignment: .leading, spacing: 7) {
                    Text(note.sidebarPreview.replacingOccurrences(of: "\n", with: " "))
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if !note.trimmedSourceText.isEmpty, !note.trimmedContents.isEmpty {
                        Text(note.trimmedContents)
                            .font(.callout)
                            .foregroundStyle(.primary)
                            .lineLimit(3)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(annotationColor.opacity(isSelected ? 0.28 : 0.16), in: .rect(cornerRadius: 4))
                    }
                }
            }
        }
        .padding(.vertical, 5)
    }
}

private struct ReaderInspector: View {
    @ObservedObject var controller: ReaderDocumentController
    let onUpdateNote: (AnnotationNote, String) -> Void
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        switch controller.inspectorDestination {
        case let .note(note, startsEditing):
            NoteInspectorView(
                note: note,
                preamble: controller.document.preamble,
                startsEditing: startsEditing,
                onUpdate: { onUpdateNote(note, $0) },
                onDelete: { controller.removeNote(note, undoManager: undoManager) },
                onClose: { controller.inspectorDestination = nil }
            )
        case .preamble:
            PreambleInspectorView(document: controller.document)
        case nil:
            EmptyView()
        }
    }
}

private extension DocumentOutlineItem {
    var optionalChildren: [DocumentOutlineItem]? { children.isEmpty ? nil : children }
}
