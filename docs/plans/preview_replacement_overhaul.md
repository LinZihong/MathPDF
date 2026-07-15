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
- The working tree implements reciprocal popup persistence, guarded incremental
  saves, semantic postvalidation, byte-identical no-op snapshots, per-revision
  caching, and fail-closed editing for unsupported PDFs.
- The permission-clean document suite initially passed 6/10 because the
  validator compared fractional in-memory timestamps with whole-second PDF
  `/M` values. After correct whole-second normalization, it passed 7/10 and
  exposed deeper writer corruption across sequential documents: a new
  `/Text` note vanished, edited highlight contents became nil, and an
  unrelated bleed box drifted.
- Independent review blocks the undocumented PDFKit append writer and confirms
  additional graph-validation, undo, edit-gating, read-only creation, and
  orphan-inference defects.
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
- 2026-07-14: The undocumented PDFKit append option is rejected as the
  persistence backend. PDFKit remains the runtime viewer; dirty saves move
  behind an `AnnotationPersistenceBackend` backed by a mature low-level PDF
  parser/writer. Do not replace it with a handwritten xref/object-stream parser
  or an external executable.
- Test hosts run serially with document/window restoration disabled. A
  permission sheet is a failed validation route, never an approval request to
  work around.
- No-op snapshots remain byte-identical. PDFs without a proven safe edit path
  remain read-only rather than silently losing semantics.
- Required build and test evidence is signed and normally runs outside the agent
  sandbox. Unsigned runs are diagnostic only.

## Next Steps

- [ ] Introduce the persistence backend boundary and replace PDFKit append
      serialization with an embeddable standards-aware writer.
- [ ] Correct exact popup-edge validation, popup-preserving undo, locked graph
      editing, read-only creation, and conflicting orphan handling.
- [ ] Expand popup graph, repeated-save, color, flags, undo, and read-only
      regression coverage; run the full signed `MathPDFTests` suite.
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

Not yet validated:

- The active reciprocal-popup persistence implementation.
- The integrated annotation interaction and toolbar redesign.
- Idle autosave, Save As, Revert, close review, failure UI, external-file
  conflicts, real multi-window routing, accessibility configurations, and large-
  document responsiveness remain GUI/manual gates as defined in
  `docs/TESTING.md`.
- The last approved UI run was environmentally blocked by a locked session and
  `Running Background`; it produced no passing product assertion.

## Compatibility Impact

The active slice replaces deliberate popup removal with reciprocal relationship
preservation. The attempted PDFKit append backend is rejected. Before commit, a
replacement writer plus independent semantic reparsing must prove owner text,
exact popup edges, standalone notes, page geometry/content, unrelated
annotations, forms, outlines, metadata, unknown annotation keys, and no-op
bytes remain correct across repeated and multi-document saves. Any regression
is a release blocker.
