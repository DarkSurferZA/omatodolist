import QtQuick
import qs.Commons
import "Item.js" as ItemJs
import "Icons.js" as Icons

// One row of the unified list: a checkbox (todo) or note glyph, an unread
// dot on unread notes, the title (bold when an unread note, struck through
// and dimmed when a done todo), and the age since updated_at on the right.
// Clicking the glyph toggles status; clicking the rest of the row selects.
Rectangle {
    id: root

    property var item: ({})
    property bool selected: false
    property color foreground: Color.foreground
    property color accent: Color.accent
    property int nowSeconds: 0

    signal picked()
    signal toggled()

    readonly property bool done: ItemJs.isDone(root.item)
    readonly property bool todo: ItemJs.isTodo(root.item)

    height: Style.space(30)
    radius: Style.cornerRadius
    color: root.selected
        ? Style.selectedFillFor(root.foreground, root.accent)
        : (rowMouse.containsMouse ? Style.hoverFillFor(root.foreground, root.accent) : "transparent")

    MouseArea {
        id: rowMouse
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.picked()
    }

    Text {
        id: glyph
        x: Style.space(10)
        y: (root.height - height) / 2
        text: root.todo ? (root.done ? Icons.boxOn : Icons.boxOff) : Icons.note
        color: root.done ? Util.alpha(root.foreground, 0.45) : (root.todo ? root.foreground : root.accent)
        font.family: Style.font.family
        font.pixelSize: Style.font.icon

        MouseArea {
            anchors.fill: parent
            anchors.margins: -Style.space(6)
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggled()
        }
    }

    Rectangle {
        visible: !root.todo && !root.done
        width: Style.space(6)
        height: width
        radius: width / 2
        color: Color.urgent
        x: glyph.x + glyph.width - Style.space(3)
        y: glyph.y - Style.space(1)
    }

    Text {
        id: title
        anchors.left: glyph.right
        anchors.leftMargin: Style.space(9)
        anchors.right: meta.left
        anchors.rightMargin: Style.space(8)
        y: (root.height - height) / 2
        text: root.item.title || ""
        elide: Text.ElideRight
        color: root.done ? Util.alpha(root.foreground, 0.5) : root.foreground
        font.strikeout: root.todo && root.done
        font.bold: !root.done && !root.todo
        font.family: Style.font.family
        font.pixelSize: Style.font.body
    }

    Text {
        id: meta
        anchors.right: parent.right
        anchors.rightMargin: Style.space(10)
        y: (root.height - height) / 2
        text: ItemJs.relativeAge(Number(root.item.updated_at), root.nowSeconds)
        color: Util.alpha(root.foreground, 0.5)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
    }
}
