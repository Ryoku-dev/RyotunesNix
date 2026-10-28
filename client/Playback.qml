pragma Singleton
import QtQuick
import Quickshell
import "lib/playback.js" as PB

// The client's only playback state: a mirror of the daemon, never a source of truth. Every event
// from Daemon is applied by lib/playback.js applyEvent (ported from player.svelte.ts); every method
// is a daemon call. The opening snapshot from `subscribe` seeds the same properties. Optimistic UI
// is confined to `seekDrag` (the held seek thumb) and `volDrag` (the held volume slider).
Singleton {
    id: root

    // --- mirrored state ----------------------------------------------------------------------
    property var now: null
    // The playing cover's sampled accent (components/ArtAccent); transparent until sampled.
    property color artAccent: "transparent"
    property var queue: ({ items: [], currentIndex: 0 })
    property real position: 0
    property real duration: 0
    property bool paused: false
    property int volume: 100
    property bool stopAfterCurrent: false
    property string rating: "indifferent"
    property var pendingVideoId: null
    property var lastError: null
    property var lyrics: ({ synced: false, lines: [] })
    property var auth: ({ signedIn: false })
    property var settings: ({})
    property var lt: ({ role: "none" })
    // The Sound dialog's effects, mirrored from the daemon (the `audio-fx` event and the subscribe
    // snapshot). `bass` is dB, reverb/width are 0..1, speed is the tempo multiplier.
    property var audioFx: ({ speed: 1, semitones: 0, reverb: 0, bass: 0, width: 0 })
    // The active music provider ("youtube" | "spotify" | "soundcloud" | "tidal"), mirrored from the daemon
    // (the subscribe snapshot's `provider` and a `provider-changed` event). The title bar's switch
    // reads it; each catalogue's own sign-in state gates its shelves, not the selector.
    property string provider: "youtube"
    // The Spotify account, mirrored from the daemon (the subscribe snapshot's `spotify` object and
    // the `spotify-auth` events). `signedIn` gates the Spotify catalogue; `premium` is null until the
    // profile is known. Never a source of truth — every field lands from the daemon.
    property var spotify: ({ signedIn: false, stored: false, name: null, premium: null })
    // The SoundCloud account, mirrored the same way (the snapshot's `soundcloud` object and the
    // `soundcloud-auth` events). SoundCloud browses and plays as a guest; signing in only adds
    // the account's own shelves (playlists, likes, following) to Home.
    property var soundcloud: ({ signedIn: false, name: null, error: "" })

    // The TIDAL account. Unlike SoundCloud there is no guest catalogue, so a signed-out TIDAL
    // shows a sign-in prompt rather than a browsable home. `quality` is the best tier the session
    // can actually reach, which the device flow caps below hi-res; `hasCredentials` stays true
    // while the daemon ships a pair and only turns false if a host clears one.
    property var tidal: ({ signedIn: false, name: null, quality: null, hasCredentials: false,
        code: "", url: "", error: "" })

    // --- SoundCloud waveform cache -----------------------------------------------------------
    // The playing track's 240 amplitude samples (get_waveform), for the Orange seek bar; null for a
    // non-SoundCloud track or before it resolves. Cached per video id so switching back to a track
    // (or reopening the stage) never refetches. Only SoundCloud ids ("sc:") carry a waveform.
    property var waveform: null
    property var waveformCache: ({})

    // --- optimistic drag state ---------------------------------------------------------------
    // NaN when the seek thumb is not held; a number pins the shown position and suppresses the
    // daemon's position echoes until release.
    property real seekDrag: NaN
    // The position the UI should render: the held thumb while dragging, else the live sample.
    readonly property real shownPosition: isNaN(root.seekDrag) ? root.position : root.seekDrag
    // True while the volume slider is held, so a volume echo cannot yank the thumb backwards.
    property bool volDrag: false

    // A message the daemon surfaced (error/notice/cover-error/lt-notice), for the toast layer.
    signal toast(string message, string kind)
    // A page asking the App to open the Now Playing overlay on a tab ("queue" | "lyrics").
    signal nowPlayingRequested(string tab)
    // A surface (player-bar tools, track menu) asking the App to open the Sound dialog.
    signal soundRequested()

    // --- Spotify Soloist: use the same player bar, not a second interface ---------------------
    // The Rust daemon forwards native Soloist updates as "soloist-event". A sparse snapshot
    // poll repairs late attachment and daemon reconnects without depending on event timing.
    property bool soloistLoading: false
    property string soloistError: ""

    function soloistTrack(n) {
        if (!n || !n.videoId) return;
        var seconds = Math.max(0, Math.round(Number(n.durationMs || 0) / 1000));
        var minutes = Math.floor(seconds / 60);
        var rem = (seconds % 60).toString().padStart(2, "0");
        root.now = {
            videoId: n.videoId,
            title: n.title || "Unknown track",
            artists: n.artists || "",
            artist: n.artists || "",
            album: n.album || "",
            thumbnail: n.thumbnail || "",
            duration: minutes + ":" + rem,
            rating: "indifferent"
        };
        root.duration = Math.max(0, Number(n.durationMs || 0) / 1000);
        root.position = PB.clampPosition(root.duration, Number(n.positionMs || 0) / 1000);
        root.paused = !!n.paused;
        root.volume = Number(n.volume === undefined ? root.volume : n.volume);
        Daemon.soloistPaused = root.paused;
        root.pendingVideoId = null;
        root.lastError = null;
        root.soloistError = "";
        root.soloistEnsureQueue();
    }

    function soloistEnsureQueue() {
        if (!root.now) return;
        var q = root.queue || {};
        var items = q.items || [];
        if (!items.length || items[0].video_id !== root.now.videoId) {
            root.queue = {
                items: [{ video_id: root.now.videoId, title: root.now.title,
                    artists: root.now.artists, thumbnail: root.now.thumbnail,
                    duration: root.now.duration }],
                currentIndex: 0, shuffle: Daemon.soloistShuffle,
                repeat: q.repeat || "off", sourceName: "Spotify"
            };
        }
        Daemon.soloistQueueItems = root.queue.items;
    }

    function soloistReadQueue(source) {
        if (!source || root.provider !== "spotify") return;
        var rows = source.queue || source.items || source.tracks || source.next_tracks || [];
        if (!Array.isArray(rows)) rows = rows.items || rows.tracks || [];
        var current = root.now ? [{ video_id: root.now.videoId,
            title: root.now.title, artists: root.now.artists,
            thumbnail: root.now.thumbnail, duration: root.now.duration }] : [];
        for (var i = 0; i < rows.length; i++) {
            var item = rows[i].item || rows[i].track || rows[i];
            var id = item.uri || item.video_id || item.videoId || "";
            if (!String(id).startsWith("spotify:track:")) continue;
            if (current.length && current[0].video_id === id) continue;
            var dec = item.decorations || {};
            var creators = dec.creators || [];
            var artists = creators.map(c => (c.entity && c.entity.decorations
                && c.entity.decorations.identity || {}).name || "").filter(Boolean).join(", ");
            var covers = (dec.visual_identity && dec.visual_identity.cover) || [];
            var cover = covers.filter(c => c.size === "large")[0] || covers[covers.length - 1];
            var secs = Math.round(((dec.playback || {}).duration_ms || 0) / 1000);
            current.push({ video_id: id,
                title: (dec.identity || {}).name || item.title || "Unknown track",
                artists: artists || item.artists || "",
                thumbnail: (cover && cover.url) || item.thumbnail || "",
                duration: Math.floor(secs / 60) + ":" + (secs % 60).toString().padStart(2, "0") });
        }
        var old = root.queue || {};
        root.queue = { items: current, currentIndex: 0, shuffle: Daemon.soloistShuffle,
            repeat: old.repeat || "off", sourceName: "Spotify" };
        Daemon.soloistQueueItems = current;
    }

    function soloistEvent(event) {
        if (!event || root.provider !== "spotify") return;
        var src = event.source || {};
        if (event.kind === "playback_state" && event.now) {
            root.soloistTrack(event.now);
            if (src.options) root.soloistOptions(src.options);
        } else if (event.kind === "position_sync" && src.position) {
            root.position = PB.clampPosition(root.duration, Number(src.position.position_ms || 0) / 1000);
        } else if (event.kind === "playback_changed") {
            root.paused = src.status !== "playing";
            Daemon.soloistPaused = root.paused;
        } else if (event.kind === "volume_changed") {
            if (!root.volDrag && typeof src.volume === "number") root.volume = src.volume;
        } else if (event.kind === "queue_changed") {
            root.soloistReadQueue(src);
        } else if (event.kind === "options_changed") {
            root.soloistOptions(src.options || src);
        } else if (event.kind === "track_changed") {
            root.soloistRefresh();
        }
    }

    function soloistOptions(o) {
        if (!o) return;
        var q = root.queue || {};
        if (o.shuffle !== undefined) Daemon.soloistShuffle = !!o.shuffle;
        var repeat = o.repeat === "track" || o.repeat === "one" ? "one"
            : o.repeat === "context" || o.repeat === "all" ? "all" : "off";
        root.queue = Object.assign({}, q, { shuffle: Daemon.soloistShuffle, repeat: repeat });
    }

    function soloistRefresh() {
        if (root.provider !== "spotify" || !Daemon.connected || root.soloistLoading) return;
        root.soloistLoading = true;
        Daemon.call("soloist_now").then(result => {
            if (root.provider !== "spotify") return;
            root.soloistTrack(result.now);
            if (result.source && result.source.options) root.soloistOptions(result.source.options);
        }).catch(e => {
            var message = (e && e.message) || "Start Spotify Soloist to play music";
            if (root.soloistError !== message) root.toast(message, "error");
            root.soloistError = message;
        }).finally(() => { root.soloistLoading = false; });
    }

    function soloistRestoreMpv() {
        if (!Daemon.connected) return;
        Daemon.call("get_playback").then(pb => {
            if (root.provider === "spotify" || !pb) return;
            root.now = pb.now;
            root.paused = pb.paused;
            root.volume = pb.volume;
            root.duration = pb.duration;
            root.position = PB.clampPosition(pb.duration, pb.position);
        }).catch(() => {});
        Daemon.call("get_queue").then(q => {
            if (root.provider !== "spotify") root.queue = q;
        }).catch(() => {});
    }

    onProviderChanged: {
        var enteringSpotify = root.provider === "spotify";
        // Only one audio engine should remain audible after a provider switch.
        if (enteringSpotify && !Daemon.soloistMode && root.now && !root.paused)
            Daemon.call("toggle_pause").catch(() => {});
        if (!enteringSpotify && Daemon.soloistMode && !Daemon.soloistPaused)
            Daemon.call("soloist_control", { action: "pause", args: {} }).catch(() => {});
        Daemon.soloistMode = enteringSpotify;
        if (Daemon.soloistMode) {
            root.now = null;
            root.queue = { items: [], currentIndex: 0, shuffle: false, repeat: "off" };
            root.soloistRefresh();
            Daemon.call("soloist_queue", { limit: 20 })
                .then(q => root.soloistReadQueue(q)).catch(() => {});
        } else {
            root.soloistRestoreMpv();
        }
    }

    Timer {
        interval: 250
        repeat: true
        running: root.provider === "spotify" && !root.paused && root.duration > 0
        onTriggered: root.position = PB.clampPosition(root.duration, root.position + 0.25)
    }
    Timer {
        interval: 8000
        repeat: true
        running: root.provider === "spotify" && Daemon.connected
        onTriggered: {
            root.soloistRefresh();
            Daemon.call("soloist_queue", { limit: 20 })
                .then(q => root.soloistReadQueue(q)).catch(() => {});
        }
    }

    // --- events + opening snapshot -----------------------------------------------------------
    Connections {
        target: Daemon
        function onEvent(name, data) {
            if (name === "soloist-event") {
                root.soloistEvent(data);
                return;
            }
            // Prevent MPV state echoes from overwriting Soloist's visible player.
            if (root.provider === "spotify" && ["now-playing", "position", "duration",
                "playback-state", "queue-changed", "queue-index", "volume", "rating"]
                .indexOf(name) !== -1) return;
            var fx = PB.applyEvent(root, name, data);
            if (fx) {
                if (fx.toast) root.toast(fx.toast, fx.kind);
                // Sign-in events can ask the browser to open their approval page.
                if (fx.openUrl) Quickshell.execDetached(["xdg-open", fx.openUrl]);
            }
        }
        function onSnapshot(snap) { root.loadSnapshot(snap); }
    }

    // Seed state from the { playback, queue, settings, auth } reply the daemon sends on subscribe
    // (and re-sends after every reconnect), the socket equivalent of frontend_ready's resync.
    function loadSnapshot(snap) {
        if (!snap) return;
        if (snap.provider) root.provider = snap.provider;
        if (snap.queue && root.provider !== "spotify") root.queue = snap.queue;
        var pb = snap.playback;
        if (pb && root.provider !== "spotify") {
            root.volume = pb.volume;         // before the now guard: the slider is stale either way
            if (!root.now) {                 // a real now-playing event may have beaten the snapshot
                root.now = pb.now;
                root.rating = (pb.now && pb.now.rating) ? pb.now.rating : "indifferent";
                root.paused = pb.paused;
                root.duration = pb.duration;
                root.position = PB.clampPosition(pb.duration, pb.position);
                root.stopAfterCurrent = pb.stopAfterCurrent || false;
            }
        }
        if (snap.settings) root.settings = snap.settings;
        if (snap.auth) root.auth = { signedIn: !!snap.auth.signedIn, name: snap.auth.name, avatar: snap.auth.avatar };
        if (snap.audioFx) root.audioFx = snap.audioFx;
        if (snap.spotify)
            root.spotify = { signedIn: !!snap.spotify.signedIn, stored: !!snap.spotify.stored,
                name: snap.spotify.name, premium: snap.spotify.premium };
        if (snap.tidal)
            root.tidal = { signedIn: !!snap.tidal.signedIn, name: snap.tidal.name,
                quality: snap.tidal.quality, hasCredentials: !!snap.tidal.hasCredentials,
                code: "", url: "", error: "" };
        if (snap.soundcloud)
            root.soundcloud = { signedIn: !!snap.soundcloud.signedIn,
                name: snap.soundcloud.name, error: "" };
    }

    // --- SoundCloud waveform -----------------------------------------------------------------
    // On every track change resolve a SoundCloud track's waveform (get_waveform) into the per-id
    // cache and publish it as `waveform`; a non-SoundCloud track clears it. A cached id is served
    // straight away and never refetched. onNowChanged also covers the opening snapshot's `now`.
    onNowChanged: root.ensureWaveform(root.now ? root.now.videoId : null)
    function ensureWaveform(vid) {
        if (!vid || String(vid).indexOf("sc:") !== 0) {
            root.waveform = null;
            return;
        }
        if (root.waveformCache[vid]) {
            root.waveform = root.waveformCache[vid];
            return;
        }
        root.waveform = null;
        Daemon.call("get_waveform", { id: vid })
            .then((r) => {
                var s = (r && r.samples) ? r.samples : [];
                root.waveformCache[vid] = s;
                if (root.now && root.now.videoId === vid)
                    root.waveform = s;
            })
            .catch(() => {});
    }

    // --- methods (each a daemon call) --------------------------------------------------------
    function play(item) { return Daemon.call("play", { item: item }); }
    function playIndex(i) { return Daemon.call("play_index", { index: i }); }
    function togglePause() { return Daemon.call("toggle_pause"); }
    function next() { return Daemon.call("next_track"); }
    function prev() { return Daemon.call("prev_track"); }
    function seek(secs) { return Daemon.call("seek", { position: secs }); }
    function setVolume(v) { return Daemon.call("set_volume", { volume: v }); }
    // Send the Sound dialog's effects to the daemon; its audio-fx echo updates root.audioFx.
    function setAudioFx(fx) {
        return Daemon.call("set_audio_fx", { speed: fx.speed, semitones: fx.semitones, reverb: fx.reverb, bass: fx.bass, width: fx.width, eq: fx.eq });
    }
    // Optimistic: the switch flips the local mirror at once and asks the daemon. The daemon method
    // lands later, so a failure is swallowed rather than surfaced.
    function setProvider(p) {
        root.provider = p;
        return Daemon.call("set_provider", { provider: p }).catch(() => {});
    }
    // Start the Spotify OAuth flow; the daemon spawns the task and drives the rest through
    // spotify-auth events (the url step opens the browser). Idempotent while a flow is running.
    function spotifySignIn() { return Daemon.call("spotify_sign_in"); }
    function spotifySignOut() { return Daemon.call("spotify_sign_out"); }
    function tidalSignIn() { return Daemon.call("tidal_sign_in"); }
    function tidalSignOut() { return Daemon.call("tidal_sign_out"); }
    function tidalSetCredentials(c) { return Daemon.call("tidal_set_credentials", c); }

    function soundcloudSignIn() { return Daemon.call("soundcloud_sign_in"); }
    function soundcloudSignOut() { return Daemon.call("soundcloud_sign_out"); }
    function toggleShuffle() { return Daemon.call("toggle_shuffle"); }
    // off -> all -> one -> off, matching player.svelte.ts cycleRepeat.
    function cycleRepeat() {
        var r = (root.queue && root.queue.repeat) ? root.queue.repeat : "off";
        return Daemon.call("set_repeat", { mode: r === "off" ? "all" : r === "all" ? "one" : "off" });
    }
}
