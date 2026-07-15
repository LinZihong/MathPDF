# MVP PDF Reader And Math Note Rendering

> **Historical and non-operational.** This completed MVP plan preserves evidence
> only. Use the current product, state, and testing documents for instructions.

This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to date as work proceeds.

This document must be maintained in accordance with [PLANS.md](../../PLANS.md).

## Purpose / Big Picture

After this change, MathPDF should stop being a template app and become a usable first MVP for the current product slice. A user should be able to open a PDF from disk, read it inside a native macOS window, and inspect existing annotation comments with math rendered more readably than the raw TeX delimiters stored in the PDF. The concrete proof target for this MVP is `pdfs for testing/ell_curves.pdf`, which already contains a highlight note whose contents include inline `$...$` math and a display `\[ ... \]` equation.

This plan intentionally limits scope to the user-requested MVP. It does not implement annotation creation, note editing, table of contents, per-document preamble metadata, or a full TeX engine. PDF annotation compatibility remains unchanged because note contents stay plain text inside the source PDF, and per-document preamble metadata is unchanged because this MVP does not write metadata yet.

## Progress

- [x] (2026-04-05 20:43Z) Read `docs/initial_description.txt`, `AGENTS.md`, `PLANS.md`, and inspected the current template-style project structure.
- [x] (2026-04-05 20:44Z) Confirmed `pdfs for testing/ell_curves.pdf` exists in the repo and extracted the existing math-bearing note content with a PDFKit inspection script.
- [x] (2026-04-05 20:50Z) Replaced the template app with a reader shell that can open a PDF, host `PDFView`, list extracted notes, and render selected note contents in a dedicated inspector.
- [x] (2026-04-05 20:50Z) Added domain logic for annotation-note extraction and a forgiving math renderer for `$...$`, `\(...\)`, `\[...\]`, superscripts, subscripts, and basic TeX command cleanup.
- [x] (2026-04-05 20:50Z) Added focused unit tests for note extraction and math rendering behavior in `MathPDFTests/MathPDFTests.swift`.
- [x] (2026-04-05 20:50Z) Updated repo testing guidance in `AGENTS.md` and launch automation in `scripts/build-and-launch.sh` to use the `ell_curves.pdf` MVP fixture.
- [x] (2026-04-05 20:52Z) Ran a successful app build with `xcodebuild -project MathPDF.xcodeproj -scheme MathPDF -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build`.
- [x] (2026-04-05 21:26Z) Ran the narrowest successful automated test loop with `xcodebuild ... -only-testing:MathPDFTests build-for-testing` followed by `xcodebuild ... -only-testing:MathPDFTests test-without-building`.
- [x] (2026-04-05 21:10Z) Added explicit UI-test app termination and updated `AGENTS.md` with repo-level rules to prevent future placeholder or leaking UI tests.

## Surprises & Discoveries

- Observation: `ell_curves.pdf` currently contains one real note duplicated as a `Highlight` annotation and a `Popup` annotation with the same contents.
  Evidence: A local PDFKit inspection printed both annotation types for page 1 with identical math-bearing contents.

- Observation: sandbox-safe `xcodebuild` must use an in-repo derived-data path, and the checked-in project also needs signing disabled for local validation in this environment.
  Evidence: `xcodebuild -project MathPDF.xcodeproj -scheme MathPDF -derivedDataPath .build/DerivedData build` progressed to compilation setup, then failed on missing `Mac Development` signing credentials.

- Observation: the `@Observable` macro path is not reliable in this sandbox because Swift plugin-server macro expansion fails during `xcodebuild`.
  Evidence: the first build attempt with `@Observable` failed with `ObservationMacros.ObservableMacro could not be found`; switching to `ObservableObject` and `@Published` removed the failure and allowed the build to complete.

- Observation: even `-only-testing:MathPDFTests` still tries to use the macOS XCTest manager service, which this sandbox blocks.
  Evidence: `xcodebuild ... -only-testing:MathPDFTests test` failed with `Failed to establish communication with the test runner` and `testmanagerd.control ... Sandbox restriction`.

- Observation: template-style UI tests are a bad fit for this repo once real workflow automation starts because they can launch the app without owning termination or asserting useful behavior.
  Evidence: the checked-in placeholder tests launched the app and captured a screenshot, but did not terminate the app or validate the MVP workflow.

- Observation: a direct focused `xcodebuild ... -only-testing:MathPDFTests test` can race ahead of bundle packaging in this project, while `build-for-testing` followed by `test-without-building` runs cleanly and deterministically.
  Evidence: the direct `test` invocation failed with `Failed to create a bundle instance representing ... MathPDFTests.xctest`, but the sequential `build-for-testing` and `test-without-building` pair completed successfully.

## Decision Log

- Decision: Treat this task as an existing-project change and keep the MVP scoped to opening PDFs and rendering existing annotation comments.
  Rationale: That matches the user request and the repository instructions to avoid inferring extra scope beyond the source-of-truth product description.
  Date/Author: 2026-04-05 / Codex

- Decision: Implement a forgiving built-in TeX-subset renderer instead of introducing a new external math rendering dependency.
  Rationale: The repository is still template-sized, network access is restricted, and the real fixture only requires inline `$...$`, display `\[ ... \]`, superscripts, subscripts, and graceful raw-text fallback.
  Date/Author: 2026-04-05 / Codex

- Decision: Encode test-lifecycle guardrails in `AGENTS.md` instead of creating a repository skill.
  Rationale: the failure mode was a standing repo workflow issue, not a reusable multi-repo capability. Contributors need these rules every time they touch tests, so `AGENTS.md` is the right home.
  Date/Author: 2026-04-05 / Codex

## Outcomes & Retrospective

The requested first MVP is now implemented as an existing-project change. MathPDF can open a PDF from disk, display it in `PDFView`, extract non-popup notes, and show the selected note in an inspector that renders common TeX-like math more readably while still exposing the original stored plain text. The repo’s testing protocol now points future validation at `pdfs for testing/ell_curves.pdf`, which is the real fixture that motivated this slice.

This MVP can now reasonably be treated as done for the first reader-and-rendering slice because the app build succeeds and the focused `MathPDFTests` suite passes against the real fixture on macOS. The main gap is broader automated coverage of the full reader workflow. The repo now has better test hygiene than the template it started from: UI tests terminate what they launch, and `AGENTS.md` now requires deterministic launch setup and explicit app cleanup. That should prevent future “bad tests” that leak launched app instances or keep meaningless placeholder coverage around.

## Context and Orientation

The current project is the default SwiftUI macOS app template. The only checked-in application files are `MathPDF/MathPDFApp.swift` and `MathPDF/ContentView.swift`, and the existing test files are templates in `MathPDFTests/MathPDFTests.swift` and `MathPDFUITests/`. The Xcode project uses file-system-synchronized groups, so new files placed under `MathPDF/` and the test directories should join the corresponding targets without hand-editing `project.pbxproj`.

For this MVP, the key repository fixture is `pdfs for testing/ell_curves.pdf`. A “note” in this plan means a PDF annotation whose `contents` string is non-empty and user-authored. A “popup” annotation is a PDFKit companion annotation used by some PDFs to present note UI; it duplicates user-authored note content and should not be listed separately. A “forgiving renderer” means code that attempts to improve readability for common math syntax but falls back to showing readable raw text when it cannot confidently interpret the input.

## Plan of Work

Replace the template `MathPDF/ContentView.swift` with a root reader interface backed by a new observable document model. That model should live in `MathPDF/` alongside small domain types for loaded documents, extracted notes, and the selected note. It should be responsible for opening a PDF from a user-selected file path or a launch argument, creating a `PDFDocument`, extracting non-popup notes, and tracking the currently selected note. The initial open affordance should be a clear macOS button in the empty state and toolbar.

Add a PDFKit bridge under `MathPDF/` using `NSViewRepresentable` so SwiftUI can host `PDFView`. The bridge should update its displayed `PDFDocument` as the view model changes and navigate to the selected note’s page and bounds when the user picks a note from the sidebar.

Add a small rendering layer under `MathPDF/` that splits note content into plain-text paragraphs, inline math fragments, and display math blocks. The first MVP renderer only needs to support the syntax present in `ell_curves.pdf` plus close relatives: `$...$`, `\(...\)`, `\[...\]`, superscripts, subscripts, a few Greek commands, and forgiving command stripping for unsupported TeX-like tokens. Unsupported or malformed expressions must remain readable, not replaced with errors.

Update `MathPDFTests/MathPDFTests.swift` so the test target exercises real note extraction from `ell_curves.pdf` and renderer behavior on both supported and malformed math snippets. Keep UI tests lightweight unless the environment can reliably automate the new open-document flow.

Update `AGENTS.md` so future contributors validate the first MVP against `pdfs for testing/ell_curves.pdf`, including proof that the PDF opens and that the math-bearing note becomes more readable without changing the underlying PDF data format.

## Concrete Steps

From the repository root `/Users/linzihong/Documents/Development/Xcode/MathPDF`, implement and validate the MVP with these commands:

1. Inspect the real fixture note contents with a sandbox-safe Swift command:

       mkdir -p .swift-module-cache
       CLANG_MODULE_CACHE_PATH=$PWD/.swift-module-cache swift -e 'import PDFKit; import Foundation; let url = URL(fileURLWithPath: "pdfs for testing/ell_curves.pdf"); let doc = PDFDocument(url: url)!; for i in 0..<doc.pageCount { let page = doc.page(at: i)!; for annotation in page.annotations where !(annotation.contents ?? "").isEmpty { print("page=\(i + 1) type=\(annotation.type ?? "unknown") contents=\(annotation.contents!)") } }'

   Expect output that includes a page-1 highlight note with `$a$`, `$b$`, `$c$`, and `\[ a^n + b^n = c^n \]`.

2. Build the app with signing disabled and local derived data:

       xcodebuild -project MathPDF.xcodeproj -scheme MathPDF -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build

3. Build the focused unit-test bundle:

       xcodebuild -project MathPDF.xcodeproj -scheme MathPDF -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO -only-testing:MathPDFTests build-for-testing

4. Execute the focused unit tests without rebuilding:

       xcodebuild -project MathPDF.xcodeproj -scheme MathPDF -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO -only-testing:MathPDFTests test-without-building

5. Launch the built app against the fixture when manual validation is needed:

       MATHPDF_OPEN_DOCUMENT="$PWD/pdfs for testing/ell_curves.pdf" scripts/build-and-launch.sh

Current session status:

    Successful build:
    xcodebuild -project MathPDF.xcodeproj -scheme MathPDF -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build

    Successful focused test build:
    xcodebuild -project MathPDF.xcodeproj -scheme MathPDF -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO -only-testing:MathPDFTests build-for-testing

    Successful focused test execution:
    xcodebuild -project MathPDF.xcodeproj -scheme MathPDF -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO -only-testing:MathPDFTests test-without-building

## Validation and Acceptance

Treat this as an existing-project change, not greenfield work. Use scheme `MathPDF`. Use no simulator because the checked-in target is macOS.

Acceptance for the MVP is behavioral:

1. After launching the app, the user can open `pdfs for testing/ell_curves.pdf` either from the in-app open control or via `MATHPDF_OPEN_DOCUMENT` launch automation.
2. The document displays inside the main reader area with a native `PDFView` and remains scrollable/zoomable.
3. The app extracts the real existing note from the PDF without listing the duplicate popup annotation as a second user note.
4. Selecting the note reveals it in context and shows a rendered reading view where the stored raw TeX delimiters are replaced by a more readable presentation.
5. If the renderer is given malformed math input, the UI still shows readable text rather than an error state.

Automated validation should at minimum prove note extraction from `ell_curves.pdf`, math block parsing, superscript handling, and graceful fallback on malformed input.

In this session, the build acceptance proof succeeded, fixture inspection succeeded, and the focused unit-test loop passed on macOS with the sequential `build-for-testing` plus `test-without-building` workflow.

## Idempotence and Recovery

All repository edits in this plan are additive or direct replacements of template code and are safe to repeat. The build and test commands are idempotent when run from the repository root with `.build/DerivedData` as the derived-data path. If a build fails because Xcode recreated signing settings or stale derived data, rerun the same command after removing `.build/DerivedData`.

## Artifacts and Notes

Current fixture evidence:

    pages=2
    page=1 type=Highlight contents=This is a test comment with some math: ... $a$, $b$, and $c$ ... \[ a^n + b^n = c^n \] ...
    page=1 type=Popup contents=This is a test comment with some math: ... $a$, $b$, and $c$ ... \[ a^n + b^n = c^n \] ...

## Interfaces and Dependencies

Use only Apple frameworks already available to the macOS target: SwiftUI, PDFKit, and AppKit where the file open panel or native representable bridge needs it. At the end of this plan, the codebase should contain:

- A document-facing observable type in `MathPDF/` that owns the active `PDFDocument`, the opened file URL, the extracted notes, and the selected note.
- A note extraction function that accepts `PDFDocument` and returns a list of note models without popup duplicates.
- A math parsing and formatting layer that produces a testable intermediate representation before SwiftUI converts it into styled `Text`.
- A SwiftUI note-rendering view that consumes that intermediate representation and presents both inline and display math readably.

Revision note: updated after implementation to record the completed MVP, the successful build command, the `@Observable` to `ObservableObject` adjustment forced by sandboxed macro expansion, and the later repo-workflow change that made UI-test termination and placeholder-test cleanup explicit policy.
