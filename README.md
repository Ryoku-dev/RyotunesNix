
<div align="center">
 
# Ryotunes for NixOS

**A Ryoku native desktop music player with native audio playback, live shell theming, and a UI that knows when to disappear remade specifically for NixOS compatability.**

[Download](https://github.com/ryoku-dev/ryotunes/releases/latest) · [Architecture](docs/ARCHITECTURE.md) · [Install](docs/INSTALL-ARCH.md) · [Troubleshooting](docs/TROUBLESHOOTING.md) · [Ryoku NixOS](https://github.com/ryoku-dev/ryoku-on-nixos)

</div>

<br />

<img width="1168" height="692" alt="image" src="https://github.com/user-attachments/assets/38228072-23e7-46a9-9af4-a79295b3bfc0" />
<img width="1168" height="692" alt="image" src="https://github.com/user-attachments/assets/4ed12a81-cc04-4352-9e98-cb63c3bb65b7" />


<p align="center"><sub>Repository artwork based on the live v2 Home layout and Ryoku visual language.</sub></p>

---

## Built for Ryoku on NixOS, not just compatible with it

Ryotunes is a Linux first desktop music application shaped around the way **Ryoku** actually behaves.

The primary interface is Quickshell / QML, connected to the Rust ryotunesd systemd daemon. Rust and libmpv manages playback, media state and provider integrations independently. The older Svelte/ WebKitGTK adaption remains a separate legacy launch mode as a fallback.

<table>
<tr>
<td width="33%" valign="top">

---

### Skins

Ryotunes have community made themes within the Ryostore, downloading the themes from the Ryostore adds it to your Settings > Appearance section.

---

## Contributing

Start with **[CONTRIBUTING.md](CONTRIBUTING.md)**. Changes touching playback lifecycle, theme integration, Home rendering, background behavior or replacement packaging deserve explicit regression testing.

---

## Upstream, license & independence

Ryotunes is a **GPL-3.0-or-later modified work derived from [SimoHypers/LiMusic](https://github.com/SimoHypers/limusic)**.

The project retains transparent upstream attribution while pursuing its own Ryoku specific product direction, interface, lifecycle, performance architecture and packaging model. See **[UPSTREAM.md](UPSTREAM.md)** for the detailed note.

Distributed under **[GPL-3.0-or-later](LICENSE)**.

---

<div align="center">

### Music, for the Ryoku desktop.

</div>
