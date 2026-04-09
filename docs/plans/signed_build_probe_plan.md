# Signed Debug Build Probe

This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to date as work proceeds.

This document must be maintained in accordance with [PLANS.md](/Users/linzihong/Documents/Development/Xcode/MathPDF/PLANS.md).

## Purpose / Big Picture

This plan captures a narrow but important investigation result: MathPDF's KaTeX note rendering bug is reproducible in a genuinely signed macOS Debug app built by `xcodebuild`, not just when launching from Xcode's Run action. After this slice, a future contributor can rebuild both the unsigned and signed app variants on demand, verify which one is actually signed, and continue isolating what part of the signed runtime breaks `WKWebView`-backed math rendering.

This plan does not change PDF annotation compatibility, math rendering fallback behavior, or per-document preamble metadata. It only documents the investigation and improves local build tooling.

## Progress

- [x] (2026-04-06 23:10Z) Verified that a temporary Xcode `CODE_SIGNING_ALLOWED = NO` override had been contaminating plain `xcodebuild` Debug builds, which produced a falsely named repo-local "signed" build that was actually unsigned.
- [x] (2026-04-06 23:24Z) Rebuilt a genuinely signed repo-local Debug app with `xcodebuild -derivedDataPath .build/ActuallySignedDerivedData build` and verified signer metadata with `codesign -dvv`.
- [x] (2026-04-06 23:30Z) Recorded the signed entitlements and the user-observed outcome that the signed repo-local build still fails to render math.
- [x] (2026-04-06 23:40Z) Updated `scripts/build-and-launch.sh` so future sessions can request signed or unsigned builds explicitly instead of mutating Xcode Build Settings.
- [x] (2026-04-06 23:45Z) Updated `docs/xcode_run_weirdness.md` with the corrected signed-versus-unsigned diagnosis and practical guidance.

## Surprises & Discoveries

- Observation: The user-defined `CODE_SIGNING_ALLOWED = NO` setting added in Xcode Build Settings affected plain `xcodebuild` Debug builds too.
  Evidence: `xcodebuild -showBuildSettings` resolved `CODE_SIGNING_ALLOWED = NO`, and `codesign -dvv` reported `code object is not signed at all` for the repo-local build that had been assumed to be signed.

- Observation: A repo-local Debug build can be genuinely signed outside Xcode Run.
  Evidence: `codesign -dvv .build/ActuallySignedDerivedData/Build/Products/Debug/MathPDF.app` printed `Authority=Apple Development: 1046298030@qq.com (LU64G749MJ)` and `TeamIdentifier=NNVU3CZ6DZ`.

- Observation: The signed repo-local build still fails to render KaTeX output.
  Evidence: Manual validation by the user after building the signed copy: "Good, this does not render."

## Decision Log

- Decision: Keep the project default signed and make unsigned builds an explicit helper-script option instead of a persistent Xcode Build Settings override.
  Rationale: Leaving `CODE_SIGNING_ALLOWED = NO` inside the target causes plain `xcodebuild` Debug builds to become unsigned by default, which undermines reproduction of the shipping-like runtime.
  Date/Author: 2026-04-06 / Codex

- Decision: Extend `scripts/build-and-launch.sh` rather than adding a second one-off script.
  Rationale: The repository already had a canonical local validation helper. Making signed and unsigned modes first-class there reduces drift and keeps future commands easy to remember.
  Date/Author: 2026-04-06 / Codex

## Outcomes & Retrospective

This slice achieved the narrow goal. The repository now records that signing state is a real causal variable: unsigned builds render, signed builds do not, even when both are produced by `xcodebuild` outside Xcode Run. The next investigation should treat the signed runtime, its entitlements, and its `WKWebView` subprocess behavior as the main area to isolate.

What remains unresolved is the mechanism. This plan does not explain why the signed app fails; it only removes earlier false leads and leaves a reproducible setup for the next pass.

## Context and Orientation

MathPDF is a macOS SwiftUI app in `/Users/linzihong/Documents/Development/Xcode/MathPDF/MathPDF/`. The shared Xcode scheme is `MathPDF` at `/Users/linzihong/Documents/Development/Xcode/MathPDF/MathPDF.xcodeproj/xcshareddata/xcschemes/MathPDF.xcscheme`. The helper script for local validation is `/Users/linzihong/Documents/Development/Xcode/MathPDF/scripts/build-and-launch.sh`.

The app's note renderer uses `WKWebView` in `/Users/linzihong/Documents/Development/Xcode/MathPDF/MathPDF/MathNoteRendering.swift`. The current failure is that a note containing valid KaTeX markup renders correctly in an unsigned build but shows raw text in a signed build. The canonical fixture PDF remains `/Users/linzihong/Documents/Development/Xcode/MathPDF/pdfs for testing/ell_curves.pdf`.

Code signing on macOS means the app bundle carries a cryptographic signature plus entitlements, which are attached permissions. In this project, the signed app carries at least `com.apple.security.app-sandbox` and `com.apple.security.files.user-selected.read-only`. The investigation result is that the presence of the signed runtime matters to rendering behavior.

## Plan of Work

Keep the helper workflow explicit. `scripts/build-and-launch.sh` must support two modes. In unsigned mode it should continue passing `CODE_SIGNING_ALLOWED=NO` and write to `.build/DerivedData`. In signed mode it must omit that override and write to a different derived-data root so both app variants can coexist. After the build completes, the script should print enough `codesign` metadata to show whether the result is actually signed.

The narrative investigation document at `/Users/linzihong/Documents/Development/Xcode/MathPDF/docs/xcode_run_weirdness.md` must be updated to reflect the corrected diagnosis: the bug is reproducible in a signed repo-local `xcodebuild` product, so the main variable is signed versus unsigned runtime rather than Xcode Run alone.

## Concrete Steps

Run these commands from `/Users/linzihong/Documents/Development/Xcode/MathPDF`.

Build an unsigned app and print its signing status:

    scripts/build-and-launch.sh --unsigned --build-only

Expected output includes:

    Signing mode: unsigned
    Built app: /Users/linzihong/Documents/Development/Xcode/MathPDF/.build/DerivedData/Build/Products/Debug/MathPDF.app
    codesign: app is unsigned

Build a signed app and print its signing status:

    scripts/build-and-launch.sh --signed --build-only

Expected output includes signer metadata similar to:

    Signing mode: signed
    Built app: /Users/linzihong/Documents/Development/Xcode/MathPDF/.build/SignedDerivedData/Build/Products/Debug/MathPDF.app
    Identifier=linz.MathPDF
    Authority=Apple Development: 1046298030@qq.com (LU64G749MJ)
    TeamIdentifier=NNVU3CZ6DZ

If a future contributor temporarily adds `CODE_SIGNING_ALLOWED = NO` back into Xcode Build Settings, they must remember that plain `xcodebuild` Debug builds will inherit that and become unsigned unless the command line explicitly adds `CODE_SIGNING_ALLOWED=YES`.

## Validation and Acceptance

Treat this as an existing-project change. Use scheme `MathPDF`. No simulator is used because the checked-in app target is macOS.

Validation has two parts. First, run:

    xcodebuild -project MathPDF.xcodeproj -scheme MathPDF -configuration Debug -derivedDataPath .build/ActuallySignedDerivedData build
    codesign -dvv .build/ActuallySignedDerivedData/Build/Products/Debug/MathPDF.app

Acceptance for the first part is that `codesign -dvv` prints signer metadata, including an `Authority=` line and a `TeamIdentifier=` line. Second, manually launch the resulting app and open `pdfs for testing/ell_curves.pdf`. Acceptance for the second part is the observed current bug: the signed app opens but does not render the math note, while the unsigned helper-built app does render it.

## Idempotence and Recovery

These steps are safe to repeat. Each helper mode writes to a separate `.build` derived-data directory, so rebuilding one variant does not destroy the other. If signing state becomes confusing again, rebuild with `--build-only` and rely on the printed `codesign` output rather than the folder name.

If a contributor accidentally reintroduces `CODE_SIGNING_ALLOWED = NO` in Xcode Build Settings and wants to restore signed defaults, remove that override from Xcode or explicitly pass `CODE_SIGNING_ALLOWED=YES` on the `xcodebuild` command line.

## Artifacts and Notes

The signed verification command produced output of this form:

    Identifier=linz.MathPDF
    Authority=Apple Development: 1046298030@qq.com (LU64G749MJ)
    TeamIdentifier=NNVU3CZ6DZ
    Signed Time=Apr 6, 2026 at 23:24:38

The signed entitlements printed as:

    com.apple.security.app-sandbox = true
    com.apple.security.files.user-selected.read-only = true
    com.apple.security.get-task-allow = true

## Interfaces and Dependencies

No app-facing Swift interfaces changed in this slice. The only tooling interface added is the CLI for `/Users/linzihong/Documents/Development/Xcode/MathPDF/scripts/build-and-launch.sh`:

- `--unsigned` builds with `CODE_SIGNING_ALLOWED=NO`
- `--signed` builds with the project's current signing settings
- `--build-only` suppresses launch so the built app can be inspected manually

Revision note: created this plan on 2026-04-06 to preserve the corrected signed-versus-unsigned diagnosis and the new helper-script workflow after the false "signed build" result was traced to a lingering Xcode Build Settings override.
