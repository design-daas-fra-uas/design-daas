#!/usr/bin/env bash
#
# Prints the line the computer with the browser needs in its hosts file:
# HOST_IP followed by every host name of DAAS_PUBLIC_URL, FRONTEND_PUBLIC_URL
# and AUTH_PUBLIC_URL (the browser opens all of them). Changes nothing.
#
# Usage: ./client-hosts.bash -e <env-file>

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.bash"

ENV_FILE=""
while getopts ":e:" o; do
    case "$o" in
        e) ENV_FILE="$OPTARG" ;;
        *) echo "Usage: $0 -e <env-file>" >&2; exit 1 ;;
    esac
done
[[ -n "$ENV_FILE" ]] || { echo "Usage: $0 -e <env-file>" >&2; exit 1; }
load_stack_env "$ENV_FILE" >/dev/null
[[ -n "${HOST_IP:-}" ]] || die "HOST_IP is not set in $ENV_FILE"

names=()
for url in "$DAAS_PUBLIC_URL" "$FRONTEND_PUBLIC_URL" "$AUTH_PUBLIC_URL"; do
    name="$(url_host "$url")"
    [[ " ${names[*]} " == *" $name "* ]] || names+=("$name")
done

echo "Add this line to the hosts file of every computer with a browser"
echo "(Linux/macOS: /etc/hosts, Windows: C:\\Windows\\System32\\drivers\\etc\\hosts),"
echo "unless your DNS already resolves these names to $HOST_IP:"
echo ""
echo "$HOST_IP  ${names[*]}"
