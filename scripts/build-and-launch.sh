#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/MathPDF.xcodeproj"
SCHEME="MathPDF"
CONFIGURATION="${CONFIGURATION:-Debug}"
SIGNING_MODE="${MATHPDF_SIGNING_MODE:-signed}"
BUILD_ONLY="${MATHPDF_BUILD_ONLY:-0}"
DOCUMENT_PATH=""
RENDERER_EXPERIMENT="${MATHPDF_RENDERER_EXPERIMENT:-}"
RENDERER_DIAGNOSTICS="${MATHPDF_RENDERER_DIAGNOSTICS:-0}"
SCRIPT_NAME="${0:t}"

usage() {
  cat >&2 <<EOF
Usage: $SCRIPT_NAME [--signed|--developer-signed|--unsigned] [--build-only] [--renderer-experiment name] [--renderer-diagnostics] [path-to-pdf]

Defaults:
  --signed     Sign to run locally without requiring an Apple Development certificate
  --developer-signed  Use the project's Apple Development signing settings
  --unsigned   Build with CODE_SIGNING_ALLOWED=NO for narrow comparisons only
  --build-only Build but do not launch the app
  --renderer-experiment name  Pass a renderer experiment to the app
  --renderer-diagnostics      Show the native renderer diagnostics readout in the note inspector

Environment overrides:
  CONFIGURATION=Debug|Release
  MATHPDF_OPEN_DOCUMENT=/abs/path/to/file.pdf
  MATHPDF_SIGNING_MODE=signed|developer-signed|unsigned
  MATHPDF_BUILD_ONLY=1
  MATHPDF_RENDERER_EXPERIMENT=production|production-no-height|plain-text|inline-js|inline-js-height|katex-no-fonts
  MATHPDF_RENDERER_DIAGNOSTICS=1
EOF
  exit 1
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --signed)
      SIGNING_MODE="signed"
      ;;
    --developer-signed)
      SIGNING_MODE="developer-signed"
      ;;
    --unsigned)
      SIGNING_MODE="unsigned"
      ;;
    --build-only)
      BUILD_ONLY=1
      ;;
    --renderer-experiment)
      shift
      if [[ "$#" -eq 0 ]]; then
        echo "--renderer-experiment requires a value." >&2
        usage
      fi
      RENDERER_EXPERIMENT="$1"
      ;;
    --renderer-diagnostics)
      RENDERER_DIAGNOSTICS=1
      ;;
    -h|--help)
      usage
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage
      ;;
    *)
      if [[ -n "$DOCUMENT_PATH" ]]; then
        echo "Only one PDF path may be provided." >&2
        usage
      fi
      DOCUMENT_PATH="$1"
      ;;
  esac
  shift
done

if [[ -z "$DOCUMENT_PATH" && "$#" -gt 0 ]]; then
  DOCUMENT_PATH="$1"
  shift
fi

if [[ "$#" -gt 0 ]]; then
  echo "Unexpected extra arguments: $*" >&2
  usage
fi

DOCUMENT_PATH="${DOCUMENT_PATH:-${MATHPDF_OPEN_DOCUMENT:-}}"

if [[ -n "$DOCUMENT_PATH" ]]; then
  if ! DOCUMENT_PATH="$(realpath "$DOCUMENT_PATH" 2>/dev/null)"; then
    echo "Document path does not exist: $DOCUMENT_PATH" >&2
    exit 1
  fi
fi

case "$SIGNING_MODE" in
  signed)
    DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/.build/SignedDerivedData}"
    XCODEBUILD_SIGNING_ARGS=(
      CODE_SIGN_IDENTITY=-
      CODE_SIGN_STYLE=Manual
      DEVELOPMENT_TEAM=
      PROVISIONING_PROFILE_SPECIFIER=
    )
    ;;
  developer-signed)
    DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/.build/DeveloperSignedDerivedData}"
    XCODEBUILD_SIGNING_ARGS=()
    ;;
  unsigned)
    DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/.build/DerivedData}"
    XCODEBUILD_SIGNING_ARGS=(CODE_SIGNING_ALLOWED=NO)
    ;;
  *)
    echo "Unsupported signing mode: $SIGNING_MODE" >&2
    usage
    ;;
esac

APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/MathPDF.app"

echo "Project: $PROJECT_PATH"
echo "Scheme: $SCHEME"
echo "Configuration: $CONFIGURATION"
echo "Signing mode: $SIGNING_MODE"
echo "DerivedData: $DERIVED_DATA_PATH"

xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  "${XCODEBUILD_SIGNING_ARGS[@]}" \
  build

if [[ ! -d "$APP_PATH" ]]; then
  echo "Built app not found at $APP_PATH" >&2
  exit 1
fi

echo "Built app: $APP_PATH"
if [[ "$SIGNING_MODE" != "unsigned" ]]; then
  codesign --verify --deep --strict --verbose=2 "$APP_PATH"
  entitlements="$(codesign -d --entitlements - "$APP_PATH" 2>&1)"
  for required_entitlement in \
    com.apple.security.app-sandbox \
    com.apple.security.network.client \
    com.apple.security.files.user-selected.read-write; do
    if [[ "$entitlements" != *"$required_entitlement"* ]]; then
      echo "Missing required entitlement: $required_entitlement" >&2
      exit 1
    fi
  done
  echo "Verified local signature and required sandbox entitlements."
fi

if codesign_output="$(codesign -dvv "$APP_PATH" 2>&1)"; then
  echo "$codesign_output" | grep -E '^(Identifier|Authority|TeamIdentifier|Signed Time)=' || true
else
  echo "codesign: app is unsigned"
fi

if [[ "$BUILD_ONLY" == "1" ]]; then
  echo "Build-only mode: not launching app."
  exit 0
fi

APP_ARGS=(
  -ApplePersistenceIgnoreState YES
  -NSQuitAlwaysKeepsWindows NO
)
if [[ -n "$RENDERER_EXPERIMENT" ]]; then
  APP_ARGS+=(--renderer-experiment "$RENDERER_EXPERIMENT")
fi

if [[ "$RENDERER_DIAGNOSTICS" == "1" ]]; then
  APP_ARGS+=(--renderer-diagnostics)
fi

if [[ -n "$DOCUMENT_PATH" ]]; then
  open -na "$APP_PATH" "$DOCUMENT_PATH" --args "${APP_ARGS[@]}"
  echo "Launched $APP_PATH with $DOCUMENT_PATH"
else
  open -na "$APP_PATH" --args "${APP_ARGS[@]}"
  echo "Launched $APP_PATH"
fi
