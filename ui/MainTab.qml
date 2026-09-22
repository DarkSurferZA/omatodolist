pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// "Notes & Todos" tab (spec §3.1/§3.2): unified list on the left (type tags
// [N]/[T], filter input + All/Notes/Todos segment, updated_at DESC, dimmed
// rows for status=1), and the right-hand detail pane doubles as the inline
// editor — no overlay composer. Selecting an item shows its title+body as
// editable fields; `n` starts a new-item draft; Tab/Enter move into the pane.
//
// The Toast is owned by Panel.qml and injected here (Quickshell ignores
// single-file imports, so components never reference each other by type name —
// all cross-file types resolve through Panel's "ui" directory import).
//
// Keyboard map (spec §3.1):
//   list:   j/k or ↑/↓ move · Enter/l/→/Tab edit the selected item
//           · n (or a) new draft · space/c toggle status (read/unread,
//           completed/in-progress) · d delete (double-press to confirm)
//           · Esc closes the panel
//   editor: fields own printable keys · Tab title→body, body→save+list
//           · Enter in body saves · Esc saves (auto-save on leaving — spec
//           §3.4) · `Ctrl+T` with an empty title toggles a new draft's type
//           · space/d intentionally do nothing here (list actions only)
//   control: Esc returns to the list · Tab walks filter → segment → list
//
// Focus model: `pump` owns keyboard focus for the list (focusState 2). The
// filter field (0) and segment (1) are reached by mouse click or Tab routed
// through the pump. The editor fields claim focus directly and handle their
// own keys; everything commits back through commitEditor().
Item {
    id: root

    // ------------------------------------------------------------------ deps
    property QtObject db: null              // Panel's Data.Db instance
    property var toast: null                // ui/Toast instance (Panel-owned)
    property color foreground: Color.foreground
    property color accent: Color.accent

    signal closeRequested()                 // Esc in the list closes the panel

    // ------------------------------------------------------------------ state
    property string filterType: "all"       // all | note | todo
    property int focusState: 2              // 0 filter field, 1 segment, 2 list
    property int selectedId: -1
    property bool draftNew: false           // right pane holds a new-item draft
    property string draftType: "note"       // draft's type ('note' | 'todo')

    // Public editor access (Ui.smoke drives these instead of real focus).
    property alias editorTitle: titleField.text
    property alias editorBody: bodyField.text
    readonly property bool editingNow: titleField.activeFocus || bodyField.activeFocus

    // Values the editor opened with, so commit only writes when something
    // actually changed (keeps "edited" history rows honest).
    property string _editBaseTitle: ""
    property string _editBaseBody: ""

    // Highlighting a different row (j/k/click) refreshes the right-hand
    // description pane to the newly selected item — but never clobbers a
    // draft or an in-progress edit (fields with active focus).
    onSelectedIdChanged: {
        if (root.draftNew || titleField.activeFocus || bodyField.activeFocus) return
        root.refillEditor()
    }

    property int deleteArmId: -1            // -1 = not armed
    readonly property bool deleteArmed: root.deleteArmId >= 0

    // ------------------------------------------------------------------ derived
    function indexOfId(items, id) {
        var list = items || []
        for (var i = 0; i < list.length; ++i)
            if (Number(list[i].id) === Number(id)) return i
        return -1
    }
    readonly property var itemList: root.db ? (root.db.items || []) : []
    readonly property int selectedIndex: root.indexOfId(root.itemList, root.selectedId)
    readonly property var selectedItem: root.selectedIndex >= 0 ? root.itemList[root.selectedIndex] : null
    // Test hooks (Ui.smoke/Edge.smoke): the empty-list label text ("" when the
    // list has rows) and the body field's wrap mode.
    readonly property string emptyLabel: emptyText.visible ? emptyText.text : ""
    readonly property int bodyWrapMode: bodyField.wrapMode

    function statusVerb() {
        if (!root.selectedItem) return ""
        var done = Number(root.selectedItem.status) === 1
        return root.selectedItem.type === "todo"
            ? (done ? "Reopen" : "Complete")
            : (done ? "Mark unread" : "Mark read")
    }

    function toggleStatus() {
        if (!root.db || !root.selectedItem) return
        root.db.setStatus(root.selectedItem.id, Number(root.selectedItem.status) === 1 ? 0 : 1)
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
        if (root.toast) root.toast.show("Deleting — press d again to confirm")
    }

    // ------------------------------------------------------------------ focus
    function focusFilter() { filterText.forceActiveFocus() }
    function filter(text) { filterText.text = text || "" }
    function focusSegment() { root.focusState = 1; segment.forceActiveFocus() }
    function focusList() { root.focusState = 2; pump.forceActiveFocus() }
    function exitEditor() {
        filterText.text = ""
        root.focusList()
    }

    // Called by Panel.qml when the panel opens or this tab is re-shown.
    function resetFocus() {
        root.draftNew = false
        root.refillEditor()
        root.focusList()
    }

    // ------------------------------------------------------------------ navigation
    function moveSelection(delta) {
        var items = root.itemList
        var n = items.length
        if (n === 0) return
        var cur = root.selectedIndex
        var next = Math.max(0, Math.min(n - 1, cur + delta))
        root.selectedId = items[next].id
        listView.positionViewAtIndex(next, ListView.Center)
    }

    // ------------------------------------------------------------------ editor
    // Sync the editor fields to the selected item (used on reset, after data
    // reloads, and when a draft is discarded). The item is resolved directly
    // from selectedId + itemList rather than through the selectedItem binding:
    // inside onSelectedIdChanged that binding has not always re-evaluated yet,
    // which left the pane showing the previous item (a one-step lag).
    function refillEditor() {
        var idx = root.indexOfId(root.itemList, root.selectedId)
        var it = idx >= 0 ? root.itemList[idx] : null
        titleField.text = it ? String(it.title || "") : ""
        bodyField.text = it ? String(it.body || "") : ""
        root._editBaseTitle = titleField.text
        root._editBaseBody = bodyField.text
    }

    // Enter/Tab/l from the list: open the selected item in the editor.
    function focusEditor() {
        root.deleteArmId = -1
        deleteArmTimer.stop()
        if (root.draftNew) { Qt.callLater(function() { titleField.forceActiveFocus() }); return }
        if (!root.selectedItem) { root.startNew(); return }
        root.draftNew = false
        root.refillEditor()
        Qt.callLater(function() { titleField.forceActiveFocus() })
    }

    // `n`/`a` from the list: start a new-item draft in the editor pane.
    function startNew() {
        if (!root.db) return
        root.deleteArmId = -1
        deleteArmTimer.stop()
        root.draftNew = true
        root.draftType = "note"
        titleField.text = ""
        bodyField.text = ""
        Qt.callLater(function() { titleField.forceActiveFocus() })
    }

    // `Ctrl+T` (empty title) / clicking the Note/Todo chips flips a draft's type.
    function toggleDraftType() {
        if (!root.draftNew) return
        root.draftType = root.draftType === "todo" ? "note" : "todo"
    }

    function focusBody() { bodyField.forceActiveFocus() }

    // Auto-save on leaving the editor: Tab from the body, Enter in the body,
    // or Esc from any field all land here. Empty new drafts are discarded
    // (the cancellation path); existing items only write when changed.
    function commitEditor() {
        var title = String(titleField.text || "").trim()
        var body = String(bodyField.text || "")

        if (root.draftNew) {
            root.draftNew = false
            if (title === "") {
                if (root.toast) root.toast.show("New item needs a title")
                root.refillEditor()
            } else {
                root.db.add(root.draftType, title, body)
                if (root.toast) root.toast.show("Added " + root.draftType + " — " + title)
            }
            root.focusList()
            return
        }

        if (!root.selectedItem) {
            root.refillEditor()
            root.focusList()
            return
        }
        if (title === "") {
            if (root.toast) root.toast.show("Title can't be empty")
            return
        }
        if (title !== root._editBaseTitle || body !== root._editBaseBody) {
            root.db.update(root.selectedItem.id, title, body)
            if (root.toast) root.toast.show("Saved — " + title)
        }
        root.focusList()
    }

    // ------------------------------------------------------------------ keys
    function onKey(event) {
        if (root.focusState !== 2) { handleControlFocusedKey(event); return }
        handleListKey(event)
    }

    function handleListKey(event) {
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
            root.startNew(); event.accepted = true
        } else if (event.key === Qt.Key_Escape) {
            if (root.deleteArmed) { root.deleteArmId = -1; deleteArmTimer.stop(); event.accepted = true }
            else { root.closeRequested(); event.accepted = true }
        }
    }

    // A control (filter field or segment) has focus: it owns printable keys;
    // Esc returns to the list, Tab walks the filter -> segment -> list cycle.
    function handleControlFocusedKey(event) {
        if (event.key === Qt.Key_Escape) {
            root.exitEditor(); event.accepted = true
        } else if (event.key === Qt.Key_Tab) {
            if (root.focusState === 0) root.focusSegment()
            else root.focusList()
            event.accepted = true
        } else if (event.key === Qt.Key_Backtab) {
            if (root.focusState === 0) root.focusList()
            else root.focusFilter()
            event.accepted = true
        }
    }

    // ------------------------------------------------------------------ focus owner
    Item {
        id: pump
        anchors.fill: parent
        focus: true
        Keys.onPressed: function(event) { root.onKey(event) }
        onActiveFocusChanged: if (pump.activeFocus) root.focusState = 2
    }

    // ------------------------------------------------------------------ filter
    Timer {
        id: filterDebounce
        interval: 120
        onTriggered: {
            if (root.db) root.db.list(root.filterType, filterText.text)
        }
    }

    // ------------------------------------------------------------------ layout
    RowLayout {
        anchors.fill: parent
        spacing: Style.spacing.lg

        // -------- left: title list pane (35% of the panel width) ----------
        ColumnLayout {
            Layout.preferredWidth: Math.round(root.width * 0.35)
            Layout.minimumWidth: Math.max(180, Math.round(root.width * 0.28))
            Layout.maximumWidth: Math.round(root.width * 0.35)
            Layout.fillHeight: true
            spacing: Style.spacing.sm

            RowLayout {
                Layout.fillWidth: true
                spacing: Style.spacing.md

                Text {
                    text: "omatodolist"
                    color: root.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.title
                    font.bold: true
                }

                Item { Layout.fillWidth: true }

                // Status count (spec §3.2): unread notes / in-progress todos.
                Text {
                    text: (root.db ? root.db.unreadNotes : 0) + " / " + (root.db ? root.db.inProgressTodos : 0)
                    color: Qt.darker(root.foreground, 1.3)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    QQC.ToolTip.visible: countHover.hovered
                    QQC.ToolTip.delay: 500
                    QQC.ToolTip.text: "unread notes / in-progress todos"
                }
                HoverHandler { id: countHover }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Style.spacing.md

                TextField {
                    id: filterText
                    Layout.fillWidth: true
                    placeholderText: "Filter (Esc to clear)"
                    foreground: root.foreground
                    accent: root.accent
                    activeFocusOnTab: false
                    onTextChanged: filterDebounce.restart()
                    onAccepted: root.focusList()
                    onActiveFocusChanged: if (filterText.activeFocus) root.focusState = 0
                }

                ButtonGroup {
                    id: segment
                    options: [
                        { value: "all", label: "All" },
                        { value: "note", label: "Notes" },
                        { value: "todo", label: "Todos" }
                    ]
                    value: root.filterType
                    focusable: false
                    foreground: root.foreground
                    accent: root.accent
                    onChanged: function(v) { root.filterType = v; filterDebounce.restart() }
                    onActiveFocusChanged: if (segment.activeFocus) root.focusState = 1
                }
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
                    id: emptyText
                    anchors.centerIn: parent
                    visible: listView.count === 0
                    text: filterText.text.trim() !== "" || root.filterType !== "all"
                        ? "No items match the filter"
                        : "No items yet — press `n` to add"
                    color: Qt.darker(root.foreground, 1.6)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                }

                ListView {
                    id: listView
                    anchors.fill: parent
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    keyNavigationEnabled: false
                    spacing: Style.spacing.xxs
                    model: root.itemList
                    currentIndex: root.selectedIndex

                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        width: listView.width
                        height: titleRow.implicitHeight + Style.space(10)
                        radius: Style.cornerRadius
                        color: index === listView.currentIndex
                            ? Style.selectedFillFor(root.foreground, root.accent)
                            : "transparent"

                        readonly property bool done: Number(modelData.status) === 1

                        Row {
                            id: titleRow
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: Style.spacing.controlPaddingX
                            anchors.rightMargin: Style.spacing.controlPaddingX
                            spacing: Style.spacing.sm

                            Text {
                                id: tagText
                                text: modelData.type === "todo" ? "[T]" : "[N]"
                                color: index === listView.currentIndex
                                    ? Style.selectedStateColor(root.foreground, root.accent)
                                    : (done ? Qt.darker(root.foreground, 1.4) : Qt.darker(root.foreground, 1.2))
                                font.family: Style.font.family
                                font.pixelSize: Style.font.bodySmall
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                text: modelData.title
                                elide: Text.ElideRight
                                width: parent.width - tagText.implicitWidth - Style.spacing.sm
                                color: index === listView.currentIndex
                                    ? Style.selectedStateColor(root.foreground, root.accent)
                                    : (done ? Qt.darker(root.foreground, 1.6) : root.foreground)
                                font.family: Style.font.family
                                font.pixelSize: Style.font.body
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton
                            onClicked: {
                                root.selectedId = modelData.id
                                root.focusList()
                                listView.positionViewAtIndex(index, ListView.Center)
                            }
                        }
                    }
                }
            }

            // List-key hint (spec §3.1): the actions that belong to the list
            // pane only — the editor intentionally has none of these.
            Text {
                Layout.fillWidth: true
                text: "j/k move · space/c toggle · d delete (x2) · n new · Enter/Tab edit"
                elide: Text.ElideRight
                color: Qt.darker(root.foreground, 1.5)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
            }
        }

        // -------- separator -----------------------------------------------
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 1
            color: Util.alpha(root.foreground, 0.10)
        }

        // -------- right: detail + inline editor (fills the remaining ~65%) --
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Text {
                anchors.centerIn: parent
                visible: !root.selectedItem && !root.draftNew
                text: root.itemList.length === 0
                    ? "No items yet — press n to add"
                    : "Select an item and press Enter (or Tab) to edit it"
                horizontalAlignment: Text.AlignHCenter
                color: Qt.darker(root.foreground, 1.6)
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                lineHeight: 1.6
            }

            ColumnLayout {
                anchors.fill: parent
                visible: !!root.selectedItem || root.draftNew
                spacing: Style.spacing.sm

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.spacing.sm

                    // New-draft type picker (Note/Todo chips, `t` also toggles).
                    // Direct children (NOT Loaders): a Loader hides the loaded
                    // item's Layout.* props from the ambient layout, collapsing
                    // Rectangles to 0x0 and letting their text pile up.
                    RowLayout {
                        visible: root.draftNew
                        Layout.preferredHeight: Style.space(26)
                        spacing: Style.spacing.sm
                        Button {
                            text: "Note"
                            bordered: true
                            selected: root.draftType === "note"
                            foreground: root.foreground
                            accent: root.accent
                            onClicked: root.draftType = "note"
                        }
                        Button {
                            text: "Todo"
                            bordered: true
                            selected: root.draftType === "todo"
                            foreground: root.foreground
                            accent: root.accent
                            onClicked: root.draftType = "todo"
                        }
                    }

                    // Existing item: fixed type tag (type never changes on edit).
                    Rectangle {
                        visible: !!root.selectedItem && !root.draftNew
                        Layout.preferredWidth: typeTag.implicitWidth + Style.space(14)
                        Layout.preferredHeight: typeTag.implicitHeight + Style.space(6)
                        radius: Style.cornerRadius
                        color: Util.alpha(root.foreground, 0.10)
                        Text {
                            id: typeTag
                            anchors.centerIn: parent
                            text: root.selectedItem ? root.selectedItem.type : ""
                            color: root.foreground
                            font.family: Style.font.family
                            font.pixelSize: Style.font.caption
                        }
                    }

                    // Existing item's status tag (list actions change it).
                    Rectangle {
                        visible: !!root.selectedItem && !root.draftNew
                        Layout.preferredWidth: statusTag.implicitWidth + Style.space(14)
                        Layout.preferredHeight: statusTag.implicitHeight + Style.space(6)
                        radius: Style.cornerRadius
                        color: root.selectedItem && Number(root.selectedItem.status) === 1
                            ? Util.alpha(root.accent, 0.15)
                            : Util.alpha(Color.urgent, 0.12)
                        Text {
                            id: statusTag
                            anchors.centerIn: parent
                            text: root.selectedItem
                                ? (root.selectedItem.type === "todo"
                                    ? (Number(root.selectedItem.status) === 1 ? "done" : "in progress")
                                    : (Number(root.selectedItem.status) === 1 ? "read" : "unread"))
                                : ""
                            color: root.selectedItem && Number(root.selectedItem.status) === 1 ? root.accent : Color.urgent
                            font.family: Style.font.family
                            font.pixelSize: Style.font.caption
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: root.draftNew
                            ? "new " + root.draftType + " — Tab/Enter/Esc save"
                            : "editing — changes save when you leave"
                        color: Qt.darker(root.foreground, 1.5)
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                    }
                }

                TextField {
                    id: titleField
                    Layout.fillWidth: true
                    placeholderText: "Title (required)"
                    foreground: root.foreground
                    accent: root.accent
                    activeFocusOnTab: false
                    onAccepted: root.focusBody()
                    Keys.onPressed: function(event) {
                        if (event.key === Qt.Key_Tab) {
                            root.focusBody(); event.accepted = true
                        } else if (event.key === Qt.Key_Backtab) {
                            root.commitEditor(); event.accepted = true
                        } else if (event.key === Qt.Key_Escape) {
                            root.commitEditor(); event.accepted = true
                        } else if (event.text === Qt.Key_T && root.draftNew
                            && (event.modifiers & Qt.ControlModifier)) {
                            root.toggleDraftType(); event.accepted = true
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Util.alpha(root.foreground, 0.10)
                }

                QQC.TextArea {
                    id: bodyField
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    placeholderText: "Body (optional)"
                    color: root.foreground
                    placeholderTextColor: Qt.darker(root.foreground, 1.5)
                    selectionColor: Style.selectionFillFor(root.foreground, root.accent)
                    selectedTextColor: root.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    wrapMode: Text.Wrap
                    padding: Style.spacing.controlPaddingX
                    background: Rectangle { color: "transparent" }
                    selectByMouse: true
                    activeFocusOnTab: false
                    Keys.onPressed: function(event) {
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            if (!(event.modifiers & Qt.ShiftModifier)) { root.commitEditor(); event.accepted = true }
                            else event.accepted = false          // let Shift+Enter insert a newline
                        } else if (event.key === Qt.Key_Tab) {
                            root.commitEditor(); event.accepted = true
                        } else if (event.key === Qt.Key_Backtab) {
                            Qt.callLater(function() { titleField.forceActiveFocus() }); event.accepted = true
                        } else if (event.key === Qt.Key_Escape) {
                            root.commitEditor(); event.accepted = true
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: root.draftNew
                        ? "`Ctrl+T` toggles note/todo (empty title) · Enter in body saves · Esc cancels an empty draft"
                        : "space/d act on the list pane · Tab back to the list when done"
                    color: Qt.darker(root.foreground, 1.5)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                }
            }
        }
    }

    Timer {
        id: deleteArmTimer
        interval: 2000
        onTriggered: root.deleteArmId = -1
    }

    // ------------------------------------------------------------------ db sync
    function onItemsUpdated() {
        var items = root.itemList
        var refill = !root.draftNew && !titleField.activeFocus && !bodyField.activeFocus
        if (root.indexOfId(items, root.selectedId) >= 0) {
            if (refill) root.refillEditor()
            return
        }
        if (items.length === 0) {
            root.selectedId = -1
            root.draftNew = false
            root.refillEditor()
            return
        }
        root.selectedId = items[0].id
        if (refill) root.refillEditor()
        listView.positionViewAtIndex(0, ListView.Center)
    }

    Connections {
        target: root.db
        function onItemsChanged() { root.onItemsUpdated() }
        function onItemsUpdated() { root.onItemsUpdated() }
        function onAdded(id) {
            root.selectedId = Number(id)
            Qt.callLater(function() { root.focusList() })
            listView.positionViewAtIndex(root.selectedIndex, ListView.Center)
        }
        function onStatusChanged(id, status) {
            if (Number(id) !== root.selectedId || !root.toast) return
            var item = root.selectedItem
            if (!item) return
            var todo = item.type === "todo"
            var label = todo
                ? (status === 1 ? "Completed" : "Reopened")
                : (status === 1 ? "Marked read" : "Marked unread")
            root.toast.show(label + " — " + item.title)
        }
        function onItemDeleted(id) {
            if (Number(id) !== root.selectedId) return
            root.deleteArmId = -1
            deleteArmTimer.stop()
            if (root.toast) root.toast.show("Deleted")
            var items = root.itemList
            var idx = root.indexOfId(items, Number(id))
            root.selectedId = (idx >= 0 && idx + 1 < items.length)
                ? items[idx + 1].id
                : (items.length - 1 > 0 ? items[items.length - 1].id : -1)
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
