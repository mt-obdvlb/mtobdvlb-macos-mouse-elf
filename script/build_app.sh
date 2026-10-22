#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
CONFIGURATION="${1:-debug}"
case "$CONFIGURATION" in debug|release) ;; *) echo "usage: $0 [debug|release]" >&2; exit 2;; esac
./script/swift.sh build -c "$CONFIGURATION" --product MouseElf
BUILD_DIR="$(./script/swift.sh build -c "$CONFIGURATION" --show-bin-path)"
mkdir -p "$ROOT_DIR/dist"
STAGING_DIR="$(mktemp -d "$BUILD_DIR/mouse-elf-bundle.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
APP_BUNDLE="$STAGING_DIR/MouseElf.app"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BUILD_DIR/MouseElf" "$APP_BUNDLE/Contents/MacOS/MouseElf"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
if [ ! -f "$ROOT_DIR/dist/AppIcon.icns" ] || [ "$ROOT_DIR/script/generate_icon.swift" -nt "$ROOT_DIR/dist/AppIcon.icns" ]; then
    swift "$ROOT_DIR/script/generate_icon.swift" "$ROOT_DIR/dist"
    /usr/bin/iconutil -c icns "$ROOT_DIR/dist/AppIcon.iconset" -o "$ROOT_DIR/dist/AppIcon.icns"
fi
cp "$ROOT_DIR/dist/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
/usr/bin/plutil -lint "$APP_BUNDLE/Contents/Info.plist"
# Desktop/iCloud file providers may attach Finder metadata to generated bundles.
# Clear only this generated app before signing, never the source tree.
/usr/bin/xattr -cr "$APP_BUNDLE"
/usr/bin/codesign --force --sign "${MOUSE_ELF_SIGNING_IDENTITY:--}" --identifier dev.mtobdvlb.mouse-elf "$APP_BUNDLE"
/usr/bin/codesign --verify --strict "$APP_BUNDLE"
if [ -d "$BUILD_DIR/MouseElf.app" ]; then
    mv "$BUILD_DIR/MouseElf.app" "$STAGING_DIR/previous-bundle"
fi
mv "$APP_BUNDLE" "$BUILD_DIR/MouseElf.app"
if [ -L "$ROOT_DIR/dist/MouseElf.app" ]; then
    rm "$ROOT_DIR/dist/MouseElf.app"
elif [ -e "$ROOT_DIR/dist/MouseElf.app" ]; then
    mv "$ROOT_DIR/dist/MouseElf.app" "$STAGING_DIR/previous-output"
fi
# A synchronized Desktop can add FinderInfo after signing. Keep the signed
# bundle outside the file provider and expose it through a project-local link.
ln -s "$BUILD_DIR/MouseElf.app" "$ROOT_DIR/dist/MouseElf.app"
/usr/bin/codesign --verify --strict "$BUILD_DIR/MouseElf.app"
echo "Built: $ROOT_DIR/dist/MouseElf.app"
