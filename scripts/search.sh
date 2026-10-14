#!/bin/bash
# Alfred Script Filter: lists the contacts matching the text typed after the
# keyword. contacts-cli supplies the contacts as plain JSON, and
# to_script_filter.pl turns them into rows: every row's arg is a phone number (or
# an email, for contacts with no number), which Enter copies and ⌘↩ messages.
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
out=$(NO_COLOR=1 "$bin" search --format json -- "$query" 2>"$errfile")
status=$?

if [ "$status" -ne 0 ] || [ -z "$out" ]; then
  reason=$(head -n 1 "$errfile")
  case "$reason" in
    *"unexpected argument"* | *"invalid value"*) reason="$reason (brew upgrade contacts-cli may fix this)" ;;
  esac
  error_item "contacts-cli failed" "${reason:-No output}"
  exit 0
fi

if ! rows=$(printf '%s' "$out" | /usr/bin/perl "$here/to_script_filter.pl" "$flag" "$query" 2>"$errfile"); then
  error_item "contacts-cli returned something unexpected" "$(head -n 1 "$errfile")"
  exit 0
fi

printf '%s\n' "$rows"
