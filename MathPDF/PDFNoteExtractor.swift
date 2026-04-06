//
//  PDFNoteExtractor.swift
//  MathPDF
//
//  Created by Zihong Lin on 4/5/26.
//

import PDFKit

enum PDFNoteExtractor {
    static func extractNotes(from document: PDFDocument) -> [AnnotationNote] {
        var notes: [AnnotationNote] = []

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else {
                continue
            }

            for (annotationIndex, annotation) in page.annotations.enumerated() {
                let contents = annotation.contents?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let annotationType = annotation.type ?? "Unknown"

                guard !contents.isEmpty else {
                    continue
                }

                guard annotationType.caseInsensitiveCompare("Popup") != .orderedSame else {
                    continue
                }

                let id = "\(pageIndex)-\(annotationIndex)-\(annotationType)-\(annotation.bounds.integral.debugDescription)"
                notes.append(
                    AnnotationNote(
                        id: id,
                        pageIndex: pageIndex,
                        annotationType: annotationType,
                        contents: contents,
                        bounds: annotation.bounds
                    )
                )
            }
        }

        return notes
    }
}
