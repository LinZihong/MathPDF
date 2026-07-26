import PDFKit
import SwiftUI

struct ReaderSidebar: View {
    @ObservedObject var controller: ReaderDocumentController
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        VStack(spacing: 0) {
            sidebarTitleMenu

            switch controller.sidebarMode {
            case .contents:
                ReaderOutlineList(controller: controller)
            case .notes:
                ReaderAnnotationList(controller: controller, undoManager: undoManager)
            }
        }
    }

    private var sidebarTitleMenu: some View {
        Menu {
            ForEach(ReaderSidebarMode.allCases) { mode in
                Button {
                    controller.sidebarMode = mode
                } label: {
                    Label(
                        mode.rawValue,
                        systemImage: mode == controller.sidebarMode
                            ? "checkmark"
                            : (mode == .contents ? "list.bullet.indent" : "highlighter")
                    )
                }
            }
        } label: {
            HStack(spacing: 7) {
                Image(
                    systemName: controller.sidebarMode == .contents
                        ? "list.bullet.indent"
                        : "highlighter"
                )
                .foregroundStyle(.secondary)
                Text(controller.sidebarMode.rawValue)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .contentShape(.rect)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .accessibilityLabel("Sidebar Content")
        .accessibilityIdentifier("sidebar-content-menu")
        .padding(.horizontal, 12)
        .frame(height: 38)
    }
}

private struct ReaderOutlineList: View {
    @ObservedObject var controller: ReaderDocumentController

    var body: some View {
        if controller.outline.isEmpty {
            ReaderSidebarEmptyState(
                title: "No Table of Contents",
                detail: "This PDF does not include an outline.",
                systemImage: "list.bullet.indent"
            )
        } else {
            List {
                OutlineGroup(controller.outline, children: \.optionalChildren) { item in
                    Button {
                        controller.selectOutline(item)
                    } label: {
                        Text(item.title)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        item.pageIndex.map { "\(item.title), page \($0 + 1)" } ?? item.title
                    )
                }
            }
            .listStyle(.sidebar)
        }
    }
}

private struct ReaderAnnotationList: View {
    @ObservedObject var controller: ReaderDocumentController
    let undoManager: UndoManager?

    var body: some View {
        if controller.notes.isEmpty {
            ReaderSidebarEmptyState(
                title: "No Highlights or Notes",
                detail: "Annotations in this PDF will appear here.",
                systemImage: "highlighter"
            )
        } else {
            List(selection: sidebarSelection) {
                ForEach(controller.notes) { note in
                    Button {
                        controller.selectNote(note)
                    } label: {
                        NoteSidebarRow(note: note)
                            .contentShape(Rectangle())
                    }
                        .buttonStyle(.plain)
                        .tag(note.id)
                        .contextMenu {
                            Button(deleteTitle(for: note), role: .destructive) {
                                controller.removeNote(note, undoManager: undoManager)
                            }
                            .disabled(!controller.document.canEdit(note.annotation))
                        }
                        .help(note.author.map { "Author: \($0)" } ?? "")
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Page \(note.pageIndex + 1), \(note.sidebarPreview)")
                        .accessibilityValue(
                            controller.selectedNoteID == note.id ? "Selected" : ""
                        )
                        .accessibilityIdentifier(
                            "note-row-\(note.pageIndex)-\(note.annotationType.lowercased())"
                        )
                }
            }
            .listStyle(.sidebar)
            .onDeleteCommand(perform: deleteSelection)
        }
    }

    private var sidebarSelection: Binding<AnnotationNote.ID?> {
        Binding(
            get: { controller.selectedNoteID },
            set: controller.selectNote(id:)
        )
    }

    private func deleteSelection() {
        guard
            let selectedNoteID = controller.selectedNoteID,
            let note = controller.notes.first(where: { $0.id == selectedNoteID })
        else { return }
        guard controller.document.canEdit(note.annotation) else { return }
        controller.removeNote(note, undoManager: undoManager)
    }

    private func deleteTitle(for note: AnnotationNote) -> String {
        note.annotationType == "Highlight" ? "Delete Highlight" : "Delete Note"
    }
}

private struct NoteSidebarRow: View {
    let note: AnnotationNote

    private var annotationColor: Color { Color(nsColor: note.color) }
    private var isHighlight: Bool { note.annotationType == "Highlight" }
    private var primaryText: String {
        if !note.trimmedSourceText.isEmpty { return note.trimmedSourceText }
        return note.trimmedContents.isEmpty ? "Empty note" : note.trimmedContents
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(annotationColor)
                .frame(width: 3)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if !isHighlight {
                        Image(systemName: "note.text")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }

                    Text(primaryText.replacingOccurrences(of: "\n", with: " "))
                        .font(.body)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text("\(note.pageIndex + 1)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                if isHighlight, !note.trimmedContents.isEmpty {
                    Label(
                        note.trimmedContents.replacingOccurrences(of: "\n", with: " "),
                        systemImage: "bubble.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 7)
    }
}

private struct ReaderSidebarEmptyState: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.callout.bold())
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private extension DocumentOutlineItem {
    var optionalChildren: [DocumentOutlineItem]? { children.isEmpty ? nil : children }
}
