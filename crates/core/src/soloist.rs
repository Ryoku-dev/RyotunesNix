//! Optional bridge to Spotify Soloist's localhost-only WebSocket API.
//!
//! This module never launches Soloist, receives an API key, reads its credential store,
//! or changes the existing librespot/MPV player. It connects to the *already-running*
//! user-owned Soloist process for a short RPC and closes the socket afterward.

use std::net::IpAddr;
use std::path::PathBuf;
use std::time::Duration;

use anyhow::{anyhow, bail, ensure, Context as _, Result};
use futures_util::{SinkExt as _, StreamExt as _};
use serde_json::{json, Value};
use tokio::time::{timeout, Instant};
use tokio_tungstenite::{connect_async, tungstenite::Message};

const CONNECT_TIMEOUT: Duration = Duration::from_secs(3);
const REPLY_TIMEOUT: Duration = Duration::from_secs(5);
const MAX_REPLY_BYTES: usize = 2 * 1024 * 1024;

/// The bridge's probe state is separate from Spotify's original librespot auth state.
/// A missing Soloist process must never mark the old Spotify provider signed out.
pub struct SoloistBridge {
    data_dir: PathBuf,
}

impl SoloistBridge {
    pub fn discover() -> Self {
        let home = std::env::var_os("HOME").map(PathBuf::from).unwrap_or_default();
        let data_dir =
            std::env::var_os("RYOTUNES_SOLOIST_DATA_DIR").map(PathBuf::from).unwrap_or_else(|| {
                // Respect the isolated test session we have already paired; the
                // production default remains the ordinary Soloist data directory.
                let eval = home.join(".local/share/ryotunes-soloist-eval");
                if eval.is_dir() {
                    eval
                } else {
                    std::env::var_os("XDG_DATA_HOME")
                        .map(PathBuf::from)
                        .unwrap_or_else(|| home.join(".local/share"))
                        .join("soloist")
                }
            });
        Self { data_dir }
    }

    fn endpoint(&self) -> Result<String> {
        let raw_host = std::fs::read_to_string(self.data_dir.join("ws.addr"))
            .context("Soloist is not running with its local WebSocket API (ws.addr missing)")?;
        let host = raw_host.trim();
        let address: IpAddr = host.parse().context("invalid Soloist WebSocket address")?;
        ensure!(address.is_loopback(), "refusing a non-local Soloist WebSocket address");
        let raw_port = std::fs::read_to_string(self.data_dir.join("ws.port"))
            .context("Soloist WebSocket port is unavailable (ws.port missing)")?;
        let port: u16 = raw_port.trim().parse().context("invalid Soloist WebSocket port")?;
        ensure!(port != 0, "Soloist WebSocket port must be nonzero");
        let host = match address {
            IpAddr::V4(v4) => v4.to_string(),
            IpAddr::V6(v6) => format!("[{v6}]"),
        };
        Ok(format!("ws://{host}:{port}"))
    }

    async fn connect(
        &self,
    ) -> Result<
        tokio_tungstenite::WebSocketStream<
            tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>,
        >,
    > {
        let url = self.endpoint()?;
        let (socket, _) = timeout(CONNECT_TIMEOUT, connect_async(url.as_str()))
            .await
            .context("timed out contacting Soloist's local WebSocket")?
            .context("cannot connect to Soloist's local WebSocket")?;
        Ok(socket)
    }

    /// Read the actual authenticated/active-device status, not a guessed process state.
    pub async fn status(&self) -> Result<Value> {
        let mut socket = self.connect().await?;
        Self::send(&mut socket, json!({"type":"command", "command":"get_auth_state"})).await?;
        Self::receive(&mut socket, "auth_state", None).await
    }

    /// The official full snapshot, plus a Ryotunes-friendly rendering of its item.
    pub async fn now(&self) -> Result<Value> {
        let mut socket = self.connect().await?;
        Self::send(&mut socket, json!({"type":"command", "command":"get_state"})).await?;
        let raw = Self::receive(&mut socket, "playback_state", None).await?;
        Ok(json!({ "now": normalize_now(&raw), "source": raw }))
    }

    pub async fn queue(&self, limit: u32) -> Result<Value> {
        ensure!(limit <= 80, "Soloist queue limit must not exceed 80");
        let mut socket = self.connect().await?;
        Self::send(&mut socket, json!({"type":"command", "command":"get_queue", "limit": limit}))
            .await?;
        Self::receive(&mut socket, "queue_changed", None).await
    }

    /// Observe the existing Soloist playback process. No playback commands are issued.
    /// Each incoming notification is published independently of the legacy MPV player.
    /// The caller owns reconnection and the lifetime of the listening task.
    pub async fn watch_stream<F>(&self, mut publish: F) -> Result<()>
    where
        F: FnMut(Value) + Send,
    {
        let mut socket = self.connect().await?;

        // A new observer can attach after a track started. Request snapshots so
        // its subscribers do not depend on receiving a future change first.
        Self::send(&mut socket, json!({"type":"command", "command":"get_state"})).await?;
        Self::send(&mut socket, json!({"type":"command", "command":"get_queue", "limit": 10}))
            .await?;

        let mut keepalive = tokio::time::interval(Duration::from_secs(30));
        keepalive.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
        loop {
            tokio::select! {
                _ = keepalive.tick() => {
                    socket.send(Message::Ping(Vec::new().into()))
                        .await.context("cannot ping Soloist event socket")?;
                }
                incoming = socket.next() => {
                    let incoming = incoming
                        .ok_or_else(|| anyhow!("Soloist event socket closed"))?
                        .context("Soloist event WebSocket error")?;
                    match incoming {
                        Message::Text(text) => {
                            if text.len() > MAX_REPLY_BYTES {
                                tracing::warn!("dropping oversized Soloist event");
                                continue;
                            }
                            let source: Value = match serde_json::from_str(&text) {
                                Ok(value) => value,
                                Err(error) => {
                                    tracing::debug!(%error, "ignoring invalid Soloist event JSON");
                                    continue;
                                }
                            };
                            if let Some(event) = event_payload(source) {
                                publish(event);
                            }
                        }
                        Message::Ping(data) => {
                            socket.send(Message::Pong(data))
                                .await.context("cannot reply to Soloist ping")?;
                        }
                        Message::Close(_) => bail!("Soloist closed its event stream"),
                        _ => {}
                    }
                }
            }
        }
    }

    /// Explicit whitelist: never allow arbitrary messages or any account/auth commands.
    /// A successful command_result means *dispatched*, not that Spotify has acted yet.
    pub async fn control(&self, action: &str, args: &Value) -> Result<Value> {
        let mut socket = self.connect().await?;
        let requests = control_messages(action, args)?;
        for request in requests {
            let expected = request["command"].as_str().unwrap_or_default().to_owned();
            Self::send(&mut socket, request).await?;
            Self::receive(&mut socket, "command_result", Some(&expected)).await?;
        }
        Ok(json!({ "accepted": true, "action": action }))
    }

    async fn send<S>(socket: &mut tokio_tungstenite::WebSocketStream<S>, value: Value) -> Result<()>
    where
        S: tokio::io::AsyncRead + tokio::io::AsyncWrite + Unpin,
    {
        socket
            .send(Message::Text(value.to_string().into()))
            .await
            .context("cannot send Soloist request")
    }

    async fn receive<S>(
        socket: &mut tokio_tungstenite::WebSocketStream<S>,
        desired_type: &str,
        desired_command: Option<&str>,
    ) -> Result<Value>
    where
        S: tokio::io::AsyncRead + tokio::io::AsyncWrite + Unpin,
    {
        let deadline = Instant::now() + REPLY_TIMEOUT;
        loop {
            let remaining = deadline.saturating_duration_since(Instant::now());
            if remaining.is_zero() {
                bail!("Soloist did not return {desired_type} in time");
            }
            let frame = timeout(remaining, socket.next())
                .await
                .context("Soloist response timed out")?
                .ok_or_else(|| anyhow!("Soloist closed the WebSocket"))?
                .context("Soloist WebSocket error")?;
            match frame {
                Message::Text(text) => {
                    ensure!(
                        text.len() <= MAX_REPLY_BYTES,
                        "Soloist response exceeds the size limit"
                    );
                    let response: Value =
                        serde_json::from_str(&text).context("invalid JSON in Soloist reply")?;
                    let kind = response["type"].as_str().unwrap_or("");
                    if kind == "error" {
                        bail!(
                            "Soloist: {}",
                            response["message"].as_str().unwrap_or("unknown error")
                        );
                    }
                    if kind == desired_type
                        && desired_command
                            .is_none_or(|name| response["command"].as_str() == Some(name))
                    {
                        return Ok(response);
                    }
                    // The websocket emits auth_state and possibly playback_state on
                    // connect. Ignore unsolicited events until our requested response.
                }
                Message::Ping(bytes) => {
                    socket
                        .send(Message::Pong(bytes))
                        .await
                        .context("cannot answer Soloist ping")?;
                }
                Message::Close(_) => bail!("Soloist closed the WebSocket during the request"),
                _ => {}
            }
        }
    }
}

fn valid_spotify_uri(uri: &str, track_only: bool) -> Result<()> {
    let allowed = ["spotify:track:", "spotify:album:", "spotify:playlist:", "spotify:episode:"];
    let prefix = allowed.iter().find(|prefix| uri.starts_with(**prefix));
    ensure!(prefix.is_some(), "unsupported Spotify playback URI");
    ensure!(!track_only || prefix == Some(&"spotify:track:"), "queue items must be Spotify tracks");
    let id = uri.rsplit(':').next().unwrap_or("");
    ensure!(
        id.len() == 22 && id.bytes().all(|b| b.is_ascii_alphanumeric()),
        "invalid Spotify URI identifier"
    );
    Ok(())
}

fn control_messages(action: &str, args: &Value) -> Result<Vec<Value>> {
    let msg = |name| json!({ "type": "command", "command": name });
    let requests = match action {
        "play" => {
            let mut request = msg("play");
            if let Some(uri) = args.get("uri") {
                let uri = uri.as_str().ok_or_else(|| anyhow!("uri must be a string"))?;
                valid_spotify_uri(uri, false)?;
                request["uri"] = json!(uri);
            }
            vec![request]
        }
        "pause" | "skip_next" | "skip_prev" | "activate" | "deactivate" => vec![msg(action)],
        "seek" => {
            let pos =
                args["positionMs"].as_u64().context("positionMs must be a nonnegative integer")?;
            ensure!(pos <= 86_400_000, "seek position exceeds 24 hours");
            vec![json!({"type":"command", "command":"seek", "position_ms": pos})]
        }
        "volume" => {
            let v = args["volume"].as_u64().context("volume must be an integer")?;
            ensure!(v <= 100, "volume must be 0–100");
            vec![json!({"type":"command", "command":"set_volume", "volume": v})]
        }
        "shuffle" => {
            let value = args["enabled"].as_bool().context("enabled must be a boolean")?;
            vec![json!({"type":"command", "command":"set_shuffle", "enabled": value})]
        }
        "repeat" => match args["mode"].as_str() {
            Some("off") => vec![
                json!({"type":"command", "command":"set_repeat_track", "enabled": false}),
                json!({"type":"command", "command":"set_repeat_context", "enabled": false}),
            ],
            Some("context") => vec![
                json!({"type":"command", "command":"set_repeat_track", "enabled": false}),
                json!({"type":"command", "command":"set_repeat_context", "enabled": true}),
            ],
            Some("track") => vec![
                json!({"type":"command", "command":"set_repeat_context", "enabled": false}),
                json!({"type":"command", "command":"set_repeat_track", "enabled": true}),
            ],
            _ => bail!("repeat mode must be off, context or track"),
        },
        "add_to_queue" => {
            let uri = args["uri"].as_str().context("uri must be a Spotify track URI")?;
            valid_spotify_uri(uri, true)?;
            vec![json!({"type":"command", "command":"add_to_queue", "uri": uri})]
        }
        _ => bail!("unsupported Soloist control action: {action}"),
    };
    Ok(requests)
}

/// Snapshot mapping for the current Ryotunes `SongItem` conventions.
/// Keep the raw source alongside it; this does not yet replace the live MPV model.
pub fn normalize_now(source: &Value) -> Value {
    let item = &source["item"];
    let decorations = &item["decorations"];
    let creators = decorations["creators"].as_array();
    let artists = creators
        .map(|list| {
            list.iter()
                .filter_map(|person| person["entity"]["decorations"]["identity"]["name"].as_str())
                .collect::<Vec<_>>()
                .join(", ")
        })
        .unwrap_or_default();
    let covers = decorations["visual_identity"]["cover"].as_array();
    let thumbnail = covers.and_then(|list| {
        list.iter()
            .find(|cover| cover["size"] == "large")
            .or_else(|| list.iter().find(|cover| cover["size"] == "xlarge"))
            .or_else(|| list.last())
            .and_then(|cover| cover["url"].as_str())
    });
    let status = source["status"].as_str().unwrap_or("idle");
    json!({
        "videoId": item["uri"].as_str(),
        "title": decorations["identity"]["name"].as_str(),
        "artists": artists,
        "album": decorations["parent"]["entity"]["decorations"]["identity"]["name"].as_str(),
        "albumId": decorations["parent"]["entity"]["uri"].as_str(),
        "thumbnail": thumbnail,
        "durationMs": decorations["playback"]["duration_ms"].as_u64(),
        "positionMs": source["position"]["position_ms"].as_u64(),
        "timestampMs": source["position"]["timestamp_ms"].as_u64(),
        "speed": source["position"]["speed"].as_f64(),
        "volume": source["volume"].as_u64(),
        "paused": status != "playing",
        "status": status,
        "isActive": source["is_active"].as_bool().unwrap_or(false),
        "availableActions": &source["available_actions"],
        "contextUri": source["context"]["uri"].as_str(),
    })
}

/// Explicit notification allowlist: never forward auth or arbitrary command replies
/// into the UI event bus. Keep full provider data under `source`; the normalised
/// `now` is included only for complete playback snapshots.
fn event_payload(source: Value) -> Option<Value> {
    let kind = source.get("type")?.as_str()?.to_owned();
    if !matches!(
        kind.as_str(),
        "playback_state"
            | "playback_changed"
            | "position_sync"
            | "device_changed"
            | "queue_changed"
            | "track_changed"
            | "volume_changed"
            | "options_changed"
    ) {
        return None;
    }
    let mut event = json!({ "kind": kind, "source": source });
    if kind == "playback_state" {
        event["now"] = normalize_now(&event["source"]);
    }
    Some(event)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn soloist_live_events_are_namespaced_and_filter_private_messages() {
        let playback = json!({
            "type": "playback_state", "status": "buffering", "is_active": false,
            "item": { "uri": "spotify:track:3stWWPN41byqp8loPdy92u", "decorations": {
                "identity": { "name": "Master of None" }, "creators": [],
                "playback": { "duration_ms": 192240 }
            }}
        });
        let event = event_payload(playback).expect("playback is allowed");
        assert_eq!(event["kind"], "playback_state");
        assert_eq!(event["now"]["title"], "Master of None");
        assert_eq!(event["now"]["status"], "buffering");
        assert_eq!(event["now"]["isActive"], false);
        let active = event_payload(json!({
            "type": "device_changed", "is_active": true,
            "device_name": "Ryotunes Soloist Test"
        }))
        .expect("active device transition");
        assert_eq!(active["source"]["is_active"], true);
        assert!(event_payload(json!({"type":"auth_state", "token":"secret"})).is_none());
        assert!(event_payload(json!({"type":"command_result", "command":"pause"})).is_none());
    }

    #[test]
    fn parses_a_realistic_playback_snapshot() {
        let raw = json!({
            "type": "playback_state", "status": "playing", "is_active": true,
            "item": {"uri": "spotify:track:2X485T9Z5Ly0xyaghN73ed", "decorations": {
                "identity": {"name": "Let It Happen"},
                "visual_identity": {"cover": [{"url": "small", "size": "small"}, {"url": "large", "size": "large"}]},
                "parent": {"entity": {"uri": "spotify:album:79dL7FLiJFOO0EoehUHQBv", "decorations": {"identity": {"name": "Currents"}}}},
                "creators": [{"entity": {"decorations": {"identity": {"name": "Tame Impala"}}}}],
                "playback": {"duration_ms": 459877}
            }},
            "position": {"position_ms": 276807, "timestamp_ms": 1793220359871u64, "speed": 1.0},
            "volume": 100, "available_actions": {"pause": {}}
        });
        let now = normalize_now(&raw);
        assert_eq!(now["title"], "Let It Happen");
        assert_eq!(now["artists"], "Tame Impala");
        assert_eq!(now["album"], "Currents");
        assert_eq!(now["thumbnail"], "large");
        assert_eq!(now["durationMs"], 459877);
        assert_eq!(now["positionMs"], 276807);
        assert_eq!(now["paused"], false);
    }

    #[test]
    fn blocks_unsafe_controls_and_bad_uris() {
        assert!(control_messages("sign_out", &Value::Null).is_err());
        assert!(control_messages("play", &json!({"uri":"https://example.com"})).is_err());
        assert!(control_messages(
            "add_to_queue",
            &json!({"uri":"spotify:playlist:37i9dQZF1EYkqdzj48dyYq"})
        )
        .is_err());
        assert!(control_messages("volume", &json!({"volume": 101})).is_err());
        assert!(control_messages("pause", &Value::Null).is_ok());
    }

    #[test]
    fn repeat_mode_emits_two_ordered_commands() {
        let v = control_messages("repeat", &json!({"mode":"track"})).unwrap();
        assert_eq!(v[0]["command"], "set_repeat_context");
        assert_eq!(v[1]["command"], "set_repeat_track");
        assert_eq!(v[1]["enabled"], true);
    }
}
