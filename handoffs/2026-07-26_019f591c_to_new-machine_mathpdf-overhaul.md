# MathPDF overhaul handoff: continue on another machine

Status: **ACTIVE — NOT RELEASE-SIGNED-OFF**

Created: 2026-07-26

Source task: `local/019f591c-8b73-7803-adce-70cc076c1833`

Independent visible-audit task: `local/019f795d-c5e5-7110-87b8-d725e34c7866`

Target task: a new task on the other machine (ID not yet known)

Transfer route: committed repository state; worktree handoff failed

Project: existing macOS SwiftUI/PDFKit app

Scheme: `MathPDF`

Simulator: none

## Instruction to the receiving agent

Treat this file as the durable task handoff, not as product ground truth. First
read, in order:

1. `AGENTS.md`
2. `docs/initial_description.txt`
3. `docs/CURRENT.md`
4. `docs/TESTING.md`
5. `docs/plans/preview_replacement_overhaul.md`
6. `docs/decisions/annotation-popup-interoperability.md`
7. this handoff

Then inspect the actual checkout and the commit containing this file. Create an
active goal whose objective is to finish the existing Preview-replacement
overhaul, not to start a new redesign. Continue autonomously until the remaining
contracts pass or a genuine external blocker is reached. Do not treat any
historical plan, prior PASS, or this handoff as authority over current code and
fresh evidence.

The immediate next task is narrow: verify and, if needed, finish native document
dirty-state accounting for committed note edits and Math Macros. Do not reopen
the already-settled broad UI redesign unless fresh holistic evidence finds a
real regression.

## User's original commissioning prompt — verbatim

The following is the original prompt exactly as supplied in the source task. It
must remain available to future agents as the product ambition and autonomy
contract:

> This is a previous project that I ditched when it became extremely frustrating for me to have to micro-manage the agent. This might significantly improve with [@build-macos-apps](plugin://build-macos-apps@openai-curated-remote). Overall, my feeling was first and foremost that the UI/UX simply is too heavy and clunky. It's burdened by unintuitive interface that requires otherwise unnecessary clicks. This therefore creates an "unresponsive feeling". A perhaps inappropriate analogy is that Apple would never design an app like this; it feels more like a Windows-type object. It's a challenge for you to figure out exactly what these would mean. Moreover, edge cases are not thoroughly considered in previous rounds. This simple PDF reader was surprisingly hard to get right; there were many design flaws not considered by previous agents (e.g., note overlay positions, save workflows, unnatural/unexpected/maddening scroll position re-anchoring).
>
> My goal is a one-shot vast improvement of the experience. It should replace my macOS Preview app TODAY by offering a comparable intuitive experience, strengthened by the TeX ability of MathPDF. I'm taking this as a benchmark of GPT 5.6 Sol's capabilities, notably an improvement of front-end designs, which I've heard wonderful things about. Do not disappoint me. The objective is simple: with minimal instruction from me, you should ship the best product which I would be happy with. There should be enough context in this project to figure out my (perhaps unspoken) wishes for this product. After a thorough audit of this project, ask me questions about my visions if there are substantial doubts.
>
> Consider this ONE-SHOT: once there is a clear vision, do not stop until finish. We end at a great product that's pleasant to use today. If you've decided that something should be done, it should be done in this session. Tell me what's unclear now, or at the latest after an audit.
>
> Autonomously incorporate adversarial prompting into your strategies. Dynamically invoke independent agents to audit or advise on important work as you see fit; for me, UI/UX is obviously very important. Unless you are extremely confident in your design capabilities, generate images of your intention first and consult/discuss with an independent agent who has context of the product vision.
>
> Do NOT be afraid of major overhauls. Discard everything if the skeleton is just not right or optimal. It should still feel much like a native macOS app, ideally with PDFKit.
>
> Tex: currently use KaTex, originally tried MathJax but switched during signing issues (which turn out was not because of mathjax). But I learned of alternatives like RaTex and most recently SwaTex. I would not mind switching if one is just more natural.
>
> Note: the current agents.md and various docs/guidelines may no longer be optimal for these goals. pdfs_for_tests folder do not exist on this machine. New pdfs for your tests are in place, but you might want to take appropriate sections of them and modify some of the comments.

The user's immediate clarification after that prompt was also:

> 1. yes; 2. recommendation ok; 3. a preamble i use for my tex documents, but this surely is over complicated for annotation rendering; I guess math operator and simple commands like \Q should work, no other expectations.
>
> Good identifying some overall product spec improvements. What about UI? You have not told me plans. Do you want to generate some designs for me to look over, or should I trust you with your design instincts plus your iteration with your designers? Use[$apple-design](/Users/linzihong/.codex/skills/apple-design/SKILL.md) if helpful.
>
> Should i also trust you to come up with CORRECT set of tests and testing RULES to fulfil the overhaul intentions?

The referenced preamble was:

`/Users/linzihong/Documents/Mathematical writings/Moduli of (3,3)-curves/preamble.sty`

It was context for supported simple macros/operators, not a requirement to
support an entire TeX preamble.

## Product intent and user constraints accumulated afterward

These points were repeatedly emphasized and remain binding unless the user
explicitly changes them:

- The PDF must stay visually dominant. The app must feel native, light,
  immediate, and calm—not like a ported Windows/Java application or a 2010s
  custom dashboard.
- Learn taste and interaction hierarchy from Preview; do not pixel-copy Preview
  or reduce design review to rote comparison.
- Use native macOS document, window, toolbar, sidebar, menu, inspector,
  accessibility, undo, search, and keyboard conventions. Custom surfaces are
  justified only where MathPDF's TeX-aware annotation workflow requires them.
- Toolbar controls must be appropriately sized and discoverable at ordinary
  window widths. Hide secondary choices in native menus instead of heavy blue
  segmented tabs.
- The sidebar is not the primary way to discover notes. While scrolling the
  PDF, highlights with attached notes must have an obvious, fixed,
  highlight-adjacent on-page affordance.
- The note badge must stay fixed beside its source highlight. It must not float
  around with a leader line. The contained reading/editing surface should be
  positioned beside or below the source without covering it when space exists.
- Avoid maddening viewport movement. Direct activation must preserve page,
  scale, and clip origin; sidebar navigation should reveal minimally and keep
  truthful Back history.
- Highlight color choice must work and remain coherent across the page
  highlight, badge, sidebar accent, note surface, and selected palette value.
- Selected-text context menus, annotation placement, edit/commit/cancel/delete,
  undo/redo, sidebar mode switching, Find, Save/Save As/Revert, and window close
  behavior are product workflows, not isolated buttons.
- The user explicitly disliked automation taking over the desktop, then later
  allowed it when useful. Prefer focused Computer Use for visible QA, but visual
  inspection cannot be replaced by blind UI automation.
- Permission prompts are immediate failures. Never ask for or broaden Documents
  access. Never GUI-open source PDFs from the checkout or Documents. Use the
  debug-only in-memory fixture or realistic derived fixtures under
  `/private/tmp/MathPDF-Fixtures`.
- Build/test with the normal signed `MathPDF.app` production host and Automatic
  Apple Development signing. Out-of-sandbox Xcode execution is normally
  required on this machine. `MathPDFTestHost` is fallback-only.
- Close every MathPDF/Preview window and terminate every launched process after
  testing.
- Keep docs current with implementation and evidence.
- Independent reviewers must be prompted as holistic experts, not
  micromanaged toward bugs the primary agent already knows. A separate fresh
  prompt gatekeeper may only CHECK a reviewer prompt; it must never rewrite it.
- Record prompting lessons, including real prompts that worked, in
  `docs/AGENT_PROMPTING_LESSONS.md`.
- At the ultimate end of the original goal, terminate only the exact
  `caffeinate -d` assertion the user started and verify it is gone. Do not kill
  unrelated `caffeinate` processes. This has **not** been done because the goal
  is not yet complete.

## Interoperability contract and architecture

The user rejected sidebar-only note discovery and clarified the intended disk
contract:

1. Highlight notes use ordinary PDF markup owner contents plus a standards-
   valid reciprocal `/Highlight /Popup -> /Popup /Parent -> owner` graph.
2. MathPDF suppresses PDFKit's native popup presentation only in memory and
   renders one MathPDF page affordance/surface.
3. Saved output should be semantically indistinguishable from a normal
   interoperable PDF annotation graph, without proprietary note records,
   companion `/Text` duplicates, orphan Popups, or duplicate visible markers.
4. Exact Preview bytes or identical cross-reader styling are not required;
   semantic interoperability is.

The current accepted implementation keeps PDFKit/PDFView for viewing,
selection, navigation, and runtime annotation objects. A separate persistence
session preserves hidden Popup companions and reciprocal edges. Dirty saves use
the embedded qpdf-backed writer and strict semantic revalidation. Runtime
`page.annotations` excludes Popup companions and visible owners have a nil live
`popup` pointer, preventing PDFKit from painting a second closed-Popup marker.

Do not regress to any of these rejected approaches:

- deleting all Popup objects on save;
- adding a second `/Text` note for every highlight;
- relying on `highlight.popup = popup` alone and assuming PDFKit serialization
  preserves it;
- using `/AP` alone as popup semantics;
- byte-copying Preview output;
- introducing a proprietary MathPDF note format.

See `docs/decisions/annotation-popup-interoperability.md` for the durable
decision and `docs/CURRENT.md` for evidence. The earlier side-task handoff about
interoperability was useful context, explicitly not ground truth.

## What the overhaul currently contains

The working tree in the handoff commit includes a broad native interaction
redesign and final-state hardening:

- a contained page-attached note read/edit surface replacing detached popovers
  and a note inspector;
- fixed highlight-adjacent comment badges, with no leader-line floating;
- runtime suppression of PDFKit Popup presentation while preserving reciprocal
  serialized Popup graphs;
- true source-list selection and a quiet title-menu sidebar mode switch;
- a lighter native toolbar with Back/Forward, direct page entry, zoom, a concise
  annotation/color menu, place-note state, and native adaptive `.searchable`;
- default-window Command-F with an accessibility name of `Search PDF`;
- document-scoped Math Macros inspector and KaTeX rendering with readable raw
  fallback;
- named Preview-compatible highlight colors, synchronized across all surfaces;
- one-step document undo for committed annotation changes;
- an isolated AppKit text editor undo stack so Command-Z while editing undoes
  typing without prematurely committing or closing the editor;
- pending note drafts integrated with `NSDocument` editing registration so
  autosave/close can commit or reject them coherently;
- focused semantic tests for annotation topology, identity, metadata,
  preservation, dirty mutations, lifecycle, runtime presentation, and UI
  contracts.

`MathPDF/NativeSearchField.swift` is intentionally deleted; native
`.searchable` replaced the custom bridge.

## Latest visible evidence and the exact remaining defect

The independent auditor used only the signed candidate at:

`/private/tmp/MathPDF-DerivedData/Build/Products/Debug/MathPDF.app`

with the debug-only in-memory three-page fixture. It repeatedly reached exactly
one Untitled document window with no Open/TCC/Documents prompt.

Already proved in visible interaction:

- the fixed badge sits beside the source highlight;
- there is no competing PDFKit marker;
- the surface is attached and does not cover its source;
- color continuity works and undo restores it;
- close clears sidebar selection;
- note placement has a visible active state;
- default-window Command-F presents/focuses `Search PDF`, searches, navigates,
  and clears cleanly;
- editor-local Command-Z restores the exact `A point of $\Q$` baseline while
  the editor stays open;
- note and macro content undo restore their exact baselines.

The last completed independent verdict before the handoff patch was
`INTERACTIVE NO-PASS`:

- editor-local typing correctly showed Edited and one editor Undo cleared it;
- after Done, the committed annotation changed, but the window immediately
  became clean instead of remaining Edited;
- Math Macro edits changed the macro text/count but never showed Edited;
- one Command-Z restored both note and macro contents correctly.

Therefore the remaining blocker was native document dirty-state accounting,
not content undo.

## Latest code patch at handoff time

After that verdict, the source task applied a new exact-window change-accounting
patch:

- `ContentView` now owns `DocumentWindowState`, which attaches to the actual
  containing `NSWindow`, observes `isDocumentEdited`, and records permanent
  changes through that window's `NSDocument.updateChangeCount(.changeDone)`;
- successful committed note edits call the containing document's
  `updateChangeCount(.changeDone)` only after the temporary draft change has
  been balanced;
- `PreambleInspectorView` records a permanent change for ordinary macro edits,
  while skipping setter calls that occur during undo/redo;
- `MathPDFDocument.updatePreambleFromEditor` now returns whether a real model
  change occurred;
- KVO delivery is kept on the main actor.

This patch addresses both observed failures and avoids the earlier duplicate
count: the pending note draft is cleared before the committed model mutation
records its own permanent change.

Current evidence for this patch:

- `scripts/build-and-launch.sh --signed --build-only` succeeded on 2026-07-25;
- a refreshed signed `build-for-testing` succeeded for the app, unit-test, and
  UI-test targets on 2026-07-26 after updating four focused test closures to the
  current draft-state callback signature;
- a final signed build-only then succeeded again on 2026-07-26, removing the
  test-injection products and verifying the production app;
- the app was signed by the normal Apple Development identity;
- designated requirement and required sandbox/network/user-selected-file
  entitlements were verified;
- no post-patch visible audit has yet been completed;
- a clean full test runner completion and post-patch visible audit still need
  refreshing on the receiving machine.

Do not claim this patch fixed the product until the focused visible contract
passes.

## Exact accepted focused audit prompt — verbatim

A fresh, check-only prompt gatekeeper accepted this prompt. The gatekeeper did
not rewrite it. Reuse it unchanged after producing a freshly signed candidate:

> Act as the independent macOS release auditor for one focused correction in the newly signed MathPDF candidate. Do not inspect or modify project files. Do not open, save, or export any filesystem PDF. Launch only /private/tmp/MathPDF-DerivedData/Build/Products/Debug/MathPDF.app/Contents/MacOS/MathPDF with the debug-only annotated-reader in-memory fixture and established restoration-suppression flags.
>
> Expected first observable state is exactly one visible Untitled three-page fixture window with no Open/TCC/permission prompt within 30 seconds. Any prompt or missed state is an immediate stop; terminate, inspect once, retry at most once, then return UNVERIFIED. Total session limit is three minutes.
>
> Exercise only these contracts with concrete visible/accessibility evidence:
> 1. Open the existing note editor, establish its exact baseline, type ` test`, and verify the window becomes Edited. While the editor remains focused and open, execute exactly one key:"super+z". PASS this contract only if the editor returns exactly to baseline and Edited clears.
> 2. Type ` test` again and commit Done. PASS this contract only if rendered contents change and the window says Edited. Execute one document-level key:"super+z"; contents and title must return exactly to baseline.
> 3. Open Math Macros, append one harmless macro, and require Edited to appear. Execute one key:"super+z"; macro contents/count and clean title must return exactly to baseline.
>
> Return INTERACTIVE PASS only if all three contracts pass. Any product defect is INTERACTIVE NO-PASS. Any tool/evidence limit is UNVERIFIED, never PASS. Do not infer from code or earlier evidence. At the end terminate the exact MathPDF process, verify pgrep -x MathPDF finds none, and report that no file/project mutation occurred.

The separate visible-audit task worked because it was a normal main task with
Computer Use permission. Spawned subagents could not receive an invisible
Computer Use approval and repeatedly hung. On the other machine, either use a
normal independent task in the same manner or run the visible audit directly;
do not revive the known blocked subagent route.

## Required next actions, in order

1. Pull the handoff commit and inspect `git status`; do not assume a clean tree
   if machine-local Xcode files differ.
2. Read the files listed at the top of this handoff and inspect the latest
   `DocumentWindowState`, `PendingDocumentEditor`, note commit, and macro binding
   code.
3. Run a signed all-target compile:

   ```sh
   xcodebuild -project MathPDF.xcodeproj -scheme MathPDF \
     -derivedDataPath /private/tmp/MathPDF-DerivedData build-for-testing
   ```

4. Run the signed unit suite in the production app host. Treat assertion
   completion separately from Xcode result/coverage finalization stalls:

   ```sh
   xcodebuild -project MathPDF.xcodeproj -scheme MathPDF \
     -derivedDataPath /private/tmp/MathPDF-DerivedData \
     -only-testing:MathPDFTests test
   ```

5. Finish with a freshly signed product:

   ```sh
   scripts/build-and-launch.sh --signed --build-only
   ```

6. Run the exact focused audit prompt above. Stop immediately on any permission
   prompt. Use only the in-memory fixture. Close and verify the app process.
7. If any contract fails, diagnose the ownership/counting path; do not paper
   over it by merely changing the subtitle. The native document must agree with
   close/save behavior.
8. If all three contracts pass, run one bounded regression inspection of Find,
   fixed badge geometry, single-affordance ownership, color continuity, and
   selection cleanup. Do not broaden into a new speculative redesign without
   evidence.
9. Request one final read-only adversarial code audit focused on document change
   accounting, undo/redo grouping, multiwindow routing, failed commits, view
   teardown, autosave, and close behavior. The reviewer must not modify files.
10. Update `docs/CURRENT.md`, the active Work Card, its index status, and
    `docs/AGENT_PROMPTING_LESSONS.md` with final truthful evidence. Only mark the
    Work Card completed after the required visible contracts pass.
11. Commit the completed slice. Preserve unrelated machine-local/user Xcode
    state.
12. At the ultimate goal end, close all MathPDF/Preview processes and terminate
    only the user's exact `caffeinate -d` process, verifying that unrelated
    assertions remain untouched.

## Validation history that must not be overstated

- Historical signed production-host unit suites passed through 65 cases.
- The current source contains 68 Swift Testing cases.
- One later invocation reported all 68 assertions passing, then stalled while
  Xcode finalized coverage/result logging and was terminated. That is assertion
  evidence, not a clean runner PASS.
- Subsequent signed runner attempts stalled before starting tests and add no
  product evidence.
- Signed `build-for-testing` for all three targets and a final signed build-only
  passed after the change-accounting patch.
- Earlier independent visual review eventually returned `VISUAL PASS` after
  correcting toolbar weight, source overlap, badge ambiguity, sidebar density,
  and color continuity.
- Earlier independent interactive review returned a PASS for default-window
  Find and the core attached-note affordance, but stricter post-audit contracts
  exposed the dirty-state issue described above. The newest applicable verdict
  remains NO-PASS until the patch is retested.

## Repository hygiene at handoff

Two Xcode files were already identified as user/machine-owned and must not be
staged merely to make the tree clean:

- `MathPDF.xcodeproj/xcshareddata/xcschemes/MathPDF.xcscheme`
- `MathPDF.xcodeproj/xcuserdata/linzihong.xcuserdatad/xcschemes/xcschememanagement.plist`

The handoff commit should include the product source, tests, project docs, the
intentional deletion of `MathPDF/NativeSearchField.swift`, and this handoff. If
the two Xcode files remain modified after checkout, inspect them as local state
and leave them alone unless the user explicitly asks otherwise.

## Important unresolved risks

- Does one document-level Command-Z after Done clear both annotation contents
  and the native Edited state with the new change count?
- Does one macro Command-Z restore text/count and clear the native Edited state,
  without double decrement or stale dirty state?
- Does redo correctly reapply content and dirty state for both paths?
- Does autosave/close commit a pending note draft exactly once under the new
  accounting?
- Does a failed note commit retain the pending draft and truthful dirty state?
- Does `DocumentWindowState` remain bound to the correct window under real
  multi-document focus and inspector lifetime changes?
- Will the latest signed unit/UI runner complete cleanly on the other machine?

These are concrete release questions. Answer them with current code and fresh
evidence; do not reconstruct a favorable answer from earlier reports.
