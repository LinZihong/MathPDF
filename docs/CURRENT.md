# Current State

Last updated: 2026-07-13

The Preview-replacement overhaul is implemented as an existing-project change.
Final unlocked-desktop UI validation remains open.
The exact scheme is `MathPDF`; this is a macOS app and no simulator is used.

What works:

- Native per-document windows with a standard-height unified toolbar and a quiet title menu for
  Table of Contents or Highlights and Notes,
  always-visible PDF search with result navigation, direct page entry, grouped
  zoom controls, printing, Save As, and Revert.
- Highlight creation, box-note creation, plain-text editing, undo, and native
  document autosave.
- One annotation has one in-app reading affordance. MathPDF intercepts PDFKit
  annotation clicks before PDFKit can also open a popup, while drag selection is
  handed back to PDFKit.
- On save, PDFKit popup companions are normalized out of a serialized copy
  because PDFKit does not reliably preserve their `/Popup` and `/Parent`
  relationship. The owning highlight or text annotation retains the plain-text
  note, so other readers receive one interoperable annotation instead of an
  orphaned duplicate; the live document is not mutated by serialization.
- Direct annotation clicks preserve the viewport. Sidebar selection preserves
  scale, minimally reveals offscreen annotations, updates the page counter, and
  preserves truthful Back history.
- Short notes use an anchored native popover; long or constrained notes use the
  trailing inspector. Existing notes open read-first; only New Note or explicit
  Edit places focus in the plain-text editor.
- Inspector destinations are mutually exclusive, note-list rows stay spatially
  stable, selected notes support Delete, and temporary note placement uses a
  crosshair with Escape and missed-click cancellation.
- Bundled KaTeX renders common delimiters plus document-scoped `\newcommand`
  aliases, simple parameterized commands, and `\DeclareMathOperator`. Failures
  stay readable as raw text.
- The preamble is stored as a versioned Base64 marker in standard PDF Keywords,
  preserving unrelated keywords and importing both PDFKit- and externally-
  authored metadata.
- Signed local builds use ad-hoc “Sign to Run Locally” signing and verify the
  sandbox, network-client, and user-selected read/write entitlements.

Validation state:

- Twenty-five signed unit/integration tests pass, including PDFKit
  page/scale/Back navigation, multiline highlight geometry, edge-clamped note
  placement, exact annotation identity, document isolation, adversarial
  semantic PDF preservation, popup normalization, and runtime
  renderer-injection checks.
- The UI-test target compiles. Execution was explicitly approved and moved to
  `/tmp/MathPDF-DerivedData`, with a debug-only in-memory fixture window that
  bypasses the document Open panel. The final run could not activate because
  the Mac locked after the user left; XCTest recorded `Running Background`.
  This is an environmental block, not a passing result.
- Computer Use validation passed on
  `/tmp/MathPDF-Fixtures/58x-annotations-short.pdf`, a seven-page excerpt of a
  supplied research PDF with realistic annotations and document macros.
- Direct page activation produced exactly one popover while page 1 and 208%
  zoom remained unchanged. Sidebar navigation to page 3 preserved 195% zoom,
  updated the page field, and Back returned to page 1. The native File menu
  contains Print.
- All MathPDF and UI-test processes were terminated after testing.

User material:

- `TestPDFs/` is untracked and was not modified. Manual fixtures belong under
  `/tmp/MathPDF-Fixtures`; never open the originals for a validation edit.

Next unlocked-desktop action:

- Run the three MathPDF UI tests from `/tmp/MathPDF-DerivedData`, visually check
  the active research-PDF window after the final toolbar/search changes, obtain
  the independent design ship verdict, and quit every MathPDF window.
