import AppKit
import SwiftUI

@main
struct MathPDFApp: App {
    @NSApplicationDelegateAdaptor(MathPDFAppDelegate.self) private var appDelegate

    var body: some Scene {
        DocumentGroup(newDocument: { MathPDFDocument() }) { configuration in
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

#if DEBUG
private final class MathPDFAppDelegate: NSObject, NSApplicationDelegate {
    private var uiTestWindow: NSWindow?
    private var uiTestDocument: MathPDFDocument?

    func applicationWillFinishLaunching(_ notification: Notification) {
        guard isRunningUITest else { return }
        NSApp.setActivationPolicy(.regular)

        let document = MathPDFDocument()
        let rootView = DocumentRootView(document: document, fileURL: nil)
        let window = NSWindow(contentViewController: NSHostingController(rootView: rootView))
        window.title = "MathPDF UI Fixture"
        window.setContentSize(NSSize(width: 1180, height: 800))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.toolbarStyle = .unified
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()

        uiTestDocument = document
        uiTestWindow = window
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard isRunningUITest, let uiTestWindow else { return }
        NSApp.windows.compactMap { $0 as? NSOpenPanel }.forEach { $0.orderOut(nil) }
        NSApp.activate()
        uiTestWindow.makeKeyAndOrderFront(nil)
    }

    private var isRunningUITest: Bool {
        ProcessInfo.processInfo.environment["MATHPDF_UI_FIXTURE"] == "annotated-reader"
    }
}
#else
private final class MathPDFAppDelegate: NSObject, NSApplicationDelegate { }
#endif

private struct ReaderCommands: Commands {
    @FocusedValue(\.pdfViewProxy) private var pdfViewProxy

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
                NotificationCenter.default.post(name: .focusMathPDFSearch, object: nil)
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(pdfViewProxy == nil)
        }
    }
}

private struct DocumentRootView: View {
    @ObservedObject var document: MathPDFDocument
    let fileURL: URL?

    @StateObject private var controller: ReaderDocumentController
    @State private var didLoadUITestFixture = false

    init(document: MathPDFDocument, fileURL: URL?) {
        self.document = document
        self.fileURL = fileURL
        _controller = StateObject(wrappedValue: ReaderDocumentController(document: document))
    }

    var body: some View {
        ContentView(controller: controller, fileURL: fileURL)
            .frame(minWidth: 820, minHeight: 560)
            .task {
#if DEBUG
                guard !didLoadUITestFixture else { return }
                didLoadUITestFixture = true
                document.loadUITestFixtureIfRequested()
#endif
            }
    }
}
