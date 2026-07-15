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
- `0fb21e7` records the stable production-host signing route, fixture boundary,
  permission escape protocol, and test-host fallback policy.
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
  read-first in an anchored popover or trailing inspector; explicit Edit and New
  Note enter plain-text editing.
- Bundled KaTeX supports common delimiters, document-scoped aliases, simple
  parameterized commands, and math operators, with readable raw-text fallback.
- The document preamble uses a versioned marker in standard PDF Keywords while
  preserving unrelated metadata.
- The checkpoint passed 25 out-of-sandbox signed unit/integration tests. That
  evidence covers the checkpoint's then-current popup-normalization policy, not
  the active reciprocal-popup delta below.
- A signed manual pass on
  `/tmp/MathPDF-Fixtures/58x-annotations-short.pdf` verified one-popover
  ownership, direct-click viewport stability, sidebar page/zoom navigation,
  Back, and the native Print menu. All launched MathPDF/test processes were
  terminated afterward.

## Working-tree changes, headlessly validated

- The working tree adds reciprocal `/Popup` and `/Parent` persistence through
  an embedded qpdf-backed writer, post-save semantic validation, byte-identical
  no-op snapshots, per-revision snapshot caching, and read-only handling for
  encrypted, signed, non-commentable, or otherwise unsupported edits. PDFKit
  remains the viewer and in-memory annotation surface.
- The writer owns its annotation identity and reciprocal edge graph instead of
  trusting PDFKit's transient popup topology. It rejects unregistered runtime
  mutations and validates exact output edges before returning a snapshot.
- The normal signed production-host document suite passes 14/14. It covers
  standalone Text notes, highlight notes, unrelated metadata and annotations,
  repeated revisions, delete/undo/redo, identical geometry and contents,
  color changes, multi-document isolation, no-op bytes, and fail-closed
  untracked mutation. The full signed production-host unit suite passes 30/30.
  Neither run requested Documents access, and the host exited afterward.
- The adversarial lifecycle corpus exposed a PDFKit behavior in which assigning
  `annotation.popup = nil` clears the owner's `contents`. Detach, reattach, and
  color-change paths now preserve owner text explicitly, with regressions.
- The earlier PDFKit serializer probe dropped reciprocal popup topology, so the
  undocumented append backend is not the active writer. That is not a proof
  that every controlled PDFKit-to-Preview workflow must fail; a narrowly scoped
  end-to-end experiment remains a fallback only if qpdf becomes blocked. The
  embedded qpdf boundary is the accepted persistence direction pending real
  Preview and independent-parser handshake evidence.
- The requested interaction redesign remains unimplemented: the detached note
  inspector/popover and current toolbar are not acceptance-ready.

## Open validation gates

- Commit the headlessly green reciprocal-popup slice without staging the
  user-owned `TestPDFs/` source corpus.
- Validate a realistic Preview-authored and MathPDF-authored annotation matrix
  under `/tmp/MathPDF-Fixtures` with raw dictionaries and an independent parser.
- Build and run the three UI tests serially from
  `/tmp/MathPDF-DerivedData`; their shared scheme now suppresses document
  restoration, but the fixture and explicit-termination rules still apply.
- Visually inspect a research excerpt under `/tmp/MathPDF-Fixtures`, obtain the
  independent design ship verdict after the interaction redesign, and quit
  every MathPDF instance.
- Apply `docs/TESTING.md` exactly. `TestPDFs/` remains read-only source material
  and is never a GUI launch target.

## Next safe action

Commit the reciprocal-popup slice, then replace the detached annotation surfaces
and undersized toolbar. Use the production app host and default Xcode signing;
use `MathPDFTestHost` only if that normal route becomes blocked again.
