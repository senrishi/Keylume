#!/bin/zsh
set -eu
cd "${0:A:h}"
bundle="$PWD/dist/MK1300-RGB.app"
macos="$bundle/Contents/MacOS"
mkdir -p "$macos" "$bundle/Contents/Resources"
cp Resources/Kicktroll-* "$bundle/Contents/Resources/"

clang -O2 -mmacosx-version-min=13.0 rgb-probe.c -framework IOKit -framework CoreFoundation -o "$macos/rgb-probe"
swiftc -module-cache-path "$PWD/dist/module-cache" -parse-as-library -O -target "$(uname -m)-apple-macosx13.0" Editor.swift -o "$macos/MK1300-RGB"
cat > "$bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>MK1300-RGB</string>
<key>CFBundleIdentifier</key><string>local.mk1300.rgb</string>
<key>CFBundleName</key><string>MK1300 RGB</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>6</string>
<key>CFBundleShortVersionString</key><string>1.4.1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
</dict></plist>
PLIST

codesign --force --sign - "$macos/rgb-probe"
codesign --force --sign - "$bundle"
codesign --verify --deep --strict "$bundle"
"$macos/MK1300-RGB" --check-bundle
