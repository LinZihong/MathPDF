# Preview-Replacement Reader Overhaul

Status: active
Last updated: 2026-07-14
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
- The working tree implements reciprocal popup persistence through an embedded
  qpdf-backed writer, semantic postvalidation, byte-identical no-op snapshots,
  per-revision caching, and fail-closed editing for unsupported PDFs. PDFKit
  remains the viewer and in-memory annotation API.
- The writer now owns the authoritative identity/edge graph, rejects untracked
  PDFKit mutations, and requires reciprocal output edges. The orphan-popup
  failures were traced to one-pass discovery of PDFKit-created Text popups and
  corrected with two-pass binding plus explicit edge registration.
- The production-host document suite passes 14/14 and the full signed unit suite
  passes 30/30 without a Documents prompt. The adversarial revision corpus also
  found and locked down PDFKit clearing owner contents when `popup` is detached.
- The detached note inspector/popover and toolbar remain the old interaction and
  must be replaced. The design direction is one context-preserving annotation
  surface with restrained color continuity and a quieter native hierarchy.
- Final unlocked-desktop UI tests and the independent visual ship verdict remain
  open.

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
- [ ] Validate realistic Preview-authored input, one-sided/orphan conflict
      handling, annotation flags, and an independent raw-parser matrix.
- [ ] Review the compatibility impact and commit the reciprocal-popup slice if
      the semantic gates pass.
- [ ] Replace the detached note surfaces and toolbar; add palette continuity and
      on-page note affordances without changing stored annotation semantics.
- [ ] On an unlocked, explicitly approved desktop, run the three UI tests from
      `/tmp/MathPDF-DerivedData`.
- [ ] Inspect a `/tmp/MathPDF-Fixtures` research excerpt across the full
      workflow, obtain the independent interactive design ship verdict, and
      terminate every MathPDF instance.

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
- 2026-07-14: the full signed production-host `MathPDFTests` suite passed 30/30
  in seven suites without a Documents prompt.

Not yet validated:

- Preview-authored raw corpus comparison, independent-parser confirmation,
  one-sided/orphan conflict cases, and annotation-flag preservation.
- The integrated annotation interaction and toolbar redesign.
- Idle autosave, Save As, Revert, close review, failure UI, external-file
  conflicts, real multi-window routing, accessibility configurations, and large-
  document responsiveness remain GUI/manual gates as defined in
  `docs/TESTING.md`.
- The last approved UI run was environmentally blocked by a locked session and
  `Running Background`; it produced no passing product assertion.

## Compatibility Impact

The active slice replaces deliberate popup removal with reciprocal relationship
preservation. The observed PDFKit append result was not reliable enough to be
the active writer, and qpdf is the embedded writer. Headless semantic reparsing now proves owner text, exact popup
edges, standalone notes, page geometry/content, unrelated annotations, forms,
outlines, metadata, preamble state, and no-op bytes across repeated and
multi-document saves. Preview-authored corpus and independent-parser evidence
remain required before final compatibility sign-off. Any regression is a
release blocker.
