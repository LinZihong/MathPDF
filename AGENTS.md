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
4. `PLANS.md` and plan-specific docs created for a task
5. Existing code and tests

When a product decision is not settled in the description, record it as an explicit assumption in the relevant plan or ask the user if it affects architecture or compatibility.

## Repo Map

- `MathPDF/`: app code.
- `MathPDFTests/`: unit and logic tests using Swift Testing.
- `MathPDFUITests/`: UI and workflow tests with XCTest.
- `docs/`: product notes and supporting design material.
- [PLANS.md](/Users/linzihong/Documents/Development/Xcode/MathPDF/PLANS.md): required format and maintenance rules for execution plans.

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

- Build: `xcodebuild -project MathPDF.xcodeproj -scheme MathPDF build`
- Test: `xcodebuild -project MathPDF.xcodeproj -scheme MathPDF test`
- Build and launch helper: `scripts/build-and-launch.sh`

Current project facts confirmed locally:

- Scheme: `MathPDF`
- Targets: `MathPDF`, `MathPDFTests`, `MathPDFUITests`
- Platform: macOS (`SDKROOT = macosx`)
- Current treatment: existing-project change
- Simulator used: none, because the current checked-in target is macOS rather than iOS

Use a small trustworthy validation loop after each change. Run the narrowest command that proves the touched contract, then expand to broader builds later.

- Pure logic or parser work: run the smallest relevant unit test target or focused `xcodebuild test` invocation.
- View-only edits that do not affect build settings: run a build first, then launch the app and exercise the changed UI path manually.
- Project or integration changes: run a full scheme build, then tests if the build passes.
- User-visible workflow changes: pair the narrowest automated check available with a manual product check that demonstrates the actual reading or annotation behavior.

If the environment cannot run UI tests, simulator-backed tooling, or launch automation, still run the most relevant build or unit-test command available and record the limitation explicitly, including the exact scheme, simulator or lack of simulator, and checks used.

## Product Validation

Building is necessary but not sufficient. For MathPDF, validation should prove user-visible reader behavior whenever a change affects product flow.

Minimum expectations by change type:

- PDF loading or reader-shell changes: launch the app, open a representative PDF, and verify the document window appears and remains usable.
- Sidebar changes: verify `Table of Contents` and `Notes` are present when expected, can be selected, and reflect the active document state.
- Annotation discovery or note-list changes: verify notes appear in the sidebar, selecting a note reveals it in context, and both highlight-attached notes and box-style notes still behave correctly when relevant.
- Note editing changes: verify note text remains editable as plain text and persists through the intended save path for the current slice.
- Math rendering changes: verify supported math-like note text renders more readably, and invalid or unsupported math falls back to readable raw text without noisy failure UI.
- Preamble or metadata changes: verify per-document scope, verify the inspector-style editing path, and verify the document still round-trips as a normal PDF rather than a proprietary note format.

When practical, keep or create a small set of representative sample PDFs for manual and automated checks:

- a PDF with no notes
- a PDF with highlight-attached notes
- a PDF with box-style note annotations
- a PDF with valid math markup
- a PDF with intentionally broken math markup to verify fallback behavior

If sample files do not exist yet, say so explicitly in the plan or final report and describe the substitute validation used.

Use UI tests for stable, repeatable workflows once the UI exists, especially:

- launching the app into a known document state
- opening a PDF
- toggling or selecting sidebar views
- selecting a note and confirming context reveal
- editing a note through the intended UI flow

For early feature work, manual product validation is acceptable if the UI is still in flux, but do not stop at “build succeeded” when the change is user-visible.

## Documentation Rules

- For any task expected to last more than a small, single-file edit, create or update a plan that follows [PLANS.md](/Users/linzihong/Documents/Development/Xcode/MathPDF/PLANS.md).
- Keep plans self-contained. A future contributor should not need chat history to continue.
- When product-facing behavior changes, update [docs/initial_description.txt](/Users/linzihong/Documents/Development/Xcode/MathPDF/docs/initial_description.txt) or add a more structured product doc in `docs/` as part of the same work.
- When reporting work, always include whether the task was treated as greenfield or existing-project, the exact scheme used, the simulator used or an explicit statement that none was used, and the smallest validation steps actually run.
