//
//  PDFNoteExtractor.swift
//  MathPDF
//
//  Created by Zihong Lin on 4/5/26.
//

import PDFKit

enum PDFNoteExtractor {
    private static let supportedAnnotationTypes = ["Highlight", "Text"]

    static func extractNotes(from document: PDFDocument) -> [AnnotationNote] {
        var notes: [AnnotationNote] = []

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else {
                continue
            }

            let annotations = page.annotations
            for (annotationIndex, annotation) in annotations.enumerated() {
                guard !isPreviewTextCompanion(annotation, among: annotations) else {
                    continue
                }

                guard let note = note(
                    for: annotation,
                    pageIndex: pageIndex,
                    annotationIndex: annotationIndex,
                    includeEmptyContents: false
                ) else {
                    continue
                }

                notes.append(note)
            }
        }

        return notes
    }

    private static func isPreviewTextCompanion(
        _ annotation: PDFAnnotation,
        among annotations: [PDFAnnotation]
    ) -> Bool {
        guard annotationType(annotation, equals: "Text") else {
            return false
        }

        let contents = normalizedContents(annotation.contents ?? "")
        guard !contents.isEmpty else {
            return false
        }

        return annotations.contains { candidate in
            guard annotationType(candidate, equals: "Highlight") else {
                return false
            }

            guard normalizedContents(candidate.contents ?? "") == contents else {
                return false
            }

            let annotationCenter = CGPoint(x: annotation.bounds.midX, y: annotation.bounds.midY)
            let candidateAnchor = CGPoint(x: candidate.bounds.maxX, y: candidate.bounds.maxY)
            return hypot(annotationCenter.x - candidateAnchor.x, annotationCenter.y - candidateAnchor.y) < 80
        }
    }

    static func note(
        for annotation: PDFAnnotation,
        pageIndex: Int,
        annotationIndex: Int,
        includeEmptyContents: Bool
    ) -> AnnotationNote? {
        let contents = annotation.contents ?? ""
        let trimmedContents = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        let annotationType = annotation.type ?? "Unknown"

        guard annotationType.caseInsensitiveCompare("Popup") != .orderedSame else {
            return nil
        }

        guard supportedAnnotationTypes.contains(where: {
            $0.caseInsensitiveCompare(annotationType) == .orderedSame
        }) else {
            return nil
        }

        guard includeEmptyContents || !trimmedContents.isEmpty else {
            return nil
        }

        let id = "\(pageIndex)-\(annotationIndex)-\(annotationType)-\(annotation.bounds.integral.debugDescription)"
        return AnnotationNote(
            id: id,
            pageIndex: pageIndex,
            annotationIndex: annotationIndex,
            annotationType: annotationType,
            contents: contents,
            bounds: annotation.bounds
        )
    }

    private static func annotationType(_ annotation: PDFAnnotation, equals type: String) -> Bool {
        (annotation.type ?? "").caseInsensitiveCompare(type) == .orderedSame
    }

    private static func normalizedContents(_ contents: String) -> String {
        contents.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
