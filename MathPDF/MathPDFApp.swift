import AppKit
import SwiftUI

@main
struct MathPDFApp: App {
    @NSApplicationDelegateAdaptor(MathPDFAppDelegate.self) private var appDelegate

    var body: some Scene {
        DocumentGroup(newDocument: { MathPDFDocument.newDocumentForCurrentProcess() }) { configuration in
            DocumentRootView(
                document: configuration.document,
                fileURL: configuration.fileURL
            )
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
            ReaderCommands()
        }
        .defaultSize(width: 1180, height: 800)
        .windowToolbarStyle(.unified)
    }
}

private final class MathPDFAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
#if DEBUG
        guard ProcessInfo.processInfo.environment["MATHPDF_UI_FIXTURE"] == "annotated-reader" else {
            return
        }

        // A clean document-app launch may stop at the document shell without
        // instantiating a document, so DocumentRootView never exists to load
        // the deterministic in-memory fixture. Ask the real document
        // controller for a normal DocumentGroup document; this preserves the
        // shipping scene, responder chain, undo manager, autosave, and menus.
        DispatchQueue.main.async {
            let controller = NSDocumentController.shared
            guard controller.documents.isEmpty else { return }
            controller.newDocument(nil)
        }
#endif
    }
}

private struct ReaderCommands: Commands {
    @FocusedValue(\.pdfViewProxy) private var pdfViewProxy
    @FocusedValue(\.readerCommandContext) private var readerCommandContext

    var body: some Commands {
        CommandGroup(after: .saveItem) {
            Divider()
            Button("Print…") {
                pdfViewProxy?.printDocument()
            }
            .keyboardShortcut("p", modifiers: .command)
            .disabled(pdfViewProxy == nil)
        }

        CommandGroup(after: .textEditing) {
            Button("Find in PDF") {
                readerCommandContext?.focusSearch()
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(readerCommandContext == nil)
        }

        CommandMenu("Math") {
            Button("Math Macros…") {
                readerCommandContext?.togglePreambleInspector()
            }
            .keyboardShortcut("m", modifiers: [.command, .option])
            .disabled(readerCommandContext == nil)
        }
    }
}

private struct DocumentRootView: View {
    @ObservedObject var document: MathPDFDocument
    let fileURL: URL?

    @StateObject private var controller: ReaderDocumentController
    init(document: MathPDFDocument, fileURL: URL?) {
        self.document = document
        self.fileURL = fileURL
        _controller = StateObject(wrappedValue: ReaderDocumentController(document: document))
    }

    var body: some View {
        ContentView(controller: controller, fileURL: fileURL)
            .frame(minWidth: 820, minHeight: 560)
    }
}
