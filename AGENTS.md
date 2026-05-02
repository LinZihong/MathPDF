# MathPDF Agent Guide

This repository is a macOS SwiftUI app (`MathPDF`) with unit tests in `MathPDFTests` and UI tests in `MathPDFUITests`.

Start from [docs/initial_description.txt](/Users/linzihong/Documents/Development/Xcode/MathPDF/docs/initial_description.txt). That file is the current product source of truth. Do not infer extra features, extra platforms, or storage formats beyond what it says. If a task would materially expand scope, stop and make the assumption explicit.

Treat this repo as an existing-project change, not a greenfield scaffold. Reuse the current Xcode project, scheme, targets, and any existing models or utilities unless a task explicitly requires restructuring.

## Product Brief

MathPDF is a native PDF reader for Apple platforms aimed at people who write math inside PDF annotations. The key behavior is:

- Annotation note contents remain plain text inside the PDF.
- When note text contains supported math notation, the app renders that math for reading comfort.
- Rendering is an enhanced view over interoperable PDF data, not a proprietary annotation format.

The intended reading workflow from the current description:

- Open a PDF and show a polished document view.
- Provide a sidebar with `Table of Contents` and `Notes`.
- Support highlights with attached notes and box-style note annotations.
- Opening a note from the document or sidebar should reveal it in context.
- Notes stay editable as plain text.

Math-specific constraints from the current description:

- Support common MathJax-style delimiters and broadly compatible math syntax.
- Favor forgiving rendering over strict parsing.
- On parse/render failure, show readable raw text rather than noisy errors.
- Live preview while typing is not required unless the product description changes.

Per-document macro constraints:

- Each PDF may define its own math preamble or macros.
- The preamble is scoped to the document, not to the user globally.
- The preamble should be editable from an inspector-style UI.
- The preamble should travel with the PDF through metadata so compatible viewers can read it.

Design constraints:

- The app should feel minimal, tasteful, native, and uncluttered.
- Math readability is the value add; avoid feature creep that turns the app into a general-purpose knowledge manager.

## Source Hierarchy

Use this order when instructions conflict:

1. Direct user instructions in the current conversation.
2. [docs/initial_description.txt](/Users/linzihong/Documents/Development/Xcode/MathPDF/docs/initial_description.txt)
3. This `AGENTS.md`
4. [docs/CURRENT.md](/Users/linzihong/Documents/Development/Xcode/MathPDF/docs/CURRENT.md)
5. `PLANS.md` and plan-specific docs created for a task
6. Existing code and tests

When a product decision is not settled in the description, record it as an explicit assumption in the relevant plan or ask the user if it affects architecture or compatibility.

## Repo Map

- `MathPDF/`: app code.
- `MathPDFTests/`: unit and logic tests using Swift Testing.
- `MathPDFUITests/`: UI and workflow tests with XCTest.
- `docs/`: product notes and supporting design material.
- `docs/CURRENT.md`: short handoff note for the active repository state.
- `docs/plans/`: compact Work Cards plus historical ExecPlans.
- `docs/plans/EXECPLAN_INDEX.md`: master index of checked-in Work Cards and historical plans.
- [PLANS.md](/Users/linzihong/Documents/Development/Xcode/MathPDF/PLANS.md): required format and maintenance rules for Work Cards. The repo migrated from long ExecPlans to compact Work Cards on 2026-05-02.

## Working Rules

- Stay CLI-first. Prefer `xcodebuild` for listing schemes, building, testing, and any build-for-testing style loop.
- A cleaner generator such as Tuist is optional, not the default.
- If XcodeBuildMCP is available in a future session, use it once scheme inspection, launch automation, screenshots, logs, or UI interaction become important enough that shell commands alone are no longer efficient.
- Keep UI code separate from PDF parsing, annotation extraction, math detection, math rendering, and metadata persistence.
- Prefer testable services and models over putting document logic directly in SwiftUI views.
- Preserve interoperability: do not introduce a custom note storage format when plain-text PDF annotations are sufficient.
- Treat graceful fallback as a feature. Broken math should degrade to readable text.
- Favor additive, reversible changes. For risky migrations, keep old and new paths side by side until behavior is validated.
- If a change touches document format, annotation semantics, or metadata persistence, add or update tests and document the compatibility impact.
- Reuse existing navigation patterns, shared utilities, and models when they already exist.
- Keep compatibility intact across supported Apple platforms. Right now the checked-in project is macOS-only, so do not accidentally hard-code assumptions that would make later Apple-platform expansion harder without explicit product direction.

## Architecture Direction

The codebase is still near the Xcode template, so new work should establish clean boundaries early.

- UI layer: document window, sidebar, inspector, annotation editing surfaces, and view state.
- Domain layer: annotation discovery, note indexing, math-fragment detection, preamble resolution, and fallback decisions.
- Integration layer: PDFKit or equivalent document integration, metadata read/write, export/save coordination.
- Rendering layer: math rendering from plain-text note content plus per-document preamble context.

Avoid collapsing these concerns into a single `ContentView` replacement.

## Implementation Priorities

- Build a real PDF reading workflow before polishing secondary preferences.
- Make note discovery and contextual navigation reliable before optimizing advanced rendering cases.
- Keep the math rendering pipeline observable and debuggable so raw text fallback is easy to reason about.
- Treat per-document preamble persistence as part of the core feature set, not a later cosmetic addition.

## Validation

Use real commands that match this repo:

- Build: `xcodebuild -project MathPDF.xcodeproj -scheme MathPDF -derivedDataPath .build/SignedDerivedData build`
- Test: `xcodebuild -project MathPDF.xcodeproj -scheme MathPDF -derivedDataPath .build/SignedDerivedData test`
- Build and launch helper: `scripts/build-and-launch.sh`

Validation defaults:

- If a future Codex session starts in a restricted sandbox by mistake, remind the user to grant full filesystem and app-launch access for this project before attempting manual validation or signed launch workflows.
- Use signed builds by default for builds, tests, launches, and manual validation.
- Use `scripts/build-and-launch.sh --signed` for normal app validation.
- Use `scripts/build-and-launch.sh --unsigned` only for narrow debugging experiments that explicitly need an unsigned comparison.
- Add `--build-only` when you need to inspect the built `.app` or launch it manually.
- The signed app target must keep `ENABLE_OUTGOING_NETWORK_CONNECTIONS = YES`. Without the resulting `com.apple.security.network.client` entitlement, the sandboxed `WKWebView` renderer crashes its `WebContent` and `Networking` helper processes even for local `loadHTMLString` note content.
- Annotation authoring and save-to-document workflows require `ENABLE_USER_SELECTED_FILES = readwrite`; do not regress that to `readonly` once editing ships.
- Do not reintroduce a persistent `CODE_SIGNING_ALLOWED = NO` Xcode build-setting override just to get an unsigned build; that contaminates plain `xcodebuild` products and obscures signed-versus-unsigned comparisons.

Use a small trustworthy loop after each change. Run the narrowest command that proves the touched contract, then expand only as needed:

- Pure logic work: run the smallest relevant signed unit-test invocation, for example `xcodebuild -project MathPDF.xcodeproj -scheme MathPDF -derivedDataPath .build/SignedDerivedData -only-testing:MathPDFTests test`.
- View-only edits: build first, then launch the signed app and exercise the changed UI path manually.
- Project or integration changes: run a full signed scheme build, then tests if the build passes.
- User-visible workflow changes: pair the narrowest automated check with a manual product check in the running signed app.
- For UI-test iteration, first prove the target compiles with `build-for-testing` before running the test bundle.
- Do not leave template placeholder tests in place once a target gains real workflow coverage. Remove them or replace them with meaningful checks.

## Product Validation

Building is necessary but not sufficient. For MathPDF, validation should prove user-visible reader behavior whenever a change affects product flow.

- Use `pdfs for testing/ell_curves.pdf` as the default manual validation fixture unless a task needs a different sample.
- For reader-shell and PDF-loading changes, prove the PDF opens and the document window stays usable.
- For sidebar and note-discovery changes, prove `Table of Contents` and `Notes` behave correctly and selecting a note reveals it in context.
- For note-editing changes, prove note text stays plain text and persists through the intended save path.
- For math-rendering changes, prove valid math becomes more readable and broken math falls back to readable raw text.
- For metadata or preamble changes, prove document scope and PDF round-tripping remain intact.

Standard manual loop for user-visible changes:

- Launch the signed app with a representative PDF, usually `scripts/build-and-launch.sh --signed "pdfs for testing/ell_curves.pdf"`.
- Exercise the changed workflow in the running app.
- Capture a screenshot of the app window with the macOS window-capture skill, for example `/Users/linzihong/.codex/skills/macos-window-capture/scripts/capture_app_window.sh --app "MathPDF" --output /tmp/mathpdf-debug/validation.png`.
- Inspect the screenshot before reporting success.

UI test rules:

- Every `XCUIApplication` that a test launches must be terminated explicitly.
- Prefer deterministic launch arguments or environment variables such as `MATHPDF_OPEN_DOCUMENT` over driving `NSOpenPanel`.
- Add stable accessibility identifiers before depending on UI assertions.
- A screenshot-only UI test is not enough; it still needs a concrete assertion.

## Documentation Rules

- For any task expected to last more than a small, single-file edit, create or update a compact Work Card that follows [PLANS.md](/Users/linzihong/Documents/Development/Xcode/MathPDF/PLANS.md).
- Store checked-in Work Cards under [docs/plans/](/Users/linzihong/Documents/Development/Xcode/MathPDF/docs/plans).
- Whenever you create, supersede, pause, or complete a Work Card, update [docs/plans/EXECPLAN_INDEX.md](/Users/linzihong/Documents/Development/Xcode/MathPDF/docs/plans/EXECPLAN_INDEX.md) in the same change. Future sessions should be able to discover plan relationships from the index alone.
- Keep [docs/CURRENT.md](/Users/linzihong/Documents/Development/Xcode/MathPDF/docs/CURRENT.md) short and current whenever the repository is left with unfinished active work.
- When product-facing behavior changes, update [docs/initial_description.txt](/Users/linzihong/Documents/Development/Xcode/MathPDF/docs/initial_description.txt) or add a more structured product doc in `docs/` as part of the same work.
- When reporting work, always include whether the task was treated as greenfield or existing-project, the exact scheme used, the simulator used or an explicit statement that none was used, and the smallest validation steps actually run.
