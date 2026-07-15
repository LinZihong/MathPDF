import AppKit
import CryptoKit
import Foundation
import PDFKit

enum PDFPersistenceError: LocalizedError {
    case unavailable(String)
    case sourceChanged
    case mappingFailed(String)
    case serializationFailed(String)

    var errorDescription: String? {
        switch self {
        case let .unavailable(reason):
            reason
        case .sourceChanged:
            "MathPDF refused to save because the source PDF changed unexpectedly."
        case let .mappingFailed(reason):
            "MathPDF cannot safely map this PDF's annotations: \(reason)"
        case let .serializationFailed(reason):
            "MathPDF refused to save because PDF validation failed: \(reason)"
        }
    }
}

private struct PDFPersistenceInspection: Decodable {
    let editable: Bool
    let reason: String
    let encrypted: Bool
    let signed: Bool
    let linearized: Bool
    let warnings: Bool
    let pages: [Page]

    struct Page: Decodable {
        let index: Int
        let object: Int
        let generation: Int
        let annotations: [Annotation]
    }

    struct Annotation: Decodable {
        let slot: Int
        let object: Int
        let generation: Int
        let subtype: String
        let nm: String
        let fingerprint: String
        let flags: Int
        let open: Bool
        let hasAppearance: Bool
        let popup: Reference?
        let parent: Reference?
    }

    struct Reference: Decodable, Hashable {
        let object: Int
        let generation: Int
    }
}

private struct PDFAnnotationOrigin: Encodable, Hashable {
    let pageIndex: Int
    let pageObject: Int
    let pageGeneration: Int
    let slot: Int
    let object: Int
    let generation: Int
    let subtype: String
    let fingerprint: String
}

private enum PDFAnnotationDirtyField: String, Encodable, Hashable {
    case appearance = "AP"
    case color = "C"
    case contents = "Contents"
    case flags = "F"
    case iconName = "Name"
    case modified = "M"
    case name = "NM"
    case open = "Open"
    case parent = "Parent"
    case popup = "Popup"
    case quadrilateralPoints = "QuadPoints"
    case rectangle = "Rect"
    case richContents = "RC"
    case subject = "Subj"
    case userName = "T"
}

private struct PDFAnnotationWriteRequest: Encodable {
    let sourceSHA256: String
    let annotations: [Annotation]
    let edges: [Edge]
    let metadata: Metadata

    struct Annotation: Encodable {
        let id: UUID
        let origin: PDFAnnotationOrigin?
        let pageIndex: Int
        let subtype: String
        let deleted: Bool
        let dirty: [PDFAnnotationDirtyField]
        let contents: String?
        let modificationDate: Double?
        let rectangle: [Double]
        let quadrilateralPoints: [Double]
        let color: [Double]
        let flags: Int
        let open: Bool
        let name: String
        let iconName: String?
        let userName: String?
        let subject: String?
    }

    struct Edge: Encodable, Hashable {
        let owner: UUID
        let popup: UUID
    }

    struct Metadata: Encodable {
        let preamble: String
        let dirty: Bool
    }
}

final class PDFAnnotationPersistenceSession {
    struct PopupPresentationState {
        let flags: Int
        let isOpen: Bool
    }

    private struct Binding {
        let id: UUID
        let origin: PDFAnnotationOrigin?
        let hasOriginalAppearance: Bool
    }

    private let sourceData: Data
    private let sourceSHA256: String
    private(set) var editingError: Error?
    private var bindingByObject: [ObjectIdentifier: Binding] = [:]
    private var annotationByID: [UUID: PDFAnnotation] = [:]
    private var dirtyFields: [UUID: Set<PDFAnnotationDirtyField>] = [:]
    private var popupEdges: Set<PDFAnnotationWriteRequest.Edge> = []
    private var deletedIDs: Set<UUID> = []
    private var detachedPopupByOwner: [UUID: PDFAnnotation] = [:]
    private var metadataDirty = false

    init(sourceData: Data, document: PDFDocument) {
        self.sourceData = sourceData
        sourceSHA256 = SHA256.hash(data: sourceData).map { String(format: "%02x", $0) }.joined()

        do {
            let inspectionData = try Self.inspect(sourceData)
            let inspection = try JSONDecoder().decode(
                PDFPersistenceInspection.self,
                from: inspectionData
            )
            guard inspection.editable else {
                editingError = PDFPersistenceError.unavailable(inspection.reason)
                return
            }
            try bind(document: document, to: inspection)
            repairOneSidedRuntimeEdges(using: inspection, document: document)
        } catch {
            editingError = error
        }
    }

    var isEditable: Bool { editingError == nil }

    func canEdit(_ annotation: PDFAnnotation) -> Bool {
        guard editingError == nil else { return false }
        guard Self.annotationAllowsEditing(annotation) else { return false }
        if let popup = annotation.popup, !Self.annotationAllowsEditing(popup) {
            return false
        }
        return true
    }

    func canChangeColor(of annotation: PDFAnnotation) -> Bool {
        guard canEdit(annotation) else { return false }
        guard let ownerBinding = binding(for: annotation) else { return false }
        if ownerBinding.hasOriginalAppearance || annotation.value(forAnnotationKey: .appearanceDictionary) != nil {
            return false
        }
        if let popup = annotation.popup,
           let popupBinding = binding(for: popup),
           popupBinding.hasOriginalAppearance || popup.value(forAnnotationKey: .appearanceDictionary) != nil {
            return false
        }
        return true
    }

    @discardableResult
    func registerCreated(_ annotation: PDFAnnotation) -> UUID {
        if let binding = binding(for: annotation) {
            return binding.id
        }
        let id = UUID()
        let binding = Binding(id: id, origin: nil, hasOriginalAppearance: false)
        bindingByObject[ObjectIdentifier(annotation)] = binding
        annotationByID[id] = annotation
        deletedIDs.remove(id)
        dirtyFields[id] = Set(PDFAnnotationDirtyField.allForCreation)
        ensureDurableName(on: annotation, binding: binding)
        return id
    }

    func markContentsChanged(on annotation: PDFAnnotation) {
        let binding = ensureBinding(for: annotation)
        mark(binding, [.contents, .modified, .richContents, .name])
    }

    func markColorChanged(on annotation: PDFAnnotation) {
        let binding = ensureBinding(for: annotation)
        mark(binding, [.color, .modified, .name])
    }

    func markPopupEdge(owner: PDFAnnotation, popup: PDFAnnotation) {
        let ownerBinding = ensureBinding(for: owner)
        let popupBinding = ensureBinding(for: popup)
        popupEdges = Set(popupEdges.filter {
            $0.owner != ownerBinding.id && $0.popup != popupBinding.id
        })
        popupEdges.insert(.init(owner: ownerBinding.id, popup: popupBinding.id))
        mark(ownerBinding, [.popup, .name])
        mark(popupBinding, [.parent, .contents, .modified, .name])
        deletedIDs.remove(popupBinding.id)
        detachedPopupByOwner.removeValue(forKey: ownerBinding.id)
    }

    func detachPopup(_ popup: PDFAnnotation, from owner: PDFAnnotation) {
        let ownerBinding = ensureBinding(for: owner)
        let popupBinding = ensureBinding(for: popup)
        popupEdges.remove(.init(owner: ownerBinding.id, popup: popupBinding.id))
        detachedPopupByOwner[ownerBinding.id] = popup
        deletedIDs.insert(popupBinding.id)
        mark(ownerBinding, [.popup])
        mark(popupBinding, [.parent])
    }

    func takeDetachedPopup(for owner: PDFAnnotation) -> PDFAnnotation? {
        let ownerBinding = ensureBinding(for: owner)
        guard let popup = detachedPopupByOwner.removeValue(forKey: ownerBinding.id) else {
            return nil
        }
        if let popupBinding = binding(for: popup) {
            deletedIDs.remove(popupBinding.id)
        }
        return popup
    }

    func markDeleted(_ annotation: PDFAnnotation) {
        let binding = ensureBinding(for: annotation)
        deletedIDs.insert(binding.id)
        popupEdges = Set(popupEdges.filter {
            $0.owner != binding.id && $0.popup != binding.id
        })
    }

    func markRestored(_ annotation: PDFAnnotation) {
        let binding = ensureBinding(for: annotation)
        deletedIDs.remove(binding.id)
    }

    func markMetadataChanged() {
        metadataDirty = true
    }

    func popupPresentationState(for popup: PDFAnnotation) -> PopupPresentationState {
        PopupPresentationState(
            flags: Self.rawFlags(of: popup),
            isOpen: popup.isOpen
        )
    }

    func serializedData(document: PDFDocument, preamble: String) throws -> Data {
        guard editingError == nil else { throw editingError! }
        let request = try makeRequest(document: document, preamble: preamble)
        let requestData = try JSONEncoder().encode(request)
        var bridgeError: NSError?
        guard let result = MPPDFSerializeAnnotationGraph(
            sourceData,
            requestData,
            &bridgeError
        ) else {
            throw bridgeError ?? PDFPersistenceError.serializationFailed("The qpdf writer returned no data.")
        }
        return result
    }

    private static func inspect(_ data: Data) throws -> Data {
        var bridgeError: NSError?
        guard let result = MPPDFInspectSource(data, &bridgeError) else {
            throw bridgeError ?? PDFPersistenceError.unavailable("qpdf could not inspect this PDF.")
        }
        return result
    }

    private func bind(document: PDFDocument, to inspection: PDFPersistenceInspection) throws {
        guard document.pageCount == inspection.pages.count else {
            throw PDFPersistenceError.mappingFailed("PDFKit and qpdf disagree on the page count.")
        }

        var bindingByReference: [PDFPersistenceInspection.Reference: Binding] = [:]
        var inventoryByReference: [PDFPersistenceInspection.Reference: PDFPersistenceInspection.Annotation] = [:]

        for pageInventory in inspection.pages {
            guard let page = document.page(at: pageInventory.index) else {
                throw PDFPersistenceError.mappingFailed("PDFKit omitted page \(pageInventory.index + 1).")
            }
            let annotations = page.annotations
            guard annotations.count == pageInventory.annotations.count else {
                throw PDFPersistenceError.mappingFailed(
                    "PDFKit and qpdf disagree on page \(pageInventory.index + 1)'s annotation count."
                )
            }

            for (annotation, inventory) in zip(annotations, pageInventory.annotations) {
                guard annotation.type?.caseInsensitiveCompare(inventory.subtype) == .orderedSame else {
                    throw PDFPersistenceError.mappingFailed(
                        "PDFKit reordered or retyped an annotation on page \(pageInventory.index + 1)."
                    )
                }
                let binding = Binding(
                    id: UUID(),
                    origin: PDFAnnotationOrigin(
                        pageIndex: pageInventory.index,
                        pageObject: pageInventory.object,
                        pageGeneration: pageInventory.generation,
                        slot: inventory.slot,
                        object: inventory.object,
                        generation: inventory.generation,
                        subtype: inventory.subtype,
                        fingerprint: inventory.fingerprint
                    ),
                    hasOriginalAppearance: inventory.hasAppearance
                )
                bindingByObject[ObjectIdentifier(annotation)] = binding
                annotationByID[binding.id] = annotation
                let reference = PDFPersistenceInspection.Reference(
                    object: inventory.object,
                    generation: inventory.generation
                )
                bindingByReference[reference] = binding
                inventoryByReference[reference] = inventory
            }
        }

        // Import the raw graph once. From this point onward the session owns
        // disk relationships; PDFKit's presentation graph is not consulted to
        // reconstruct persistence intent at save time.
        for pageInventory in inspection.pages {
            for inventory in pageInventory.annotations {
                let reference = PDFPersistenceInspection.Reference(
                    object: inventory.object,
                    generation: inventory.generation
                )
                guard let binding = bindingByReference[reference] else { continue }

                if let popupReference = inventory.popup,
                   let popupBinding = bindingByReference[popupReference] {
                    popupEdges.insert(.init(owner: binding.id, popup: popupBinding.id))
                    if inventoryByReference[popupReference]?.parent == nil {
                        dirtyFields[popupBinding.id, default: []].insert(.parent)
                    }
                }

                if inventory.subtype.caseInsensitiveCompare("Popup") == .orderedSame,
                   let parentReference = inventory.parent,
                   let ownerBinding = bindingByReference[parentReference] {
                    popupEdges.insert(.init(owner: ownerBinding.id, popup: binding.id))
                    if inventoryByReference[parentReference]?.popup == nil {
                        dirtyFields[ownerBinding.id, default: []].insert(.popup)
                    }
                }
            }
        }
    }

    private func repairOneSidedRuntimeEdges(
        using inspection: PDFPersistenceInspection,
        document: PDFDocument
    ) {
        var annotationByReference: [PDFPersistenceInspection.Reference: PDFAnnotation] = [:]
        for pageInventory in inspection.pages {
            guard let page = document.page(at: pageInventory.index) else { continue }
            for (annotation, inventory) in zip(page.annotations, pageInventory.annotations) {
                annotationByReference[.init(
                    object: inventory.object,
                    generation: inventory.generation
                )] = annotation
            }
        }

        for pageInventory in inspection.pages {
            guard let page = document.page(at: pageInventory.index) else { continue }
            for (annotation, inventory) in zip(page.annotations, pageInventory.annotations) {
                if let popupReference = inventory.popup,
                   let popup = annotationByReference[popupReference] {
                    annotation.popup = popup
                    _ = popup.setValue(annotation, forAnnotationKey: .parent)
                } else if inventory.subtype.caseInsensitiveCompare("Popup") == .orderedSame,
                          let parentReference = inventory.parent,
                          let owner = annotationByReference[parentReference] {
                    owner.popup = annotation
                    _ = annotation.setValue(owner, forAnnotationKey: .parent)
                }
            }
        }
    }

    private func makeRequest(
        document: PDFDocument,
        preamble: String
    ) throws -> PDFAnnotationWriteRequest {
        var liveAnnotations: [(annotation: PDFAnnotation, binding: Binding, pageIndex: Int)] = []
        var currentIDs: Set<UUID> = []
        var records: [PDFAnnotationWriteRequest.Annotation] = []

        // PDFKit automatically inserts a Popup companion after a Text
        // annotation. Bind the complete page graph before reading any edges so
        // ownership never depends on whether the owner or popup appears first
        // in the page's /Annots array.
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            for annotation in page.annotations {
                guard let binding = binding(for: annotation) else {
                    throw PDFPersistenceError.mappingFailed(
                        "PDFKit exposed an untracked \(annotation.type ?? "annotation") on page \(pageIndex + 1)."
                    )
                }
                currentIDs.insert(binding.id)
                liveAnnotations.append((annotation, binding, pageIndex))
            }
        }

        for item in liveAnnotations {
            records.append(record(
                annotation: item.annotation,
                binding: item.binding,
                pageIndex: item.pageIndex,
                deleted: false
            ))
        }

        for id in deletedIDs where !currentIDs.contains(id) {
            guard let annotation = annotationByID[id], let binding = binding(for: annotation) else {
                continue
            }
            let pageIndex = binding.origin?.pageIndex ?? 0
            records.append(record(
                annotation: annotation,
                binding: binding,
                pageIndex: pageIndex,
                deleted: true
            ))
        }

        return PDFAnnotationWriteRequest(
            sourceSHA256: sourceSHA256,
            annotations: records.sorted { $0.id.uuidString < $1.id.uuidString },
            edges: popupEdges
                .filter {
                    currentIDs.contains($0.owner)
                        && currentIDs.contains($0.popup)
                        && !deletedIDs.contains($0.owner)
                        && !deletedIDs.contains($0.popup)
                }
                .sorted { $0.owner.uuidString < $1.owner.uuidString },
            metadata: .init(preamble: preamble, dirty: metadataDirty)
        )
    }

    private func record(
        annotation: PDFAnnotation,
        binding: Binding,
        pageIndex: Int,
        deleted: Bool
    ) -> PDFAnnotationWriteRequest.Annotation {
        let bounds = annotation.bounds
        let quadrilateralPoints = (annotation.quadrilateralPoints ?? []).flatMap { value in
            let point = value.pointValue
            return [Double(bounds.minX + point.x), Double(bounds.minY + point.y)]
        }
        let color = annotation.color.usingColorSpace(.deviceRGB) ?? annotation.color
        let components = [
            Double(color.redComponent),
            Double(color.greenComponent),
            Double(color.blueComponent),
        ]
        return PDFAnnotationWriteRequest.Annotation(
            id: binding.id,
            origin: binding.origin,
            pageIndex: pageIndex,
            subtype: annotation.type ?? "",
            deleted: deleted,
            dirty: Array(dirtyFields[binding.id] ?? []).sorted { $0.rawValue < $1.rawValue },
            contents: annotation.contents,
            modificationDate: annotation.modificationDate?.timeIntervalSince1970,
            rectangle: [
                Double(bounds.minX), Double(bounds.minY),
                Double(bounds.maxX), Double(bounds.maxY),
            ],
            quadrilateralPoints: quadrilateralPoints,
            color: components,
            flags: popupDiskFlags(for: annotation),
            open: popupDiskOpenState(for: annotation),
            name: durableName(of: annotation) ?? binding.id.uuidString,
            iconName: annotation.value(forAnnotationKey: .name) as? String,
            userName: annotation.userName,
            subject: annotation.value(forAnnotationKey: PDFAnnotationKey(rawValue: "/Subj")) as? String
        )
    }

    private func binding(for annotation: PDFAnnotation) -> Binding? {
        bindingByObject[ObjectIdentifier(annotation)]
    }

    private func ensureBinding(for annotation: PDFAnnotation) -> Binding {
        if let binding = binding(for: annotation) {
            return binding
        }
        _ = registerCreated(annotation)
        return bindingByObject[ObjectIdentifier(annotation)]!
    }

    private func mark(_ binding: Binding, _ fields: Set<PDFAnnotationDirtyField>) {
        dirtyFields[binding.id, default: []].formUnion(fields)
        if let annotation = annotationByID[binding.id] {
            ensureDurableName(on: annotation, binding: binding)
        }
    }

    private func ensureDurableName(on annotation: PDFAnnotation, binding: Binding) {
        if durableName(of: annotation)?.isEmpty != false {
            _ = annotation.setValue(
                binding.id.uuidString,
                forAnnotationKey: PDFAnnotationKey(rawValue: "/NM")
            )
            dirtyFields[binding.id, default: []].insert(.name)
        }
    }

    private func durableName(of annotation: PDFAnnotation) -> String? {
        annotation.value(forAnnotationKey: PDFAnnotationKey(rawValue: "/NM")) as? String
    }

    private func popupDiskFlags(for annotation: PDFAnnotation) -> Int {
        let flags = Self.rawFlags(of: annotation)
        return annotation.type?.caseInsensitiveCompare("Popup") == .orderedSame
            ? flags & ~(1 << 5)
            : flags
    }

    private func popupDiskOpenState(for annotation: PDFAnnotation) -> Bool {
        annotation.type?.caseInsensitiveCompare("Popup") == .orderedSame ? false : annotation.isOpen
    }

    private static func annotationAllowsEditing(_ annotation: PDFAnnotation) -> Bool {
        let restrictedFlags = (1 << 6) | (1 << 7) | (1 << 9)
        return rawFlags(of: annotation) & restrictedFlags == 0
    }

    private static func rawFlags(of annotation: PDFAnnotation) -> Int {
        (annotation.value(forAnnotationKey: .flags) as? NSNumber)?.intValue ?? 0
    }
}

private extension PDFAnnotationDirtyField {
    static let allForCreation: [Self] = [
        .color, .contents, .flags, .iconName, .modified, .name, .open,
        .quadrilateralPoints, .rectangle, .subject, .userName,
    ]
}
