import AppKit
import Foundation
import PDFKit

enum PDFAnnotationInteroperabilityError: LocalizedError {
    case invalidSerializedDocument(String)

    var errorDescription: String? {
        switch self {
        case let .invalidSerializedDocument(reason):
            "MathPDF refused to save because annotation compatibility validation failed: \(reason)"
        }
    }
}

struct PDFPopupDiskState {
    let flags: Int
    let isOpen: Bool
}

enum PDFAnnotationInteroperability {
    private static let restrictedAnnotationFlags = (1 << 6) | (1 << 7) | (1 << 9)

    static func annotationAllowsEditing(_ annotation: PDFAnnotation) -> Bool {
        rawFlags(of: annotation) & restrictedAnnotationFlags == 0
    }

    static func capturePopupDiskStates(
        in document: PDFDocument
    ) -> [ObjectIdentifier: PDFPopupDiskState] {
        var states: [ObjectIdentifier: PDFPopupDiskState] = [:]
        for popup in popupAnnotations(in: document) {
            states[ObjectIdentifier(popup)] = PDFPopupDiskState(
                flags: rawFlags(of: popup),
                isOpen: popup.isOpen
            )
        }
        return states
    }

    static func suppressPopupPresentation(
        in document: PDFDocument,
        states: inout [ObjectIdentifier: PDFPopupDiskState]
    ) {
        for popup in popupAnnotations(in: document) {
            let identifier = ObjectIdentifier(popup)
            if case nil = states[identifier] {
                states[identifier] = PDFPopupDiskState(
                    flags: rawFlags(of: popup),
                    isOpen: popup.isOpen
                )
            }
            popup.isOpen = false
        }
    }

    static func makePopupCompanion(for owner: PDFAnnotation, on page: PDFPage) -> PDFAnnotation {
        let popup = PDFAnnotation(
            bounds: popupBounds(for: owner, on: page),
            forType: .popup,
            withProperties: nil
        )
        popup.color = owner.color
        popup.contents = nil
        popup.isOpen = false
        // The page and owner are used only for placement and persistence
        // bookkeeping. Do not attach either live PDFKit relationship here:
        // PDFKit paints a native closed-note marker from `owner.popup` even
        // when the Popup itself is absent from `page.annotations`.
        return popup
    }

    static func validate(
        serializedData: Data,
        against expectedDocument: PDFDocument,
        logicalAnnotationsByPage: [[PDFAnnotation]]? = nil,
        logicalPopupEdges: [(owner: PDFAnnotation, popup: PDFAnnotation)]? = nil
    ) throws {
        guard let reloaded = PDFDocument(data: serializedData) else {
            throw PDFAnnotationInteroperabilityError.invalidSerializedDocument(
                "the serialized PDF could not be reopened"
            )
        }
        let expected = DocumentSemantics(
            document: expectedDocument,
            logicalAnnotationsByPage: logicalAnnotationsByPage,
            logicalPopupEdges: logicalPopupEdges
        )
        let actual = DocumentSemantics(document: reloaded)
        guard expected.pageCount == actual.pageCount else {
            throw PDFAnnotationInteroperabilityError.invalidSerializedDocument("page count changed")
        }
        guard expected.pages == actual.pages else {
            let reason = expected.firstPageDifference(from: actual)
                ?? "page geometry or annotation semantics changed"
            throw PDFAnnotationInteroperabilityError.invalidSerializedDocument(reason)
        }
        guard expected.keywords == actual.keywords else {
            throw PDFAnnotationInteroperabilityError.invalidSerializedDocument("PDF Keywords changed")
        }
    }

    private static func popupAnnotations(in document: PDFDocument) -> [PDFAnnotation] {
        (0..<document.pageCount).flatMap { pageIndex in
            document.page(at: pageIndex)?.annotations.filter {
                $0.type?.caseInsensitiveCompare("Popup") == .orderedSame
            } ?? []
        }
    }

    private static func popupBounds(for owner: PDFAnnotation, on page: PDFPage) -> CGRect {
        let cropBox = page.bounds(for: .cropBox)
        let size = CGSize(width: 72, height: 36)
        let proposed = CGPoint(x: owner.bounds.maxX + 4, y: owner.bounds.maxY + 4)
        let origin = CGPoint(
            x: min(max(proposed.x, cropBox.minX), cropBox.maxX - size.width),
            y: min(max(proposed.y, cropBox.minY), cropBox.maxY - size.height)
        )
        return CGRect(origin: origin, size: size)
    }

    private static func rawFlags(of annotation: PDFAnnotation) -> Int {
        (annotation.value(forAnnotationKey: .flags) as? NSNumber)?.intValue ?? 0
    }

}

private struct DocumentSemantics {
    let pageCount: Int
    let pages: [PageSemantics]
    let keywords: [String]

    init(
        document: PDFDocument,
        logicalAnnotationsByPage: [[PDFAnnotation]]? = nil,
        logicalPopupEdges: [(owner: PDFAnnotation, popup: PDFAnnotation)]? = nil
    ) {
        pageCount = document.pageCount
        pages = (0..<document.pageCount).compactMap { pageIndex in
            document.page(at: pageIndex).map {
                let logicalAnnotations = logicalAnnotationsByPage.flatMap { pages in
                    pageIndex < pages.count ? pages[pageIndex] : nil
                }
                return PageSemantics(
                    page: $0,
                    index: pageIndex,
                    annotations: logicalAnnotations ?? $0.annotations,
                    popupEdges: logicalPopupEdges
                )
            }
        }
        let attributes = document.documentAttributes ?? [:]
        let key = PDFDocumentAttribute.keywordsAttribute.rawValue
        if let values = attributes[key] as? [String] {
            keywords = values
        } else if let value = attributes[key] as? String {
            keywords = [value]
        } else {
            keywords = []
        }
    }

    func firstPageDifference(from other: DocumentSemantics) -> String? {
        for index in pages.indices {
            guard index < other.pages.count else {
                return "page \(index + 1) disappeared"
            }
            if let difference = pages[index].firstDifference(from: other.pages[index]) {
                return "page \(index + 1): \(difference)"
            }
        }
        return pages.count == other.pages.count
            ? nil
            : "serialized document gained unexpected pages"
    }
}

private struct PageSemantics: Equatable {
    let rotation: Int
    let mediaBox: RectSemantics
    let cropBox: RectSemantics
    let bleedBox: RectSemantics
    let trimBox: RectSemantics
    let artBox: RectSemantics
    let annotations: [AnnotationSemantics]
    let reciprocalPopupOwners: [String]
    let reciprocalPopupEdges: [PopupEdgeSemantics]
    let orphanPopups: [String]

    init(
        page: PDFPage,
        index: Int,
        annotations pageAnnotations: [PDFAnnotation],
        popupEdges explicitPopupEdges: [(owner: PDFAnnotation, popup: PDFAnnotation)]? = nil
    ) {
        rotation = page.rotation
        mediaBox = RectSemantics(page.bounds(for: .mediaBox))
        cropBox = RectSemantics(page.bounds(for: .cropBox))
        bleedBox = RectSemantics(page.bounds(for: .bleedBox))
        trimBox = RectSemantics(page.bounds(for: .trimBox))
        artBox = RectSemantics(page.bounds(for: .artBox))
        // `/Annots` order controls overlapping annotation painting and hit
        // testing. Treat it as document semantics instead of comparing a sorted
        // multiset that can conceal first-save order drift.
        annotations = pageAnnotations.map {
            AnnotationSemantics(annotation: $0, pageIndex: index)
        }

        let pageAnnotationIDs = Set(pageAnnotations.map(ObjectIdentifier.init))
        let indexByID = Dictionary(uniqueKeysWithValues: pageAnnotations.enumerated().map {
            (ObjectIdentifier($0.element), $0.offset)
        })
        var owners: [String] = []
        var edges: [PopupEdgeSemantics] = []
        var ownedPopupIDs: Set<ObjectIdentifier> = []
        let popupPairs: [(owner: PDFAnnotation, popup: PDFAnnotation)]
        if let explicitPopupEdges {
            popupPairs = explicitPopupEdges.filter {
                pageAnnotationIDs.contains(ObjectIdentifier($0.owner))
                    && pageAnnotationIDs.contains(ObjectIdentifier($0.popup))
            }
        } else {
            popupPairs = pageAnnotations.compactMap { owner in
                guard
                    owner.type?.caseInsensitiveCompare("Popup") != .orderedSame,
                    let popup = owner.popup,
                    pageAnnotationIDs.contains(ObjectIdentifier(popup)),
                    let parent = popup.value(forAnnotationKey: .parent) as? PDFAnnotation,
                    parent === owner
                else { return nil }
                return (owner: owner, popup: popup)
            }
        }

        for pair in popupPairs {
            let owner = pair.owner
            let popup = pair.popup
            guard
                let ownerIndex = indexByID[ObjectIdentifier(owner)],
                let popupIndex = indexByID[ObjectIdentifier(popup)]
            else { continue }
            owners.append(AnnotationSemantics(annotation: owner, pageIndex: index).description)
            edges.append(.init(
                owner: Self.edgeIdentity(for: owner, at: ownerIndex, pageIndex: index),
                popup: Self.edgeIdentity(for: popup, at: popupIndex, pageIndex: index)
            ))
            ownedPopupIDs.insert(ObjectIdentifier(popup))
        }
        reciprocalPopupOwners = owners.sorted()
        reciprocalPopupEdges = edges.sorted {
            ($0.owner, $0.popup) < ($1.owner, $1.popup)
        }
        orphanPopups = pageAnnotations.filter {
            $0.type?.caseInsensitiveCompare("Popup") == .orderedSame
                && !ownedPopupIDs.contains(ObjectIdentifier($0))
        }
        .map { AnnotationSemantics(annotation: $0, pageIndex: index).description }
        .sorted()
    }

    private static func edgeIdentity(
        for annotation: PDFAnnotation,
        at index: Int,
        pageIndex: Int
    ) -> String {
        if let name = annotation.value(
            forAnnotationKey: PDFAnnotationKey(rawValue: "/NM")
        ) as? String, !name.isEmpty {
            return "nm:\(name)"
        }
        let semantics = AnnotationSemantics(annotation: annotation, pageIndex: pageIndex)
        return "slot:\(index)|\(semantics.description)"
    }

    func firstDifference(from other: PageSemantics) -> String? {
        if rotation != other.rotation { return "rotation changed" }
        if mediaBox != other.mediaBox { return "media box changed" }
        if cropBox != other.cropBox { return "crop box changed" }
        if bleedBox != other.bleedBox { return "bleed box changed" }
        if trimBox != other.trimBox { return "trim box changed" }
        if artBox != other.artBox { return "art box changed" }
        if annotations.count != other.annotations.count {
            return "annotation count changed from \(annotations.count) to \(other.annotations.count)"
        }
        for index in annotations.indices where annotations[index] != other.annotations[index] {
            return "annotation \(index + 1) changed; expected [\(annotations[index])] actual [\(other.annotations[index])]"
        }
        if reciprocalPopupOwners != other.reciprocalPopupOwners {
            return "reciprocal popup ownership changed"
        }
        if reciprocalPopupEdges != other.reciprocalPopupEdges {
            return "exact reciprocal popup edges changed"
        }
        if orphanPopups != other.orphanPopups {
            return "orphan popup set changed"
        }
        return nil
    }
}

private struct PopupEdgeSemantics: Equatable {
    let owner: String
    let popup: String
}

private struct AnnotationSemantics: Equatable, CustomStringConvertible {
    let pageIndex: Int
    let type: String
    let bounds: RectSemantics
    let contents: String
    let color: ColorSemantics
    let flags: Int
    let userName: String
    let modificationDateSecond: Int64
    let name: String
    let subject: String
    let quadPoints: [PointSemantics]

    init(annotation: PDFAnnotation, pageIndex: Int) {
        self.pageIndex = pageIndex
        type = annotation.type ?? ""
        bounds = RectSemantics(annotation.bounds)
        contents = type.caseInsensitiveCompare("Popup") == .orderedSame
            ? ""
            : annotation.contents ?? ""
        color = ColorSemantics(annotation.color)
        flags = (annotation.value(forAnnotationKey: .flags) as? NSNumber)?.intValue ?? 0
        userName = annotation.userName ?? ""
        modificationDateSecond = type.caseInsensitiveCompare("Popup") == .orderedSame
            ? 0
            : annotation.modificationDate.map {
                Int64($0.timeIntervalSinceReferenceDate.rounded(.towardZero))
            } ?? 0
        name = annotation.value(forAnnotationKey: .name) as? String ?? ""
        subject = annotation.value(forAnnotationKey: PDFAnnotationKey(rawValue: "/Subj")) as? String ?? ""
        quadPoints = (annotation.quadrilateralPoints ?? []).map {
            PointSemantics($0.pointValue)
        }
    }

    var description: String {
        [
            String(pageIndex), type, bounds.description, contents, color.description,
            String(flags), userName, String(modificationDateSecond), name, subject,
            quadPoints.map(\.description).joined(separator: ","),
        ].joined(separator: "|")
    }
}

private struct RectSemantics: Equatable, CustomStringConvertible {
    let x: Int64
    let y: Int64
    let width: Int64
    let height: Int64

    init(_ rect: CGRect) {
        x = Self.quantize(rect.origin.x)
        y = Self.quantize(rect.origin.y)
        width = Self.quantize(rect.width)
        height = Self.quantize(rect.height)
    }

    var description: String { "\(x),\(y),\(width),\(height)" }

    private static func quantize(_ value: CGFloat) -> Int64 {
        Int64((value * 1_000).rounded())
    }
}

private struct PointSemantics: Equatable, CustomStringConvertible {
    let x: Int64
    let y: Int64

    init(_ point: CGPoint) {
        x = Int64((point.x * 1_000).rounded())
        y = Int64((point.y * 1_000).rounded())
    }

    var description: String { "\(x),\(y)" }
}

private struct ColorSemantics: Equatable, CustomStringConvertible {
    let red: Int
    let green: Int
    let blue: Int
    let alpha: Int

    init(_ color: NSColor) {
        let rgb = color.usingColorSpace(.deviceRGB) ?? color
        red = Int((rgb.redComponent * 10_000).rounded())
        green = Int((rgb.greenComponent * 10_000).rounded())
        blue = Int((rgb.blueComponent * 10_000).rounded())
        alpha = Int((rgb.alphaComponent * 10_000).rounded())
    }

    var description: String { "\(red),\(green),\(blue),\(alpha)" }
}
