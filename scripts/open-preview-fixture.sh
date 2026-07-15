#!/bin/zsh
set -euo pipefail

SCRIPT_NAME="${0:t}"
CHECK_ONLY=0

usage() {
  echo "Usage: $SCRIPT_NAME [--check-only] /private/tmp/MathPDF-Fixtures/file.pdf" >&2
  exit 1
}

if [[ "${1:-}" == "--check-only" ]]; then
  CHECK_ONLY=1
  shift
fi

[[ "$#" -eq 1 ]] || usage

DOCUMENT_PATH="$1"
if ! DOCUMENT_PATH="$(realpath "$DOCUMENT_PATH" 2>/dev/null)"; then
  echo "Document path does not exist: $1" >&2
  exit 1
fi

if [[ "$DOCUMENT_PATH" != /private/tmp/MathPDF-Fixtures/*.pdf ]]; then
  echo "Refusing unsafe Preview fixture path: $DOCUMENT_PATH" >&2
  echo "Derive a PDF copy under /tmp/MathPDF-Fixtures first." >&2
  exit 1
fi

if [[ ! -f "$DOCUMENT_PATH" ]]; then
  echo "Preview fixture is not a regular file: $DOCUMENT_PATH" >&2
  exit 1
fi

echo "Verified Preview fixture: $DOCUMENT_PATH"
if [[ "$CHECK_ONLY" == "1" ]]; then
  exit 0
fi

open -a Preview "$DOCUMENT_PATH"
