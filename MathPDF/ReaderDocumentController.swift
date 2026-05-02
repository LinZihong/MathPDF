//
//  ReaderDocumentController.swift
//  MathPDF
//
//  Created by Zihong Lin on 4/5/26.
//

import AppKit
import Combine
import PDFKit
import UniformTypeIdentifiers

@MainActor
final class ReaderDocumentController: ObservableObject {
    @Published var documentURL: URL?
    @Published var pdfDocument: PDFDocument?
    @Published var notes: [AnnotationNote] = []
    @Published var selectedNoteID: AnnotationNote.ID?
    @Published var activeNote: AnnotationNote?
    @Published var errorMessage: String?

    private var didAttemptLaunchOpen = false
    private let popupCoordinator = PDFPopupCompanionCoordinator()
    private var securityScopedDocumentURL: URL?

    var selectedNote: AnnotationNote? {
        activeNote
    }

    func openDocumentPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        openDocument(at: url)
    }

    func openLaunchDocumentIfNeeded() {
        guard !didAttemptLaunchOpen else {
            return
        }
        didAttemptLaunchOpen = true

        guard let launchPath = launchDocumentPath() else {
            return
        }

        openDocument(at: URL(fileURLWithPath: launchPath))
    }

    func openDocument(at url: URL) {
        let startedSecurityScope = beginAccessingSecurityScopedDocumentIfNeeded(url)

        guard let pdfDocument = PDFDocument(url: url) else {
            if startedSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
            errorMessage = "MathPDF couldn't load \(url.lastPathComponent)."
            return
        }

        if let previousURL = securityScopedDocumentURL, previousURL != url {
            previousURL.stopAccessingSecurityScopedResource()
        }

        if startedSecurityScope {
            securityScopedDocumentURL = url
        } else if securityScopedDocumentURL != url {
            securityScopedDocumentURL = nil
        }

        popupCoordinator.prepareDocumentForDisplay(pdfDocument)
        documentURL = url
        self.pdfDocument = pdfDocument
        refreshNotes(activeNoteID: nil)
        activeNote = nil
        selectedNoteID = nil
        errorMessage = nil
    }

    func activateSidebarSelection() {
        guard let selectedNoteID else {
            activeNote = nil
            return
        }

        activeNote = note(withID: selectedNoteID, includeEmptyContents: true)
    }

    func activateNote(_ note: AnnotationNote?) {
        activeNote = note
        if let note, notes.contains(where: { $0.id == note.id }) {
            selectedNoteID = note.id
        } else if note == nil {
            selectedNoteID = nil
        }
    }

    func activateAnnotation(_ annotation: PDFAnnotation) {
        guard let note = note(for: annotation, includeEmptyContents: true) else {
            return
        }

        activateNote(note)
    }

    func dismissActiveNote() {
        activeNote = nil
        selectedNoteID = nil
    }

    @discardableResult
    func saveActiveNoteContents(_ contents: String) -> Bool {
        guard
            let pdfDocument,
            let documentURL,
            let activeNote,
            let annotation = annotation(for: activeNote)
        else {
            errorMessage = "MathPDF couldn't save the selected note."
            return false
        }

        let previousContents = annotation.contents
        let previousModificationDate = annotation.modificationDate
        annotation.contents = contents
        annotation.modificationDate = Date()
        let popupMutation = popupCoordinator.synchronizePopupCompanion(
            for: annotation,
            previousContents: previousContents ?? "",
            updatedContents: contents
        )

        guard popupCoordinator.writeDocument(pdfDocument, to: documentURL) else {
            popupMutation.rollback()
            annotation.contents = previousContents
            annotation.modificationDate = previousModificationDate
            popupCoordinator.prepareDocumentForDisplay(pdfDocument)
            errorMessage = "MathPDF couldn't write changes back to \(documentURL.lastPathComponent)."
            return false
        }

        popupCoordinator.prepareDocumentForDisplay(pdfDocument)
        refreshNotes(activeNoteID: activeNote.id)
        if let refreshedNote = note(withID: activeNote.id, includeEmptyContents: true) {
            self.activeNote = refreshedNote
        } else {
            self.activeNote = nil
        }
        errorMessage = nil
        return true
    }

    private func refreshNotes(activeNoteID: AnnotationNote.ID?) {
        guard let pdfDocument else {
            notes = []
            if activeNoteID == nil {
                selectedNoteID = nil
            }
            return
        }

        notes = PDFNoteExtractor.extractNotes(from: pdfDocument)

        if let activeNoteID, notes.contains(where: { $0.id == activeNoteID }) {
            selectedNoteID = activeNoteID
        } else if let selectedNoteID, notes.contains(where: { $0.id == selectedNoteID }) {
            // Keep the current sidebar selection if it still exists.
        } else if activeNoteID == nil {
            selectedNoteID = nil
        } else {
            selectedNoteID = notes.first?.id
        }
    }

    private func note(
        for annotation: PDFAnnotation,
        includeEmptyContents: Bool
    ) -> AnnotationNote? {
        guard
            let page = annotation.page,
            let pdfDocument,
            let pageIndex = pdfDocument.index(for: page).nonNegative
        else {
            return nil
        }

        guard let annotationIndex = page.annotations.firstIndex(where: { $0 === annotation }) else {
            return nil
        }

        return PDFNoteExtractor.note(
            for: annotation,
            pageIndex: pageIndex,
            annotationIndex: annotationIndex,
            includeEmptyContents: includeEmptyContents
        )
    }

    private func note(
        withID id: AnnotationNote.ID,
        includeEmptyContents: Bool
    ) -> AnnotationNote? {
        guard let pdfDocument else {
            return nil
        }

        for pageIndex in 0..<pdfDocument.pageCount {
            guard let page = pdfDocument.page(at: pageIndex) else {
                continue
            }

            for (annotationIndex, annotation) in page.annotations.enumerated() {
                guard
                    let note = PDFNoteExtractor.note(
                        for: annotation,
                        pageIndex: pageIndex,
                        annotationIndex: annotationIndex,
                        includeEmptyContents: includeEmptyContents
                    ),
                    note.id == id
                else {
                    continue
                }

                return note
            }
        }

        return nil
    }

    private func annotation(for note: AnnotationNote) -> PDFAnnotation? {
        guard
            let pdfDocument,
            let page = pdfDocument.page(at: note.pageIndex)
        else {
            return nil
        }

        guard page.annotations.indices.contains(note.annotationIndex) else {
            return nil
        }

        let annotation = page.annotations[note.annotationIndex]
        let current = PDFNoteExtractor.note(
            for: annotation,
            pageIndex: note.pageIndex,
            annotationIndex: note.annotationIndex,
            includeEmptyContents: true
        )

        return current?.id == note.id ? annotation : nil
    }

    private func beginAccessingSecurityScopedDocumentIfNeeded(_ url: URL) -> Bool {
        guard url.isFileURL else {
            return false
        }

        if securityScopedDocumentURL == url {
            return false
        }

        return url.startAccessingSecurityScopedResource()
    }

    private func launchDocumentPath() -> String? {
        Self.launchDocumentPath(
            arguments: ProcessInfo.processInfo.arguments,
            environment: ProcessInfo.processInfo.environment
        )
    }

    nonisolated static func launchDocumentPath(
        arguments: [String],
        environment: [String: String],
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> String? {
        if let index = arguments.firstIndex(of: "--open-document") {
            let pathIndex = arguments.index(after: index)
            if pathIndex < arguments.endIndex {
                return NSString(string: arguments[pathIndex]).expandingTildeInPath
            }
        }

        if let positionalPath = arguments
            .dropFirst()
            .map({ NSString(string: $0).expandingTildeInPath })
            .first(where: { argument in
                !argument.hasPrefix("-") && fileExists(argument)
            }) {
            return positionalPath
        }

        if let environmentPath = environment["MATHPDF_OPEN_DOCUMENT"] {
            return NSString(string: environmentPath).expandingTildeInPath
        }

        return nil
    }
}

private extension Int {
    var nonNegative: Int? {
        self >= 0 ? self : nil
    }
}
