#!/bin/zsh
# Builds BringBar.app (Apple silicon, native arm64) next to this script.
# Requires only the Xcode Command Line Tools:  xcode-select --install
# ./build.sh --install  also copies it to /Applications and starts it.
set -e
cd "$(dirname "$0")"
APP=BringBar.app
[[ -f Icon/AppIcon.icns ]] || swift Icon/make-icon.swift
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
cp Icon/AppIcon.icns "$APP/Contents/Resources/"
cp -R Resources/*.lproj "$APP/Contents/Resources/"
swiftc -O -swift-version 5 -target arm64-apple-macos14 Sources/BringBar/*.swift -o "$APP/Contents/MacOS/BringBar"
codesign --force --sign - "$APP"
echo "Built: $(pwd)/$APP"
if [[ "$1" == "--install" ]]; then
  pkill -x BringBar || true
  rm -rf /Applications/BringBar.app && cp -R "$APP" /Applications/
  open /Applications/BringBar.app
  echo "Installed in /Applications"
fi
