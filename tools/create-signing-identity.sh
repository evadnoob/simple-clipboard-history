#!/bin/bash
# Create the self-signed code signing identity that bundle.sh uses, in the login keychain. Run once per machine.
#   bash tools/create-signing-identity.sh ["identity name", default "evadnoob Local Code Signing"]
#
# Why: an ad-hoc signature (codesign -s -) changes with every build, so macOS treats each build as a new app and
# drops its Accessibility permission. A signature from a fixed certificate keeps the same designated requirement
# (bundle identifier and certificate), so permissions survive rebuilds.
#
# The certificate does not need to be trusted for codesign to use it; `security find-identity` lists it with
# CSSMERR_TP_NOT_TRUSTED, which is expected. The private key exists only in the keychain afterwards.
# To remove it: security delete-identity -c "evadnoob Local Code Signing"
set -euo pipefail
name=${1:-evadnoob Local Code Signing}
if security find-identity -p codesigning | grep -qF "\"$name\""; then
    echo "The identity \"$name\" already exists:"
    security find-identity -p codesigning | grep -F "\"$name\""
    exit 0
fi
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
cd "$dir"
/usr/bin/openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem -days 3650 -nodes \
    -subj "/CN=$name" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    -addext "basicConstraints=critical,CA:false"
/usr/bin/openssl pkcs12 -export -inkey key.pem -in cert.pem -out identity.p12 -passout pass:temporary
security import identity.p12 -k "$HOME/Library/Keychains/login.keychain-db" -P temporary -T /usr/bin/codesign
security find-identity -p codesigning | grep -F "\"$name\""
