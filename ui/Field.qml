import QtQuick
import qs.Commons
import qs.Ui

// Single-line text field pinned to Style.spacing.controlHeight and
// vertically centered — the kit's TextField pads for a taller default.
TextField {
    implicitHeight: Style.spacing.controlHeight
    topPadding: 0
    bottomPadding: 0
    verticalAlignment: TextInput.AlignVCenter
}
