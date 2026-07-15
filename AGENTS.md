# MathPDF Agent Guide

MathPDF is an existing macOS SwiftUI/PDFKit project. Its product source of
truth is [`docs/initial_description.txt`](docs/initial_description.txt). Read
that first, then [`docs/CURRENT.md`](docs/CURRENT.md) for the active state. Do
not infer extra platforms, features, or storage formats.

The project documents have separate jobs, not one global precedence ladder:

- `docs/initial_description.txt` owns accepted product behavior and scope.
- `docs/CURRENT.md` owns drift-prone working-tree and validation state.
- `docs/TESTING.md` owns validation, fixture, permission, and evidence rules.
- `PLANS.md` owns Work Card policy; active Work Cards contain only substantial
  workstream deltas and decisions.

Direct user instructions control the current task. Within each document's
domain, follow its owning document and verify implementation claims against the
working tree and fresh evidence. Historical plans and reports are context, not
current instructions.

## Outcome

Ship a minimal, native PDF reader for mathematical annotation work:

- PDF annotation contents remain interoperable plain text.
- MathPDF renders supported TeX for reading and falls back to readable source.
- PDF viewing, navigation, annotation editing, saving, and interoperability are
  trustworthy enough to replace Preview for the documented workflow.
- The PDF stays visually dominant; avoid knowledge-management feature creep or
  custom chrome that duplicates native macOS behavior.

Treat changes as existing-project work. Preserve the Xcode project, `MathPDF`
scheme, targets, and established architectural boundaries. Restructure them
only when the user explicitly requests it or an active Work Card identifies a
concrete incompatibility with the requested outcome.

## Durable Constraints

- Keep UI, PDF/annotation integration, domain logic, and math rendering
  separated. Prefer testable services over document logic in SwiftUI views.
- Plain-text annotation contents are authoritative. Do not introduce a
  proprietary note format or a companion `/Text` annotation for a highlight.
- Preserve or create standards-valid annotation relationships on disk. MathPDF
  may suppress PDFKit popup presentation in memory, but saved output must not
  contain duplicate or orphaned annotations.
- Any implementation change that can alter serialized PDF annotation semantics
  or metadata requires semantic round-trip tests. Record its compatibility
  impact in the active Work Card, or in `docs/decisions/` when the decision is
  durable. Never weaken a failing preservation test merely because PDFKit
  produced the loss.
- Broken or unsupported TeX must remain readable. Document macros are scoped to
  the PDF and stored in the documented metadata marker.
- Use native macOS document, toolbar, sidebar, inspector, menu, keyboard,
  accessibility, undo, and window conventions by default. Depart from one only
  when the documented workflow requires behavior it cannot provide, and record
  the reason in the active Work Card.

## Validation

Follow [`docs/TESTING.md`](docs/TESTING.md). Use the narrowest check that proves
the changed contract, then expand in proportion to risk.

```sh
xcodebuild -project MathPDF.xcodeproj -scheme MathPDF \
  -derivedDataPath /private/tmp/MathPDF-DerivedData build
xcodebuild -project MathPDF.xcodeproj -scheme MathPDF \
  -derivedDataPath /private/tmp/MathPDF-DerivedData \
  -only-testing:MathPDFTests test
scripts/build-and-launch.sh --signed --build-only
```

Installed Build macOS Apps skills supplement this repository's workflow with
generic command selection, debugging, and failure classification. When their
guidance differs from this file or `docs/TESTING.md`, follow the repository
rules. Reuse `scripts/build-and-launch.sh`; do not create a competing build/run
entrypoint or Codex Run action unless the user explicitly requests one.

Required build and test validation must use signed products. A one-off unsigned
build may be used only as an explicitly labeled diagnostic and does not satisfy
a validation gate. Keep the app sandbox's outgoing-network and user-selected
read/write entitlements; the bundled WebKit renderer and document editing depend
on them. Do not persist `CODE_SIGNING_ALLOWED = NO` in project settings, schemes,
or scripts.

Signed `xcodebuild` commands usually require out-of-sandbox execution on this
machine so the signing process can use the necessary system and keychain
resources. If a required signed build or test fails inside the agent sandbox
with signing, keychain, or permission evidence, rerun the same command with
out-of-sandbox permission. Do not replace the required signed check with an
unsigned build.

For changes observable through the app UI, a build alone does not satisfy the
GUI validation gate. When approved and the desktop is available, exercise the
changed path in a visible app, inspect it, and quit every MathPDF instance. If
GUI execution is not approved or the desktop is unavailable, report that gate
as unverified; do not substitute a build or unit-test pass for it. UI tests
require assertions, stable accessibility identifiers, deterministic fixtures,
and explicit application termination.

## Fixture and Permission Invariant

`TestPDFs/` contains read-only source material, not launch fixtures. Never pass
a GUI-facing PDF path inside `TestPDFs/`, this checkout, or any other Documents
directory to MathPDF, Preview, XCTest, `open`, or GUI automation. This does not
restrict CLI tools from reading the checkout or source PDFs. Derive a short
realistic fixture with CLI tools, place it under `/tmp/MathPDF-Fixtures`, resolve
its launch path under `/private/tmp/MathPDF-Fixtures`, and launch only that copy
or the documented debug-only in-memory fixture. Never edit a supplied PDF in
place.

A permission prompt is an immediate stop signal. Before launching a GUI
validation route, record its expected first observable state; failure to reach
that state within 30 seconds is also a stop signal. Follow the bounded recovery
protocol in `docs/TESTING.md`: terminate and inspect once, retry at most once,
then report the gate unverified. Never wait for an absent user, alter TCC, or
broaden Documents access.

The primary agent owns this stop decision. Any delegated validation prompt must
repeat the safe-fixture boundary, the 30-second signal, the one-retry limit, and
the requirement to report back instead of waiting.

## Project Records

- For work that materially changes product behavior, crosses architectural
  boundaries, or will span sessions, follow [`PLANS.md`](PLANS.md): create or
  update a Work Card under `docs/plans/`, and update
  [`docs/plans/WORK_CARD_INDEX.md`](docs/plans/WORK_CARD_INDEX.md) when the card is
  created or its lifecycle status changes.
- Keep `docs/CURRENT.md` short and factual when active work remains.
- Update the product description when accepted product-facing behavior changes,
  not merely for an experimental working-tree implementation.
- In every implementation completion report or durable work handoff, state the
  `MathPDF` scheme, that the change was made in the existing macOS project with
  no simulator, and the exact validation completed and left unverified.
