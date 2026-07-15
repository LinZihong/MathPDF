# Vendored qpdf persistence dependency

MathPDF links qpdf `12.3.2` and libjpeg-turbo `3.2.0` as universal static
archives. The app has no Homebrew or other non-system runtime dependency; the
remaining dynamic links are Apple's `libz`, `libc++`, and `libSystem`.

The archives are used only by the narrow Objective-C++ PDF persistence bridge.
PDFKit remains the runtime viewer. Regenerate the archives and public qpdf
headers with `scripts/vendor-qpdf.sh`.

Pinned revisions:

- qpdf `v12.3.2`: `a898bb3a7289d1d05789d6d3f0d5dd534943a8da`
- libjpeg-turbo `3.2.0`: `c85e6b905bf237038faa936dab160ebfc5da0344`

Licenses and qpdf's notice are retained under `licenses/`.
