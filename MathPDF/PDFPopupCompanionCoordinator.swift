//
//  PDFPopupCompanionCoordinator.swift
//  MathPDF
//
//  Created by Codex on 4/9/26.
//

import CoreGraphics
import PDFKit

@MainActor
final class PDFPopupCompanionCoordinator {
    struct Mutation {
        let rollback: () -> Void

        static let none = Mutation {}

        static func combined(_ mutations: [Mutation]) -> Mutation {
            Mutation {
                for mutation in mutations.reversed() {
                    mutation.rollback()
                }
            }
        }
    }

    func prepareDocumentForDisplay(_ document: PDFDocument) {
        setPreviewAnnotationDisplay(in: document, shouldDisplay: false)
    }

    func writeDocument(_ document: PDFDocument, to url: URL) -> Bool {
        setPreviewAnnotationDisplay(in: document, shouldDisplay: true)
        return document.write(to: url)
    }

    func synchronizePopupCompanion(
        for annotation: PDFAnnotation,
        previousContents: String,
        updatedContents: String
    ) -> Mutation {
        guard
            isHighlight(annotation),
            let page = annotation.page
        else {
            return .none
        }

        let popupMutation = synchronizeExistingPopupCompanion(
            for: annotation,
            previousContents: previousContents,
            updatedContents: updatedContents,
            on: page
        )
        let textMutation = synchronizeTextCompanion(
            for: annotation,
            previousContents: previousContents,
            updatedContents: updatedContents,
            on: page
        )

        return .combined([popupMutation, textMutation])
    }

    private func synchronizeExistingPopupCompanion(
        for annotation: PDFAnnotation,
        previousContents: String,
        updatedContents: String,
        on page: PDFPage
    ) -> Mutation {
        guard let popup = popupCompanion(
            for: annotation,
            previousContents: previousContents,
            updatedContents: updatedContents,
            on: page
        ) else {
            return .none
        }

        let previousContents = popup.contents
        let previousModificationDate = popup.modificationDate
        let previousShouldDisplay = popup.shouldDisplay
        let previousShouldPrint = popup.shouldPrint
        let previousPopup = annotation.popup

        configurePopupCompanion(popup, for: annotation, contents: updatedContents)

        return Mutation {
            popup.contents = previousContents
            popup.modificationDate = previousModificationDate
            popup.shouldDisplay = previousShouldDisplay
            popup.shouldPrint = previousShouldPrint
            annotation.popup = previousPopup
        }
    }

    private func synchronizeTextCompanion(
        for annotation: PDFAnnotation,
        previousContents: String,
        updatedContents: String,
        on page: PDFPage
    ) -> Mutation {
        if let text = textCompanion(
            for: annotation,
            previousContents: previousContents,
            updatedContents: updatedContents,
            on: page
        ) {
            let previousContents = text.contents
            let previousModificationDate = text.modificationDate
            let previousShouldDisplay = text.shouldDisplay
            let previousShouldPrint = text.shouldPrint
            let previousColor = text.color
            let previousPopupContents = text.popup?.contents
            let previousPopupModificationDate = text.popup?.modificationDate
            let previousPopupShouldDisplay = text.popup?.shouldDisplay
            let previousPopupShouldPrint = text.popup?.shouldPrint
            let previousPopupColor = text.popup?.color

            configureTextCompanion(text, for: annotation, contents: updatedContents)

            return Mutation {
                text.contents = previousContents
                text.modificationDate = previousModificationDate
                text.shouldDisplay = previousShouldDisplay
                text.shouldPrint = previousShouldPrint
                text.color = previousColor

                if let popup = text.popup {
                    popup.contents = previousPopupContents
                    popup.modificationDate = previousPopupModificationDate
                    popup.color = previousPopupColor ?? popup.color
                    if let previousPopupShouldDisplay {
                        popup.shouldDisplay = previousPopupShouldDisplay
                    }
                    if let previousPopupShouldPrint {
                        popup.shouldPrint = previousPopupShouldPrint
                    }
                }
            }
        }

        let text = makeTextCompanion(for: annotation, contents: updatedContents)
        page.addAnnotation(text)
        configureTextCompanion(text, for: annotation, contents: updatedContents)

        return Mutation {
            if text.page === page {
                page.removeAnnotation(text)
            }
        }
    }

    private func setPreviewAnnotationDisplay(in document: PDFDocument, shouldDisplay: Bool) {
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else {
                continue
            }

            for annotation in page.annotations where isPopup(annotation) || isText(annotation) {
                annotation.shouldDisplay = shouldDisplay
            }
        }
    }

    private func popupCompanion(
        for annotation: PDFAnnotation,
        previousContents: String,
        updatedContents: String,
        on page: PDFPage
    ) -> PDFAnnotation? {
        if let popup = annotation.popup, isPopup(popup) {
            return popup
        }

        let popupCandidates = page.annotations.filter { candidate in
            isLikelyPopupCompanion(
                candidate,
                for: annotation,
                previousContents: previousContents,
                updatedContents: updatedContents
            )
        }

        return popupCandidates.min { lhs, rhs in
            companionScore(for: lhs, matching: annotation) < companionScore(for: rhs, matching: annotation)
        }
    }

    private func textCompanion(
        for annotation: PDFAnnotation,
        previousContents: String,
        updatedContents: String,
        on page: PDFPage
    ) -> PDFAnnotation? {
        let textCandidates = page.annotations.filter { candidate in
            isLikelyTextCompanion(
                candidate,
                for: annotation,
                previousContents: previousContents,
                updatedContents: updatedContents
            )
        }

        return textCandidates.min { lhs, rhs in
            companionScore(for: lhs, matching: annotation) < companionScore(for: rhs, matching: annotation)
        }
    }

    private func makeTextCompanion(
        for annotation: PDFAnnotation,
        contents: String
    ) -> PDFAnnotation {
        let text = PDFAnnotation(
            bounds: textBounds(for: annotation.bounds),
            forType: PDFAnnotationSubtype.text,
            withProperties: nil
        )
        text.contents = contents
        return text
    }

    private func makePopupCompanion(for text: PDFAnnotation) -> PDFAnnotation {
        PDFAnnotation(
            bounds: popupBounds(for: text.bounds),
            forType: PDFAnnotationSubtype.popup,
            withProperties: nil
        )
    }

    private func configurePopupCompanion(
        _ popup: PDFAnnotation,
        for annotation: PDFAnnotation,
        contents: String
    ) {
        annotation.popup = popup
        popup.contents = contents
        popup.modificationDate = Date()
        popup.shouldDisplay = true
        popup.shouldPrint = true
    }

    private func configureTextCompanion(
        _ text: PDFAnnotation,
        for annotation: PDFAnnotation,
        contents: String
    ) {
        text.bounds = textBounds(for: annotation.bounds)
        text.contents = contents
        text.modificationDate = Date()
        text.color = annotation.color
        text.shouldDisplay = true
        text.shouldPrint = true

        let popup = text.popup ?? makePopupCompanion(for: text)
        text.popup = popup
        popup.bounds = popupBounds(for: text.bounds)
        popup.modificationDate = text.modificationDate
        popup.shouldDisplay = true
        popup.shouldPrint = true
        popup.color = text.color
    }

    private func textBounds(for highlightBounds: CGRect) -> CGRect {
        CGRect(
            x: highlightBounds.maxX + 4,
            y: highlightBounds.maxY + 4,
            width: 24,
            height: 24
        ).integral
    }

    private func popupBounds(for textBounds: CGRect) -> CGRect {
        CGRect(
            x: textBounds.maxX + 4,
            y: textBounds.maxY + 4,
            width: 72,
            height: 36
        ).integral
    }

    private func isLikelyPopupCompanion(
        _ candidate: PDFAnnotation,
        for annotation: PDFAnnotation,
        previousContents: String,
        updatedContents: String
    ) -> Bool {
        guard isPopup(candidate) else {
            return false
        }

        guard contentsAreCompatible(
            candidate.contents ?? "",
            previousContents: previousContents,
            updatedContents: updatedContents
        ) else {
            return false
        }

        return companionScore(for: candidate, matching: annotation) < 220
    }

    private func isLikelyTextCompanion(
        _ candidate: PDFAnnotation,
        for annotation: PDFAnnotation,
        previousContents: String,
        updatedContents: String
    ) -> Bool {
        guard isText(candidate) else {
            return false
        }

        guard contentsAreCompatible(
            candidate.contents ?? "",
            previousContents: previousContents,
            updatedContents: updatedContents
        ) else {
            return false
        }

        return companionScore(for: candidate, matching: annotation) < 180
    }

    private func contentsAreCompatible(
        _ candidateContents: String,
        previousContents: String,
        updatedContents: String
    ) -> Bool {
        let candidateContents = normalizedContents(candidateContents)
        let previousNormalized = normalizedContents(previousContents)
        let updatedNormalized = normalizedContents(updatedContents)

        return candidateContents.isEmpty ||
            previousNormalized.isEmpty ||
            updatedNormalized.isEmpty ||
            candidateContents == previousNormalized ||
            candidateContents == updatedNormalized
    }

    private func companionScore(
        for popup: PDFAnnotation,
        matching annotation: PDFAnnotation
    ) -> CGFloat {
        let popupCenter = CGPoint(x: popup.bounds.midX, y: popup.bounds.midY)
        let annotationAnchor = CGPoint(x: annotation.bounds.maxX, y: annotation.bounds.maxY)
        return hypot(popupCenter.x - annotationAnchor.x, popupCenter.y - annotationAnchor.y)
    }

    private func isHighlight(_ annotation: PDFAnnotation) -> Bool {
        guard let type = annotation.type else {
            return false
        }

        return normalizedSubtypeName(type) == normalizedSubtypeName(PDFAnnotationSubtype.highlight.rawValue)
    }

    private func isText(_ annotation: PDFAnnotation) -> Bool {
        guard let type = annotation.type else {
            return false
        }

        return normalizedSubtypeName(type) == normalizedSubtypeName(PDFAnnotationSubtype.text.rawValue)
    }

    private func isPopup(_ annotation: PDFAnnotation) -> Bool {
        guard let type = annotation.type else {
            return false
        }

        return normalizedSubtypeName(type) == normalizedSubtypeName(PDFAnnotationSubtype.popup.rawValue)
    }

    private func normalizedContents(_ contents: String) -> String {
        contents.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedSubtypeName(_ subtype: String) -> String {
        subtype.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
    }
}
