import Combine
import PDFKit
import SwiftUI

struct AnnotationNoteCapabilities: Equatable {
    let canEditContents: Bool
    let canDelete: Bool
    let canChangeColor: Bool
    let editingUnavailableReason: String?
    let colorUnavailableReason: String?
}

@MainActor
final class AnnotationNoteEditingSession: ObservableObject {
    @Published private(set) var draft: String
    @Published private(set) var isEditing: Bool
    @Published private(set) var selectedColor: AnnotationColorChoice?
    @Published private(set) var surfaceColor: NSColor

    private var transactionBaseline: String?
    private let onLiveUpdate: (String) -> Bool
    private let onCommit: (String) -> Void
    private let onEditingChanged: (Bool) -> Void

    init(
        contents: String,
        color: NSColor,
        startsEditing: Bool,
        onLiveUpdate: @escaping (String) -> Bool,
        onCommit: @escaping (String) -> Void,
        onEditingChanged: @escaping (Bool) -> Void
    ) {
        draft = contents
        isEditing = startsEditing
        selectedColor = AnnotationColorChoice.matching(color)
        surfaceColor = color
        transactionBaseline = startsEditing ? contents : nil
        self.onLiveUpdate = onLiveUpdate
        self.onCommit = onCommit
        self.onEditingChanged = onEditingChanged
    }

    func replaceDraft(with contents: String) {
        guard contents != draft, onLiveUpdate(contents) else { return }
        draft = contents
    }

    func acceptColorChange(_ color: AnnotationColorChoice) {
        selectedColor = color
        surfaceColor = color.nsColor
    }

    /// Undo and other document-side mutations are authoritative while the
    /// surface remains open. Rebase an active edit transaction so finishing
    /// the edit cannot replay a stale pre-Undo baseline.
    func reconcileDocumentState(contents: String, color: NSColor) {
        if draft != contents {
            draft = contents
        }
        if isEditing {
            transactionBaseline = contents
        }
        let matchedColor = AnnotationColorChoice.matching(color)
        if selectedColor != matchedColor {
            selectedColor = matchedColor
        }
        if surfaceColor != color {
            surfaceColor = color
        }
    }

    func beginEditing() {
        guard !isEditing else { return }
        transactionBaseline = draft
        isEditing = true
        onEditingChanged(true)
    }

    func finishEditing() {
        guard isEditing else { return }
        commitIfNeeded()
        isEditing = false
        onEditingChanged(false)
    }

    func commitIfNeeded() {
        guard let transactionBaseline else { return }
        if transactionBaseline != draft {
            onCommit(transactionBaseline)
        }
        self.transactionBaseline = nil
    }
}

struct AnnotationNoteSurface: View {
    let note: AnnotationNote
    let preamble: String
    let capabilities: AnnotationNoteCapabilities
    @ObservedObject var editingSession: AnnotationNoteEditingSession
    let onDelete: () -> Void
    let onColorChange: (AnnotationColorChoice) -> Bool
    let onClose: () -> Void
    let onReveal: () -> Void

    @FocusState private var editorFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .background(.regularMaterial, in: .rect(cornerRadius: 12))
        .clipShape(.rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.72), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.12), radius: 9, y: 3)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Note on page \(note.pageIndex + 1)")
        .accessibilityIdentifier("annotation-note-surface")
        .onAppear {
            if editingSession.isEditing { editorFocused = true }
        }
        .onChange(of: editingSession.isEditing) { _, isEditing in
            editorFocused = isEditing
        }
        .onExitCommand(perform: close)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(nsColor: editingSession.surfaceColor))
                .frame(width: 9, height: 9)
                .overlay(Circle().stroke(.white.opacity(0.75), lineWidth: 1))
                .accessibilityHidden(true)

            Text(note.annotationType == "Highlight" ? "Highlight Note" : "Note")
                .font(.headline)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            Button("Page \(note.pageIndex + 1)", action: onReveal)
                .buttonStyle(.plain)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .accessibilityLabel("Return to page \(note.pageIndex + 1)")
                .help("Return to Page \(note.pageIndex + 1)")

            Spacer(minLength: 8)

            noteActionsMenu

            Button("Close Note", systemImage: "xmark", action: close)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .frame(width: 28, height: 28)
                .help("Close Note")
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(Color(nsColor: editingSession.surfaceColor).opacity(0.06))
    }

    private var noteActionsMenu: some View {
        Menu {
            if note.annotationType == "Highlight" {
                Section("Highlight Color") {
                    ForEach(AnnotationColorChoice.allCases) { color in
                        Button {
                            changeColor(to: color)
                        } label: {
                            Label(
                                color.rawValue,
                                systemImage: editingSession.selectedColor == color
                                    ? "checkmark.circle.fill"
                                    : "circle.fill"
                            )
                        }
                        .disabled(!capabilities.canChangeColor)
                        .accessibilityIdentifier("note-color-\(color.rawValue.lowercased())")
                    }
                }
            }

            Divider()

            Button(deleteTitle, systemImage: "trash", role: .destructive, action: onDelete)
                .disabled(!capabilities.canDelete)
        } label: {
            Label("Note Actions", systemImage: "ellipsis")
                .labelStyle(.iconOnly)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 28, height: 28)
        .help("Note Actions")
        .accessibilityLabel("Note Actions")
        .accessibilityValue(editingSession.selectedColor?.rawValue ?? "Custom")
        .accessibilityIdentifier("note-actions")
    }

    @ViewBuilder
    private var content: some View {
        if editingSession.isEditing {
            TextEditor(text: Binding(
                get: { editingSession.draft },
                set: editingSession.replaceDraft(with:)
            ))
            .font(.body.monospaced())
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
            .padding(10)
            .focused($editorFocused)
            .accessibilityIdentifier("note-editor")
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                MathNoteView(
                    rawText: editingSession.draft,
                    preamble: preamble,
                    minimumContentHeight: 32,
                    maximumContentHeight: 280
                )
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("note-rendered-content")
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Spacer()

            if editingSession.isEditing {
                Button("Done", action: finishEditing)
                    .keyboardShortcut(.return, modifiers: .command)
                    .accessibilityIdentifier("note-done")
            } else if capabilities.canEditContents {
                Button(editButtonTitle, action: beginEditing)
                    .accessibilityIdentifier("note-edit")
            } else {
                Label("Read Only", systemImage: "lock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(capabilities.editingUnavailableReason ?? "This annotation is read only.")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.16))
    }

    private func changeColor(to color: AnnotationColorChoice) {
        guard onColorChange(color) else { return }
        editingSession.acceptColorChange(color)
    }

    private func beginEditing() {
        guard capabilities.canEditContents else { return }
        editingSession.beginEditing()
    }

    private func finishEditing() {
        editingSession.finishEditing()
    }

    private func close() {
        editingSession.commitIfNeeded()
        onClose()
    }

    private var deleteTitle: String {
        note.annotationType == "Highlight" ? "Delete Highlight" : "Delete Note"
    }

    private var editButtonTitle: String {
        editingSession.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Add Note"
            : "Edit"
    }
}
