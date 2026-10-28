pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Ryoku.Ui.Singletons
import "../"

// Real stereo PCM views. One on-demand Python/ffmpeg bridge runs while the
// selected instrument is visible AND Ryotunes is playing. Never records audio
// to disk, and never runs while showing the ordinary Spectrum instrument.
Rectangle {
    id: root
    property bool active: false
    property string instrument: "oscilloscope"  // oscilloscope | vectorscope
    property var sampleFrame: ({ wave: [], xy: [], phase: 0, rms: 0 })
    property string captureError: ""
    readonly property bool analysing: root.active && root.visible && Style.live

    implicitHeight: Style.sp(46)
    radius: Style.radiusCard
    color: Tokens.paperLift
    border.width: 1
    border.color: Tokens.line
    clip: true

    function rgba(color, alpha) {
        return "rgba(" + Math.round(color.r * 255) + "," + Math.round(color.g * 255)
            + "," + Math.round(color.b * 255) + "," + alpha + ")";
    }
    function readFrame(line) {
        try {
            var obj = JSON.parse(line);
            if (obj.error) {
                root.captureError = String(obj.error);
                return;
            }
            if (!Array.isArray(obj.wave) || !Array.isArray(obj.xy)) return;
            root.captureError = "";
            root.sampleFrame = obj;
        } catch (error) {
            root.captureError = "Stereo capture returned invalid data";
        }
    }

    onAnalysingChanged: {
        root.sampleFrame = ({ wave: [], xy: [], phase: 0, rms: 0 });
        if (root.analysing) root.captureError = "";
    }
    onInstrumentChanged: plot.requestPaint()
    onSampleFrameChanged: plot.requestPaint()

    Process {
        id: capture
        // Quickshell.shellDir is the root client directory, not the cwd.
        command: ["python3", Quickshell.shellDir + "/tools/audio_scope_bridge.py"]
        property bool backoff: false
        running: root.analysing && !capture.backoff
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (line) => root.readFrame(line)
        }
        onExited: {
            if (root.analysing) {
                capture.backoff = true;
                restartTimer.restart();
            }
        }
    }
    Timer { id: restartTimer; interval: 1400; onTriggered: capture.backoff = false }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Style.sp(3)
        spacing: Style.sp(2)

        Canvas {
            id: plot
            Layout.fillWidth: true
            Layout.fillHeight: true
            renderTarget: Canvas.Image
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            Connections {
                target: Style
                function onAccentChanged(): void { plot.requestPaint(); }
            }
            onPaint: {
                var ctx = getContext("2d");
                var w = width, h = height;
                ctx.clearRect(0, 0, w, h);
                if (w < 4 || h < 4) return;
                var left = Style.sp(2), top = Style.sp(2);
                var usableW = w - 2 * left, usableH = h - 2 * top;
                if (usableW <= 0 || usableH <= 0) return;

                ctx.strokeStyle = root.rgba(Tokens.inkFaint, 0.15);
                ctx.lineWidth = 1;
                for (var i = 1; i < 8; ++i) {
                    var gx = left + usableW * i / 8;
                    ctx.beginPath(); ctx.moveTo(gx, top); ctx.lineTo(gx, top + usableH); ctx.stroke();
                }
                for (var j = 1; j < 6; ++j) {
                    var gy = top + usableH * j / 6;
                    ctx.beginPath(); ctx.moveTo(left, gy); ctx.lineTo(left + usableW, gy); ctx.stroke();
                }

                ctx.strokeStyle = root.rgba(Tokens.inkFaint, 0.35);
                ctx.beginPath();
                ctx.moveTo(left, top + usableH / 2);
                ctx.lineTo(left + usableW, top + usableH / 2);
                ctx.stroke();
                if (!root.analysing) return;

                var packet = root.sampleFrame;
                if (root.instrument === "oscilloscope") {
                    var values = packet.wave || [];
                    if (values.length < 2) return;
                    ctx.lineWidth = 1.6;
                    ctx.strokeStyle = root.rgba(Style.accent, 0.95);
                    ctx.beginPath();
                    for (var k = 0; k < values.length; k++) {
                        var vx = left + k * usableW / (values.length - 1);
                        var vy = top + usableH / 2 - Math.max(-1, Math.min(1, values[k])) * usableH * 0.45;
                        if (k === 0) ctx.moveTo(vx, vy); else ctx.lineTo(vx, vy);
                    }
                    ctx.stroke();
                } else {
                    // X = (L - R)/sqrt(2), Y = (L + R)/sqrt(2).
                    // Mono is vertical; wide stereo spreads horizontally.
                    var pairs = packet.xy || [];
                    if (pairs.length < 2) return;
                    var side = Math.min(usableW, usableH) * 0.42;
                    var cx = left + usableW / 2, cy = top + usableH / 2;
                    ctx.strokeStyle = root.rgba(Tokens.inkFaint, 0.26);
                    ctx.beginPath(); ctx.moveTo(cx, cy - side); ctx.lineTo(cx, cy + side);
                    ctx.moveTo(cx - side, cy); ctx.lineTo(cx + side, cy); ctx.stroke();
                    ctx.fillStyle = root.rgba(Style.accent, 0.48);
                    for (var v = 0; v < pairs.length; v++) {
                        var a = Number(pairs[v][0]) || 0;
                        var b = Number(pairs[v][1]) || 0;
                        var px = cx + (a - b) * side * 0.70710678;
                        var py = cy - (a + b) * side * 0.70710678;
                        ctx.fillRect(px - 1, py - 1, 2, 2);
                    }
                }
            }
        }
    }

    Text {
        anchors.centerIn: parent
        visible: !root.analysing || root.captureError !== ""
            || (root.sampleFrame.rms || 0) < 0.0001
        text: root.captureError !== "" ? root.captureError
            : !Style.live ? (Playback.now ? "PAUSED  ·  PLAY TO ANALYSE" : "PLAY A TRACK TO ANALYSE")
            : "WAITING FOR STEREO AUDIO"
        color: Tokens.inkMuted
        font.family: Style.fontMono
        font.pixelSize: Style.fs.sm
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        width: parent.width - Style.sp(8)
    }
}
