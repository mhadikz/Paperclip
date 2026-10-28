#!/bin/bash
# Builds and runs the test suite without XCTest (works with Command Line Tools only).
# Usage: scripts/test.sh [name-filter]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="$(xcrun --show-sdk-path)"
TARGET="${TARGET:-arm64-apple-macosx14.0}"
OUT="$ROOT/build/PaperclipTests"

mkdir -p "$ROOT/build"

EXTRA_FRAMEWORKS=()
if [ -d "$SDK/System/Library/Frameworks/FoundationModels.framework" ]; then
  EXTRA_FRAMEWORKS+=(-framework FoundationModels)
fi

SOURCES=()
while IFS= read -r -d '' file; do
  case "$file" in
    *PaperclipApp.swift) continue ;;   # only one @main
  esac
  SOURCES+=("$file")
done < <(find "$ROOT/Paperclip" -name '*.swift' -print0 | sort -z)
while IFS= read -r -d '' file; do
  SOURCES+=("$file")
done < <(find "$ROOT/PaperclipTests" -name '*.swift' -print0 | sort -z)

echo "→ Compiling tests (${#SOURCES[@]} files)"
swiftc "${SOURCES[@]}" \
  -o "$OUT" \
  -sdk "$SDK" \
  -target "$TARGET" \
  -swift-version 5 \
  -Onone \
  -framework SwiftUI \
  -framework AppKit \
  -framework ServiceManagement \
  -framework Combine \
  -framework Carbon \
  -framework Vision \
  -framework OSLog \
  -framework WidgetKit \
  -framework AppIntents \
  ${EXTRA_FRAMEWORKS[@]+"${EXTRA_FRAMEWORKS[@]}"}

echo "→ Running"
"$OUT" "$@"
