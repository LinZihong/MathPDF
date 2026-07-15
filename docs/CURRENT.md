# Current State

Last updated: 2026-07-14

This file records current implementation and validation state only. Product
requirements live in `docs/initial_description.txt`; validation rules live in
`docs/TESTING.md`; the active delta lives in
`docs/plans/preview_replacement_overhaul.md`.

The scheme is `MathPDF`. This is an existing macOS project; no simulator is
used.

## Committed and validated baseline

- `eaf9ce1` is the last committed checkpoint.
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
- This interoperability delta is implemented but uncommitted and has not passed
  a fresh signed test run. Do not describe it as validated or shipped.

## Open validation gates

- The UI-test target compiles, but the last approved run reached `Running
  Background` after the Mac locked; no product assertion ran. When the desktop
  is unlocked, run the three UI tests from `/tmp/MathPDF-DerivedData`.
- Visually inspect a research excerpt under `/tmp/MathPDF-Fixtures`, obtain the
  independent design ship verdict, and quit every MathPDF instance.
- Apply `docs/TESTING.md` exactly. `TestPDFs/` remains read-only source material
  and is never a GUI launch target.

## Next safe action

Run the focused signed interoperability tests and then the full signed unit
suite, outside the agent sandbox when signing resources require it. Do not begin
the remaining GUI gates until the desktop is unlocked and execution is approved.
