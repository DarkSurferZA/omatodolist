import QtQuick
import qs.Commons
import qs.Ui

// The kit's Button sizes to its content and an icon is taller than a label,
// so a button with an icon came out taller than one without. Every button
// in the panel goes through here to share one height.
Button {
    implicitHeight: Style.spacing.controlHeight
}
