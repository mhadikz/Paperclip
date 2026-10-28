#!/bin/bash
# Regenerates Paperclip/Resources/AppIcon.icns from scripts/make-icon.swift.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build/icon"
mkdir -p "$OUT"
ICONSET="$(swift "$ROOT/scripts/make-icon.swift" "$OUT")"
iconutil -c icns "$ICONSET" -o "$ROOT/Paperclip/Resources/AppIcon.icns"
echo "→ Wrote $ROOT/Paperclip/Resources/AppIcon.icns"
