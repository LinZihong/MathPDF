//
//  ContentView.swift
//  MathPDF
//
//  Created by Zihong Lin on 4/5/26.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var controller: ReaderDocumentController

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .task {
            controller.openLaunchDocumentIfNeeded()
        }
        .alert("Couldn't Open PDF", isPresented: errorIsPresented) {
            Button("OK", role: .cancel) {
                controller.errorMessage = nil
            }
        } message: {
            Text(controller.errorMessage ?? "Unknown error")
        }
    }

    private var sidebar: some View {
        List(selection: $controller.selectedNoteID) {
            Section("Document") {
                Button("Open PDF…") {
                    controller.openDocumentPanel()
                }

                if let documentURL = controller.documentURL {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(documentURL.lastPathComponent)
                            .font(.headline)
                        Text(documentURL.path(percentEncoded: false))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 4)
                } else {
                    Text("No PDF loaded")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Notes") {
                if controller.notes.isEmpty {
                    Text(controller.pdfDocument == nil ? "Open a PDF to inspect comments." : "This PDF has no note annotations.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(controller.notes) { note in
                        NoteListRow(note: note)
                            .tag(note.id)
                            .accessibilityIdentifier("note-row-\(note.pageIndex + 1)")
                    }
                }
            }
        }
        .accessibilityIdentifier("sidebar-list")
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItem {
                Button {
                    controller.openDocumentPanel()
                } label: {
                Label("Open PDF", systemImage: "folder")
                }
                .accessibilityIdentifier("toolbar-open-pdf")
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let pdfDocument = controller.pdfDocument {
            HSplitView {
                PDFReaderView(document: pdfDocument, focusedNote: controller.selectedNote)
                    .frame(minWidth: 500, minHeight: 500)

                NoteInspectorView(note: controller.selectedNote, noteCount: controller.notes.count)
                    .frame(minWidth: 320, idealWidth: 360)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .accessibilityIdentifier("note-inspector")
            }
        } else {
            ContentUnavailableView {
                Label("Open a PDF", systemImage: "doc.richtext")
            } description: {
                Text("Load a PDF to read it natively and inspect existing comments with math rendered for readability.")
            } actions: {
                Button("Open PDF…") {
                    controller.openDocumentPanel()
                }
            }
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { controller.errorMessage != nil },
            set: { newValue in
                if !newValue {
                    controller.errorMessage = nil
                }
            }
        )
    }
}

private struct NoteListRow: View {
    let note: AnnotationNote

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Page \(note.pageIndex + 1)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(note.contents.replacingOccurrences(of: "\n", with: " "))
                .lineLimit(3)
        }
        .padding(.vertical, 4)
    }
}

private struct NoteInspectorView: View {
    let note: AnnotationNote?
    let noteCount: Int

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let note {
                    Text("Rendered Note")
                        .font(.title2.weight(.semibold))
                        .accessibilityIdentifier("rendered-note-title")

                    Text("Page \(note.pageIndex + 1) • \(note.annotationType)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("rendered-note-metadata")

                    MathNoteView(rawText: note.contents)
                        .padding()
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityIdentifier("rendered-note-content")

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Stored Plain Text")
                            .font(.headline)
                            .accessibilityIdentifier("raw-note-title")
                        Text(note.contents)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("raw-note-content")
                    }
                } else if noteCount > 0 {
                    ContentUnavailableView {
                        Label("Select a Note", systemImage: "text.bubble")
                    } description: {
                        Text("Pick a note from the sidebar to reveal it in the PDF and render its math content.")
                    }
                } else {
                    ContentUnavailableView {
                        Label("No Notes Found", systemImage: "text.bubble")
                    } description: {
                        Text("This PDF has no supported annotation comments to inspect.")
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
