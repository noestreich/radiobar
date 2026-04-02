#!/bin/bash
# ──────────────────────────────────────────────────────────────────────────────
# RadioBar – Release-Build mit Signierung und Notarisierung
#
# Voraussetzungen:
#   1. Developer ID Application Certificate im Schlüsselbund
#      → developer.apple.com → Certificates → Developer ID Application
#
#   2. Credentials einmalig speichern (interaktive Passworteingabe):
#      xcrun notarytool store-credentials "radiobar-notarize" \
#          --apple-id "du@example.com" \
#          --team-id  "DEINE_TEAM_ID"
#
# Danach einfach aufrufen:
#   ./build-release.sh
# ──────────────────────────────────────────────────────────────────────────────
set -e

APP="RadioBar"
BUNDLE="$APP.app"
ZIP="$APP-notarize.zip"
ENTITLEMENTS="RadioBar.entitlements"
KEYCHAIN_PROFILE="radiobar-notarize"

# Zertifikat automatisch aus dem Schlüsselbund ermitteln
IDENTITY=$(security find-identity -v -p codesigning \
           | grep "Developer ID Application" \
           | head -1 | awk -F'"' '{print $2}')

if [ -z "$IDENTITY" ]; then
    echo "✗ Kein 'Developer ID Application'-Zertifikat im Schlüsselbund gefunden."
    exit 1
fi
echo "  Zertifikat: $IDENTITY"

# ── Kompilieren ────────────────────────────────────────────────────────────────
echo "▶ Kompiliere (release)..."
swift build -c release 2>&1

# ── Bundle zusammenstellen ─────────────────────────────────────────────────────
echo "▶ Erstelle App-Bundle..."
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
mkdir -p "$BUNDLE/Contents/Resources"

cp ".build/release/$APP"                      "$BUNDLE/Contents/MacOS/$APP"
cp "Sources/RadioBar/Resources/Info.plist"    "$BUNDLE/Contents/"
cp "Sources/RadioBar/Resources/AppIcon.icns"  "$BUNDLE/Contents/Resources/AppIcon.icns"

# ── Signieren (Hardened Runtime + Entitlements) ────────────────────────────────
echo "▶ Signiere App..."
codesign \
    --force \
    --deep \
    --options runtime \
    --entitlements "$ENTITLEMENTS" \
    --sign "$IDENTITY" \
    "$BUNDLE"

codesign --verify --deep --strict "$BUNDLE" && echo "  ✓ Signierung OK"

# ── ZIP für Notarisierung ──────────────────────────────────────────────────────
echo "▶ Erstelle ZIP für Notarisierung..."
rm -f "$ZIP"
ditto -c -k --keepParent "$BUNDLE" "$ZIP"

# ── Notarisierung einreichen ───────────────────────────────────────────────────
echo "▶ Sende zur Notarisierung (kann 1–5 Minuten dauern)..."
xcrun notarytool submit "$ZIP" \
    --keychain-profile "$KEYCHAIN_PROFILE" \
    --wait

# ── Staple (Notarisierungsticket einbetten) ────────────────────────────────────
echo "▶ Staple Notarisierungsticket..."
xcrun stapler staple "$BUNDLE"
xcrun stapler validate "$BUNDLE" && echo "  ✓ Staple OK"

# ── Fertiges ZIP für Weitergabe ────────────────────────────────────────────────
FINAL="RadioBar-signed.zip"
rm -f "$FINAL"
ditto -c -k --keepParent "$BUNDLE" "$FINAL"

echo ""
echo "✓ Fertig: $FINAL"
echo "  Zum Testen:  open $BUNDLE"
echo "  Weitergabe:  $FINAL per AirDrop / Mail / Download-Link"
