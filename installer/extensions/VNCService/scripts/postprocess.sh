#!/bin/sh
#
# cups-pdf PostProcessing hook (set by create_printer.sh): cups-pdf calls it
# with the path of the PDF it wrote; tell the printer server (server.js),
# which sends the file to the user's session.
#
# cups-pdf sometimes passes a broken byte in the title part of the name
# (".../hosts__\301-job_1.pdf" for the file "hosts__-job_1.pdf"), so look
# the real file up by its folder and job number.

SERVER_URL="http://localhost:8010/api/vnc/file"

DIR="$(dirname "$1")"
JOB="$(printf '%s' "$1" | sed -n 's/.*-job_\([0-9][0-9]*\)\.pdf$/\1/p')"
FILE="$1"
for f in "$DIR"/*-job_"$JOB".pdf; do
    [ -n "$JOB" ] && [ -f "$f" ] && FILE="$f" && break
done

response=$(curl -s -X POST -H "Content-Type: application/json" \
    -d "{\"message\": \"$FILE\"}" "$SERVER_URL")

echo "Response from server: $response"
