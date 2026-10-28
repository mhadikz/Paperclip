#!/bin/bash
# Renders UI previews to build/previews/*.png (no Screen Recording permission needed).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="$(xcrun --show-sdk-path)"
OUT="$ROOT/build/RenderPreviews"
mkdir -p "$ROOT/build/previews"
SOURCES=()
while IFS= read -r -d '' f; do
  case "$f" in *PaperclipApp.swift) continue ;; esac
  SOURCES+=("$f")
done < <(find "$ROOT/Paperclip" -name '*.swift' -print0 | sort -z)
SOURCES+=("$ROOT/scripts/previews/RenderPreviews.swift")
EXTRA_FRAMEWORKS=()
if [ -d "$SDK/System/Library/Frameworks/FoundationModels.framework" ]; then
  EXTRA_FRAMEWORKS+=(-framework FoundationModels)
fi
echo "→ Compiling preview renderer"
swiftc "${SOURCES[@]}" -o "$OUT" -sdk "$SDK" -target "$(uname -m)-apple-macosx14.0" -swift-version 5 -Onone \
  -framework SwiftUI -framework AppKit -framework ServiceManagement -framework Combine -framework Carbon \
  -framework Vision -framework OSLog -framework WidgetKit -framework AppIntents ${EXTRA_FRAMEWORKS[@]+"${EXTRA_FRAMEWORKS[@]}"}
"$OUT" "$ROOT/build/previews"
