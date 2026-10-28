pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Ryoku.Ui.Singletons
import "../"
import "../components"

// Ryotunes Focus Mode v2: a native, artwork-led listening space.
// Riff-inspired immersion; Ryotunes layout, tokens, playback and lyrics remain authoritative.
// Instantiated only while the user requests it. There is no secondary audio engine.
Item {
    id: root
    focus: true
    clip: true

    signal closeRequested()

    readonly property var now: Playback.now
    readonly property int artSize: Math.max(Style.sp(40), Math.min(
        Style.sp(110), Math.round(width * 0.34), Math.round(height * 0.48)))
    readonly property bool soundcloud: !!root.now && String(root.now.videoId).startsWith("sc:")
    property string coverFlash: ""

    Timer { id: flashTimer; interval: 220; onTriggered: root.coverFlash = "" }

    function togglePlayback() {
        root.coverFlash = Playback.paused ? "play" : "pause";
        flashTimer.restart();
        Playback.togglePause();
    }

    Rectangle { anchors.fill: parent; color: Tokens.paper }

    // Reuse the app's existing blurred-cover wash: static between track changes.
    Backdrop {
        anchors.fill: parent
        strength: 0.3
        focusX: 0.28
        focusY: 0.36
    }
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(Tokens.paper.r, Tokens.paper.g, Tokens.paper.b,
            Style.paperDark ? 0.28 : 0.5)
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: Style.sp(10)
        anchors.rightMargin: Style.sp(10)
        anchors.topMargin: Style.sp(6)
        anchors.bottomMargin: Style.sp(7)
        spacing: Style.sp(5)

        // The normal title bar and sidebar are hidden by App while Focus Mode is open.
        RowLayout {
            Layout.fillWidth: true
            spacing: Style.sp(3)

            Text {
                text: "力  RYOTUNES"
                color: Tokens.inkMuted
                font.family: Style.fontMono
                font.pixelSize: Style.fs.xs
                font.letterSpacing: Style.trackMicro
            }
            Item { Layout.fillWidth: true }
            IconButton {
                icon: "close"
                iconSize: Style.fs.lg
                diameter: Style.sp(9)
                outlined: true
                tip: "Leave Focus Mode"
                tipBelow: true
                onClicked: root.closeRequested()
            }
        }

        Hairline { Layout.fillWidth: true }

        RowLayout {
            id: listeningArea
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Style.sp(12)

            // Cover and track identity. Keep the original artwork shape; no Riff morph overlays.
            ColumnLayout {
                Layout.preferredWidth: Math.max(root.artSize, Math.round(root.width * 0.39))
                Layout.fillHeight: true
                spacing: Style.sp(3)

                // The stage should start near the editorial header, not float midway down
                // an otherwise empty full-height column. Leave the remaining room below.
                Item {
                    Layout.preferredHeight: Math.max(Style.sp(2),
                        Math.min(Style.sp(16), Math.round(root.height * 0.05)))
                }

                Item {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: root.artSize
                    Layout.preferredHeight: root.artSize

                    Artwork {
                        anchors.fill: parent
                        px: root.artSize
                        cornerRadius: Style.radiusCard
                        url: (root.now && root.now.thumbnail) ? root.now.thumbnail : ""
                    }
                    Rectangle {
                        anchors.fill: parent
                        radius: Style.radiusCard
                        color: "#66000000"
                        opacity: coverArea.containsMouse ? 1 : 0
                        Behavior on opacity {
                            enabled: !Tokens.reduceMotion
                            NumberAnimation { duration: Style.motion.snap }
                        }
                    }
                    Icon {
                        anchors.centerIn: parent
                        name: root.coverFlash !== "" ? root.coverFlash
                            : (Playback.paused ? "play" : "pause")
                        size: Style.fs.title
                        color: "#ffffff"
                        visible: root.coverFlash !== "" || coverArea.containsMouse
                    }
                    MouseArea {
                        id: coverArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.togglePlayback()
                    }
                }

                ColumnLayout {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.maximumWidth: Math.max(root.artSize, Style.sp(65))
                    spacing: Style.sp(1)

                    Text {
                        Layout.fillWidth: true
                        text: (root.now && root.now.title) ? root.now.title : "Nothing playing"
                        textFormat: Text.PlainText
                        color: Tokens.ink
                        font.family: Style.fontDisplay
                        font.pixelSize: Style.fs.title
                        maximumLineCount: 2
                        wrapMode: Text.WordWrap
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignHCenter
                    }
                    Text {
                        Layout.fillWidth: true
                        text: (root.now && root.now.artists) ? root.now.artists : ""
                        textFormat: Text.PlainText
                        color: Tokens.inkMuted
                        font.family: Style.fontUi
                        font.pixelSize: Style.fs.md
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root.soundcloud ? "SOUNDCLOUD" : Playback.provider.toUpperCase()
                        color: Tokens.inkFaint
                        font.family: Style.fontMono
                        font.pixelSize: Style.fs.micro
                        font.letterSpacing: Style.trackMicro
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                Item { Layout.fillHeight: true }
            }

            // Reuse the existing lyrics component: word timings, seek-to-line, source fallback,
            // reduced motion and the visibility-gated timer all remain in one implementation.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Style.sp(3)

                // Focus typography is an opt-in display treatment. The lyric data,
                // scrolling, network requests and timing remain owned by LyricsPanel.
                LyricsPanel {
                    id: lyricsView
                    focusMode: true
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                }
            }
        }

        Hairline { Layout.fillWidth: true }

        // One transport. The daemon remains the only authority for playback and volume.
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.sp(3)

            RowLayout {
                Layout.fillWidth: true
                spacing: Style.sp(3)
                Text {
                    text: Style.fmtTime(Playback.shownPosition)
                    color: Tokens.inkFaint
                    font.family: Style.fontMono
                    font.pixelSize: Style.fs.xs
                }
                Slider {
                    Layout.fillWidth: true
                    from: 0
                    to: Math.max(1, Playback.duration)
                    value: Playback.shownPosition
                    trackColor: Tokens.lineStrong
                    fillColor: Style.accent
                    onMoved: (v) => Playback.seekDrag = v
                    onCommitted: (v) => {
                        Playback.seekDrag = NaN;
                        Playback.seek(v).catch((e) => Playback.toast(
                            (e && e.message) ? e.message : "Seek failed", "error"));
                    }
                }
                Text {
                    text: Style.fmtTime(Playback.duration)
                    color: Tokens.inkFaint
                    font.family: Style.fontMono
                    font.pixelSize: Style.fs.xs
                }
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: Style.sp(4)
                IconButton {
                    icon: "shuffle"
                    tip: "Shuffle"
                    active: !!(Playback.queue && Playback.queue.shuffle)
                    onClicked: Playback.toggleShuffle()
                }
                IconButton {
                    icon: "previous"
                    iconSize: Style.fs.lg
                    diameter: Style.sp(10)
                    tip: "Previous track"
                    onClicked: Playback.prev()
                }
                IconButton {
                    icon: Playback.paused ? "play" : "pause"
                    iconSize: Style.fs.xl
                    diameter: Style.sp(13)
                    primary: true
                    tip: Playback.paused ? "Play" : "Pause"
                    onClicked: root.togglePlayback()
                }
                IconButton {
                    icon: "next"
                    iconSize: Style.fs.lg
                    diameter: Style.sp(10)
                    tip: "Next track"
                    onClicked: Playback.next()
                }
                IconButton {
                    icon: (Playback.queue && Playback.queue.repeat === "one") ? "repeat-one" : "repeat"
                    tip: "Repeat"
                    active: !!(Playback.queue && Playback.queue.repeat && Playback.queue.repeat !== "off")
                    onClicked: Playback.cycleRepeat()
                }
            }
        }
    }
}
