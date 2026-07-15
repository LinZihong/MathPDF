# Robust MathJax Note Renderer

> **Historical and non-operational.** This completed MathJax plan preserves
> evidence only. Its commands and renderer assumptions are superseded.

This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to date as work proceeds.

This document must be maintained in accordance with [PLANS.md](../../PLANS.md).

## Purpose / Big Picture

After this change, MathPDF should keep the MVP reader workflow but replace the hand-rolled Swift math presentation path with a real TeX-capable renderer based on MathJax. A user should be able to open `pdfs for testing/ell_curves.pdf`, select its note, and see the note rendered through a more robust math engine without also showing a second raw-text panel in the inspector. The visible proof is that the existing note still renders cleanly, malformed input still degrades to readable text, and the rest of the PDF-reading workflow continues to work.

This plan intentionally keeps the current MVP shell intact. PDF annotation compatibility remains unchanged because the underlying annotation contents are still plain text stored in the PDF. Per-document preamble metadata also remains unchanged in this slice; the new renderer should be structured so a later slice can pass document-scoped macros into MathJax, but this plan does not yet add metadata persistence or a preamble editor.

## Progress

- [x] (2026-04-05 21:31Z) Reviewed the current MVP renderer, the completed MVP ExecPlan, and the current repo state after commit `3d0720b`.
- [x] (2026-04-05 21:32Z) Verified the current official `mathjax` package version as `4.1.1`.
- [x] (2026-04-05 21:40Z) Replaced the Swift parser-based renderer with a bundled local MathJax-backed `WKWebView` surface and a pure-Swift HTML/JavaScript helper.
- [x] (2026-04-05 21:40Z) Removed the duplicate raw-text note display from the inspector while keeping note metadata and selection flow.
- [x] (2026-04-05 21:42Z) Replaced parser-specific unit tests with focused renderer-payload tests and updated the UI test expectation to match the simplified inspector.
- [x] (2026-04-05 21:42Z) Ran the build, focused test-build, focused test-execution, and launch-helper validation loop for the new renderer slice.

## Surprises & Discoveries

- Observation: Xcode’s file-system-synchronized group handling flattens resource copies into the app bundle, so bundling the full MathJax package causes filename collisions such as `require.mjs`.
  Evidence: the first renderer build failed with `Multiple commands produce ... Resources/require.mjs` because both `MathJax/require.mjs` and `MathJax/sre/require.mjs` mapped to the same flattened destination.

- Observation: a single bundled `tex-svg.js` entrypoint is sufficient for the current fixture and keeps the app bundle integration simple.
  Evidence: after reducing the bundled assets to `tex-svg.js` plus the license file, the app build succeeded and the focused unit tests passed.

## Decision Log

- Decision: Use a bundled local MathJax runtime rather than a CDN-hosted script.
  Rationale: The app is a native PDF reader, and tying note rendering to live network access would be brittle and out of step with the product’s “just works” intent. Bundling MathJax also makes future per-document macros more predictable.
  Date/Author: 2026-04-05 / Codex

- Decision: Prefer a `WKWebView`-hosted MathJax renderer over continuing to expand the custom Swift parser.
  Rationale: The MVP parser is sufficient for the first fixture, but it is the wrong long-term surface for TeX compatibility. A web view contains MathJax cleanly behind a rendering boundary while leaving the PDF and note indexing logic untouched.
  Date/Author: 2026-04-05 / Codex

- Decision: Remove the raw plain-text panel from the inspector in this slice.
  Rationale: The user explicitly requested it, and the product source of truth requires plain-text storage and editability in the PDF, not a duplicate always-visible raw-text reading panel in the MVP inspector.
  Date/Author: 2026-04-05 / Codex

- Decision: Bundle only the `tex-svg.js` MathJax entrypoint plus the license file in this slice rather than the full published package tree.
  Rationale: the Xcode synced-group resource path flattens copied files and collides on duplicate basenames from the full package. The single combined entrypoint still provides a real MathJax renderer and keeps this slice shippable without hand-restructuring the Xcode project.
  Date/Author: 2026-04-05 / Codex

## Outcomes & Retrospective

The renderer replacement is complete for this slice. MathPDF now keeps the MVP reader shell but renders note contents through a `WKWebView` backed by bundled MathJax `tex-svg.js` rather than the earlier hand-built Swift parser. The inspector now shows note metadata and the rendered reading surface only, which matches the requested simplification.

The main remaining gap is broader TeX coverage beyond what the single combined entrypoint provides by itself. If later work needs `\require`-driven component loading, the project will likely need a more explicit resource-bundling strategy than the current synced-group flattening behavior allows.

## Context and Orientation

The current reader shell lives in `MathPDF/ContentView.swift`, and it shows a split layout with the PDF on the left and a note inspector on the right. The current note rendering implementation lives entirely in `MathPDF/MathNoteRendering.swift`. That file contains a custom parser that splits note text into paragraphs, inline math fragments, and display math blocks, then renders those fragments as SwiftUI `Text`. The current tests in `MathPDFTests/MathPDFTests.swift` directly exercise that parser representation.

A “robust renderer” in this plan means MathJax, the established JavaScript math typesetting engine, running inside a `WKWebView`. A “bundled local runtime” means the MathJax JavaScript files are checked into the repository and copied into the app bundle so the renderer can load from app-local files instead of a remote CDN.

The repository is still an existing-project macOS app using the `MathPDF` scheme. The working MVP behavior from the previous plan must remain intact: open PDFs, extract non-popup notes, reveal selected notes in context, and render note contents more readably. The only intentional UI subtraction in this slice is removing the extra raw-text section from the inspector.

## Plan of Work

Create a new rendering layer in `MathPDF/` that wraps a `WKWebView` configured for note rendering. That layer should accept the raw note text and produce a complete HTML document that loads bundled MathJax assets from the app bundle, applies minimal native-looking CSS, and injects the note text into the page in a form MathJax can typeset. The wrapper should disable unnecessary web-view affordances, keep the background transparent or aligned with the native panel styling, and expose a predictable accessibility identifier for UI tests.

Replace the existing `MathNoteView` implementation so it no longer depends on the parser-based `MathTextRun` model. The code should still fail gracefully when MathJax cannot typeset something: the rendered page should show readable raw note text rather than a noisy JavaScript failure surface. Because this slice is about the renderer backend rather than note editing, keep the note text flow read-only in the inspector.

Bundle MathJax under a repository path inside `MathPDF/` so Xcode’s file-system-synchronized group picks it up as app resources. Use a local script URL rooted in the app bundle rather than a network URL. Keep the integration path simple: a static HTML shell plus a small JavaScript bridge is sufficient.

Update `MathPDF/ContentView.swift` so the note inspector presents only the rendered view and note metadata. Keep the PDF selection and sidebar behavior unchanged.

Replace the parser-specific unit tests in `MathPDFTests/MathPDFTests.swift` with tests that validate the contracts that remain important after this refactor: note extraction still excludes popup duplicates, the HTML/template generation preserves the original note text and MathJax delimiters, and malformed input still produces readable content in the generated HTML. If a small pure-Swift HTML-template helper exists, test that helper instead of trying to run WebKit inside the unit test target.

Update `docs/initial_description.txt` only if the finished behavior introduces a new durable product statement that is not already captured there. Because the product description already says notes remain plain text in the PDF and math is rendered for reading comfort, no broader product rewrite is expected unless implementation reveals a necessary clarification.

## Concrete Steps

From the repository root `/Users/linzihong/Documents/Development/Xcode/MathPDF`, carry out the work with these concrete commands and checks:

1. Fetch the official MathJax package contents for inspection:

       npm pack mathjax@4.1.1

2. Expand the package into a temporary local directory and copy the bundled entrypoint plus license into `MathPDF/MathJax/`:

       tar -xzf /tmp/mathpdf-mathjax/mathjax-4.1.1.tgz -C /tmp/mathpdf-mathjax/package
       rm -rf MathPDF/MathJax
       mkdir -p MathPDF/MathJax
       cp /tmp/mathpdf-mathjax/package/package/tex-svg.js MathPDF/MathJax/tex-svg.js
       cp /tmp/mathpdf-mathjax/package/package/LICENSE MathPDF/MathJax/LICENSE-MathJax.txt

3. Build the app:

       xcodebuild -project MathPDF.xcodeproj -scheme MathPDF -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build

4. Build the focused unit-test bundle:

       xcodebuild -project MathPDF.xcodeproj -scheme MathPDF -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO -only-testing:MathPDFTests build-for-testing

5. Execute the focused unit tests:

       xcodebuild -project MathPDF.xcodeproj -scheme MathPDF -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO -only-testing:MathPDFTests test-without-building

6. Launch against the fixture for manual validation:

       MATHPDF_OPEN_DOCUMENT="$PWD/pdfs for testing/ell_curves.pdf" scripts/build-and-launch.sh

Observed outcomes in this session:

    Build succeeded:
    xcodebuild -project MathPDF.xcodeproj -scheme MathPDF -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build

    Focused test build succeeded:
    xcodebuild -project MathPDF.xcodeproj -scheme MathPDF -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO -only-testing:MathPDFTests build-for-testing

    Focused test execution succeeded:
    xcodebuild -project MathPDF.xcodeproj -scheme MathPDF -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO -only-testing:MathPDFTests test-without-building

    Launch helper succeeded:
    MATHPDF_OPEN_DOCUMENT="$PWD/pdfs for testing/ell_curves.pdf" scripts/build-and-launch.sh

## Validation and Acceptance

Treat this as an existing-project change. Use scheme `MathPDF`. Use no simulator because the current checked-in app target is macOS.

Acceptance is behavioral:

1. `pdfs for testing/ell_curves.pdf` still opens in the app and remains readable in the main `PDFView`.
2. The note list still shows one user note rather than a duplicate popup companion.
3. Selecting the note still reveals it in context.
4. The inspector shows a single rendered note surface, not a second raw-text reading panel.
5. The rendered note uses the bundled robust renderer path rather than the old custom Swift parser.
6. Broken or unsupported math-like input still appears as readable text rather than an error-heavy blank state.

Automated validation should prove at minimum that note extraction still works and that the HTML or JavaScript payload sent to the renderer preserves readable fallback behavior.

In this session, the build, focused unit-test build, focused unit-test execution, and launch helper all succeeded on macOS. Manual visual inspection of the launched window was not available through the terminal session, so the launch check proves startup and fixture targeting but not pixel-level UI confirmation.

## Idempotence and Recovery

The file edits in this plan should be additive or targeted replacements. Re-running the build and focused test commands is safe when `.build/DerivedData` is kept local to the repository. If bundling MathJax produces stale extracted files, remove the temporary extraction directory and re-copy the intended resource folder into `MathPDF/`. If the app bundle fails to find a local script, verify the resource path first rather than falling back to a remote CDN.

## Artifacts and Notes

Important artifacts captured during implementation:

- the exact bundled MathJax path under `MathPDF/MathJax/tex-svg.js`
- the exact build and focused test commands run
- the exact fixture-based launch path used for `ell_curves.pdf`

## Interfaces and Dependencies

Use Apple frameworks already available to the macOS target: SwiftUI, PDFKit, AppKit where needed, and WebKit for the new rendering surface. Use the official `mathjax` package version `4.1.1` as the bundled third-party dependency source.

At the end of this slice, the codebase should contain:

- A small pure-Swift helper that turns raw note text into the HTML payload consumed by the web renderer.
- A `WKWebView` bridge in `MathPDF/` that loads the bundled MathJax script and refreshes when the selected note changes.
- A simplified note inspector in `MathPDF/ContentView.swift` that presents rendered output without the duplicate raw-text panel.
- Focused tests that validate the new renderer inputs without depending on the removed parser intermediate representation.

Revision note: created to replace the MVP’s hand-rolled renderer with a bundled MathJax-based rendering surface while preserving the rest of the reader workflow.
