#!/bin/bash
# Alfred Run Script, reached with ⌘↩: opens the transport chosen in the workflow
# settings (--signal, --sms, ...) for the selected number or email. What it
# prints is shown in a notification, so it is always a single short line.
set -u

here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"

target="${1:-}"
flag="${message_flag:---signal}"

if [ -z "$target" ]; then
  echo "Nothing selected to message"
  exit 0
fi

if ! bin=$(find_contacts_cli); then
  echo "contacts-cli not found. $(not_found_message)"
  exit 0
fi

# `message` finds the contact again by this number or email and opens the app.
out=$(NO_COLOR=1 "$bin" message "$flag" -- "$target" 2>&1)
status=$?

if [ "$status" -ne 0 ]; then
  # The reason is on the first line ("Error: Contact 'X' has no phone number...").
  printf '%s\n' "$out" | sed -n '/./{p;q;}'
else
  printf '%s\n' "$out" | tail -n 1
fi
