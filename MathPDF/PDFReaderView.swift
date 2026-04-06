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

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displaysPageBreaks = true
        pdfView.backgroundColor = .windowBackgroundColor
        pdfView.document = document
        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        if pdfView.document !== document {
            pdfView.document = document
        }

        guard let focusedNote else {
            context.coordinator.lastFocusedNoteID = nil
            return
        }

        guard context.coordinator.lastFocusedNoteID != focusedNote.id else {
            return
        }

        guard let page = document.page(at: focusedNote.pageIndex) else {
            return
        }

        let destination = PDFDestination(
            page: page,
            at: CGPoint(x: focusedNote.bounds.minX, y: focusedNote.bounds.maxY)
        )
        pdfView.go(to: destination)
        context.coordinator.lastFocusedNoteID = focusedNote.id
    }

    final class Coordinator {
        var lastFocusedNoteID: AnnotationNote.ID?
    }
}
