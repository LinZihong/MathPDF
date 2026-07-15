# KaTeX Renderer Probe

> **Historical and non-operational.** This completed investigation preserves
> evidence only. Use `AGENTS.md`, `docs/CURRENT.md`, and `docs/TESTING.md` for
> current commands and claims.

This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to date as work proceeds.

This document must be maintained in accordance with [PLANS.md](../../PLANS.md).

## Purpose / Big Picture

After this change, MathPDF should render supported LaTeX-style note content through a `WKWebView` backed by KaTeX so we can answer a narrower technical question with evidence: whether the broken behavior was specific to the bundled MathJax path or whether `WKWebView` math rendering is failing more generally in this app.

This is an existing-project renderer probe, not a product expansion. PDF note storage remains plain text inside the PDF. The reader shell, note discovery, and fallback requirements remain unchanged. KaTeX is acceptable here as a diagnostic renderer path even if the project later returns to MathJax or another TeX engine.

## Progress

- [x] (2026-04-05 23:16Z) Confirmed the current repository state has reverted to the earlier Swift parser renderer in `MathPDF/MathNoteRendering.swift`; the MathJax-backed `WKWebView` path is not currently on the active code path.
- [x] (2026-04-05 23:16Z) Confirmed there is no existing local KaTeX bundle checked into the repository.
- [x] (2026-04-06 06:16Z) Added a bundled KaTeX runtime and stylesheet under `MathPDF/KaTeX/`, including local fonts and auto-render support, in a layout that the app bundle copies correctly.
- [x] (2026-04-06 06:18Z) Replaced the active parser renderer with a `WKWebView` KaTeX renderer while preserving readable raw-text fallback when rendering fails.
- [x] (2026-04-06 06:24Z) Updated focused tests to cover the KaTeX HTML contract, offscreen `WKWebView` rendering, malformed-input fallback, and direct launch-document argument parsing.
- [x] (2026-04-06 07:24Z) Ran focused tests, a full scheme build, and fixture-based launch validation using the macOS `MathPDF` scheme with no simulator.

## Surprises & Discoveries

- Observation: the current code path no longer exercises any `WKWebView` integration at all.
  Evidence: `MathPDF/MathNoteRendering.swift` now contains only the earlier parser-based `MathTextRun` / `NoteRenderBlock` logic and a pure SwiftUI `MathNoteView`.

- Observation: KaTeX is not already available in the repository.
  Evidence: `find . -maxdepth 4 \( -iname '*katex*' -o -path '*/katex/*' \) -print` returned no matches from the repository root.

- Observation: the blank or missing-document manual checks were confounded by launch mechanics rather than by missing renderer assets.
  Evidence: the app bundle contained `katex.min.js`, `auto-render.min.js`, `katex.min.css`, and the KaTeX fonts under `.build/DerivedData/Build/Products/Debug/MathPDF.app/Contents/Resources`, while earlier captures also showed multiple concurrent `MathPDF` instances from different build locations and a direct-executable launch path that did not reliably surface the document window as a normal app launch.

- Observation: `WKWebView` math rendering works in the checked-in app once the launch path is controlled and the KaTeX runtime is bundled.
  Evidence: the focused `MathPDFTests/webViewRendersFixtureNoteWithKaTeX()` test passed, and a captured live launch against `pdfs for testing/ell_curves.pdf` showed both inline and display math rendered in the note inspector.

- Observation: an unresolved Xcode-Run-only discrepancy remains even though the Xcode-built app bundle contains the same KaTeX assets and renderer strings as the CLI-built bundle.
  Evidence: the Xcode-built app under `~/Library/Developer/Xcode/DerivedData/.../MathPDF.app` contained `katex.min.js`, `auto-render.min.js`, the KaTeX fonts, and renderer strings such as `renderMathInElement`, but still behaved differently under Xcode Run. The process environment also showed debugger-injected values including `DYLD_INSERT_LIBRARIES`, `DYLD_FRAMEWORK_PATH`, `DYLD_LIBRARY_PATH`, and `-NSDocumentRevisionsDebugMode YES`.

## Decision Log

- Decision: pursue KaTeX as a focused `WKWebView` probe before revisiting MathJax.
  Rationale: KaTeX has a much simpler asset/runtime model than MathJax and should let us determine quickly whether the remaining problem is the webview bridge itself or the MathJax packaging/bootstrap path.
  Date/Author: 2026-04-05 / Codex

## Outcomes & Retrospective

Completed with one follow-up caveat. The active renderer is now a KaTeX-backed `WKWebView`, and the probe answered the original technical question: `WKWebView` rendering is not fundamentally broken in MathPDF. The earlier failure was specific to the prior MathJax integration and to a confusing manual-launch workflow that made app-state validation unreliable. A separate Xcode-Run-only launch/runtime discrepancy remains documented in `docs/xcode_run_weirdness.md`.

## Context and Orientation

The current reader shell lives in `MathPDF/ContentView.swift`. It already routes the selected note into `MathNoteView`. The current `MathNoteRendering.swift` implementation is the older parser-based path that presents a lightweight text-only approximation of math. That means the repository has temporarily lost the ability to prove whether a browser-based renderer can work in the app at all.

The renderer probe should stay inside the note-rendering boundary. It should not widen into editing flows, metadata persistence, or sidebar restructuring. The only question in scope is whether a bundled KaTeX surface in `WKWebView` can render the note from `pdfs for testing/ell_curves.pdf` while still degrading gracefully for malformed input.

## Plan of Work

First, add a local KaTeX resource bundle under `MathPDF/` that is small enough to integrate cleanly with the current Xcode project. Prefer the standard browser build assets that support the auto-render extension and local font/CSS references.

Next, replace the parser-backed `MathNoteView` with a `WKWebView` wrapper that loads a generated HTML document, points KaTeX at the bundled resources, renders the note text using common math delimiters, and falls back to readable raw text if rendering fails.

Then, update the focused tests to keep the PDF fixture extraction coverage while also validating the generated HTML contract and fallback decisions in pure Swift. Avoid UI tests in this slice unless the runner environment becomes reliable enough to use.

Finally, run the narrowest useful validation loop first, then the broader build and launch checks documented in `AGENTS.md`.

## Concrete Steps

From the repository root `/Users/linzihong/Documents/Development/Xcode/MathPDF`, use this loop:

1. Add KaTeX assets under `MathPDF/KaTeX/`.
2. Implement the `WKWebView` renderer in `MathPDF/MathNoteRendering.swift`.
3. Update `MathPDFTests/MathPDFTests.swift` for the new renderer contract.
4. Run focused unit tests:

       xcodebuild -project MathPDF.xcodeproj -scheme MathPDF -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO -only-testing:MathPDFTests test

5. Build the app:

       xcodebuild -project MathPDF.xcodeproj -scheme MathPDF -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build

6. Launch against the canonical fixture:

       MATHPDF_OPEN_DOCUMENT="$PWD/pdfs for testing/ell_curves.pdf" scripts/build-and-launch.sh

## Validation and Acceptance

Treat this as an existing-project change. Use scheme `MathPDF`. Use no simulator because the checked-in app target is macOS.

Acceptance is:

1. The app builds successfully with a bundled KaTeX resource set.
2. The focused unit tests pass and still prove note extraction from `ell_curves.pdf`.
3. The active note inspector path uses `WKWebView` rather than the old hand-spun parser.
4. Valid math note text on the canonical fixture renders through the web renderer path rather than falling back to raw text immediately.
5. Malformed math remains readable rather than crashing or showing a noisy JavaScript error surface.

## Idempotence and Recovery

These edits are additive and local to renderer resources, renderer code, tests, and plan files. Re-running the build and test commands is safe with `.build/DerivedData` kept inside the repository. If the KaTeX experiment fails, the safe recovery path is to keep any stronger tests and back out only the renderer-specific edits.

## Artifacts and Notes

Preserve:

- the exact KaTeX resource layout used under `MathPDF/`
- the renderer bootstrap strategy used in `MathNoteRendering.swift`
- the direct launch-document parsing in `ReaderDocumentController.swift`
- the `scripts/build-and-launch.sh [path-to-pdf]` workflow that now launches the bundle with `open -n -a ... --args`
- the exact focused test, full build, and launch commands actually run

## Interfaces and Dependencies

Keep using the existing Apple frameworks already in the macOS target: SwiftUI, WebKit, PDFKit, and Foundation. Keep note storage and extraction unchanged.

At the end of this work, the repository should expose:

- a `WKWebView`-backed `MathNoteView`
- focused tests in `MathPDFTests/MathPDFTests.swift` that still cover the fixture and the renderer contract
- a checked-in ExecPlan and index entry describing the KaTeX probe

Revision note: created to probe whether `WKWebView` note rendering succeeds with KaTeX after the prior bundled MathJax path failed to produce rendered DOM.
