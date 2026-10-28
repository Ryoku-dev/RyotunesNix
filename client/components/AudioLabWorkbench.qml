pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Ryoku.Ui.Singletons
import "../"

// Single Audiophile instrument surface. Exactly one view owns audio capture.
// Spectrum keeps using the original Cava singleton; stereo scopes share one
// 25fps PCM capture bridge, activated only while their selected view is visible.
ColumnLayout {
    id: root
    property bool active: false
    property string mode: "spectrum"
    // Match the breathing room around Home controls: tabs sit above the panel,
    // never pressed against the plot's top border.
    spacing: Style.sp(4)
    // Preferred size of the global top strip; App owns its actual height.
    implicitHeight: Style.sp(48)

    RowLayout {
        Layout.fillWidth: true
        spacing: Style.sp(2)
        Chip {
            text: "Spectrum"
            active: root.mode === "spectrum"
            onClicked: root.mode = "spectrum"
        }
        Chip {
            text: "Oscilloscope"
            active: root.mode === "oscilloscope"
            onClicked: root.mode = "oscilloscope"
        }
        Chip {
            text: "Vectorscope"
            active: root.mode === "vectorscope"
            onClicked: root.mode = "vectorscope"
        }
        Item { Layout.fillWidth: true }
    }

    AudioSpectrumWorkbench {
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: root.mode === "spectrum"
        active: root.active && root.visible && root.mode === "spectrum"
    }
    AudioStereoScope {
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: root.mode !== "spectrum"
        active: root.active && root.visible && root.mode !== "spectrum"
        instrument: root.mode
    }
}
