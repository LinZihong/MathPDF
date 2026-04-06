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
    @Published var errorMessage: String?

    private var didAttemptLaunchOpen = false

    var selectedNote: AnnotationNote? {
        notes.first(where: { $0.id == selectedNoteID })
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
        guard let pdfDocument = PDFDocument(url: url) else {
            errorMessage = "MathPDF couldn't load \(url.lastPathComponent)."
            return
        }

        documentURL = url
        self.pdfDocument = pdfDocument
        notes = PDFNoteExtractor.extractNotes(from: pdfDocument)
        selectedNoteID = notes.first?.id
        errorMessage = nil
    }

    private func launchDocumentPath() -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--open-document") {
            let pathIndex = arguments.index(after: index)
            if pathIndex < arguments.endIndex {
                return arguments[pathIndex]
            }
        }

        return ProcessInfo.processInfo.environment["MATHPDF_OPEN_DOCUMENT"]
    }
}
