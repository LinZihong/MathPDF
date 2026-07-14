import CoreGraphics
import PDFKit

struct AnnotationNote: Identifiable {
    let id: String
    let pageIndex: Int
    let annotationType: String
    let contents: String
    let sourceText: String
    let author: String?
    let bounds: CGRect
    let annotation: PDFAnnotation

    var trimmedContents: String {
        contents.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedSourceText: String {
        sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var sidebarPreview: String {
        if !trimmedSourceText.isEmpty { return trimmedSourceText }
        if !trimmedContents.isEmpty { return trimmedContents }
        return "Empty note"
    }
}

extension AnnotationNote: Equatable {
    static func == (lhs: AnnotationNote, rhs: AnnotationNote) -> Bool {
        lhs.id == rhs.id && lhs.contents == rhs.contents && lhs.bounds == rhs.bounds
    }
}

struct DocumentOutlineItem: Identifiable, Hashable {
    let id: String
    let title: String
    let pageIndex: Int?
    let point: CGPoint?
    let children: [DocumentOutlineItem]
}

enum ReaderSidebarMode: String, CaseIterable, Identifiable {
    case contents = "Table of Contents"
    case notes = "Highlights and Notes"

    var id: String { rawValue }
}

enum ReaderTool: String, CaseIterable, Identifiable {
    case browse
    case textNote

    var id: String { rawValue }
}

struct ReaderNavigationRequest: Equatable {
    let token: UUID
    let pageIndex: Int
    let point: CGPoint?
    let bounds: CGRect?
    let noteID: String?
    let opensNote: Bool
    let annotation: PDFAnnotation?

    static func == (lhs: ReaderNavigationRequest, rhs: ReaderNavigationRequest) -> Bool {
        lhs.token == rhs.token
    }
}
