#!/usr/bin/env bash
# Creates a self-signed "NotchDeck Local" code-signing identity in the login keychain.
# Signing every build with the same identity keeps macOS permissions (Accessibility, Automation)
# attached to the app across rebuilds; ad-hoc signatures change with every build.
set -euo pipefail
NAME="NotchDeck Local"
if security find-identity -p codesigning | grep -q "$NAME"; then
    echo "\"$NAME\" already exists"; exit 0
fi
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cat > "$WORK/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$WORK/cert.cnf" \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null
openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -name "$NAME" \
    -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 -passout pass:notchdeck -out "$WORK/id.p12" 2>/dev/null
security import "$WORK/id.p12" -k ~/Library/Keychains/login.keychain-db -P notchdeck -T /usr/bin/codesign
echo "Created \"$NAME\""
