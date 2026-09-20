pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "data" as Data
import "ui" as Ui

// Scratchpad popup: "Notes & Todos" (Phase 2) + "History" (Phase 3).
// MainTab + HistoryTab + the Toast live here (not in the tabs) so every cross-
// component reference resolves through this file's "ui" directory import —
// Quickshell ignores single-file imports.
Panel {
    id: root
    moduleName: "io.github.darksurferza.omatodolist"
    // IPC: BarWidget.qml owns the `scratchpad` handler (open/close/show/hide/
    // toggle; Phase 4 adds clearHistory + the data API). The kit Panel's own
    // IpcHandler also registers the same target (Quickshell registers it even
    // with manageIpc:false / empty ipcTarget) — the shell logs a "will not be
    // used" warning against BarWidget's handler, exactly like every other
    // kit-based plugin including omaplug and the first-party panels. It is
    // benign while both handlers dispatch to the same open/close/toggle
    // functions; Phase 4 must implement the richer API on the winning handler
    // (the Panel-side one).
    ipcTarget: "scratchpad"
    manageIpc: false

    property var anchorItem: null
    property var hostWidget: null
    readonly property var barIdentity: hostWidget || root

    // Data layer (Phase 1). Own instance + file watcher (spec §4); reopening
    // the panel re-loads as a safety net on top of the watcher.
    Data.Db {
        id: db
        Component.onCompleted: db.init()
    }
    onOpenedChanged: {
        if (!root.opened) {
            mainTab.commitIfDirty()
            return
        }
        db.load()
        root.resetTabFocus()
        focusPrimeTimer.restart()
    }
    onActiveTabChanged: {
        mainTab.commitIfDirty()
        root.resetTabFocus()
    }

    // The popup surface maps a beat after `opened` flips (layer-shell focus
    // negotiation), so re-prime keyboard focus on a short retry like the
    // first-party panels do — otherwise the first keystrokes can land nowhere.
    Timer {
        id: focusPrimeTimer
        interval: 120
        repeat: false
        onTriggered: if (root.opened) root.resetTabFocus()
    }

    // Give keyboard focus to whichever tab is showing (the reopen safety net
    // above supersedes focusing only tab 0).
    function resetTabFocus() {
        if (root.activeTab === 0) mainTab.resetFocus()
        else historyTab.resetFocus()
    }

    readonly property color contentForeground: bar ? bar.barForeground : Color.foreground

    property int activeTab: 0

    // The popup card. The kit Panel is only the state machine (open/close/
    // toggle IPC); without a popup window nothing is ever drawn, so the bar
    // button hovered but clicks only flipped `opened` invisibly. KeyboardPanel
    // binds `open` to the same controller state, so the button (and IPC) stays
    // the source of truth while the card fades in under the icon. `owner` is
    // the bar widget (not this panel) so popout coordination and the bar's
    // open-panel indicator compare against slot.activeItem correctly.
    KeyboardPanel {
        id: panel
        anchorItem: root.anchorItem
        owner: root.barIdentity
        bar: root.bar
        open: root.opened
        contentWidth: panel.fittedContentWidth(Style.space(760))
        contentHeight: panel.fittedContentHeight(Style.space(520))

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Style.space(16)
            spacing: Style.space(12)

            TabBar {
                id: tabBar
                Layout.fillWidth: true

                TabButton {
                    text: "Notes & Todos"
                    onClicked: root.activeTab = 0
                    focusPolicy: Qt.NoFocus
                }
                TabButton {
                    text: "History"
                    onClicked: root.activeTab = 1
                    focusPolicy: Qt.NoFocus
                }
            }

            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: root.activeTab

                Ui.MainTab {
                    id: mainTab
                    db: db
                    toast: toast
                    foreground: root.contentForeground
                    onCloseRequested: root.close()
                }

                // History — read-only mutation log (spec §3.3).
                Ui.HistoryTab {
                    id: historyTab
                    db: db
                    toast: toast
                    foreground: root.contentForeground
                    onCloseRequested: root.close()
                }
            }
        }

        // Transient confirmation line (delete/status/save feedback).
        Ui.Toast {
            id: toast
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Style.spacing.panelGap
            z: 10
        }
    }
}
