<div align="center">
  <img src="src-tauri/icons/icon.png" width="88" alt="Ryotunes icon" />

  <h1>RyotunesNix</h1>

  <p><strong>Music, shaped for the Ryoku desktop.</strong></p>

  <p>
    A native Quickshell music player for NixOS.<br>
    Built with Rust, QML and the Ryoku design language.
  </p>

  <p>
    <a href="#getting-started">Get started</a> ·
    <a href="#features">Features</a> ·
    <a href="#spotify-soloist">Spotify</a> ·
    <a href="docs/SKINS.md">Skins</a> ·
    <a href="CONTRIBUTING.md">Contribute</a>
  </p>

  <p><sub>NixOS · x86_64-linux · Quickshell · Rust · GPL-3.0-or-later</sub></p>

  <img src="docs/assets/homepage.png" width="100%" alt="" />

  <sub>Illustrated interface preview. The appearance follows your chosen Ryoku palette and Ryotunes skin.</sub>
</div>

<br>

## Made for the desktop you actually use

**RyotunesNix** brings [Ryotunes](https://github.com/Ryoku-dev/ryotunes) to [Ryoku on NixOS](https://github.com/Ryoku-dev/Ryoku-on-NixOS), with a **native Quickshell frontend** and a separate Rust playback daemon. Music and media state belong to the backend, not to a window you have to leave open.

This repository is the **NixOS-focused edition**, not the legacy Tauri desktop launcher. Running `ryotunes` from this flake starts the native QML interface.

## Features

<table>
  <tr>
    <td width="50%" valign="top">
      <strong>Native interface</strong><br>
      Quickshell and QML surfaces designed to sit naturally alongside the Ryoku desktop.
    </td>
    <td width="50%" valign="top">
      <strong>Playback that lives beyond the window</strong><br>
      A Rust <code>ryotunesd</code> daemon keeps playback and media state independent of the frontend.
    </td>
  </tr>
  <tr>
    <td valign="top">
      <strong>Music from multiple sources</strong><br>
      Explore your library, artists, albums, playlists and supported music providers from one place.
    </td>
    <td valign="top">
      <strong>Audio Lab</strong><br>
      Audio controls, visualisers and listening tools integrated into the native player.
    </td>
  </tr>
  <tr>
    <td valign="top">
      <strong>Skins that belong to Ryoku</strong><br>
      Follow the system palette or choose a skin. Community skins can be managed through RyoStore.
    </td>
    <td valign="top">
      <strong>Downloads and personal listening</strong><br>
      Save music locally, manage playlists and browse listening views without leaving the app.
    </td>
  </tr>
</table>

<details>
  <summary><strong>More interface previews</strong></summary>
  <br>
  <img src="https://github.com/user-attachments/assets/38228072-23e7-46a9-9af4-a79295b3bfc0" width="100%" alt="Ryotunes interface preview one" />
  <img src="https://github.com/user-attachments/assets/4ed12a81-cc04-4352-9e98-cb63c3bb65b7" width="100%" alt="Ryotunes interface preview two" />
</details>

## Getting started

### With Ryoku on NixOS

RyotunesNix is integrated into the [Ryoku on NixOS](https://github.com/Ryoku-dev/Ryoku-on-NixOS) package bundle. On a supported Ryoku installation, launch it with:

```bash
ryotunes
```

Ryoku manages the installed player and its socket-activated daemon as part of the desktop configuration.

### Using the flake directly

To try the native application from this repository:

```bash
nix run github:Ryoku-dev/RyotunesNix
```

Or build the package:

```bash
nix build github:Ryoku-dev/RyotunesNix#ryotunes
```

The flake currently targets **x86_64-linux**. A standalone flake invocation supplies the player but **does not automatically install the Ryoku NixOS user services**. The native client needs a running `ryotunesd` daemon. For the fully managed desktop experience, use the Ryoku on NixOS integration.

## Spotify Soloist

Spotify playback through Soloist uses an **optional external backend**. RyotunesNix includes the local bridge, but it does not bundle the Soloist executable or any account credentials.

After obtaining your own permitted Soloist executable and API key, run the one-time setup:

```bash
nix run 'github:Ryoku-dev/RyotunesNix#setup-soloist' -- /absolute/path/to/soloist
```

The setup creates an opt-in systemd user service that starts Soloist on login. Your key stays on your machine, outside the Nix store. A running Soloist backend and `ryotunesd` are both required for this playback path.

See **[Spotify Soloist setup and troubleshooting](docs/spotify-soloist.md)** for the full instructions and security notes.

## Inside the project

| Path | Purpose |
| --- | --- |
| [`client/`](client/) | Native Quickshell UI and playback surfaces |
| [`crates/`](crates/) | Rust playback core, daemon, CLI and protocols |
| [`nix/`](nix/) | NixOS package and native launcher wrapper |
| [`skins/`](skins/) | Bundled visual skins and skin schema |
| [`docs/`](docs/) | Design, architecture and troubleshooting references |

**Want to customise it?** Start with the [skin guide](docs/SKINS.md) and [design language](docs/DESIGN.md). For source changes, read [CONTRIBUTING.md](CONTRIBUTING.md).

## Credits and licence

RyotunesNix is maintained as the NixOS-focused edition of [Ryotunes](https://github.com/Ryoku-dev/ryotunes), a modified work derived from [LiMusic](https://github.com/SimoHypers/limusic).

Licensed under **[GPL-3.0-or-later](LICENSE)**. See [UPSTREAM.md](UPSTREAM.md) for attribution and project history.

<div align="center">
  <br>
  <sub>緑 · Ryoku</sub>
  <p><strong>Keep the music. Lose the clutter.</strong></p>
</div>
