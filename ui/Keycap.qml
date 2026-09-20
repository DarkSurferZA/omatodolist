import QtQuick
import qs.Commons

// One `key` + label pair inside a HintBar.
Row {
    id: root
    property string k: ""
    property string l: ""
    property color foreground: Color.foreground
    spacing: Style.spacing.sm

    Rectangle {
        width: kt.implicitWidth + Style.space(10)
        height: kt.implicitHeight + Style.space(4)
        radius: Style.space(3)
        color: Util.alpha(root.foreground, 0.06)
        border.width: 1
        border.color: Util.alpha(root.foreground, 0.22)
        Text {
            id: kt
            anchors.centerIn: parent
            text: root.k
            color: Util.alpha(root.foreground, 0.9)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
        }
    }
    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.l
        color: Util.alpha(root.foreground, 0.62)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
    }
}
