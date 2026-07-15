# Annotation Popup Interoperability

Status: accepted product and compatibility decision
Date: 2026-07-14

## Decision

Plain-text `/Contents` on the owning highlight or standalone `/Text` annotation
is authoritative. A highlight note must not gain a duplicate `/Text` annotation.

When a popup companion is present or required, saved output preserves or creates
one reciprocal owner `/Popup` to companion `/Parent` relationship. Popup
companions are relationships, not independent notes or sidebar entries. MathPDF
may suppress PDFKit's popup presentation only in memory and present one
math-aware reading surface of its own.

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

The active implementation and its unvalidated state are tracked in
`docs/CURRENT.md` and `docs/plans/preview_replacement_overhaul.md`. Required
proof is defined in `docs/TESTING.md`.
