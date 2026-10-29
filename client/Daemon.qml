pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// One connection to ryotunesd. Requests carry an id and resolve a Promise; lines without
// an id are events. A dropped connection is retried every 2 s; once a subscription is asked
// for it is re-sent on every reconnect, and every pending request is rejected on a drop so no
// page waits forever.
Singleton {
    id: root

    property bool quitting: false

    readonly property string socketPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/ryotunes/ryotunesd.sock"
    readonly property bool connected: !!root.sock && root.sock.connected
    property int protocol: 0
    property string daemonVersion: ""

    // A daemon event (no id): name plus its payload, fanned out to Playback and any surface.
    signal event(string name, var data)
    // A failure the daemon itself cannot record (not connected, socket dropped). `level` is
    // "warn"/"error"; Logs subscribes and forwards into the diagnostics record. Emitted as a
    // signal rather than calling Logs directly so the two singletons do not import each other.
    signal callFailed(string level, string target, string message)
    // The `subscribe` reply: the full { playback, queue, settings, auth } snapshot, delivered on
    // the first subscribe and again after every reconnect so Playback resynchronises each time.
    signal snapshot(var data)

    // Soloist owns playback while Spotify is the selected catalogue.
    // The native MPV player remains untouched for every other provider.
    property bool soloistMode: false
    property bool soloistPaused: true
    property bool soloistShuffle: false
    property var soloistQueueItems: []

    function soloistItemId(item) {
        if (!item) return "";
        return String(item.video_id || item.videoId || item.uri || item.id || "");
    }

    function soloistRoute(method, params) {
        if (!root.soloistMode) return null;
        var p = params || {};
        var action = "";
        var args = {};
        var uri = "";

        if (method === "play") {
            uri = root.soloistItemId(p.item);
            if (!uri.startsWith("spotify:track:"))
                return { error: "Spotify Soloist can play Spotify tracks only" };
            action = "play";
            args = { uri: uri };
        } else if (method === "play_playlist") {
            // Prefer native Spotify playlist context, if the caller supplied one.
            uri = String(p.spotifyUri || "");
            if (!uri.startsWith("spotify:playlist:") && !uri.startsWith("spotify:album:")) {
                var rows = p.items || [];
                var idx = p.start === undefined || p.start === null ? 0 : p.start;
                uri = root.soloistItemId(rows[idx] || rows[0]);
            }
            if (!uri.startsWith("spotify:"))
                return { error: "No Spotify tracks to play" };
            action = "play";
            args = { uri: uri };
        } else if (method === "play_index") {
            uri = root.soloistItemId(root.soloistQueueItems[p.index]);
            if (!uri.startsWith("spotify:track:"))
                return { error: "Spotify queue item unavailable" };
            action = "play";
            args = { uri: uri };
        } else if (method === "toggle_pause") {
            action = root.soloistPaused ? "play" : "pause";
        } else if (method === "next_track") {
            action = "skip_next";
        } else if (method === "prev_track") {
            action = "skip_prev";
        } else if (method === "seek") {
            action = "seek";
            args = { positionMs: Math.max(0, Math.round(Number(p.position) * 1000)) };
        } else if (method === "set_volume") {
            action = "volume";
            args = { volume: Math.max(0, Math.min(100, Math.round(Number(p.volume)))) };
        } else if (method === "toggle_shuffle") {
            action = "shuffle";
            args = { enabled: !root.soloistShuffle };
            root.soloistShuffle = args.enabled;
        } else if (method === "set_repeat") {
            action = "repeat";
            args = { mode: p.mode === "one" ? "track" : p.mode === "all" ? "context" : "off" };
        } else if (method === "add_to_queue" || method === "play_next") {
            var items = p.items || [];
            uri = root.soloistItemId(items[0]);
            if (!uri.startsWith("spotify:track:"))
                return { error: "Soloist queue accepts Spotify tracks only" };
            action = "add_to_queue";
            args = { uri: uri };
        } else if (["move_in_queue", "remove_from_queue", "clear_queued", "set_stop_after_current"].indexOf(method) !== -1) {
            return { error: "This queue operation is not supported by Spotify Soloist" };
        } else {
            return null;
        }
        return { method: "soloist_control", params: { action: action, args: args } };
    }

    property int nextId: 1
    property var pending: ({})
    // Whether a subscription has been asked for; drives the re-subscribe on reconnect.
    property bool wantSubscribe: false
    property var sock: null

    function reconnect() {
        if (root.quitting || root.connected)
            return;

        if (root.sock)
            root.sock.destroy();

        root.sock = socketComponent.createObject(root);
        root.sock.connected = true;
    }
    Component.onCompleted: root.reconnect()

    function call(method, params) {
        var routed = root.soloistRoute(method, params);
        if (routed) {
            if (routed.error) return Promise.reject({code: "soloist_unsupported", message: routed.error});
            method = routed.method;
            params = routed.params;
        }
        return new Promise((resolve, reject) => {
            if (!root.connected) {
                // The daemon never sees this failure, so it can only be recorded here: a user
                // clicking play against a dead daemon is a support ticket with no other trace.
                root.callFailed("warn", "rpc:" + method, "ryotunesd is not connected");
                reject({ code: "disconnected", message: "ryotunesd is not connected" });
                return;
            }
            const id = root.nextId++;
            root.pending[id] = { resolve, reject };
            sock.write(JSON.stringify({ id, method, params: params === undefined ? null : params }) + "\n");
            sock.flush();
        });
    }

    // Ask the daemon for a hello (version handshake) and the event stream with its opening
    // snapshot. Idempotent: sets the intent, subscribes now if connected, and the socket re-runs
    // it on every future reconnect. Returns the subscribe Promise for the immediate caller.
    function subscribeAll() {
        root.wantSubscribe = true;
        return root._subscribe();
    }

    function _subscribe() {
        if (!root.connected)
            return Promise.reject({ code: "disconnected", message: "ryotunesd is not connected" });
        root.call("hello").then(h => { root.protocol = h.protocol; root.daemonVersion = h.daemon; });
        const p = root.call("subscribe", { events: ["*"] });
        p.then(s => root.snapshot(s));
        return p;
    }

    function handleLine(line) {
        let msg;
        try { msg = JSON.parse(line); } catch (e) { return; }
        if (msg.event !== undefined) {
            root.event(msg.event, msg.data);
            return;
        }
        const p = root.pending[msg.id];
        if (!p) return;
        delete root.pending[msg.id];
        if (msg.error) p.reject(msg.error); else p.resolve(msg.result);
    }

    Component {
        id: socketComponent
        Socket {
            id: connection
            path: root.socketPath
            parser: SplitParser { onRead: line => root.handleLine(line) }
            onConnectionStateChanged: {
                if (root.sock !== connection) return;
                if (connection.connected) {
                    if (root.wantSubscribe) root._subscribe();
                } else {
                    root.callFailed("error", "daemon", "connection to ryotunesd lost (socket closed)");
                    for (const id in root.pending) root.pending[id].reject({ code: "disconnected", message: "connection lost" });
                    root.pending = {};
                }
            }
        }
    }
    Timer {
        id: retry
        interval: 2000
        running: !root.quitting && !root.connected
        repeat: true

        onTriggered: root.reconnect()
    }
}
