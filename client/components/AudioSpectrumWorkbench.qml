pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Ryoku.Ui.Singletons
import "../"

// Audio Lab v1: real 40-band PipeWire/Cava spectrum, using the existing
// Spectrum singleton. No sample synthesis or simulated bars. The process only
// runs when this panel or another visible consumer has claimed it and music
// is playing. Curve and bars are two views of the same real spectrum.
Rectangle {
    id: root

    property bool active: false
    property string presentation: "bars"

    implicitHeight: Style.sp(46)
    radius: Style.radiusCard
    color: Tokens.paperLift
    border.width: 1
    border.color: Tokens.line
    clip: true

    function updateClaim() {
        Spectrum.claim("ryotunes-audio-lab-library", root.active && root.visible);
    }
    onActiveChanged: updateClaim()
    onVisibleChanged: updateClaim()
    Component.onCompleted: updateClaim()
    Component.onDestruction: Spectrum.claim("ryotunes-audio-lab-library", false)

    function rgba(c, alpha) {
        return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255)
            + "," + Math.round(c.b * 255) + "," + alpha + ")";
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Style.sp(3)
        spacing: Style.sp(2)

        RowLayout {
            Layout.fillWidth: true
            spacing: Style.sp(3)

            // Keep the view selector; the diagnostic header is unnecessary chrome.
            Item { Layout.fillWidth: true }
            Text {
                text: "BARS"
                color: root.presentation === "bars" ? Tokens.ink : Tokens.inkFaint
                font.family: Style.fontMono
                font.pixelSize: Style.fs.xs
                font.weight: root.presentation === "bars" ? Font.DemiBold : Font.Normal
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -Style.sp(2)
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.presentation = "bars"
                }
            }
            Rectangle {
                implicitWidth: 1
                implicitHeight: Style.sp(3)
                color: Tokens.line
            }
            Text {
                text: "CURVE"
                color: root.presentation === "curve" ? Tokens.ink : Tokens.inkFaint
                font.family: Style.fontMono
                font.pixelSize: Style.fs.xs
                font.weight: root.presentation === "curve" ? Font.DemiBold : Font.Normal
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -Style.sp(2)
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.presentation = "curve"
                }
            }
        }

        Canvas {
            id: chart
            Layout.fillWidth: true
            Layout.fillHeight: true
            renderTarget: Canvas.Image
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()

            Connections {
                target: Spectrum
                function onLevelsChanged() { if (root.active && root.visible) chart.requestPaint(); }
            }
            Connections {
                target: root
                function onPresentationChanged() { chart.requestPaint(); }
            }
            Connections {
                target: Style
                function onAccentChanged() { chart.requestPaint(); }
            }

            onPaint: {
                var c = getContext("2d");
                var w = width, h = height;
                c.clearRect(0, 0, w, h);
                if (w < 2 || h < 2) return;
                var left = Style.sp(1), right = w - Style.sp(1);
                var top = Style.sp(2), bottom = h - Style.sp(3);
                var cw = right - left, ch = bottom - top;
                if (cw <= 0 || ch <= 0) return;

                c.lineWidth = 1;
                c.strokeStyle = root.rgba(Tokens.inkFaint, 0.13);
                for (var gy = 1; gy < 4; gy++) {
                    var ly = top + ch * gy / 4;
                    c.beginPath(); c.moveTo(left, ly); c.lineTo(right, ly); c.stroke();
                }
                for (var gx = 1; gx < 8; gx++) {
                    var lx = left + cw * gx / 8;
                    c.beginPath(); c.moveTo(lx, top); c.lineTo(lx, bottom); c.stroke();
                }

                var values = Spectrum.levels || [];
                var n = Math.min(40, values.length);
                if (!Spectrum.analysing || n < 1) return;

                var slot = cw / n;
                var main = Style.accent;
                var low = root.rgba(main, 0.28);
                var bright = root.rgba(main, 0.92);
                var grad = c.createLinearGradient(0, bottom, 0, top);
                grad.addColorStop(0, low);
                grad.addColorStop(1, bright);

                if (root.presentation === "curve") {
                    c.beginPath(); c.moveTo(left, bottom);
                    for (var k = 0; k < n; k++) {
                        var value = Math.max(0, Math.min(1, Number(values[k]) || 0));
                        var px = left + (k + 0.5) * slot;
                        var py = bottom - Math.pow(value, 0.78) * ch;
                        c.lineTo(px, py);
                    }
                    c.lineTo(right, bottom); c.closePath();
                    c.fillStyle = grad; c.fill();
                    c.beginPath();
                    for (var j = 0; j < n; j++) {
                        var a = Math.max(0, Math.min(1, Number(values[j]) || 0));
                        var x = left + (j + 0.5) * slot;
                        var y = bottom - Math.pow(a, 0.78) * ch;
                        if (j === 0) c.moveTo(x, y); else c.lineTo(x, y);
                    }
                    c.strokeStyle = bright; c.lineWidth = 1.5; c.stroke();
                } else {
                    c.fillStyle = grad;
                    var bw = Math.max(1, slot * 0.77);
                    for (var i = 0; i < n; i++) {
                        var level = Math.max(0, Math.min(1, Number(values[i]) || 0));
                        if (level <= 0) continue;
                        var bh = Math.max(1, Math.pow(level, 0.78) * ch);
                        c.fillRect(left + i * slot + (slot - bw) / 2, bottom - bh, bw, bh);
                    }
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            Text {
                text: "LOW"
                color: Tokens.inkFaint
                font.family: Style.fontMono
                font.pixelSize: Style.fs.micro
            }
            Item { Layout.fillWidth: true }
            Text {
                text: "MID"
                color: Tokens.inkFaint
                font.family: Style.fontMono
                font.pixelSize: Style.fs.micro
            }
            Item { Layout.fillWidth: true }
            Text {
                text: "HIGH"
                color: Tokens.inkFaint
                font.family: Style.fontMono
                font.pixelSize: Style.fs.micro
            }
        }
    }

    Text {
        anchors.centerIn: parent
        visible: root.active && !Style.live
        text: Playback.now ? "PAUSED  ·  PLAY TO ANALYSE" : "PLAY A TRACK TO SEE THE SPECTRUM"
        color: Tokens.inkMuted
        font.family: Style.fontMono
        font.pixelSize: Style.fs.sm
    }
}
