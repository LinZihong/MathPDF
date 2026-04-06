//
//  MathNoteRendering.swift
//  MathPDF
//
//  Created by Zihong Lin on 4/5/26.
//

import Foundation
import SwiftUI

enum MathTextStyle: Equatable {
    case normal
    case superscript
    case subscripted
}

struct MathTextRun: Equatable {
    let text: String
    let style: MathTextStyle
}

enum InlineNoteFragment: Equatable {
    case text(String)
    case math([MathTextRun])
}

enum NoteRenderBlock: Equatable {
    case paragraph([InlineNoteFragment])
    case displayMath([MathTextRun])
}

enum MathNoteRenderer {
    static func blocks(from rawText: String) -> [NoteRenderBlock] {
        let parser = NoteBlockParser(source: rawText)
        return parser.parse()
    }

    static func mathRuns(from source: String) -> [MathTextRun] {
        var parser = MathRunParser(source: source)
        return parser.parse()
    }

    static func plainText(from runs: [MathTextRun]) -> String {
        runs.map(\.text).joined()
    }
}

private struct NoteBlockParser {
    let source: String

    func parse() -> [NoteRenderBlock] {
        let normalized = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var blocks: [NoteRenderBlock] = []
        var fragments: [InlineNoteFragment] = []
        var buffer = ""
        var index = normalized.startIndex

        func flushBuffer() {
            guard !buffer.isEmpty else {
                return
            }
            fragments.append(.text(buffer))
            buffer.removeAll(keepingCapacity: true)
        }

        func flushParagraph() {
            flushBuffer()
            guard !fragments.isEmpty else {
                return
            }
            blocks.append(.paragraph(fragments))
            fragments.removeAll(keepingCapacity: true)
        }

        while index < normalized.endIndex {
            if normalized[index...].hasPrefix("\n\n") {
                flushParagraph()
                index = normalized.index(index, offsetBy: 2)
                while index < normalized.endIndex, normalized[index] == "\n" {
                    index = normalized.index(after: index)
                }
                continue
            }

            if normalized[index...].hasPrefix("\\["),
               let (content, nextIndex) = extractDelimitedContent(in: normalized, from: index, opening: "\\[", closing: "\\]") {
                flushParagraph()
                blocks.append(.displayMath(MathNoteRenderer.mathRuns(from: content)))
                index = nextIndex
                continue
            }

            if normalized[index...].hasPrefix("$$"),
               let (content, nextIndex) = extractDelimitedContent(in: normalized, from: index, opening: "$$", closing: "$$") {
                flushParagraph()
                blocks.append(.displayMath(MathNoteRenderer.mathRuns(from: content)))
                index = nextIndex
                continue
            }

            if normalized[index...].hasPrefix("\\("),
               let (content, nextIndex) = extractDelimitedContent(in: normalized, from: index, opening: "\\(", closing: "\\)") {
                flushBuffer()
                fragments.append(.math(MathNoteRenderer.mathRuns(from: content)))
                index = nextIndex
                continue
            }

            if normalized[index] == "$",
               let (content, nextIndex) = extractInlineDollarContent(in: normalized, from: index) {
                flushBuffer()
                fragments.append(.math(MathNoteRenderer.mathRuns(from: content)))
                index = nextIndex
                continue
            }

            if normalized[index] == "\n" {
                if buffer.last != " " {
                    buffer.append(" ")
                }
                index = normalized.index(after: index)
                continue
            }

            buffer.append(normalized[index])
            index = normalized.index(after: index)
        }

        flushParagraph()
        return blocks
    }

    private func extractDelimitedContent(
        in source: String,
        from start: String.Index,
        opening: String,
        closing: String
    ) -> (String, String.Index)? {
        let contentStart = source.index(start, offsetBy: opening.count)
        guard let closingRange = source.range(of: closing, range: contentStart..<source.endIndex) else {
            return nil
        }

        let content = String(source[contentStart..<closingRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (content, closingRange.upperBound)
    }

    private func extractInlineDollarContent(in source: String, from start: String.Index) -> (String, String.Index)? {
        var index = source.index(after: start)

        while index < source.endIndex {
            if source[index] == "$" {
                let previousIndex = source.index(before: index)
                if source[previousIndex] != "\\" {
                    let content = String(source[source.index(after: start)..<index])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    return (content, source.index(after: index))
                }
            }
            index = source.index(after: index)
        }

        return nil
    }
}

private struct MathRunParser {
    let source: String
    private let greekMap: [String: String] = [
        "alpha": "α",
        "beta": "β",
        "gamma": "γ",
        "delta": "δ",
        "epsilon": "ε",
        "theta": "θ",
        "lambda": "λ",
        "mu": "μ",
        "pi": "π",
        "sigma": "σ",
        "phi": "φ",
        "omega": "ω"
    ]

    private var index: String.Index

    init(source: String) {
        self.source = source
        self.index = source.startIndex
    }

    mutating func parse() -> [MathTextRun] {
        let runs = parseSequence(until: nil)
        return mergeRuns(runs)
    }

    private mutating func parseSequence(until terminator: Character?) -> [MathTextRun] {
        var runs: [MathTextRun] = []

        while index < source.endIndex {
            let character = source[index]

            if let terminator, character == terminator {
                index = source.index(after: index)
                break
            }

            switch character {
            case "{":
                index = source.index(after: index)
                runs.append(contentsOf: parseSequence(until: "}"))
            case "^":
                index = source.index(after: index)
                runs.append(contentsOf: styledAtom(.superscript))
            case "_":
                index = source.index(after: index)
                runs.append(contentsOf: styledAtom(.subscripted))
            case "\\":
                runs.append(contentsOf: parseCommand())
            default:
                index = source.index(after: index)
                runs.append(MathTextRun(text: String(character), style: .normal))
            }
        }

        return runs
    }

    private mutating func styledAtom(_ style: MathTextStyle) -> [MathTextRun] {
        guard index < source.endIndex else {
            return []
        }

        if source[index] == "{" {
            index = source.index(after: index)
            let groupedRuns = parseSequence(until: "}")
            return [MathTextRun(text: MathNoteRenderer.plainText(from: groupedRuns), style: style)]
        }

        if source[index] == "\\" {
            let commandRuns = parseCommand()
            return [MathTextRun(text: MathNoteRenderer.plainText(from: commandRuns), style: style)]
        }

        let character = source[index]
        index = source.index(after: index)
        return [MathTextRun(text: String(character), style: style)]
    }

    private mutating func parseCommand() -> [MathTextRun] {
        index = source.index(after: index)

        guard index < source.endIndex else {
            return [MathTextRun(text: "\\", style: .normal)]
        }

        let character = source[index]

        if character.isLetter {
            let commandStart = index
            while index < source.endIndex, source[index].isLetter {
                index = source.index(after: index)
            }

            let command = String(source[commandStart..<index])

            if let greek = greekMap[command] {
                return [MathTextRun(text: greek, style: .normal)]
            }

            switch command {
            case "frac":
                let numerator = readGroupedPlainText()
                let denominator = readGroupedPlainText()
                let combined = denominator.isEmpty ? numerator : "\(numerator)/\(denominator)"
                return [MathTextRun(text: combined, style: .normal)]
            case "text", "mathrm", "operatorname":
                let text = readGroupedPlainText()
                return [MathTextRun(text: text, style: .normal)]
            case "left", "right":
                return []
            case ",", " ", ";", "quad", "qquad":
                return [MathTextRun(text: " ", style: .normal)]
            default:
                let grouped = readGroupedPlainText()
                if grouped.isEmpty {
                    return [MathTextRun(text: command, style: .normal)]
                }
                return [MathTextRun(text: grouped, style: .normal)]
            }
        }

        index = source.index(after: index)
        return [MathTextRun(text: String(character), style: .normal)]
    }

    private mutating func readGroupedPlainText() -> String {
        guard index < source.endIndex, source[index] == "{" else {
            return ""
        }

        index = source.index(after: index)
        let groupedRuns = parseSequence(until: "}")
        return MathNoteRenderer.plainText(from: groupedRuns)
    }

    private func mergeRuns(_ runs: [MathTextRun]) -> [MathTextRun] {
        var merged: [MathTextRun] = []

        for run in runs where !run.text.isEmpty {
            if let last = merged.last, last.style == run.style {
                merged[merged.count - 1] = MathTextRun(text: last.text + run.text, style: last.style)
            } else {
                merged.append(run)
            }
        }

        return merged
    }
}

struct MathNoteView: View {
    let rawText: String

    var body: some View {
        let blocks = MathNoteRenderer.blocks(from: rawText)

        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let fragments):
                    paragraphText(from: fragments)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .displayMath(let runs):
                    HStack {
                        Spacer(minLength: 0)
                        mathText(from: runs, baseSize: 22)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private func paragraphText(from fragments: [InlineNoteFragment]) -> Text {
        fragments.reduce(Text("")) { partial, fragment in
            partial + inlineText(for: fragment)
        }
    }

    private func inlineText(for fragment: InlineNoteFragment) -> Text {
        switch fragment {
        case .text(let text):
            return Text(verbatim: text)
        case .math(let runs):
            return mathText(from: runs, baseSize: 18)
        }
    }

    private func mathText(from runs: [MathTextRun], baseSize: CGFloat) -> Text {
        runs.reduce(Text("")) { partial, run in
            partial + styledText(for: run, baseSize: baseSize)
        }
    }

    private func styledText(for run: MathTextRun, baseSize: CGFloat) -> Text {
        let fontSize: CGFloat
        let baselineOffset: CGFloat

        switch run.style {
        case .normal:
            fontSize = baseSize
            baselineOffset = 0
        case .superscript:
            fontSize = baseSize * 0.72
            baselineOffset = baseSize * 0.35
        case .subscripted:
            fontSize = baseSize * 0.72
            baselineOffset = -baseSize * 0.18
        }

        return Text(verbatim: run.text)
            .font(.system(size: fontSize, weight: .regular, design: .serif))
            .baselineOffset(baselineOffset)
    }
}
