#!/bin/bash
# Fast type-check of app + widget sources (no linking, no install).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="$(xcrun --show-sdk-path)"
TARGET="${TARGET:-arm64-apple-macosx14.0}"

SOURCES=()
while IFS= read -r -d '' file; do
  SOURCES+=("$file")
done < <(find "$ROOT/Paperclip" -name '*.swift' -print0 | sort -z)

echo "→ Type-checking app sources (${#SOURCES[@]} files)"
swiftc "${SOURCES[@]}" -parse-as-library -typecheck \
  -sdk "$SDK" -target "$TARGET" -swift-version 5 "$@"

WIDGET_SOURCES=("$ROOT/Paperclip/Shared/WidgetSnapshot.swift" "$ROOT/Paperclip/Shared/WidgetActions.swift")
while IFS= read -r -d '' file; do
  WIDGET_SOURCES+=("$file")
done < <(find "$ROOT/PaperclipWidget" -name '*.swift' -print0 | sort -z)

echo "→ Type-checking widget sources (${#WIDGET_SOURCES[@]} files)"
swiftc "${WIDGET_SOURCES[@]}" -parse-as-library -typecheck -application-extension \
  -sdk "$SDK" -target "$TARGET" -swift-version 5 "$@"

echo "✓ Type-check passed"
