import AppKit

@main
struct MathPDFTestHostMain {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = MathPDFTestHostDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.prohibited)
        application.run()
    }
}

@MainActor
final class MathPDFTestHostDelegate: NSObject, NSApplicationDelegate {
    private(set) var unexpectedDocumentEvents: [String] = []
    private(set) var documentPolicyChecks: [String] = []

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        documentPolicyChecks.append("open-untitled-denied")
        return false
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        unexpectedDocumentEvents.append("reopen")
        return false
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        unexpectedDocumentEvents.append("open-files:\(filenames.count)")
        sender.reply(toOpenOrPrint: .failure)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        unexpectedDocumentEvents.append("open-urls:\(urls.count)")
    }

    func applicationShouldRestoreApplicationState(_ app: NSApplication) -> Bool {
        documentPolicyChecks.append("restore-state-denied")
        return false
    }

    func applicationShouldSaveApplicationState(_ app: NSApplication) -> Bool {
        false
    }
}
