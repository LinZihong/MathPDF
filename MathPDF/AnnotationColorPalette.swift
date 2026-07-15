import AppKit
import SwiftUI

enum AnnotationColorChoice: String, CaseIterable, Identifiable {
    case yellow = "Yellow"
    case green = "Green"
    case blue = "Blue"
    case pink = "Pink"
    case purple = "Purple"

    var id: String { rawValue }

    var nsColor: NSColor {
        switch self {
        case .yellow:
            NSColor(deviceRed: 250 / 255, green: 205 / 255, blue: 90 / 255, alpha: 1)
        case .green:
            NSColor(deviceRed: 124 / 255, green: 200 / 255, blue: 104 / 255, alpha: 1)
        case .blue:
            NSColor(deviceRed: 105 / 255, green: 176 / 255, blue: 241 / 255, alpha: 1)
        case .pink:
            NSColor(deviceRed: 251 / 255, green: 92 / 255, blue: 137 / 255, alpha: 1)
        case .purple:
            NSColor(deviceRed: 200 / 255, green: 133 / 255, blue: 218 / 255, alpha: 1)
        }
    }

    var color: Color { Color(nsColor: nsColor) }

    var shortLabel: String {
        switch self {
        case .yellow: "Y"
        case .green: "G"
        case .blue: "B"
        case .pink: "Pk"
        case .purple: "Pu"
        }
    }

    static func nearest(to color: NSColor) -> AnnotationColorChoice {
        guard let target = color.usingColorSpace(.deviceRGB) else { return .yellow }
        return allCases.min { lhs, rhs in
            distance(from: lhs.nsColor, to: target) < distance(from: rhs.nsColor, to: target)
        } ?? .yellow
    }

    static func matching(_ color: NSColor) -> AnnotationColorChoice? {
        guard let target = color.usingColorSpace(.deviceRGB) else { return nil }
        return allCases.first {
            // PDF `/C` values have no ICC profile. PDFKit may surface the same
            // authored components through a calibrated space, whose device-RGB
            // conversion is visibly identical but not numerically exact.
            distance(from: $0.nsColor, to: target) <= 0.01
        }
    }

    private static func distance(from lhs: NSColor, to rhs: NSColor) -> CGFloat {
        guard
            let lhs = lhs.usingColorSpace(.deviceRGB),
            let rhs = rhs.usingColorSpace(.deviceRGB)
        else { return .greatestFiniteMagnitude }
        let red = lhs.redComponent - rhs.redComponent
        let green = lhs.greenComponent - rhs.greenComponent
        let blue = lhs.blueComponent - rhs.blueComponent
        return red * red + green * green + blue * blue
    }
}
