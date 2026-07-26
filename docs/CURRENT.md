# Current State

Last updated: 2026-07-26

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
- The final interaction pass removes the custom search-field bridge in favor of
  native adaptive `.searchable`, keeps Command-F scoped to the focused document,
  clears stale results when Find is canceled, and retains accessible search at
  the default window width. The toolbar, quiet sidebar mode menu, fixed
  highlight-adjacent note badge, and page-attached note surface keep the PDF
  visually dominant without duplicating PDFKit popup presentation.
- Note editing now uses a local isolated undo stack while the editor is active.
  Pending note drafts participate in NSDocument's editing protocol, fail closed
  on an unsuccessful commit, and remain resolvable if their view detaches.
  Macro editing no longer double-registers native and model undo operations.
  Stricter visible review later showed that permanent note and macro mutations
  were not reliably reflected by the containing NSDocument's Edited state. The
  latest working tree records those permanent changes through the exact
  containing window/document after balancing the temporary draft transaction;
  that correction builds signed but is not yet visibly verified.
- The signed source currently contains 68 Swift Testing cases. All 68 assertions
  passed in the production app host; that invocation later stalled while Xcode
  finalized coverage/result logging and was terminated. Subsequent signed
  `test` and `test-without-building` attempts stalled before starting tests, so
  the runner's clean completion remains an evidence limitation rather than a
  product failure. The latest signed `build-for-testing` and final signed
  build-only both succeed after the exact-window change-accounting patch.
- Independent visible Computer Use initially returned `INTERACTIVE NO-PASS` for
  false dirty-state feedback after undo, then another `INTERACTIVE NO-PASS` for
  inaccessible Find at the default window width. After correction, the exact
  signed in-memory candidate returned `INTERACTIVE PASS`: Command-F found and
  focused `Search PDF`, one Command-Z restored note contents and clean title,
  closing the surface cleared sidebar selection, and exactly one fixed MathPDF
  badge remained beside the source highlight. The independent reviewer closed
  the exact app process after every pass. A stricter post-audit contract then
  found editor-local dirty/undo state correct but returned `INTERACTIVE
  NO-PASS` because Done cleared Edited after a committed note mutation and Math
  Macro edits never marked the window Edited. Both content undo paths restored
  their exact baselines. The newest verdict therefore remains NO-PASS until the
  latest exact-window change-accounting patch is retested.
- A final adversarial code audit found and then confirmed closure of failed-
  commit dismissal, isolated text undo, multiwindow Find routing, duplicate
  macro undo, and view-teardown editing-registration risks. It reports no
  remaining P1/P2 issue. A fresh check-only prompt gatekeeper accepted the final
  focused interactive contract only after two prior gatekeepers independently
  rejected permissive PASS semantics and a missing no-project-modification
  boundary; no gatekeeper rewrote the prompt.

## Open validation gates

- Rerun the accepted focused Computer Use contract. It must prove editor-local
  dirty/undo, committed-note dirty/undo,
  and macro dirty/undo against the real NSDocument. The latest exact-window
  change-accounting patch has signed app/unit/UI compile evidence but no fresh
  visible verdict.
- A clean new Xcode unit/UI test-runner completion is still desirable because
  recent runner invocations stalled outside the test bodies. The current source
  does have signed compile evidence for every target, and the last full unit
  invocation reached 68/68 passing assertions before the runner stalled.
- Idle autosave, Save As, Revert, write-failure UI, external-file conflicts,
  accessibility configurations, and largest-document responsiveness remain
  explicit extended manual gates in `docs/TESTING.md`.
- Apply `docs/TESTING.md` exactly. `TestPDFs/` remains read-only source material
  and is never a GUI launch target.

## Next safe action

Continue from
`handoffs/2026-07-26_019f591c_to_new-machine_mathpdf-overhaul.md`. Refresh the
signed all-target compile and unit evidence, then run its verbatim bounded
focused Computer Use prompt. Close the Work Card only if every required
contract passes. Keep using the production app host and default Xcode signing;
use `MathPDFTestHost` only if that normal route becomes blocked again.
