#!/bin/sh
#
# cups-pdf PostProcessing hook (set by create_printer.sh): cups-pdf calls it
# with the path of the PDF it wrote; tell the printer server (server.js),
# which sends the file to the user's session.
#
# cups-pdf sometimes passes a broken byte in the title part of the name
# (".../hosts__\301-job_1.pdf" for the file "hosts__-job_1.pdf"), so when
# that name does not exist, look the real file up in the printer's folder:
# by its job number when the name has one ("-job_N", depends on the driver
# file), else the newest PDF there (the one just written).

SERVER_URL="http://localhost:8010/api/vnc/file"

DIR="$(dirname "$1")"
FILE="$1"
if [ ! -f "$FILE" ]; then
    JOB="$(printf '%s' "$1" | sed -n 's/.*-job_\([0-9][0-9]*\)\.pdf$/\1/p')"
    for f in "$DIR"/*-job_"$JOB".pdf; do
        [ -n "$JOB" ] && [ -f "$f" ] && FILE="$f" && break
    done
fi
if [ ! -f "$FILE" ]; then
    FILE="$(ls -t "$DIR"/*.pdf 2>/dev/null | head -n1)"
fi

response=$(curl -s -X POST -H "Content-Type: application/json" \
    -d "{\"message\": \"$FILE\"}" "$SERVER_URL")

echo "Response from server: $response"
