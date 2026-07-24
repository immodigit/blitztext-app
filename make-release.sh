#!/bin/bash
set -euo pipefail

# Blitztext Release-Pipeline: Developer-ID-Signierung → DMG → Notarisierung →
# Stapling → SHA256 für die Homebrew-Cask.
#
# Voraussetzungen (einmalig einzurichten, siehe homebrew/README.md):
#   1. Apple Developer Program + "Developer ID Application"-Zertifikat in der Keychain
#   2. Notar-Zugang als Keychain-Profil:
#        xcrun notarytool store-credentials "blitztext-notary" \
#          --apple-id "<deine-apple-id>" --team-id "<TEAMID>" --password "<app-spezifisches-pw>"
#
# Verwendung:
#   BLITZTEXT_SIGN_IDENTITY="Developer ID Application: Dein Name (TEAMID)" \
#   BLITZTEXT_NOTARY_PROFILE="blitztext-notary" \
#   ./make-release.sh
#
# Ohne BLITZTEXT_NOTARY_PROFILE wird nur signiert + DMG gebaut (kein Notarize/Staple).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/BlitztextMac"
RESOURCES_SRC="$PROJECT_DIR/Resources"
ENTITLEMENTS="$RESOURCES_SRC/BlitztextMac.entitlements"
APP="$SCRIPT_DIR/Blitztext.app"

SIGN_IDENTITY="${BLITZTEXT_SIGN_IDENTITY:-}"
# Notar-Zugang: entweder ein Keychain-Profil (lokal bequem) ODER Inline-
# Credentials (für CI, wo kein Login-Keychain-Profil existiert).
NOTARY_PROFILE="${BLITZTEXT_NOTARY_PROFILE:-}"
NOTARY_APPLE_ID="${BLITZTEXT_NOTARY_APPLE_ID:-}"
NOTARY_TEAM_ID="${BLITZTEXT_NOTARY_TEAM_ID:-}"
NOTARY_PASSWORD="${BLITZTEXT_NOTARY_PASSWORD:-}"

if [ -z "$SIGN_IDENTITY" ]; then
    echo "❌ BLITZTEXT_SIGN_IDENTITY fehlt."
    echo "   Setze es auf deine \"Developer ID Application: ... (TEAMID)\"-Identität."
    echo "   Verfügbare Identitäten:"
    security find-identity -v -p codesigning | grep "Developer ID Application" || echo "   (keine gefunden – Zertifikat fehlt in der Keychain)"
    exit 1
fi

VERSION="$(grep 'MARKETING_VERSION:' "$PROJECT_DIR/project.yml" | sed 's/.*"\(.*\)".*/\1/' || echo "1.5")"
DMG="$SCRIPT_DIR/Blitztext-$VERSION.dmg"

echo "🔨 [1/6] Baue App-Bundle (Developer-ID-Signierung) ..."
# build-spm.sh baut + signiert bereits mit der übergebenen Identität. Wir
# übersignieren danach mit Hardened Runtime + Timestamp (nötig fürs Notarisieren).
BLITZTEXT_SIGN_IDENTITY="$SIGN_IDENTITY" "$SCRIPT_DIR/build-spm.sh"

echo "🔏 [2/6] Signiere mit Hardened Runtime + sicherem Zeitstempel ..."
# Verschachtelten Code (dylibs, Frameworks, Helfer-Bundles mit Mach-O) zuerst
# signieren – innen nach außen, sonst lehnt der Notar-Service ab.
sign_nested() {
    local target="$1"
    codesign --force --options runtime --timestamp \
        --sign "$SIGN_IDENTITY" "$target"
}

while IFS= read -r -d '' item; do
    # Nur echte Mach-O-Objekte signieren (Resource-Bundles überspringen).
    if file "$item" | grep -q "Mach-O"; then
        sign_nested "$item"
    fi
done < <(find "$APP/Contents" -type f \( -name "*.dylib" -o -name "*.so" \) -print0)

for nested in "$APP"/Contents/Frameworks/* "$APP"/Contents/Resources/*.bundle; do
    [ -e "$nested" ] || continue
    codesign --force --options runtime --timestamp \
        --sign "$SIGN_IDENTITY" "$nested" 2>/dev/null || true
done

# Haupt-App zuletzt, mit Entitlements.
codesign --force --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" \
    --sign "$SIGN_IDENTITY" "$APP"

echo "   ✔︎ Signatur-Prüfung:"
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | sed 's/^/     /'

echo "📀 [3/6] Baue DMG: $DMG"
STAGING="$(mktemp -d)"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname "Blitztext" \
    -srcfolder "$STAGING" \
    -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
rm -rf "$STAGING"

NOTARIZED=false
if [ -n "$NOTARY_PROFILE" ]; then
    echo "📤 [4/6] Reiche DMG zur Notarisierung ein (Keychain-Profil, kann 1–5 min dauern) ..."
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait --timeout 100m
    NOTARIZED=true
elif [ -n "$NOTARY_APPLE_ID" ] && [ -n "$NOTARY_TEAM_ID" ] && [ -n "$NOTARY_PASSWORD" ]; then
    echo "📤 [4/6] Reiche DMG zur Notarisierung ein (Inline-Credentials, kann 1–5 min dauern) ..."
    # --timeout: sauber abbrechen statt vom Job-Timeout gekillt zu werden.
    # Die allererste Team-Submission kann bei Apple ungewöhnlich lange dauern.
    xcrun notarytool submit "$DMG" \
        --apple-id "$NOTARY_APPLE_ID" \
        --team-id "$NOTARY_TEAM_ID" \
        --password "$NOTARY_PASSWORD" \
        --wait --timeout 100m
    NOTARIZED=true
else
    echo "⏭  [4/6] Kein Notar-Zugang gesetzt – überspringe Notarisierung."
    echo "    DMG ist signiert, aber NICHT notarisiert (Gatekeeper blockt beim Nutzer)."
    echo "    Setze BLITZTEXT_NOTARY_PROFILE oder BLITZTEXT_NOTARY_APPLE_ID/TEAM_ID/PASSWORD."
fi

if [ "$NOTARIZED" = true ]; then
    echo "📎 [5/6] Hefte Notar-Ticket an DMG (Stapling) ..."
    xcrun stapler staple "$DMG"

    echo "   ✔︎ Gatekeeper-Prüfung:"
    spctl -a -vv -t install "$DMG" 2>&1 | sed 's/^/     /' || true
fi

SHA="$(shasum -a 256 "$DMG" | awk '{print $1}')"

echo ""
echo "✅ [6/6] Release fertig!"
echo "   DMG:     $DMG"
echo "   Version: $VERSION"
echo "   SHA256:  $SHA"
echo ""
echo "Nächste Schritte:"
echo "  1. GitHub Release mit Tag v$VERSION anlegen und $DMG hochladen:"
echo "       gh release create v$VERSION \"$DMG\" --title \"Blitztext $VERSION\" --notes \"…\""
echo "  2. In homebrew/Casks/blitztext.rb Version + SHA256 setzen:"
echo "       version \"$VERSION\""
echo "       sha256 \"$SHA\""
echo "  3. Cask in dein Tap-Repo (homebrew-blitztext) pushen."
echo ""
