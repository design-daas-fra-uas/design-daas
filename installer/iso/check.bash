#!/usr/bin/env bash
#
# Checks a built install ISO without booting it:
#   - it is a readable ISO with the postinstall files
#   - the VM will trust exactly the host's current public key
#     (/root/.ssh/id_rsa.pub), so the backend can log in
#   - it contains NO private key: anyone with the VM could use it
#
# Usage: ./check.bash <iso-file>     (run as root)

set -uo pipefail

ISO="${1:?Usage: $0 <iso-file>}"
HOSTKEY=/root/.ssh/id_rsa.pub
FAILED=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ok()   { echo "  ok    $*"; }
fail() { echo "  FAIL  $*"; FAILED=1; }

# fingerprint FILE: SHA256 fingerprint of a public key file
fingerprint() { ssh-keygen -lf "$1" 2>/dev/null | awk '{print $2}'; }

echo "Checking $ISO"
[[ -s "$ISO" ]] || { echo "  FAIL  $ISO is missing or empty"; exit 1; }

if xorriso -osirrox on -indev "$ISO" -extract /postinstall "$TMP/postinstall" >/dev/null 2>&1; then
    ok "readable ISO with postinstall/ ($(du -h "$ISO" | cut -f1))"
else
    fail "cannot read postinstall/ from $ISO"
fi

wanted="$(fingerprint "$HOSTKEY")"
got="$(fingerprint "$TMP/postinstall/ssh/authorized_keys")"
if [[ -n "$got" && "$got" == "$wanted" ]]; then
    ok "authorized_keys = host key $wanted"
else
    fail "authorized_keys is '${got:-missing}', host key is $wanted (rebuild the ISO)"
fi

private="$(grep -rlE -- '-----BEGIN [A-Z ]*PRIVATE KEY-----' "$TMP" 2>/dev/null)"
names="$(xorriso -osirrox on -indev "$ISO" -find / -name 'id_rsa' -o -name 'id_ed25519' -o -name 'id_ecdsa' 2>/dev/null)"
if [[ -z "$private" && -z "$names" ]]; then
    ok "no private key in the ISO"
else
    fail "PRIVATE KEY in the ISO: ${private//$TMP/} ${names}"
fi

if (( FAILED )); then
    echo "RESULT: FAILED"
    exit 1
fi
echo "RESULT: all checks passed"
