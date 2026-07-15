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
        let rectangle: [Double]
        let color: [Double]
        let modificationDate: String
        let userName: String
        let subject: String
        let richContents: String
        let popupInferred: Bool
        let parentInferred: Bool
        let requiresPageInsertion: Bool
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
        let name: String?
        let iconName: String?
        let userName: String?
        let subject: String?
        let richContents: String?
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
        let originalColor: [Double]?
    }

    private enum OptionalStringState {
        case absent
        case value(String)

        var value: String? {
            switch self {
            case .absent: nil
            case let .value(value): value
            }
        }

        init(_ value: String?) {
            self = value.map(Self.value) ?? .absent
        }
    }

    private let sourceData: Data
    private let sourceSHA256: String
    private(set) var editingError: Error?
    private var bindingByObject: [ObjectIdentifier: Binding] = [:]
    private var annotationByID: [UUID: PDFAnnotation] = [:]
    private var dirtyFields: [UUID: Set<PDFAnnotationDirtyField>] = [:]
    private var popupEdges: Set<PDFAnnotationWriteRequest.Edge> = []
    private var importedPopupEdges: Set<PDFAnnotationWriteRequest.Edge> = []
    private var deletedIDs: Set<UUID> = []
    private var detachedPopupByOwner: [UUID: PDFAnnotation] = [:]
    // PDFKit's page graph is also its presentation graph. Popup companions
    // must remain in the persistence model without being handed to PDFView,
    // otherwise PDFKit can draw its own closed-note affordance beside
    // MathPDF's badge. This order is the logical `/Annots` order used by the
    // writer even while Popup objects are absent from `page.annotations`.
    private var annotationOrderByPage: [Int: [UUID]] = [:]
    private var popupColorComponentsByID: [UUID: [Double]] = [:]
    // PDFKit does not reliably surface an imported annotation's raw `/RC`
    // string. Keep the persistence value beside the binding so undo can restore
    // it exactly even when the in-memory PDFAnnotation drops it.
    private var richContentsByID: [UUID: OptionalStringState] = [:]
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
            importedPopupEdges = popupEdges
        } catch {
            editingError = error
        }
    }

    var isEditable: Bool { editingError == nil }

    func canEdit(_ annotation: PDFAnnotation) -> Bool {
        guard editingError == nil else { return false }
        guard Self.annotationAllowsEditing(annotation) else { return false }
        if let popup = popupCompanion(for: annotation), !Self.annotationAllowsEditing(popup) {
            return false
        }
        return true
    }

    func popupCompanion(for owner: PDFAnnotation) -> PDFAnnotation? {
        guard let ownerBinding = binding(for: owner) else { return nil }
        guard let edge = popupEdges.first(where: {
            $0.owner == ownerBinding.id && !deletedIDs.contains($0.popup)
        }) else { return nil }
        return annotationByID[edge.popup]
    }

    func popupColor(for popup: PDFAnnotation) -> NSColor {
        guard let binding = binding(for: popup),
              let components = popupColorComponentsByID[binding.id],
              components.count == 3 else { return popup.color }
        return NSColor(
            deviceRed: CGFloat(components[0]),
            green: CGFloat(components[1]),
            blue: CGFloat(components[2]),
            alpha: 1
        )
    }

    func logicalPopupEdges() -> [(owner: PDFAnnotation, popup: PDFAnnotation)] {
        popupEdges.compactMap { edge in
            guard
                !deletedIDs.contains(edge.owner),
                !deletedIDs.contains(edge.popup),
                let owner = annotationByID[edge.owner],
                let popup = annotationByID[edge.popup]
            else { return nil }
            return (owner: owner, popup: popup)
        }
    }

    func canChangeColor(of annotation: PDFAnnotation) -> Bool {
        guard canEdit(annotation) else { return false }
        guard annotation.type?.caseInsensitiveCompare("Highlight") == .orderedSame else {
            return false
        }
        return binding(for: annotation) != nil
    }

    @discardableResult
    func registerCreated(_ annotation: PDFAnnotation) -> UUID {
        if let binding = binding(for: annotation) {
            return binding.id
        }
        let id = UUID()
        let binding = Binding(
            id: id,
            origin: nil,
            hasOriginalAppearance: false,
            originalColor: nil
        )
        bindingByObject[ObjectIdentifier(annotation)] = binding
        annotationByID[id] = annotation
        deletedIDs.remove(id)
        dirtyFields[id] = Set(PDFAnnotationDirtyField.allForCreation)
        if annotation.type?.caseInsensitiveCompare("Popup") == .orderedSame,
           let components = Self.colorComponents(of: annotation.color) {
            popupColorComponentsByID[id] = components
        }
        ensureDurableName(on: annotation, binding: binding)
        return id
    }

    @discardableResult
    func registerCreated(_ annotation: PDFAnnotation, pageIndex: Int) -> UUID {
        let id = registerCreated(annotation)
        if annotationOrderByPage[pageIndex]?.contains(id) != true {
            annotationOrderByPage[pageIndex, default: []].append(id)
        }
        return id
    }

    /// Removes Popup companions and their owner pointers from PDFKit's live
    /// presentation graph while retaining objects, reciprocal edges, durable
    /// fields, and logical page order in this persistence session.
    func suppressPopupPresentation(in document: PDFDocument) {
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            for popup in page.annotations where
                popup.type?.caseInsensitiveCompare("Popup") == .orderedSame
            {
                let binding = ensureBinding(for: popup)
                if annotationOrderByPage[pageIndex]?.contains(binding.id) != true {
                    annotationOrderByPage[pageIndex, default: []].append(binding.id)
                }
                page.removeAnnotation(popup)
            }

            for owner in page.annotations where
                owner.type?.caseInsensitiveCompare("Popup") != .orderedSame
            {
                guard let popup = owner.popup else { continue }
                let contents = owner.contents
                let popupColor = popup.color
                owner.popup = nil
                owner.contents = contents
                popup.color = popupColor
                popup.removeValue(forAnnotationKey: .parent)
            }
        }

        // PDFKit can paint a closed-note marker from `owner.popup` even when
        // the Popup is absent from `page.annotations`. Persistence owns this
        // relationship, so the live viewer must not retain either direction.
        for edge in popupEdges {
            guard
                let owner = annotationByID[edge.owner],
                let popup = annotationByID[edge.popup]
            else { continue }
            if owner.popup === popup {
                let contents = owner.contents
                let popupColor = popup.color
                owner.popup = nil
                owner.contents = contents
                popup.color = popupColor
            }
            popup.removeValue(forAnnotationKey: .parent)
        }
    }

    func logicalAnnotationsByPage(in document: PDFDocument) -> [[PDFAnnotation]] {
        (0..<document.pageCount).map { pageIndex in
            let orderedIDs = annotationOrderByPage[pageIndex] ?? []
            return orderedIDs.compactMap { id in
                guard !deletedIDs.contains(id) else { return nil }
                return annotationByID[id]
            }
        }
    }

    func markContentsChanged(on annotation: PDFAnnotation) {
        let binding = ensureBinding(for: annotation)
        richContentsByID[binding.id] = .absent
        mark(binding, [.contents, .modified, .richContents, .name])
    }

    func richContents(of annotation: PDFAnnotation) -> String? {
        guard let binding = binding(for: annotation) else {
            return annotation.value(
                forAnnotationKey: PDFAnnotationKey(rawValue: "/RC")
            ) as? String
        }
        return richContentsByID[binding.id]?.value
    }

    func restoreRichContents(_ value: String?, on annotation: PDFAnnotation) {
        let binding = ensureBinding(for: annotation)
        richContentsByID[binding.id] = OptionalStringState(value)
    }

    /// Restoring an undo snapshot must be able to remove an `/NM` that did not
    /// exist before the edit. Unlike a fresh edit, this path therefore records
    /// the current identity verbatim instead of inventing a replacement name.
    func markContentsStateRestored(on annotation: PDFAnnotation) {
        let binding = ensureBinding(for: annotation)
        dirtyFields[binding.id, default: []].formUnion([
            .contents, .modified, .richContents, .name,
        ])
    }

    func markColorChanged(on annotation: PDFAnnotation) {
        let binding = ensureBinding(for: annotation)
        var fields: Set<PDFAnnotationDirtyField> = [.color, .modified, .name]
        updateAppearanceDirtyField(for: annotation, binding: binding, fields: &fields)
        mark(binding, fields)
    }

    func markPopupColorChanged(on annotation: PDFAnnotation, to color: NSColor) {
        let binding = ensureBinding(for: annotation)
        popupColorComponentsByID[binding.id] = Self.colorComponents(of: color)
        var fields: Set<PDFAnnotationDirtyField> = [.color]
        if binding.hasOriginalAppearance {
            if Self.colorsMatch(binding.originalColor, popupColorComponentsByID[binding.id]) {
                dirtyFields[binding.id]?.remove(.appearance)
            } else {
                fields.insert(.appearance)
            }
        }
        mark(binding, fields)
    }

    private func updateAppearanceDirtyField(
        for annotation: PDFAnnotation,
        binding: Binding,
        fields: inout Set<PDFAnnotationDirtyField>
    ) {
        if binding.hasOriginalAppearance {
            if Self.colorsMatch(binding.originalColor, Self.colorComponents(of: annotation.color)) {
                dirtyFields[binding.id]?.remove(.appearance)
            } else {
                fields.insert(.appearance)
            }
        }
    }

    func markPopupEdge(owner: PDFAnnotation, popup: PDFAnnotation) {
        let ownerBinding = ensureBinding(for: owner)
        let popupBinding = ensureBinding(for: popup)
        let edge = PDFAnnotationWriteRequest.Edge(
            owner: ownerBinding.id,
            popup: popupBinding.id
        )
        let relationshipChanged = !popupEdges.contains(edge)
        popupEdges = Set(popupEdges.filter {
            $0.owner != ownerBinding.id && $0.popup != popupBinding.id
        })
        popupEdges.insert(edge)
        if relationshipChanged {
            // Relationship repair is intentionally narrower than companion
            // normalization. Imported Popup-private fields remain opaque unless
            // an explicit user action, such as recoloring, changes them.
            dirtyFields[ownerBinding.id, default: []].insert(.popup)
            dirtyFields[popupBinding.id, default: []].insert(.parent)
        }
        deletedIDs.remove(popupBinding.id)
        detachedPopupByOwner.removeValue(forKey: ownerBinding.id)
    }

    func isImported(_ annotation: PDFAnnotation) -> Bool {
        binding(for: annotation)?.origin != nil
    }

    func restorePopupEdge(owner: PDFAnnotation, popup: PDFAnnotation) {
        let ownerBinding = ensureBinding(for: owner)
        let popupBinding = ensureBinding(for: popup)
        let edge = PDFAnnotationWriteRequest.Edge(
            owner: ownerBinding.id,
            popup: popupBinding.id
        )
        guard importedPopupEdges.contains(edge) else {
            markPopupEdge(owner: owner, popup: popup)
            return
        }

        popupEdges = Set(popupEdges.filter {
            $0.owner != ownerBinding.id && $0.popup != popupBinding.id
        })
        popupEdges.insert(edge)
        deletedIDs.remove(popupBinding.id)
        detachedPopupByOwner.removeValue(forKey: ownerBinding.id)
    }

    func detachPopup(_ popup: PDFAnnotation, from owner: PDFAnnotation) {
        let ownerBinding = ensureBinding(for: owner)
        let popupBinding = ensureBinding(for: popup)
        popupEdges.remove(.init(owner: ownerBinding.id, popup: popupBinding.id))
        detachedPopupByOwner[ownerBinding.id] = popup
        deletedIDs.insert(popupBinding.id)
        dirtyFields[ownerBinding.id, default: []].insert(.popup)
        dirtyFields[popupBinding.id, default: []].insert(.parent)
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
        var annotationByReference: [PDFPersistenceInspection.Reference: PDFAnnotation] = [:]

        func bind(
            _ annotation: PDFAnnotation,
            to inventory: PDFPersistenceInspection.Annotation,
            on pageInventory: PDFPersistenceInspection.Page
        ) {
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
                hasOriginalAppearance: inventory.hasAppearance,
                originalColor: inventory.color.count == 3 ? inventory.color : nil
            )
            bindingByObject[ObjectIdentifier(annotation)] = binding
            annotationByID[binding.id] = annotation
            annotationOrderByPage[pageInventory.index, default: []].append(binding.id)
            richContentsByID[binding.id] = OptionalStringState(
                inventory.richContents.isEmpty ? nil : inventory.richContents
            )
            if inventory.subtype.caseInsensitiveCompare("Popup") == .orderedSame,
               inventory.color.count == 3 {
                popupColorComponentsByID[binding.id] = inventory.color
                // PDFKit may synthesize the owner's color for an attached
                // Popup instead of exposing the Popup's independent raw `/C`.
                // The hidden companion is persistence-owned, so restore its
                // actual color for exact color undo/redo bookkeeping.
                annotation.color = NSColor(
                    deviceRed: CGFloat(inventory.color[0]),
                    green: CGFloat(inventory.color[1]),
                    blue: CGFloat(inventory.color[2]),
                    alpha: 1
                )
            }
            let reference = PDFPersistenceInspection.Reference(
                object: inventory.object,
                generation: inventory.generation
            )
            bindingByReference[reference] = binding
            inventoryByReference[reference] = inventory
            annotationByReference[reference] = annotation
        }

        for pageInventory in inspection.pages {
            guard let page = document.page(at: pageInventory.index) else {
                throw PDFPersistenceError.mappingFailed("PDFKit omitted page \(pageInventory.index + 1).")
            }
            let annotations = page.annotations
            let pageAnnotations = pageInventory.annotations.filter { $0.slot >= 0 }
            guard annotations.count == pageAnnotations.count else {
                throw PDFPersistenceError.mappingFailed(
                    "PDFKit and qpdf disagree on page \(pageInventory.index + 1)'s annotation count."
                )
            }

            for (annotation, inventory) in zip(annotations, pageAnnotations) {
                guard annotation.type?.caseInsensitiveCompare(inventory.subtype) == .orderedSame else {
                    throw PDFPersistenceError.mappingFailed(
                        "PDFKit reordered or retyped an annotation on page \(pageInventory.index + 1)."
                    )
                }
                bind(annotation, to: inventory, on: pageInventory)
            }
        }

        // PDFKit exposes the proven 58x legacy companion through owner.popup,
        // but omits it from page.annotations. Bind that exact object to its raw
        // off-/Annots origin by adding it to the page only during import. The
        // presentation-suppression boundary immediately removes it again. The
        // source bytes remain the cached no-op snapshot; insertion is persisted
        // only when another document mutation makes a dirty save necessary.
        for pageInventory in inspection.pages {
            guard let page = document.page(at: pageInventory.index) else { continue }
            for inventory in pageInventory.annotations where inventory.requiresPageInsertion {
                guard
                    inventory.slot < 0,
                    inventory.subtype.caseInsensitiveCompare("Popup") == .orderedSame,
                    let parentReference = inventory.parent,
                    let owner = annotationByReference[parentReference],
                    let popup = owner.popup,
                    popup.type?.caseInsensitiveCompare("Popup") == .orderedSame
                else {
                    throw PDFPersistenceError.mappingFailed(
                        "PDFKit did not expose the proven off-page Popup on page \(pageInventory.index + 1)."
                    )
                }
                if !page.annotations.contains(where: { $0 === popup }) {
                    page.addAnnotation(popup)
                }
                Self.restoreDetachedPopupSemantics(popup, from: inventory)
                bind(popup, to: inventory, on: pageInventory)
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
                    if inventory.popupInferred {
                        dirtyFields[binding.id, default: []].insert(.popup)
                    }
                    if inventoryByReference[popupReference]?.parent == nil ||
                        inventoryByReference[popupReference]?.parentInferred == true {
                        dirtyFields[popupBinding.id, default: []].insert(.parent)
                    }
                }

                if inventory.subtype.caseInsensitiveCompare("Popup") == .orderedSame,
                   let parentReference = inventory.parent,
                   let ownerBinding = bindingByReference[parentReference] {
                    popupEdges.insert(.init(owner: ownerBinding.id, popup: binding.id))
                    if inventory.parentInferred {
                        dirtyFields[binding.id, default: []].insert(.parent)
                    }
                    if inventoryByReference[parentReference]?.popup == nil ||
                        inventoryByReference[parentReference]?.popupInferred == true {
                        dirtyFields[ownerBinding.id, default: []].insert(.popup)
                    }
                }
            }
        }

        // `popupEdges` is now the sole runtime owner of reciprocal Popup
        // relationships. Reattaching them to PDFKit would make its viewer draw
        // a second, native closed-note marker before MathPDF can intervene.
    }

    private func makeRequest(
        document: PDFDocument,
        preamble: String
    ) throws -> PDFAnnotationWriteRequest {
        var currentIDs: Set<UUID> = []
        var records: [PDFAnnotationWriteRequest.Annotation] = []
        var visibleIDsByPage: [Int: [UUID]] = [:]
        var visiblePageByID: [UUID: Int] = [:]
        var logicalPageByID: [UUID: Int] = [:]

        for (pageIndex, orderedIDs) in annotationOrderByPage {
            for id in orderedIDs {
                guard logicalPageByID.updateValue(pageIndex, forKey: id) == nil else {
                    throw PDFPersistenceError.mappingFailed(
                        "A tracked annotation belongs to more than one logical page."
                    )
                }
            }
        }

        // Visible annotations come from PDFKit. Popup companions deliberately
        // do not: they live in `annotationOrderByPage` so PDFView cannot draw a
        // second affordance. Validate the two graphs before reconciling their
        // ordering; a direct PDFKit removal or cross-page move must fail closed
        // instead of resurrecting or duplicating an annotation on disk.
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            for annotation in page.annotations {
                guard let binding = binding(for: annotation) else {
                    throw PDFPersistenceError.mappingFailed(
                        "PDFKit exposed an untracked \(annotation.type ?? "annotation") on page \(pageIndex + 1)."
                    )
                }
                guard annotation.type?.caseInsensitiveCompare("Popup") != .orderedSame else {
                    throw PDFPersistenceError.mappingFailed(
                        "A Popup companion re-entered PDFKit's presentation graph on page \(pageIndex + 1)."
                    )
                }
                guard !deletedIDs.contains(binding.id) else {
                    throw PDFPersistenceError.mappingFailed(
                        "A deleted annotation re-entered PDFKit's presentation graph on page \(pageIndex + 1)."
                    )
                }
                guard let logicalPage = logicalPageByID[binding.id] else {
                    throw PDFPersistenceError.mappingFailed(
                        "A tracked \(annotation.type ?? "annotation") has no logical page."
                    )
                }
                guard logicalPage == pageIndex else {
                    throw PDFPersistenceError.mappingFailed(
                        "A tracked \(annotation.type ?? "annotation") moved from page \(logicalPage + 1) to page \(pageIndex + 1) outside MathPDF's save model."
                    )
                }
                guard visiblePageByID.updateValue(pageIndex, forKey: binding.id) == nil else {
                    throw PDFPersistenceError.mappingFailed(
                        "A tracked annotation appears more than once in PDFKit's presentation graph."
                    )
                }
                visibleIDsByPage[pageIndex, default: []].append(binding.id)
            }
        }

        for pageIndex in 0..<document.pageCount {
            let logicalOrder = annotationOrderByPage[pageIndex] ?? []
            let expectedVisibleIDs = logicalOrder.filter { id in
                guard !deletedIDs.contains(id), let annotation = annotationByID[id] else {
                    return false
                }
                return annotation.type?.caseInsensitiveCompare("Popup") != .orderedSame
            }
            let visibleIDs = visibleIDsByPage[pageIndex] ?? []
            guard Set(expectedVisibleIDs) == Set(visibleIDs),
                  expectedVisibleIDs.count == visibleIDs.count else {
                throw PDFPersistenceError.mappingFailed(
                    "PDFKit's visible annotation set changed outside MathPDF on page \(pageIndex + 1)."
                )
            }

            // `/Annots` order controls painting and hit testing. Replace only
            // the live non-Popup slots with PDFKit's current visible order;
            // hidden Popup and deleted slots retain their durable positions.
            var visibleIterator = visibleIDs.makeIterator()
            annotationOrderByPage[pageIndex] = logicalOrder.map { id in
                guard !deletedIDs.contains(id),
                      let annotation = annotationByID[id],
                      annotation.type?.caseInsensitiveCompare("Popup") != .orderedSame
                else { return id }
                return visibleIterator.next() ?? id
            }

            for id in annotationOrderByPage[pageIndex] ?? [] where !deletedIDs.contains(id) {
                guard
                    let annotation = annotationByID[id],
                    let binding = binding(for: annotation)
                else { continue }
                currentIDs.insert(id)
                records.append(record(
                    annotation: annotation,
                    binding: binding,
                    pageIndex: pageIndex,
                    deleted: false
                ))
            }
        }

        for id in deletedIDs where !currentIDs.contains(id) {
            guard let annotation = annotationByID[id], let binding = binding(for: annotation) else {
                continue
            }
            let pageIndex = binding.origin?.pageIndex
                ?? annotationOrderByPage.first(where: { $0.value.contains(id) })?.key
                ?? 0
            records.append(record(
                annotation: annotation,
                binding: binding,
                pageIndex: pageIndex,
                deleted: true
            ))
        }

        return PDFAnnotationWriteRequest(
            sourceSHA256: sourceSHA256,
            // Records follow the logical `/Annots` order, including Popup
            // companions excluded from PDFKit's presentation graph.
            annotations: records,
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
        let components: [Double]
        if annotation.type?.caseInsensitiveCompare("Popup") == .orderedSame,
           let popupComponents = popupColorComponentsByID[binding.id] {
            components = popupComponents
        } else {
            let color = annotation.color.usingColorSpace(.deviceRGB) ?? annotation.color
            components = [
                Double(color.redComponent),
                Double(color.greenComponent),
                Double(color.blueComponent),
            ]
        }
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
            name: durableName(of: annotation),
            iconName: annotation.value(forAnnotationKey: .name) as? String,
            userName: annotation.userName,
            subject: annotation.value(forAnnotationKey: PDFAnnotationKey(rawValue: "/Subj")) as? String,
            richContents: richContentsByID[binding.id]?.value
                ?? (annotation.value(
                    forAnnotationKey: PDFAnnotationKey(rawValue: "/RC")
                ) as? String)
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
        Self.rawFlags(of: annotation)
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

    private static func restoreDetachedPopupSemantics(
        _ popup: PDFAnnotation,
        from inventory: PDFPersistenceInspection.Annotation
    ) {
        if inventory.rectangle.count == 4 {
            popup.bounds = CGRect(
                x: inventory.rectangle[0],
                y: inventory.rectangle[1],
                width: inventory.rectangle[2] - inventory.rectangle[0],
                height: inventory.rectangle[3] - inventory.rectangle[1]
            )
        }
        if inventory.color.count == 3 {
            popup.color = NSColor(
                deviceRed: inventory.color[0],
                green: inventory.color[1],
                blue: inventory.color[2],
                alpha: 1
            )
        }
        _ = popup.setValue(NSNumber(value: inventory.flags), forAnnotationKey: .flags)
        popup.isOpen = inventory.open
        if inventory.nm.isEmpty {
            popup.removeValue(forAnnotationKey: PDFAnnotationKey(rawValue: "/NM"))
        } else {
            _ = popup.setValue(
                inventory.nm,
                forAnnotationKey: PDFAnnotationKey(rawValue: "/NM")
            )
        }
        if inventory.modificationDate.isEmpty {
            popup.modificationDate = nil
        } else {
            popup.modificationDate = date(fromPDFString: inventory.modificationDate)
        }
        popup.userName = inventory.userName.isEmpty ? nil : inventory.userName
        for (value, key) in [
            (inventory.subject, PDFAnnotationKey(rawValue: "/Subj")),
            (inventory.richContents, PDFAnnotationKey(rawValue: "/RC")),
        ] {
            if value.isEmpty {
                popup.removeValue(forAnnotationKey: key)
            } else {
                _ = popup.setValue(value, forAnnotationKey: key)
            }
        }
    }

    private static func date(fromPDFString source: String) -> Date? {
        let normalized = source.replacingOccurrences(of: "'", with: "")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in [
            "'D:'yyyyMMddHHmmssX",
            "'D:'yyyyMMddHHmmssZ",
            "'D:'yyyyMMddHHmmss",
            "'D:'yyyyMMdd",
            "'D:'yyyy",
        ] {
            formatter.dateFormat = format
            if let date = formatter.date(from: normalized) {
                return date
            }
        }
        return nil
    }

    private static func colorComponents(of color: NSColor) -> [Double]? {
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return nil }
        return [Double(rgb.redComponent), Double(rgb.greenComponent), Double(rgb.blueComponent)]
    }

    private static func colorsMatch(_ lhs: [Double]?, _ rhs: [Double]?) -> Bool {
        guard let lhs, let rhs, lhs.count == rhs.count else { return lhs == nil && rhs == nil }
        return zip(lhs, rhs).allSatisfy { pair in
            abs(pair.0 - pair.1) < 0.000_1
        }
    }
}

private extension PDFAnnotationDirtyField {
    static let allForCreation: [Self] = [
        .color, .contents, .flags, .iconName, .modified, .name, .open,
        .quadrilateralPoints, .rectangle, .subject, .userName,
    ]
}
