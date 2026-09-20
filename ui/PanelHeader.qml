import QtQuick
import QtQuick.Layouts
import qs.Commons
import "Icons.js" as Icons

RowLayout {
    id: root

    property QtObject db: null
    property int activeTab: 0
    property color foreground: Color.foreground

    signal tabPicked(int index)
    signal newRequested()

    spacing: Style.spacing.xxl

    Segment {
        Layout.preferredWidth: Style.space(260)
        options: [
            { value: "0", label: "Items", icon: Icons.all, count: root.db ? root.db.totalNotes + root.db.totalTodos : 0 },
            { value: "1", label: "History", icon: Icons.history, count: root.db ? root.db.history.length : 0 }
        ]
        value: String(root.activeTab)
        foreground: root.foreground
        onPicked: function(v) { root.tabPicked(Number(v)) }
    }

    Item { Layout.fillWidth: true }

    Text {
        text: (root.db ? root.db.unreadNotes : 0) + " unread · " + (root.db ? root.db.inProgressTodos : 0) + " open"
        color: Util.alpha(root.foreground, 0.62)
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
    }

    ActionButton {
        bordered: true
        selected: true
        iconText: Icons.plus
        text: "New"
        tooltipText: "New item (n)"
        foreground: root.foreground
        onClicked: root.newRequested()
    }
}
