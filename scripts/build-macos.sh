#!/bin/zsh
set -eu
cd "${0:A:h:h}"
root="$PWD"
version="$(cat VERSION)"
bundle="$root/dist/Keylume.app"
macos="$bundle/Contents/MacOS"
mkdir -p "$macos" "$bundle/Contents/Resources"
cp shared/resources/Kicktroll-* "$bundle/Contents/Resources/"
cp shared/presets/RS.json "$bundle/Contents/Resources/"
cp branding/Keylume.icns "$bundle/Contents/Resources/"
archs=(${=KEYLUME_ARCHS:-$(uname -m)})
for arch in $archs; do
  mkdir -p "dist/native/$arch"
  clang -O2 -arch "$arch" -mmacosx-version-min=13.0 apps/macos/rgb-probe.c -framework IOKit -framework CoreFoundation -o "dist/native/$arch/rgb-probe"
  swiftc -module-cache-path "$root/dist/module-cache/$arch" -parse-as-library -O -target "$arch-apple-macosx13.0" apps/macos/Editor.swift -o "dist/native/$arch/Keylume"
done
for executable in rgb-probe Keylume; do
  inputs=()
  for arch in $archs; do inputs+=("dist/native/$arch/$executable"); done
  if (( ${#inputs} == 1 )); then cp "$inputs[1]" "$macos/$executable"; else lipo -create $inputs -output "$macos/$executable"; fi
done
cat > "$bundle/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Keylume</string>
<key>CFBundleIdentifier</key><string>local.mk1300.rgb</string>
<key>CFBundleName</key><string>Keylume</string>
<key>CFBundleDisplayName</key><string>Keylume</string>
<key>CFBundleIconFile</key><string>Keylume.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>$version</string>
<key>CFBundleShortVersionString</key><string>$version</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$macos/rgb-probe"
codesign --force --sign - "$bundle"
codesign --verify --deep --strict "$bundle"
"$macos/Keylume" --check-bundle
# Keep intermediate executables out of the output tree: this bundle is the app.
python3 - <<'PY'
import shutil
shutil.rmtree('dist/native')
PY
