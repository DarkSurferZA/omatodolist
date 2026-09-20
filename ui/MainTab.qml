pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "Item.js" as ItemJs

// Keyboard map:
//   list:   j/k or ↑/↓ move · Enter/l/→/Tab edit the selected item
//           · n new draft · space/c toggle status · d delete (double-press
//           to confirm) · / focus search · f cycles All/Notes/Todos
//           · Esc closes the panel
//   editor: fields own printable keys · Tab title→body, body→save+list
//           · Enter in body saves · Esc saves (auto-save on leaving)
//           · `t` on an empty draft title toggles note/todo
//   search: Esc/Shift+Tab return to the list
Item {
    id: root

    property QtObject db: null              // Panel's Data.Db instance
    property var toast: null                // ui/Toast instance (Panel-owned)
    property color foreground: Color.foreground
    property color accent: Color.accent

    signal closeRequested()                 // Esc in the list closes the panel

    property string filterType: "all"       // all | note | todo
    property int selectedId: -1
    property bool draftNew: false           // right pane holds a new-item draft
    property string draftType: "note"       // draft's type ('note' | 'todo')
    property int deleteArmId: -1            // -1 = not armed
    property int nowSeconds: Math.floor(Date.now() / 1000)

    readonly property bool deleteArmed: root.deleteArmId >= 0 && root.deleteArmId === root.selectedId
    property alias searchText: searchField.text
    property alias editorTitle: editorPane.titleText
    property alias editorBody: editorPane.bodyText

    property int _selectAfterReload: -1
    property int _quietSaveId: -1

    readonly property bool editorFocused: editorPane.titleFocused || editorPane.bodyFocused
    readonly property string focusContext: {
        if (searchField.activeFocus) return "search"
        if (root.editorFocused) return root.draftNew ? "draft" : "editor"
        return "list"
    }

    // Focus hops title -> body through a tick with neither focused, so the
    // save waits one turn and re-checks. Nothing is scheduled for a blur that
    // leaves nothing to save, or it would land on a draft opened meanwhile.
    onEditorFocusedChanged: {
        if (root.editorFocused || !(root.draftNew || editorPane.dirty)) return
        Qt.callLater(function() { if (!root.editorFocused) root.commitIfDirty() })
    }

    readonly property var hintSets: ({
        list: [["j/k", "move"], ["Enter", "edit"], ["n", "new"], ["Space", "toggle"],
            ["d d", "delete"], ["/", "search"], ["f", "filter"], ["Esc", "close"]],
        search: [["Enter", "to list"], ["Esc", "clear"]],
        editor: [["Tab", "next field"], ["Enter", "save"], ["Shift+Enter", "new line"], ["Esc", "save and back"]],
        draft: [["Tab", "next field"], ["Enter", "save"], ["Shift+Enter", "new line"], ["Esc", "save and back"], ["t", "note/todo"]],
        deleteArmed: [["d", "press again to delete"]]
    })
    readonly property var hints: root.deleteArmed ? root.hintSets.deleteArmed : root.hintSets[root.focusContext]

    onSelectedIdChanged: {
        if (root.draftNew) return
        root.saveEdit()
        root.refillEditor()
    }

    readonly property var itemList: root.db ? (root.db.items || []) : []
    readonly property int selectedIndex: ItemJs.indexOfId(root.itemList, root.selectedId)
    readonly property var selectedItem: root.selectedIndex >= 0 ? root.itemList[root.selectedIndex] : null
    readonly property bool _filtered: root.filterType !== "all" || root.searchText.trim() !== ""

    function toggleStatus() {
        if (!root.db || !root.selectedItem) return
        root.db.setStatus(root.selectedItem.id, ItemJs.isDone(root.selectedItem) ? 0 : 1)
    }
    function convertSelected() {
        if (!root.db || !root.selectedItem) return
        root.db.convertType(root.selectedItem.id)
    }
    function copySelected() {
        if (!root.selectedItem) return
        var title = String(root.selectedItem.title || "")
        var body = String(root.selectedItem.body || "")
        Quickshell.clipboardText = body === "" ? title : (title + "\n\n" + body)
        if (root.toast) root.toast.show("Copied")
    }
    function armDelete() {
        if (!root.db || !root.selectedItem) return
        if (root.deleteArmed && root.deleteArmId === root.selectedItem.id) {
            root.deleteArmId = -1
            deleteArmTimer.stop()
            root.db.deleteItem(root.selectedItem.id)
            return
        }
        root.deleteArmId = root.selectedItem.id
        deleteArmTimer.restart()
        if (root.toast) root.toast.show("Delete again to confirm")
    }

    function focusSearch() { searchField.forceActiveFocus() }
    function focusList() { pump.forceActiveFocus() }

    // Called by Panel.qml when the panel opens or this tab is re-shown.
    function resetFocus() {
        root.draftNew = false
        root.refillEditor()
        root.focusList()
    }

    function pickItem(id) {
        root._selectAfterReload = -1
        root.selectedId = id
        root.focusList()
        listView.positionViewAtIndex(root.selectedIndex, ListView.Center)
    }
    function moveSelection(delta) {
        var items = root.itemList
        var n = items.length
        if (n === 0) return
        var cur = root.selectedIndex
        var next = Math.max(0, Math.min(n - 1, cur + delta))
        root.selectedId = items[next].id
        listView.positionViewAtIndex(next, ListView.Center)
    }

    // Resolved from selectedId + itemList rather than the selectedItem
    // binding, which lags by one step inside onSelectedIdChanged.
    function refillEditor() {
        var idx = ItemJs.indexOfId(root.itemList, root.selectedId)
        editorPane.openItem(idx >= 0 ? root.itemList[idx] : null)
    }

    function focusEditor() {
        root.deleteArmId = -1
        deleteArmTimer.stop()
        if (root.draftNew) { Qt.callLater(function() { editorPane.focusTitle() }); return }
        if (!root.selectedItem) { root.startNew("note"); return }
        root.draftNew = false
        root.refillEditor()
        Qt.callLater(function() { editorPane.focusTitle() })
    }

    function startNew(type) {
        if (!root.db) return
        root.saveEdit()
        root.deleteArmId = -1
        deleteArmTimer.stop()
        root.draftNew = true
        root.draftType = type === "todo" ? "todo" : "note"
        editorPane.openDraft()
        Qt.callLater(function() { editorPane.focusTitle() })
    }

    function saveEdit() {
        var e = editorPane.takeEdit()
        if (!e) return
        root.db.update(e.id, e.title, e.body)
        if (!e.titleWasEmpty) return
        root._quietSaveId = e.id
        if (root.toast) root.toast.show("Title can't be empty — kept “" + e.title + "”")
    }

    // Every way out of the editor lands here. Keys and the Save button hand
    // focus back to the list; a save caused by focus already having moved
    // (a click into the search field, the panel closing) leaves focus alone.
    function commitEditor(returnFocus) {
        if (root.draftNew) {
            var title = String(editorPane.titleText || "").trim()
            var body = String(editorPane.bodyText || "")
            root.draftNew = false
            root.refillEditor()
            if (title === "") {
                if (root.toast) root.toast.show("New item needs a title")
            } else {
                root.db.add(root.draftType, title, body)
                if (root.toast) root.toast.show("Added " + root.draftType + " — " + title)
            }
        } else {
            root.saveEdit()
        }
        if (returnFocus) root.focusList()
    }

    function discardEditor() {
        root.draftNew = false
        root.refillEditor()
        root.focusList()
    }

    function commitIfDirty() {
        if (root.draftNew || editorPane.dirty) root.commitEditor(false)
    }

    function cycleFilter() {
        var order = ["all", "note", "todo"]
        root.filterType = order[(order.indexOf(root.filterType) + 1) % order.length]
        filterDebounce.restart()
    }

    function onListKey(event) {
        if (event.key === Qt.Key_Down || event.key === Qt.Key_J || event.text === "j") {
            root.moveSelection(1); event.accepted = true
        } else if (event.key === Qt.Key_Up || event.key === Qt.Key_K || event.text === "k") {
            root.moveSelection(-1); event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
            || event.key === Qt.Key_Right || event.key === Qt.Key_Tab
            || event.key === Qt.Key_L || event.text === "l") {
            root.focusEditor(); event.accepted = true
        } else if (event.key === Qt.Key_Space || event.text === " "
            || event.key === Qt.Key_C || event.text === "c") {
            root.toggleStatus(); event.accepted = true
        } else if (event.text === "d") {
            root.armDelete(); event.accepted = true
        } else if (event.text === "n" || event.text === "a") {
            root.startNew("note"); event.accepted = true
        } else if (event.text === "/") {
            root.focusSearch(); event.accepted = true
        } else if (event.text === "f") {
            root.cycleFilter(); event.accepted = true
        } else if (event.key === Qt.Key_Escape) {
            if (root.deleteArmed) { root.deleteArmId = -1; deleteArmTimer.stop(); event.accepted = true }
            else { root.closeRequested(); event.accepted = true }
        }
    }

    Item {
        id: pump
        anchors.fill: parent
        focus: true
        Keys.onPressed: function(event) { root.onListKey(event) }
    }

    Timer {
        id: filterDebounce
        interval: 120
        onTriggered: {
            root._selectAfterReload = -1
            if (root.db) root.db.list(root.filterType, root.searchText)
        }
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: root.nowSeconds = Math.floor(Date.now() / 1000)
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Style.spacing.xxl

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Style.spacing.xxl

            ColumnLayout {
                Layout.preferredWidth: Style.space(270)
                Layout.minimumWidth: Style.space(270)
                Layout.maximumWidth: Style.space(270)
                Layout.fillHeight: true
                spacing: Style.spacing.lg

                SearchField {
                    id: searchField
                    Layout.fillWidth: true
                    foreground: root.foreground
                    accent: root.accent
                    activeFocusOnTab: false
                    onTextChanged: filterDebounce.restart()
                    onAccepted: root.focusList()
                    Keys.onPressed: function(event) {
                        if (event.key === Qt.Key_Escape) {
                            searchField.text = ""; root.focusList(); event.accepted = true
                        } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                            root.focusList(); event.accepted = true
                        }
                    }
                }

                Segment {
                    id: typeSegment
                    Layout.fillWidth: true
                    value: root.filterType
                    foreground: root.foreground
                    accent: root.accent
                    options: [
                        { value: "all", label: "All", count: root.db ? (root.db.totalNotes + root.db.totalTodos) : 0 },
                        { value: "note", label: "Notes", count: root.db ? root.db.totalNotes : 0 },
                        { value: "todo", label: "Todos", count: root.db ? root.db.totalTodos : 0 }
                    ]
                    onPicked: function(v) { root.filterType = v; filterDebounce.restart() }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    ListView {
                        id: listView
                        anchors.fill: parent
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        keyNavigationEnabled: false
                        spacing: Style.spacing.xxs
                        model: root.itemList

                        delegate: ItemRow {
                            required property var modelData
                            width: listView.width
                            item: modelData
                            selected: Number(modelData.id) === root.selectedId && !root.draftNew
                            foreground: root.foreground
                            accent: root.accent
                            nowSeconds: root.nowSeconds
                            onPicked: root.pickItem(modelData.id)
                            onToggled: {
                                if (root.db) root.db.setStatus(modelData.id, ItemJs.isDone(modelData) ? 0 : 1)
                            }
                        }
                    }

                    EmptyState {
                        anchors.centerIn: parent
                        visible: listView.count === 0
                        filtered: root._filtered
                        foreground: root.foreground
                        accent: root.accent
                        onNewNote: root.startNew("note")
                        onNewTodo: root.startNew("todo")
                        onClearSearch: {
                            searchField.text = ""
                            root.filterType = "all"
                            filterDebounce.restart()
                            root.focusList()
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillHeight: true
                Layout.preferredWidth: 1
                color: Util.alpha(root.foreground, 0.10)
            }

            EditorPane {
                id: editorPane
                visible: !!root.selectedItem || root.draftNew
                Layout.fillWidth: true
                Layout.fillHeight: true
                item: root.selectedItem
                draft: root.draftNew
                draftType: root.draftType
                deleteArmed: root.deleteArmed
                nowSeconds: root.nowSeconds
                foreground: root.foreground
                accent: root.accent
                onLeaveRequested: root.commitEditor(true)
                onToggleDraftTypeRequested: function(v) { root.draftType = v }
                onToggleRequested: root.toggleStatus()
                onConvertRequested: root.convertSelected()
                onCopyRequested: root.copySelected()
                onDeleteClicked: root.armDelete()
                onSaveRequested: root.commitEditor(true)
                onDiscardRequested: root.discardEditor()
            }

            Item {
                visible: !root.selectedItem && !root.draftNew
                Layout.fillWidth: true
                Layout.fillHeight: true

                Text {
                    anchors.centerIn: parent
                    text: "Your note or todo opens here."
                    color: Util.alpha(root.foreground, 0.45)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Util.alpha(root.foreground, 0.10)
        }

        HintBar {
            Layout.fillWidth: true
            hints: root.hints
            urgent: root.deleteArmed
            foreground: root.foreground
        }
    }

    Timer {
        id: deleteArmTimer
        interval: 2000
        onTriggered: root.deleteArmId = -1
    }

    function onItemsSynced() {
        if (root.draftNew) return
        var items = root.itemList
        if (root._selectAfterReload >= 0 && ItemJs.indexOfId(items, root._selectAfterReload) >= 0) {
            root.selectedId = root._selectAfterReload
            root._selectAfterReload = -1
            listView.positionViewAtIndex(root.selectedIndex, ListView.Center)
        }
        var refill = !root.editorFocused && !editorPane.dirty
        if (ItemJs.indexOfId(items, root.selectedId) >= 0) {
            if (refill) root.refillEditor()
            return
        }
        root.selectedId = items.length > 0 ? items[0].id : -1
        if (refill) root.refillEditor()
        if (items.length > 0) listView.positionViewAtIndex(0, ListView.Center)
    }

    Connections {
        target: root.db
        function onItemsUpdated() { root.onItemsSynced() }
        function onAdded(id) { root._selectAfterReload = Number(id) }
        function onUpdated(id, title) {
            if (id === root._quietSaveId) { root._quietSaveId = -1; return }
            if (root.toast) root.toast.show("Saved — " + title)
        }
        function onStatusChanged(id, status) {
            if (Number(id) !== root.selectedId || !root.toast) return
            var item = root.selectedItem
            if (!item) return
            root.toast.show(ItemJs.statusToast(item, status))
        }
        function onTypeChanged(id) {
            var idx = ItemJs.indexOfId(root.itemList, Number(id))
            if (idx < 0 || !root.toast) return
            var before = root.itemList[idx]
            var newType = ItemJs.isTodo(before) ? "note" : "todo"
            root.toast.show("Converted to " + newType + " — " + before.title)
        }
        function onItemDeleted(id) {
            if (Number(id) !== root.selectedId) return
            root.deleteArmId = -1
            deleteArmTimer.stop()
            if (root.toast) root.toast.show("Deleted")
            var items = root.itemList
            var idx = ItemJs.indexOfId(items, Number(id))
            root.selectedId = idx + 1 < items.length ? items[idx + 1].id
                : (idx - 1 >= 0 ? items[idx - 1].id : -1)
        }
        function onFailed(message) {
            if (root.toast) root.toast.show("Error: " + String(message || "unknown"), true)
        }
    }

    Component.onCompleted: {
        root.refillEditor()
        root.focusList()
    }
}
