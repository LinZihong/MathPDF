# ExecPlan Index

This file is the repository-level index for executable plans. Treat it as the first stop after reading `docs/initial_description.txt`, `AGENTS.md`, and `PLANS.md` when a task may build on earlier work.

Purpose:

- give future sessions a stable place to discover all checked-in ExecPlans
- record the relationship between plans, features, and current status
- prevent later plans from becoming orphaned documents that only make sense with chat history

How to use this file:

- when creating a new ExecPlan, add a row for it in the table below in the same change
- when a plan supersedes, depends on, or branches from an earlier plan, record that explicitly in the `Related Plans` column
- when a plan is completed, paused, abandoned, or superseded, update its `Status`
- when a feature spans multiple plans, keep the feature name stable so future contributors can find the sequence

Statuses:

- `active`: the plan is still the current working specification for that feature slice
- `completed`: the plan’s intended scope shipped or was otherwise finished
- `paused`: work stopped intentionally and may resume later
- `superseded`: a newer plan replaced it for ongoing work
- `abandoned`: the plan is no longer expected to be implemented

## Plans

| Feature | Plan | Status | Related Plans | Notes |
| --- | --- | --- | --- | --- |
| MVP reader and math note rendering | [docs/plans/mvp_reader_math_notes_plan.md](./mvp_reader_math_notes_plan.md) | active | none yet | First real product slice. Covers PDF opening, note extraction, math-reading presentation, and fixture-driven validation around `pdfs for testing/ell_curves.pdf`. |

Revision note: moved under `docs/plans/` so the index now lives beside the plans it tracks and the top-level `docs/` directory stays organized.
