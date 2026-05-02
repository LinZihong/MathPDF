# Current State

Last updated: 2026-05-02

Active work:
Annotation authoring and inline note popovers.

Planning workflow:
The repository has migrated from long self-contained ExecPlans to compact Work Cards. Older long plans in `docs/plans/` are historical unless marked active in the index.

Working tree:
Partial progress is committed locally for editing existing PDF notes inline and saving them back to the PDF. Push still requires a configured git remote.

What appears to work:
- Existing supported notes can open in an inline popover from the document or sidebar.
- The popover has rendered and source modes.
- Existing note edits can be saved back to the PDF.
- The rendered note view scrolls with a direct `WKWebView` SwiftUI wrapper.
- The app launch script no longer forces additional app instances, avoiding the multi-window launch problem.
- The app no longer auto-opens the first annotation when a document loads.
- Sidebar selection switches the visible popover by note identity.
- Saving a note currently creates a PDFKit `/Text` companion plus `/Popup` companion for Preview interoperability.
- Focused unit tests were added for save persistence and popup companion behavior.

What is not done:
- Creating new highlight-attached notes.
- Creating new box-style text notes.
- Matching Preview's plain yellow square exactly. Inspection of `pdfs for testing/Intro_to_AG_I_Autumn+II-Winter_2023.pdf` shows the usual Preview square is a `/Popup` annotation paired to a `/Highlight`, not the `/Text` companion currently created by MathPDF.
- Hiding the preserved Preview popup squares inside MathPDF is still under investigation.
- Final signed manual validation after finishing the writable-reader slice.

Next recommended step:
Change popup companion saving to match Preview's `/Highlight` plus `/Popup` structure, then validate in Preview and MathPDF screenshots before continuing note creation flows.
