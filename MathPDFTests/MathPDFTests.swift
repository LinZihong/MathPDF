//
//  MathPDFTests.swift
//  MathPDFTests
//
//  Created by Zihong Lin on 4/5/26.
//

import Foundation
import PDFKit
import Testing
import WebKit
@testable import MathPDF

@Suite(.serialized)
struct MathPDFTests {

    @Test
    func extractsNonPopupNotesFromFixture() throws {
        let document = try #require(PDFDocument(url: fixtureURL))

        let notes = PDFNoteExtractor.extractNotes(from: document)
        let fermatNote = notes.first { $0.contents.contains("Fermat") }

        #expect(notes.isEmpty == false)
        #expect(notes.contains { $0.annotationType == "Highlight" })
        #expect(fermatNote?.contents.contains("$a$") == true)
        #expect(fermatNote?.contents.contains("\\[") == true)
        #expect(fermatNote?.contents.contains("a^n + b^n = c^n") == true)
        #expect(fermatNote?.contents.contains("\\]") == true)
    }

    @Test
    func generatesKaTeXHTMLContractForFixtureNote() throws {
        let document = try #require(PDFDocument(url: fixtureURL))
        let note = try #require(
            PDFNoteExtractor.extractNotes(from: document).first { $0.contents.contains("Fermat") }
        )

        let renderedDocument = try MathNoteRenderer.renderedDocument(
            rawText: note.contents,
            assetDirectoryURL: katexAssetURL
        )

        #expect(renderedDocument.baseURL == katexAssetURL)
        #expect(renderedDocument.html.contains("renderMathInElement"))
        #expect(renderedDocument.html.contains("expectedMathMarkup = true"))
        #expect(renderedDocument.html.contains("Fermat"))
        #expect(renderedDocument.html.contains("katex-error"))
    }

    @MainActor
    @Test
    func webViewRendersFixtureNoteWithKaTeX() async throws {
        let document = try #require(PDFDocument(url: fixtureURL))
        let note = try #require(
            PDFNoteExtractor.extractNotes(from: document).first { $0.contents.contains("Fermat") }
        )
        let renderedDocument = try MathNoteRenderer.renderedDocument(
            rawText: note.contents,
            assetDirectoryURL: katexAssetURL
        )

        let snapshot = try await WebRendererProbe.snapshot(of: renderedDocument)

        #expect(snapshot.renderState == "rendered")
        #expect(snapshot.katexCount > 0)
        #expect(snapshot.innerText.contains("Fermat"))
        #expect(snapshot.innerText.contains("Last Theorem"))
    }

    @MainActor
    @Test
    func renderedWebViewContentScrollsWhenClamped() async throws {
        let rawText = (1...40)
            .map { "Scrollable rendered note line \($0) with $a_\($0)$." }
            .joined(separator: "\n")
        let renderedDocument = try MathNoteRenderer.renderedDocument(
            rawText: rawText,
            assetDirectoryURL: katexAssetURL
        )

        let snapshot = try await WebRendererProbe.scrollSnapshot(of: renderedDocument)

        #expect(snapshot.scrollHeight > snapshot.clientHeight)
        #expect(snapshot.scrollTop > 0)
    }

    @MainActor
    @Test
    func leavesMalformedInlineMathReadable() async throws {
        let renderedDocument = try MathNoteRenderer.renderedDocument(
            rawText: "Broken $a^n text",
            assetDirectoryURL: katexAssetURL
        )

        let snapshot = try await WebRendererProbe.snapshot(of: renderedDocument)
        #expect(snapshot.renderState == "raw" || snapshot.renderState == "text")
        #expect(snapshot.katexCount == 0)
        #expect(snapshot.innerText.contains("Broken $a^n text"))
    }

    @Test
    func launchDocumentPathPrefersExplicitFlag() {
        let path = ReaderDocumentController.launchDocumentPath(
            arguments: ["/tmp/MathPDF", "--open-document", "~/fixture.pdf", "/tmp/ignored.pdf"],
            environment: ["MATHPDF_OPEN_DOCUMENT": "/tmp/from-env.pdf"],
            fileExists: { $0 == "/tmp/ignored.pdf" }
        )

        #expect(path == NSString(string: "~/fixture.pdf").expandingTildeInPath)
    }

    @Test
    func launchDocumentPathAcceptsExistingPositionalFile() {
        let path = ReaderDocumentController.launchDocumentPath(
            arguments: ["/tmp/MathPDF", "-NSDocumentRevisionsDebugMode", "YES", "~/fixture.pdf"],
            environment: [:],
            fileExists: { $0 == NSString(string: "~/fixture.pdf").expandingTildeInPath }
        )

        #expect(path == NSString(string: "~/fixture.pdf").expandingTildeInPath)
    }

    @MainActor
    @Test
    func openingDocumentDoesNotAutomaticallyOpenFirstNote() throws {
        let tempURL = try temporaryFixtureCopy()
        let controller = ReaderDocumentController()

        controller.openDocument(at: tempURL)

        #expect(controller.notes.isEmpty == false)
        #expect(controller.selectedNoteID == nil)
        #expect(controller.activeNote == nil)
    }

    @MainActor
    @Test
    func savesEditedNoteContentsBackToPDF() throws {
        let tempURL = try temporaryFixtureCopy()
        let controller = ReaderDocumentController()
        controller.openDocument(at: tempURL)

        let note = try #require(controller.notes.first { $0.contents.contains("Fermat") })
        controller.activateNote(note)

        let updatedText = """
        Updated math note:
        Fermat still uses $a$, $b$, and $c$.
        """
        controller.saveActiveNoteContents(updatedText)

        #expect(controller.errorMessage == nil)
        #expect(controller.selectedNote?.contents == updatedText)

        let reloadedDocument = try #require(PDFDocument(url: tempURL))
        let reloadedNote = try #require(
            PDFNoteExtractor.extractNotes(from: reloadedDocument).first { $0.contents == updatedText }
        )
        #expect(reloadedNote.contents == updatedText)
    }

    @MainActor
    @Test
    func savingHighlightSynchronizesExistingPopupCompanion() throws {
        let tempURL = try temporaryFixtureCopy()
        let controller = ReaderDocumentController()
        controller.openDocument(at: tempURL)

        let note = try #require(controller.notes.first { $0.contents.contains("Fermat") })
        controller.activateNote(note)

        let updatedText = "Popup companion sync check"
        #expect(controller.saveActiveNoteContents(updatedText))

        let reloadedDocument = try #require(PDFDocument(url: tempURL))
        let page = try #require(reloadedDocument.page(at: note.pageIndex))
        let text = try #require(page.annotations.first {
            isAnnotation($0, subtype: "Text") && $0.contents == updatedText
        })
        let popup = try #require(page.annotations.first {
            isAnnotation($0, subtype: "Popup") && $0.contents == updatedText
        })

        #expect(text.shouldDisplay)
        #expect(text.shouldPrint)
        #expect(popup.contents == updatedText)
        #expect(popup.shouldDisplay)
        try expectSerializedPreviewTextContract(in: tempURL, contents: updatedText)
        #expect(PDFNoteExtractor.extractNotes(from: reloadedDocument).filter { $0.contents == updatedText }.count == 1)
    }

    @MainActor
    @Test
    func savingHighlightCreatesPopupCompanionWhenMissing() throws {
        let tempURL = try temporaryFixtureCopy()
        let strippedDocument = try #require(PDFDocument(url: tempURL))
        let page = try #require(strippedDocument.page(at: 0))
        for annotation in page.annotations where (annotation.type ?? "").caseInsensitiveCompare("Popup") == .orderedSame {
            page.removeAnnotation(annotation)
        }
        #expect(strippedDocument.write(to: tempURL))

        let controller = ReaderDocumentController()
        controller.openDocument(at: tempURL)

        let note = try #require(controller.notes.first { $0.contents.contains("Fermat") })
        controller.activateNote(note)

        let updatedText = "Created popup companion"
        #expect(controller.saveActiveNoteContents(updatedText))

        let reloadedDocument = try #require(PDFDocument(url: tempURL))
        let reloadedPage = try #require(reloadedDocument.page(at: 0))
        let text = try #require(reloadedPage.annotations.first {
            isAnnotation($0, subtype: "Text") && $0.contents == updatedText
        })
        #expect(text.shouldDisplay)
        #expect(text.shouldPrint)
        try expectSerializedPreviewTextContract(in: tempURL, contents: updatedText)
        #expect(PDFNoteExtractor.extractNotes(from: reloadedDocument).filter { $0.contents == updatedText }.count == 1)
        #expect(
            reloadedPage.annotations
                .filter { isAnnotation($0, subtype: "Popup") || isAnnotation($0, subtype: "Text") }
                .allSatisfy(\.shouldDisplay) == true
        )
    }

    private var fixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("pdfs for testing/ell_curves.pdf")
    }

    private var katexAssetURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("MathPDF/KaTeX", isDirectory: true)
    }

    private func temporaryFixtureCopy() throws -> URL {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")
        try FileManager.default.copyItem(at: fixtureURL, to: destination)
        return destination
    }

    private func isAnnotation(_ annotation: PDFAnnotation, subtype: String) -> Bool {
        (annotation.type ?? "").caseInsensitiveCompare(subtype) == .orderedSame
    }

    private func expectSerializedPreviewTextContract(
        in url: URL,
        contents: String
    ) throws {
        let pdfText = String(decoding: try Data(contentsOf: url), as: UTF8.self)

        #expect(pdfText.contains("/Popup"))
        #expect(pdfText.contains("/Parent"))
        #expect(pdfText.contains("/Subtype"))
        #expect(pdfText.contains("/Text"))
        #expect(pdfText.contains("/F 4"))
        #expect(pdfText.contains("/Contents (\(contents))"))
    }
}

@MainActor
private enum WebRendererProbe {
    static func snapshot(of renderedDocument: MathRenderedDocument) async throws -> WebRendererSnapshot {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .init(x: 0, y: 0, width: 480, height: 320), configuration: configuration)
        let navigationDelegate = NavigationDelegate()
        webView.navigationDelegate = navigationDelegate
        webView.loadHTMLString(renderedDocument.html, baseURL: renderedDocument.baseURL)

        try await navigationDelegate.waitForFinish()

        let renderState = try await waitForRenderState(in: webView)
        let katexCount = try await webView.javaScriptInt("Number(document.body.dataset.katexCount || 0)")
        let innerText = try await webView.javaScriptString("document.body.innerText")

        return WebRendererSnapshot(
            renderState: renderState,
            katexCount: katexCount,
            innerText: innerText
        )
    }

    static func scrollSnapshot(of renderedDocument: MathRenderedDocument) async throws -> WebRendererScrollSnapshot {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .init(x: 0, y: 0, width: 320, height: 120), configuration: configuration)
        let navigationDelegate = NavigationDelegate()
        webView.navigationDelegate = navigationDelegate
        webView.loadHTMLString(renderedDocument.html, baseURL: renderedDocument.baseURL)

        try await navigationDelegate.waitForFinish()
        _ = try await waitForRenderState(in: webView)

        let scrollHeight = try await webView.javaScriptInt("document.scrollingElement.scrollHeight")
        let clientHeight = try await webView.javaScriptInt("document.scrollingElement.clientHeight")
        _ = try await webView.javaScriptValue("document.scrollingElement.scrollTo(0, 90)")
        try await Task.sleep(for: .milliseconds(100))
        let scrollTop = try await webView.javaScriptInt("Math.round(document.scrollingElement.scrollTop)")

        return WebRendererScrollSnapshot(
            scrollHeight: scrollHeight,
            clientHeight: clientHeight,
            scrollTop: scrollTop
        )
    }

    private static func waitForRenderState(in webView: WKWebView) async throws -> String {
        for _ in 0..<20 {
            let state = try await webView.javaScriptString("document.body.dataset.renderState || ''")
            if !state.isEmpty, state != "loading" {
                return state
            }

            try await Task.sleep(for: .milliseconds(100))
        }

        return try await webView.javaScriptString("document.body.dataset.renderState || ''")
    }
}

private struct WebRendererSnapshot {
    let renderState: String
    let katexCount: Int
    let innerText: String
}

private struct WebRendererScrollSnapshot {
    let scrollHeight: Int
    let clientHeight: Int
    let scrollTop: Int
}

@MainActor
private final class NavigationDelegate: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?

    func waitForFinish() async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume()
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

@MainActor
private extension WKWebView {
    func javaScriptString(_ script: String) async throws -> String {
        let value = try await javaScriptValue(script)
        return value as? String ?? ""
    }

    func javaScriptInt(_ script: String) async throws -> Int {
        let value = try await javaScriptValue(script)
        return value as? Int ?? 0
    }

    func javaScriptValue(_ script: String) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            evaluateJavaScript(script) { value, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: value)
                }
            }
        }
    }
}
