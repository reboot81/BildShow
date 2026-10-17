#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-release}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swift-cache"
swift build --disable-sandbox -c "$configuration" --arch arm64
bin_dir="$(swift build --disable-sandbox -c "$configuration" --arch arm64 --show-bin-path)"
app="$PWD/build/BildShow.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/BildShow" "$app/Contents/MacOS/"
cp packaging/Info.plist "$app/Contents/Info.plist"
ditto "$bin_dir/BildShow_BildShow.bundle" "$app/Contents/Resources/BildShow_BildShow.bundle"
if [[ -f packaging/AppIcon.icns ]]; then cp packaging/AppIcon.icns "$app/Contents/Resources/"; fi
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp --entitlements packaging/BildShow.entitlements "$app"
else
  codesign --force --sign - --options runtime --entitlements packaging/BildShow.entitlements "$app"
fi
codesign --verify --deep --strict "$app"
echo "$app"
