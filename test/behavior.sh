#!/usr/bin/env bash
# Drives the real MainTab against a seeded sqlite db, offscreen, then asserts
# on the rows that reached the db. Covers the editor's save-on-leave contract.

set -euo pipefail
source "$(dirname "$0")/lib/harness.sh"

cat > "$cfg_dir/shell.qml" <<'QML'
import QtQuick
import Quickshell
import qs.Commons
import "data" as Data
import "ui" as Ui

ShellRoot {
  id: sr
  property int stepIndex: 0
  property bool started: false
  property int writeFailures: 0
  property int lastId: -1
  property int keepId: -1
  property int beforeLastId: -1
  function titleOf(id) {
    for (var i = 0; i < db.items.length; ++i) if (Number(db.items[i].id) === id) return db.items[i].title
    return "missing"
  }
  readonly property var steps: [
    function() { mainTab.pickItem(2); mainTab.focusEditor() },
    function() { mainTab.editorTitle = "EDITED-RENEW"; mainTab.pickItem(3) },
    function() { mainTab.commitIfDirty() },
    function() { console.log("HIGHLIGHTED " + sr.highlighted(mainTab).join(",")) },

    function() { mainTab.pickItem(4); mainTab.focusEditor() },
    function() { mainTab.editorTitle = "EDITED-COFFEE"; mainTab.focusSearch() },
    function() { console.log("FOCUS-AFTER-SEARCH " + mainTab.focusContext + " TITLE4 " + sr.titleOf(4)) },
    function() { mainTab.searchText = "panel" },
    function() { mainTab.searchText = "" },

    function() { mainTab.startNew("note") },
    function() { mainTab.editorTitle = "DRAFT-ON-CLOSE"; mainTab.commitIfDirty() },

    function() { mainTab.pickItem(5); mainTab.focusEditor() },
    function() { mainTab.startNew("todo") },
    function() { mainTab.editorTitle = "DRAFT-BY-ENTER"; mainTab.commitEditor() },

    function() { mainTab.pickItem(1); mainTab.focusEditor() },
    function() { mainTab.editorTitle = "DISCARDED"; mainTab.discardEditor() },
    function() { mainTab.commitIfDirty() },

    function() { mainTab.pickItem(5); mainTab.convertSelected() },

    function() { mainTab.pickItem(3); mainTab.focusEditor() },
    function() { mainTab.editorTitle = ""; mainTab.editorBody = "BODY-KEPT"; mainTab.pickItem(1) },

    function() { sr.lastId = db.items[db.items.length - 1].id; sr.beforeLastId = db.items[db.items.length - 2].id; mainTab.pickItem(sr.lastId) },
    function() { mainTab.armDelete(); mainTab.armDelete() },
    function() { console.log("AFTER-DELETE-LAST " + (mainTab.selectedId === sr.beforeLastId ? "previous-row" : "other:" + mainTab.selectedId)) },

    function() { mainTab.searchText = "zzz_no_match" },
    function() { mainTab.startNew("note") },
    function() { mainTab.editorTitle = "DRAFT-IN-EMPTY-LIST"; db.load() },
    function() { console.log("DRAFT-AFTER-RELOAD " + mainTab.draftNew + " " + mainTab.editorTitle) },
    function() { mainTab.commitEditor(true) },
    function() { mainTab.searchText = "" },

    function() { mainTab.pickItem(1); mainTab.focusEditor() },
    function() { mainTab.editorBody = "QUEUED-BODY"; mainTab.pickItem(2); mainTab.convertSelected(); mainTab.toggleStatus() },

    function() { mainTab.filterType = "todo"; mainTab.searchText = "upstream" },
    function() { sr.keepId = mainTab.selectedId; mainTab.startNew("note") },
    function() { mainTab.editorTitle = "NOTE-HIDDEN-BY-FILTER"; mainTab.commitEditor(true) },
    function() { mainTab.filterType = "all"; mainTab.searchText = "" },
    function() { console.log("SELECTION-AFTER-WIDENING " + (mainTab.selectedId === sr.keepId ? "kept" : "hijacked:" + mainTab.selectedId)) },

    function() { mainTab.pickItem(4); mainTab.focusEditor() },
    function() { mainTab.editorBody = "THROWN-AWAY"; mainTab.discardEditor(); mainTab.startNew("note") },
    function() { console.log("DRAFT-AFTER-DISCARD " + mainTab.draftNew); mainTab.discardEditor() },

    function() { mainTab.cycleFilter() },
    function() { console.log("FILTER-AFTER-F " + mainTab.filterType + " rows=" + db.items.filter(function(i) { return i.type !== "note" }).length) }
  ]

  function highlighted(item) {
    var ids = []
    if (String(item).indexOf("ItemRow") === 0 && item.selected) ids.push(item.item.id)
    for (var i = 0; i < item.children.length; ++i) ids = ids.concat(sr.highlighted(item.children[i]))
    return ids
  }

  Data.Db {
    id: db
    Component.onCompleted: db.init()
  }
  Connections {
    target: db
    function onItemsUpdated() { if (!sr.started) { sr.started = true; stepTimer.start() } }
    function onFailed(message) { sr.writeFailures++; console.log("DB-FAILED " + message) }
  }
  Timer {
    id: stepTimer
    interval: 600
    repeat: true
    onTriggered: {
      if (sr.stepIndex >= sr.steps.length) { console.log("WRITE-FAILURES " + sr.writeFailures); Qt.exit(0); return }
      sr.steps[sr.stepIndex++]()
    }
  }
  FloatingWindow {
    implicitWidth: 760; implicitHeight: 520
    Ui.MainTab { id: mainTab; anchors.fill: parent; db: db }
  }
}
QML

run_qs > "$cfg_dir/qs.log" 2>&1 || { cat "$cfg_dir/qs.log"; echo "qs exited non-zero"; exit 2; }

failures=0
expect() {
  local what="$1" sql="$2" want="$3" got
  got="$(sqlite3 "$db" "$sql")"
  if [[ "$got" == "$want" ]]; then echo "ok   $what"
  else echo "FAIL $what: want '$want', got '$got'"; failures=$((failures + 1)); fi
}

expect "edit is saved to the item it was typed in when another row is clicked" \
  "SELECT title FROM items WHERE id = 2" "EDITED-RENEW"
expect "the clicked row keeps its own title" \
  "SELECT title FROM items WHERE id = 3" "Reply to upstream PR review"
if rg -q "HIGHLIGHTED 3$" "$cfg_dir/qs.log"; then echo "ok   only the clicked row is highlighted after the save reloads the list"
else echo "FAIL highlight after reload: $(rg -o 'HIGHLIGHTED.*' "$cfg_dir/qs.log" || echo none)"; failures=$((failures + 1)); fi
expect "edit is saved when focus moves to the search field" \
  "SELECT title FROM items WHERE id = 4" "EDITED-COFFEE"
logged() {
  local what="$1" pattern="$2"
  if rg -q "$pattern" "$cfg_dir/qs.log"; then echo "ok   $what"
  else echo "FAIL $what: $(rg -o "${pattern%% *}.*" "$cfg_dir/qs.log" | head -3 | tr '\n' ';')"; failures=$((failures + 1)); fi
}
logged "focus stays in the search field, and the edit is already saved before any search" "FOCUS-AFTER-SEARCH search TITLE4 EDITED-COFFEE$"
expect "committing a draft leaves the previously open item untouched" \
  "SELECT title FROM items WHERE id = 5" "Backup scratchpad.db"
expect "draft committed from the title field is saved once" \
  "SELECT COUNT(*) FROM items WHERE title = 'DRAFT-BY-ENTER'" "1"
expect "draft is saved when the panel closes" \
  "SELECT COUNT(*) FROM items WHERE title = 'DRAFT-ON-CLOSE'" "1"
expect "discard leaves the item untouched" \
  "SELECT title FROM items WHERE id = 1" "Ideas for the panel"
expect "convert flips the type and keeps the status" \
  "SELECT type || ':' || status FROM items WHERE id = 5" "note:1"
expect "convert is logged in history" \
  "SELECT COUNT(*) FROM history WHERE action = 'converted' AND title = 'Backup scratchpad.db'" "1"

expect "an emptied title keeps the saved title and still saves the body" \
  "SELECT title || '|' || body FROM items WHERE id = 3" "Reply to upstream PR review|BODY-KEPT"
logged "deleting the last row selects the row above it" "AFTER-DELETE-LAST previous-row$"
logged "a draft survives a reload of an empty filtered list" "DRAFT-AFTER-RELOAD true DRAFT-IN-EMPTY-LIST$"
expect "that draft is saved" "SELECT COUNT(*) FROM items WHERE title = 'DRAFT-IN-EMPTY-LIST'" "1"
expect "three writes fired in one tick all land (edit, convert, toggle)" \
  "SELECT (SELECT body FROM items WHERE id = 1) || '|' || (SELECT type || ':' || status FROM items WHERE id = 2)" "QUEUED-BODY|note:1"
logged "an item added outside the filter does not hijack the selection later" "SELECTION-AFTER-WIDENING kept$"
logged "a draft opened in the same tick as a discard stays open" "DRAFT-AFTER-DISCARD true$"
logged "f cycles the type filter and the list follows" "FILTER-AFTER-F note rows=0$"
logged "no write was rejected during the whole run" "WRITE-FAILURES 0$"

exit $(( failures > 0 ))
