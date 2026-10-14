#!/bin/bash
# Packages the workflow as dist/Contacts-CLI.alfredworkflow (a zip file that
# Alfred imports when you open it). Requires `zip`.
set -euo pipefail

cd "$(dirname "$0")/.."

version=$(awk '/<key>version<\/key>/ { getline next_line; if (next_line ~ /<string>/) { gsub(/.*<string>|<\/string>.*/, "", next_line); print next_line; exit } }' info.plist)
[ -n "$version" ] || { echo "Could not read the version from info.plist" >&2; exit 1; }

mkdir -p dist
out="dist/Contacts-CLI.alfredworkflow"
rm -f "$out"
zip -qrX "$out" info.plist scripts/lib.sh scripts/search.sh scripts/message.sh scripts/to_script_filter.pl

echo "Built $out (workflow version $version)"
