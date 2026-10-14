#!/bin/bash
# Alfred Script Filter: prints the contacts matching the text typed after the
# keyword, as Script Filter JSON. Every row's arg is the phone number (or the
# email, for contacts with no number), which Enter copies and ⌘↩ messages.
set -u

here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"

query="${1:-}"
flag="${message_flag:---signal}"

if ! bin=$(find_contacts_cli); then
  error_item "contacts-cli not found" "$(not_found_message)"
  exit 0
fi

errfile=$(mktemp) || exit 1
trap 'rm -f "$errfile"' EXIT

# `--` keeps a query that starts with a dash from being read as a flag.
out=$(NO_COLOR=1 "$bin" search --format alfred \
  --message-subtitle "Message with $flag" -- "$query" 2>"$errfile")
status=$?

if [ "$status" -ne 0 ] || [ -z "$out" ]; then
  error_item "contacts-cli failed" \
    "$(head -n 1 "$errfile") (brew upgrade contacts-cli may fix this)"
  exit 0
fi

printf '%s\n' "$out"
