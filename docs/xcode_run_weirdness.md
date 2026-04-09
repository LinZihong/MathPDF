# Xcode Run Weirdness

Observed on 2026-04-06 while validating the KaTeX renderer migration.

## Summary

Math rendering works in the unsigned app bundle produced through the repo-local CLI workflow, but fails in a genuinely signed Debug app bundle. The key variable is no longer just "Xcode Run versus xcodebuild". A repo-local `xcodebuild` product built with signing enabled also reproduces the rendering failure, which makes code signing plus the attached entitlements the strongest current lead.

## Known-Good Unsigned Path

The repo-local CLI workflow defaults to an unsigned build and writes to:

- `/Users/linzihong/Documents/Development/Xcode/MathPDF/.build/DerivedData/Build/Products/Debug/MathPDF.app`

The canonical validation command is:

```bash
scripts/build-and-launch.sh "/Users/linzihong/Documents/Development/Xcode/MathPDF/pdfs for testing/ell_curves.pdf"
```

That path produced a live app window showing `ell_curves.pdf` and a rendered note inspector with KaTeX-rendered inline and display math.

## Signed Path That Fails

After removing the temporary Xcode override that forced `CODE_SIGNING_ALLOWED=NO`, the repo-local signed build was reproduced with:

```bash
xcodebuild \
  -project MathPDF.xcodeproj \
  -scheme MathPDF \
  -configuration Debug \
  -derivedDataPath .build/ActuallySignedDerivedData \
  build
```

The resulting app bundle was:

- `/Users/linzihong/Documents/Development/Xcode/MathPDF/.build/ActuallySignedDerivedData/Build/Products/Debug/MathPDF.app`

`codesign -dvv` printed real signer metadata for that bundle:

- `Identifier=linz.MathPDF`
- `Authority=Apple Development: 1046298030@qq.com (LU64G749MJ)`
- `TeamIdentifier=NNVU3CZ6DZ`
- `Signed Time=Apr 6, 2026 at 23:24:38`

The signed bundle also carried these entitlements:

- `com.apple.security.app-sandbox = true`
- `com.apple.security.files.user-selected.read-only = true`
- `com.apple.security.get-task-allow = true`

Manual product validation then confirmed that this genuinely signed repo-local `xcodebuild` product still failed to render KaTeX output in the note inspector.

## What Was Confirmed

- The Xcode-built app bundle contains the KaTeX runtime assets:
  - `katex.min.js`
  - `auto-render.min.js`
  - `katex.min.css`
  - the `KaTeX_*.woff2` font files
- The Xcode-built app binary also contains the KaTeX renderer strings such as:
  - `renderMathInElement`
  - `katex-error`
  - `noteHeight`
  - `expectedMathMarkup`
- Therefore the Xcode-built product is not simply missing the new renderer resources.
- The same rendering failure occurs in a signed app built by `xcodebuild`, not only in an app launched from Xcode's Run action.
- Therefore the "debugger-only" theory is too weak on its own. Signing state is a stronger differentiator than launch origin.

## Important Source Of Confusion During Debugging

Earlier debugging was confounded by both launch mechanics and an accidental Xcode build-setting override:

- the old helper script launched the raw executable directly instead of launching the app bundle in the normal macOS way
- that made it easy to end up with multiple `MathPDF` instances from different build locations
- one visible `MathPDF` window could have no PDF loaded while another hidden instance had the expected document open
- adding `CODE_SIGNING_ALLOWED = NO` in Xcode Build Settings affected plain `xcodebuild` Debug builds too, which produced a falsely named "signed" repo-local build that was actually unsigned

That confusion was real, but it is not the whole story. After the launch workflow was cleaned up and a genuinely signed repo-local bundle was produced, the rendering discrepancy still remained.

## Most Relevant Remaining Difference

The current strongest lead is the difference between signed-plus-entitled runtime and unsigned runtime. That lead is stronger than the old "Xcode debugger only" theory because the signed failure can now be reproduced without Xcode Run.

The older Xcode Run environment discrepancy still exists and may matter, because when Xcode runs the app under the debugger it injects a materially different runtime environment, including:

- `DYLD_INSERT_LIBRARIES`
- `DYLD_FRAMEWORK_PATH`
- `DYLD_LIBRARY_PATH`
- `libMainThreadChecker.dylib`
- `libViewDebuggerSupport.dylib`
- `-NSDocumentRevisionsDebugMode YES`

But this is no longer the primary suspect. The next investigation should focus on why the signed runtime breaks `WKWebView`-backed math rendering even when the app bundle is built outside Xcode Run.

## Additional Unresolved Detail

Directly launching the Xcode-built app bundle with:

```bash
open -n -a "$HOME/Library/Developer/Xcode/DerivedData/MathPDF-gdsictjnpekonjbwwweutdbnhxmr/Build/Products/Debug/MathPDF.app" --args --open-document "/Users/linzihong/Documents/Development/Xcode/MathPDF/pdfs for testing/ell_curves.pdf"
```

could still show an early `Couldn't Open PDF` alert. In contrast, the CLI-built app could sometimes show similar open-state weirdness yet still succeed after manually opening the same file. That means the remaining issue may involve launch-time document opening in addition to the debugger-injected environment.

However, launch-time file opening is not the main renderer failure described above. The key failure mode is that after a signed app opens the fixture manually, the note still shows raw math text instead of KaTeX-rendered output.

## Current Practical Guidance

- Use `scripts/build-and-launch.sh --unsigned` for reliable renderer validation while this bug remains unresolved.
- Use `scripts/build-and-launch.sh --signed --build-only` when you need a genuinely signed repo-local product that mirrors the shipping runtime more closely.
- Do not leave `CODE_SIGNING_ALLOWED = NO` in Xcode Build Settings if you want plain `xcodebuild` Debug builds to stay signed by default.
- If you temporarily restore `CODE_SIGNING_ALLOWED = NO` in Xcode for local debugging, remember that a plain `xcodebuild ... build` will inherit that and become unsigned unless the command line explicitly overrides it with `CODE_SIGNING_ALLOWED=YES`.
