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

    weak var pdfView: PDFView?
    private weak var attachedDocument: PDFDocument?
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

    func attach(_ pdfView: PDFView) {
        if attachedDocument !== pdfView.document {
            cancelSearch()
        }
        self.pdfView = pdfView
        attachedDocument = pdfView.document
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
        guard let pdfView, let page = pdfView.currentPage else { return }
        pdfView.setScaleToFit(page: page, fitWidthOnly: false)
        refresh()
    }

    func fitWidth() {
        guard let pdfView, let page = pdfView.currentPage else { return }
        pdfView.setScaleToFit(page: page, fitWidthOnly: true)
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
        // During document replacement `pdfView.document` may already point at
        // the incoming document. Cancel against the independently tracked
        // source document so its asynchronous find cannot publish stale
        // selections into the new reader state.
        (attachedDocument ?? pdfView?.document)?.cancelFindString()
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
    let annotationRevision: Int
    let navigationRequest: ReaderNavigationRequest?
    let tool: ReaderTool
    let preamble: String
    let proxy: PDFViewProxy
    let noteForAnnotation: (PDFAnnotation) -> AnnotationNote?
    let capabilitiesForAnnotation: (PDFAnnotation) -> AnnotationNoteCapabilities
    let onUpdateNote: (AnnotationNote, String) -> Bool
    let onCommitNoteEdit: (AnnotationNote, String) -> Void
    let onDeleteNote: (AnnotationNote) -> Void
    let onUpdateColor: (AnnotationNote, AnnotationColorChoice, UndoManager?) -> Bool
    let onCancelTextNote: () -> Void
    let onCreateTextNote: (PDFPage, CGPoint) -> AnnotationNote?
    let onAnnotationPresentationChanged: (AnnotationNote.ID, Bool) -> Void
    let enforceRuntimeAnnotationPresentation: () -> Void

    func makeNSView(context: Context) -> ReaderContainerView {
        let view = ReaderContainerView()
        view.configure(
            document: document,
            proxy: proxy,
            noteForAnnotation: noteForAnnotation,
            capabilitiesForAnnotation: capabilitiesForAnnotation,
            onUpdateNote: onUpdateNote,
            onCommitNoteEdit: onCommitNoteEdit,
            onDeleteNote: onDeleteNote,
            onUpdateColor: onUpdateColor,
            onCancelTextNote: onCancelTextNote,
            onCreateTextNote: onCreateTextNote,
            preamble: preamble,
            annotationRevision: annotationRevision,
            onAnnotationPresentationChanged: onAnnotationPresentationChanged,
            enforceRuntimeAnnotationPresentation: enforceRuntimeAnnotationPresentation
        )
        return view
    }

    func updateNSView(_ view: ReaderContainerView, context: Context) {
        view.updateCallbacks(
            noteForAnnotation: noteForAnnotation,
            capabilitiesForAnnotation: capabilitiesForAnnotation,
            onUpdateNote: onUpdateNote,
            onCommitNoteEdit: onCommitNoteEdit,
            onDeleteNote: onDeleteNote,
            onUpdateColor: onUpdateColor,
            onCancelTextNote: onCancelTextNote,
            onCreateTextNote: onCreateTextNote,
            preamble: preamble,
            onAnnotationPresentationChanged: onAnnotationPresentationChanged,
            enforceRuntimeAnnotationPresentation: enforceRuntimeAnnotationPresentation
        )
        view.pdfView.readerTool = tool

        if view.pdfView.document !== document {
            view.setDocument(document)
        }
        view.updateAnnotationRevision(annotationRevision)
        if let navigationRequest {
            view.handle(navigationRequest)
        }
    }
}

private final class ActiveAnnotationPresentation {
    let annotation: PDFAnnotation
    var contents: String
    var color: AnnotationColorChoice?
    var capabilities: AnnotationNoteCapabilities
    var preamble: String

    init(
        annotation: PDFAnnotation,
        contents: String,
        color: AnnotationColorChoice?,
        capabilities: AnnotationNoteCapabilities,
        preamble: String
    ) {
        self.annotation = annotation
        self.contents = contents
        self.color = color
        self.capabilities = capabilities
        self.preamble = preamble
    }
}

final class ReaderContainerView: NSView {
    let pdfView = ReaderPDFView()
    private let annotationOverlay = AnnotationAffordanceOverlayView()

    private weak var proxy: PDFViewProxy?
    private var noteForAnnotation: ((PDFAnnotation) -> AnnotationNote?)?
    private var capabilitiesForAnnotation: ((PDFAnnotation) -> AnnotationNoteCapabilities)?
    private var onUpdateNote: ((AnnotationNote, String) -> Bool)?
    private var onCommitNoteEdit: ((AnnotationNote, String) -> Void)?
    private var onDeleteNote: ((AnnotationNote) -> Void)?
    private var onUpdateColor: ((AnnotationNote, AnnotationColorChoice, UndoManager?) -> Bool)?
    private var onCancelTextNote: (() -> Void)?
    private var onCreateTextNote: ((PDFPage, CGPoint) -> AnnotationNote?)?
    private var onAnnotationPresentationChanged: ((AnnotationNote.ID, Bool) -> Void)?
    private var enforceRuntimeAnnotationPresentation: (() -> Void)?
    private var preamble = ""
    private var lastNavigationToken: UUID?
    private var lastAnnotationRevision: Int?
    private var observations: [NSObjectProtocol] = []
    private var activePresentation: ActiveAnnotationPresentation?
    private var annotationSurface: NSHostingView<AnnotationNoteSurface>?
    private var annotationEditingSession: AnnotationNoteEditingSession?
    private var annotationSurfaceIsEditing = false
    private var preferredSurfaceSize = NSSize(width: 310, height: 210)
    private var lastDocumentVisibleOrigin: NSPoint?
    private var pendingNavigationPresentationToken: UUID?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("PDF reader")
        setAccessibilityIdentifier("pdf-reader")

        pdfView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pdfView)
        annotationOverlay.translatesAutoresizingMaskIntoConstraints = false
        addSubview(annotationOverlay)
        NSLayoutConstraint.activate([
            pdfView.leadingAnchor.constraint(equalTo: leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: trailingAnchor),
            pdfView.topAnchor.constraint(equalTo: topAnchor),
            pdfView.bottomAnchor.constraint(equalTo: bottomAnchor),
            annotationOverlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            annotationOverlay.trailingAnchor.constraint(equalTo: trailingAnchor),
            annotationOverlay.topAnchor.constraint(equalTo: topAnchor),
            annotationOverlay.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        annotationOverlay.pdfView = pdfView
        annotationOverlay.onActivate = { [weak self] annotation in
            self?.presentNote(for: annotation, startsEditing: false)
        }

        pdfView.onAnnotationActivated = { [weak self] annotation in
            self?.presentNote(for: annotation, startsEditing: false)
        }
        pdfView.onCreateTextNote = { [weak self] page, point in
            guard let self, let note = self.onCreateTextNote?(page, point) else { return }
            self.presentNote(for: note.annotation, startsEditing: true)
        }
        pdfView.onCancelTextNote = { [weak self] in self?.onCancelTextNote?() }
        pdfView.onBeginScroll = { [weak self] in self?.dismissAnnotationSurface() }
        pdfView.onBackgroundActivated = { [weak self] in self?.dismissAnnotationSurface() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        observations.forEach(NotificationCenter.default.removeObserver)
    }

    override func layout() {
        super.layout()
        enforceRuntimeAnnotationPresentation?()
        annotationOverlay.refresh()
        layoutAnnotationSurface()
    }

    func configure(
        document: PDFDocument,
        proxy: PDFViewProxy,
        noteForAnnotation: @escaping (PDFAnnotation) -> AnnotationNote?,
        capabilitiesForAnnotation: @escaping (PDFAnnotation) -> AnnotationNoteCapabilities,
        onUpdateNote: @escaping (AnnotationNote, String) -> Bool,
        onCommitNoteEdit: @escaping (AnnotationNote, String) -> Void,
        onDeleteNote: @escaping (AnnotationNote) -> Void,
        onUpdateColor: @escaping (AnnotationNote, AnnotationColorChoice, UndoManager?) -> Bool,
        onCancelTextNote: @escaping () -> Void,
        onCreateTextNote: @escaping (PDFPage, CGPoint) -> AnnotationNote?,
        preamble: String,
        annotationRevision: Int,
        onAnnotationPresentationChanged: @escaping (AnnotationNote.ID, Bool) -> Void = { _, _ in },
        enforceRuntimeAnnotationPresentation: @escaping () -> Void = {}
    ) {
        self.proxy = proxy
        updateCallbacks(
            noteForAnnotation: noteForAnnotation,
            capabilitiesForAnnotation: capabilitiesForAnnotation,
            onUpdateNote: onUpdateNote,
            onCommitNoteEdit: onCommitNoteEdit,
            onDeleteNote: onDeleteNote,
            onUpdateColor: onUpdateColor,
            onCancelTextNote: onCancelTextNote,
            onCreateTextNote: onCreateTextNote,
            preamble: preamble,
            onAnnotationPresentationChanged: onAnnotationPresentationChanged,
            enforceRuntimeAnnotationPresentation: enforceRuntimeAnnotationPresentation
        )

        pdfView.displayMode = .singlePageContinuous
        pdfView.displaysPageBreaks = true
        pdfView.pageShadowsEnabled = true
        pdfView.autoScales = true
        pdfView.backgroundColor = .underPageBackgroundColor
        setDocument(document)
        lastAnnotationRevision = annotationRevision
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
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.enforceRuntimeAnnotationPresentation?()
                    self.proxy?.refresh()
                    if (name == .PDFViewPageChanged || name == .PDFViewScaleChanged),
                       self.pendingNavigationPresentationToken == nil {
                        self.dismissAnnotationSurface()
                    } else {
                        self.annotationOverlay.refresh()
                        self.layoutAnnotationSurface()
                    }
                }
            }
        }

        if let clipView = pdfView.documentView?.enclosingScrollView?.contentView {
            clipView.postsBoundsChangedNotifications = true
            lastDocumentVisibleOrigin = clipView.bounds.origin
            observations.append(
                NotificationCenter.default.addObserver(
                    forName: NSView.boundsDidChangeNotification,
                    object: clipView,
                    queue: .main
                ) { [weak self, weak clipView] _ in
                    guard let self, let clipView else { return }
                    self.enforceRuntimeAnnotationPresentation?()
                    let origin = clipView.bounds.origin
                    let didScroll = self.lastDocumentVisibleOrigin.map {
                        hypot(origin.x - $0.x, origin.y - $0.y) > 0.5
                    } ?? false
                    self.lastDocumentVisibleOrigin = origin
                    if didScroll, self.pendingNavigationPresentationToken == nil {
                        self.dismissAnnotationSurface()
                    } else {
                        self.annotationOverlay.refresh()
                        self.layoutAnnotationSurface()
                    }
                }
            )
        }
    }

    func updateCallbacks(
        noteForAnnotation: @escaping (PDFAnnotation) -> AnnotationNote?,
        capabilitiesForAnnotation: @escaping (PDFAnnotation) -> AnnotationNoteCapabilities,
        onUpdateNote: @escaping (AnnotationNote, String) -> Bool,
        onCommitNoteEdit: @escaping (AnnotationNote, String) -> Void,
        onDeleteNote: @escaping (AnnotationNote) -> Void,
        onUpdateColor: @escaping (AnnotationNote, AnnotationColorChoice, UndoManager?) -> Bool,
        onCancelTextNote: @escaping () -> Void,
        onCreateTextNote: @escaping (PDFPage, CGPoint) -> AnnotationNote?,
        preamble: String,
        onAnnotationPresentationChanged: @escaping (AnnotationNote.ID, Bool) -> Void,
        enforceRuntimeAnnotationPresentation: @escaping () -> Void
    ) {
        let preambleChanged = self.preamble != preamble
        self.noteForAnnotation = noteForAnnotation
        self.capabilitiesForAnnotation = capabilitiesForAnnotation
        self.onUpdateNote = onUpdateNote
        self.onCommitNoteEdit = onCommitNoteEdit
        self.onDeleteNote = onDeleteNote
        self.onUpdateColor = onUpdateColor
        self.onCancelTextNote = onCancelTextNote
        self.onCreateTextNote = onCreateTextNote
        self.onAnnotationPresentationChanged = onAnnotationPresentationChanged
        self.enforceRuntimeAnnotationPresentation = enforceRuntimeAnnotationPresentation
        self.preamble = preamble
        annotationOverlay.refresh()
        if preambleChanged {
            reconcileActivePresentation()
        }
    }

    func setDocument(_ document: PDFDocument) {
        enforceRuntimeAnnotationPresentation?()
        dismissAnnotationSurface()
        pdfView.cancelPendingAnnotationInteraction()
        pendingNavigationPresentationToken = nil
        lastAnnotationRevision = nil
        lastDocumentVisibleOrigin = nil
        pdfView.document = document
        enforceRuntimeAnnotationPresentation?()
        proxy?.attach(pdfView)
        annotationOverlay.refresh()
    }

    func updateAnnotationRevision(_ revision: Int) {
        guard lastAnnotationRevision != revision else { return }
        enforceRuntimeAnnotationPresentation?()
        lastAnnotationRevision = revision
        annotationOverlay.refresh()
        reconcileActivePresentation()
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
        if request.opensNote {
            dismissAnnotationSurface()
            pendingNavigationPresentationToken = request.token
        } else {
            pendingNavigationPresentationToken = nil
        }
        pdfView.reveal(pageRect, on: page, padding: 24)
        assert(pdfView.scaleFactor == originalScale)

        if request.opensNote, let annotation = request.annotation {
            DispatchQueue.main.async { [weak self] in
                guard
                    let self,
                    self.lastNavigationToken == request.token,
                    self.pendingNavigationPresentationToken == request.token
                else { return }
                self.presentNote(for: annotation, startsEditing: request.startsEditing)
                // PDFKit can emit page and clip-view changes for several run-loop
                // turns after `reveal`. Keep those navigation-generated events
                // from dismissing the surface we just opened. A real user scroll
                // after this short settling interval still dismisses immediately.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard self?.pendingNavigationPresentationToken == request.token else { return }
                    self?.pendingNavigationPresentationToken = nil
                }
            }
        } else {
            pendingNavigationPresentationToken = nil
        }
        proxy?.refresh()
    }

    private func presentNote(for annotation: PDFAnnotation, startsEditing: Bool) {
        guard
            let note = noteForAnnotation?(annotation),
            let capabilities = capabilitiesForAnnotation?(annotation),
            annotation.page != nil
        else { return }

        dismissAnnotationSurface()
        let selectedColor = AnnotationColorChoice.matching(annotation.color)
        let presentation = ActiveAnnotationPresentation(
            annotation: annotation,
            contents: note.contents,
            color: selectedColor,
            capabilities: capabilities,
            preamble: preamble
        )
        activePresentation = presentation
        annotationSurfaceIsEditing = AnnotationSurfaceEditingPolicy.startsEditing(
            noteContents: note.contents,
            canEditContents: capabilities.canEditContents,
            requested: startsEditing
        )
        preferredSurfaceSize = preferredSize(
            for: note.contents,
            editing: annotationSurfaceIsEditing
        )

        let editingSession = AnnotationNoteEditingSession(
            contents: note.contents,
            color: annotation.color,
            startsEditing: annotationSurfaceIsEditing,
            onLiveUpdate: { [weak self, weak presentation] contents in
                guard let self, let presentation else { return false }
                let previousContents = presentation.contents
                presentation.contents = contents
                guard self.onUpdateNote?(note, contents) == true else {
                    presentation.contents = previousContents
                    return false
                }
                self.annotationOverlay.refresh()
                return true
            },
            onCommit: { [weak self] originalContents in
                self?.onCommitNoteEdit?(note, originalContents)
            },
            onEditingChanged: { [weak self] isEditing in
                guard let self else { return }
                self.annotationSurfaceIsEditing = isEditing
                self.preferredSurfaceSize = self.preferredSize(
                    for: self.annotationEditingSession?.draft ?? note.contents,
                    editing: isEditing
                )
                self.layoutAnnotationSurface()
                if !isEditing {
                    DispatchQueue.main.async { [weak self] in
                        self?.reconcileActivePresentation()
                    }
                }
            }
        )
        annotationEditingSession = editingSession

        let rootView = AnnotationNoteSurface(
            note: note,
            preamble: preamble,
            capabilities: capabilities,
            editingSession: editingSession,
            onDelete: { [weak self] in
                guard let self else { return }
                guard capabilities.canDelete else { return }
                self.dismissAnnotationSurface(commitEditing: false)
                self.onDeleteNote?(note)
                self.annotationOverlay.refresh()
            },
            onColorChange: { [weak self] color in
                guard let self, capabilities.canChangeColor else { return false }
                guard self.onUpdateColor?(note, color, self.window?.undoManager) == true else {
                    return false
                }
                presentation.color = color
                self.annotationEditingSession?.acceptColorChange(color)
                self.annotationOverlay.refresh()
                return true
            },
            onClose: { [weak self] in self?.dismissAnnotationSurface() },
            onReveal: { [weak self] in self?.revealActiveAnnotation() }
        )

        let surface = NSHostingView(rootView: rootView)
        // The surface is frame-managed by the PDF container. Letting the
        // hosting view advertise SwiftUI-derived intrinsic sizes makes AppKit
        // re-enter the entire window's constraint graph while the surface is
        // being inserted (including toolbar segmented controls), which can
        // spin indefinitely on annotation activation.
        surface.sizingOptions = []
        surface.translatesAutoresizingMaskIntoConstraints = true
        surface.autoresizingMask = []
        annotationSurface = surface
        addSubview(surface, positioned: .above, relativeTo: annotationOverlay)
        layoutAnnotationSurface()
        annotationOverlay.activeAnnotation = annotation
        annotationOverlay.refresh()
        onAnnotationPresentationChanged?(note.id, true)
    }

    private func dismissAnnotationSurface(commitEditing: Bool = true) {
        let dismissedNoteID = activePresentation.flatMap { presentation in
            noteForAnnotation?(presentation.annotation)?.id
        }
        if commitEditing {
            annotationEditingSession?.commitIfNeeded()
        }
        annotationSurface?.removeFromSuperview()
        annotationSurface = nil
        annotationEditingSession = nil
        activePresentation = nil
        annotationSurfaceIsEditing = false
        annotationOverlay.activeAnnotation = nil
        annotationOverlay.surfaceFrame = nil
        annotationOverlay.refresh()
        if let dismissedNoteID {
            onAnnotationPresentationChanged?(dismissedNoteID, false)
        }
    }

    private func revealActiveAnnotation() {
        guard
            let annotation = activePresentation?.annotation,
            let page = annotation.page
        else { return }
        let originalScale = pdfView.scaleFactor
        pdfView.reveal(annotation.bounds, on: page, padding: 28)
        assert(pdfView.scaleFactor == originalScale)
        layoutAnnotationSurface()
    }

    private func reconcileActivePresentation() {
        guard let presentation = activePresentation else { return }
        let annotation = presentation.annotation
        guard
            annotation.page != nil,
            let refreshedNote = noteForAnnotation?(annotation),
            let refreshedCapabilities = capabilitiesForAnnotation?(annotation)
        else {
            dismissAnnotationSurface(commitEditing: false)
            return
        }

        if annotationSurfaceIsEditing, !refreshedCapabilities.canEditContents {
            dismissAnnotationSurface(commitEditing: false)
            return
        }

        let refreshedColor = AnnotationColorChoice.matching(annotation.color)
        let needsRefresh = presentation.contents != refreshedNote.contents
            || presentation.color != refreshedColor
            || presentation.capabilities != refreshedCapabilities
            || presentation.preamble != preamble

        guard needsRefresh else { return }

        annotationEditingSession?.reconcileDocumentState(
            contents: refreshedNote.contents,
            color: annotation.color
        )
        presentation.contents = refreshedNote.contents
        presentation.color = refreshedColor
        preferredSurfaceSize = preferredSize(
            for: refreshedNote.contents,
            editing: annotationSurfaceIsEditing
        )

        let requiresSurfaceRebuild = presentation.capabilities != refreshedCapabilities
            || presentation.preamble != preamble
        presentation.capabilities = refreshedCapabilities
        presentation.preamble = preamble

        if requiresSurfaceRebuild, !annotationSurfaceIsEditing {
            presentNote(for: annotation, startsEditing: false)
        } else {
            layoutAnnotationSurface()
            annotationOverlay.refresh()
        }
    }

    private func preferredSize(for contents: String, editing: Bool) -> NSSize {
        let explicitLines = contents.split(separator: "\n", omittingEmptySubsequences: false).count
        let wrappedLines = max(explicitLines, Int(ceil(Double(max(contents.count, 1)) / 44)))
        let hasDisplayMath = contents.contains("\\[") || contents.contains("$$")
        let width: CGFloat = hasDisplayMath || contents.count > 280 ? 360 : 310
        let readingHeight = min(max(154, CGFloat(wrappedLines * 21 + 94)), 390)
        return NSSize(width: width, height: editing ? max(readingHeight, 190) : readingHeight)
    }

    private func layoutAnnotationSurface() {
        guard
            let surface = annotationSurface,
            let annotation = activePresentation?.annotation,
            let page = annotation.page,
            bounds.width > 120,
            bounds.height > 120
        else { return }

        let safeBounds = bounds.insetBy(dx: 14, dy: 14)
        guard safeBounds.width >= 180, safeBounds.height >= 120 else {
            dismissAnnotationSurface()
            return
        }
        let size = NSSize(
            width: min(preferredSurfaceSize.width, safeBounds.width),
            height: min(preferredSurfaceSize.height, safeBounds.height)
        )
        let annotationFrame = annotationOverlay.convert(
            pdfView.convert(annotation.bounds, from: page),
            from: pdfView
        )
        guard annotationFrame.intersects(safeBounds) else {
            dismissAnnotationSurface()
            return
        }
        let anchor: NSRect
        if let affordanceFrame = annotationOverlay.affordanceFrame(for: annotation) {
            anchor = affordanceFrame
        } else {
            anchor = annotationFrame
        }
        let gap: CGFloat = 14
        let candidates = [
            NSRect(x: anchor.midX - size.width / 2, y: anchor.minY - gap - size.height, width: size.width, height: size.height),
            NSRect(x: anchor.midX - size.width / 2, y: anchor.maxY + gap, width: size.width, height: size.height),
            NSRect(x: anchor.maxX + gap, y: anchor.midY - size.height / 2, width: size.width, height: size.height),
            NSRect(x: anchor.minX - gap - size.width, y: anchor.midY - size.height / 2, width: size.width, height: size.height),
        ]

        let protectedAnnotationFrame = annotationFrame.insetBy(dx: -10, dy: -10)
        let frame = candidates.first(where: {
            safeBounds.contains($0) && !$0.intersects(protectedAnnotationFrame)
        })
            ?? candidates.first(where: { safeBounds.contains($0) })
            ?? clampedFrame(bestCandidate(from: candidates, in: safeBounds), inside: safeBounds)
        surface.frame = frame
        annotationOverlay.activeAnnotation = annotation
        annotationOverlay.surfaceFrame = frame
        annotationOverlay.refresh()
    }

    private func bestCandidate(from candidates: [NSRect], in safeBounds: NSRect) -> NSRect {
        candidates.max { lhs, rhs in
            visibleArea(of: lhs, in: safeBounds) < visibleArea(of: rhs, in: safeBounds)
        } ?? NSRect(origin: safeBounds.origin, size: preferredSurfaceSize)
    }

    private func visibleArea(of rect: NSRect, in bounds: NSRect) -> CGFloat {
        let intersection = rect.intersection(bounds)
        guard !intersection.isNull else { return 0 }
        return intersection.width * intersection.height
    }

    private func clampedFrame(_ rect: NSRect, inside bounds: NSRect) -> NSRect {
        let width = min(rect.width, bounds.width)
        let height = min(rect.height, bounds.height)
        return NSRect(
            x: min(max(rect.minX, bounds.minX), bounds.maxX - width),
            y: min(max(rect.minY, bounds.minY), bounds.maxY - height),
            width: width,
            height: height
        )
    }
}

enum AnnotationSurfaceEditingPolicy {
    static func startsEditing(
        noteContents: String,
        canEditContents: Bool,
        requested: Bool
    ) -> Bool {
        // Contents are deliberately not a trigger. An imported empty note or
        // bare highlight is still something the user opened while reading.
        // Only New Note or an explicit Edit/Add Note action requests focus.
        _ = noteContents
        return canEditContents && requested
    }
}

extension PDFView {
    fileprivate func setScaleToFit(page: PDFPage, fitWidthOnly: Bool) {
        let pageBounds = page.bounds(for: displayBox)
        guard pageBounds.width > 0, pageBounds.height > 0 else { return }
        let quarterTurns = ((page.rotation % 360) + 360) % 360
        let swapsAxes = quarterTurns == 90 || quarterTurns == 270
        let pageSize = swapsAxes
            ? CGSize(width: pageBounds.height, height: pageBounds.width)
            : pageBounds.size
        let viewport = bounds.insetBy(dx: 18, dy: 18).size
        guard viewport.width > 0, viewport.height > 0 else { return }
        let widthScale = viewport.width / pageSize.width
        let heightScale = viewport.height / pageSize.height
        let target = fitWidthOnly ? widthScale : min(widthScale, heightScale)
        autoScales = false
        scaleFactor = min(max(target, minScaleFactor), maxScaleFactor)
    }

    func reveal(_ pageRect: CGRect, on page: PDFPage, padding: CGFloat) {
        guard let documentView else {
            go(to: pageRect, on: page)
            return
        }

        let rectInPDFView = convert(pageRect, from: page)
        let rectInDocumentView = documentView.convert(rectInPDFView, from: self)
        let comfortablyVisible = documentView.visibleRect.insetBy(dx: padding, dy: padding)
        guard !comfortablyVisible.contains(rectInDocumentView) else { return }

        // PDFKit records rect destinations in its Back/Forward history even
        // when the destination is elsewhere on the current tall page. A raw
        // document-view scroll does not, which made same-page sidebar jumps
        // impossible to undo with Back.
        let originalScale = scaleFactor
        go(to: pageRect.insetBy(dx: -padding, dy: -padding), on: page)
        if scaleFactor != originalScale {
            scaleFactor = originalScale
        }
        let updatedVisibleRect = documentView.visibleRect.insetBy(dx: padding, dy: padding)
        if !updatedVisibleRect.contains(rectInDocumentView) {
            documentView.scrollToVisible(rectInDocumentView.insetBy(dx: -padding, dy: -padding))
        }
    }
}

enum AnnotationActivationGesturePolicy {
    private static let selectionModifiers: NSEvent.ModifierFlags = [
        .shift, .control, .option, .command,
    ]

    static func interceptsForNoteActivation(
        clickCount: Int,
        modifierFlags: NSEvent.ModifierFlags
    ) -> Bool {
        clickCount == 1 && modifierFlags.intersection(selectionModifiers).isEmpty
    }
}

final class ReaderPDFView: PDFView {
    var readerTool: ReaderTool = .browse {
        didSet {
            guard oldValue != readerTool else { return }
            clearDeferredAnnotationInteraction()
            window?.invalidateCursorRects(for: self)
        }
    }
    var onAnnotationActivated: ((PDFAnnotation) -> Void)?
    var onCreateTextNote: ((PDFPage, CGPoint) -> Void)?
    var onCancelTextNote: (() -> Void)?
    var onBeginScroll: (() -> Void)?
    var onBackgroundActivated: (() -> Void)?

    private var mouseDownLocation: CGPoint?
    private var deferredMouseDownEvent: NSEvent?
    private var deferredMouseUpEvent: NSEvent?
    private var deferredAnnotation: PDFAnnotation?
    private var forwardedDeferredMouseDown = false
    private var pendingSingleClickWorkItem: DispatchWorkItem?
    private var windowResignObserver: NSObjectProtocol?

    deinit {
        if let windowResignObserver {
            NotificationCenter.default.removeObserver(windowResignObserver)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let windowResignObserver {
            NotificationCenter.default.removeObserver(windowResignObserver)
        }
        windowResignObserver = window.map { window in
            NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.clearDeferredAnnotationInteraction()
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        if pendingSingleClickWorkItem != nil {
            if event.clickCount > 1 {
                replayDeferredClickToPDFKit()
                clearDeferredAnnotationInteraction()
                super.mouseDown(with: event)
                return
            }
            clearDeferredAnnotationInteraction()
        }

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

        var noteOwnerAtLocation: PDFAnnotation?
        if readerTool == .browse,
           let location = mouseDownLocation,
           let page = page(for: location, nearest: false) {
            let pagePoint = convert(location, to: page)
            if let annotation = page.annotation(at: pagePoint),
               let owner = noteOwner(for: annotation, on: page),
               annotationActivationContains(pagePoint, owner: owner) {
                noteOwnerAtLocation = owner
            }
        }

        if let noteOwnerAtLocation,
           AnnotationActivationGesturePolicy.interceptsForNoteActivation(
               clickCount: event.clickCount,
               modifierFlags: event.modifierFlags
           ) {
                deferredMouseDownEvent = event
                deferredAnnotation = noteOwnerAtLocation
                forwardedDeferredMouseDown = false
                return
        }

        if readerTool == .browse, noteOwnerAtLocation == nil {
            onBackgroundActivated?()
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
                clearDeferredAnnotationInteraction()
            } else {
                deferredMouseUpEvent = event
                let workItem = DispatchWorkItem { [weak self, weak deferredAnnotation] in
                    guard
                        let self,
                        let deferredAnnotation,
                        self.deferredAnnotation === deferredAnnotation
                    else { return }
                    self.onAnnotationActivated?(deferredAnnotation)
                    self.clearDeferredAnnotationInteraction()
                }
                pendingSingleClickWorkItem = workItem
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + NSEvent.doubleClickInterval,
                    execute: workItem
                )
            }
            return
        }

        super.mouseUp(with: event)
        clearDeferredAnnotationInteraction()
    }

    private func clearDeferredAnnotationInteraction() {
        pendingSingleClickWorkItem?.cancel()
        pendingSingleClickWorkItem = nil
        deferredMouseDownEvent = nil
        deferredMouseUpEvent = nil
        deferredAnnotation = nil
        forwardedDeferredMouseDown = false
        mouseDownLocation = nil
    }

    func cancelPendingAnnotationInteraction() {
        clearDeferredAnnotationInteraction()
    }

    private func replayDeferredClickToPDFKit() {
        guard let deferredMouseDownEvent else { return }
        super.mouseDown(with: deferredMouseDownEvent)
        if let deferredMouseUpEvent {
            super.mouseUp(with: deferredMouseUpEvent)
        }
    }

    private func isNoteAnnotation(_ annotation: PDFAnnotation) -> Bool {
        let type = (annotation.type ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return type.caseInsensitiveCompare("Highlight") == .orderedSame
            || type.caseInsensitiveCompare("Text") == .orderedSame
    }

    private func noteOwner(for annotation: PDFAnnotation, on _: PDFPage) -> PDFAnnotation? {
        // Popup companions are persistence-only. Treating one as an
        // interactive runtime target would reintroduce the duplicate native
        // affordance model that the overlay replaces.
        isNoteAnnotation(annotation) ? annotation : nil
    }

    private func annotationActivationContains(_ pagePoint: CGPoint, owner: PDFAnnotation) -> Bool {
        guard owner.type?.caseInsensitiveCompare("Highlight") == .orderedSame else {
            return owner.bounds.insetBy(dx: -2, dy: -2).contains(pagePoint)
        }
        guard let points = owner.quadrilateralPoints, points.count >= 4 else {
            return owner.bounds.insetBy(dx: -2, dy: -2).contains(pagePoint)
        }

        var index = 0
        while index + 3 < points.count {
            let quad = points[index..<(index + 4)].map(\.pointValue)
            if let first = quad.first {
                let relativeBounds = quad.dropFirst().reduce(
                    CGRect(origin: first, size: .zero)
                ) { bounds, point in
                    bounds.union(CGRect(origin: point, size: .zero))
                }
                let pageBounds = relativeBounds.offsetBy(
                    dx: owner.bounds.minX,
                    dy: owner.bounds.minY
                )
                if pageBounds.insetBy(dx: -2, dy: -2).contains(pagePoint) {
                    return true
                }
            }
            index += 4
        }
        return false
    }

    override func scrollWheel(with event: NSEvent) {
        clearDeferredAnnotationInteraction()
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

final class AnnotationAffordanceOverlayView: NSView {
    weak var pdfView: ReaderPDFView?
    var onActivate: ((PDFAnnotation) -> Void)?
    var activeAnnotation: PDFAnnotation?
    var surfaceFrame: NSRect?

    private var buttons: [ObjectIdentifier: AnnotationBadgeButton] = [:]
    private var anchorPoints: [ObjectIdentifier: CGPoint] = [:]

    private struct BadgeGroup {
        let primary: PDFAnnotation
        var annotations: [PDFAnnotation]
        let frame: NSRect
    }

    override var isFlipped: Bool { pdfView?.isFlipped ?? super.isFlipped }
    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        for (identifier, button) in buttons {
            guard let anchor = anchorPoints[identifier] else { continue }
            let center = CGPoint(x: button.frame.midX, y: button.frame.midY)
            guard hypot(center.x - anchor.x, center.y - anchor.y) > 18 else { continue }
            let path = NSBezierPath()
            path.move(to: anchor)
            path.line(to: center)
            button.annotationColor.withAlphaComponent(0.48).setStroke()
            path.lineCapStyle = .round
            path.lineWidth = 1.25
            path.stroke()
        }

        guard
            let surfaceFrame,
            let activeAnnotation,
            let button = buttons.values.first(where: { candidate in
                candidate.annotations.contains(where: { $0 === activeAnnotation })
            })
        else { return }

        let start = CGPoint(x: button.frame.midX, y: button.frame.midY)
        let end = closestPoint(on: surfaceFrame, to: start)
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)
        activeAnnotation.color.withAlphaComponent(0.68).setStroke()
        path.lineCapStyle = .round
        path.lineWidth = 1.5
        path.stroke()
    }

    func refresh() {
        guard let pdfView, let document = pdfView.document else {
            buttons.values.forEach { $0.removeFromSuperview() }
            buttons.removeAll()
            anchorPoints.removeAll()
            needsDisplay = true
            return
        }

        var visible: [ObjectIdentifier: BadgeGroup] = [:]
        var occupiedFrames: [NSRect] = []
        for page in visiblePages(in: document, pdfView: pdfView) {
            let annotations = page.annotations
                .filter(isCommentedHighlight)
                .sorted {
                    markerFrame(for: $0, on: page, in: pdfView).minY
                        < markerFrame(for: $1, on: page, in: pdfView).minY
                }
            for annotation in annotations {
                let desiredFrame = markerFrame(for: annotation, on: page, in: pdfView)
                if let markerFrame = collisionAdjustedFrame(
                    desiredFrame,
                    avoiding: occupiedFrames,
                    inside: bounds.insetBy(dx: 4, dy: 4)
                ) {
                    guard markerFrame.intersects(bounds.insetBy(dx: -20, dy: -20)) else { continue }
                    let identifier = ObjectIdentifier(annotation)
                    visible[identifier] = BadgeGroup(
                        primary: annotation,
                        annotations: [annotation],
                        frame: markerFrame
                    )
                    anchorPoints[identifier] = annotationAnchor(for: annotation, on: page, in: pdfView)
                    occupiedFrames.append(markerFrame)
                } else if let nearestIdentifier = visible.min(by: { lhs, rhs in
                    distance(from: lhs.value.frame, to: desiredFrame)
                        < distance(from: rhs.value.frame, to: desiredFrame)
                })?.key {
                    visible[nearestIdentifier]?.annotations.append(annotation)
                }
            }
        }

        let staleIdentifiers = buttons.keys.filter { visible[$0] == nil }
        for identifier in staleIdentifiers {
            buttons.removeValue(forKey: identifier)?.removeFromSuperview()
            anchorPoints.removeValue(forKey: identifier)
        }

        for (identifier, payload) in visible {
            let button: AnnotationBadgeButton
            if let existing = buttons[identifier] {
                button = existing
            } else {
                button = AnnotationBadgeButton(frame: payload.frame)
                button.target = self
                button.action = #selector(activateBadge(_:))
                addSubview(button)
                buttons[identifier] = button
            }
            button.annotations = payload.annotations
            button.annotationColor = payload.primary.color
            button.isSelectedAnnotation = payload.annotations.contains(where: { $0 === activeAnnotation })
            button.frame = payload.frame
            button.toolTip = payload.annotations.count == 1
                ? "Open Attached Comment"
                : "Choose from \(payload.annotations.count) nearby comments"
            button.setAccessibilityLabel(accessibilityLabel(for: payload.annotations))
        }
        needsDisplay = true
    }

    func affordanceFrame(for annotation: PDFAnnotation) -> NSRect? {
        buttons.values.first(where: { button in
            button.annotations.contains(where: { $0 === annotation })
        })?.frame
    }

    @objc private func activateBadge(_ sender: AnnotationBadgeButton) {
        guard let annotation = sender.annotations.first else { return }
        guard sender.annotations.count > 1 else {
            onActivate?(annotation)
            return
        }

        let menu = NSMenu(title: "Nearby Comments")
        menu.autoenablesItems = false
        for annotation in sender.annotations {
            let item = NSMenuItem(
                title: menuTitle(for: annotation),
                action: #selector(activateStackedAnnotation(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = annotation
            menu.addItem(item)
        }
        menu.popUp(
            positioning: nil,
            at: CGPoint(x: sender.bounds.minX, y: sender.bounds.maxY),
            in: sender
        )
    }

    @objc private func activateStackedAnnotation(_ sender: NSMenuItem) {
        guard let annotation = sender.representedObject as? PDFAnnotation else { return }
        onActivate?(annotation)
    }

    private func markerFrame(
        for annotation: PDFAnnotation,
        on page: PDFPage,
        in pdfView: PDFView
    ) -> NSRect {
        let targetBounds = finalQuadBounds(for: annotation)
        let highlightRect = pdfView.convert(targetBounds, from: page)
        let pageRect = pdfView.convert(page.bounds(for: .cropBox), from: page)
        let preferredX = highlightRect.maxX + 8
        let outsidePageX = pageRect.maxX + 12
        let centerX: CGFloat
        if preferredX <= pageRect.maxX - 14 {
            centerX = preferredX
        } else if outsidePageX <= pdfView.bounds.maxX - 14 {
            centerX = outsidePageX
        } else {
            centerX = pageRect.maxX - 14
        }
        let center = CGPoint(
            x: centerX,
            y: min(max(highlightRect.midY, pageRect.minY + 14), pageRect.maxY - 14)
        )
        let centerInOverlay = convert(center, from: pdfView)
        return NSRect(x: centerInOverlay.x - 14, y: centerInOverlay.y - 14, width: 28, height: 28)
    }

    private func annotationAnchor(
        for annotation: PDFAnnotation,
        on page: PDFPage,
        in pdfView: PDFView
    ) -> CGPoint {
        let highlightRect = pdfView.convert(finalQuadBounds(for: annotation), from: page)
        return convert(CGPoint(x: highlightRect.maxX, y: highlightRect.midY), from: pdfView)
    }

    private func collisionAdjustedFrame(
        _ desired: NSRect,
        avoiding occupied: [NSRect],
        inside limits: NSRect
    ) -> NSRect? {
        let verticalSteps = max(1, Int(ceil(limits.height / 30)))
        let horizontalSteps = max(1, min(4, Int(ceil(limits.width / 30))))
        var offsets: [CGPoint] = [.zero]
        for radius in 1...max(verticalSteps, horizontalSteps) {
            if radius <= verticalSteps {
                offsets.append(CGPoint(x: 0, y: CGFloat(-30 * radius)))
                offsets.append(CGPoint(x: 0, y: CGFloat(30 * radius)))
            }
            if radius <= horizontalSteps {
                for verticalRadius in 0...min(radius, verticalSteps) {
                    let y = CGFloat(30 * verticalRadius)
                    for xSign: CGFloat in [1, -1] {
                        offsets.append(CGPoint(x: CGFloat(30 * radius) * xSign, y: y))
                        if y > 0 {
                            offsets.append(CGPoint(x: CGFloat(30 * radius) * xSign, y: -y))
                        }
                    }
                }
            }
        }
        for offset in offsets {
            let candidate = desired.offsetBy(dx: offset.x, dy: offset.y)
            if limits.contains(candidate), !occupied.contains(where: { $0.intersects(candidate) }) {
                return candidate
            }
        }
        return nil
    }

    private func distance(from lhs: NSRect, to rhs: NSRect) -> CGFloat {
        hypot(lhs.midX - rhs.midX, lhs.midY - rhs.midY)
    }

    private func visiblePages(in document: PDFDocument, pdfView: PDFView) -> [PDFPage] {
        let visiblePages = pdfView.visiblePages
        if !visiblePages.isEmpty { return visiblePages }
        if let currentPage = pdfView.currentPage { return [currentPage] }
        if let firstPage = document.page(at: 0) { return [firstPage] }
        return []
    }

    private func finalQuadBounds(for annotation: PDFAnnotation) -> CGRect {
        guard let points = annotation.quadrilateralPoints, points.count >= 4 else {
            return annotation.bounds
        }
        let last = points.suffix(4).map(\.pointValue)
        guard let first = last.first else { return annotation.bounds }
        let relativeBounds = last.dropFirst().reduce(CGRect(origin: first, size: .zero)) { bounds, point in
            bounds.union(CGRect(origin: point, size: .zero))
        }
        return relativeBounds.offsetBy(dx: annotation.bounds.minX, dy: annotation.bounds.minY)
    }

    private func isCommentedHighlight(_ annotation: PDFAnnotation) -> Bool {
        guard annotation.type == "Highlight" else { return false }
        return !(annotation.contents ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func pageNumber(for annotation: PDFAnnotation) -> Int {
        guard
            let page = annotation.page,
            let document = pdfView?.document
        else { return 1 }
        return max(1, document.index(for: page) + 1)
    }

    private func accessibilityLabel(for annotations: [PDFAnnotation]) -> String {
        guard let annotation = annotations.first else { return "Comment" }
        if annotations.count > 1 {
            return "\(annotations.count) nearby comments, page \(pageNumber(for: annotation))"
        }
        let preview = (annotation.contents ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        let clipped = preview.count > 72 ? String(preview.prefix(69)) + "…" : preview
        if clipped.isEmpty {
            return "Comment on highlight, page \(pageNumber(for: annotation))"
        }
        return "Comment on highlight, page \(pageNumber(for: annotation)): \(clipped)"
    }

    private func menuTitle(for annotation: PDFAnnotation) -> String {
        let preview = (annotation.contents ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        let clipped = preview.isEmpty ? "Comment" : String(preview.prefix(54))
        return "Page \(pageNumber(for: annotation)): \(clipped)"
    }

    private func closestPoint(on rect: NSRect, to point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, rect.minX), rect.maxX),
            y: min(max(point.y, rect.minY), rect.maxY)
        )
    }
}

final class AnnotationBadgeButton: NSButton {
    var annotations: [PDFAnnotation] = [] { didSet { needsDisplay = true } }
    var annotationColor: NSColor = .systemYellow { didSet { needsDisplay = true } }
    var isSelectedAnnotation = false { didSet { needsDisplay = true } }

    private var isHovered = false { didSet { needsDisplay = true } }
    private var trackingAreaReference: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        title = ""
        focusRingType = .exterior
        setButtonType(.momentaryChange)
        setAccessibilityRole(.button)
        toolTip = "Open Attached Comment"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        let badgeRect = NSRect(x: 5, y: 8, width: 18, height: 14)
        let badge = NSBezierPath(roundedRect: badgeRect, xRadius: 5, yRadius: 5)
        let fillColor = annotationColor.blended(
            withFraction: isHovered ? 0.09 : 0,
            of: .labelColor
        ) ?? annotationColor
        fillColor.withAlphaComponent(0.96).setFill()
        badge.fill()

        NSColor.separatorColor.withAlphaComponent(0.76).setStroke()
        badge.lineWidth = 0.75
        badge.stroke()

        let tail = NSBezierPath()
        tail.move(to: CGPoint(x: badgeRect.minX + 4, y: badgeRect.minY + 1.5))
        tail.line(to: CGPoint(x: badgeRect.minX + 2, y: badgeRect.minY - 3))
        tail.line(to: CGPoint(x: badgeRect.minX + 8, y: badgeRect.minY + 1))
        tail.close()
        fillColor.withAlphaComponent(0.96).setFill()
        tail.fill()
        NSColor.separatorColor.withAlphaComponent(0.68).setStroke()
        tail.lineWidth = 0.65
        tail.stroke()

        if isSelectedAnnotation {
            let selectionRing = NSBezierPath(
                roundedRect: badgeRect.insetBy(dx: -2.5, dy: -2.5),
                xRadius: 6.5,
                yRadius: 6.5
            )
            NSColor.labelColor.withAlphaComponent(0.58).setStroke()
            selectionRing.lineWidth = 1.5
            selectionRing.stroke()
        }

        let glyphColor = NSColor.black.withAlphaComponent(isHovered ? 0.82 : 0.68)
        if annotations.count > 1 {
            let count = annotations.count > 99 ? "99+" : String(annotations.count)
            let attributed = NSAttributedString(
                string: count,
                attributes: [
                    .font: NSFont.systemFont(ofSize: annotations.count > 9 ? 8 : 9, weight: .semibold),
                    .foregroundColor: glyphColor,
                ]
            )
            attributed.draw(
                in: NSRect(x: badgeRect.minX, y: badgeRect.minY + 3, width: badgeRect.width, height: 12)
            )
            return
        }

        glyphColor.setFill()
        for x in [10.5, 14, 17.5] {
            NSBezierPath(ovalIn: NSRect(x: x, y: 14, width: 1.7, height: 1.7)).fill()
        }
    }

    override var focusRingMaskBounds: NSRect {
        NSRect(x: 3, y: 4, width: 22, height: 21)
    }

    override func drawFocusRingMask() {
        NSBezierPath(
            roundedRect: focusRingMaskBounds,
            xRadius: 7,
            yRadius: 7
        ).fill()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaReference { removeTrackingArea(trackingAreaReference) }
        let tracking = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseEnteredAndExited],
            owner: self
        )
        addTrackingArea(tracking)
        trackingAreaReference = tracking
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
}
