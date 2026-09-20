#!/usr/bin/env bash
# Leave the panel on the "Notes & Todos" tab before running: the active tab
# survives a close, `n` does nothing on History, and the script cannot read
# which tab is up.

set -euo pipefail

shell_path="${OMARCHY_PATH:-/usr/share/omarchy}/shell"
db="${XDG_DATA_HOME:-$HOME/.local/share}/omarchy/scratchpad.db"
failures=0

ipc() { qs -p "$shell_path" ipc call scratchpad "$@"; }

titles() { sqlite3 "$db" "SELECT group_concat(title, '|') FROM items;"; }

has_title() { sqlite3 "$db" "SELECT COUNT(*) FROM items WHERE title = '$1';"; }

draft() {
  ipc open >/dev/null
  sleep 1.5
  wtype "n"; sleep 0.4
  wtype "$1"; sleep 0.4
  wtype -k Return; sleep 0.4
  wtype "body of $1"; sleep 0.4
}

check() {
  local title="$1" how="$2"
  if [[ $(has_title "$title") == "1" ]]; then
    echo "ok   $how — '$title' persisted"
  else
    echo "FAIL $how — '$title' never reached the db (rows: $(titles))"
    failures=$((failures + 1))
  fi
}

command -v wtype >/dev/null || { echo "wtype is required"; exit 2; }
[[ $(ipc ping) == "ok" ]] || { echo "plugin ipc not answering on target 'scratchpad'"; exit 2; }

draft "repro-enter-$$"
wtype -k Return; sleep 1.2
check "repro-enter-$$" "Enter in the body"

ipc close >/dev/null; sleep 0.8
draft "repro-close-$$"
ipc close >/dev/null; sleep 1.2
check "repro-close-$$" "panel closed while drafting"

exit $(( failures > 0 ))
