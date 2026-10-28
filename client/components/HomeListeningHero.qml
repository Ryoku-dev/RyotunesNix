pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Ryoku.Ui.Singletons
import "../"

// A listening-first Home feature with an art-derived, static ambient wash.
// Riff-inspired composition, but Ryoku tokens, typography and native playback.
// The real player and its transport remain authoritative; no additional audio engine.
Rectangle {
    id: root

    readonly property var now: Playback.now
    readonly property bool compact: width < Style.sp(180)
    readonly property int artSize: Style.sp(root.compact ? 34 : 48)
    signal focusRequested()

    implicitHeight: Style.sp(root.compact ? 48 : 59)
    radius: Style.radiusCard
    color: Tokens.paperLift
    border.width: 1
    border.color: Tokens.lineSoft
    clip: true

    // Static cover atmosphere. One asynchronously loaded, bounded thumbnail; no blur
    // shader, timer, floating gradient or per-frame effect.
    Image {
        id: ambientCover
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        width: parent.width * 0.56
        source: root.now && root.now.thumbnail ? Style.thumb(root.now.thumbnail, 640) : ""
        sourceSize: Qt.size(640, 640)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        opacity: status === Image.Ready ? (root.compact ? 0.15 : 0.28) : 0
        Behavior on opacity {
            enabled: !Tokens.reduceMotion
            NumberAnimation { duration: Style.motion.slow }
        }
    }
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Tokens.paperLift }
            GradientStop {
                position: 0.57
                color: Qt.rgba(Tokens.paperLift.r, Tokens.paperLift.g, Tokens.paperLift.b, 0.91)
            }
            GradientStop {
                position: 1.0
                color: Qt.rgba(Tokens.paperLift.r, Tokens.paperLift.g, Tokens.paperLift.b, 0.46)
            }
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: Style.sp(root.compact ? 4 : 5)
        spacing: Style.sp(root.compact ? 3 : 7)

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumWidth: 0
            spacing: Style.sp(2)

            Text {
                text: Playback.paused ? "CONTINUE LISTENING" : "NOW PLAYING"
                color: Tokens.inkMuted
                font.family: Style.fontMono
                font.pixelSize: Style.fs.micro
                font.letterSpacing: Style.trackMicro
            }
            Text {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                text: root.now ? root.now.title : ""
                color: Tokens.ink
                font.family: Style.fontDisplay
                font.pixelSize: root.compact ? Style.fs.xl : Style.fs.hero
                elide: Text.ElideRight
                textFormat: Text.PlainText
            }
            Text {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                text: root.now ? root.now.artists : ""
                color: Tokens.inkMuted
                font.family: Style.fontUi
                font.pixelSize: Style.fs.md
                elide: Text.ElideRight
                textFormat: Text.PlainText
            }

            Item { Layout.fillHeight: true }

            RowLayout {
                Layout.fillWidth: true
                spacing: Style.sp(2)
                Btn {
                    text: Playback.paused ? "Resume" : "Pause"
                    icon: Playback.paused ? "play" : "pause"
                    primary: true
                    onClicked: Playback.togglePause().catch((e) =>
                        Playback.toast(String(e), "error"))
                }
                Btn {
                    visible: root.width >= Style.sp(147)
                    text: "Focus"
                    onClicked: root.focusRequested()
                }
                IconButton {
                    visible: root.width >= Style.sp(160)
                    icon: "queue"
                    tip: "Open queue"
                    outlined: true
                    diameter: Style.ctlH
                    onClicked: Playback.nowPlayingRequested("queue")
                }
                Item { Layout.fillWidth: true }
            }
        }

        Item {
            Layout.preferredWidth: root.artSize
            Layout.preferredHeight: root.artSize
            Layout.alignment: Qt.AlignVCenter
            Artwork {
                anchors.fill: parent
                px: root.artSize
                cornerRadius: Style.radiusCard
                url: root.now && root.now.thumbnail ? root.now.thumbnail : ""
            }
            // Artwork doubles as the entrance to the full Focus listening view.
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.focusRequested()
            }
        }
    }
}
