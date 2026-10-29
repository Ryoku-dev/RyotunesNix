# Spotify Soloist on NixOS

RyotunesNix ships the Rust Soloist **bridge**, not the separately distributed
Spotify Soloist executable, credentials, or an automatically enabled backend.
The bridge connects to an already running local WebSocket; without it Spotify
playback through Soloist reports `ws.addr missing`.

## One-time setup (opt in)

Obtain your own permitted Soloist executable and Spotify Soloist API key from
their official provider. Then run:

```bash
nix run 'github:Ryoku-dev/RyotunesNix#setup-soloist' -- /absolute/path/to/soloist
```

Alternatively, from a source checkout, run:

```bash
bash scripts/setup-soloist.sh /absolute/path/to/soloist
```

The script stores the key as a user-only file (`~/.config/ryotunes-soloist/api-key`),
creates an opt-in `systemd --user` service, and enables startup at login.
It uses `steam-run-free` via `nix shell` for the external Soloist runtime.
No NixOS rebuild is necessary for this *user-service* setup.

The service and launcher are deliberately kept outside the immutable Nix store.
The key is never added to the repo or flake lock. Soloist currently receives
its key through `--api-key`, so the key may be inspectable by processes with
sufficient access to command-line arguments. Do not publish process listings
or service debug logs containing credentials.

The installer preserves an existing user service rather than overwriting it.
It will automatically select the legacy `ryotunes-soloist-eval` directory if
that directory exists, matching Ryotunes' current discovery code. Otherwise
it uses the normal `~/.local/share/soloist` data directory (or `XDG_DATA_HOME`).

## Verify startup

```bash
systemctl --user is-enabled ryotunes-soloist-backend.service
systemctl --user is-active ryotunes-soloist-backend.service
```

When Soloist starts with `--ws`, Ryotunes looks for `ws.addr` and `ws.port`
in the selected data directory. Playback also requires the separate
`ryotunesd` daemon to be running. These are **two** distinct processes.

## Limits

- This setup requires the user to supply their own executable and key; `nix run`
  does not fetch or redistribute Soloist.
- The Spotify API and executable may change or require renewed authorization.
- The `ryotunes-soloist-backend` user service can be disabled with
  `systemctl --user disable --now ryotunes-soloist-backend.service`.
- The backend and Ryotunes are separate; removing an older Ryotunes package
  does **not** require deleting the Soloist backend or its data.
