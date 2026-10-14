#!/bin/bash
# Tests for the workflow's scripts and info.plist. Run with: bash tests/test.sh
#
# The scripts are run for real, against a fake `contacts-cli` that records how it
# was called. Nothing here needs Alfred or the real contacts-cli. Written for
# macOS's bash 3.2, the same shell Alfred uses.
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0

ok() { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; shift; printf '       %s\n' "$@"; }

assert_eq() { # name expected actual
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected: $2" "actual:   $3"; fi
}

assert_contains() { # name haystack needle
  case "$2" in
    *"$3"*) ok "$1" ;;
    *) bad "$1" "expected to contain: $3" "actual: $2" ;;
  esac
}

assert_valid_json() { # name text
  if printf '%s' "$2" | perl -MJSON::PP -e 'local $/; decode_json(<STDIN>)' 2>/dev/null; then
    ok "$1"
  else
    bad "$1" "not valid JSON: $2"
  fi
}

# Reads JSON on stdin and prints a perl expression over it, e.g. '$j->{items}[0]{title}'.
json_get() { perl -MJSON::PP -e 'local $/; my $j = decode_json(<STDIN>); print eval $ARGV[0]' "$1"; }

# ── fake contacts-cli ───────────────────────────────────────────────────────
# Records its arguments (one per line) in $FAKE_LOG and its NO_COLOR setting in
# $FAKE_LOG.env, then prints $FAKE_STDOUT / $FAKE_STDERR and exits $FAKE_EXIT.

FAKE_DIR="$TMP/bin"
mkdir -p "$FAKE_DIR"
FAKE="$FAKE_DIR/contacts-cli"
cat > "$FAKE" <<'FAKE_EOF'
#!/bin/bash
printf '%s\n' "$@" > "$FAKE_LOG"
printf 'NO_COLOR=%s\n' "${NO_COLOR:-}" > "$FAKE_LOG.env"
[ -n "${FAKE_STDERR:-}" ] && printf '%s\n' "$FAKE_STDERR" >&2
[ -n "${FAKE_STDOUT:-}" ] && printf '%s\n' "$FAKE_STDOUT"
exit "${FAKE_EXIT:-0}"
FAKE_EOF
chmod +x "$FAKE"

LOG="$TMP/args.log"

# Runs a script the way Alfred would: a bare environment plus the workflow's
# settings. Extra VAR=value pairs go in the EXTRA array. Sets OUT and STATUS.
EXTRA=()
run() { # script args...
  local script=$1
  shift
  rm -f "$LOG" "$LOG.env"
  OUT=$(env -i PATH="/usr/bin:/bin" HOME="$TMP" FAKE_LOG="$LOG" \
    CONTACTS_CLI_SEARCH_PATH="$TMP/nothing-here" TESTING=1 "${EXTRA[@]}" \
    bash "$ROOT/scripts/$script" "$@" 2>/dev/null)
  STATUS=$?
}

args_logged() { paste -s -d'|' "$LOG"; }

echo "search.sh"

EXTRA=(contacts_cli_path="$FAKE" FAKE_STDOUT='{"items":[]}')
run search.sh alice
assert_eq "calls contacts-cli with the json format, default subtitle and the query" \
  "search|--format|json|--message-subtitle|Message with --signal|--|alice" "$(args_logged)"
assert_eq "prints what contacts-cli printed" '{"items":[]}' "$OUT"
assert_eq "turns colour off" "NO_COLOR=1" "$(cat "$LOG.env")"
assert_eq "exits 0" "0" "$STATUS"

EXTRA=(contacts_cli_path="$FAKE" message_flag=--sms FAKE_STDOUT='{"items":[]}')
run search.sh alice
assert_eq "puts the configured message flag in the command-key subtitle" \
  "search|--format|json|--message-subtitle|Message with --sms|--|alice" "$(args_logged)"

EXTRA=(contacts_cli_path="$FAKE" FAKE_STDOUT='{"items":[]}')
run search.sh
assert_eq "an empty query is passed as an empty string" \
  "search|--format|json|--message-subtitle|Message with --signal|--|" "$(args_logged)"

run search.sh --help
assert_eq "a query that looks like a flag goes after --" \
  "search|--format|json|--message-subtitle|Message with --signal|--|--help" "$(args_logged)"

run search.sh "alice smith"
assert_eq "a query with spaces stays one argument" \
  "search|--format|json|--message-subtitle|Message with --signal|--|alice smith" "$(args_logged)"

mkdir -p "$TMP/with space"
cp "$FAKE" "$TMP/with space/contacts-cli"
EXTRA=(contacts_cli_path="$TMP/with space/contacts-cli" FAKE_STDOUT='{"items":[]}')
run search.sh alice
assert_eq "works when the configured path contains a space" '{"items":[]}' "$OUT"

EXTRA=(CONTACTS_CLI_SEARCH_PATH="$FAKE_DIR" FAKE_STDOUT='{"items":[]}')
run search.sh alice
assert_eq "finds contacts-cli in the Homebrew search path when no path is set" '{"items":[]}' "$OUT"

EXTRA=(FAKE_STDOUT='{"items":[]}')
run search.sh alice
assert_valid_json "not installed: prints valid Script Filter JSON" "$OUT"
assert_eq "not installed: title" "contacts-cli not found" "$(printf '%s' "$OUT" | json_get '$j->{items}[0]{title}')"
assert_contains "not installed: subtitle says how to install" \
  "$(printf '%s' "$OUT" | json_get '$j->{items}[0]{subtitle}')" "brew install quintrino/tap/contacts-cli"
assert_eq "not installed: the row cannot be selected" "0" "$(printf '%s' "$OUT" | json_get '$j->{items}[0]{valid}')"
assert_eq "not installed: exits 0" "0" "$STATUS"

EXTRA=(contacts_cli_path="$TMP/nope")
run search.sh alice
assert_valid_json "bad path setting: prints valid JSON" "$OUT"
assert_eq "bad path setting: names the path" "No executable at $TMP/nope" \
  "$(printf '%s' "$OUT" | json_get '$j->{items}[0]{subtitle}')"

EXTRA=(contacts_cli_path="$FAKE" FAKE_EXIT=2 FAKE_STDERR="error: unexpected argument \"--format\" found")
run search.sh alice
assert_valid_json "failing contacts-cli: prints valid JSON even with quotes in the error" "$OUT"
assert_eq "failing contacts-cli: title" "contacts-cli failed" "$(printf '%s' "$OUT" | json_get '$j->{items}[0]{title}')"
assert_contains "failing contacts-cli: shows the error" \
  "$(printf '%s' "$OUT" | json_get '$j->{items}[0]{subtitle}')" 'unexpected argument "--format" found'
assert_eq "failing contacts-cli: exits 0 so Alfred shows the row" "0" "$STATUS"

EXTRA=(contacts_cli_path="$FAKE" FAKE_STDOUT="")
run search.sh alice
assert_eq "no output at all: also shows a failure row" "contacts-cli failed" \
  "$(printf '%s' "$OUT" | json_get '$j->{items}[0]{title}')"

echo "message.sh"

EXTRA=(contacts_cli_path="$FAKE" FAKE_STDOUT="ok")
run message.sh "+61491570006"
assert_eq "defaults to --signal and puts the number after --" \
  "message|--signal|--|+61491570006" "$(args_logged)"
assert_eq "turns colour off" "NO_COLOR=1" "$(cat "$LOG.env")"

EXTRA=(contacts_cli_path="$FAKE" message_flag=--whatsapp FAKE_STDOUT="ok")
run message.sh "+61491570006"
assert_eq "uses the configured flag" "message|--whatsapp|--|+61491570006" "$(args_logged)"

EXTRA=(contacts_cli_path="$FAKE" message_flag=--email FAKE_STDOUT="ok")
run message.sh "alice@example.com"
assert_eq "an email is passed through the same way" "message|--email|--|alice@example.com" "$(args_logged)"

EXTRA=(contacts_cli_path="$FAKE" FAKE_STDOUT="$(printf 'sgnl://signal.me/#p/+61491570006\n→ Opening Signal for Alice\n→ Opened with Signal Beta')")
run message.sh "+61491570006"
assert_eq "on success shows only the last line" "→ Opened with Signal Beta" "$OUT"
assert_eq "exits 0" "0" "$STATUS"

EXTRA=(contacts_cli_path="$FAKE" FAKE_EXIT=1 FAKE_STDERR="Error: Contact 'Bob Jones' has no phone number on record")
run message.sh "bob@example.com"
assert_eq "on failure shows the reason" "Error: Contact 'Bob Jones' has no phone number on record" "$OUT"
assert_eq "on failure still exits 0 so the notification appears" "0" "$STATUS"

EXTRA=(contacts_cli_path="$FAKE")
run message.sh ""
assert_eq "nothing selected: says so" "Nothing selected to message" "$OUT"
assert_eq "nothing selected: does not call contacts-cli" "no" "$([ -f "$LOG" ] && echo yes || echo no)"

EXTRA=(FAKE_STDOUT="ok")
run message.sh "+61491570006"
assert_contains "not installed: says so" "$OUT" "contacts-cli not found"
assert_contains "not installed: says how to install" "$OUT" "brew install quintrino/tap/contacts-cli"

echo "info.plist"

PLIST="$ROOT/info.plist"

# Every tag opens and closes in order (plutil, when present, does the real lint).
balanced=$(perl -e '
  local $/; my $x = <STDIN>; my @stack;
  while ($x =~ m{<(/?)([A-Za-z]+)([^>]*?)(/?)>}g) {
    my ($close, $name, $self) = ($1, $2, $4);
    next if $self;
    if ($close) { my $top = pop @stack; if (!defined $top || $top ne $name) { print "mismatch at </$name>"; exit } }
    else { push @stack, $name }
  }
  print @stack ? "unclosed <$stack[-1]>" : "ok";
' < "$PLIST")
assert_eq "tags are balanced" "ok" "$balanced"

if command -v plutil >/dev/null 2>&1; then
  if plutil -lint "$PLIST" >/dev/null 2>&1; then ok "plutil -lint passes"; else bad "plutil -lint passes" "$(plutil -lint "$PLIST")"; fi
else
  echo "  skip plutil -lint (not available)"
fi

plist=$(cat "$PLIST")

assert_eq "keyword is 'contacts'" "contacts" \
  "$(perl -0777 -ne 'print $1 if m{<key>keyword</key>\s*<string>([^<]*)</string>}' < "$PLIST")"

copy_uid=$(perl -0777 -ne 'print $1 if m{alfred\.workflow\.output\.clipboard</string>\s*<key>uid</key>\s*<string>([^<]*)</string>}' < "$PLIST")
run_script_uid=$(perl -0777 -ne 'print $1 if m{alfred\.workflow\.action\.script</string>\s*<key>uid</key>\s*<string>([^<]*)</string>}' < "$PLIST")
filter_uid=$(perl -0777 -ne 'print $1 if m{alfred\.workflow\.input\.scriptfilter</string>\s*<key>uid</key>\s*<string>([^<]*)</string>}' < "$PLIST")

connection_targets() { # modifiers: destination uids the Script Filter reaches with that modifier
  FILTER_UID="$filter_uid" MODS="$1" perl -0777 -ne '
    if (m{<key>connections</key>\s*<dict>(.*?)</dict>\s*<key>createdby</key>}s) {
      my $connections = $1;
      while ($connections =~ m{<key>\Q$ENV{FILTER_UID}\E</key>\s*<array>(.*?)</array>}sg) {
        my $array = $1;
        while ($array =~ m{<key>destinationuid</key>\s*<string>([^<]*)</string>\s*<key>modifiers</key>\s*<integer>(\d+)</integer>}g) {
          print "$1\n" if $2 eq $ENV{MODS};
        }
      }
    }' < "$PLIST"
}

assert_eq "Enter (no modifier) goes to Copy to Clipboard" "$copy_uid" "$(connection_targets 0)"
assert_eq "⌘↩ (modifier 1048576) goes to the Run Script" "$run_script_uid" "$(connection_targets 1048576)"

all_uids=$(perl -0777 -ne 'while (m{<key>uid</key>\s*<string>([^<]*)</string>}g) { print "$1\n" }' < "$PLIST" | sort -u)
missing=""
for dest in $(perl -0777 -ne 'while (m{<key>destinationuid</key>\s*<string>([^<]*)</string>}g) { print "$1\n" }' < "$PLIST" | sort -u); do
  printf '%s\n' "$all_uids" | grep -qx "$dest" || missing="$missing $dest"
done
assert_eq "every connection leads to an object that exists" "" "$missing"

assert_contains "defines the message_flag setting" "$plist" "<string>message_flag</string>"
assert_contains "defines the contacts_cli_path setting" "$plist" "<string>contacts_cli_path</string>"

known_flags="--signal --whatsapp --telegram --imessage --sms --facetime --tel --email"
offered=$(perl -0777 -ne 'if (m{<key>pairs</key>\s*<array>(.*)</array>\s*</dict>\s*<key>description</key>}s) { my $p = $1; while ($p =~ m{<array>\s*<string>[^<]*</string>\s*<string>([^<]*)</string>}g) { print "$1\n" } }' < "$PLIST")
unknown=""
for flag in $offered; do
  case " $known_flags " in *" $flag "*) ;; *) unknown="$unknown $flag" ;; esac
done
assert_eq "every dropdown choice is a contacts-cli message flag" "" "$unknown"
assert_eq "the dropdown offers every message flag" "$(printf '%s\n' $known_flags | sort | tr '\n' ' ')" "$(printf '%s\n' $offered | sort | tr '\n' ' ')"
assert_eq "the default message flag is --signal" "--signal" \
  "$(perl -0777 -ne 'print $1 if m{<key>default</key>\s*<string>(--[^<]*)</string>}' < "$PLIST")"

missing=""
for script in $(perl -0777 -ne 'while (m{bash \./scripts/([A-Za-z_]+\.sh)}g) { print "$1\n" }' < "$PLIST" | sort -u); do
  [ -f "$ROOT/scripts/$script" ] || missing="$missing $script"
done
assert_eq "every script the workflow runs exists" "" "$missing"

echo "build.sh"

if command -v zip >/dev/null 2>&1 && command -v unzip >/dev/null 2>&1; then
  cp -R "$ROOT" "$TMP/repo"
  rm -rf "$TMP/repo/dist"
  (cd "$TMP/repo" && bash scripts/build.sh >/dev/null 2>&1)
  listing=$(unzip -Z1 "$TMP/repo/dist/Contacts-CLI.alfredworkflow" 2>/dev/null | sort | tr '\n' ' ')
  assert_eq "the package holds info.plist and the scripts, and nothing else" \
    "info.plist scripts/lib.sh scripts/message.sh scripts/search.sh " "$listing"
else
  echo "  skip build (zip/unzip not available)"
fi

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
