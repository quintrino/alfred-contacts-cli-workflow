# Shared helpers, sourced by search.sh and message.sh. Written for macOS's
# stock bash 3.2, which is what Alfred runs.

# Directories checked for contacts-cli in addition to $PATH, because Alfred
# starts scripts with a minimal PATH that leaves out Homebrew.
: "${CONTACTS_CLI_SEARCH_PATH:=/opt/homebrew/bin:/usr/local/bin:/home/linuxbrew/.linuxbrew/bin}"

# Prints the path to contacts-cli. Uses the workflow's "contacts-cli path"
# setting if it is filled in, otherwise looks it up.
find_contacts_cli() {
  if [ -n "${contacts_cli_path:-}" ]; then
    if [ -x "$contacts_cli_path" ]; then
      printf '%s\n' "$contacts_cli_path"
      return 0
    fi
    return 1
  fi
  local PATH="$CONTACTS_CLI_SEARCH_PATH:$PATH"
  command -v contacts-cli
}

# Escapes backslashes and double quotes so a single line can sit in a JSON string.
json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

# Prints a Script Filter result with one row that does nothing when selected.
error_item() {
  printf '{"items":[{"title":"%s","subtitle":"%s","valid":false}]}\n' \
    "$(json_escape "$1")" "$(json_escape "$2")"
}

# Explains why contacts-cli could not be found.
not_found_message() {
  if [ -n "${contacts_cli_path:-}" ]; then
    printf 'No executable at %s' "$contacts_cli_path"
  else
    printf 'Install it with: brew install quintrino/tap/contacts-cli'
  fi
}
