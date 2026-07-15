import PDFKit

enum PDFNoteExtractor {
    private static let supportedAnnotationTypes = ["Highlight", "Text"]

    static func extractNotes(from document: PDFDocument) -> [AnnotationNote] {
        var notes: [AnnotationNote] = []
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            for annotation in page.annotations {
                guard let note = note(for: annotation, pageIndex: pageIndex, includeEmptyContents: false) else {
                    continue
                }
                notes.append(note)
            }
        }
        return notes
    }

    static func note(
        for annotation: PDFAnnotation,
        pageIndex: Int,
        includeEmptyContents: Bool
    ) -> AnnotationNote? {
        let type = normalizedType(annotation)
        guard supportedAnnotationTypes.contains(where: { $0.caseInsensitiveCompare(type) == .orderedSame }) else {
            return nil
        }

        let contents = annotation.contents ?? ""
        let sourceText: String
        if type.caseInsensitiveCompare("Highlight") == .orderedSame,
           let page = annotation.page {
            sourceText = page.selection(for: annotation.bounds)?.string ?? ""
        } else {
            sourceText = ""
        }
        let hasReadableText = !contents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard includeEmptyContents || hasReadableText else {
            return nil
        }

        return AnnotationNote(
            id: "\(pageIndex)-\(ObjectIdentifier(annotation).hashValue)",
            pageIndex: pageIndex,
            annotationType: type,
            contents: contents,
            sourceText: sourceText,
            author: annotation.userName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            bounds: annotation.bounds,
            color: annotation.color,
            annotation: annotation
        )
    }

    static func extractOutline(from document: PDFDocument) -> [DocumentOutlineItem] {
        guard let root = document.outlineRoot else { return [] }
        return (0..<root.numberOfChildren).compactMap { index in
            root.child(at: index).map { outlineItem($0, document: document, path: "\(index)") }
        }
    }

    private static func outlineItem(
        _ outline: PDFOutline,
        document: PDFDocument,
        path: String
    ) -> DocumentOutlineItem {
        let destination = outline.destination ?? (outline.action as? PDFActionGoTo)?.destination
        let pageIndex = destination
            .flatMap(\.page)
            .map { document.index(for: $0) }
            .flatMap { $0 >= 0 ? $0 : nil }
        let children = (0..<outline.numberOfChildren).compactMap { index in
            outline.child(at: index).map {
                outlineItem($0, document: document, path: "\(path).\(index)")
            }
        }
        return DocumentOutlineItem(
            id: path,
            title: outline.label?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Untitled Section",
            pageIndex: pageIndex,
            point: destination?.point,
            children: children
        )
    }

    private static func normalizedType(_ annotation: PDFAnnotation) -> String {
        (annotation.type ?? "Unknown").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
