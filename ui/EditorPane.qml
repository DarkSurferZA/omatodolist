import QtQuick
import QtQuick.Controls as QQC
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "Item.js" as ItemJs
import "Icons.js" as Icons

// Owns the edit session: which row the fields belong to, what they opened
// with, and what they hold now. The three only change together, through
// openItem(), openDraft() and takeEdit(), so the fields can never hold text
// that belongs to a different row than editingId. MainTab decides when to
// save, never what the fields hold.
ColumnLayout {
    id: root

    property var item: null
    property bool draft: false
    property string draftType: "note"
    property bool deleteArmed: false
    property int nowSeconds: 0
    property color foreground: Color.foreground
    property color accent: Color.accent

    property alias titleText: titleField.text
    property alias bodyText: bodyField.text
    property int editingId: -1
    property string _baseTitle: ""
    property string _baseBody: ""
    readonly property bool dirty: !root.draft && root.editingId >= 0
        && (titleField.text !== root._baseTitle || bodyField.text !== root._baseBody)
    readonly property bool titleFocused: titleField.activeFocus
    readonly property bool bodyFocused: bodyField.activeFocus
    readonly property bool unsaved: root.draft || root.dirty

    signal leaveRequested()               // Esc/Backtab from title, Esc/Tab/Enter from body — autosave and back to the list
    signal toggleDraftTypeRequested(string v)
    signal toggleRequested()
    signal convertRequested()
    signal copyRequested()
    signal deleteClicked()
    signal saveRequested()
    signal discardRequested()

    function openItem(it) {
        root.editingId = it ? Number(it.id) : -1
        titleField.text = it ? String(it.title || "") : ""
        bodyField.text = it ? String(it.body || "") : ""
        root._baseTitle = titleField.text
        root._baseBody = bodyField.text
    }
    function openDraft() { root.openItem(null) }

    // Returns the pending edit and marks it as the new base, or null when
    // there is nothing to save. An emptied title falls back to the saved
    // one so the body typed next to it is never thrown away.
    function takeEdit() {
        if (!root.dirty) return null
        var typed = String(titleField.text || "").trim()
        var title = typed === "" ? root._baseTitle : typed
        titleField.text = title
        root._baseTitle = title
        root._baseBody = bodyField.text
        return { id: root.editingId, title: title, body: root._baseBody, titleWasEmpty: typed === "" }
    }

    function focusTitle() { titleField.forceActiveFocus() }
    function focusBody() { bodyField.forceActiveFocus() }

    spacing: Style.spacing.lg

    RowLayout {
        Layout.fillWidth: true
        spacing: Style.spacing.lg

        Segment {
            visible: root.draft
            fill: false
            options: [
                { value: "note", label: "Note", icon: Icons.note },
                { value: "todo", label: "Todo", icon: Icons.boxOff }
            ]
            value: root.draftType
            foreground: root.foreground
            accent: root.accent
            onPicked: function(v) { root.toggleDraftTypeRequested(v) }
        }

        Row {
            visible: !root.draft
            spacing: Style.spacing.md

            Text {
                text: root.item && ItemJs.isTodo(root.item) ? Icons.boxOff : Icons.note
                color: root.accent
                font.family: Style.font.family
                font.pixelSize: Style.font.icon
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: root.item && ItemJs.isTodo(root.item) ? "Todo" : "Note"
                color: root.foreground
                font.bold: true
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                anchors.verticalCenter: parent.verticalCenter
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: statusText.implicitWidth + Style.space(14)
                height: statusText.implicitHeight + Style.space(6)
                radius: height / 2
                color: root.item && ItemJs.isDone(root.item) ? Util.alpha(root.foreground, 0.08) : Util.alpha(Color.urgent, 0.14)
                Text {
                    id: statusText
                    anchors.centerIn: parent
                    text: root.item ? ItemJs.statusLabel(root.item) : ""
                    color: root.item && ItemJs.isDone(root.item) ? Util.alpha(root.foreground, 0.7) : Color.urgent
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                }
            }
        }

        Item { Layout.fillWidth: true }

        Row {
            spacing: Style.spacing.sm
            Rectangle {
                width: Style.space(6); height: width; radius: width / 2
                anchors.verticalCenter: parent.verticalCenter
                color: root.unsaved ? Color.urgent : Util.alpha(root.foreground, 0.4)
            }
            Text {
                text: root.draft
                    ? "Unsaved draft"
                    : (root.dirty
                            ? "Unsaved changes"
                            : "Saved · edited " + ItemJs.relativeAge(Number(root.item ? root.item.updated_at : 0), root.nowSeconds))
                color: Util.alpha(root.foreground, 0.62)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
            }
        }
    }

    Field {
        id: titleField
        Layout.fillWidth: true
        placeholderText: root.draft ? (root.draftType === "todo" ? "What needs doing?" : "Note title") : "Title"
        foreground: root.foreground
        accent: root.accent
        activeFocusOnTab: false
        onAccepted: root.focusBody()
        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Tab) {
                root.focusBody(); event.accepted = true
            } else if (event.key === Qt.Key_Backtab || event.key === Qt.Key_Escape) {
                root.leaveRequested(); event.accepted = true
            } else if (event.text === "t" && root.draft
                && String(titleField.text) === "" && !event.modifiers) {
                root.toggleDraftTypeRequested(root.draftType === "todo" ? "note" : "todo"); event.accepted = true
            }
        }
    }

    QQC.TextArea {
        id: bodyField
        Layout.fillWidth: true
        Layout.fillHeight: true
        placeholderText: "Details (optional)"
        color: root.foreground
        placeholderTextColor: Util.alpha(root.foreground, 0.45)
        selectionColor: Style.selectionFillFor(root.foreground, root.accent)
        selectedTextColor: root.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        wrapMode: Text.Wrap
        padding: Style.spacing.controlPaddingX
        background: Rectangle {
            color: Util.alpha(root.foreground, 0.03)
            border.width: 1
            border.color: Util.alpha(root.foreground, 0.10)
        }
        selectByMouse: true
        activeFocusOnTab: false
        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                if (!(event.modifiers & Qt.ShiftModifier)) { root.leaveRequested(); event.accepted = true }
                else event.accepted = false          // let Shift+Enter insert a newline
            } else if (event.key === Qt.Key_Tab) {
                root.leaveRequested(); event.accepted = true
            } else if (event.key === Qt.Key_Backtab) {
                Qt.callLater(function() { root.focusTitle() }); event.accepted = true
            } else if (event.key === Qt.Key_Escape) {
                root.leaveRequested(); event.accepted = true
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Style.spacing.md

        ActionButton {
            visible: root.unsaved
            bordered: true
            selected: true
            iconText: Icons.check
            text: root.draft ? ("Save " + root.draftType) : "Save"
            foreground: root.foreground
            accent: root.accent
            onClicked: root.saveRequested()
        }
        ActionButton {
            visible: root.unsaved
            bordered: true
            text: "Discard"
            foreground: root.foreground
            accent: root.accent
            onClicked: root.discardRequested()
        }
        ActionButton {
            visible: !root.unsaved
            bordered: true
            iconText: Icons.check
            text: root.item ? ItemJs.toggleVerb(root.item) : ""
            foreground: root.foreground
            accent: root.accent
            onClicked: root.toggleRequested()
        }
        ActionButton {
            visible: !root.unsaved
            bordered: true
            iconText: Icons.swap
            text: root.item && ItemJs.isTodo(root.item) ? "To note" : "To todo"
            foreground: root.foreground
            accent: root.accent
            onClicked: root.convertRequested()
        }
        ActionButton {
            visible: !root.unsaved
            bordered: true
            iconText: Icons.copy
            text: "Copy"
            foreground: root.foreground
            accent: root.accent
            onClicked: root.copyRequested()
        }
        Item { Layout.fillWidth: true }
        ActionButton {
            visible: !root.draft
            bordered: true
            iconText: Icons.trash
            text: root.deleteArmed ? "Confirm" : "Delete"
            foreground: Color.urgent
            onClicked: root.deleteClicked()
        }
    }
}
