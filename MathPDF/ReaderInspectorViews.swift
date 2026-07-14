import SwiftUI

struct NoteInspectorView: View {
    let note: AnnotationNote
    let preamble: String
    let onUpdate: (String) -> Void
    let onDelete: () -> Void
    let onClose: () -> Void

    @State private var draft: String
    @State private var isEditing: Bool
    @FocusState private var editorFocused: Bool

    init(
        note: AnnotationNote,
        preamble: String,
        startsEditing: Bool = false,
        onUpdate: @escaping (String) -> Void,
        onDelete: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.note = note
        self.preamble = preamble
        self.onUpdate = onUpdate
        self.onDelete = onDelete
        self.onClose = onClose
        _draft = State(initialValue: note.contents)
        _isEditing = State(initialValue: startsEditing)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Note")
                        .font(.headline)
                    Text("Page \(note.pageIndex + 1)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    commitDraft()
                    onClose()
                } label: {
                    Label("Close Inspector", systemImage: "xmark")
                }
                .buttonStyle(.plain)
                .help("Close Inspector")
            }
            .padding(14)

            Divider()

            if isEditing {
                TextEditor(text: $draft)
                    .font(.body.monospaced())
                    .focused($editorFocused)
                    .padding(10)
                    .accessibilityIdentifier("note-editor")
                    .onAppear { editorFocused = true }
                    .onSubmit { endEditing() }
            } else {
                ScrollView {
                    MathNoteView(rawText: draft, preamble: preamble)
                        .padding(14)
                }
            }

            Divider()

            HStack {
                Button("Delete Note", role: .destructive) {
                    onDelete()
                    onClose()
                }
                .keyboardShortcut(.delete, modifiers: [.command])

                Text("Stored as plain text in this PDF")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if isEditing {
                    Button("Done", action: endEditing)
                        .keyboardShortcut(.return, modifiers: [.command])
                } else {
                    Button("Edit") {
                        isEditing = true
                        editorFocused = true
                    }
                }
            }
            .padding(12)
        }
        .onChange(of: note.id) {
            commitDraft()
            draft = note.contents
        }
        .onDisappear(perform: commitDraft)
    }

    private func endEditing() {
        commitDraft()
        isEditing = false
        editorFocused = false
    }

    private func commitDraft() {
        guard draft != note.contents else { return }
        onUpdate(draft)
    }
}

struct PreambleInspectorView: View {
    @ObservedObject var document: MathPDFDocument

    var body: some View {
        let compilation = MathPreambleCompiler.compile(document.preamble)
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Math Macros")
                    .font(.headline)
                Text("Stored in this PDF")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(14)

            Divider()

            TextEditor(text: $document.preamble)
                .font(.body.monospaced())
                .padding(10)
                .accessibilityIdentifier("preamble-editor")

            Divider()

            Text("Supports simple \\newcommand definitions and \\DeclareMathOperator. Other document preamble lines are preserved but ignored while rendering notes.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(12)

            Text(compilation.statusText)
                .font(.caption)
                .foregroundStyle(compilation.invalidLineNumbers.isEmpty ? Color.secondary : Color.orange)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
    }
}
