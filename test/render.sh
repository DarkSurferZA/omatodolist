#!/usr/bin/env bash
# Renders PanelHeader, MainTab and HistoryTab against
# a real, seeded sqlite db, offscreen, and checks that every ActionButton,
# Field, SearchField and Segment is exactly Style.spacing.controlHeight tall
# (the dev's hard rule: a button with an icon must never be taller than a
# plain text button). Exits non-zero if any control fails that check.
#
# Usage: test/render.sh [output-dir]
#
# output-dir defaults to a throwaway directory (plain `npm test` only cares
# about the exit code) — pass one explicitly to keep the PNGs for review.
#
# Builds a throwaway `qs -p` config dir with Commons/Ui symlinked to the
# installed kit and ui/data symlinked to this worktree, and a throwaway
# XDG_DATA_HOME with a seeded scratchpad.db — same pattern as the approved
# prototype's render harness (~/.cache/omatodolist-2026-09-19/proto/run.sh).

set -euo pipefail

out_dir="${1:-$(mktemp -d)}"
mkdir -p "$out_dir"
out_dir="$(cd "$out_dir" && pwd)"

source "$(dirname "$0")/lib/harness.sh"

cat > "$cfg_dir/shell.qml" <<'QML'
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "data" as Data
import "ui" as Ui

ShellRoot {
  id: sr
  property int readyCount: 0
  property bool started: false            // guards the initial-load wait from firing again
  property int activeTab: 0
  property bool failed: false
  property string currentScene: ""
  property int sceneIndex: 0
  readonly property var scenes: Quickshell.env("SCENES").split(",")
  // A scene that finds fewer controls than this measured nothing.
  readonly property var minControls: ({ browse: 9, draft: 8, empty: 5, history: 3, blank: 6 })
  readonly property string outDir: Quickshell.env("OUT_DIR")

  Data.Db {
    id: db
    Component.onCompleted: db.init()
  }

  // Every scene after the first also triggers db signals (a search re-list,
  // a status/history refresh) — only the very first triple-ready should
  // kick off the scene sequence, or a later signal would race settleTimer
  // and call nextScene() again mid-sequence.
  function markReady() {
    if (sr.started) return
    sr.readyCount += 1
    if (sr.readyCount >= 3) {
      sr.started = true
      Qt.callLater(sr.nextScene)
    }
  }

  Connections {
    target: db
    function onItemsUpdated() { sr.markReady() }
    function onHistoryUpdated() { sr.markReady() }
    function onCountsUpdated() { sr.markReady() }
  }

  // Collect every visible ActionButton/Field/SearchField/Segment under
  // `item`, by parsing the QML type name off its toString().
  function walk(item, out) {
    var n = String(item).split("_QMLTYPE")[0].split("(")[0]
    if (/^(ActionButton|Field|SearchField|Segment)$/.test(n) && item.visible)
      out.push({ name: n, height: item.height })
    for (var i = 0; i < item.children.length; ++i) walk(item.children[i], out)
  }

  function checkHeights(sceneName, rootItem) {
    var found = []
    sr.walk(rootItem, found)
    var want = Style.spacing.controlHeight
    var parts = []
    for (var i = 0; i < found.length; ++i) {
      var row = found[i]
      var ok = row.height === want
      if (!ok) sr.failed = true
      parts.push(row.name + "=" + row.height + (ok ? "" : " MISMATCH(want " + want + ")"))
    }
    if (found.length < sr.minControls[sceneName]) {
      sr.failed = true
      parts.push("TOO-FEW-CONTROLS(" + found.length + " < " + sr.minControls[sceneName] + ")")
    }
    console.log("SCENE " + sceneName + " HEIGHTS " + parts.join(" "))
  }

  function nextScene() {
    if (sr.sceneIndex >= sr.scenes.length) {
      console.log(sr.failed ? "RESULT FAIL" : "RESULT OK")
      Qt.exit(sr.failed ? 1 : 0)
      return
    }
    var name = sr.scenes[sr.sceneIndex]
    sr.sceneIndex++
    sr.currentScene = name
    // Reset to a clean base so a scene never inherits the previous one's
    // draft, search text, or keyboard focus (an async focusTitle() queued
    // by the previous scene can otherwise still land here).
    mainTab.draftNew = false
    mainTab.searchText = ""
    mainTab.focusList()
    sr.activeTab = (name === "history") ? 1 : 0
    if (name === "draft") mainTab.startNew("todo")
    else if (name === "empty") mainTab.searchText = "zzz_no_match_xyz"
    settleTimer.restart()
  }

  Timer {
    id: settleTimer
    interval: 500
    repeat: false
    onTriggered: sr.captureScene()
  }

  function captureScene() {
    var name = sr.currentScene
    sr.checkHeights(name, frame)
    frame.grabToImage(function(r) {
      r.saveToFile(sr.outDir + "/" + name + ".png")
      console.log("SHOT " + name + " saved")
      sr.nextScene()
    })
  }

  FloatingWindow {
    implicitWidth: 760
    implicitHeight: 520

    Rectangle {
      id: frame
      x: 0; y: 0; width: 760; height: 520
      color: Color.background

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: Style.space(16)
        spacing: Style.space(12)

        Ui.PanelHeader {
          Layout.fillWidth: true
          db: db
          activeTab: sr.activeTab
        }

        StackLayout {
          Layout.fillWidth: true
          Layout.fillHeight: true
          currentIndex: sr.activeTab

          Ui.MainTab {
            id: mainTab
            db: db
          }
          Ui.HistoryTab {
            id: historyTab
            db: db
          }
        }
      }
    }
  }
}
QML

echo "config dir: $cfg_dir"
echo "output dir: $out_dir"
SCENES=browse,draft,empty,history OUT_DIR="$out_dir" run_qs
sqlite3 "$db" "DELETE FROM items; DELETE FROM history;"
SCENES=blank OUT_DIR="$out_dir" run_qs
