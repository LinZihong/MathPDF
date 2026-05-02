//
//  MathPDFApp.swift
//  MathPDF
//
//  Created by Zihong Lin on 4/5/26.
//

import AppKit
import SwiftUI

@main
struct MathPDFApp: App {
    @StateObject private var controller = ReaderDocumentController()
    @State private var didApplyInitialWindowSize = false

    var body: some Scene {
        Window("MathPDF", id: "main") {
            ContentView(controller: controller)
                .onAppear {
                    applyInitialWindowSizeIfNeeded()
                }
                .onOpenURL { url in
                    guard url.isFileURL else {
                        return
                    }

                    controller.openDocument(at: url)
                }
        }
        .defaultSize(width: 1200, height: 820)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open PDF…") {
                    controller.openDocumentPanel()
                }
                .keyboardShortcut("o")
            }
        }
    }

    private func applyInitialWindowSizeIfNeeded() {
        guard !didApplyInitialWindowSize else {
            return
        }

        didApplyInitialWindowSize = true
        DispatchQueue.main.async {
            let preferredSize = NSSize(width: 1200, height: 820)
            guard let window = NSApplication.shared.windows.first(where: \.isVisible) else {
                return
            }

            window.minSize = NSSize(width: 900, height: 650)

            guard window.frame.width < 1100 || window.frame.height < 760 else {
                return
            }

            var frame = window.frame
            frame.origin.y += frame.height - preferredSize.height
            frame.size = preferredSize
            window.setFrame(frame, display: true, animate: false)
        }
    }
}
