import Foundation

struct MathPreambleCompilation: Equatable {
    let macros: [String: String]
    let ignoredLineNumbers: [Int]
    let invalidLineNumbers: [Int]

    var statusText: String {
        if !invalidLineNumbers.isEmpty {
            return "Could not read supported macro syntax on line\(invalidLineNumbers.count == 1 ? "" : "s") \(invalidLineNumbers.map(String.init).joined(separator: ", "))."
        }
        if macros.isEmpty {
            return "No supported math macros found."
        }
        return "\(macros.count) math macro\(macros.count == 1 ? "" : "s") available to this PDF."
    }
}

enum MathPreambleCompiler {
    private static let commandExpression = try! NSRegularExpression(
        pattern: #"^\\(?:newcommand|renewcommand)\{(\\[A-Za-z]+)\}(?:\[(\d+)\])?\{(.+)\}\s*$"#
    )
    private static let operatorExpression = try! NSRegularExpression(
        pattern: #"^\\DeclareMathOperator\*?\{(\\[A-Za-z]+)\}\{(.+)\}\s*$"#
    )

    static func compile(_ source: String) -> MathPreambleCompilation {
        var macros: [String: String] = [:]
        var ignored: [Int] = []
        var invalid: [Int] = []

        for (offset, rawLine) in source.components(separatedBy: .newlines).enumerated() {
            let lineNumber = offset + 1
            let line = stripComment(from: rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if let groups = captures(commandExpression, in: line), groups.count == 3 {
                let name = groups[0]
                let argumentCount = Int(groups[1]) ?? 0
                let body = groups[2]
                if (0...9).contains(argumentCount), body.count <= 2_000 {
                    macros[name] = body
                } else {
                    invalid.append(lineNumber)
                }
                continue
            }

            if let groups = captures(operatorExpression, in: line), groups.count == 2 {
                macros[groups[0]] = "\\operatorname{\(groups[1])}"
                continue
            }

            if line.hasPrefix("\\newcommand")
                || line.hasPrefix("\\renewcommand")
                || line.hasPrefix("\\DeclareMathOperator") {
                invalid.append(lineNumber)
            } else {
                ignored.append(lineNumber)
            }
        }

        return MathPreambleCompilation(
            macros: macros,
            ignoredLineNumbers: ignored,
            invalidLineNumbers: invalid
        )
    }

    private static func captures(_ expression: NSRegularExpression, in string: String) -> [String]? {
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        guard let match = expression.firstMatch(in: string, range: range) else { return nil }
        return (1..<match.numberOfRanges).map { index in
            let range = match.range(at: index)
            guard range.location != NSNotFound, let swiftRange = Range(range, in: string) else { return "" }
            return String(string[swiftRange])
        }
    }

    private static func stripComment(from line: String) -> String {
        var previous: Character?
        for index in line.indices {
            let character = line[index]
            if character == "%", previous != "\\" {
                return String(line[..<index])
            }
            previous = character
        }
        return line
    }
}
