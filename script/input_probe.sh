#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
probe_cache="/tmp/mouse-elf-probe-${UID}"
mkdir -p "$probe_cache"
chmod 700 "$probe_cache"
probe_app="$probe_cache/MouseElfProbe.app"
mkdir -p "$probe_app/Contents/MacOS"

swiftc -swift-version 5 -parse-as-library \
  -framework AppKit -framework CoreGraphics \
  "$project_root/Tests/Fixtures/InputProbe.swift" \
  -o "$probe_app/Contents/MacOS/MouseElfProbe"

cat > "$probe_app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>MouseElfProbe</string>
  <key>CFBundleIdentifier</key><string>local.mouse-elf.input-probe</string>
  <key>CFBundleName</key><string>MouseElfProbe</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
</dict></plist>
PLIST

printf 'APP_PATH=%s\nSTATE_PATH=/tmp/mouse-elf-probe.json\n' "$probe_app"
if [[ "${1:-}" != "--build-only" ]]; then
  open "$probe_app"
fi
