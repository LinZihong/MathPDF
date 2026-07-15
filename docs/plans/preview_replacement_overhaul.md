# Preview-Replacement Reader Overhaul

Status: active
Last updated: 2026-07-14
Context: existing-project change
Scheme: MathPDF
Simulator: none, macOS app

## Scope

Finish the remaining interoperability and release-evidence delta for the native
Preview-replacement reader. Stable product behavior is defined in
`docs/initial_description.txt`; this Work Card does not restate it.

This active slice changes PDF annotation compatibility. It does not change math
fallback behavior or the per-document preamble format.

## Non-Goals

- Do not expand Preview parity beyond the documented research-PDF workflow.
- Do not add a proprietary annotation format or duplicate `/Text` notes.
- Do not redesign the shipped reader shell while closing this validation slice.
- Do not treat historical plan commands as current validation instructions.

## Current State

- Commit `eaf9ce1` is the validated checkpoint for the broader reader overhaul.
- The working tree implements reciprocal popup persistence, guarded incremental
  saves, semantic postvalidation, byte-identical no-op snapshots, per-revision
  caching, and fail-closed editing for unsupported PDFs.
- The active changes are uncommitted and have not passed a fresh signed suite.
- Final unlocked-desktop UI tests and the independent visual ship verdict remain
  open.

See `docs/CURRENT.md` for the concise repository state and
`docs/TESTING.md` for all fixture, signing, evidence, permission, and cleanup
rules.

## Decisions

- The accepted product and compatibility contract lives in
  `docs/decisions/annotation-popup-interoperability.md`.
- Edited snapshots use incremental append and are reparsed before acceptance.
  Reject page, geometry, annotation, relationship, or Keywords drift.
- No-op snapshots remain byte-identical. PDFs without a proven safe edit path
  remain read-only rather than silently losing semantics.
- Required build and test evidence is signed and normally runs outside the agent
  sandbox. Unsigned runs are diagnostic only.

## Next Steps

- [ ] Run the focused signed interoperability tests.
- [ ] Run the full signed `MathPDFTests` suite.
- [ ] Review the compatibility impact and commit the reciprocal-popup slice if
      the semantic gates pass.
- [ ] On an unlocked, explicitly approved desktop, run the three UI tests from
      `/tmp/MathPDF-DerivedData`.
- [ ] Inspect a `/tmp/MathPDF-Fixtures` research excerpt, obtain the independent
      visual ship verdict, and terminate every MathPDF instance.

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

Not yet validated:

- The active reciprocal-popup persistence implementation.
- Idle autosave, Save As, Revert, close review, failure UI, external-file
  conflicts, real multi-window routing, accessibility configurations, and large-
  document responsiveness remain GUI/manual gates as defined in
  `docs/TESTING.md`.
- The last approved UI run was environmentally blocked by a locked session and
  `Running Background`; it produced no passing product assertion.

## Compatibility Impact

The active slice replaces deliberate popup removal with reciprocal relationship
preservation. Before commit, semantic reparsing must prove owner text, popup
ownership, standalone notes, page geometry, unrelated annotations, metadata,
and no-op bytes remain correct. Any regression is a release blocker.
