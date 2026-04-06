#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/MathPDF.xcodeproj"
SCHEME="MathPDF"
CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED_DATA_PATH="$ROOT_DIR/.build/DerivedData"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/MathPDF.app"
EXECUTABLE_PATH="$APP_PATH/Contents/MacOS/MathPDF"

echo "Project: $PROJECT_PATH"
echo "Scheme: $SCHEME"
echo "Configuration: $CONFIGURATION"
echo "DerivedData: $DERIVED_DATA_PATH"

xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  build

if [[ ! -d "$APP_PATH" ]]; then
  echo "Built app not found at $APP_PATH" >&2
  exit 1
fi

if [[ -n "${MATHPDF_OPEN_DOCUMENT:-}" ]]; then
  if [[ ! -x "$EXECUTABLE_PATH" ]]; then
    echo "Built executable not found at $EXECUTABLE_PATH" >&2
    exit 1
  fi

  "$EXECUTABLE_PATH" --open-document "$MATHPDF_OPEN_DOCUMENT" >/dev/null 2>&1 &
  echo "Launched $APP_PATH with $MATHPDF_OPEN_DOCUMENT"
else
  open "$APP_PATH"
  echo "Launched $APP_PATH"
fi
