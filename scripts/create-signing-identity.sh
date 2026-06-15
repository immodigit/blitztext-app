#!/bin/bash
set -euo pipefail

# Erzeugt eine stabile, selbstsignierte Code-Signing-Identität für die lokale
# Entwicklung und importiert sie in den Login-Schlüsselbund.
#
# Warum: Der lokale Build ist sonst ad-hoc signiert und bekommt bei JEDEM Build
# eine neue Signatur. macOS bindet die Bedienungshilfen-Freigabe und den
# Keychain-Zugriff (OpenAI API Key) an die Signatur — nach jedem Rebuild wären
# beide ungültig. Mit einer stabilen Identität bleibt die Signatur konstant,
# also überleben Freigabe und Keychain-Zugriff alle künftigen Builds.
#
# build-spm.sh erkennt diese Identität automatisch und signiert damit.
# Einmalig ausführen:  ./scripts/create-signing-identity.sh

IDENTITY_NAME="${BLITZTEXT_SIGN_IDENTITY:-Blitztext Local Dev}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$IDENTITY_NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "✅ Identität \"$IDENTITY_NAME\" existiert bereits. Nichts zu tun."
    exit 0
fi

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

# Selbstsigniertes Zertifikat mit Code-Signing-Verwendung erzeugen.
cat > "$WORKDIR/cert.cnf" <<EOF
[ req ]
distinguished_name = dn
x509_extensions = v3
prompt = no
[ dn ]
CN = $IDENTITY_NAME
[ v3 ]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

echo "🔐 Erzeuge selbstsigniertes Zertifikat \"$IDENTITY_NAME\" (10 Jahre gültig) ..."
openssl req -x509 -newkey rsa:2048 \
    -keyout "$WORKDIR/key.pem" -out "$WORKDIR/cert.pem" \
    -days 3650 -nodes -config "$WORKDIR/cert.cnf" >/dev/null 2>&1

# In PKCS#12 bündeln. LibreSSL (macOS) erzeugt mit leerem Passwort ein p12,
# das `security import` nicht verifizieren kann — daher Transport-Passwort.
TRANSPORT_PW="blitztext-import"
openssl pkcs12 -export \
    -inkey "$WORKDIR/key.pem" -in "$WORKDIR/cert.pem" \
    -out "$WORKDIR/identity.p12" -passout "pass:$TRANSPORT_PW" \
    -name "$IDENTITY_NAME" >/dev/null 2>&1

echo "📥 Importiere in den Login-Schlüsselbund (macOS fragt evtl. nach deinem Passwort) ..."
# -T /usr/bin/codesign erlaubt codesign den Zugriff auf den privaten Schlüssel,
# damit beim Bauen kein Keychain-Prompt erscheint.
security import "$WORKDIR/identity.p12" \
    -k "$KEYCHAIN" -P "$TRANSPORT_PW" -T /usr/bin/codesign

echo ""
echo "✅ Fertig. \"$IDENTITY_NAME\" ist eingerichtet."
echo "   build-spm.sh signiert ab jetzt automatisch damit."
echo "   Beim ersten Build kann macOS einmal nach dem Keychain-Zugriff fragen -> \"Always Allow\"."
echo ""
echo "   Falls eine alte Freigabe noch hakt, einmalig zuruecksetzen:"
echo "     tccutil reset Accessibility app.blitztext.mac"
