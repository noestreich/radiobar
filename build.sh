#!/bin/bash
set -e

APP="RadioBar"
BUNDLE="$APP.app"

echo "▶ Kompiliere $APP..."
swift build -c release 2>&1

BIN=".build/release/$APP"

echo "▶ Erstelle App-Bundle..."
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
mkdir -p "$BUNDLE/Contents/Resources"

cp "$BIN" "$BUNDLE/Contents/MacOS/$APP"
cp ".build/release/RadioBar_RadioBar.bundle/Contents/Resources/Info.plist" \
   "$BUNDLE/Contents/" 2>/dev/null \
|| cp "Sources/RadioBar/Resources/Info.plist" "$BUNDLE/Contents/"
cp "Sources/RadioBar/Resources/AppIcon.icns" "$BUNDLE/Contents/Resources/AppIcon.icns"

echo "▶ Signiere App (ad-hoc)..."
codesign --force --deep --sign - "$BUNDLE"

echo ""
echo "✓ Fertig: $BUNDLE"
echo ""
echo "  Starten:     open $BUNDLE"
echo "  Installieren: cp -r $BUNDLE /Applications/"
