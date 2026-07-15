import CoreGraphics
import AppKit
import PDFKit

struct AnnotationNote: Identifiable {
    let id: String
    let pageIndex: Int
    let annotationType: String
    let contents: String
    let sourceText: String
    let author: String?
    let bounds: CGRect
    let color: NSColor
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
        lhs.id == rhs.id
            && lhs.contents == rhs.contents
            && lhs.bounds == rhs.bounds
            && lhs.color == rhs.color
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

struct AnnotationAuthoringNotice: Identifiable, Equatable {
    let id: String
    let title: String
    let message: String

    static let multiPageHighlightNote = AnnotationAuthoringNotice(
        id: "multi-page-highlight-note",
        title: "Use a Single-Page Selection",
        message: "A PDF note belongs to one highlight on one page. Shorten the selection, or use Highlight to mark the full multi-page passage."
    )
}

struct ReaderNavigationRequest: Equatable {
    let token: UUID
    let pageIndex: Int
    let point: CGPoint?
    let bounds: CGRect?
    let noteID: String?
    let opensNote: Bool
    let startsEditing: Bool
    let annotation: PDFAnnotation?

    static func == (lhs: ReaderNavigationRequest, rhs: ReaderNavigationRequest) -> Bool {
        lhs.token == rhs.token
    }
}
