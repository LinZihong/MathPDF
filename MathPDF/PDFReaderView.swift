//
//  PDFReaderView.swift
//  MathPDF
//
//  Created by Zihong Lin on 4/5/26.
//

import PDFKit
import SwiftUI

struct PDFReaderView: NSViewRepresentable {
    let document: PDFDocument
    let focusedNote: AnnotationNote?
    let onActivateAnnotation: (PDFAnnotation) -> Void
    let onSaveNoteContents: (String) -> Bool
    let onCloseNote: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onActivateAnnotation: onActivateAnnotation,
            onSaveNoteContents: onSaveNoteContents,
            onCloseNote: onCloseNote
        )
    }

    func makeNSView(context: Context) -> ReaderContainerView {
        let containerView = ReaderContainerView()
        containerView.configure(
            document: document,
            coordinator: context.coordinator
        )
        return containerView
    }

    func updateNSView(_ containerView: ReaderContainerView, context: Context) {
        context.coordinator.onActivateAnnotation = onActivateAnnotation
        context.coordinator.onSaveNoteContents = onSaveNoteContents
        context.coordinator.onCloseNote = onCloseNote

        if containerView.pdfView.document !== document {
            containerView.configure(
                document: document,
                coordinator: context.coordinator
            )
        }
        containerView.refreshPreviewAnnotationVisibility()

        guard let focusedNote else {
            context.coordinator.lastFocusedNoteID = nil
            containerView.present(note: nil, on: document, coordinator: context.coordinator)
            return
        }

        guard let page = document.page(at: focusedNote.pageIndex) else {
            return
        }

        if context.coordinator.lastFocusedNoteID != focusedNote.id {
            let destination = PDFDestination(
                page: page,
                at: CGPoint(x: focusedNote.bounds.minX, y: focusedNote.bounds.maxY)
            )
            containerView.pdfView.go(to: destination)
            context.coordinator.lastFocusedNoteID = focusedNote.id
        }

        containerView.present(note: focusedNote, on: document, coordinator: context.coordinator)
    }

    final class Coordinator {
        var onActivateAnnotation: (PDFAnnotation) -> Void
        var onSaveNoteContents: (String) -> Bool
        var onCloseNote: () -> Void
        var lastFocusedNoteID: AnnotationNote.ID?

        init(
            onActivateAnnotation: @escaping (PDFAnnotation) -> Void,
            onSaveNoteContents: @escaping (String) -> Bool,
            onCloseNote: @escaping () -> Void
        ) {
            self.onActivateAnnotation = onActivateAnnotation
            self.onSaveNoteContents = onSaveNoteContents
            self.onCloseNote = onCloseNote
        }
    }
}

final class ReaderContainerView: NSView {
    let pdfView = ReaderPDFView()
    private let noteHostView = NSHostingView(rootView: AnyView(EmptyView()))
    private var currentNoteID: AnnotationNote.ID?
    private var observations: [NSObjectProtocol] = []
    private weak var currentPage: PDFPage?
    private var currentNoteBounds: CGRect = .zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        pdfView.translatesAutoresizingMaskIntoConstraints = false
        noteHostView.translatesAutoresizingMaskIntoConstraints = true
        noteHostView.isHidden = true

        addSubview(pdfView)
        addSubview(noteHostView)

        NSLayoutConstraint.activate([
            pdfView.leadingAnchor.constraint(equalTo: leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: trailingAnchor),
            pdfView.topAnchor.constraint(equalTo: topAnchor),
            pdfView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        for observation in observations {
            NotificationCenter.default.removeObserver(observation)
        }
    }

    func configure(document: PDFDocument, coordinator: PDFReaderView.Coordinator) {
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displaysPageBreaks = true
        pdfView.backgroundColor = .windowBackgroundColor
        pdfView.document = document
        pdfView.onAnnotationActivated = coordinator.onActivateAnnotation

        for observation in observations {
            NotificationCenter.default.removeObserver(observation)
        }
        observations.removeAll()

        for name in [
            NSNotification.Name.PDFViewVisiblePagesChanged,
            NSNotification.Name.PDFViewScaleChanged,
            NSNotification.Name.PDFViewPageChanged
        ] {
            let observation = NotificationCenter.default.addObserver(
                forName: name,
                object: pdfView,
                queue: .main
            ) { [weak self] _ in
                self?.repositionNotePopover()
            }
            observations.append(observation)
        }
    }

    func present(
        note: AnnotationNote?,
        on document: PDFDocument,
        coordinator: PDFReaderView.Coordinator
    ) {
        guard
            let note,
            let page = document.page(at: note.pageIndex)
        else {
            currentNoteID = nil
            currentPage = nil
            currentNoteBounds = .zero
            noteHostView.isHidden = true
            noteHostView.rootView = AnyView(EmptyView())
            return
        }

        currentNoteID = note.id
        currentPage = page
        currentNoteBounds = note.bounds

        noteHostView.rootView = AnyView(
            InlineNotePopover(
                note: note,
                onSave: coordinator.onSaveNoteContents,
                onClose: coordinator.onCloseNote
            )
            .id(note.id)
        )
        noteHostView.isHidden = false
        repositionNotePopover()
    }

    func refreshPreviewAnnotationVisibility() {
        guard let document = pdfView.document else {
            return
        }

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else {
                continue
            }

            for annotation in page.annotations where isPreviewAffordance(annotation) {
                annotation.shouldDisplay = false
            }
        }

        pdfView.layoutDocumentView()
        pdfView.setNeedsDisplay(pdfView.bounds)
    }

    override func layout() {
        super.layout()
        repositionNotePopover()
    }

    private func repositionNotePopover() {
        guard
            currentNoteID != nil,
            let page = currentPage,
            !noteHostView.isHidden
        else {
            return
        }

        let noteRect = pdfView.convert(currentNoteBounds, from: page)
        let preferredSize = NSSize(width: 340, height: 360)
        let gap: CGFloat = 16
        let horizontalMargin: CGFloat = 16
        let verticalMargin: CGFloat = 16

        var originX = noteRect.maxX + gap
        if originX + preferredSize.width > bounds.maxX - horizontalMargin {
            originX = noteRect.minX - preferredSize.width - gap
        }
        originX = max(horizontalMargin, min(originX, bounds.maxX - preferredSize.width - horizontalMargin))

        var originY = noteRect.maxY - preferredSize.height
        originY = max(verticalMargin, min(originY, bounds.maxY - preferredSize.height - verticalMargin))

        noteHostView.frame = CGRect(origin: CGPoint(x: originX, y: originY), size: preferredSize)
    }

    private func isPreviewAffordance(_ annotation: PDFAnnotation) -> Bool {
        guard let type = annotation.type?.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased() else {
            return false
        }

        return type == "popup" || type == "text"
    }
}

final class ReaderPDFView: PDFView {
    var onAnnotationActivated: ((PDFAnnotation) -> Void)?

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        activateAnnotationIfNeeded(from: event)
    }

    private func activateAnnotationIfNeeded(from event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)
        guard let page = page(for: viewPoint, nearest: false) else {
            return
        }

        let pagePoint = convert(viewPoint, to: page)
        guard let annotation = page.annotation(at: pagePoint) else {
            return
        }

        onAnnotationActivated?(annotation)
    }
}

private struct InlineNotePopover: View {
    enum Mode: String, CaseIterable, Identifiable {
        case rendered = "Rendered"
        case source = "Source"

        var id: String { rawValue }
    }

    let note: AnnotationNote
    let onSave: (String) -> Bool
    let onClose: () -> Void

    @State private var mode: Mode = .rendered
    @State private var draftText: String

    init(
        note: AnnotationNote,
        onSave: @escaping (String) -> Bool,
        onClose: @escaping () -> Void
    ) {
        self.note = note
        self.onSave = onSave
        self.onClose = onClose
        _draftText = State(initialValue: note.contents)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Rendered Note")
                        .font(.headline)
                        .accessibilityIdentifier("rendered-note-title")
                    Text("Page \(note.pageIndex + 1) • \(note.annotationType)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("rendered-note-metadata")
                }

                Spacer()

                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
            }

            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Group {
                switch mode {
                case .rendered:
                    MathNoteView(rawText: draftText, maximumContentHeight: 208)
                        .padding()
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityIdentifier("rendered-note-content")
                case .source:
                    TextEditor(text: $draftText)
                        .font(.body.monospaced())
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(nsColor: .textBackgroundColor))
                        )
                        .accessibilityIdentifier("inline-note-source-editor")
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: 232, alignment: .topLeading)

            HStack {
                if draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Empty notes stay editable, but only appear in the sidebar once they have text.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Stored as plain text in the PDF.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Save") {
                    if onSave(draftText) {
                        onClose()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("inline-note-save")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.black.opacity(0.08))
        )
        .shadow(color: .black.opacity(0.14), radius: 18, y: 12)
        .accessibilityIdentifier("inline-note-popover")
    }
}
