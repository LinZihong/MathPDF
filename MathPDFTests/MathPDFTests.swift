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

        #expect(notes.count == 1)
        #expect(notes.first?.annotationType == "Highlight")
        #expect(notes.first?.contents.contains("$a$") == true)
        #expect(notes.first?.contents.contains("\\[") == true)
        #expect(notes.first?.contents.contains("a^n + b^n = c^n") == true)
        #expect(notes.first?.contents.contains("\\]") == true)
    }

    @Test
    func generatesKaTeXHTMLContractForFixtureNote() throws {
        let document = try #require(PDFDocument(url: fixtureURL))
        let note = try #require(PDFNoteExtractor.extractNotes(from: document).first)

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
        let note = try #require(PDFNoteExtractor.extractNotes(from: document).first)
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
