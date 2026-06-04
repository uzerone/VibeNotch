#!/usr/bin/env bash
# One-time setup: creates a self-signed code-signing certificate and imports
# it into the login keychain. Once installed, build-dmg.sh signs VibeNotch
# with this stable identity, so macOS treats every rebuild as the same app
# and a single "Always Allow" on the Keychain prompt persists forever.
#
# Idempotent — safe to re-run; bails out if the identity already exists.
set -euo pipefail

IDENTITY="VibeNotch Self-Signed"
LOGIN_KC="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning 2>/dev/null | grep -F "$IDENTITY" >/dev/null; then
    echo "✅ Signing identity '$IDENTITY' is already installed."
    echo "   You can run ./scripts/build-dmg.sh now."
    exit 0
fi

echo "==> Generating self-signed code-signing certificate"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/ext.cnf" <<EOF
[req]
distinguished_name = req_dn
prompt = no
x509_extensions = v3_codesign

[req_dn]
CN = $IDENTITY

[v3_codesign]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$TMP/key.pem" \
    -out "$TMP/cert.pem" \
    -days 3650 \
    -config "$TMP/ext.cnf" >/dev/null 2>&1

# Bundle key + cert into PKCS#12 for keychain import. macOS keychain wants
# the legacy PKCS#12 format; openssl 3 defaults to a newer format that
# imports as an opaque blob with no usable identity.
# macOS `security import` only accepts PKCS#12 archives that use SHA-1 MAC
# and 3DES encryption. Newer openssl defaults to SHA-256 + AES which fails
# with a misleading "MAC verification failed". A non-empty password works
# more reliably than empty across openssl versions; we'll strip it on import.
P12_PASS="vibenotch"
openssl pkcs12 -export \
    -inkey "$TMP/key.pem" \
    -in "$TMP/cert.pem" \
    -name "$IDENTITY" \
    -out "$TMP/cert.p12" \
    -passout "pass:$P12_PASS" \
    -macalg sha1 \
    -keypbe PBE-SHA1-3DES \
    -certpbe PBE-SHA1-3DES \
    -legacy >/dev/null 2>&1

echo "==> Importing into login keychain"
# -A grants every process access to the private key without a per-app prompt,
# which is what we want so codesign and CI can sign non-interactively.
security import "$TMP/cert.p12" \
    -k "$LOGIN_KC" \
    -A \
    -P "$P12_PASS" >/dev/null

# Verify codesign can actually see it
if ! security find-identity -p codesigning 2>/dev/null | grep -F "$IDENTITY" >/dev/null; then
    echo "❌ Import succeeded but codesign can't find the identity. Try restarting your terminal." >&2
    exit 1
fi

echo "✅ Installed signing identity '$IDENTITY'"
echo "   Next: ./scripts/build-dmg.sh"
echo
echo "Note: This cert is NOT trusted by Gatekeeper — first launch of the .app"
echo "still needs a right-click → Open. But macOS's Keychain ACL now treats"
echo "every VibeNotch rebuild as the same app, so you only need to click"
echo "\"Always Allow\" once on the Claude Code-credentials prompt."
