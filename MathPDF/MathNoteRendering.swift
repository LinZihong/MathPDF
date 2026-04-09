//
//  MathNoteRendering.swift
//  MathPDF
//
//  Created by Zihong Lin on 4/5/26.
//

import Foundation
import SwiftUI
import WebKit

struct MathRenderedDocument: Equatable {
    let html: String
    let baseURL: URL
    let experiment: MathRendererExperiment
    let enablesHeightMessages: Bool
}

enum MathNoteRendererError: LocalizedError {
    case missingAsset(String)
    case unreadableAsset(String)

    var errorDescription: String? {
        switch self {
        case .missingAsset(let name):
            return "Missing renderer asset: \(name)"
        case .unreadableAsset(let name):
            return "Couldn't read renderer asset: \(name)"
        }
    }
}

enum MathRendererExperiment: String, CaseIterable {
    case production = "production"
    case productionNoHeight = "production-no-height"
    case plainText = "plain-text"
    case inlineJavaScript = "inline-js"
    case inlineJavaScriptWithHeight = "inline-js-height"
    case katexNoFonts = "katex-no-fonts"

    var enablesHeightMessages: Bool {
        switch self {
        case .production, .inlineJavaScriptWithHeight, .katexNoFonts:
            return true
        case .productionNoHeight, .plainText, .inlineJavaScript:
            return false
        }
    }

    static func current(
        processInfo: ProcessInfo = .processInfo,
        arguments: [String]? = nil
    ) -> MathRendererExperiment {
        let arguments = arguments ?? processInfo.arguments
        if let index = arguments.firstIndex(of: "--renderer-experiment") {
            let valueIndex = arguments.index(after: index)
            if valueIndex < arguments.endIndex,
               let experiment = MathRendererExperiment(rawValue: arguments[valueIndex]) {
                return experiment
            }
        }

        guard let rawValue = processInfo.environment["MATHPDF_RENDERER_EXPERIMENT"] else {
            return .production
        }

        return MathRendererExperiment(rawValue: rawValue) ?? .production
    }
}

struct MathRendererDebugSettings {
    let experiment: MathRendererExperiment
    let diagnosticsEnabled: Bool

    static func current(processInfo: ProcessInfo = .processInfo) -> MathRendererDebugSettings {
        let arguments = processInfo.arguments

        return MathRendererDebugSettings(
            experiment: MathRendererExperiment.current(
                processInfo: processInfo,
                arguments: arguments
            ),
            diagnosticsEnabled: Self.diagnosticsEnabled(
                processInfo: processInfo,
                arguments: arguments
            )
        )
    }

    private static func diagnosticsEnabled(processInfo: ProcessInfo, arguments: [String]) -> Bool {
        if arguments.contains("--renderer-diagnostics") {
            return true
        }

        return boolEnvironmentValue(
            named: "MATHPDF_RENDERER_DIAGNOSTICS",
            processInfo: processInfo
        )
    }

    private static func boolEnvironmentValue(named name: String, processInfo: ProcessInfo) -> Bool {
        guard let value = processInfo.environment[name] else {
            return false
        }

        switch value.lowercased() {
        case "1", "true", "yes", "on":
            return true
        default:
            return false
        }
    }
}

struct MathRendererDiagnostics: Equatable {
    var experiment = MathRendererExperiment.production.rawValue
    var lastEvent = "idle"
    var renderState = ""
    var katexCount = 0
    var errorCount = 0
    var errorMessage = ""
    var textPreview = ""
    var innerHTMLLength = 0
    var fontStatus = ""
    var fontCheck = false
    var webContentTerminated = false

    var summaryText: String {
        let preview = textPreview.replacingOccurrences(of: "\n", with: "\\n")

        return """
        experiment: \(experiment)
        event: \(lastEvent)
        state: \(renderState.isEmpty ? "<empty>" : renderState)
        katexCount: \(katexCount)
        errorCount: \(errorCount)
        fontStatus: \(fontStatus.isEmpty ? "<empty>" : fontStatus)
        fontCheck: \(fontCheck)
        webContentTerminated: \(webContentTerminated)
        innerHTMLLength: \(innerHTMLLength)
        errorMessage: \(errorMessage.isEmpty ? "<empty>" : errorMessage)
        textPreview: \(preview.isEmpty ? "<empty>" : preview)
        """
    }

    static func initial(for experiment: MathRendererExperiment) -> MathRendererDiagnostics {
        MathRendererDiagnostics(experiment: experiment.rawValue)
    }
}

enum MathNoteRenderer {
    static func hasMathMarkup(in rawText: String) -> Bool {
        rawText.contains("\\[")
            || rawText.contains("\\(")
            || rawText.contains("$$")
            || hasInlineDollarMath(in: rawText)
    }

    static func renderedDocument(
        rawText: String,
        bundle: Bundle = .main,
        debugSettings: MathRendererDebugSettings = .current()
    ) throws -> MathRenderedDocument {
        guard let baseURL = bundle.resourceURL else {
            throw MathNoteRendererError.missingAsset("bundle resource directory")
        }

        return try renderedDocument(
            rawText: rawText,
            assetDirectoryURL: baseURL,
            debugSettings: debugSettings
        )
    }

    static func renderedDocument(
        rawText: String,
        assetDirectoryURL: URL,
        debugSettings: MathRendererDebugSettings = .current()
    ) throws -> MathRenderedDocument {
        let experiment = debugSettings.experiment

        let html: String
        switch experiment {
        case .plainText:
            html = plainTextHTML(rawText: rawText)
        case .inlineJavaScript:
            html = try inlineJavaScriptHTML(
                rawText: rawText,
                enableHeightMessages: false
            )
        case .inlineJavaScriptWithHeight:
            html = try inlineJavaScriptHTML(
                rawText: rawText,
                enableHeightMessages: true
            )
        case .katexNoFonts:
            html = try productionHTML(
                rawText: rawText,
                assetDirectoryURL: assetDirectoryURL,
                enableHeightMessages: true,
                includeFontFaces: false
            )
        case .production:
            html = try productionHTML(
                rawText: rawText,
                assetDirectoryURL: assetDirectoryURL,
                enableHeightMessages: true,
                includeFontFaces: true
            )
        case .productionNoHeight:
            html = try productionHTML(
                rawText: rawText,
                assetDirectoryURL: assetDirectoryURL,
                enableHeightMessages: false,
                includeFontFaces: true
            )
        }

        return MathRenderedDocument(
            html: html,
            baseURL: assetDirectoryURL,
            experiment: experiment,
            enablesHeightMessages: experiment.enablesHeightMessages
        )
    }

    private static func plainTextHTML(rawText: String) -> String {
        let escapedText = escapedHTML(rawText)

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
        \(baseStyleSheet())
          </style>
        </head>
        <body data-render-state="text" data-katex-count="0" data-error-count="0" data-error-message="">
          <div id="note-root">\(escapedText)</div>
        </body>
        </html>
        """
    }

    private static func inlineJavaScriptHTML(
        rawText: String,
        enableHeightMessages: Bool
    ) throws -> String {
        let escapedText = try jsonLiteral(for: rawText)
        let heightHook = heightMessageHook(enabled: enableHeightMessages)

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
        \(baseStyleSheet())
          </style>
        </head>
        <body data-render-state="loading" data-katex-count="0" data-error-count="0" data-error-message="">
          <div id="note-root">Booting renderer…</div>
          <script>
            const rawText = \(escapedText);
            const root = document.getElementById("note-root");
            root.textContent = "Inline JS OK: " + rawText;
            document.body.dataset.renderState = "rendered";
            \(heightHook)
          </script>
        </body>
        </html>
        """
    }

    private static func productionHTML(
        rawText: String,
        assetDirectoryURL: URL,
        enableHeightMessages: Bool,
        includeFontFaces: Bool
    ) throws -> String {
        let styleSheet = try normalizedStyleSheet(
            assetDirectoryURL: assetDirectoryURL,
            includeFontFaces: includeFontFaces
        )
        let katexScript = try assetContents(named: "katex.min.js", in: assetDirectoryURL)
        let autoRenderScript = try assetContents(named: "auto-render.min.js", in: assetDirectoryURL)
        let escapedText = try jsonLiteral(for: rawText)
        let initialFallbackHTML = escapedHTML(rawText)
        let expectedMathMarkup = hasMathMarkup(in: rawText) ? "true" : "false"
        let heightHook = heightMessageHook(enabled: enableHeightMessages)

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
        \(styleSheet)

        \(baseStyleSheet())

        .katex-display {
          margin: 0.85em 0;
          overflow-x: auto;
          overflow-y: hidden;
          padding: 0.1em 0;
        }

        .katex-error {
          color: inherit !important;
          background: transparent !important;
          border: 0 !important;
          font: inherit !important;
          white-space: pre-wrap;
        }
          </style>
          <script>
        \(katexScript)
          </script>
          <script>
        \(autoRenderScript)
          </script>
        </head>
        <body data-render-state="loading" data-katex-count="0" data-error-count="0" data-error-message="">
          <div id="note-root">\(initialFallbackHTML)</div>
          <script>
            const rawText = \(escapedText);
            const expectedMathMarkup = \(expectedMathMarkup);
            const root = document.getElementById("note-root");
            root.textContent = rawText;

            function publishState(state, errorMessage) {
              document.body.dataset.renderState = state;
              document.body.dataset.katexCount = String(document.querySelectorAll(".katex").length);
              document.body.dataset.errorCount = String(document.querySelectorAll(".katex-error").length);
              document.body.dataset.errorMessage = errorMessage || "";
              \(heightHook)
            }

            window.addEventListener("error", (event) => {
              document.body.dataset.errorMessage = String(event.error || event.message || "window.error");
            });

            window.addEventListener("unhandledrejection", (event) => {
              document.body.dataset.errorMessage = String(event.reason || "unhandledrejection");
            });

            try {
              renderMathInElement(root, {
                delimiters: [
                  {left: "$$", right: "$$", display: true},
                  {left: "\\\\[", right: "\\\\]", display: true},
                  {left: "\\\\(", right: "\\\\)", display: false},
                  {left: "$", right: "$", display: false}
                ],
                throwOnError: false,
                strict: "ignore",
                trust: false,
                errorColor: "inherit"
              });

              const katexCount = document.querySelectorAll(".katex").length;
              publishState(katexCount > 0 ? "rendered" : (expectedMathMarkup ? "raw" : "text"), "");
            } catch (error) {
              root.textContent = rawText;
              publishState("raw", String(error));
            }
          </script>
        </body>
        </html>
        """
    }

    private static func baseStyleSheet() -> String {
        """
        :root {
          color-scheme: light dark;
          font: -apple-system-body;
        }

        html, body {
          margin: 0;
          padding: 0;
          background: transparent;
        }

        body {
          color: #1f2328;
          font: 16px/1.6 -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
        }

        #note-root {
          white-space: pre-wrap;
          overflow-wrap: anywhere;
        }
        """
    }

    private static func heightMessageHook(enabled: Bool) -> String {
        guard enabled else {
            return ""
        }

        return """
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.noteHeight) {
          window.requestAnimationFrame(() => {
            const height = Math.ceil(document.documentElement.scrollHeight);
            window.webkit.messageHandlers.noteHeight.postMessage(height);
          });
        }
        """
    }

    private static func normalizedStyleSheet(
        assetDirectoryURL: URL,
        includeFontFaces: Bool
    ) throws -> String {
        let styleSheet = try assetContents(named: "katex.min.css", in: assetDirectoryURL)
            .replacingOccurrences(of: "fonts/", with: "")
            .replacingOccurrences(of: "/*# sourceMappingURL=katex.min.css.map */", with: "")

        guard !includeFontFaces else {
            return styleSheet
        }

        let expression = try NSRegularExpression(pattern: "@font-face\\{[^}]+\\}")
        let range = NSRange(styleSheet.startIndex..<styleSheet.endIndex, in: styleSheet)
        return expression.stringByReplacingMatches(in: styleSheet, range: range, withTemplate: "")
    }

    private static func assetContents(named fileName: String, in directoryURL: URL) throws -> String {
        let assetURL = directoryURL.appendingPathComponent(fileName)

        guard FileManager.default.fileExists(atPath: assetURL.path) else {
            throw MathNoteRendererError.missingAsset(fileName)
        }

        do {
            return try String(contentsOf: assetURL, encoding: .utf8)
        } catch {
            throw MathNoteRendererError.unreadableAsset(fileName)
        }
    }

    private static func jsonLiteral(for string: String) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: [string])
        guard
            let encoded = String(data: data, encoding: .utf8),
            encoded.count >= 2
        else {
            throw MathNoteRendererError.unreadableAsset("json literal")
        }

        return String(encoded.dropFirst().dropLast())
    }

    private static func escapedHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func hasInlineDollarMath(in rawText: String) -> Bool {
        var previous: Character?
        var openCount = 0

        for character in rawText {
            guard character == "$", previous != "\\" else {
                previous = character
                continue
            }

            openCount += 1
            if openCount == 2 {
                return true
            }

            previous = character
        }

        return false
    }
}

struct MathNoteView: View {
    let rawText: String

    private let debugSettings = MathRendererDebugSettings.current()

    @State private var renderedDocument: MathRenderedDocument?
    @State private var contentHeight: CGFloat = 96
    @State private var diagnostics = MathRendererDiagnostics.initial(for: .production)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                if let renderedDocument {
                    MathNoteWebView(
                        html: renderedDocument.html,
                        baseURL: renderedDocument.baseURL,
                        enablesHeightMessages: renderedDocument.enablesHeightMessages,
                        diagnostics: $diagnostics,
                        contentHeight: $contentHeight
                    )
                    .id("\(renderedDocument.experiment.rawValue)-\(renderedDocument.enablesHeightMessages)")
                    .frame(height: max(contentHeight, 96))
                } else {
                    fallbackView
                }
            }

            if debugSettings.diagnosticsEnabled {
                Text(diagnostics.summaryText)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("renderer-diagnostics")
            }
        }
        .task(id: rawText) {
            do {
                renderedDocument = try MathNoteRenderer.renderedDocument(
                    rawText: rawText,
                    debugSettings: debugSettings
                )
                if let renderedDocument {
                    diagnostics = .initial(for: renderedDocument.experiment)
                }
            } catch {
                renderedDocument = nil
                diagnostics = .initial(for: .production)
                diagnostics.lastEvent = "renderedDocument-error"
                diagnostics.errorMessage = error.localizedDescription
            }
        }
    }

    private var fallbackView: some View {
        Text(rawText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .font(.system(size: 16, weight: .regular, design: .default))
            .textSelection(.enabled)
    }
}

private struct MathNoteWebView: NSViewRepresentable {
    let html: String
    let baseURL: URL
    let enablesHeightMessages: Bool
    @Binding var diagnostics: MathRendererDiagnostics
    @Binding var contentHeight: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(diagnostics: $diagnostics, contentHeight: $contentHeight)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        if enablesHeightMessages {
            configuration.userContentController.add(context.coordinator, name: Coordinator.heightMessageName)
        }

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        webView.allowsMagnification = false
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.lastLoadedHTML != html else {
            return
        }

        context.coordinator.beginLoad(experiment: diagnostics.experiment)
        context.coordinator.lastLoadedHTML = html
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.navigationDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Coordinator.heightMessageName)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        static let heightMessageName = "noteHeight"

        @Binding var diagnostics: MathRendererDiagnostics
        @Binding var contentHeight: CGFloat
        var lastLoadedHTML: String?
        private var sampleToken = 0

        init(diagnostics: Binding<MathRendererDiagnostics>, contentHeight: Binding<CGFloat>) {
            _diagnostics = diagnostics
            _contentHeight = contentHeight
        }

        func beginLoad(experiment: String) {
            sampleToken += 1
            diagnostics = .initial(
                for: MathRendererExperiment(rawValue: experiment) ?? .production
            )
            diagnostics.lastEvent = "loading"
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard
                message.name == Self.heightMessageName,
                let number = message.body as? NSNumber
            else {
                return
            }

            contentHeight = max(CGFloat(number.doubleValue), 96)
            diagnostics.lastEvent = "height-message"
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            diagnostics.lastEvent = "didFinish"
            sampleDOM(in: webView, event: "didFinish")
            scheduleSampling(in: webView, token: sampleToken, remainingSamples: 8)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            diagnostics.lastEvent = "didFail"
            diagnostics.errorMessage = error.localizedDescription
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            diagnostics.lastEvent = "didFailProvisional"
            diagnostics.errorMessage = error.localizedDescription
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            diagnostics.lastEvent = "webContentTerminated"
            diagnostics.webContentTerminated = true
            sampleDOM(in: webView, event: "terminated")
        }

        private func scheduleSampling(in webView: WKWebView, token: Int, remainingSamples: Int) {
            guard remainingSamples > 0 else {
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self, weak webView] in
                guard
                    let self,
                    let webView,
                    self.sampleToken == token
                else {
                    return
                }

                self.sampleDOM(in: webView, event: "poll\(9 - remainingSamples)")
                self.scheduleSampling(in: webView, token: token, remainingSamples: remainingSamples - 1)
            }
        }

        private func sampleDOM(in webView: WKWebView, event: String) {
            let script = """
            (() => {
              const root = document.getElementById("note-root") || document.body;
              const fonts = document.fonts;
              return {
                renderState: document.body && document.body.dataset ? (document.body.dataset.renderState || "") : "",
                katexCount: document.body && document.body.dataset ? Number(document.body.dataset.katexCount || 0) : 0,
                errorCount: document.body && document.body.dataset ? Number(document.body.dataset.errorCount || 0) : 0,
                errorMessage: document.body && document.body.dataset ? (document.body.dataset.errorMessage || "") : "",
                innerText: root ? (root.innerText || "") : "",
                innerHTMLLength: root ? ((root.innerHTML || "").length) : 0,
                fontStatus: fonts ? (fonts.status || "") : "",
                fontCheck: fonts ? fonts.check("16px KaTeX_Main") : false
              };
            })()
            """

            webView.evaluateJavaScript(script) { [weak self] result, error in
                guard let self else {
                    return
                }

                if let error {
                    self.diagnostics.lastEvent = "\(event)-sample-error"
                    self.diagnostics.errorMessage = error.localizedDescription
                    return
                }

                guard let payload = result as? [String: Any] else {
                    self.diagnostics.lastEvent = "\(event)-sample-empty"
                    return
                }

                self.diagnostics.lastEvent = event
                self.diagnostics.renderState = payload["renderState"] as? String ?? ""
                self.diagnostics.katexCount = payload["katexCount"] as? Int ?? 0
                self.diagnostics.errorCount = payload["errorCount"] as? Int ?? 0
                self.diagnostics.errorMessage = payload["errorMessage"] as? String ?? ""
                self.diagnostics.textPreview = payload["innerText"] as? String ?? ""
                self.diagnostics.innerHTMLLength = payload["innerHTMLLength"] as? Int ?? 0
                self.diagnostics.fontStatus = payload["fontStatus"] as? String ?? ""
                self.diagnostics.fontCheck = payload["fontCheck"] as? Bool ?? false

                if let number = resultValue(payload["innerHTMLLength"]) {
                    self.diagnostics.innerHTMLLength = number
                }

                if let katexCount = resultValue(payload["katexCount"]) {
                    self.diagnostics.katexCount = katexCount
                }

                if let errorCount = resultValue(payload["errorCount"]) {
                    self.diagnostics.errorCount = errorCount
                }
            }
        }

        private func resultValue(_ value: Any?) -> Int? {
            if let value = value as? Int {
                return value
            }

            if let number = value as? NSNumber {
                return number.intValue
            }

            return nil
        }
    }
}
