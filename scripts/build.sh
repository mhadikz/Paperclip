#!/bin/bash
# Builds Paperclip.app (+ widget extension) with swiftc, no Xcode required.
#
#   scripts/build.sh                 debug-ish build for this Mac, installed to ~/Applications
#   scripts/build.sh --release       universal (arm64 + x86_64), optimized, hardened runtime
#   scripts/build.sh --no-install    leave the result in build/ only
#   SIGN_IDENTITY="Developer ID Application: …" scripts/build.sh --release
#
# Output: build/Paperclip.app
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/Paperclip"
WIDGET_SRC="$ROOT/PaperclipWidget"
BUILD="$ROOT/build"
APP="$BUILD/Paperclip.app"
MACOS="$APP/Contents/MacOS"
RESOURCES="$APP/Contents/Resources"
WIDGET_APPEX="$APP/Contents/PlugIns/PaperclipWidgets.appex"
WIDGET_MACOS="$WIDGET_APPEX/Contents/MacOS"

SDK="$(xcrun --show-sdk-path)"
MIN_OS="14.0"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"   # "-" = ad-hoc
RELEASE=0
INSTALL=1
for arg in "$@"; do
  case "$arg" in
    --release) RELEASE=1 ;;
    --no-install) INSTALL=0 ;;
    --help|-h) sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

if [ "$RELEASE" = 1 ]; then
  ARCHS=(arm64 x86_64)
else
  ARCHS=("$(uname -m)")
fi

APP_FRAMEWORKS=(SwiftUI AppKit ServiceManagement Combine Carbon Vision OSLog WidgetKit AppIntents)
# FoundationModels ships with the macOS 26 SDK only; the code soft-depends on it via canImport.
if [ -d "$SDK/System/Library/Frameworks/FoundationModels.framework" ]; then
  APP_FRAMEWORKS+=(FoundationModels)
fi
WIDGET_FRAMEWORKS=(SwiftUI AppKit WidgetKit AppIntents)

echo "→ Cleaning build directory"
rm -rf "$APP" "$BUILD/obj"
mkdir -p "$MACOS" "$RESOURCES" "$WIDGET_MACOS" "$BUILD/obj"

collect_sources() {
  local dir="$1"; shift
  find "$dir" -name '*.swift' -print0 | sort -z
}

compile() {
  # compile <output> <arch> <extension:0|1> <frameworks...> -- <sources...>
  local out="$1"; local arch="$2"; local is_ext="$3"; shift 3
  local frameworks=()
  while [ "$1" != "--" ]; do frameworks+=("-framework" "$1"); shift; done
  shift
  local extra=()
  if [ "$is_ext" = 1 ]; then
    extra+=(-application-extension -Xlinker -e -Xlinker _NSExtensionMain)
  fi
  swiftc "$@" \
    -parse-as-library \
    -o "$out" \
    -sdk "$SDK" \
    -target "${arch}-apple-macosx${MIN_OS}" \
    -swift-version 5 \
    -O -wmo \
    "${frameworks[@]}" \
    ${extra[@]+"${extra[@]}"}
}

link_universal() {
  # link_universal <final> <slice...>
  local final="$1"; shift
  if [ "$#" -eq 1 ]; then
    mv "$1" "$final"
  else
    lipo -create "$@" -output "$final"
    rm -f "$@"
  fi
}

echo "→ Compiling app (${ARCHS[*]})"
APP_SOURCES=()
while IFS= read -r -d '' f; do APP_SOURCES+=("$f"); done < <(collect_sources "$SRC")
APP_SLICES=()
for arch in "${ARCHS[@]}"; do
  compile "$BUILD/obj/Paperclip-$arch" "$arch" 0 "${APP_FRAMEWORKS[@]}" -- "${APP_SOURCES[@]}"
  APP_SLICES+=("$BUILD/obj/Paperclip-$arch")
done
link_universal "$MACOS/Paperclip" "${APP_SLICES[@]}"

echo "→ Compiling widget extension (${ARCHS[*]})"
WIDGET_SOURCES=("$SRC/Shared/WidgetSnapshot.swift" "$SRC/Shared/WidgetActions.swift")
while IFS= read -r -d '' f; do WIDGET_SOURCES+=("$f"); done < <(collect_sources "$WIDGET_SRC")
WIDGET_SLICES=()
for arch in "${ARCHS[@]}"; do
  compile "$BUILD/obj/PaperclipWidgets-$arch" "$arch" 1 "${WIDGET_FRAMEWORKS[@]}" -- "${WIDGET_SOURCES[@]}"
  WIDGET_SLICES+=("$BUILD/obj/PaperclipWidgets-$arch")
done
link_universal "$WIDGET_MACOS/PaperclipWidgets" "${WIDGET_SLICES[@]}"

echo "→ Bundling resources"
cp "$SRC/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
if [ ! -f "$SRC/Resources/AppIcon.icns" ]; then
  "$ROOT/scripts/make-icon.sh"
fi
cp "$SRC/Resources/AppIcon.icns" "$RESOURCES/AppIcon.icns"
cp "$WIDGET_SRC/Info.plist" "$WIDGET_APPEX/Contents/Info.plist"
mkdir -p "$WIDGET_APPEX/Contents/Resources/Metadata.appintents"
cp "$WIDGET_SRC/Metadata.appintents/"* "$WIDGET_APPEX/Contents/Resources/Metadata.appintents/"

sign_app() {
  local dest="$1"
  # Inside-out, never --deep: PluginKit rejects an appex signed with the parent's entitlements.
  codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp=none \
    --entitlements "$WIDGET_SRC/PaperclipWidget.entitlements" \
    "$dest/Contents/PlugIns/PaperclipWidgets.appex"
  codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp=none \
    --entitlements "$SRC/Resources/Paperclip.entitlements" \
    "$dest"
}

echo "→ Code signing ($SIGN_IDENTITY)"
sign_app "$APP"
codesign --verify --strict "$APP"

if [ "$INSTALL" = 1 ]; then
  pkill -x Paperclip 2>/dev/null || true
  pkill -x PaperclipWidgets 2>/dev/null || true

  install_app() {
    local dest="$1"
    mkdir -p "$(dirname "$dest")"
    rm -rf "$dest"
    cp -R "$APP" "$dest"
    xattr -cr "$dest" 2>/dev/null || true
  }

  # Launch Services is unreliable for apps on some external volumes.
  INSTALL_DIR="${HOME}/Applications"
  install_app "$INSTALL_DIR/Paperclip.app"
  if [ -w /Applications ]; then
    install_app "/Applications/Paperclip.app"
  fi

  LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
  "$LSREGISTER" -f "$INSTALL_DIR/Paperclip.app" >/dev/null 2>&1 || true
  pluginkit -a "$INSTALL_DIR/Paperclip.app/Contents/PlugIns/PaperclipWidgets.appex" >/dev/null 2>&1 || true
  if [ -d /Applications/Paperclip.app ]; then
    "$LSREGISTER" -f /Applications/Paperclip.app >/dev/null 2>&1 || true
    pluginkit -a /Applications/Paperclip.app/Contents/PlugIns/PaperclipWidgets.appex >/dev/null 2>&1 || true
  fi
  pluginkit -e use -i com.mhadikz.Paperclip.Widget >/dev/null 2>&1 || true

  echo "→ Installed: $INSTALL_DIR/Paperclip.app"
  [ -d /Applications/Paperclip.app ] && echo "→ Also installed: /Applications/Paperclip.app"
  echo ""
  echo "Run with:  open \"$INSTALL_DIR/Paperclip.app\""
fi

echo "→ Built: $APP"
lipo -info "$MACOS/Paperclip" | sed 's/^/   /'
