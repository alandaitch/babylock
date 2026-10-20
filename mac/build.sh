#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
output_dir="${1:-$repo_root/dist}"
app="$output_dir/BabyLock.app"

mkdir -p "$app/Contents/MacOS"
cp "$repo_root/mac/Info.plist" "$app/Contents/Info.plist"
swiftc -O -swift-version 5 -target arm64-apple-macos13.0 "$repo_root/mac/main.swift" \
  -o "$app/Contents/MacOS/BabyLock-arm64" \
  -framework AppKit -framework ApplicationServices
swiftc -O -swift-version 5 -target x86_64-apple-macos13.0 "$repo_root/mac/main.swift" \
  -o "$app/Contents/MacOS/BabyLock-x86_64" \
  -framework AppKit -framework ApplicationServices
lipo -create "$app/Contents/MacOS/BabyLock-arm64" \
  "$app/Contents/MacOS/BabyLock-x86_64" -output "$app/Contents/MacOS/BabyLock"
rm "$app/Contents/MacOS/BabyLock-arm64" "$app/Contents/MacOS/BabyLock-x86_64"
codesign --force --deep --sign - "$app"
echo "$app"
