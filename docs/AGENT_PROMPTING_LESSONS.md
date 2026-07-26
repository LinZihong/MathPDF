# Prompting Independent Product Reviewers

This note records reusable lessons from the MathPDF overhaul. It is about how to
commission judgment, not how to predetermine a verdict.

## Ask for the product spirit, then evidence

A useful design prompt starts with the human standard the product must meet:
immediate comprehension, calm reading flow, trustworthy feedback, native
platform character, and confidence in ordinary daily use. Concrete user
complaints are samples of that standard, not a closed checklist. Preview is a
reference for macOS taste and behavioral expectations, not a pixel template.

The reviewer must still report observable evidence: what they opened, what they
tried without coaching, what they initially believed a control meant, what
actually happened, and which states determined the verdict. A polished static
screenshot is not evidence of a coherent interaction model.

## Preserve naive discovery

Do not tell a visual reviewer where the confusing affordance is or which control
is suspected to lie. Ask them to read, scroll, discover annotated material,
open and edit it, and try the controls they naturally expect to work. This tests
whether the interface communicates its own model. Feeding the suspected answer
to the reviewer turns independent judgment into confirmation.

The prompt should explicitly authorize holistic judgment—semantic clarity,
hierarchy, typography, density, spatial behavior, feedback, accessibility,
edge cases, and truthfulness—without turning those words into an exhaustive
scorecard. The reviewer remains responsible for noticing important qualities
that the prompt did not name.

## Test truth, not only appearance

Every visible state must correspond to an accepted model mutation. Reviewers
should interact with controls and compare the resulting document state, not
merely judge whether the controls look native. Optimistic local state that can
outlive a rejected edit is a product-trust failure even when it looks polished.

Code and visual audits are complementary. A visual reviewer can discover that
an affordance is unclear; a code auditor can prove that a color checkmark may
change while the document rejects the color. Neither substitutes for the other.

Ask the reviewer to challenge the harness as well as the product. In the
annotation-affordance audit, a holistic macOS/PDF reviewer independently found
that counting `NSPopover`s could not detect a PDFKit page-drawn marker, and
that a DEBUG replacement window changed undo and menu routing by bypassing the
real `DocumentGroup`. The useful prompt supplied the product contract and
authorized architectural judgment; it did not feed either suspected defect.
This is the right level of prompting: establish the human and semantic standard,
then require the reviewer to decide whether the evidence actually measures it.

## Make operational safety part of the prompt

GUI review prompts need an explicit first expected state, a short time limit,
permission-sheet stop conditions, an exact fixture and app path, a ban on
broadening filesystem/TCC access, a one-retry maximum, and mandatory process
cleanup. These constraints cannot be assumed merely because the repository
documents contain them.

The reviewer prompt also needs to constrain its own control surface. Do not use
AppleScript or `System Events` merely to discover a window or take a screenshot:
that can create a ChatGPT Automation prompt which then blocks an otherwise safe
product test. Prefer app-scoped XCUITest, Computer Use when it returns visible
state promptly, or CoreGraphics window-ID capture. A QA-tool permission prompt
is still a failed route even when MathPDF did not request it.

A stuck Computer Use call is not product evidence. If the first state cannot be
observed within the bound, the only valid result is an unverified review plus
cleanup—not a speculative SHIP or NO-SHIP verdict.

The startup bound and the review bound solve different problems. The first
observable state has a 30-second permission/startup gate and at most one clean
retry. Once that state exists, a later stalled interaction must be described as
a product or automation failure, not mislabeled as a startup violation. Give
the entire delegated session its own short bound as well; otherwise a reviewer
can leave a healthy but idle app open indefinitely without producing judgment.
If the reviewer exceeds that bound, the primary agent should request a verdict
from evidence already gathered, then interrupt and clean up if it still does
not return.

## Keep the gatekeeper check-only

The prompt gatekeeper evaluates whether the authored prompt preserves
independence, product spirit, evidentiary rigor, and operational safety. It may
pass or return concise defect diagnoses. It must not rewrite the prompt: the
primary agent owns the intent and must learn by revising its own wording.

Operational rules deserve the same gatekeeping as design language. In the
final MathPDF review prompt, a fresh check-only gatekeeper rejected the first
draft because it omitted the repository's one-clean-retry recovery rule. The
primary agent revised that omission itself; the second check passed. This is a
useful rejection: it improved safety without steering the reviewer's taste or
turning the gatekeeper into a ghostwriter.

The last focused audit supplied another useful example. One gatekeeper rejected
the candidate because its PASS rule allowed a named contract to remain
unexercised; a second rejected it because “do not inspect project files” did not
explicitly prohibit modifying them. The primary agent corrected each omission
in its own words. A fresh third gatekeeper then accepted the exact prompt that
was sent unchanged to the reviewer. Multiple terse rejections were more useful
than one unsolicited rewrite because they preserved authorship while exposing
distinct holes in the contract.

## Use decisive acceptance language

The final reviewer returns SHIP or NO-SHIP and only the few observations that
materially determine that verdict. A NO-SHIP response should describe a
coherent product direction rather than a micromanaged patch list. After fixes,
acceptance requires a fresh interactive pass; an earlier verdict cannot be
reinterpreted as approval of a build the reviewer never used.

## Audit an acceptance even after it passes

A gatekeeper pass is evidence, not abdication of authorship. For the final
MathPDF interactive-review prompt, a fresh check-only gatekeeper accepted the
first draft, but the primary agent's own reread found that “the requested
fixture” was not an exact path and “do not edit files” conflicted with testing
PDF saves. The primary agent corrected those ambiguities itself and obtained a
second ACCEPT. This is the desired relationship: the gatekeeper challenges the
prompt, while the author remains accountable even when the check says yes.

## Examples that worked in MathPDF

The following are verbatim prompts sent to independent reviewers. They are
included as evidence of the technique, not as templates to copy mechanically.

### Verbatim final visual-review prompt

> Act as the senior macOS product design authority for a daily-use native PDF
> reader, not as a checklist executor or Preview pixel-copy critic. Reassess
> the current product holistically from the two exact post-redesign,
> post-scroll-fix app-window screenshots below. Use view_image yourself at
> original detail. Decide independently whether the visual design now has
> sufficient native taste, clarity, restraint, hierarchy, and note
> discoverability to ship today. Do not assume earlier criticisms remain true;
> judge only current evidence. Return a crisp VISUAL PASS or VISUAL NO-PASS with
> only material issues that would genuinely block daily use. Screenshot paths:
> /private/tmp/MathPDF-Fixtures/final-visual/post-scroll-fix/A478DF12-BCCE-4C30-AFCF-5322EB6B2046.png
> and
> /private/tmp/MathPDF-Fixtures/final-visual/post-scroll-fix/C3AFC567-2CBB-468F-9BA3-D7B1614BBF85.png

### Verbatim final interactive-review prompt

> Use Computer Use now for the final independent interactive product verdict
> on the already-running signed production MathPDF app with its in-memory
> annotated-reader fixture. You are the senior macOS PDF-reader product/design
> authority; judge the whole daily-use experience independently, not a Preview
> pixel copy and not a checklist. Discover the sidebar modes yourself, open a
> highlighted note from both sidebar and on-page affordance, inspect read/edit
> continuity, recolor and Undo, toolbar/search/page controls, scroll/viewport
> behavior, and overall native taste. The final static redesign already
> received VISUAL PASS, but do not inherit that verdict. Expected first visible
> state: one MathPDF window titled Untitled with a 3-page fixture, within 30
> seconds. If Computer Use does not return visible state within 30 seconds, any
> permission/TCC/Open panel appears, or the route stalls, stop and return
> UNVERIFIED—do not use AppleScript/System Events, do not broaden permissions,
> do not infer from code or screenshots. Do not save or open any file path.
> Return INTERACTIVE PASS or INTERACTIVE NO-PASS with only material evidence,
> then close MathPDF and verify cleanup. This prompt follows the previously
> check-only-gatekept final review contract in
> docs/FINAL_INTERACTIVE_REVIEW_PROMPT.md.

### A holistic visual brief found defects that were never named

The first independent visual reviewer was set up as a senior macOS product
designer responsible for judging a daily-use mathematical PDF reader. The brief
explained the desired product spirit—document dominance, native restraint,
clear annotation discovery, and trustworthy interaction—but did not point to a
particular toolbar control, badge, card, or sidebar row.

That reviewer returned `VISUAL NO-PASS` and independently identified the custom-
capsule feel of the toolbar, an ambiguous on-page marker, an overly heavy note
surface, weak read/edit continuity, cramped sidebar rows, and stale color
identity after recoloring. Those observations were valuable precisely because
they were not restatements of defects supplied in the prompt.

After the redesign, the follow-up prompt told the same reviewer to act as the
final macOS design authority, inspect two exact current screenshots at original
detail, judge only the new evidence, and neither inherit the old verdict nor
reduce the task to Preview pixel matching. The fresh result was `VISUAL PASS`.
This was a productive no-pass/pass loop: the standard stayed stable while the
evidence changed.

### A natural-use brief exposed trust and toolbar-adaptation failures

After Computer Use became available only in a separate user-visible main task,
the reviewer was asked to behave as a daily-use macOS PDF reader expert and to
discover the product naturally. The prompt did not mention dirty-state or
adaptive-toolbar suspicions. The first interactive review independently found
that undo could restore every visible annotation while the real window still
claimed `Edited`; the next build independently exposed that Find disappeared at
the default window width. Those were release-blocking truths, not aesthetic
preferences. Focused follow-ups then proved the corrected contracts with the
exact shortcut syntax `key:"super+z"` and `key:"super+f"`.

The operational lesson is that an auditor should launch the exact signed app
and use the same document scene a person uses. When delegated Computer Use
approval was invisible in ordinary subagents, repeatedly retrying those hidden
workers produced no product evidence. Reusing a separate visible main task as
the independent reviewer preserved human-style interaction and made permission
state observable without weakening reviewer independence.

### Verbatim focused post-audit contract

> PASS only if every named contract is exercised and passes. A product defect
> is NO-PASS. An evidence/tool limitation that prevents exercising any contract
> is UNVERIFIED, never PASS. Do not infer success from code or earlier reports.

That sentence followed two check-only rejections and prevented a plausible but
invalid PASS based on exercising only the easiest subset. The complete prompt
also named the exact signed executable and in-memory fixture, prohibited both
inspection and modification of project files, separated the 30-second launch
gate from a three-minute session bound, limited recovery to one retry, and
required exact-process cleanup.

The same focused contract also showed why a prior holistic PASS must not end
adversarial review of newly changed trust paths. Successive fresh runs proved
editor-local Undo, exposed duplicate committed-note change accounting, exposed
the opposite undercount after that duplicate was removed, and finally isolated
the same missing dirty-state ownership in Math Macros. Each NO-PASS described
the exact current candidate instead of being averaged with earlier good
evidence. The prompt named user-visible state transitions and required exact
before/after evidence without telling the reviewer which implementation
variable to blame.

### A semantic ownership brief exposed a hidden PDFKit presentation path

The annotation auditor received the user-level invariant rather than a proposed
patch: one annotation should produce one MathPDF affordance at runtime, while
the saved PDF should preserve a reciprocal Highlight–Popup relationship for
Preview. The auditor was asked to challenge both implementation and proof.

It found that removing Popup objects from `page.annotations` was insufficient:
PDFKit could still paint its closed-popup marker through the owning highlight's
live `popup` pointer. It also found that color Undo could lose an imported
Popup's independent color and appearance stream. The resulting fix established
the stronger three-part invariant—no runtime Popup page member, no runtime owner
pointer, reciprocal persistence graph—and added the missing imported-color/AP
regression. A narrower prompt such as “check that Popups are removed from the
page” would likely have confirmed the incomplete implementation.

### The check-only gatekeeper improved safety without taking authorship

The final interactive-review prompt was given to a gatekeeper with an explicit
contract: return acceptance or concise defects, and never rewrite the prompt.
The gatekeeper rejected a draft that omitted the one-clean-retry rule. The
primary author then revised the prompt rather than adopting gatekeeper-written
language.

On another pass the gatekeeper accepted, but the primary author's own reread
still found that “the requested fixture” did not name an exact safe path and
that a blanket “do not edit files” instruction conflicted with exercising saves
on a disposable PDF. Correcting those issues after an acceptance demonstrated
the intended division of responsibility: the gatekeeper is an adversarial
check, not a substitute author or a source of infallible approval.

### `UNVERIFIED` was a successful review outcome

The Computer Use reviewers received an exact signed-app state, the in-memory or
`/private/tmp/MathPDF-Fixtures` boundary, a 30-second first-state limit, a one-
retry maximum, permission-sheet stop conditions, and mandatory cleanup. They
were also told not to infer a verdict from source code, build logs, or old
screenshots if visible interaction evidence never arrived.

When the Computer Use channel stalled, the reviewers returned `UNVERIFIED` or
were interrupted at the bound, and MathPDF was closed. This did not satisfy the
interactive acceptance gate, but it was still good reviewer behavior: it
prevented a fabricated ship verdict, an unbounded wait, and pressure to grant
broader permissions. Prompts should make epistemic refusal an explicit success
condition when the required evidence is unavailable.
