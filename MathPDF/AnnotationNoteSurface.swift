import AppKit
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
    private let onCommit: (String, String) -> Bool
    private let onDraftPendingChanged: (_ isPending: Bool, _ committed: Bool) -> Void
    private let onEditingChanged: (Bool) -> Void

    init(
        contents: String,
        color: NSColor,
        startsEditing: Bool,
        onCommit: @escaping (String, String) -> Bool,
        onDraftPendingChanged: @escaping (_ isPending: Bool, _ committed: Bool) -> Void,
        onEditingChanged: @escaping (Bool) -> Void
    ) {
        draft = contents
        isEditing = startsEditing
        selectedColor = AnnotationColorChoice.matching(color)
        surfaceColor = color
        transactionBaseline = startsEditing ? contents : nil
        self.onCommit = onCommit
        self.onDraftPendingChanged = onDraftPendingChanged
        self.onEditingChanged = onEditingChanged
    }

    func replaceDraft(with contents: String) {
        guard contents != draft else { return }
        let wasPending = hasPendingDraft
        draft = contents
        if hasPendingDraft != wasPending {
            onDraftPendingChanged(hasPendingDraft, false)
        }
    }

    func acceptColorChange(_ color: AnnotationColorChoice) {
        selectedColor = color
        surfaceColor = color.nsColor
    }

    /// Keep a local draft intact across unrelated presentation refreshes. If
    /// the model itself changed while a draft is pending, rebase the eventual
    /// commit on that new model value rather than silently discarding typing.
    func reconcileDocumentState(contents: String, color: NSColor) {
        let wasPending = hasPendingDraft
        if isEditing {
            if !wasPending, draft != contents {
                draft = contents
            }
            transactionBaseline = contents
        } else if draft != contents {
            draft = contents
        }
        if hasPendingDraft != wasPending {
            onDraftPendingChanged(hasPendingDraft, false)
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
        guard commitIfNeeded(continuingEditing: false) else { return }
        isEditing = false
        onEditingChanged(false)
    }

    @discardableResult
    func commitIfNeeded(continuingEditing: Bool = false) -> Bool {
        guard let transactionBaseline else { return true }
        let wasPending = transactionBaseline != draft
        if wasPending {
            onDraftPendingChanged(false, false)
            guard onCommit(transactionBaseline, draft) else {
                onDraftPendingChanged(true, false)
                return false
            }
        }
        self.transactionBaseline = continuingEditing && isEditing ? draft : nil
        return true
    }

    func discardPendingChanges() {
        let wasPending = hasPendingDraft
        if let transactionBaseline {
            draft = transactionBaseline
        }
        transactionBaseline = nil
        isEditing = false
        if wasPending {
            onDraftPendingChanged(false, false)
        }
        onEditingChanged(false)
    }

    private var hasPendingDraft: Bool {
        guard let transactionBaseline else { return false }
        return draft != transactionBaseline
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
        .background {
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                Color(nsColor: editingSession.surfaceColor).opacity(0.10)
            }
        }
        .clipShape(.rect(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(
                    Color(nsColor: editingSession.surfaceColor).opacity(0.72),
                    lineWidth: 0.8
                )
        }
        .shadow(color: .black.opacity(0.10), radius: 7, y: 2)
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

            Text("Note")
                .font(.subheadline.weight(.semibold))
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

        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(Color(nsColor: editingSession.surfaceColor).opacity(0.05))
    }

    private var noteActionsMenu: some View {
        Menu {
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
        .accessibilityIdentifier("note-actions")
    }

    @ViewBuilder
    private var content: some View {
        if editingSession.isEditing {
            IsolatedUndoTextEditor(
                text: Binding(
                    get: { editingSession.draft },
                    set: editingSession.replaceDraft(with:)
                ),
                isFocused: Binding(
                    get: { editorFocused },
                    set: { editorFocused = $0 }
                )
            )
            .padding(10)
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
            if note.annotationType == "Highlight" {
                colorPalette
            }

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

            Button("Close", action: close)
                .accessibilityLabel("Close Note")
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(Color(nsColor: editingSession.surfaceColor).opacity(0.04))
    }

    private var colorPalette: some View {
        HStack(spacing: 7) {
            ForEach(AnnotationColorChoice.allCases) { color in
                Button {
                    changeColor(to: color)
                } label: {
                    Circle()
                        .fill(color.color)
                        .frame(width: 16, height: 16)
                        .padding(3)
                        .overlay {
                            Circle()
                                .strokeBorder(
                                    editingSession.selectedColor == color
                                        ? Color.primary.opacity(0.72)
                                        : Color.clear,
                                    lineWidth: 1.5
                                )
                        }
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .disabled(!capabilities.canChangeColor)
                .help(color.rawValue)
                .accessibilityLabel(color.rawValue)
                .accessibilityValue(
                    editingSession.selectedColor == color ? "Selected" : ""
                )
                .accessibilityIdentifier("note-color-\(color.rawValue.lowercased())")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Highlight Color")
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

/// An annotation draft is an editor transaction, not a sequence of persistent
/// document mutations. Giving the native text view its own undo manager keeps
/// ordinary typing undo local while the document undo manager receives the
/// single committed annotation mutation.
private struct IsolatedUndoTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: $isFocused)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true

        let textView = IsolatedUndoTextView()
        textView.delegate = context.coordinator
        textView.string = text
        textView.font = .monospacedSystemFont(
            ofSize: NSFont.systemFontSize,
            weight: .regular
        )
        textView.textColor = .labelColor
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.importsGraphics = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 3, height: 4)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.setAccessibilityIdentifier("note-editor")
        scrollView.documentView = textView
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.text = $text
        context.coordinator.isFocused = $isFocused
        guard let textView = scrollView.documentView as? IsolatedUndoTextView else { return }

        if textView.string != text {
            context.coordinator.isUpdatingProgrammatically = true
            textView.string = text
            textView.isolatedUndoManager.removeAllActions()
            context.coordinator.isUpdatingProgrammatically = false
        }

        if isFocused, textView.window?.firstResponder !== textView {
            DispatchQueue.main.async { [weak textView] in
                guard let textView else { return }
                textView.window?.makeFirstResponder(textView)
            }
        }
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        (scrollView.documentView as? NSTextView)?.delegate = nil
        coordinator.textView = nil
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var isFocused: Binding<Bool>
        weak var textView: NSTextView?
        var isUpdatingProgrammatically = false

        init(text: Binding<String>, isFocused: Binding<Bool>) {
            self.text = text
            self.isFocused = isFocused
        }

        func textDidBeginEditing(_ notification: Notification) {
            isFocused.wrappedValue = true
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdatingProgrammatically,
                  let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }

        func textDidEndEditing(_ notification: Notification) {
            isFocused.wrappedValue = false
        }
    }
}

private final class IsolatedUndoTextView: NSTextView {
    let isolatedUndoManager = UndoManager()

    override var undoManager: UndoManager? {
        isolatedUndoManager
    }

    @IBAction func undo(_ sender: Any?) {
        isolatedUndoManager.undo()
    }

    @IBAction func redo(_ sender: Any?) {
        isolatedUndoManager.redo()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([
            .command, .shift, .option, .control
        ])
        guard window?.firstResponder === self,
              event.charactersIgnoringModifiers?.lowercased() == "z" else {
            return super.performKeyEquivalent(with: event)
        }

        if modifiers == [.command] {
            isolatedUndoManager.undo()
            return true
        }
        if modifiers == [.command, .shift] {
            isolatedUndoManager.redo()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
