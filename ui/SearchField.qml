import QtQuick
import qs.Commons
import "Icons.js" as Icons

// Field with a leading search glyph and a trailing clear (x) that only
// shows once there's text to clear.
Field {
    id: root
    placeholderText: "Search notes and todos"
    leftPadding: Style.space(30)
    rightPadding: Style.space(28)

    Text {
        x: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        text: Icons.search
        color: Util.alpha(root.foreground, 0.6)
        font.family: Style.font.family
        font.pixelSize: Style.font.icon
    }

    Text {
        visible: root.text !== ""
        anchors.right: parent.right
        anchors.rightMargin: Style.space(9)
        anchors.verticalCenter: parent.verticalCenter
        text: Icons.close
        color: Util.alpha(root.foreground, 0.7)
        font.family: Style.font.family
        font.pixelSize: Style.font.icon

        MouseArea {
            anchors.fill: parent
            anchors.margins: -6
            cursorShape: Qt.PointingHandCursor
            onClicked: root.text = ""
        }
    }
}
