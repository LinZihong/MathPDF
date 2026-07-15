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
