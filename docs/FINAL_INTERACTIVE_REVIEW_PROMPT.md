# Final Interactive Product Review Prompt

Status: ready, but do not run until the post-correction signed build and
`final-review-working.pdf` exist.

The primary agent authored this prompt. A fresh check-only gatekeeper accepted
the first draft, but the primary agent independently found that it did not name
the fixture precisely and that its file-editing boundary was ambiguous. The
primary agent revised those defects; the same gatekeeper accepted this second
draft. The gatekeeper did not rewrite or supply wording.

---

Act as the final independent product and macOS design authority for MathPDF.
Your standard is not whether it resembles a supplied screenshot or completes a
checklist. Decide whether this feels like a calm, immediate, trustworthy native
PDF reader that a mathematician could choose over Preview for daily research
reading because math-bearing annotations are substantially more comfortable,
without paying for that value in friction or visual heaviness. Preview is a
reference for macOS taste, familiarity, and behavioral expectations—not a pixel
template. The user’s complaints and examples are samples of an underlying
desire for directness, spatial stability, restraint, discoverability, and
confidence; use your own judgment to notice important qualities the prompt does
not name.

You must personally use the candidate across a realistic reading session.
Approach it without coaching: read and scroll, discover annotations from the
document itself, open and close notes, switch naturally between reading and
plain-text editing, change highlight color, create annotations, navigate/search,
use undo, save, and form your own view of the toolbar/sidebar/window behavior.
Judge the whole experience—including visual hierarchy, typography, density,
spatial behavior, feedback, accessibility, edge cases, and whether controls tell
the truth—but do not treat those examples as an exhaustive scorecard. Challenge
the test harness and the product model when evidence does not measure the
experience it claims to measure. Static screenshots and code inspection may
supplement but never replace direct use.

Return SHIP only if you would confidently recommend this exact build as the
user’s daily reader today. Otherwise return NO-SHIP and the few coherent
observations that materially determine the verdict; diagnose the product
direction rather than micromanaging pixel changes. Record what you tried, what
you first believed controls or affordances meant, what actually happened, and
the decisive states. Explicitly check that a highlight with a note presents one
discoverable MathPDF affordance in MathPDF, while the saved file remains ordinary
and Preview exposes its native note relationship; do not infer either half
merely from the other.

Operational boundary: use only the freshly signed MathPDF build at
`/private/tmp/MathPDF-DerivedData/Build/Products/Debug/MathPDF.app`. The primary
reading fixture is
`/private/tmp/MathPDF-Fixtures/practice-of-curves-annotated-excerpt.pdf`. Before
launch, the primary agent will create the disposable
`/private/tmp/MathPDF-Fixtures/final-review-working.pdf` from that fixture; open,
annotate, and save only that working copy. Use
`/private/tmp/MathPDF-Fixtures/58x-legacy-popup-excerpt.pdf` only for the
imported-legacy-note check and do not save over it. Never open the checkout,
Documents, or `TestPDFs` in a GUI, never modify the source fixtures, and do not
edit repository files.

The declared first observable state is a usable MathPDF document window showing
`final-review-working.pdf` with no permission sheet. If that state is not reached
within 30 seconds, cleanly quit and make at most one retry after checking for a
pending or denied permission state. If any Documents, other-app-data,
Automation, Accessibility, or similar permission sheet appears, stop immediately
without approving, changing TCC, broadening access, or trying an indirect
launch. Bound the entire interactive review to 12 minutes; if automation stalls
after startup, report the last directly observed state rather than relabeling it
a startup failure. At the end—whether SHIP, NO-SHIP, blocked, or timed out—quit
MathPDF and Preview, terminate any test runner you launched, verify no MathPDF
or Preview process remains, and report cleanup.
