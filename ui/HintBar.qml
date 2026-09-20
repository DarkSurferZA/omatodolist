pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons

// Full-width row of Keycaps below the panel's content. Wraps to a second
// line instead of eliding — a cut-off shortcut list is worse than a taller
// footer.
Flow {
    id: root
    property var hints: []
    property color foreground: Color.foreground
    property bool urgent: false
    spacing: Style.space(14)

    Repeater {
        model: root.hints
        delegate: Keycap {
            required property var modelData
            k: modelData[0]
            l: modelData[1]
            foreground: root.urgent ? Color.urgent : root.foreground
        }
    }
}
