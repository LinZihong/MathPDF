# Annotation Authoring And Inline Note Popovers

> **Historical and non-operational.** This plan was superseded by
> `docs/plans/preview_replacement_overhaul.md`. Do not execute commands or infer
> current product, fixture, signing, or validation rules from this file.

Status: superseded
Last updated: 2026-05-02
Context: existing-project change
Scheme: MathPDF
Simulator: none, macOS app

## Scope

Make MathPDF's note workflow writable while preserving plain-text PDF annotation compatibility. This work moves note interaction from the detached right-side inspector into an annotation-anchored MathPDF popover, lets existing supported notes be edited as plain text, saves those edits back into the PDF, and sets up the remaining creation flows for highlight-attached notes and box-style text notes.

This work changes PDF annotation behavior because it mutates standard PDF annotations and preserves Preview-compatible popup companions. It does not change per-document preamble metadata. Math rendering fallback behavior should remain forgiving: valid math renders for reading comfort, and broken math remains readable as raw text.

## Non-Goals

- Do not introduce a proprietary note storage format.
- Do not turn MathPDF into a general-purpose annotation manager.
- Do not implement per-document preamble editing in this slice.
- Do not add arbitrary free-text, ink, form, or non-product annotation workflows.

## Current State

- `MathPDF/AnnotationNote.swift` now carries enough identity to reconnect a sidebar item to a page annotation: page index, annotation index, type, contents, and bounds.
- `MathPDF/PDFNoteExtractor.swift` extracts supported highlight and text-note annotations, skips popup annotations, and de-duplicates Preview-style text companions when they mirror highlight contents.
- `MathPDF/ReaderDocumentController.swift` can activate notes from sidebar selection or PDF annotation clicks, save edited note contents back to the document, refresh the note list, and roll back in-memory annotation changes if writing fails.
- `MathPDF/PDFReaderView.swift` now hosts a `PDFView` inside a container that can present an inline note popover anchored near the annotation bounds.
- The inline popover has `Rendered` and `Source` modes, reuses `MathNoteView`, includes a plain-text editor, and closes after a successful save.
- `MathPDF/PDFPopupCompanionCoordinator.swift` hides Preview popup/text affordances inside MathPDF, restores them before writing, and updates or creates popup companions so other PDF viewers can still expose highlight notes.
- The Xcode project now uses read-write user-selected file access so the signed app can save user-selected PDFs.
- `MathPDF/MathNoteRendering.swift` gained height and scrolling fixes for clamped rendered-note content.
- `MathPDFTests/MathPDFTests.swift` includes focused tests for editing existing notes, synchronizing existing popup companions, creating missing popup companions, and scrolling long rendered notes.
- Remaining feature gap: creation flows for new highlight-attached notes and new box-style text notes are not implemented.
- Remaining validation gap: final signed manual validation against `pdfs for testing/ell_curves.pdf` and a writable scratch PDF still needs to happen after the slice is complete.

## Decisions

- 2026-04-08: Keep sidebar note discovery, but make in-context annotation interaction the primary editing surface. The sidebar remains useful for document-wide navigation.
- 2026-04-08: Own the note editor UI in MathPDF instead of depending on PDFKit or Preview popup UI. PDFKit exposes mutation primitives, but not a suitable rendered-math editor.
- 2026-04-08: Keep stored note text plain and show rendered math as a sibling reading surface. This preserves PDF interoperability.
- 2026-04-08: Limit the initial writable slice to highlights with notes and box-style text notes, matching the product brief.
- 2026-04-09: Ship the first implementation pass around editing existing notes before adding creation flows. The identity, popover, and save path were the core architectural blockers.
- 2026-04-09: Restore annotation contents and popup companion state if a write fails so the live document does not pretend unsaved edits succeeded.
- 2026-04-09: Preserve Preview-compatible popup companions in the PDF file but hide them inside MathPDF. This avoids duplicate UI while keeping interoperability.
- 2026-05-02: This file was converted from the old long ExecPlan format into the compact Work Card format from `PLANS.md`; prior detailed narrative is historical and recoverable from git history if needed.

## Next Steps

- [ ] Decide whether to commit the existing-note editing slice before implementing new annotation creation.
- [ ] Add a creation flow for highlight-attached notes from a text selection in `PDFView`.
- [ ] Add a creation flow for box-style text notes at a sensible visible page location.
- [ ] Add stable accessibility identifiers for new creation controls before writing UI tests against them.
- [ ] Validate the completed writable-reader slice in a signed app using `pdfs for testing/ell_curves.pdf` and a writable scratch PDF.

## Validation

Passed:
- 2026-04-09: Built the signed app, launched it against `pdfs for testing/ell_curves.pdf`, and captured screenshots showing the inline popover next to the highlighted note.
- 2026-04-10: Ran focused `MathPDFTests` with editing and popup companion persistence tests.
- 2026-04-10: Validated long rendered-note scrolling with a rendered area clamped to 208 points and scrollable content substantially taller than the viewport.
- 2026-04-10: Validated popup compatibility with a scratch PDF: saved files contain visible `/Popup` companions for Preview, while MathPDF hides those companions in memory.

Not yet validated:
- Full signed scheme build after the final creation-flow implementation.
- Full signed scheme test run after the final creation-flow implementation.
- Manual signed product pass after new note creation is implemented.

Useful commands:

    xcodebuild -project MathPDF.xcodeproj -scheme MathPDF -derivedDataPath .build/SignedDerivedData build

    xcodebuild -project MathPDF.xcodeproj -scheme MathPDF -derivedDataPath .build/SignedDerivedData -only-testing:MathPDFTests test

    scripts/build-and-launch.sh --signed "pdfs for testing/ell_curves.pdf"

## Notes

Use a writable scratch PDF for manual save validation. Do not edit the checked-in fixture in place.

    mkdir -p /tmp/mathpdf-scratch
    cp "pdfs for testing/ell_curves.pdf" /tmp/mathpdf-scratch/ell_curves-editable.pdf
    scripts/build-and-launch.sh --signed "/tmp/mathpdf-scratch/ell_curves-editable.pdf"

Capture manual validation evidence with the existing macOS window-capture skill when user-visible workflows change.
