import SwiftUI

struct ReaderToolbar: ToolbarContent {
    @ObservedObject var controller: ReaderDocumentController
    @Binding var pageField: String
    let onHighlight: () -> Void
    let onHighlightWithNote: () -> Void
    let onToggleTextNote: () -> Void

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button("Back", systemImage: "chevron.left", action: controller.readerProxy.goBack)
                .disabled(!controller.readerProxy.canGoBack)
                .help("Back")
                .controlSize(.large)
                .imageScale(.large)

            Button("Forward", systemImage: "chevron.right", action: controller.readerProxy.goForward)
                .disabled(!controller.readerProxy.canGoForward)
                .help("Forward")
                .controlSize(.large)
                .imageScale(.large)
        }

        ToolbarItem(placement: .automatic) {
            PagePositionControl(
                pageField: $pageField,
                pageCount: max(controller.readerProxy.pageCount, 1),
                currentPage: controller.readerProxy.pageIndex + 1,
                onSubmit: submitPage
            )
        }

        ToolbarItem(placement: .automatic) {
            HStack(spacing: 3) {
                Button("Zoom Out", systemImage: "minus.magnifyingglass", action: controller.readerProxy.zoomOut)
                    .help("Zoom Out")

                Menu {
                    Button("Actual Size", action: controller.readerProxy.actualSize)
                    Button("Fit Page", action: controller.readerProxy.fitPage)
                    Button("Fit Width", action: controller.readerProxy.fitWidth)
                } label: {
                    Text(controller.readerProxy.scaleLabel)
                        .monospacedDigit()
                        .frame(minWidth: 44)
                }
                .help("Zoom")

                Button("Zoom In", systemImage: "plus.magnifyingglass", action: controller.readerProxy.zoomIn)
                    .help("Zoom In")
            }
            .controlSize(.large)
            .imageScale(.large)
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Button("Highlight with Note", systemImage: "bubble.left.and.text.bubble.right") {
                    onHighlightWithNote()
                }
                .disabled(!controller.readerProxy.selectionAvailable)
            } label: {
                Label("Highlight", systemImage: "highlighter")
                    .foregroundStyle(controller.highlightColor.color)
            } primaryAction: {
                guard controller.readerProxy.selectionAvailable else { return }
                onHighlight()
            }
            .controlSize(.large)
            .imageScale(.large)
            .disabled(!controller.canAuthorAnnotations)
            .help(
                controller.annotationAuthoringUnavailableReason
                    ?? "Highlight Selected Text"
            )
            .accessibilityIdentifier("annotation-tools")

            Menu {
                ForEach(AnnotationColorChoice.allCases) { color in
                    Button {
                        controller.highlightColor = color
                    } label: {
                        Label(color.rawValue, systemImage: "circle.fill")
                    }
                }
            } label: {
                Label("Highlight Color", systemImage: "circle.fill")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(controller.highlightColor.color)
            }
            .controlSize(.large)
            .help("Highlight Color: \(controller.highlightColor.rawValue)")
            .accessibilityLabel("Highlight Color")
            .accessibilityValue(controller.highlightColor.rawValue)
            .accessibilityIdentifier("highlight-color-menu")
            .disabled(!controller.canAuthorAnnotations)

            Button(action: onToggleTextNote) {
                Label(
                    controller.readerTool == .textNote ? "Click PDF to Place Note" : "Place Note",
                    systemImage: controller.readerTool == .textNote
                        ? "xmark.circle.fill"
                        : "note.text.badge.plus"
                )
                .foregroundStyle(controller.readerTool == .textNote ? Color.accentColor : Color.primary)
            }
            .controlSize(.large)
            .help(controller.readerTool == .textNote ? "Cancel Note Placement" : "Place Note")
            .accessibilityValue(controller.readerTool == .textNote ? "Active" : "Inactive")
            .accessibilityIdentifier("place-note")
            .disabled(!controller.canAuthorAnnotations)
        }

        ToolbarItem(placement: .primaryAction) {
            ReaderSearchToolbar(controller: controller)
        }
    }

    private func submitPage() {
        guard let page = Int(pageField), (1...max(controller.readerProxy.pageCount, 1)).contains(page) else {
            pageField = String(controller.readerProxy.pageIndex + 1)
            return
        }
        controller.readerProxy.goToPage(page - 1)
    }
}

private struct PagePositionControl: View {
    @Binding var pageField: String
    let pageCount: Int
    let currentPage: Int
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            TextField("Page", text: $pageField)
                .textFieldStyle(.roundedBorder)
                .frame(width: 44)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .onSubmit(onSubmit)
                .accessibilityLabel("Page number")

            Text("/ \(pageCount)")
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .fixedSize()
        }
        .controlSize(.regular)
        .help("Page \(currentPage) of \(pageCount)")
    }
}

private struct ReaderSearchToolbar: View {
    @ObservedObject var controller: ReaderDocumentController

    @ViewBuilder
    var body: some View {
        if let searchStatus {
            HStack(spacing: 3) {
                Text(searchStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)

                Button("Previous Search Result", systemImage: "chevron.up", action: controller.readerProxy.findPrevious)
                    .labelStyle(.iconOnly)
                    .disabled(controller.readerProxy.searchResultCount == 0)

                Button("Next Search Result", systemImage: "chevron.down", action: controller.readerProxy.findNext)
                    .labelStyle(.iconOnly)
                    .disabled(controller.readerProxy.searchResultCount == 0)
            }
            .frame(width: 82)
        }
    }

    private var searchStatusIsCurrent: Bool {
        controller.searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(controller.readerProxy.searchQuery) == .orderedSame
    }

    private var searchStatus: String? {
        guard searchStatusIsCurrent else { return nil }
        return controller.readerProxy.searchStatus
    }
}
