//
//  MathPDFApp.swift
//  MathPDF
//
//  Created by Zihong Lin on 4/5/26.
//

import SwiftUI

@main
struct MathPDFApp: App {
    @StateObject private var controller = ReaderDocumentController()

    var body: some Scene {
        WindowGroup {
            ContentView(controller: controller)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open PDF…") {
                    controller.openDocumentPanel()
                }
                .keyboardShortcut("o")
            }
        }
    }
}
