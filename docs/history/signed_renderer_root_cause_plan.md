# Signed Renderer Root Cause And Fix

> **Historical and non-operational.** This completed renderer investigation
> preserves evidence only. Its old fixture paths and unsigned commands are not
> current instructions.

This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to date as work proceeds.

This historical document was originally maintained under
[PLANS.md](../../PLANS.md).

## Purpose / Big Picture

After this change, MathPDF should render math notes in both the unsigned local build and the signed sandboxed local build. A contributor should be able to build both variants intentionally, run small renderer experiments inside the app, and confirm that the canonical note in `pdfs for testing/ell_curves.pdf` no longer disappears in the signed copy.

This is an existing-project debugging and bug-fix slice. PDF annotation compatibility must remain unchanged because note contents stay plain text inside the PDF. Per-document preamble metadata is out of scope. The only intended product change is that the signed app must keep the rendered-note surface working instead of flashing raw text and then going blank.

## Progress

- [x] (2026-04-07 07:06Z) Reviewed `docs/initial_description.txt`, `AGENTS.md`, `PLANS.md`, `docs/plans/EXECPLAN_INDEX.md`, the prior KaTeX and signed-build probe plans, and the active renderer/tests/scripts code.
- [x] (2026-04-07 07:06Z) Updated `AGENTS.md` so future sessions know how to request signed and unsigned local builds without contaminating default `xcodebuild` behavior.
- [x] (2026-04-07 07:47Z) Added a renderer diagnostics surface and controlled experiment modes so the signed app can expose WebKit state, JavaScript success/failure, and local-resource behavior without relying on visual guesswork alone.
- [x] (2026-04-07 07:47Z) Ran narrow signed-versus-unsigned experiments, recorded them here, and isolated the smallest causal difference.
- [x] (2026-04-07 07:47Z) Implemented the production fix once the root cause was proven, then ran focused tests, full builds, and fixture-based signed/unsigned app validation.

## Surprises & Discoveries

- Observation: the app currently inlines the KaTeX JavaScript and stylesheet into the HTML document, but the stylesheet still references separate local font files via relative `url(...)` entries.
  Evidence: `MathPDF/MathNoteRendering.swift` reads `katex.min.css`, strips `fonts/`, and passes the app bundle resource directory as the `baseURL` for `loadHTMLString`.

- Observation: the signed-versus-unsigned split is already strong enough that product debugging cannot rely on only the unsigned helper flow.
  Evidence: `docs/history/signed_build_probe_plan.md` and
  `docs/history/xcode_run_weirdness.md` both record that a genuinely signed
  repo-local `xcodebuild` product reproduced the blank-renderer failure while
  the unsigned build rendered the same note.

- Observation: the signed failure is not specific to KaTeX, font files, inline JavaScript, or note-height messaging.
  Evidence: signed runs of the `plain-text`, `inline-js`, `inline-js-height`, `katex-no-fonts`, and full `production` experiments all produced the same blank note area while diagnostics reported `webContentTerminated: true`.

- Observation: removing `isInspectable` does not fix the signed failure.
  Evidence: after rebuilding the signed app without `webView.isInspectable = true`, the signed `plain-text` experiment still terminated the `WKWebView` web-content process.

- Observation: the broken signed app crashes both WebKit helper processes almost immediately after `loadHTMLString`.
  Evidence: `log show --style compact --last 3m --predicate 'process == "MathPDF"'` recorded `WebProcessProxy::didClose: (web process ... crash)` and `NetworkProcessProxy::didClose (Network Process ... crash)` during the signed `plain-text` probe.

- Observation: enabling the app sandbox's outgoing-network capability is the smallest change that flips the signed renderer from failing to healthy.
  Evidence: a one-off build with `xcodebuild ... ENABLE_OUTGOING_NETWORK_CONNECTIONS=YES build` added `com.apple.security.network.client` to the app entitlements and immediately made the signed `plain-text` and signed `production` runs succeed without any renderer-code changes.

- Observation: `WKWebView` in this sandboxed macOS app depends on `com.apple.security.network.client` even for local `loadHTMLString` content.
  Evidence: with the entitlement absent, both `com.apple.WebKit.WebContent` and `com.apple.WebKit.Networking` crashed; with the entitlement present, both helper processes stayed alive and OCR of the captured window showed the rendered note content in both `plain-text` and full `production` runs.

## Decision Log

- Decision: create a fresh ExecPlan for root-cause isolation instead of continuing the earlier signed-build probe plan.
  Rationale: the previous plan established the reproduction and tooling, but the current work is a deeper diagnostic-and-fix pass with new instrumentation, experiments, and acceptance criteria.
  Date/Author: 2026-04-07 / Codex

- Decision: add in-app experiment hooks before applying speculative fixes.
  Rationale: the signed app currently fails in a way that is easy to misread visually. The fastest path to a defensible fix is to make the app report which part of the `WKWebView` pipeline fails under signing.
  Date/Author: 2026-04-07 / Codex

- Decision: keep the file-open-event launch path and security-scoped document handling that were added during diagnosis.
  Rationale: signed local automation initially failed before renderer code even ran because a sandboxed app launched with only a raw CLI path could not open the fixture PDF. Switching the helper to `open -a <app> <pdf> --args ...` and handling file URLs through `.onOpenURL` fixed that independent signed-launch problem and remains the correct validation path.
  Date/Author: 2026-04-07 / Codex

- Decision: fix the production issue by enabling `ENABLE_OUTGOING_NETWORK_CONNECTIONS = YES` for the app target's Debug and Release configurations.
  Rationale: the decisive one-variable experiment showed that adding `com.apple.security.network.client` stops the signed `WKWebView` helper crashes and restores the production KaTeX renderer. This is narrower and more defensible than reworking HTML load modes or removing diagnostics.
  Date/Author: 2026-04-07 / Codex

## Outcomes & Retrospective

Outcome: completed. The signed and unsigned local apps now both render the canonical note in `pdfs for testing/ell_curves.pdf`, and the root cause is no longer speculative: the sandboxed app needed `com.apple.security.network.client` for `WKWebView` to keep its `WebContent` and `Networking` helpers alive. The renderer diagnostics, signed/unsigned helper workflow, and plan notes now preserve the elimination trail so a future contributor can explain the fix instead of rediscovering it.

## Context and Orientation

MathPDF is a macOS SwiftUI app rooted in `/Users/linzihong/Documents/Development/Xcode/MathPDF/MathPDF/`. The app target uses a sandbox when built with signing enabled. The note inspector routes note contents into `MathPDF/MathNoteRendering.swift`, which currently creates a `WKWebView`, generates an HTML document with inlined KaTeX JavaScript and CSS, and loads that document with `loadHTMLString(_:baseURL:)`.

The canonical manual validation fixture is `/Users/linzihong/Documents/Development/Xcode/MathPDF/pdfs for testing/ell_curves.pdf`. The helper workflow for local products is `/Users/linzihong/Documents/Development/Xcode/MathPDF/scripts/build-and-launch.sh`, which can now build either a signed or unsigned app into separate derived-data roots.

The key symptom to explain is this: in the unsigned app, the raw note text flashes briefly and then becomes rendered math. In the signed app, the raw note text flashes briefly and then disappears. That symptom suggests the page starts loading, but a later stage of the `WKWebView` rendering pipeline fails or blanks the content. The experiments in this plan are meant to split the problem into smaller questions: whether plain inline HTML works, whether inline JavaScript runs, whether native-to-JavaScript message handling works, whether local bundle-backed resource URLs work under the signed sandbox, and whether the current KaTeX bootstrap path is the specific failing piece.

## Plan of Work

First, extend `MathPDF/MathNoteRendering.swift` so the renderer can optionally run a small set of controlled experiments selected through environment variables. Each experiment must keep the same `WKWebView` shell but vary one suspected cause at a time, such as plain inline HTML, inline JavaScript DOM replacement, native height-message posting, KaTeX without external font dependencies, or the full production document. The Swift side must also expose a concise diagnostics model that records page events like navigation completion, web-content termination, JavaScript-reported render state, and any error text.

Second, surface those diagnostics in the app in a way that does not affect normal users, such as a hidden or environment-gated debug readout in the note inspector. The goal is to make the signed app tell us whether it reached a rendered state, stayed raw, terminated its web-content process, or lost access to a local dependency.

Third, run narrow experiments in both unsigned and signed builds. Start from the simplest cases and move upward: static HTML without JavaScript, inline JavaScript that replaces raw text, the current message-handler path, the KaTeX runtime without external font URLs if possible, and finally the full production document. Each experiment result must be recorded in this plan’s `Surprises & Discoveries` and `Decision Log` sections so a future contributor can follow the elimination trail.

Finally, once one causal variable is isolated, implement the smallest production fix. If the issue is local-resource access from `loadHTMLString`, prefer a fix inside the rendering layer, such as a file-based load mode with explicit read access or fully self-contained HTML assets. If the issue is elsewhere, keep the fix equally narrow. After the fix, remove or reduce any temporary diagnostics that are no longer needed for product behavior while preserving the most valuable automated checks.

## Concrete Steps

Run these commands from `/Users/linzihong/Documents/Development/Xcode/MathPDF`.

1. Use focused unit tests while iterating on renderer code:

       xcodebuild -project MathPDF.xcodeproj -scheme MathPDF -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO -only-testing:MathPDFTests test

2. Build an unsigned app for experiment runs:

       scripts/build-and-launch.sh --unsigned --build-only

3. Build a signed app for experiment runs:

       scripts/build-and-launch.sh --signed --build-only

4. Launch the canonical fixture in either mode once experiment environment variables exist:

       MATHPDF_OPEN_DOCUMENT="$PWD/pdfs for testing/ell_curves.pdf" scripts/build-and-launch.sh --unsigned

       MATHPDF_OPEN_DOCUMENT="$PWD/pdfs for testing/ell_curves.pdf" scripts/build-and-launch.sh --signed

5. After the fix, run the full macOS app build:

       xcodebuild -project MathPDF.xcodeproj -scheme MathPDF -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build

This section must be updated with the exact signed and unsigned experiment commands that were actually run, including any environment variables used to select the diagnostic scenario.

Actual commands used during this plan:

1. Build and launch the signed app against the fixture while selecting individual renderer experiments:

       scripts/build-and-launch.sh --signed --renderer-diagnostics --renderer-experiment plain-text "pdfs for testing/ell_curves.pdf"

       scripts/build-and-launch.sh --signed --renderer-diagnostics --renderer-experiment inline-js "pdfs for testing/ell_curves.pdf"

       scripts/build-and-launch.sh --signed --renderer-diagnostics --renderer-experiment inline-js-height "pdfs for testing/ell_curves.pdf"

       scripts/build-and-launch.sh --signed --renderer-diagnostics --renderer-experiment katex-no-fonts "pdfs for testing/ell_curves.pdf"

       scripts/build-and-launch.sh --signed --renderer-diagnostics --renderer-experiment production "pdfs for testing/ell_curves.pdf"

2. Capture the window for OCR-backed validation:

       /Users/linzihong/.codex/skills/macos-window-capture/scripts/capture_app_window.sh --app "MathPDF" --output /tmp/mathpdf-debug/<name>.png

3. Inspect signed-app logs for helper-process crashes:

       command log show --style compact --last 3m --predicate 'process == "MathPDF"'

4. Run the decisive one-variable entitlement experiment in a separate derived-data root:

       xcodebuild -project MathPDF.xcodeproj -scheme MathPDF -configuration Debug -derivedDataPath .build/SignedNetDerivedData ENABLE_OUTGOING_NETWORK_CONNECTIONS=YES build

       open -n -a "$PWD/.build/SignedNetDerivedData/Build/Products/Debug/MathPDF.app" "$PWD/pdfs for testing/ell_curves.pdf" --args --renderer-diagnostics --renderer-experiment plain-text

       open -n -a "$PWD/.build/SignedNetDerivedData/Build/Products/Debug/MathPDF.app" "$PWD/pdfs for testing/ell_curves.pdf" --args --renderer-diagnostics --renderer-experiment production

5. Confirm the entitlement actually changed:

       codesign -d --entitlements :- .build/SignedNetDerivedData/Build/Products/Debug/MathPDF.app

6. OCR the captured windows to confirm note content survives and renders:

       swift -e 'import Foundation; import Vision; import AppKit; ...'

7. Validate the final project settings through the normal helper paths:

       scripts/build-and-launch.sh --signed --renderer-diagnostics --renderer-experiment production "pdfs for testing/ell_curves.pdf"

       scripts/build-and-launch.sh --unsigned --renderer-experiment production "pdfs for testing/ell_curves.pdf"

8. Run the focused unit-test target:

       xcodebuild -project MathPDF.xcodeproj -scheme MathPDF -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO -only-testing:MathPDFTests test

## Validation and Acceptance

Treat this as an existing-project change. Use scheme `MathPDF`. Use no simulator because the checked-in app target is macOS.

Acceptance is behavioral and causal:

1. A contributor can intentionally build both unsigned and signed local apps without editing Xcode Build Settings.
2. Renderer diagnostics can distinguish at least these states: page loaded, rendered math produced, raw fallback produced, and a meaningful failure such as web-content termination or local-resource denial.
3. The experiment sequence identifies a specific root cause rather than only a workaround guess.
4. The production renderer fix makes the signed app render the canonical note in `ell_curves.pdf` instead of going blank.
5. The unsigned app still renders correctly, and malformed math still degrades to readable raw text rather than crashing or disappearing.

The smallest automated proof should remain a focused `MathPDFTests` run. Broader validation must include both a signed and an unsigned macOS app build, and the final report must say exactly which launch checks were run.

## Idempotence and Recovery

These diagnostics and build steps are safe to repeat because they do not migrate stored data or mutate PDFs. Rebuilding either app variant is safe because signed and unsigned helper flows use separate derived-data roots. If a temporary experiment path makes the app harder to use, keep it behind an environment variable so normal validation can return to the production path immediately.

If a candidate fix is disproven, revert only that narrow change, keep the improved diagnostics or tests that exposed the failure, and continue to the next experiment without erasing evidence.

## Artifacts and Notes

Preserve in this plan:

- the exact environment variables or launch arguments used to select each experiment
- the exact native diagnostics exposed by the renderer
- the strongest evidence for the root cause, such as a specific WebKit error, a terminated web-content callback, or a reproducible difference between `loadHTMLString` and a file-based load
- the exact focused test, build, and launch commands actually run on macOS with no simulator

## Interfaces and Dependencies

Keep using the existing Apple frameworks already in the macOS target: SwiftUI, WebKit, PDFKit, and Foundation. Keep note storage and extraction unchanged.

At the end of this work, the repository should still expose `MathNoteView` as the user-facing note-rendering view in `MathPDF/MathNoteRendering.swift`. It may also expose small supporting types there for diagnostics and controlled renderer experiments, provided those helpers stay local to the rendering layer and do not leak into unrelated document or sidebar code.

Revision note: created on 2026-04-07 to move from signed-versus-unsigned reproduction into root-cause isolation and a production fix for the signed `WKWebView` renderer failure.
