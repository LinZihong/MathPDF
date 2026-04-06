//
//  MathPDFTests.swift
//  MathPDFTests
//
//  Created by Zihong Lin on 4/5/26.
//

import Foundation
import PDFKit
import Testing
@testable import MathPDF

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
    func splitsFixtureNoteIntoParagraphAndDisplayMath() throws {
        let document = try #require(PDFDocument(url: fixtureURL))
        let note = try #require(PDFNoteExtractor.extractNotes(from: document).first)

        let blocks = MathNoteRenderer.blocks(from: note.contents)
        let displayRuns = blocks.compactMap { block -> [MathTextRun]? in
            guard case .displayMath(let runs) = block else {
                return nil
            }
            return runs
        }
        let paragraphFragments = blocks.compactMap { block -> [InlineNoteFragment]? in
            guard case .paragraph(let fragments) = block else {
                return nil
            }
            return fragments
        }

        #expect(displayRuns.count == 1)
        #expect(paragraphFragments.count >= 3)
        #expect(paragraphFragments.contains { fragments in
            fragments.contains { fragment in
                guard case .math(let runs) = fragment else {
                    return false
                }
                return MathNoteRenderer.plainText(from: runs) == "a"
            }
        })

        let displayPlainText = MathNoteRenderer.plainText(from: try #require(displayRuns.first))
        #expect(displayPlainText.contains("a"))
        #expect(displayPlainText.contains("b"))
        #expect(displayPlainText.contains("c"))
        #expect(displayPlainText.contains("n"))
        #expect(displayRuns[0].contains { $0.style == .superscript && $0.text == "n" })
    }

    @Test
    func buildsSuperscriptAndSubscriptMathRuns() {
        let runs = MathNoteRenderer.mathRuns(from: "a_i^n + \\alpha")

        #expect(runs == [
            MathTextRun(text: "a", style: .normal),
            MathTextRun(text: "i", style: .subscripted),
            MathTextRun(text: "n", style: .superscript),
            MathTextRun(text: " + α", style: .normal)
        ])
    }

    @Test
    func leavesMalformedInlineMathReadable() {
        let blocks = MathNoteRenderer.blocks(from: "Broken $a^n text")

        #expect(blocks == [
            .paragraph([.text("Broken $a^n text")])
        ])
    }

    private var fixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("pdfs for testing/ell_curves.pdf")
    }
}
