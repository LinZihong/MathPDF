# MathPDF Work Cards

This repository used to require long self-contained ExecPlans. As of 2026-05-02, new and active planning documents should use the shorter Work Card workflow described here. Older ExecPlans in `docs/plans/` are historical records and do not need to be expanded or rewritten unless they become active again.

## Purpose

Work Cards exist to preserve enough intent for a future session to continue safely without spending excessive context on stale prose. They are handoff documents, not full implementation manuals. A coding agent should still inspect the current working tree, read the relevant source files, and validate behavior directly.

Use a Work Card when a task is larger than a small single-file edit, changes product behavior, crosses architectural boundaries, or is likely to continue across sessions. Very small fixes can be handled without a Work Card, but `docs/CURRENT.md` should still be updated when the repository is left in an unfinished state.

## Source Order

When instructions conflict, use this order:

1. Direct user instructions in the current conversation.
2. `docs/initial_description.txt`.
3. `AGENTS.md`.
4. `docs/CURRENT.md`.
5. Active Work Cards in `docs/plans/`.
6. Historical plans and older ExecPlans.
7. Existing code and tests.

## Standard Files

`docs/CURRENT.md` is the first-stop handoff file. Keep it short enough to read every session. It should say what is active, what is known to work, what is unfinished, and the next recommended step.

`docs/plans/*.md` contains Work Cards. A Work Card tracks one workstream and should usually fit in 80-150 lines. Prefer concise bullets over narrative. Do not repeat product background that already lives in `docs/initial_description.txt`.

`docs/plans/EXECPLAN_INDEX.md` remains the plan index for now. Update it when creating, completing, pausing, superseding, or abandoning a Work Card. The name is historical.

`docs/decisions/*.md` is for durable decisions. Create one only when a decision changes product behavior, PDF annotation compatibility, metadata persistence, signing or sandboxing, math rendering behavior, or an architecture boundary. Keep each decision record short.

## Work Card Format

Use this structure for new Work Cards:

    # <Feature or Workstream>

    Status: active | paused | completed | superseded | abandoned
    Last updated: YYYY-MM-DD
    Context: existing-project change | greenfield change
    Scheme: MathPDF
    Simulator: none, macOS app

    ## Scope

    Briefly state what this work changes.

    ## Non-Goals

    List what this work explicitly does not change.

    ## Current State

    - What is already true in the code or docs.
    - What remains unfinished.
    - Known risks or constraints.

    ## Decisions

    - YYYY-MM-DD: Decision. Short rationale.

    ## Next Steps

    - [ ] Concrete next step.
    - [ ] Concrete next step.

    ## Validation

    Passed:
    - Exact command or manual check, with date if useful.

    Not yet validated:
    - Remaining automated or manual checks.

    ## Notes

    Optional. Add only high-signal context that does not belong in `docs/CURRENT.md` or a decision record.

## Writing Rules

Keep Work Cards compact and current. A stale short note is easier to repair than a stale essay, so prefer present facts over speculative implementation detail.

Do not treat a Work Card as a substitute for reading code. Before implementing, inspect the files you will touch and verify assumptions against the working tree.

Record assumptions only when they affect scope, compatibility, or architecture. If an assumption becomes a durable decision, move it into `docs/decisions/`.

Use checkboxes only for actionable remaining work in `Next Steps`. Completed history belongs in `Current State`, `Validation`, or git history.

When product-facing behavior changes, update `docs/initial_description.txt` or add a focused product note in `docs/` as part of the same work.

For MathPDF, always state whether the task changes PDF annotation compatibility, math rendering fallback behavior, or per-document preamble metadata. These are core product constraints.

## Validation

Use real commands that match this repository. Prefer the narrowest command that proves the touched contract, then expand only when risk justifies it.

Common commands:

    xcodebuild -project MathPDF.xcodeproj -scheme MathPDF -derivedDataPath .build/SignedDerivedData build

    xcodebuild -project MathPDF.xcodeproj -scheme MathPDF -derivedDataPath .build/SignedDerivedData test

    scripts/build-and-launch.sh --signed "pdfs for testing/ell_curves.pdf"

When reporting work, always include whether the task was treated as greenfield or existing-project, the exact scheme used, the simulator used or an explicit statement that none was used, and the smallest validation steps actually run.

## Migration Note

Do not expand old ExecPlans to match this new format just for consistency. If an old ExecPlan becomes active again, summarize its useful current facts into a compact Work Card and mark the old plan as historical, superseded, or completed in `docs/plans/EXECPLAN_INDEX.md`.
