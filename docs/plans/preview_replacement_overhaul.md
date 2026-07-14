# Preview-Replacement Reader Overhaul

Status: active
Last updated: 2026-07-13
Context: existing-project change
Scheme: MathPDF
Simulator: none, macOS app

## Scope

Replace the prototype interaction model with a trustworthy native macOS PDF
reader for mathematical reading and annotation. The shipping target is the
user's research workflow: multiple PDFs, outlines, search, stable navigation,
highlights, box notes, rendered TeX notes, printing, and safe document saving.

This changes document lifecycle, annotation behavior, metadata persistence,
math rendering delivery, reader UI, and tests. Plain-text PDF annotation
contents remain the interoperable source of truth.

## Non-Goals

- Signature authoring, image editing, cropping, OCR, and comprehensive AcroForm
  authoring are not Preview-parity requirements for this overhaul.
- Do not execute arbitrary TeX packages or a full TeX installation.
- Do not create a proprietary annotation-content format.
- Do not add knowledge-management, tagging, library, or account features.

## Experience Contract

- The PDF is the visual center. Chrome stays compact and uses native macOS
  toolbar, sidebar, inspector, menu, keyboard, and document conventions.
- Clicking an annotation already under the pointer never changes page, scale,
  or scroll position.
- Sidebar navigation scrolls only when the target is not sufficiently visible,
  preserves scale, and moves the minimum distance necessary.
- Reader updates, note editing, autosave, and math rendering never trigger a
  whole-document relayout on the interaction path.
- Note presentation remains spatially attached to its annotation. If an anchor
  leaves the visible area, the transient presentation closes or becomes a
  deliberate pinned inspector; it never clamps to an unrelated window edge.
- Edits are immediately undoable in memory. Atomic autosave follows after a
  short idle interval. Standard Save As and Revert remain available.
- Broken or unsupported TeX remains readable as plain text.
- Every PDF gets an independent window, viewport, selection, undo history,
  dirty state, sidebar mode, and preamble.

## UI Direction

- Main toolbar: sidebar, back/forward, document title and page subtitle, direct
  page entry, one grouped zoom out/value/in control, an always-visible native
  search field with contextual result navigation, annotation tools, and the
  preamble inspector.
- Sidebar: a quiet title menu chooses `Table of Contents` or `Highlights and
  Notes`; there is no persistent tab strip. Contents uses the PDF outline
  hierarchy. Highlights and Notes uses a native sidebar list with page/author
  metadata, annotation-color rules, and stable concise excerpts; popover or
  inspector owns full note content so selection never reflows the index.
- Note click: native anchored popover for reading. Long or pinned notes use the
  trailing inspector without blocking the PDF. Existing notes remain in reading
  mode until Edit; newly created notes begin editing intentionally.
- Editing: rendered reading view with one Edit action; plain-text editor with
  Done, close-to-commit, deletion, and standard undo. There is no
  Rendered/Source mode switch and no note-level disk-save concept.
- Advanced choices live in menus or inspector; the common reading path stays
  visible and direct.
- Motion is restrained, spatially symmetric, and interruptible. Reduced Motion,
  Reduced Transparency, increased contrast, keyboard access, and larger text
  are first-class validation configurations.

## Document And Compatibility Decisions

- Use PDFKit for the document and reading surface.
- Adopt a native per-document lifecycle rather than a singleton controller.
- Save through the document system with atomic replacement, undo, autosave,
  Save As, Revert, close review, and external-change handling.
- Standalone `/Text` annotations are real user notes and must remain visible.
- Highlight notes use the standard highlight annotation contents; do not invent
  a duplicate `/Text` annotation. PDFKit cannot reliably reserialize an
  associated `/Popup` + `/Parent` graph, so saved copies deliberately omit
  popup companions while retaining the note text on the owning annotation.
- Resolve annotation relationships explicitly. The normalization above occurs
  on a serialized copy and must neither mutate the live document nor discard
  standalone `/Text` annotations.
- Store document macro text in PDF metadata under a documented MathPDF key.
  Unknown readers continue to see normal plain-text annotations.

## Math Decisions

- Keep bundled KaTeX for the initial overhaul and remove prototype diagnostic
  work from the production interaction path.
- Cache immutable renderer assets and rendered HTML so repeatedly opening the
  same note does not rebuild the bundled KaTeX payload.
- Support zero-argument aliases (`\Q`), simple parameterized commands
  (`\norm{}`), and `\DeclareMathOperator`-style definitions.
- Ignore unsupported package, theorem, environment, color, and document-layout
  statements with a clear inspector status.
- A later renderer change requires a corpus-backed improvement in compatibility,
  fallback, accessibility, latency, and signed sandbox reliability.

## Testing Rules

- A build is necessary but never sufficient for user-visible work.
- Tests assert behavior, not implementation details or historical mistakes.
- Generated compact PDFs are the authoritative automated fixtures. Large user
  PDFs are manual/performance fixtures and are never modified in place.
- Logic and integration tests cover page/scale/history preservation, note
  identity and visibility, PDF reserialization, preamble metadata, runtime
  script safety, fallback, multiline highlights, edge placement, and
  independent window state. Popover count/placement and native document-panel
  workflows remain deterministic UI/manual contracts.
- UI tests use deterministic launch files, stable identifiers, explicit product
  assertions, and always terminate every launched application.
- No screenshot-only tests. Screenshots supplement assertions and manual review.
- Persistence tests reopen serialized PDF data and verify unrelated annotations,
  keywords, page count, preamble, and note text survive. Form preservation is a
  manual compatibility check when form-bearing fixtures are added.
- Viewport tests compare page, scale factor, and Back history; manual Computer
  Use checks additionally inspect the visible target and direct-click stability.
- Accessibility, dark mode, narrow windows, larger text, Reduced Motion, and
  Reduced Transparency are required configurations, not optional polish.
- Performance work must use realistic supplied PDFs and inspect first
  interaction, note opening, sidebar switching, asynchronous search
  cancellation, and autosave UI stalls; renderer and asset caches are covered by
  the implementation contract rather than screenshot timing.

## Current State

- The app now uses per-document state, stable long-lived PDF views, minimal
  navigation, native popovers/inspectors, native document saving, and a calm
  standard-height macOS reader shell.
- MathPDF intercepts supported page-annotation clicks before PDFKit can open a
  second popup. Text-selection drags still pass through to PDFKit.
- Annotation indexing is isolated from preamble edits, so typing macros does not
  rescan the document.
- Signed local ad-hoc builds pass signature and entitlement verification.
- `TestPDFs/` remains untracked user material and was not modified.

## Next Steps

- [x] Land per-document lifecycle and stable PDFView ownership.
- [x] Land the native reader shell and viewport-preserving navigation.
- [x] Replace note resolution, presentation, editing, creation, and persistence.
- [x] Add document macros and graceful KaTeX rendering.
- [x] Replace stale tests and manual fixtures with adversarial coverage.
- [ ] Complete the final unlocked-desktop UI-test run and independent visual
      ship verdict after the final toolbar/search changes.

## Validation

Passed:
- 2026-07-12: `scripts/build-and-launch.sh --unsigned --build-only`.
- 2026-07-12: Read-only code, product, architecture, and edge-case audits.
- 2026-07-12: signed `MathPDFTests` suite, 19 tests.
- 2026-07-13: signed `MathPDFTests` suite, 25 tests, including adversarial
  semantic round trips and deliberate non-mutating popup normalization.
- 2026-07-13: signed `build-for-testing` and
  `scripts/build-and-launch.sh --signed --build-only`; deep signature and
  sandbox/network/read-write entitlements verified.
- 2026-07-12: `scripts/build-and-launch.sh --signed --build-only`; deep signature
  and sandbox/network/read-write entitlements verified.
- 2026-07-12: Computer Use validation with the realistic seven-page fixture in
  `/tmp/MathPDF-Fixtures`; macros, outline, notes, one-popover ownership,
  viewport preservation, page/Back history, native note-list selection, native
  Print menu, and final window cleanup passed.

Blocked final evidence:
- 2026-07-13: UI automation was explicitly approved and the test host was moved
  entirely under `/tmp`. The permission/Open-panel failure was removed, but the
  Mac locked before the final run. XCTest therefore failed during activation
  with `current state: Running Background`; no product assertion ran. Repeat
  only after the session is unlocked.
- The newest active-window research-PDF screenshot and independent final design
  verdict remain outstanding for the same locked-session reason.
