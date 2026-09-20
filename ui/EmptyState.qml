import QtQuick
import qs.Commons
import "Icons.js" as Icons

// Right-hand-side-less list state. Unfiltered: "Nothing here yet" with
// New note / New todo (each opens a draft already in that type). Filtered
// or searched down to nothing: "No matches" with a Clear search action.
Column {
    id: root
    property bool filtered: false
    property color foreground: Color.foreground
    property color accent: Color.accent

    signal newNote()
    signal newTodo()
    signal clearSearch()

    spacing: Style.spacing.xxl

    Text {
        visible: !root.filtered
        anchors.horizontalCenter: parent.horizontalCenter
        text: Icons.note
        color: Util.alpha(root.foreground, 0.35)
        font.family: Style.font.family
        font.pixelSize: Style.space(34)
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.filtered ? "No matches" : "Nothing here yet"
        color: root.foreground
        font.bold: true
        font.family: Style.font.family
        font.pixelSize: Style.font.title
    }

    Text {
        visible: !root.filtered
        anchors.horizontalCenter: parent.horizontalCenter
        text: "Keep a note or track a todo."
        color: Util.alpha(root.foreground, 0.62)
        font.family: Style.font.family
        font.pixelSize: Style.font.body
    }

    Row {
        visible: !root.filtered
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.spacing.lg

        ActionButton {
            bordered: true
            selected: true
            iconText: Icons.plus
            text: "New note"
            foreground: root.foreground
            accent: root.accent
            onClicked: root.newNote()
        }
        ActionButton {
            bordered: true
            iconText: Icons.plus
            text: "New todo"
            foreground: root.foreground
            accent: root.accent
            onClicked: root.newTodo()
        }
    }

    ActionButton {
        visible: root.filtered
        anchors.horizontalCenter: parent.horizontalCenter
        bordered: true
        text: "Clear search"
        foreground: root.foreground
        accent: root.accent
        onClicked: root.clearSearch()
    }
}
