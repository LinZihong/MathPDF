# Fix MathJax Note Rendering Fallback Regression

This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to date as work proceeds.

This document must be maintained in accordance with [PLANS.md](../../PLANS.md).

## Purpose / Big Picture

After this change, MathPDF should once again render supported LaTeX-style note content as typeset math instead of leaving the inspector stuck on the raw-text fallback seen in the current app. A user should be able to open `pdfs for testing/ell_curves.pdf`, select its one note, and see readable math in the inspector while malformed input still degrades to plain text without noisy failures.

This is an existing-project bug fix, not a feature expansion. PDF annotation compatibility remains unchanged because note contents stay plain text inside the PDF. Per-document preamble metadata also remains unchanged in this slice. The only intended product change is restoring the already-promised rendered-note behavior.

## Progress

- [x] (2026-04-05 22:40Z) Reviewed `docs/initial_description.txt`, `AGENTS.md`, `PLANS.md`, the completed MathJax renderer plan, and the current `MathNoteRendering.swift` implementation.
- [x] (2026-04-05 22:41Z) Confirmed that the bundled `tex-svg.js` resource is present in the built app, which narrows the failure to the `WKWebView` bootstrap or resource-loading path rather than a missing bundle asset.
- [ ] Tighten the renderer tests so they assert actual MathJax readiness or rendered DOM output rather than allowing the raw fallback to count as success.
- [ ] Fix the renderer so bundled MathJax executes inside `WKWebView` and drives the inspector to the rendered phase for valid math notes.
- [ ] Run focused tests, a full scheme build, and fixture-based launch validation using the macOS `MathPDF` scheme with no simulator.

## Surprises & Discoveries

- Observation: the current focused WebKit test only proves that fallback text appears in the DOM and explicitly allows `raw`, `rendered`, or `loading` states.
  Evidence: `MathPDFTests/MathPDFTests.swift` currently treats all three render states as acceptable in `webRendererLoadsFallbackTextIntoDOM()`, so the failure in the screenshot is invisible to CI.

- Observation: the built app bundle already contains `Contents/Resources/tex-svg.js`.
  Evidence: `find .build/DerivedData/Build/Products/Debug/MathPDF.app -maxdepth 4 -name 'tex-svg.js' -print` returned `.build/DerivedData/Build/Products/Debug/MathPDF.app/Contents/Resources/tex-svg.js`.

## Decision Log

- Decision: treat this as a renderer-integration regression and validate it with stronger automated checks before changing the production path.
  Rationale: the visible product failure is that valid math notes remain in raw fallback. The safest way to regain confidence is to make the test suite fail on that behavior first, then fix the implementation until both focused tests and fixture launch checks pass.
  Date/Author: 2026-04-05 / Codex

## Outcomes & Retrospective

This plan is in progress. The expected outcome is a MathJax-backed note inspector that renders valid math again while preserving raw-text fallback for bad input. The key lesson already visible is that fallback-only tests were too weak to protect the promised product behavior.

## Context and Orientation

The current reader shell lives in `MathPDF/ContentView.swift`. It shows the PDF on the left and the selected note inspector on the right. The note-rendering bridge lives in `MathPDF/MathNoteRendering.swift`, where a SwiftUI wrapper creates a `WKWebView`, generates an HTML document, loads the bundled `MathJax/tex-svg.js` resource, and tracks a render phase of `loading`, `raw`, or `rendered`.

The focused renderer tests live in `MathPDFTests/MathPDFTests.swift`. Those tests already verify note extraction from `pdfs for testing/ell_curves.pdf`, HTML generation, and a weak `WKWebView` smoke test. The problem is that the current smoke test does not require MathJax to become ready or produce rendered DOM, so the app can regress to raw fallback while the test suite still passes.

This task does not change PDF annotation compatibility, note storage format, or per-document metadata. It only repairs the MathJax execution path and the validation around it.

## Plan of Work

First, strengthen `MathPDFTests/MathPDFTests.swift` so the WebKit-based renderer test waits for a concrete success signal from the page, such as MathJax readiness, presence of `mjx-container` elements, or the `rendered` state. Preserve a separate fallback-oriented test for malformed input so graceful degradation remains intentional rather than accidental.

Next, repair the bootstrap in `MathPDF/MathNoteRendering.swift`. The likely failure area is how the HTML page loads or references the bundled `tex-svg.js` file or how the startup hook decides MathJax is ready. Keep the page-local fallback behavior, height reporting, and SwiftUI bridge intact while making the happy path deterministic.

If the fix requires a helper for relative resource paths or a different WebKit load method, keep that helper local to the rendering layer and document why it is needed. Do not widen the scope into editing, metadata, or sidebar work.

After the code change, re-run focused unit tests, a full app build, and fixture-based launch validation. If terminal-only validation still cannot visually inspect the rendered glyphs, capture the strongest observable DOM or state evidence possible in the tests and record that limitation.

## Concrete Steps

From the repository root `/Users/linzihong/Documents/Development/Xcode/MathPDF`, use these commands as the working loop:

1. Run the focused tests before the fix to confirm the current baseline:

       xcodebuild -project MathPDF.xcodeproj -scheme MathPDF -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO -only-testing:MathPDFTests test

2. After tightening the renderer test, rerun the same focused test command and expect the new renderer assertion to fail before the production fix and pass after it.

3. After fixing `MathPDF/MathNoteRendering.swift`, build the full app:

       xcodebuild -project MathPDF.xcodeproj -scheme MathPDF -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build

4. Launch the app against the canonical fixture:

       MATHPDF_OPEN_DOCUMENT="$PWD/pdfs for testing/ell_curves.pdf" scripts/build-and-launch.sh

Observed outcomes so far in this session:

    Focused test baseline succeeded before any new assertion was added:
    xcodebuild -project MathPDF.xcodeproj -scheme MathPDF -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO -only-testing:MathPDFTests test

    Bundled MathJax asset exists in the built app:
    .build/DerivedData/Build/Products/Debug/MathPDF.app/Contents/Resources/tex-svg.js

## Validation and Acceptance

Treat this as an existing-project change. Use scheme `MathPDF`. Use no simulator because the checked-in app target is macOS.

Acceptance is behavioral:

1. `pdfs for testing/ell_curves.pdf` opens successfully through the existing launch helper.
2. The single extracted user note still appears in the sidebar and can be selected.
3. For valid math note text, the renderer test proves MathJax reaches a rendered state or produces MathJax DOM rather than remaining indefinitely in raw fallback.
4. For malformed math note text, the renderer still surfaces readable raw text instead of a blank or noisy error state.

The smallest automated proof should be a focused `MathPDFTests` run that fails before the implementation fix and passes after it. Broader validation should then include a full `xcodebuild ... build` and a fixture-based macOS app launch.

## Idempotence and Recovery

The test and renderer edits are safe to rerun because they do not migrate stored data or mutate PDFs. Re-running the `xcodebuild` commands is safe when `.build/DerivedData` stays local to the repository. If a WebKit change makes the renderer worse, the safe recovery path is to revert only the rendering-layer edits and keep the stronger tests so the regression remains visible.

## Artifacts and Notes

Important evidence to preserve in this plan:

- the exact test name that proves the rendered path instead of fallback-only DOM loading
- the exact renderer resource-loading strategy used after the fix
- the exact focused test, full build, and launch commands run on macOS with no simulator

## Interfaces and Dependencies

Keep using the existing Apple frameworks already in the macOS target: SwiftUI, WebKit, PDFKit, and Foundation. Continue using the bundled `MathPDF/MathJax/tex-svg.js` asset already checked into the repository.

At the end of this work, the repository should still expose:

- `MathNoteRenderer.htmlDocument(...)` as the pure-Swift HTML generator
- `MathNoteWebView` in `MathPDF/MathNoteRendering.swift` as the `WKWebView` bridge
- focused tests in `MathPDFTests/MathPDFTests.swift` that distinguish successful MathJax rendering from raw fallback

Revision note: created to repair the initial MathJax integration after the app was observed falling back to raw note text instead of rendering valid LaTeX.
