# MathPDF Testing Rules

These rules define MathPDF's validation contract. They exist to prevent test
runs from becoming disruptive, to keep user PDFs safe, and to make regressions
prove the behavior that a reader actually exposes.

This file is authoritative for MathPDF validation. Installed Build macOS Apps
skills are supplemental: use them to choose narrow commands, classify failures,
and guide focused reruns, but do not let generic guidance weaken the rules below
or create a second build/run workflow. `scripts/build-and-launch.sh` is the
existing project entrypoint.

## Signed Execution

Required build and test evidence uses the project's default Automatic signing,
Apple Development identity, development team, and real sandbox entitlements.
Do not override these with `CODE_SIGN_IDENTITY=-`, `CODE_SIGN_STYLE=Manual`, or
an empty team: an ad-hoc build has an unstable TCC identity across rebuilds.
The standard test shape is:

```sh
xcodebuild -project MathPDF.xcodeproj -scheme MathPDF \
  -derivedDataPath /private/tmp/MathPDF-DerivedData \
  -only-testing:MathPDFTests test
```

Signed `xcodebuild` usually needs out-of-sandbox permission on this machine to
reach signing and keychain resources. If the same command fails inside the
agent sandbox with signing, keychain, or permission evidence, rerun it outside
the sandbox. An unsigned build is diagnostic evidence only and never satisfies
a required build, test, renderer, entitlement, or release gate.

## Local Interaction Policy

- Unit tests and build-for-testing are the default automated checks.
- The normal unit-test route is hosted by the production `MathPDF.app`. This
  keeps integration tests representative of the shipping document runtime and
  is safe only with the project's stable Apple Development signature and the
  restoration guards below.
- `MathPDFTestHost.app` remains available as a fallback diagnostic host. Use it
  only if the normal production host repeatedly prompts, hangs, or reopens a
  document after the permission-stall protocol has ruled out an unsafe fixture,
  stale process, or signing regression. Any fallback run must be labeled as
  test-host evidence and followed by a production-host run before satisfying a
  release gate.
- The shared `MathPDF` scheme keeps unit and UI test targets nonparallel and
  supplies `-NSDocumentReopenSavedDocuments NO` plus
  `-ApplePersistenceIgnoreState YES` as defense in depth. Do not remove them.
- Do not run UI-test automation on the user's active desktop unless the user
  explicitly approves it for that session. Compile the UI-test target with
  `build-for-testing`, then prefer a focused Computer Use pass for local visual
  and interaction validation.
- Every launched `XCUIApplication` must be terminated explicitly. Every manual
  validation run must quit MathPDF, and the final check must verify no process
  named `MathPDF` remains.
- Launch validation builds with `-ApplePersistenceIgnoreState YES`,
  `-NSDocumentReopenSavedDocuments NO`, and `-NSQuitAlwaysKeepsWindows NO`.
  State restoration must never reopen an older document or a build from another
  DerivedData directory.
- Build and execute every test product from `/private/tmp/MathPDF-DerivedData`,
  never a DerivedData folder beneath Documents. The DEBUG UI fixture is in
  memory and bypasses `NSOpenPanel`; it must not request broad folder access.
- A locked macOS session cannot provide valid UI evidence. If XCTest reports an
  app as `Running Background`, confirm the session is unlocked before changing
  product activation behavior or repeating the run.

## Fixture Safety

- `TestPDFs/` is untracked, read-only source material. It may be inspected or
  excerpted with non-GUI CLI tools, but it is never a launch fixture. Never pass
  a path inside `TestPDFs/`, the checkout, or another Documents directory to
  MathPDF, Preview, XCTest, `open`, or GUI automation.
- Never modify, overwrite, save, or annotate a supplied PDF in place.
- Manual fixtures live under `/tmp/MathPDF-Fixtures`. Create them by copying or
  excerpting realistic supplied PDFs, then add narrowly chosen annotations,
  outlines, metadata, rotations, or crop boxes to exercise the desired case.
- Prefer short, realistic fixtures over blank synthetic pages for visual and
  manual product checks. Blank generated PDFs remain appropriate for isolated
  unit tests where page content is irrelevant.
- Resolve symlinks and confirm the document URL begins with
  `/private/tmp/MathPDF-Fixtures/` before any GUI launch, edit, or save.
- `scripts/build-and-launch.sh` enforces that resolved boundary when given a PDF
  path. Do not bypass the guard with direct `open`, Preview, or another launcher.

## Permission-Stall Escape Protocol

No local approval should be assumed during unattended work. Apply this protocol
to app launch, UI automation, Computer Use, Open panels, and document opening;
ordinary builds have their own progress and timeout expectations.

1. Before launch, record the expected first observable state and verify every
   GUI-facing document path is under `/private/tmp/MathPDF-Fixtures/` or uses
   the debug-only in-memory fixture.
2. If the expected state does not appear within 30 seconds, or a permission
   sheet, `Running Background`, TCC denial, sandbox denial, or Open panel
   appears, terminate the app/test immediately. A pending prompt counts as a
   failure, not progress.
3. Inspect the path, process state, visible UI, and relevant log output once.
   Do not enter an unbounded wait/poll loop.
4. If a path escaped the fixture boundary, recreate the fixture under `/tmp`
   and retry once. If the path was already safe, only one clean relaunch is
   allowed after removing stale app instances or restoration state.
5. If the retry stalls, abandon that validation route, record the precise
   unverified gate, and continue with non-GUI evidence where useful. Never wait
   for an absent user, alter TCC settings, request broad Documents access, or
   repeatedly relaunch the same blocked command.

The primary agent remains responsible for elapsed time and cleanup even when a
subagent or automation owns the immediate check. Delegated prompts must include
the fixture boundary, 30-second signal, one-retry limit, expected evidence, and
return-on-blocker instruction.

## Required Contracts

- Annotation activation inside the visible PDF preserves page, exact scale, and
  clip-view origin. Sidebar navigation preserves scale and moves only enough to
  reveal an offscreen target.
- One PDF annotation produces one visible reading affordance. A test must fail
  if PDFKit's popup and MathPDF's popover appear together.
- Standalone `/Text` notes remain distinct from nearby highlights. Highlight
  notes store text on the owning annotation and round-trip a reciprocal
  `/Popup` and `/Parent` graph. Popup companions do not become sidebar notes,
  and no orphan popup or duplicate in-app surface may survive.
- Editing remains plain text, is undoable, does not invent companion `/Text`
  annotations, and survives PDF reserialization.
- The versioned MathPDF preamble marker in standard PDF Keywords imports from
  externally authored PDFs and round-trips without removing unrelated keywords.
- Valid macros render; malformed or unsupported TeX remains readable raw text;
  note and macro text cannot terminate the renderer's script element.
- Each document window owns independent reader state.

## Evidence Rules

- Tests assert product behavior, not screenshots or implementation details.
- Screenshots supplement assertions and must be visually inspected.
- PDF persistence tests reparse the output and compare semantic page,
  annotation, reciprocal relationship, content, and metadata state rather than
  requiring byte equality after an edit. A no-op snapshot remains byte-identical.
- PDFKit, AppKit, and WebKit mutation tests run on the main actor. WebKit probes
  run serially and use signed hosts with the required sandbox entitlements.
- Never use arbitrary sleeps when a notification, publisher, accessibility
  state, or delegate callback can prove completion.

## Headless Coverage Boundary

The signed unit suite is the authoritative non-GUI gate. It must prove, using
generated PDFs and semantic reparsing:

- note identity and indexing, including identical nearby note contents;
- annotation creation, edge clamping, edit, delete, undo, and popup ownership;
- atomic data writes that reopen with page count, crop boxes, rotation, outline,
  unrelated annotations, form widgets, metadata, and preamble intact;
- exact no-op behavior when a reveal target is already comfortably visible,
  plus scale-preserving cross-page reveal and Back behavior;
- independent controller and document state; and
- KaTeX macro rendering, raw fallback, and adversarial script containment.

Passing that suite does **not** prove behavior owned by SwiftUI's document
runtime or by an attached, visible AppKit window. The following remain explicit
GUI/manual release gates and must never be reported as unit-tested:

- idle autosave timing, Save As, Revert, close review, write-failure UI, and
  external-file conflict handling;
- real multi-window focus, window restoration, per-window undo routing, and
  security-scoped file access;
- event routing between text selection, annotation activation, and scrolling;
- anchored popover geometry at every window/page edge and dismissal on scroll;
- keyboard focus order, menu commands, VoiceOver, larger text, dark appearance,
  increased contrast, Reduced Motion, and Reduced Transparency; and
- responsiveness on the largest supplied research PDF.

If the desktop is locked or UI execution is not approved, report these gates as
unverified for that run. A unit-test pass is release-credible for PDF semantics
and headless state transitions, but it is not by itself a Preview-replacement
release sign-off.

Any failing semantic round-trip regression is a release blocker. Do not weaken,
skip, or convert one into a raw-byte assertion merely because PDFKit produced
the loss; PDFKit output is the product's persisted output.

## Standard Validation Order

1. Run the narrowest relevant signed unit tests, using the command shape above.
2. Build the UI-test bundle with `build-for-testing` when UI test code changed;
   do not execute it locally without approval.
3. Run `scripts/build-and-launch.sh --signed --build-only` and verify the deep
   signature plus sandbox, network-client, and user-selected read/write
   entitlements.
4. Use Computer Use with a `/tmp/MathPDF-Fixtures` research excerpt for the
   changed workflow. Record page and zoom before and after annotation actions,
   inspect the final screenshot, then quit every MathPDF instance.
