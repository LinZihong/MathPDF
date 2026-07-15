import AppKit
import SwiftUI

struct NativeSearchField: NSViewRepresentable {
    @Binding var text: String
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSSearchField {
        let searchField = NSSearchField()
        searchField.placeholderString = "Search"
        searchField.sendsWholeSearchString = true
        searchField.delegate = context.coordinator
        searchField.target = context.coordinator
        searchField.action = #selector(Coordinator.submit(_:))
        searchField.setAccessibilityIdentifier("document-search")
        context.coordinator.attach(searchField)
        return searchField
    }

    func updateNSView(_ searchField: NSSearchField, context: Context) {
        context.coordinator.parent = self
        if searchField.stringValue != text {
            searchField.stringValue = text
        }
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: NativeSearchField
        private weak var searchField: NSSearchField?
        private var focusObserver: NSObjectProtocol?

        init(parent: NativeSearchField) {
            self.parent = parent
        }

        deinit {
            if let focusObserver {
                NotificationCenter.default.removeObserver(focusObserver)
            }
        }

        func attach(_ searchField: NSSearchField) {
            self.searchField = searchField
            focusObserver = NotificationCenter.default.addObserver(
                forName: .focusMathPDFSearch,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard
                    let searchField = self?.searchField,
                    searchField.window?.isKeyWindow == true
                else { return }
                searchField.window?.makeFirstResponder(searchField)
            }
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let searchField = notification.object as? NSSearchField else { return }
            parent.text = searchField.stringValue
        }

        @objc func submit(_ sender: NSSearchField) {
            parent.text = sender.stringValue
            parent.onSubmit()
        }
    }
}

extension Notification.Name {
    static let focusMathPDFSearch = Notification.Name("MathPDF.focusDocumentSearch")
}
