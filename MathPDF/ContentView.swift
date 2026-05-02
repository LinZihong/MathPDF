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
        .onChange(of: controller.selectedNoteID) {
            controller.activateSidebarSelection()
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
            PDFReaderView(
                document: pdfDocument,
                focusedNote: controller.selectedNote,
                onActivateAnnotation: controller.activateAnnotation(_:),
                onSaveNoteContents: controller.saveActiveNoteContents(_:),
                onCloseNote: controller.dismissActiveNote
            )
            .frame(minWidth: 760, minHeight: 500)
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

struct NoteListRow: View {
    let note: AnnotationNote

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Page \(note.pageIndex + 1)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(note.trimmedContents.isEmpty ? "Empty note" : note.contents.replacingOccurrences(of: "\n", with: " "))
                .lineLimit(3)
        }
        .padding(.vertical, 4)
    }
}
