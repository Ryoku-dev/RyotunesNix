<div align="center">
  <img src="src-tauri/icons/icon.png" width="88" alt="Ryotunes icon" />

  <h1>RyotunesNix</h1>

  <p><strong>The native music app for Ryoku on NixOS.</strong></p>

  </p>


<img src="docs/assets/homepage.png" width="100%" alt="Ryotunes Home" />

<table>
  <tr>
    <td width="33.33%">
      <img src="https://github.com/user-attachments/assets/878bb917-3920-446e-80ad-f3578e667201" width="100%" alt="Ryotunes screenshot 1" />
    </td>
    <td width="33.33%">
      <img src="https://github.com/user-attachments/assets/d41d0858-525e-4c60-815f-c36cf7097303" width="100%" alt="Ryotunes screenshot 2" />
    </td>
    <td width="33.33%">
      <img src="https://github.com/user-attachments/assets/4c829b74-727d-4e7e-b2ba-6a5eae230ff1" width="100%" alt="Ryotunes screenshot 3" />
    </td>
  </tr>
</table>

</div>

<br>

## Made specifically for NixOS

**RyotunesNix** brings [Ryotunes](https://github.com/Ryoku-dev/ryotunes) to [Ryoku on NixOS](https://github.com/Ryoku-dev/Ryoku-on-NixOS), completely building it from the ground up to natively support NixOS first. The entire application is written in rust and QML, the old version using Tauri + WebKitGTK is still avaliable as a fallback.

## Features

<table>
  <tr>
    <td valign="top">
      <strong>Multiple Providers</strong><br>
      Ryotunes includes streaming from Spotify, YT Music, Souncloud, Tidal and music from your local library, Ryotunes also includes a dedicated installer to install all your music and keep it local.
    </td>
    <td valign="top">
      <strong>Audiophile Mode</strong><br>
      Audiophile Mode adds a 20 band parametric EQ with frequency and gain sliders, it also includes a bar and curve cava spectrum, oscilloscope and a vectorscope and a dedicated focus mode with live lyrics.
    </td> 
  </tr>
  <tr>
    <td valign="top">
      <strong>Customisability</strong><br>
      Ryotunes comes bundles with 12 default themes and a Matugen theme, the Ryostore contains 20+ more additional themes made by the community and fully compatable with Ryotunes.
    </td>
    <td valign="top">
      <strong>Discord RPC</strong><br>
      Ryotunes comes with a fully customisible and native Discord Rich Presence automatically detecting Discord/ Vesktop and adding it to your ptofile automatically when listening.
    </td>
  </tr>
</table>

## Getting started

### With Ryoku on NixOS

RyotunesNix is integrated into the [Ryoku on NixOS](https://github.com/Ryoku-dev/Ryoku-on-NixOS) package bundle. On a supported Ryoku installation, launch it from your app launcher by typing "Ryotunes"

### Using the flake directly

To try the native application from this repository run

```bash
nix run github:Ryoku-dev/RyotunesNix
```

Or build the package

```bash
nix build github:Ryoku-dev/RyotunesNix#ryotunes
```

The flake only supports **x86_64-linux**. A standalone flake installs Ryotunes but **does not automatically install the Ryoku NixOS user services**. The native client needs a running ryotunesd daemon. For the fully managed desktop experience use the Ryoku on NixOS integration.

## Spotify Soloist

Spotify playback through Soloist uses an **optional external backend**. RyotunesNix includes the neccesary tools but it does not bundle the Soloist executable by default.
After obtaining your own permitted Soloist executable and API key, run the one time setup

```bash
nix run 'github:Ryoku-dev/RyotunesNix#setup-soloist' -- /path/to/soloist
```

The setup creates a systemd user service that starts Soloist on login. Your key stays locally on your PC, outside the Nix store. A running Soloist backend and the ryotunesd daemon are both required to play Spotify on Ryotunes, other providers work by default.

See **[Spotify Soloist setup and troubleshooting](docs/spotify-soloist.md)** for the full instructions for install <3

**Want to customise it?** Start with the [skin guide](docs/SKINS.md) and [design language](docs/DESIGN.md). For source changes, read [CONTRIBUTING.md](CONTRIBUTING.md).

## Credits and licence

RyotunesNix is maintained by [**aethctl**](https://github.com/aethctl)

Licensed under **[GPL-3.0-or-later](LICENSE)**.

<div align="center">
  <br>
  <sub>力 · RyotunesNix</sub>
</div>
