# MathPDF Work Cards

This repository used to require long self-contained ExecPlans. New and active
planning documents use the shorter Work Card workflow described here. Active
Work Cards live in `docs/plans/`; non-active plans live in `docs/history/` and
do not need to be rewritten unless their work becomes active again.

## Purpose

Work Cards exist to preserve enough intent for a future session to continue safely without spending excessive context on stale prose. They are handoff documents, not full implementation manuals. A coding agent should still inspect the current working tree, read the relevant source files, and validate behavior directly.

Use a Work Card when a task materially changes accepted product behavior,
crosses architectural boundaries, or is likely to continue across sessions.
Small, self-contained fixes do not need planning ceremony. Update
`docs/CURRENT.md` only when the repository is left with active unfinished work
or when its recorded state would otherwise become false.

## Document Responsibilities

Do not force unlike documents into one global source hierarchy:

- Direct user instructions control the current task.
- `docs/initial_description.txt` owns accepted product behavior and scope.
- `AGENTS.md` owns durable repository-wide agent constraints.
- `docs/TESTING.md` owns validation and local safety rules.
- `docs/CURRENT.md` owns active working-tree and validation state, which must be
  checked against the working tree and fresh evidence.
- Active Work Cards own only the delta, decisions, and next steps for their
  workstream.
- Historical plans and reports preserve context; their commands and status
  claims are not current instructions.

## Standard Files

`docs/CURRENT.md` is the first-stop state file after the product description.
Keep it short enough to read every session. Separate committed-and-validated,
uncommitted-or-unvalidated, and planned-only facts explicitly.

`docs/plans/*.md` contains Work Cards. A Work Card tracks one workstream and
should usually fit in 80-150 lines. Prefer concise bullets over narrative. Do
not repeat stable product requirements or testing protocols owned elsewhere.

`docs/plans/WORK_CARD_INDEX.md` indexes active and historical workstreams.
Update it when creating, completing, pausing, superseding, or abandoning a Work
Card.

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

Keep Work Cards compact and current. Prefer present deltas and decisions over
completed product history or speculative implementation detail.

Do not treat a Work Card as a substitute for reading code. Before implementing, inspect the files you will touch and verify assumptions against the working tree.

Record assumptions only when they affect scope, compatibility, or architecture. If an assumption becomes a durable decision, move it into `docs/decisions/`.

Use checkboxes only for actionable remaining work in `Next Steps`. Completed history belongs in `Current State`, `Validation`, or git history.

When accepted product-facing behavior changes, update
`docs/initial_description.txt` or add a focused product note in `docs/` as part
of the same work. Do not promote an experimental working-tree implementation to
the product contract before the decision is accepted.

For MathPDF, always state whether the task changes PDF annotation compatibility, math rendering fallback behavior, or per-document preamble metadata. These are core product constraints.

At a genuine phase boundary, make the prior state recoverable before starting a
risky architectural slice, update `docs/CURRENT.md`, and label implementation
separately from validation. Create a git checkpoint only when committing is in
scope. A blocked GUI gate does not block useful headless work, and no delegated
task may own indefinite waiting.

## Migration Note

Do not expand old ExecPlans to match this new format just for consistency. If an
old ExecPlan becomes active again, summarize its useful current facts into a
compact Work Card and record the relationship in
`docs/plans/WORK_CARD_INDEX.md`.

Commands in historical plans are evidence of what was run then, not reusable
instructions. Current validation always comes from `AGENTS.md` and
`docs/TESTING.md`.
