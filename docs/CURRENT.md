# Current State

Last updated: 2026-07-14

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
- Native per-document windows provide outlines, Highlights and Notes, search,
  page entry, grouped zoom controls, printing, Save As, Revert, annotation
  authoring, undo, and document autosave.
- Direct annotation activation preserves the viewport. Sidebar navigation
  preserves scale, minimally reveals offscreen targets, updates the page field,
  and maintains truthful Back history.
- MathPDF presents one in-app reading surface per note. Existing notes open
  read-first in an anchored popover or trailing inspector; explicit Edit and New
  Note enter plain-text editing.
- Bundled KaTeX supports common delimiters, document-scoped aliases, simple
  parameterized commands, and math operators, with readable raw-text fallback.
- The document preamble uses a versioned marker in standard PDF Keywords while
  preserving unrelated metadata.
- The checkpoint passed 25 out-of-sandbox signed unit/integration tests. That
  evidence covers the checkpoint's then-current popup-normalization policy, not
  the active reciprocal-popup delta.
- A signed manual pass on
  `/tmp/MathPDF-Fixtures/58x-annotations-short.pdf` verified one-popover
  ownership, direct-click viewport stability, sidebar page/zoom navigation,
  Back, and the native Print menu. All launched MathPDF/test processes were
  terminated afterward.

## Working-tree changes, not yet validated

- The working tree adds reciprocal `/Popup` and `/Parent` persistence through
  PDFKit's incremental append path, post-save semantic validation, byte-identical
  no-op snapshots, per-revision snapshot caching, and read-only handling for
  encrypted, signed, non-commentable, or otherwise unsupported edits.
- After whole-second `/M` normalization, the permission-clean signed document
  suite passed 7/10 and exposed real PDFKit append corruption across sequential
  writes in one process: a created `/Text` note disappeared, edited highlight
  `/Contents` became nil, and an unrelated page bleed box drifted. The result
  bundle is
  `.build/SignedDerivedData/Logs/Test/Test-MathPDF-2026.07.14_20-04-15--0700.xcresult`.
- Independent review therefore blocks the undocumented PDFKit append writer.
  Isolated green tests are not acceptance evidence for this backend.
- The audit also confirmed incomplete owner-to-popup edge validation,
  delete/undo popup metadata loss, locked-popup mutation, read-only creation
  crashes, and unsafe orphan inference.
- The requested interaction redesign remains unimplemented: the detached note
  inspector/popover and current toolbar are not acceptance-ready.

## Open validation gates

- Rerun the signed document suite after every serializer correction, then the
  full signed unit suite.
- Build and run the three UI tests serially from
  `/tmp/MathPDF-DerivedData`; their shared scheme now suppresses document
  restoration, but the fixture and explicit-termination rules still apply.
- Visually inspect a research excerpt under `/tmp/MathPDF-Fixtures`, obtain the
  independent design ship verdict after the interaction redesign, and quit
  every MathPDF instance.
- Apply `docs/TESTING.md` exactly. `TestPDFs/` remains read-only source material
  and is never a GUI launch target.

## Next safe action

Replace PDFKit serialization behind an `AnnotationPersistenceBackend` boundary
with a standards-aware low-level writer, retain PDFKit for viewing, and rerun
the signed multi-document/repeated-save semantic corpus before committing the
compatibility slice.
