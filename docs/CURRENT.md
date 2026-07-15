# Current State

Last updated: 2026-07-15

This file records current implementation and validation state only. Product
requirements live in `docs/initial_description.txt`; validation rules live in
`docs/TESTING.md`; the active delta lives in
`docs/plans/preview_replacement_overhaul.md`.

The scheme is `MathPDF`. This is an existing macOS project; no simulator is
used.

## Committed and validated baseline

- `eaf9ce1` is the recoverable product checkpoint for the broader reader
  overhaul.
- `388970b` makes both app-hosted test targets nonparallel and disables
  document/window restoration for test actions. A signed ten-test
  `MathPDFDocumentTests` run completed without a Documents permission prompt,
  proving the permission-stall fix.
- `0fb21e7` records the stable production-host signing route, fixture boundary,
  permission escape protocol, and test-host fallback policy.
- `75a4018` and `0c53234` implement and harden reciprocal popup persistence.
- `d3fb207` completes the native reader interaction overhaul, structurally
  separates runtime Popup presentation from reciprocal disk persistence, and
  adds the final unit/UI regression corpus.
- Unit tests normally use the production `MathPDF.app` host with Xcode's
  Automatic Apple Development signing. A rebuild probe changed the app's CDHash
  while preserving its certificate-based designated requirement; focused tests
  passed before and after the rebuild without a Documents prompt. The isolated
  `MathPDFTestHost` remains a fallback only.
- Native per-document windows provide outlines, Highlights and Notes, search,
  page entry, grouped zoom controls, printing, Save As, Revert, annotation
  authoring, undo, and document autosave.
- Direct annotation activation preserves the viewport. Sidebar navigation
  preserves scale, minimally reveals offscreen targets, updates the page field,
  and maintains truthful Back history.
- MathPDF presents one in-app reading surface per note. Existing notes open
  read-first; explicit Edit and New Note enter plain-text editing in the same
  page-attached surface. The macros inspector is document-settings-only.
- Bundled KaTeX supports common delimiters, document-scoped aliases, simple
  parameterized commands, and math operators, with readable raw-text fallback.
- The document preamble uses a versioned marker in standard PDF Keywords while
  preserving unrelated metadata.
- The checkpoint passed 25 out-of-sandbox signed unit/integration tests. That
  evidence covers the checkpoint's then-current popup-normalization policy, not
  the later reciprocal-popup implementation.
- A signed manual pass on
  `/tmp/MathPDF-Fixtures/58x-annotations-short.pdf` verified one-popover
  ownership, direct-click viewport stability, sidebar page/zoom navigation,
  Back, and the native Print menu. All launched MathPDF/test processes were
  terminated afterward.

## Completed overhaul and current evidence

- The interaction redesign replaces detached popovers and note inspectors with
  one contained page-attached read/edit surface. Runtime comment badges mark
  highlights with contents without creating a second PDF annotation. Surface
  placement rejects overlap with the source highlight when a safe candidate is
  available, and opening/closing it does not deliberately re-anchor the PDF.
- The sidebar is now a native, concise list selected by a quiet title menu. The
  toolbar uses large native navigation and zoom controls, direct page
  entry, one annotation control with Preview-compatible named colors, and a
  native search field. Preamble editing moved to the Math menu and optional
  document inspector.
- The Notes sidebar now uses real source-list selection rather than a tap
  gesture plus painted selection background. Its binding routes user selection
  through contextual navigation while programmatic selection from an on-page
  activation updates the row without issuing a second navigation request.
- The annotation overlay scans only nearby pages during scroll/zoom, and badge
  buttons expose accessible page-labelled actions.
- The latest normal signed production-host suite passed 65/65 after the
  presentation-graph correction. It covers
  standalone Text notes, highlight notes, unrelated metadata and annotations,
  repeated revisions, delete/undo/redo, identical geometry and contents,
  color changes, multi-document isolation, no-op bytes, and fail-closed
  untracked mutation. Raw fixtures additionally cover both one-sided popup
  directions, imported popup metadata preservation, and duplicate `/NM`
  rejection, exact imported `/RC` undo, locked annotations, imported
  Popup-private metadata, and live `/Annots` order.
  Neither run requested Documents access, and the host exited afterward.
- The adversarial lifecycle corpus exposed a PDFKit behavior in which assigning
  `annotation.popup = nil` clears the owner's `contents`. Detach, reattach, and
  color-change paths now preserve owner text explicitly, with regressions.
- An independent post-commit review found three P1 gaps. The follow-up preserves
  owner contents while repairing one-sided imports, makes imported delete/undo
  neutral to `/Contents`, `/M`, `/F`, `/Open`, `/AP`, unknown keys, and absent
  `/NM`, and fails closed on duplicate durable annotation names.
- The earlier PDFKit serializer probe dropped reciprocal popup topology, so the
  undocumented append backend is not the active writer. That is not a proof
  that every controlled PDFKit-to-Preview workflow must fail; a narrowly scoped
  end-to-end experiment remains a fallback only if qpdf becomes blocked. The
  embedded qpdf boundary is the accepted persistence direction; independent
  parsing and direct Preview popup expansion now confirm its realistic path.
- A signed build and the then-current 49-test production-host unit suite passed
  from `/private/tmp/MathPDF-DerivedData`. The UI-test bundle also builds signed
  from that location.
- Computer Use on the realistic seven-page
  `/private/tmp/MathPDF-Fixtures/practice-of-curves-annotated-excerpt.pdf`
  verified the native shell, runtime comment badges, one contained read surface,
  and in-place edit transition. The first visual pass found the surface could
  cover its source highlight; placement was corrected and visually rechecked.
- Later focused UI execution reached the MathPDF document window in roughly
  2–3 seconds. A later annotation interaction hung; that was not a 30-second
  startup violation. Separately, a QA-only AppleScript bounds query created a
  ChatGPT Automation prompt for `System Events` and obstructed one later UI
  run. The prompt was explicitly denied, AppleScript/System Events are now
  prohibited for MathPDF QA, and app-scoped XCUITest/CoreGraphics evidence is
  used instead. The DEBUG custom AppKit fixture
  window also distorted document-scene undo/menu routing and has now been
  removed; UI tests load the deterministic in-memory fixture through the real
  `DocumentGroup` scene.
- A user-visible duplicate native/custom annotation affordance exposed a real
  test gap: the UI assertion counted custom surfaces and `NSPopover`s but could
  not see a PDFKit page-drawn closed-Popup marker. Removing the Popup from
  `page.annotations` was insufficient because PDFKit also paints that marker
  from the owning annotation's live `popup` pointer. The working tree now keeps
  Popup companions and reciprocal edges only in the persistence session;
  runtime pages contain no Popup and every visible runtime owner's `popup` is
  nil. A regression asserts that split and exactly one reciprocal Popup on
  serialized output. Direct Computer Use inspection of the signed candidate
  confirmed the former native yellow marker is gone and only MathPDF's attached
  comment badge remains.
- The persistence order now reconciles PDFKit's current visible annotation
  order with durable hidden-Popup slots before writing. It fails closed if a
  tracked visible annotation was directly removed, duplicated, or moved across
  pages outside MathPDF's mutation API, preventing silent resurrection or a
  single object appearing in two page `/Annots` arrays. The source now contains
  65 Swift Testing cases, including interleaved hidden-slot, fail-closed,
  native-sidebar-selection, lazy Popup reinsertion, and exact independent
  Popup-color/AP undo regressions; all pass in the signed production host.
- A state-lifecycle follow-up now clears search when a different PDF replaces
  the reader document, keeps existing empty annotations read-first, rejects a
  multi-page Highlight with Note before mutation, and prevents an edit baseline
  from leaking through delete/undo into a later edit. Each path has a focused
  regression and all three targets compile together.
- The presentation-graph and final note-layout corrections pass signed runtime
  validation. The full production-host unit suite passed 65/65 at
  `/tmp/MathPDF-DerivedData/Logs/Test/Test-MathPDF-2026.07.15_04-07-23--0700.xcresult`.
  The annotation workflow test passed after the final scrollbar correction at
  `Test-MathPDF-2026.07.15_04-09-40--0700.xcresult`, capturing app-window-only
  reading and recolor evidence. The final full signed UI suite passed 3/3 at
  `Test-MathPDF-2026.07.15_04-19-13--0700.xcresult`; every test explicitly quit
  MathPDF. No route used `MathPDFTestHost` or opened a document path.
- Independent `pypdf` inspection of the realistic mixed corpus confirmed the
  MathPDF-authored owner `/Popup` and reciprocal Popup `/Parent`. Preview opened
  the disposable `/private/tmp/MathPDF-Fixtures/final-review-working.pdf`,
  displayed its native green marker and sidebar note, and XCUITest double-
  clicked that marker to expand Preview's popup with MathPDF's saved text.
- The first independent visual review returned `VISUAL NO-PASS`. After another
  toolbar, badge, note-surface, sidebar, color-continuity, and scroll-indicator
  pass, the independent reviewer returned `VISUAL PASS` with no static daily-
  use blocker. All MathPDF and Preview windows were closed afterward.
- `docs/FINAL_INTERACTIVE_REVIEW_PROMPT.md` now contains the bounded final
  holistic review prompt. A fresh check-only gatekeeper accepted its first
  draft; the primary agent nevertheless found and corrected an imprecise
  fixture boundary and an ambiguous file-editing rule, and the gatekeeper
  accepted the revised prompt. It remains intentionally unrun until the signed
  post-correction candidate and disposable working fixture are ready.

## Open validation gates

- The explicitly required independent Computer Use design interaction verdict
  remains `UNVERIFIED`: three bounded reviewer attempts stalled before returning
  visible state. Each attempt was interrupted and cleaned up. Independent static
  review is `VISUAL PASS`, and signed XCUITest covers the interaction workflows,
  but neither is being mislabeled as the missing Computer Use evidence.
- Idle autosave, Save As, Revert, write-failure UI, external-file conflicts,
  accessibility configurations, and largest-document responsiveness remain
  explicit extended manual gates in `docs/TESTING.md`.
- Apply `docs/TESTING.md` exactly. `TestPDFs/` remains read-only source material
  and is never a GUI launch target.

## Next safe action

Retry only the independent Computer Use product review when that channel can
return visible state within the documented bound; no product rerun or permission
change is justified merely to force it. Keep using the production app host and
default Xcode signing; use `MathPDFTestHost` only if that normal route becomes
blocked again.
