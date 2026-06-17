#!/bin/bash
set -e

# Run this from the folder that contains the four .swift files.
APP="VolumeLite"
BUNDLE_ID="com.local.volumelite"
MIN_OS="13.0"
ARCH="$(uname -m)"          # arm64 (Apple Silicon) or x86_64 (Intel)

SRC="VolumeLiteApp.swift AppDelegate.swift GlobalScrollMonitor.swift VolumeController.swift VolumeHUD.swift"

# 1. Compile the sources into a single executable.
xcrun swiftc $SRC \
  -o "$APP" \
  -target "${ARCH}-apple-macos${MIN_OS}" \
  -O

# 2. Assemble the .app bundle.
APPDIR="${APP}.app"
rm -rf "$APPDIR"
mkdir -p "$APPDIR/Contents/MacOS"
mv "$APP" "$APPDIR/Contents/MacOS/$APP"

cat > "$APPDIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>                  <string>${APP}</string>
    <key>CFBundleDisplayName</key>           <string>Volume Lite</string>
    <key>CFBundleIdentifier</key>            <string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key>            <string>${APP}</string>
    <key>CFBundlePackageType</key>           <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key> <string>6.0</string>
    <key>CFBundleShortVersionString</key>    <string>1.0</string>
    <key>CFBundleVersion</key>               <string>1</string>
    <key>LSMinimumSystemVersion</key>        <string>${MIN_OS}</string>
    <key>NSPrincipalClass</key>              <string>NSApplication</string>
    <key>LSUIElement</key>                   <true/>
</dict>
</plist>
PLIST

# 3. Ad-hoc code sign so macOS will grant it Accessibility access.
codesign --force --deep --sign - "$APPDIR"

echo "Built ${APPDIR}"
echo "Run it with:  open ./${APPDIR}    (or move it to /Applications)"
