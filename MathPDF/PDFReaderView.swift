import AppKit
import Combine
import PDFKit
import SwiftUI

@MainActor
final class PDFViewProxy: ObservableObject {
    @Published private(set) var pageIndex = 0
    @Published private(set) var pageCount = 0
    @Published private(set) var scaleFactor: CGFloat = 1
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var selectionAvailable = false
    @Published private(set) var searchQuery = ""
    @Published private(set) var isSearching = false
    @Published private(set) var searchResultCount = 0
    @Published private(set) var searchResultIndex = 0

    fileprivate weak var pdfView: PDFView?
    private var searchResults: [PDFSelection] = []
    private var searchIndex = 0
    private var activeSearchQuery = ""
    private var searchToken = UUID()
    private var searchObservers: [NSObjectProtocol] = []

    var currentSelection: PDFSelection? { pdfView?.currentSelection }
    var scaleLabel: String { "\(Int((scaleFactor * 100).rounded()))%" }
    var searchStatus: String? {
        guard !searchQuery.isEmpty else { return nil }
        if isSearching, searchResultCount == 0 { return "Finding…" }
        if searchResultCount == 0 { return "No Results" }
        return "\(searchResultIndex + 1) of \(searchResultCount)"
    }

    fileprivate func attach(_ pdfView: PDFView) {
        if self.pdfView?.document !== pdfView.document {
            cancelSearch()
        }
        self.pdfView = pdfView
        refresh()
    }

    deinit {
        searchObservers.forEach(NotificationCenter.default.removeObserver)
    }

    fileprivate func refresh() {
        guard let pdfView else { return }
        pageCount = pdfView.document?.pageCount ?? 0
        if let page = pdfView.currentPage, let document = pdfView.document {
            pageIndex = max(0, document.index(for: page))
        }
        scaleFactor = pdfView.scaleFactor
        canGoBack = pdfView.canGoBack
        canGoForward = pdfView.canGoForward
        selectionAvailable = !(pdfView.currentSelection?.string?.isEmpty ?? true)
    }

    func zoomIn() { pdfView?.zoomIn(nil); refresh() }
    func zoomOut() { pdfView?.zoomOut(nil); refresh() }

    func actualSize() {
        pdfView?.autoScales = false
        pdfView?.scaleFactor = 1
        refresh()
    }

    func fitPage() {
        guard let pdfView else { return }
        pdfView.displayMode = .singlePage
        pdfView.autoScales = false
        pdfView.scaleFactor = pdfView.scaleFactorForSizeToFit
        refresh()
    }

    func fitWidth() {
        guard let pdfView else { return }
        pdfView.displayMode = .singlePageContinuous
        pdfView.autoScales = false
        pdfView.scaleFactor = pdfView.scaleFactorForSizeToFit
        refresh()
    }

    func goBack() { pdfView?.goBack(nil); refresh() }
    func goForward() { pdfView?.goForward(nil); refresh() }

    func printDocument() {
        pdfView?.print(with: NSPrintInfo.shared, autoRotate: true)
    }

    func goToPage(_ index: Int) {
        guard let document = pdfView?.document, let page = document.page(at: index) else { return }
        let scale = pdfView?.scaleFactor
        pdfView?.go(to: page)
        if let scale { pdfView?.scaleFactor = scale }
        refresh()
    }

    func find(_ query: String) {
        guard let document = pdfView?.document else { return }
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            cancelSearch()
            pdfView?.setCurrentSelection(nil, animate: false)
            return
        }

        if query.caseInsensitiveCompare(activeSearchQuery) == .orderedSame, !searchResults.isEmpty {
            findNext()
            return
        }

        cancelSearch()
        activeSearchQuery = query
        searchQuery = query
        isSearching = true
        searchIndex = 0
        let token = UUID()
        searchToken = token

        searchObservers = [
            NotificationCenter.default.addObserver(
                forName: .PDFDocumentDidFindMatch,
                object: document,
                queue: .main
            ) { [weak self] notification in
                MainActor.assumeIsolated {
                    guard
                        let self,
                        self.searchToken == token,
                        let selection = notification.userInfo?[PDFDocumentFoundSelectionKey] as? PDFSelection
                    else { return }
                    self.searchResults.append(selection)
                    self.searchResultCount = self.searchResults.count
                    if self.searchResults.count == 1 {
                        self.revealCurrentSearchResult()
                    }
                }
            },
            NotificationCenter.default.addObserver(
                forName: .PDFDocumentDidEndFind,
                object: document,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.searchToken == token else { return }
                    self.isSearching = false
                    self.searchObservers.forEach(NotificationCenter.default.removeObserver)
                    self.searchObservers = []
                }
            },
        ]
        document.beginFindString(query, withOptions: [.caseInsensitive])
    }

    func findNext() {
        guard !searchResults.isEmpty else { return }
        searchIndex = (searchIndex + 1) % searchResults.count
        revealCurrentSearchResult()
    }

    func findPrevious() {
        guard !searchResults.isEmpty else { return }
        searchIndex = (searchIndex - 1 + searchResults.count) % searchResults.count
        revealCurrentSearchResult()
    }

    func clearSelection() {
        pdfView?.setCurrentSelection(nil, animate: false)
        refresh()
    }

    private func revealCurrentSearchResult() {
        guard searchResults.indices.contains(searchIndex), let pdfView else { return }
        let selection = searchResults[searchIndex]
        searchResultIndex = searchIndex
        pdfView.setCurrentSelection(selection, animate: false)
        if let page = selection.pages.first {
            pdfView.reveal(selection.bounds(for: page), on: page, padding: 24)
        }
        refresh()
    }

    private func cancelSearch() {
        pdfView?.document?.cancelFindString()
        searchToken = UUID()
        searchObservers.forEach(NotificationCenter.default.removeObserver)
        searchObservers = []
        searchResults = []
        searchIndex = 0
        activeSearchQuery = ""
        searchQuery = ""
        isSearching = false
        searchResultCount = 0
        searchResultIndex = 0
    }
}

struct PDFReaderView: NSViewRepresentable {
    let document: PDFDocument
    let navigationRequest: ReaderNavigationRequest?
    let tool: ReaderTool
    let preamble: String
    let proxy: PDFViewProxy
    let noteForAnnotation: (PDFAnnotation) -> AnnotationNote?
    let onUpdateNote: (AnnotationNote, String) -> Void
    let onPinNote: (AnnotationNote, Bool) -> Void
    let onCancelTextNote: () -> Void
    let onCreateTextNote: (PDFPage, CGPoint) -> AnnotationNote?

    func makeNSView(context: Context) -> ReaderContainerView {
        let view = ReaderContainerView()
        view.setAccessibilityIdentifier("pdf-reader")
        view.pdfView.setAccessibilityIdentifier("pdf-reader")
        view.configure(
            document: document,
            proxy: proxy,
            noteForAnnotation: noteForAnnotation,
            onUpdateNote: onUpdateNote,
            onPinNote: onPinNote,
            onCancelTextNote: onCancelTextNote,
            onCreateTextNote: onCreateTextNote,
            preamble: preamble
        )
        return view
    }

    func updateNSView(_ view: ReaderContainerView, context: Context) {
        view.updateCallbacks(
            noteForAnnotation: noteForAnnotation,
            onUpdateNote: onUpdateNote,
            onPinNote: onPinNote,
            onCancelTextNote: onCancelTextNote,
            onCreateTextNote: onCreateTextNote,
            preamble: preamble
        )
        view.pdfView.readerTool = tool

        if view.pdfView.document !== document {
            view.setDocument(document)
        }
        if let navigationRequest {
            view.handle(navigationRequest)
        }
    }
}

final class ReaderContainerView: NSView {
    let pdfView = ReaderPDFView()

    private weak var proxy: PDFViewProxy?
    private var noteForAnnotation: ((PDFAnnotation) -> AnnotationNote?)?
    private var onUpdateNote: ((AnnotationNote, String) -> Void)?
    private var onPinNote: ((AnnotationNote, Bool) -> Void)?
    private var onCancelTextNote: (() -> Void)?
    private var onCreateTextNote: ((PDFPage, CGPoint) -> AnnotationNote?)?
    private var preamble = ""
    private var lastNavigationToken: UUID?
    private var observations: [NSObjectProtocol] = []
    private var notePopover: NSPopover?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        pdfView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pdfView)
        NSLayoutConstraint.activate([
            pdfView.leadingAnchor.constraint(equalTo: leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: trailingAnchor),
            pdfView.topAnchor.constraint(equalTo: topAnchor),
            pdfView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        pdfView.onAnnotationActivated = { [weak self] annotation in
            self?.presentNote(for: annotation)
        }
        pdfView.onCreateTextNote = { [weak self] page, point in
            guard let self, let note = self.onCreateTextNote?(page, point) else { return }
            self.notePopover?.close()
            self.onPinNote?(note, true)
        }
        pdfView.onCancelTextNote = { [weak self] in self?.onCancelTextNote?() }
        pdfView.onBeginScroll = { [weak self] in
            self?.notePopover?.performClose(nil)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        observations.forEach(NotificationCenter.default.removeObserver)
    }

    func configure(
        document: PDFDocument,
        proxy: PDFViewProxy,
        noteForAnnotation: @escaping (PDFAnnotation) -> AnnotationNote?,
        onUpdateNote: @escaping (AnnotationNote, String) -> Void,
        onPinNote: @escaping (AnnotationNote, Bool) -> Void,
        onCancelTextNote: @escaping () -> Void,
        onCreateTextNote: @escaping (PDFPage, CGPoint) -> AnnotationNote?,
        preamble: String
    ) {
        self.proxy = proxy
        updateCallbacks(
            noteForAnnotation: noteForAnnotation,
            onUpdateNote: onUpdateNote,
            onPinNote: onPinNote,
            onCancelTextNote: onCancelTextNote,
            onCreateTextNote: onCreateTextNote,
            preamble: preamble
        )

        pdfView.displayMode = .singlePageContinuous
        pdfView.displaysPageBreaks = true
        pdfView.pageShadowsEnabled = true
        pdfView.autoScales = true
        pdfView.backgroundColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedWhite: 0.105, alpha: 1)
                : NSColor(calibratedWhite: 0.82, alpha: 1)
        }
        setDocument(document)
        proxy.attach(pdfView)

        DispatchQueue.main.async { [weak pdfView, weak proxy] in
            guard let pdfView else { return }
            let fittedScale = pdfView.scaleFactor
            pdfView.autoScales = false
            pdfView.scaleFactor = fittedScale
            proxy?.refresh()
        }

        let names: [Notification.Name] = [
            .PDFViewPageChanged,
            .PDFViewScaleChanged,
            .PDFViewSelectionChanged,
            .PDFViewChangedHistory
        ]
        observations = names.map { name in
            NotificationCenter.default.addObserver(
                forName: name,
                object: pdfView,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.proxy?.refresh()
                }
            }
        }
    }

    func updateCallbacks(
        noteForAnnotation: @escaping (PDFAnnotation) -> AnnotationNote?,
        onUpdateNote: @escaping (AnnotationNote, String) -> Void,
        onPinNote: @escaping (AnnotationNote, Bool) -> Void,
        onCancelTextNote: @escaping () -> Void,
        onCreateTextNote: @escaping (PDFPage, CGPoint) -> AnnotationNote?,
        preamble: String
    ) {
        self.noteForAnnotation = noteForAnnotation
        self.onUpdateNote = onUpdateNote
        self.onPinNote = onPinNote
        self.onCancelTextNote = onCancelTextNote
        self.onCreateTextNote = onCreateTextNote
        self.preamble = preamble
    }

    func setDocument(_ document: PDFDocument) {
        notePopover?.close()
        closeNativePopups(in: document)
        pdfView.document = document
        proxy?.attach(pdfView)
    }

    func handle(_ request: ReaderNavigationRequest) {
        guard lastNavigationToken != request.token else { return }
        lastNavigationToken = request.token
        guard let document = pdfView.document, let page = document.page(at: request.pageIndex) else { return }

        let originalScale = pdfView.scaleFactor
        let pagePoint = request.point ?? CGPoint(
            x: request.bounds?.midX ?? page.bounds(for: .cropBox).midX,
            y: request.bounds?.maxY ?? page.bounds(for: .cropBox).maxY
        )
        let pageRect = request.bounds ?? CGRect(origin: pagePoint, size: CGSize(width: 1, height: 1))
        pdfView.reveal(pageRect, on: page, padding: 24)
        assert(pdfView.scaleFactor == originalScale)

        if request.opensNote, let annotation = request.annotation {
            DispatchQueue.main.async { [weak self] in self?.presentNote(for: annotation) }
        }
        proxy?.refresh()
    }

    private func closeNativePopups(in document: PDFDocument) {
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            for annotation in page.annotations {
                annotation.isOpen = false
                annotation.popup?.isOpen = false
            }
        }
    }

    private func presentNote(for annotation: PDFAnnotation) {
        guard let note = noteForAnnotation?(annotation), let page = annotation.page else { return }

        if note.trimmedContents.isEmpty {
            notePopover?.close()
            onPinNote?(note, true)
            return
        }

        if note.contents.count > 900 || bounds.width < 760 || bounds.height < 520 {
            notePopover?.close()
            onPinNote?(note, false)
            return
        }

        notePopover?.close()
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let popoverHeight = preferredPopoverHeight(for: note.contents)
        popover.contentSize = NSSize(width: 320, height: popoverHeight)
        popover.contentViewController = NSHostingController(
            rootView: NoteReadingPopover(
                note: note,
                preamble: preamble,
                height: popoverHeight,
                onEdit: { [weak self, weak popover] in
                    popover?.close()
                    self?.onPinNote?(note, true)
                }
            )
        )
        notePopover = popover

        let rect = pdfView.convert(annotation.bounds, from: page)
        popover.show(relativeTo: rect, of: pdfView, preferredEdge: .maxX)
    }

    private func preferredPopoverHeight(for contents: String) -> CGFloat {
        let lineCount = contents.split(separator: "\n", omittingEmptySubsequences: false).count
        let estimatedWrappedLines = max(lineCount, Int(ceil(Double(contents.count) / 46)))
        switch estimatedWrappedLines {
        case ...3:
            return 120
        case 4...7:
            return 175
        default:
            return 240
        }
    }
}

extension PDFView {
    func reveal(_ pageRect: CGRect, on page: PDFPage, padding: CGFloat) {
        guard let documentView else {
            go(to: pageRect, on: page)
            return
        }

        let rectInPDFView = convert(pageRect, from: page)
        let rectInDocumentView = documentView.convert(rectInPDFView, from: self)
        let comfortablyVisible = documentView.visibleRect.insetBy(dx: padding, dy: padding)
        guard !comfortablyVisible.contains(rectInDocumentView) else { return }

        // Record the transition before directly scrolling PDFKit's document view.
        // Doing this afterward records an incidental page crossed in continuous
        // scroll mode and makes Back return to the wrong location.
        if currentPage !== page {
            go(to: page)
        }
        let updatedVisibleRect = documentView.visibleRect.insetBy(dx: padding, dy: padding)
        if !updatedVisibleRect.contains(rectInDocumentView) {
            documentView.scrollToVisible(rectInDocumentView.insetBy(dx: -padding, dy: -padding))
        }
    }
}

final class ReaderPDFView: PDFView {
    var readerTool: ReaderTool = .browse {
        didSet {
            guard oldValue != readerTool else { return }
            window?.invalidateCursorRects(for: self)
        }
    }
    var onAnnotationActivated: ((PDFAnnotation) -> Void)?
    var onCreateTextNote: ((PDFPage, CGPoint) -> Void)?
    var onCancelTextNote: (() -> Void)?
    var onBeginScroll: (() -> Void)?

    private var mouseDownLocation: CGPoint?
    private var deferredMouseDownEvent: NSEvent?
    private var deferredAnnotation: PDFAnnotation?
    private var forwardedDeferredMouseDown = false

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = convert(event.locationInWindow, from: nil)

        if readerTool == .textNote,
           let page = page(for: mouseDownLocation ?? .zero, nearest: false) {
            let point = convert(mouseDownLocation ?? .zero, to: page)
            onCreateTextNote?(page, point)
            return
        }

        if readerTool == .textNote {
            readerTool = .browse
            onCancelTextNote?()
        }

        if readerTool == .browse,
           let location = mouseDownLocation,
           let page = page(for: location, nearest: false) {
            let pagePoint = convert(location, to: page)
            if let annotation = page.annotation(at: pagePoint),
               let owner = noteOwner(for: annotation, on: page) {
                deferredMouseDownEvent = event
                deferredAnnotation = owner
                forwardedDeferredMouseDown = false
                return
            }
        }

        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let deferredMouseDownEvent, deferredAnnotation != nil else {
            super.mouseDragged(with: event)
            return
        }

        let location = convert(event.locationInWindow, from: nil)
        if !forwardedDeferredMouseDown,
           let mouseDownLocation,
           hypot(location.x - mouseDownLocation.x, location.y - mouseDownLocation.y) > 4 {
            forwardedDeferredMouseDown = true
            super.mouseDown(with: deferredMouseDownEvent)
        }
        if forwardedDeferredMouseDown {
            super.mouseDragged(with: event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard readerTool == .browse else {
            clearDeferredAnnotationInteraction()
            return
        }

        if let deferredAnnotation {
            if forwardedDeferredMouseDown {
                super.mouseUp(with: event)
            } else {
                onAnnotationActivated?(deferredAnnotation)
            }
            clearDeferredAnnotationInteraction()
            return
        }

        super.mouseUp(with: event)
        clearDeferredAnnotationInteraction()
    }

    private func clearDeferredAnnotationInteraction() {
        deferredMouseDownEvent = nil
        deferredAnnotation = nil
        forwardedDeferredMouseDown = false
        mouseDownLocation = nil
    }

    private func isNoteAnnotation(_ annotation: PDFAnnotation) -> Bool {
        let type = (annotation.type ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return type.caseInsensitiveCompare("Highlight") == .orderedSame
            || type.caseInsensitiveCompare("Text") == .orderedSame
    }

    private func noteOwner(for annotation: PDFAnnotation, on page: PDFPage) -> PDFAnnotation? {
        if isNoteAnnotation(annotation) {
            return annotation
        }
        let type = (annotation.type ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard type.caseInsensitiveCompare("Popup") == .orderedSame else { return nil }
        return page.annotations.first { candidate in
            isNoteAnnotation(candidate) && candidate.popup === annotation
        }
    }

    override func scrollWheel(with event: NSEvent) {
        onBeginScroll?()
        super.scrollWheel(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if readerTool == .textNote, event.keyCode == 53 {
            readerTool = .browse
            onCancelTextNote?()
            return
        }
        super.keyDown(with: event)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: readerTool == .textNote ? .crosshair : .arrow)
    }
}

private struct NoteReadingPopover: View {
    let note: AnnotationNote
    let preamble: String
    let height: CGFloat
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MathNoteView(
                rawText: note.contents,
                preamble: preamble,
                maximumContentHeight: max(44, height - 62)
            )
                .accessibilityIdentifier("note-rendered-content")
            Divider()
            HStack {
                Text("Page \(note.pageIndex + 1)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Edit", action: onEdit)
                    .keyboardShortcut(.return, modifiers: [])
                    .accessibilityIdentifier("note-edit")
            }
        }
        .padding(12)
        .frame(width: 320, height: height)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Note on page \(note.pageIndex + 1)")
    }
}
