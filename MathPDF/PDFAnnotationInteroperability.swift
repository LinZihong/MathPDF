import AppKit
import Foundation
import PDFKit

enum PDFAnnotationInteroperabilityError: LocalizedError {
    case encryptedDocument
    case commentingNotAllowed
    case signedDocument
    case unsupportedAppendWriter
    case invalidSerializedDocument(String)

    var errorDescription: String? {
        switch self {
        case .encryptedDocument:
            "MathPDF can read this encrypted PDF, but cannot safely edit its annotations yet."
        case .commentingNotAllowed:
            "This PDF does not permit annotation changes."
        case .signedDocument:
            "MathPDF will not edit a signed PDF until signature-preserving saves are supported."
        case .unsupportedAppendWriter:
            "This version of PDFKit cannot safely preserve this PDF while saving annotations."
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
    private static let appendMode = PDFDocumentWriteOption(
        rawValue: "PDFDocumentWriteOption_UseAppendMode"
    )
    private static let noViewFlag = 1 << 5
    private static let restrictedAnnotationFlags = (1 << 6) | (1 << 7) | (1 << 9)

    static func documentEditingError(for document: PDFDocument, sourceData: Data) -> Error? {
        if document.isLocked || document.isEncrypted {
            return PDFAnnotationInteroperabilityError.encryptedDocument
        }
        if !document.allowsCommenting {
            return PDFAnnotationInteroperabilityError.commentingNotAllowed
        }
        if sourceData.range(of: Data("/ByteRange".utf8)) != nil {
            return PDFAnnotationInteroperabilityError.signedDocument
        }
        return nil
    }

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
            guard let state = states[identifier] else { continue }
            setRawFlags(state.flags | noViewFlag, on: popup)
            popup.isOpen = false
        }
    }

    static func preparePopupGraphsForSerialization(
        in document: PDFDocument,
        states: [ObjectIdentifier: PDFPopupDiskState]
    ) {
        let pagePopups = popupAnnotations(in: document)
        for popup in pagePopups {
            let state = states[ObjectIdentifier(popup)] ?? PDFPopupDiskState(
                flags: rawFlags(of: popup) & ~noViewFlag,
                isOpen: false
            )
            setRawFlags(state.flags, on: popup)
            popup.isOpen = state.isOpen
        }

        // PDFKit's append writer is sensitive to presentation-flag and color
        // mutations. Rebuilding each reciprocal edge twice is deliberate: it
        // prevents the writer from retaining a stale internal annotation clone.
        for owner in ownerAnnotations(in: document) {
            guard let popup = owner.popup, popup.page === owner.page else { continue }
            owner.popup = nil
            owner.popup = popup
            owner.popup = nil
            owner.popup = popup
            _ = popup.setValue(owner, forAnnotationKey: .parent)
        }
    }

    static func serializedAppend(
        document: PDFDocument,
        originalData: Data
    ) throws -> Data {
        let expected = DocumentSemantics(document: document)
        guard let candidate = document.dataRepresentation(options: [appendMode: true]) else {
            throw PDFAnnotationInteroperabilityError.unsupportedAppendWriter
        }
        try validate(
            candidate: candidate,
            originalData: originalData,
            expected: expected
        )
        return candidate
    }

    static func inferUniquePopupCompanion(for owner: PDFAnnotation) -> PDFAnnotation? {
        guard
            owner.type?.caseInsensitiveCompare("Highlight") == .orderedSame,
            let page = owner.page
        else { return nil }

        let candidates = page.annotations.filter { annotation in
            guard annotation.type?.caseInsensitiveCompare("Popup") == .orderedSame else {
                return false
            }
            guard annotationColor(annotation) == annotationColor(owner) else { return false }
            let expected = popupBounds(for: owner, on: page)
            return approximatelyEqual(annotation.bounds, expected, tolerance: 1.25)
        }
        guard candidates.count == 1, let popup = candidates.first else { return nil }
        let alreadyOwned = page.annotations.contains { annotation in
            annotation !== owner && annotation.popup === popup
        }
        return alreadyOwned ? nil : popup
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
        page.addAnnotation(popup)
        owner.popup = popup
        _ = popup.setValue(owner, forAnnotationKey: .parent)
        return popup
    }

    static func attach(_ popup: PDFAnnotation, to owner: PDFAnnotation) {
        let contents = owner.contents
        owner.popup = nil
        owner.contents = contents
        owner.popup = popup
        _ = popup.setValue(owner, forAnnotationKey: .parent)
    }

    static func detachPopup(from owner: PDFAnnotation) -> PDFAnnotation? {
        guard let popup = owner.popup else { return nil }
        let contents = owner.contents
        owner.popup = nil
        owner.contents = contents
        popup.page?.removeAnnotation(popup)
        return popup
    }

    static func updateColor(
        of owner: PDFAnnotation,
        to color: NSColor,
        popupStates: inout [ObjectIdentifier: PDFPopupDiskState]
    ) {
        let popup = owner.popup
        let contents = owner.contents
        owner.popup = nil
        owner.contents = contents
        owner.color = color
        owner.removeValue(forAnnotationKey: .appearanceDictionary)
        if let popup {
            popup.color = color
            popup.removeValue(forAnnotationKey: .appearanceDictionary)
            owner.popup = popup
            _ = popup.setValue(owner, forAnnotationKey: .parent)
            if case nil = popupStates[ObjectIdentifier(popup)] {
                popupStates[ObjectIdentifier(popup)] = PDFPopupDiskState(
                    flags: rawFlags(of: popup) & ~noViewFlag,
                    isOpen: false
                )
            }
        }
    }

    static func annotationFingerprint(_ annotation: PDFAnnotation, pageIndex: Int) -> String {
        AnnotationSemantics(annotation: annotation, pageIndex: pageIndex).description
    }

    static func validate(serializedData: Data, against expectedDocument: PDFDocument) throws {
        guard let reloaded = PDFDocument(data: serializedData) else {
            throw PDFAnnotationInteroperabilityError.invalidSerializedDocument(
                "the serialized PDF could not be reopened"
            )
        }
        let expected = DocumentSemantics(document: expectedDocument)
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

    private static func validate(
        candidate: Data,
        originalData: Data,
        expected: DocumentSemantics
    ) throws {
        guard candidate.count >= originalData.count, candidate.starts(with: originalData) else {
            throw PDFAnnotationInteroperabilityError.invalidSerializedDocument(
                "PDFKit did not produce an incremental append"
            )
        }
        guard let reloaded = PDFDocument(data: candidate) else {
            throw PDFAnnotationInteroperabilityError.invalidSerializedDocument(
                "the serialized PDF could not be reopened"
            )
        }
        let actual = DocumentSemantics(document: reloaded)
        guard expected.pageCount == actual.pageCount else {
            throw PDFAnnotationInteroperabilityError.invalidSerializedDocument("page count changed")
        }
        guard expected.pages == actual.pages else {
            let reason = expected.firstPageDifference(from: actual)
                ?? "page geometry or annotation semantics changed"
            throw PDFAnnotationInteroperabilityError.invalidSerializedDocument(
                reason
            )
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

    private static func ownerAnnotations(in document: PDFDocument) -> [PDFAnnotation] {
        (0..<document.pageCount).flatMap { pageIndex in
            document.page(at: pageIndex)?.annotations.filter {
                $0.type?.caseInsensitiveCompare("Popup") != .orderedSame && $0.popup != nil
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

    private static func setRawFlags(_ flags: Int, on annotation: PDFAnnotation) {
        _ = annotation.setValue(NSNumber(value: flags), forAnnotationKey: .flags)
    }

    private static func annotationColor(_ annotation: PDFAnnotation) -> ColorSemantics {
        ColorSemantics(annotation.color)
    }

    private static func approximatelyEqual(
        _ lhs: CGRect,
        _ rhs: CGRect,
        tolerance: CGFloat
    ) -> Bool {
        abs(lhs.minX - rhs.minX) <= tolerance
            && abs(lhs.minY - rhs.minY) <= tolerance
            && abs(lhs.width - rhs.width) <= tolerance
            && abs(lhs.height - rhs.height) <= tolerance
    }
}

private struct DocumentSemantics {
    let pageCount: Int
    let pages: [PageSemantics]
    let keywords: [String]

    init(document: PDFDocument) {
        pageCount = document.pageCount
        pages = (0..<document.pageCount).compactMap { pageIndex in
            document.page(at: pageIndex).map { PageSemantics(page: $0, index: pageIndex) }
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

    init(page: PDFPage, index: Int) {
        rotation = page.rotation
        mediaBox = RectSemantics(page.bounds(for: .mediaBox))
        cropBox = RectSemantics(page.bounds(for: .cropBox))
        bleedBox = RectSemantics(page.bounds(for: .bleedBox))
        trimBox = RectSemantics(page.bounds(for: .trimBox))
        artBox = RectSemantics(page.bounds(for: .artBox))
        annotations = page.annotations
            .map { AnnotationSemantics(annotation: $0, pageIndex: index) }
            .sorted { $0.description < $1.description }

        let pageAnnotations = page.annotations
        let pageAnnotationIDs = Set(pageAnnotations.map(ObjectIdentifier.init))
        let indexByID = Dictionary(uniqueKeysWithValues: pageAnnotations.enumerated().map {
            (ObjectIdentifier($0.element), $0.offset)
        })
        var owners: [String] = []
        var edges: [PopupEdgeSemantics] = []
        var ownedPopupIDs: Set<ObjectIdentifier> = []
        for (ownerIndex, owner) in pageAnnotations.enumerated() where
            owner.type?.caseInsensitiveCompare("Popup") != .orderedSame
        {
            guard
                let popup = owner.popup,
                pageAnnotationIDs.contains(ObjectIdentifier(popup)),
                let popupIndex = indexByID[ObjectIdentifier(popup)],
                let parent = popup.value(forAnnotationKey: .parent) as? PDFAnnotation,
                parent === owner
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
    let richContents: String
    let quadPoints: [PointSemantics]

    init(annotation: PDFAnnotation, pageIndex: Int) {
        self.pageIndex = pageIndex
        type = annotation.type ?? ""
        bounds = RectSemantics(annotation.bounds)
        contents = type.caseInsensitiveCompare("Popup") == .orderedSame
            ? ""
            : annotation.contents ?? ""
        color = ColorSemantics(annotation.color)
        let storedFlags = (annotation.value(forAnnotationKey: .flags) as? NSNumber)?.intValue ?? 0
        flags = type.caseInsensitiveCompare("Popup") == .orderedSame
            ? storedFlags & ~(1 << 5)
            : storedFlags
        userName = annotation.userName ?? ""
        modificationDateSecond = annotation.modificationDate.map {
            Int64($0.timeIntervalSinceReferenceDate.rounded(.towardZero))
        } ?? 0
        name = annotation.value(forAnnotationKey: .name) as? String ?? ""
        subject = annotation.value(forAnnotationKey: PDFAnnotationKey(rawValue: "/Subj")) as? String ?? ""
        richContents = annotation.value(forAnnotationKey: PDFAnnotationKey(rawValue: "/RC")) as? String ?? ""
        quadPoints = (annotation.quadrilateralPoints ?? []).map {
            PointSemantics($0.pointValue)
        }
    }

    var description: String {
        [
            String(pageIndex), type, bounds.description, contents, color.description,
            String(flags), userName, String(modificationDateSecond), name, subject, richContents,
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
