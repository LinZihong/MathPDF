import AppKit
import PDFKit
import Testing
@testable import MathPDF

@Suite("Annotation color palette")
struct AnnotationColorPaletteTests {
    @Test("Named choices use the macOS-authored PDF colors in the supplied corpus")
    func namedChoicesMatchObservedMacOSColors() throws {
        let expected: [(AnnotationColorChoice, (CGFloat, CGFloat, CGFloat))] = [
            (.yellow, (250 / 255, 205 / 255, 90 / 255)),
            (.green, (124 / 255, 200 / 255, 104 / 255)),
            (.blue, (105 / 255, 176 / 255, 241 / 255)),
            (.pink, (251 / 255, 92 / 255, 137 / 255)),
            (.purple, (200 / 255, 133 / 255, 218 / 255)),
        ]

        for (choice, components) in expected {
            let color = try #require(choice.nsColor.usingColorSpace(.deviceRGB))
            #expect(abs(color.redComponent - components.0) < 0.000_001)
            #expect(abs(color.greenComponent - components.1) < 0.000_001)
            #expect(abs(color.blueComponent - components.2) < 0.000_001)
            #expect(AnnotationColorChoice.matching(color) == choice)
        }
    }

    @Test("An arbitrary imported PDF color is not falsely reported as a named choice")
    func arbitraryImportedColorHasNoSelectedChoice() {
        let imported = NSColor(calibratedRed: 0.24, green: 0.63, blue: 0.48, alpha: 1)
        #expect(AnnotationColorChoice.matching(imported) == nil)
    }

#if DEBUG
    @Test("A named color survives the production PDF writer and PDFKit color conversion")
    func serializedFixtureColorStillMatchesItsNamedChoice() throws {
        let document = try MathPDFDocument(data: MathPDFDocument.uiTestFixtureData())
        let page = try #require(document.pdfDocument.page(at: 1))
        let highlight = try #require(page.annotations.first { $0.type == "Highlight" })
        #expect(AnnotationColorChoice.matching(highlight.color) == .yellow)
    }
#endif
}
