pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.Commons
import "Icons.js" as Icons
import "Item.js" as ItemJs

// "History" tab: a read-only mutation log rendered as a table of
// `type | title | action | timestamp` rows (newest-first, from db.history).
// Title and row count live in Panel's tab Segment, not here. The Toast is
// owned by Panel.qml and injected here.
Item {
    id: root

    property QtObject db: null              // Panel's Data.Db instance
    property var toast: null                // ui/Toast instance (Panel-owned)
    property color foreground: Color.foreground
    property color accent: Color.accent

    signal closeRequested()                 // Esc in the list closes the panel

    property int selectedId: -1
    property int deleteArmId: -1            // -1 = not armed
    readonly property bool deleteArmed: root.deleteArmId >= 0
    readonly property bool clearButtonEnabled: root.db ? root.db.history.length > 0 : false

    readonly property var rowList: root.db ? (root.db.history || []) : []
    readonly property int selectedIndex: ItemJs.indexOfId(root.rowList, root.selectedId)
    readonly property var selectedRow: root.selectedIndex >= 0 ? root.rowList[root.selectedIndex] : null

    // Column widths shared by the header and every delegate so cells stay in
    // vertical alignment (title is the only elastic column).
    readonly property int colTypeW: Style.space(34)
    readonly property int colActionW: Style.space(76)
    readonly property int colTsW: Style.space(128)


    // Unix seconds -> "YYYY-MM-DD HH:MM".
    function formatTs(ts) {
        var n = Number(ts)
        if (!isFinite(n) || n <= 0) return "--"
        var d = new Date(n * 1000)
        function p(x) { return (x < 10 ? "0" : "") + x }
        return d.getFullYear() + "-" + p(d.getMonth() + 1) + "-" + p(d.getDate())
            + " " + p(d.getHours()) + ":" + p(d.getMinutes())
    }

    // Action scan-the-log colors: deletions in urgent, completions in accent.
    function actionColor(action) {
        var a = String(action || "")
        if (a === "deleted") return Color.urgent
        if (a === "completed") return root.accent
        return Util.alpha(root.foreground, 0.75)
    }

    function focusList() { pump.forceActiveFocus() }
    function resetFocus() {
        root.cancelDelete()
        root.focusList()
    }

    function moveSelection(delta) {
        var rows = root.rowList
        var n = rows.length
        if (n === 0) return
        var cur = root.selectedIndex
        var next = Math.max(0, Math.min(n - 1, cur + delta))
        if (cur < 0 || next === cur) return
        root.selectedId = rows[next].id
        listView.positionViewAtIndex(next, ListView.Center)
    }

    function armDelete() {
        if (!root.db || !root.selectedRow) return
        if (root.deleteArmed && root.deleteArmId === root.selectedId) {
            root.deleteArmId = -1
            deleteArmTimer.stop()
            root.db.deleteHistory(root.selectedId)
            return
        }
        root.deleteArmId = root.selectedId
        deleteArmTimer.restart()
        if (root.toast) root.toast.show("Deleting — press d again to confirm")
    }
    function cancelDelete() {
        root.deleteArmId = -1
        deleteArmTimer.stop()
    }
    function clearHistory() {
        if (!root.db) return
        root.cancelDelete()
        root.db.clearHistory()
    }

    function onKey(event) {
        if (event.key === Qt.Key_Down || event.key === Qt.Key_J || event.text === "j") {
            root.moveSelection(1); event.accepted = true
        } else if (event.key === Qt.Key_Up || event.key === Qt.Key_K || event.text === "k") {
            root.moveSelection(-1); event.accepted = true
        } else if (event.text === "d") {
            root.armDelete(); event.accepted = true
        } else if (event.text === "c") {
            root.clearHistory(); event.accepted = true
        } else if (event.key === Qt.Key_Escape) {
            if (root.deleteArmed) { root.cancelDelete(); event.accepted = true }
            else { root.closeRequested(); event.accepted = true }
        }
    }

    // Keep a valid selection after refreshes (watcher/via db): when the
    // deleted/cleared row is gone, fall back to the newest row.
    function onHistoryChanged() {
        var rows = root.rowList
        if (rows.length === 0) {
            root.selectedId = -1
            root.cancelDelete()
            return
        }
        if (ItemJs.indexOfId(rows, root.selectedId) < 0) {
            root.selectedId = rows[0].id
            if (root.selectedIndex >= 0) listView.positionViewAtIndex(root.selectedIndex, ListView.Center)
        }
    }

    Item {
        id: pump
        anchors.fill: parent
        focus: true
        Keys.onPressed: function(event) { root.onKey(event) }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Style.spacing.sm

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Style.spacing.controlPaddingX
            Layout.rightMargin: Style.spacing.controlPaddingX
            spacing: Style.spacing.sm

            Text { Layout.preferredWidth: root.colTypeW; text: "type"; color: Util.alpha(root.foreground, 0.62); font.family: Style.font.family; font.pixelSize: Style.font.caption }
            Text { Layout.fillWidth: true; text: "title"; elide: Text.ElideRight; color: Util.alpha(root.foreground, 0.62); font.family: Style.font.family; font.pixelSize: Style.font.caption }
            Text { Layout.preferredWidth: root.colActionW; text: "action"; color: Util.alpha(root.foreground, 0.62); font.family: Style.font.family; font.pixelSize: Style.font.caption }
            Text { Layout.preferredWidth: root.colTsW; text: "timestamp"; color: Util.alpha(root.foreground, 0.62); font.family: Style.font.family; font.pixelSize: Style.font.caption }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Util.alpha(root.foreground, 0.10)
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Text {
                anchors.centerIn: parent
                visible: listView.count === 0
                text: "No history entries yet —\nmutations from the Items tab appear here"
                horizontalAlignment: Text.AlignHCenter
                color: Util.alpha(root.foreground, 0.5)
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                lineHeight: 1.6
            }

            ListView {
                id: listView
                anchors.fill: parent
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                keyNavigationEnabled: false
                spacing: Style.spacing.xxs
                model: root.rowList

                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: listView.width
                    height: rowRow.implicitHeight + Style.space(10)
                    radius: Style.cornerRadius
                    color: Number(modelData.id) === root.selectedId
                        ? Style.selectedFillFor(root.foreground, root.accent)
                        : "transparent"

                    RowLayout {
                        id: rowRow
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: Style.spacing.controlPaddingX
                        anchors.rightMargin: Style.spacing.controlPaddingX
                        spacing: Style.spacing.sm

                        Text {
                            Layout.preferredWidth: root.colTypeW
                            text: modelData.type === "todo" ? Icons.boxOff : Icons.note
                            color: Number(modelData.id) === root.selectedId
                                ? Style.selectedStateColor(root.foreground, root.accent)
                                : Util.alpha(root.foreground, 0.75)
                            font.family: Style.font.family
                            font.pixelSize: Style.font.icon
                        }

                        Text {
                            Layout.fillWidth: true
                            text: modelData.title
                            elide: Text.ElideRight
                            color: Number(modelData.id) === root.selectedId
                                ? Style.selectedStateColor(root.foreground, root.accent)
                                : root.foreground
                            font.family: Style.font.family
                            font.pixelSize: Style.font.body
                        }

                        Text {
                            Layout.preferredWidth: root.colActionW
                            text: modelData.action
                            color: root.actionColor(modelData.action)
                            font.family: Style.font.family
                            font.pixelSize: Style.font.bodySmall
                        }

                        Text {
                            Layout.preferredWidth: root.colTsW
                            text: root.formatTs(modelData.ts)
                            color: Util.alpha(root.foreground, 0.62)
                            font.family: Style.font.family
                            font.pixelSize: Style.font.bodySmall
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton
                        onClicked: {
                            root.selectedId = modelData.id
                            root.cancelDelete()
                            root.focusList()
                            listView.positionViewAtIndex(index, ListView.Center)
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Util.alpha(root.foreground, 0.10)
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Style.spacing.md

            HintBar {
                Layout.fillWidth: true
                foreground: root.foreground
                urgent: root.deleteArmed
                hints: root.deleteArmed
                    ? [["d", "press again to delete"]]
                    : [["j/k", "move"], ["d d", "delete"], ["c", "clear"], ["Esc", "close"]]
            }

            ActionButton {
                id: clearButton
                text: "Clear history"
                bordered: true
                enabled: root.clearButtonEnabled
                opacity: root.clearButtonEnabled ? 1 : 0.5
                foreground: root.foreground
                accent: root.accent
                onClicked: { root.clearHistory(); root.focusList() }
            }
        }
    }

    Timer {
        id: deleteArmTimer
        interval: 2000
        onTriggered: root.deleteArmId = -1
    }

    Connections {
        target: root.db
        function onHistoryChanged() { root.onHistoryChanged() }
        function onHistoryRowDeleted(id) {
            var idx = ItemJs.indexOfId(root.rowList, Number(id))
            var title = idx >= 0 ? root.rowList[idx].title : "entry"
            if (root.toast) root.toast.show("Deleted — " + title)
        }
        function onHistoryCleared() {
            if (root.toast) root.toast.show("History cleared")
        }
        function onFailed(message) {
            if (root.toast) root.toast.show("Error: " + String(message || "unknown"), true)
        }
    }

    Component.onCompleted: root.focusList()
}