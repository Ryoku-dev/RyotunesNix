pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Ryoku.Ui.Singletons
import "../"
import "../components"

// The Sound dialog (spec section 7): a Ryotunes feature ordinary players do not have. A centred
// modal over a snapshot-blurred freeze of the frame behind it (spec 9 — the page is captured once
// with our own visuals hidden, blurred, then a scrim, so no live subtree is ever blurred). Five
// sliders drive the daemon's audio-fx chain (tempo, pitch, reverb, bass, width) with a row of
// presets; every change is applied debounced 80 ms and the daemon echoes the authoritative values
// back through Playback.audioFx. The App hosts this in a Loader { active: app.soundOpen } and wires
// onCloseRequested; it needs nothing else from us.
Item {
    id: root

    anchors.fill: parent
    focus: true
    signal closeRequested()

    // The working copy the sliders edit, seeded from the daemon mirror when the dialog opens. Kept
    // local (not a live binding to Playback.audioFx) so a drag is not fought by the echo it causes.
    property var fx: ({ speed: 1, semitones: 0, reverb: 0, bass: 0, width: 0, eq: ({ enabled: false, bands: [] }) })
    property bool equalizerOpen: false
    property int selectedEqBand: 10
    // Snapshot state. `snapReady` gates the blur (the frozen frame is drawn once, then blurred);
    // `shown` reveals the card and scrim. Both flip when the capture completes, so the snapshot is
    // the frame alone — but a fallback timer flips `shown` regardless, so a build where the capture
    // never completes still shows a usable dialog (over the unblurred page) instead of nothing.
    property bool snapReady: false
    property bool shown: false

    readonly property var presets: [
        { name: "Flat", fx: { speed: 1, semitones: 0, reverb: 0, bass: 0, width: 0 } },
        { name: "Slowed + Reverb", fx: { speed: 0.85, semitones: 0, reverb: 0.6, bass: 0, width: 0 } },
        { name: "Nightcore", fx: { speed: 1.25, semitones: 2, reverb: 0, bass: 0, width: 0 } },
        { name: "Bass Boost", fx: { speed: 1, semitones: 0, reverb: 0, bass: 8, width: 0 } },
        { name: "Wide", fx: { speed: 1, semitones: 0, reverb: 0, bass: 0, width: 0.8 } }
    ]

    Component.onCompleted: {
        var a = Playback.audioFx;
        root.fx = { speed: a.speed, semitones: a.semitones, reverb: a.reverb, bass: a.bass, width: a.width, eq: a.eq || root.defaultEq() };
        // Snapshot the frame behind us. Capture the frame-level item (the child of the window's
        // content root), not the root itself — a plain Item renders to a texture, the window root
        // does not — walking up until the next parent would be that root, whatever the nesting.
        var p = root.parent;
        while (p && p.parent && p.parent.parent)
            p = p.parent;
        frozen.sourceItem = p;
        frozen.scheduleUpdate();
        root.forceActiveFocus();
        reveal.start();
    }
    Keys.onEscapePressed: (e) => { root.closeRequested(); e.accepted = true; }

    function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)); }
    function defaultEq() {
        const hz = [32, 45, 64, 90, 125, 180, 250, 350, 500, 700,
                    1000, 1400, 2000, 2800, 4000, 5600, 8000, 11000, 15000, 19000];
        return { enabled: false, bands: hz.map(frequency => ({ frequency: frequency, gain: 0, q: 1 })) };
    }
    function activeBand() {
        const bands = root.fx.eq && root.fx.eq.bands ? root.fx.eq.bands : [];
        return bands[root.selectedEqBand] || { frequency: 1000, gain: 0, q: 1 };
    }
    function setEqEnabled(enabled) {
        root.patch({ eq: Object.assign({}, root.fx.eq, { enabled: enabled }) });
    }
    function setEqBand(index, changes) {
        const bands = root.fx.eq.bands.map((band, i) => i === index
            ? Object.assign({}, band, changes) : band);
        root.patch({ eq: Object.assign({}, root.fx.eq, { bands: bands }) });
    }
    function setEqGain(index, value) {
        root.setEqBand(index, { gain: root.clamp(Math.round(value * 10) / 10, -12, 12) });
    }
    function setEqQ(index, value) {
        root.setEqBand(index, { q: root.clamp(Math.round(value * 10) / 10, 0.3, 10) });
    }
    function setEqFrequency(index, position) {
        const frequency = 20 * Math.pow(1000, root.clamp(position, 0, 1));
        root.setEqBand(index, { frequency: Math.round(frequency) });
    }
    function resetEq() { root.patch({ eq: root.defaultEq() }); }
    // Reassign fx as a whole so the slider bindings (and preset-active state) refresh, then apply
    // after 80 ms of quiet — a drag coalesces into one daemon call instead of one per frame.
    function patch(p) { root.fx = Object.assign({}, root.fx, p); apply.restart(); }
    function setSpeed(v) { root.patch({ speed: root.clamp(Math.round(v / 0.05) * 0.05, 0.25, 2.0) }); }
    function setPitch(v) { root.patch({ semitones: root.clamp(Math.round(v), -12, 12) }); }
    function setReverb(v) { root.patch({ reverb: root.clamp(Math.round(v * 100) / 100, 0, 1) }); }
    function setBass(v) { root.patch({ bass: root.clamp(Math.round(v), -6, 12) }); }
    function setWidth(v) { root.patch({ width: root.clamp(Math.round(v * 100) / 100, 0, 1) }); }
    function applyPreset(p) { root.patch(p); }
    function presetActive(p) {
        return root.fx.speed === p.speed && root.fx.semitones === p.semitones
            && root.fx.reverb === p.reverb && root.fx.bass === p.bass && root.fx.width === p.width;
    }

    Timer {
        id: apply
        interval: 80
        onTriggered: Playback.setAudioFx(root.fx).catch((e) => Playback.toast((e && e.message) ? e.message : "Sound settings failed", "error"))
    }
    // The capture normally reveals the card; this is the floor so it appears even if the frame's
    // one-shot render never signals completion.
    Timer { id: reveal; interval: 140; onTriggered: root.shown = true }

    // ── the spec-9 snapshot blur ─────────────────────────────────────────────────────────────
    ShaderEffectSource {
        id: frozen
        anchors.fill: parent
        live: false
        recursive: false
        visible: false
        onScheduledUpdateCompleted: { root.snapReady = true; root.shown = true; }
    }
    MultiEffect {
        anchors.fill: parent
        source: frozen
        visible: Style.blurEnabled && root.snapReady
        blurEnabled: true
        blur: 1.0
        blurMax: 32
    }
    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: root.shown ? 0.5 : 0
        Behavior on opacity { NumberAnimation { duration: Style.motion.swap } }
    }
    MouseArea {
        anchors.fill: parent
        enabled: root.shown
        onClicked: root.closeRequested()
    }

    // ── the card ─────────────────────────────────────────────────────────────────────────────
    Rectangle {
        id: card
        anchors.centerIn: parent
        width: root.equalizerOpen
            ? Math.min(Style.sp(236), root.width - Style.sp(12))
            : Style.sp(120)
        implicitHeight: col.implicitHeight + Style.sp(12)
        height: implicitHeight
        radius: Style.radiusCard
        color: Tokens.paper
        border.width: 1
        border.color: Tokens.line
        visible: root.shown
        opacity: root.shown ? 1 : 0
        scale: root.shown ? 1 : 0.98
        Behavior on opacity { NumberAnimation { duration: Style.motion.swap } }
        Behavior on scale { NumberAnimation { duration: Style.motion.swap; easing.type: Easing.OutCubic } }

        // Swallow clicks so they never reach the dismiss layer behind.
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: col
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.sp(6)
            spacing: Style.sp(5)

            // header
            RowLayout {
                Layout.fillWidth: true
                spacing: Style.sp(3)
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Style.sp(1)
                    Text {
                        text: "Sound"
                        color: Tokens.ink
                        font.family: Style.fontDisplay
                        font.pixelSize: Style.fs.xl
                    }
                }
                Chip {
                    text: root.equalizerOpen ? "EFFECTS" : "20-BAND EQ"
                    active: root.equalizerOpen
                    onClicked: root.equalizerOpen = !root.equalizerOpen
                }
                IconButton {
                    Layout.alignment: Qt.AlignTop
                    icon: "close"
                    iconSize: Style.fs.md
                    onClicked: root.closeRequested()
                }
            }

            // sliders
            ColumnLayout {
                visible: !root.equalizerOpen
                Layout.fillWidth: true
                spacing: Style.sp(4)
                FxRow {
                    label: "Tempo"
                    value: root.fx.speed.toFixed(2) + "\u00D7"
                    from: 0.25; to: 2.0; val: root.fx.speed
                    onMoved: (v) => root.setSpeed(v)
                }
                FxRow {
                    label: "Pitch"
                    value: (root.fx.semitones > 0 ? "+" : "") + root.fx.semitones + " st"
                    from: -12; to: 12; val: root.fx.semitones
                    onMoved: (v) => root.setPitch(v)
                }
                FxRow {
                    label: "Reverb"
                    value: Math.round(root.fx.reverb * 100) + "%"
                    from: 0; to: 1; val: root.fx.reverb
                    onMoved: (v) => root.setReverb(v)
                }
                FxRow {
                    label: "Bass"
                    value: (root.fx.bass > 0 ? "+" : "") + root.fx.bass + " dB"
                    from: -6; to: 12; val: root.fx.bass
                    onMoved: (v) => root.setBass(v)
                }
                FxRow {
                    label: "Width"
                    value: Math.round(root.fx.width * 100) + "%"
                    from: 0; to: 1; val: root.fx.width
                    onMoved: (v) => root.setWidth(v)
                }
            }

            ColumnLayout {
                visible: root.equalizerOpen
                Layout.fillWidth: true
                spacing: Style.sp(3)

                // The equalizer is a listening surface, not a scrolling form.
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.sp(3)
                    Item { Layout.fillWidth: true }
                    Chip {
                        text: root.fx.eq.enabled ? "ON" : "BYPASS"
                        active: root.fx.eq.enabled
                        onClicked: root.setEqEnabled(!root.fx.eq.enabled)
                    }
                    Chip {
                        text: "FLAT"
                        onClicked: root.resetEq()
                    }
                }

                // One response drawing; it repaints only when the EQ data changes.
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.max(Style.sp(24),
                        Math.min(Style.sp(38), root.height * 0.13))

                    Rectangle {
                        anchors.fill: parent
                        color: Tokens.paperLift
                        radius: Style.radius
                    }

                    Canvas {
                        id: eqGraph
                        anchors.fill: parent
                        anchors.margins: Style.sp(3)
                        onPaint: {
                            const ctx = getContext("2d");
                            ctx.clearRect(0, 0, width, height);
                            const bands = root.fx.eq && root.fx.eq.bands ? root.fx.eq.bands : [];
                            const dbAt = function(hz) {
                                let db = 0;
                                for (const band of bands) {
                                    const delta = Math.log(hz / Math.max(1, band.frequency)) / Math.LN2;
                                    const spread = 1 / Math.max(0.3, band.q);
                                    db += band.gain * Math.exp(-0.5 * Math.pow(delta / spread, 2));
                                }
                                return Math.max(-18, Math.min(18, db));
                            };
                            const yAt = function(db) {
                                return height / 2 - db * height / 42;
                            };

                            // Quiet grid, with a slightly stronger zero-gain axis.
                            ctx.lineWidth = 1;
                            for (const db of [-12, -6, 0, 6, 12]) {
                                const y = yAt(db);
                                ctx.globalAlpha = db === 0 ? 0.38 : 0.16;
                                ctx.strokeStyle = Tokens.inkMuted;
                                ctx.beginPath();
                                ctx.moveTo(0, y);
                                ctx.lineTo(width, y);
                                ctx.stroke();
                            }
                            for (const hz of [100, 1000, 10000]) {
                                const x = width * Math.log(hz / 20) / Math.log(1000);
                                ctx.globalAlpha = 0.16;
                                ctx.beginPath();
                                ctx.moveTo(x, 0);
                                ctx.lineTo(x, height);
                                ctx.stroke();
                            }

                            // Preview of the combined response. The player is authoritative.
                            ctx.globalAlpha = root.fx.eq.enabled ? 0.95 : 0.28;
                            ctx.strokeStyle = Style.accent;
                            ctx.lineWidth = 2;
                            ctx.beginPath();
                            for (let x = 0; x <= width; x += 2) {
                                const hz = 20 * Math.pow(1000, x / Math.max(1, width));
                                const y = yAt(dbAt(hz));
                                if (x === 0) ctx.moveTo(x, y);
                                else ctx.lineTo(x, y);
                            }
                            ctx.lineTo(width, yAt(dbAt(20000)));
                            ctx.stroke();

                            // Selected band's position, so frequency edits have context.
                            const selected = root.activeBand();
                            const sx = Math.max(0, Math.min(width,
                                width * Math.log(Math.max(20, selected.frequency) / 20) / Math.log(1000)));
                            const sy = yAt(dbAt(Math.max(20, selected.frequency)));
                            ctx.globalAlpha = root.fx.eq.enabled ? 0.8 : 0.3;
                            ctx.strokeStyle = Tokens.inkMuted;
                            ctx.lineWidth = 1;
                            ctx.beginPath();
                            ctx.moveTo(sx, 0);
                            ctx.lineTo(sx, height);
                            ctx.stroke();
                            ctx.globalAlpha = 1;
                            ctx.fillStyle = Style.accent;
                            ctx.beginPath();
                            ctx.arc(sx, sy, Style.sp(1.1), 0, Math.PI * 2);
                            ctx.fill();
                        }
                        Connections {
                            target: root
                            function onFxChanged() { eqGraph.requestPaint(); }
                            function onSelectedEqBandChanged() { eqGraph.requestPaint(); }
                        }
                    }
                }

                // Every band stays instantiated during dragging. No Flickable stealing
                // pointer gestures and no delegate recreation on gain updates.
                Row {
                    id: faderRow
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.max(Style.sp(34),
                        Math.min(Style.sp(47), root.height * 0.19))
                    spacing: 0

                    Repeater {
                        model: 20
                        delegate: Item {
                            id: fader
                            required property int index
                            readonly property var band: root.fx.eq.bands[fader.index]
                            readonly property bool selected: root.selectedEqBand === fader.index
                            readonly property real gain: fader.band ? fader.band.gain : 0
                            width: faderRow.width / 20
                            height: faderRow.height

                            function gainAt(y) {
                                if (gainTrack.height <= 0) return;
                                const fraction = Math.max(0, Math.min(1, y / gainTrack.height));
                                root.setEqGain(fader.index, 12 - 24 * fraction);
                            }

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 1
                                radius: Style.radius
                                color: Tokens.paperLift
                                opacity: fader.selected ? 1 : 0
                            }
                            Text {
                                anchors.top: parent.top
                                anchors.topMargin: Style.sp(1)
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                text: (fader.gain > 0 ? "+" : "")
                                    + Number(fader.gain).toFixed(1)
                                color: fader.selected ? Tokens.ink : Tokens.inkFaint
                                font.family: Style.fontMono
                                font.pixelSize: Style.fs.micro
                                visible: fader.selected || Math.abs(fader.gain) > 0.05
                            }
                            Item {
                                id: gainTrack
                                anchors.top: parent.top
                                anchors.topMargin: Style.sp(7)
                                anchors.bottom: freqLabel.top
                                anchors.bottomMargin: Style.sp(3)
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: Math.max(Style.sp(5), fader.width - Style.sp(1))

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 2
                                    height: parent.height
                                    radius: 1
                                    color: Tokens.lineStrong
                                }
                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: Math.min(parent.height / 2,
                                        (12 - fader.gain) / 24 * parent.height)
                                    width: 3
                                    height: Math.max(0.5, Math.abs(parent.height / 2 -
                                        (12 - fader.gain) / 24 * parent.height))
                                    radius: 1
                                    color: Style.accent
                                    opacity: root.fx.eq.enabled ? 1 : 0.35
                                }
                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: Math.max(0, Math.min(parent.height - height,
                                        (12 - fader.gain) / 24 * parent.height - height / 2))
                                    width: Math.max(Style.sp(3), fader.width - Style.sp(2))
                                    height: Style.sp(1.3)
                                    radius: height / 2
                                    color: fader.selected ? Style.accent : Tokens.inkMuted
                                }
                                MouseArea {
                                    id: gainMouse
                                    anchors.fill: parent
                                    preventStealing: true
                                    cursorShape: Qt.SizeVerCursor
                                    onPressed: (mouse) => {
                                        root.selectedEqBand = fader.index;
                                        fader.gainAt(mouse.y);
                                    }
                                    onPositionChanged: (mouse) => {
                                        if (gainMouse.pressed) fader.gainAt(mouse.y);
                                    }
                                    onReleased: (mouse) => fader.gainAt(mouse.y)
                                }
                            }
                            Text {
                                id: freqLabel
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: Style.sp(1)
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                text: {
                                    const hz = fader.band ? fader.band.frequency : 0;
                                    return hz >= 1000
                                        ? (hz / 1000).toFixed(hz % 1000 === 0 ? 0 : 1) + "k"
                                        : String(Math.round(hz));
                                }
                                color: fader.selected ? Tokens.ink : Tokens.inkMuted
                                font.family: Style.fontMono
                                font.pixelSize: Style.fs.micro
                                font.weight: fader.selected ? Font.DemiBold : Font.Normal
                            }
                        }
                    }
                }

                // Precision controls are always scoped to the selected band.
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.sp(4)
                    ColumnLayout {
                        Layout.preferredWidth: Style.sp(27)
                        spacing: Style.sp(1)
                        Text {
                            text: "BAND " + (root.selectedEqBand + 1) + " / 20"
                            color: Tokens.inkMuted
                            font.family: Style.fontMono
                            font.pixelSize: Style.fs.micro
                        }
                        Text {
                            text: (root.activeBand().gain > 0 ? "+" : "")
                                + Number(root.activeBand().gain).toFixed(1) + " dB"
                            color: Tokens.ink
                            font.family: Style.fontDisplay
                            font.pixelSize: Style.fs.lg
                        }
                    }
                    FxRow {
                        Layout.fillWidth: true
                        label: "Frequency"
                        naturalLabel: true
                        value: Math.round(root.activeBand().frequency) + " Hz"
                        from: 0
                        to: 1
                        val: Math.log(root.activeBand().frequency / 20) / Math.log(1000)
                        onMoved: (v) => root.setEqFrequency(root.selectedEqBand, v)
                    }
                    FxRow {
                        Layout.fillWidth: true
                        label: "Q"
                        naturalLabel: true
                        value: Number(root.activeBand().q).toFixed(1)
                        from: 0.3
                        to: 10
                        val: root.activeBand().q
                        onMoved: (v) => root.setEqQ(root.selectedEqBand, v)
                    }
                }
            }
            Hairline { Layout.fillWidth: true }

            // presets
            ColumnLayout {
                visible: !root.equalizerOpen
                Layout.fillWidth: true
                spacing: Style.sp(3)
                Text {
                    text: "PRESETS"
                    color: Tokens.inkFaint
                    font.family: Style.fontMono
                    font.pixelSize: Style.fs.micro
                    font.letterSpacing: Style.trackMicro
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: Style.sp(2)
                    Repeater {
                        model: root.presets
                        delegate: Chip {
                            id: chip
                            required property var modelData
                            text: chip.modelData.name
                            active: root.presetActive(chip.modelData.fx)
                            onClicked: root.applyPreset(chip.modelData.fx)
                        }
                    }
                }
            }
        }
    }

    // One slider row: a label, its live value, and the drag control. `moved` carries the raw slider
    // value up; the parent quantizes and clamps it per field.
    component FxRow: RowLayout {
        id: r
        property string label: ""
        property string value: ""
        property bool naturalLabel: false
        property real from: 0
        property real to: 1
        property real val: 0
        signal moved(real v)

        Layout.fillWidth: true
        spacing: Style.sp(3)

        Text {
            Layout.preferredWidth: r.naturalLabel ? implicitWidth : Style.sp(16)
            text: r.label
            color: Tokens.ink
            font.family: Style.fontUi
            font.pixelSize: Style.fs.md
        }
        Slider {
            Layout.fillWidth: true
            from: r.from
            to: r.to
            value: r.val
            onMoved: (v) => r.moved(v)
            onCommitted: (v) => r.moved(v)
        }
        Text {
            Layout.preferredWidth: Style.sp(14)
            horizontalAlignment: Text.AlignRight
            text: r.value
            color: Tokens.inkMuted
            font.family: Style.fontMono
            font.pixelSize: Style.fs.xs
        }
    }
}
