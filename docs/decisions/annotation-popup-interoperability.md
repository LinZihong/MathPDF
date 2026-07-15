# Annotation Popup Interoperability

Status: accepted product and compatibility decision
Date: 2026-07-14

## Decision

Plain-text `/Contents` on the owning highlight or standalone `/Text` annotation
is authoritative. A highlight note must not gain a duplicate `/Text` annotation.

When a popup companion is present or required, saved output preserves or creates
one reciprocal owner `/Popup` to companion `/Parent` relationship. Popup
companions are relationships, not independent notes or sidebar entries. MathPDF
keeps those companions and edges in its persistence graph but excludes them
from PDFKit's live page-presentation graph, clears the visible owner's live
`popup` pointer, then presents one math-aware affordance and reading surface of
its own. Page membership and mutable annotation flags alone are not accepted as
proof of suppression because PDFKit can paint a closed Popup marker from the
owner pointer even when the Popup is absent from `page.annotations`.

Compatibility means semantic preservation, not byte-for-byte identity after an
edit. Edited output must be reparsed before acceptance and must preserve page
geometry, owner contents, popup ownership, standalone notes, unrelated
annotations, and metadata. A no-op snapshot remains byte-identical. PDFs without
a proven safe edit path remain read-only.

## Evidence and limits

A controlled Preview-authored highlight note used the reciprocal `/Popup` and
`/Parent` graph. The supplied corpus also contains owner-only, reciprocal, and
orphaned popup states, so it is compatibility evidence rather than a canonical
writer fingerprint. Cross-reader UI behavior and unsupported signed, encrypted,
or structurally restricted edits remain separate validation concerns.

A separate controlled UI-fixture experiment created annotations through
PDFKit, serialized them with `PDFDocument.dataRepresentation()`, and reparsed
the result. In that path PDFKit emitted a Popup whose `/Parent` did not target
the owning page annotation, and MathPDF correctly opened the document read-only.
Seeding the same fixture through MathPDF's production writer produced a valid
reciprocal graph. This is evidence against that specific PDFKit authoring and
serialization path; it is not a claim that PDFKit can never produce an
interoperable annotation under any controlled workflow.

The active implementation and its unvalidated state are tracked in
`docs/CURRENT.md` and `docs/plans/preview_replacement_overhaul.md`. Required
proof is defined in `docs/TESTING.md`.
