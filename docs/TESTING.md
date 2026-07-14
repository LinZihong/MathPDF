# MathPDF Testing Rules

These rules are part of the product contract. They exist to prevent test runs
from becoming disruptive, to keep user PDFs safe, and to make regressions prove
the behavior that a reader actually exposes.

## Local Interaction Policy

- Unit tests and build-for-testing are the default automated checks.
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
- Build and execute UI-test products from `/tmp/MathPDF-DerivedData`, never a
  DerivedData folder beneath Documents. The DEBUG UI fixture is in memory and
  bypasses `NSOpenPanel`; it must not request broad folder access.
- A locked macOS session cannot provide valid UI evidence. If XCTest reports an
  app as `Running Background`, confirm the session is unlocked before changing
  product activation behavior or repeating the run.

## Fixture Safety

- `TestPDFs/` is untracked user material. Never modify, overwrite, save, or
  annotate those files in place.
- Manual fixtures live under `/tmp/MathPDF-Fixtures`. Create them by copying or
  excerpting realistic supplied PDFs, then add narrowly chosen annotations,
  outlines, metadata, rotations, or crop boxes to exercise the desired case.
- Prefer short, realistic fixtures over blank synthetic pages for visual and
  manual product checks. Blank generated PDFs remain appropriate for isolated
  unit tests where page content is irrelevant.
- Opening a validation fixture must not request broad Documents-folder access.
  Confirm the document URL is under `/private/tmp/MathPDF-Fixtures` before
  editing or saving.

## Required Contracts

- Annotation activation inside the visible PDF preserves page, exact scale, and
  clip-view origin. Sidebar navigation preserves scale and moves only enough to
  reveal an offscreen target.
- One PDF annotation produces one visible reading affordance. A test must fail
  if PDFKit's popup and MathPDF's popover appear together.
- Standalone `/Text` notes remain distinct from nearby highlights. `/Popup`
  annotations do not become duplicate sidebar notes. Saved output deliberately
  normalizes PDFKit popup companions away while retaining note text on the
  owning annotation; no orphan popup may survive serialization.
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
  annotation, relationship-or-documented-normalization, content, and metadata
  state rather than PDF bytes.
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

1. Run the narrowest relevant signed unit tests.
2. Build the UI-test bundle with `build-for-testing` when UI test code changed;
   do not execute it locally without approval.
3. Run `scripts/build-and-launch.sh --signed --build-only` and verify the deep
   signature plus sandbox, network-client, and user-selected read/write
   entitlements.
4. Use Computer Use with a `/tmp/MathPDF-Fixtures` research excerpt for the
   changed workflow. Record page and zoom before and after annotation actions,
   inspect the final screenshot, then quit every MathPDF instance.
