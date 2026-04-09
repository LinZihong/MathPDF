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
    private var securityScopedDocumentURL: URL?

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

        documentURL = url
        self.pdfDocument = pdfDocument
        notes = PDFNoteExtractor.extractNotes(from: pdfDocument)
        selectedNoteID = notes.first?.id
        errorMessage = nil
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
