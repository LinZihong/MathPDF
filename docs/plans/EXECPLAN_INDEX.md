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
| MVP reader and math note rendering | [docs/plans/mvp_reader_math_notes_plan.md](./mvp_reader_math_notes_plan.md) | completed | none yet | First real product slice. Covers PDF opening, note extraction, math-reading presentation, and fixture-driven validation around `pdfs for testing/ell_curves.pdf`. |
| Robust math note rendering | [docs/plans/robust_mathjax_renderer_plan.md](./robust_mathjax_renderer_plan.md) | completed | [docs/plans/mvp_reader_math_notes_plan.md](./mvp_reader_math_notes_plan.md) | Replaces the MVP’s custom Swift renderer with a bundled MathJax-backed `WKWebView` surface while keeping the reader workflow intact. |
| Fix MathJax rendering regression | [docs/plans/mathjax_rendering_fix_plan.md](./mathjax_rendering_fix_plan.md) | paused | [docs/plans/robust_mathjax_renderer_plan.md](./robust_mathjax_renderer_plan.md) | Tightens the renderer contract and repairs the `WKWebView` integration after valid LaTeX notes were observed falling back to raw text. Paused while a narrower KaTeX probe determines whether the breakage is MathJax-specific or WebKit-wide. |
| KaTeX renderer probe | [docs/plans/katex_renderer_probe_plan.md](./katex_renderer_probe_plan.md) | completed | [docs/plans/mathjax_rendering_fix_plan.md](./mathjax_rendering_fix_plan.md) | Replaced the temporary parser fallback with a bundled KaTeX-backed `WKWebView`, proved that `WKWebView` math rendering works in the current macOS shell, and tightened the launch workflow used for fixture validation. |
| Signed-vs-unsigned debug build probe | [docs/plans/signed_build_probe_plan.md](./signed_build_probe_plan.md) | completed | [docs/plans/katex_renderer_probe_plan.md](./katex_renderer_probe_plan.md) | Documents that a genuinely signed repo-local `xcodebuild` product reproduces the rendering failure, and adds helper-script support for explicit signed or unsigned local builds. |
| Signed renderer root cause and fix | [docs/plans/signed_renderer_root_cause_plan.md](./signed_renderer_root_cause_plan.md) | completed | [docs/plans/signed_build_probe_plan.md](./signed_build_probe_plan.md), [docs/plans/katex_renderer_probe_plan.md](./katex_renderer_probe_plan.md) | Extends the reproduction into instrumented signed-versus-unsigned experiments, proves that the missing `com.apple.security.network.client` entitlement crashes sandboxed WebKit helpers, and lands the production fix. |

Revision note: moved under `docs/plans/` so the index now lives beside the plans it tracks and the top-level `docs/` directory stays organized.
