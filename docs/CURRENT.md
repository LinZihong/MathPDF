# Current State

Last updated: 2026-05-02

Active work:
Annotation authoring and inline note popovers.

Planning workflow:
The repository has migrated from long self-contained ExecPlans to compact Work Cards. Older long plans in `docs/plans/` are historical unless marked active in the index.

Working tree:
There are uncommitted changes for editing existing PDF notes inline and saving them back to the PDF.

What appears to work:
- Existing supported notes can open in an inline popover from the document or sidebar.
- The popover has rendered and source modes.
- Existing note edits can be saved back to the PDF.
- Preview popup companions are preserved on write and hidden inside MathPDF.
- Focused unit tests were added for save persistence and popup companion behavior.

What is not done:
- Creating new highlight-attached notes.
- Creating new box-style text notes.
- Final signed manual validation after finishing the writable-reader slice.

Next recommended step:
Decide whether to commit the existing-note editing slice first or finish note creation flows before committing.
