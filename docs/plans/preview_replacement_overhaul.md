# Preview-Replacement Reader Overhaul

Status: active
Last updated: 2026-07-15
Context: existing-project change
Scheme: MathPDF
Simulator: none, macOS app

## Scope

Finish reciprocal annotation interoperability and replace the current detached,
rigid annotation interaction with one coherent page-attached read/edit surface,
an appropriately restrained native toolbar, Preview-compatible highlight color
choices, and clear on-page note affordances. Stable product behavior is defined
in `docs/initial_description.txt`; this Work Card tracks only the active delta.

This work changes PDF annotation compatibility and user-facing annotation
interaction. It does not change math fallback behavior or the per-document
preamble format.

## Non-Goals

- Do not expand Preview parity beyond the documented research-PDF workflow.
- Do not add a proprietary annotation format or duplicate `/Text` notes.
- Do not turn MathPDF into a general annotation database or knowledge manager.
- Do not treat historical plan commands as current validation instructions.

## Current State

- Commit `eaf9ce1` is the recoverable product checkpoint for the broader reader
  overhaul.
- Commit `388970b` prevents parallel test hosts and document restoration from
  triggering Documents permission prompts. A signed ten-test document suite
  completed permission-clean afterward.
- The normal test route again uses the production `MathPDF.app` host with
  Automatic Apple Development signing. Focused tests passed before and after a
  rebuild whose CDHash changed but certificate-based designated requirement
  remained stable; no Documents prompt appeared. `MathPDFTestHost` is retained
  only as a fallback diagnostic host.
- Commits `75a4018` and `0c53234` implement reciprocal popup persistence through
  an embedded qpdf-backed writer, semantic postvalidation, byte-identical no-op
  snapshots, per-revision caching, and fail-closed editing for unsupported
  PDFs. PDFKit remains the viewer and in-memory annotation API.
- The writer now owns the authoritative identity/edge graph, rejects untracked
  PDFKit mutations, and requires reciprocal output edges. The orphan-popup
  failures were traced to one-pass discovery of PDFKit-created Text popups and
  corrected with two-pass binding plus explicit edge registration.
- The latest production-host signed unit suite passed 65/65 without a Documents
  prompt after the presentation-graph correction. The adversarial revision
  corpus also found and locked down PDFKit clearing owner contents when `popup`
  is detached.
- Raw fixtures now prove both one-sided import repairs, preservation-neutral
  imported delete/undo for popup contents, dates, flags, open state, appearance,
  unknown keys, and absent names, plus duplicate `/NM` fail-closed behavior.
- The working tree replaces the detached note inspector/popover with one
  contained page-attached read/edit surface, adds runtime comment badges without
  storage objects, rebuilds the toolbar and sidebar with native hierarchy, and
  connects a named highlight palette across page, badge, sidebar, and surface.
- Notes now use true source-list selection. The selection binding distinguishes
  a user's sidebar choice, which navigates, from programmatic synchronization
  after an on-page click, which must not re-anchor the PDF.
- Visual review on a realistic research excerpt caught source-highlight overlap,
  custom toolbar weight, an ambiguous badge, dense sidebar rows, and stale color
  identity. After correction, a fresh independent screenshot review returned
  `VISUAL PASS` with no daily-use blocker.
- A later UI run reached the document in roughly 2–3 seconds without a
  permission sheet; a later interaction hang was incorrectly reported as a
  startup-gate failure. The DEBUG custom fixture window distorted scene undo
  and menus, so it has been removed. UI tests now use the real `DocumentGroup`
  scene and its system undo manager.
- Duplicate native/custom note markers exposed an uncovered presentation bug.
  Popup companions now remain in the persistence graph and serialized PDF but
  are removed from PDFKit's live page graph, and visible owners have no live
  `popup` pointer. Automated proof covers runtime page membership, the owner
  pointer, and the serialized reciprocal graph. Direct Computer Use inspection
  of the signed candidate confirmed that the former native yellow marker is
  gone and only MathPDF's attached comment badge remains.
- Hidden Popup slots and PDFKit's visible annotation order are reconciled before
  serialization. Direct removal, duplication, or cross-page movement of a
  tracked visible owner now fails closed instead of resurrecting or duplicating
  the object. The 58-case Swift Testing source also covers visible reorder with
  an interleaved hidden Popup slot, native sidebar selection without a
  programmatic re-navigation, document-search replacement, read-first empty
  annotations, delete/edit undo isolation, and pre-mutation rejection of a
  multi-page Highlight with Note. The signed production host passes all 65
  cases, including a lazy-Popup-reinsertion regression and exact undo of an
  imported Popup's independent color and appearance.

See `docs/CURRENT.md` for the concise repository state and
`docs/TESTING.md` for all fixture, signing, evidence, permission, and cleanup
rules.

## Decisions

- The accepted product and compatibility contract lives in
  `docs/decisions/annotation-popup-interoperability.md`.
- Edited snapshots are reparsed before acceptance. Reject page, geometry,
  annotation, relationship, or metadata drift.
- 2026-07-14: A controlled PDFKit serialization/reload probe dropped reciprocal
  popup topology, so the undocumented append option is not the active
  persistence backend. This does not claim that every PDFKit-to-Preview path is
  impossible; a bounded end-to-end experiment remains available only if qpdf
  becomes materially blocked. PDFKit remains the runtime viewer; dirty saves
  use the embedded qpdf parser/writer. Do not replace it with a handwritten
  xref/object-stream parser or an external executable.
- Test hosts run serially with document/window restoration disabled. A
  permission sheet is a failed validation route, never an approval request to
  work around.
- Production `MathPDF.app` hosting with default Automatic Apple Development
  signing is the normal unit-test route. The isolated host is fallback evidence
  only and cannot by itself satisfy a production-host release gate.
- UI workflow tests use the real `DocumentGroup` scene. Do not introduce a
  parallel DEBUG `NSWindow`; it changes undo, menus, autosave, and document
  semantics and can turn harness behavior into false product conclusions.
- No-op snapshots remain byte-identical. PDFs without a proven safe edit path
  remain read-only rather than silently losing semantics.
- Required build and test evidence is signed and normally runs outside the agent
  sandbox. Unsigned runs are diagnostic only.

## Next Steps

- [x] Introduce the persistence backend boundary and replace PDFKit append
      serialization with an embedded qpdf writer.
- [x] Correct the two orphan-popup failures exposed by the qpdf-backed round-
      trip validator.
- [x] Correct exact popup-edge validation, popup-preserving undo, and fail-closed
      untracked graph mutation.
- [x] Expand popup graph, repeated-save, color, undo, and read-only
      regression coverage; run the full signed `MathPDFTests` suite.
- [x] Validate realistic Preview-authored input, orphan/conflicting graph
      handling, locked annotation flags, and a third-party raw-parser matrix.
- [x] Review the compatibility impact and commit the reciprocal-popup slice.
- [x] Replace the detached note surfaces and toolbar; add palette continuity and
      on-page note affordances without changing stored annotation semantics.
- [x] Re-run the UI tests serially from `/private/tmp/MathPDF-DerivedData`
      through the real `DocumentGroup` scene.
- [x] Prove the structural Popup presentation split with the full signed unit
      suite and visually confirm exactly one MathPDF affordance and one note
      surface.
- [x] Confirm that Preview still receives its native affordance from the saved
      reciprocal graph.
- [x] Inspect a `/tmp/MathPDF-Fixtures` research excerpt across the full
      workflow, obtain an independent static design ship verdict, and terminate
      every MathPDF instance.
- [ ] Obtain the explicitly required independent Computer Use interaction
      verdict. Three bounded attempts returned no visible state; each was
      classified `UNVERIFIED`, interrupted, and cleaned up rather than inferred
      from screenshots or code.
- [x] Author and check-only gatekeep the final holistic interactive-review
      prompt; retain it in `docs/FINAL_INTERACTIVE_REVIEW_PROMPT.md` until the
      signed candidate is ready.

## Validation

Passed:

- 2026-07-13: commit `eaf9ce1`; 25 out-of-sandbox signed unit/integration tests
  passed for the then-current popup-normalization policy.
- 2026-07-13: signed `build-for-testing` and
  `scripts/build-and-launch.sh --signed --build-only`; signature and sandbox,
  network-client, and user-selected read/write entitlements verified.
- 2026-07-12: signed manual validation on a realistic seven-page fixture under
  `/tmp/MathPDF-Fixtures`; annotation activation, navigation, Back, macros,
  outline, note presentation, Print, and cleanup passed.
- 2026-07-14: signed `MathPDFDocumentTests` reached all 10 tests without a
  Documents prompt after `388970b`; 6 passed and 4 exposed a real
  whole-second timestamp-validator mismatch.
- 2026-07-14: after timestamp normalization, the same nonparallel signed suite
  passed 7/10 and exposed actual sequential-write data loss; result bundle
  `.build/SignedDerivedData/Logs/Test/Test-MathPDF-2026.07.14_20-04-15--0700.xcresult`.
- 2026-07-14: a temporary production-host probe using default Xcode signing
  passed all three `MathPreambleCompilerTests` before and after a rebuild. The
  CDHash changed while the Apple Development designated requirement remained
  stable, and neither run requested Documents access.
- 2026-07-14: the normal production-host `MathPDFDocumentTests` run completed
  without a permission prompt and passed 8/10; both failures were orphan-popup
  semantic assertions in the active qpdf path.
- 2026-07-14: after two-pass popup binding and persistence-owned exact edges,
  the signed production-host `MathPDFDocumentTests` suite passed 14/14. The
  expanded corpus covers repeated snapshots, delete/undo/redo, identical
  annotations, color changes, interleaved documents, and fail-closed untracked
  mutation.
- 2026-07-14: after independent review, raw fixtures and repairs raised the
  signed document suite to 17/17. Both one-sided graph directions, imported
  popup sentinel preservation, and duplicate `/NM` rejection pass.
- 2026-07-14: the full signed production-host `MathPDFTests` suite passed 33/33
  in seven suites without a Documents prompt.
- 2026-07-14: signed build-for-testing from
  `/private/tmp/MathPDF-DerivedData` succeeded after the interaction redesign;
  the full signed production-host unit suite again passed 33/33.
- 2026-07-14: Computer Use on
  `/private/tmp/MathPDF-Fixtures/practice-of-curves-annotated-excerpt.pdf`
  verified runtime comment badges, one contained read surface, and in-place
  editing. A first-pass source-highlight overlap was fixed and rechecked.
- 2026-07-15: the expanded signed production-host suite passed 49/49 in eight
  suites before the presentation-graph correction. The corpus includes exact
  imported owner undo, Popup-private metadata, locked flags, and `/Annots`
  order.
- 2026-07-15: the structural Popup-presentation correction and removal of the
  DEBUG replacement window pass Swift parsing, `git diff --check`, unsigned
  `build`, and unsigned `build-for-testing` for all three targets under
  `/private/tmp/MathPDF-CompileCheck`.
- 2026-07-15: the follow-up visible-order reconciliation and fail-closed direct
  removal/cross-page-move regressions pass Swift parsing, `git diff --check`,
  and unsigned `build-for-testing` for all three targets in the same diagnostic
  derived-data location.
- 2026-07-15: the 58-case source plus the interaction-state lifecycle repairs
  pass Swift parsing, `git diff --check`, and unsigned `build-for-testing` for
  the app, unit-test, and UI-test targets. This remains compile evidence rather
  than signed runtime evidence.
- 2026-07-15: the normal automatically signed production `MathPDF.app` host
  passed 65/65 unit tests in eight suites at
  `/tmp/MathPDF-DerivedData/Logs/Test/Test-MathPDF-2026.07.15_03-15-18--0700.xcresult`.
  No `MathPDFTestHost` or GUI-facing file path was used.
- 2026-07-15: all three signed UI tests passed through the real `DocumentGroup`
  scene at `Test-MathPDF-2026.07.15_03-15-36--0700.xcresult`; every launched
  app was explicitly terminated. The workflow verified note read/edit access,
  palette change and Undo, selected-row reopen, document macros, and one custom
  note surface.
- 2026-07-15: direct Computer Use inspection of the same signed candidate
  verified the former PDFKit yellow closed-Popup marker is absent. One compact
  MathPDF comment badge remains attached to the highlighted passage.
- 2026-07-15: `pypdf` independently parsed the realistic mixed annotation
  fixture and confirmed the MathPDF-authored owner `/Popup` reference and the
  Popup's reciprocal `/Parent`. Preview then opened the disposable
  `/private/tmp/MathPDF-Fixtures/final-review-working.pdf`, displayed its native
  green marker and sidebar note, and XCUITest double-clicked the marker to expand
  Preview's native popup with the MathPDF-authored text.
- 2026-07-15: a first independent screenshot review returned `VISUAL NO-PASS`.
  After the native-toolbar, attached-badge, note-surface, sidebar-density, color-
  continuity, and scroll-indicator corrections, the same independent authority
  returned `VISUAL PASS` on clean app-window evidence.
- 2026-07-15: a QA-only AppleScript bounds query—not MathPDF—created a ChatGPT
  Automation prompt for `System Events` and obstructed one UI run. The prompt
  was explicitly denied, AppleScript/System Events were removed from the QA
  route, and the rule is now durable in `docs/TESTING.md`.
- 2026-07-15: after removing every one-off cleanup/Preview test, the final full
  signed production-host UI suite passed 3/3 at
  `/tmp/MathPDF-DerivedData/Logs/Test/Test-MathPDF-2026.07.15_04-19-13--0700.xcresult`.
  Each test explicitly quit MathPDF; no permission prompt or document path was
  involved.

Not yet validated:

- Independent design/product interaction through Computer Use. The final static
  evidence has `VISUAL PASS`, and XCUITest proves the workflows, but the separate
  expert Computer Use channel has stalled on every bounded attempt without
  returning visible state. This is an evidence limitation, not a known product
  failure.
- Idle autosave, Save As, Revert, close review, failure UI, external-file
  conflicts, real multi-window routing, accessibility configurations, and large-
  document responsiveness remain GUI/manual gates as defined in
  `docs/TESTING.md`.

## Compatibility Impact

The active slice replaces deliberate on-disk popup removal with reciprocal
relationship preservation, while structurally excluding Popup companions from
PDFKit's runtime page-presentation graph. The observed PDFKit append result was
not reliable enough to be the active writer, and qpdf is the embedded writer.
Headless semantic reparsing proves owner text, exact popup
edges, standalone notes, page geometry/content, unrelated annotations, forms,
outlines, metadata, preamble state, and no-op bytes across repeated and
multi-document saves. Independent parsing plus direct Preview marker expansion
now confirm the realistic interoperability path. Any regression is a release
blocker.
