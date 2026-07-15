# Work Card Index

This file indexes Work Cards and historical ExecPlans. Consult it after
`docs/CURRENT.md` when a task may build on earlier work; it does not define
product behavior, validation rules, or current implementation facts.

Migration note: this repository moved from long self-contained ExecPlans to compact Work Cards on 2026-05-02. Older long plans are historical unless their status is `active`.

Purpose:

- give future sessions a stable place to discover all checked-in Work Cards and historical plans
- record the relationship between plans, features, and current status
- prevent later plans from becoming orphaned documents that only make sense with chat history

How to use this file:

- when creating a new Work Card, add a row for it in the table below in the same change
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
| MVP reader and math note rendering | [docs/history/mvp_reader_math_notes_plan.md](../history/mvp_reader_math_notes_plan.md) | completed | none yet | Historical evidence for the first product slice. |
| Robust math note rendering | [docs/history/robust_mathjax_renderer_plan.md](../history/robust_mathjax_renderer_plan.md) | completed | [MVP reader](../history/mvp_reader_math_notes_plan.md) | Historical MathJax implementation evidence. |
| Annotation authoring and inline note popovers | [docs/history/annotation_authoring_inline_note_plan.md](../history/annotation_authoring_inline_note_plan.md) | superseded | [Preview replacement](./preview_replacement_overhaul.md) | Superseded prototype evidence. |
| Preview-replacement reader overhaul | [docs/plans/preview_replacement_overhaul.md](./preview_replacement_overhaul.md) | completed | [annotation prototype](../history/annotation_authoring_inline_note_plan.md), [MathJax renderer](../history/robust_mathjax_renderer_plan.md) | Reciprocal-popup persistence, the integrated native reader surface, signed production-host tests, direct Preview popup expansion, independent raw parsing, and the independent visual ship verdict pass. |
| Fix MathJax rendering regression | [docs/history/mathjax_rendering_fix_plan.md](../history/mathjax_rendering_fix_plan.md) | paused | [MathJax renderer](../history/robust_mathjax_renderer_plan.md) | Historical paused investigation, overtaken by KaTeX. |
| KaTeX renderer probe | [docs/history/katex_renderer_probe_plan.md](../history/katex_renderer_probe_plan.md) | completed | [MathJax regression](../history/mathjax_rendering_fix_plan.md) | Historical evidence for the renderer choice. |
| Signed-vs-unsigned debug build probe | [docs/history/signed_build_probe_plan.md](../history/signed_build_probe_plan.md) | completed | [KaTeX probe](../history/katex_renderer_probe_plan.md) | Historical signing investigation. |
| Signed renderer root cause and fix | [docs/history/signed_renderer_root_cause_plan.md](../history/signed_renderer_root_cause_plan.md) | completed | [signed build probe](../history/signed_build_probe_plan.md), [KaTeX probe](../history/katex_renderer_probe_plan.md) | Historical evidence for the entitlement fix. |

Active Work Cards remain under `docs/plans/`; non-active plans live under
`docs/history/` with non-operational banners.
