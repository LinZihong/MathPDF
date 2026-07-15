import SwiftUI

struct PreambleInspectorView: View {
    @ObservedObject var document: MathPDFDocument

    var body: some View {
        let compilation = MathPreambleCompiler.compile(document.preamble)

        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Math Macros")
                    .font(.headline)
                Text("Document settings")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(14)

            Divider()

            TextEditor(text: $document.preamble)
                .font(.body.monospaced())
                .padding(10)
                .accessibilityIdentifier("preamble-editor")

            Divider()

            VStack(alignment: .leading, spacing: 7) {
                Text("Supports simple aliases, parameterized commands, and math operators. Other preamble lines are preserved but ignored while rendering notes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(compilation.statusText)
                    .font(.caption)
                    .foregroundStyle(
                        compilation.invalidLineNumbers.isEmpty ? Color.secondary : Color.orange
                    )
            }
            .padding(12)
        }
    }
}
