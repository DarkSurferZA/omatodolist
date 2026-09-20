pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.Commons

// Mutually exclusive segmented control: the Items/History tabs, the
// All/Notes/Todos filter, and the draft's Note/Todo picker. Each chip is
// pinned to Style.spacing.controlHeight like every other control in the kit.
RowLayout {
    id: root

    property var options: []
    property string value: ""
    property bool fill: true
    property color foreground: Color.foreground
    property color accent: Color.accent

    signal picked(string v)

    spacing: 0
    uniformCellSizes: root.fill

    Repeater {
        model: root.options

        delegate: Rectangle {
            id: chip
            required property var modelData
            required property int index
            readonly property bool on: modelData.value === root.value

            Layout.fillWidth: root.fill
            Layout.leftMargin: index === 0 ? 0 : -1
            implicitWidth: inner.implicitWidth + Style.space(22)
            implicitHeight: Style.spacing.controlHeight
            color: on ? Style.selectedFillFor(root.foreground, root.accent) : (ma.containsMouse ? Style.hoverFillFor(root.foreground, root.accent) : "transparent")
            border.width: 1
            border.color: on ? Util.alpha(root.foreground, 0.55) : Style.normalBorderFor(root.foreground, root.accent)
            z: on ? 1 : 0

            Row {
                id: inner
                anchors.centerIn: parent
                spacing: Style.spacing.md

                Text {
                    visible: !!chip.modelData.icon
                    text: chip.modelData.icon || ""
                    color: root.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.icon
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: chip.modelData.label
                    color: root.foreground
                    font.bold: chip.on
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    visible: chip.modelData.count !== undefined
                    text: chip.modelData.count === undefined ? "" : String(chip.modelData.count)
                    color: Util.alpha(root.foreground, 0.55)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            MouseArea {
                id: ma
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.picked(chip.modelData.value)
            }
        }
    }
}
