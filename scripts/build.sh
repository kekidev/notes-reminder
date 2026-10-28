#!/usr/bin/env bash
# Build a Release Glance.app and a .dmg into dist/. Ad-hoc signed, not notarized.
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate
xcodebuild -scheme Glance -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath DerivedData build -quiet

rm -rf dist
mkdir -p dist
ditto DerivedData/Build/Products/Release/Glance.app dist/Glance.app

mcp=dist/Glance.app/Contents/MacOS/glance-mcp
[ -x "$mcp" ] || { echo "error: $mcp missing or not executable" >&2; exit 1; }
# No arguments is a usage error: expect exit 64 (EX_USAGE).
rc=0
"$mcp" >/dev/null 2>&1 </dev/null || rc=$?
[ "$rc" -eq 64 ] || { echo "error: glance-mcp exited $rc, expected 64" >&2; exit 1; }
echo "glance-mcp exit code: $rc"

# The Applications link gives the DMG window its drag-to-install target.
stage=$(mktemp -d)
ditto dist/Glance.app "$stage/Glance.app"
ln -s /Applications "$stage/Applications"
hdiutil create -volname Glance -srcfolder "$stage" -ov -format UDZO dist/Glance.dmg >/dev/null
rm -rf "$stage"

echo "App: $PWD/dist/Glance.app"
echo "DMG: $PWD/dist/Glance.dmg"
