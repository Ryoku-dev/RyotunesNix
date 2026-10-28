# RyotunesNix flake packaging

This is a source flake for the **RyotunesNix repository**, not a patch for upstream `ryotunes`. The package includes the Rust binaries, Quickshell UI, Ryoku QML modules, and the Audio Lab's Python/FFmpeg/PipeWire monitor helpers.

The Spotify Soloist bridge is part of the source, but **Soloist is still a separate runtime**. The flake does not download a time-limited Soloist binary, collect credentials, or change the live playback daemon.

## Apply to RyotunesNix only

First merge the Spotify, Audio Lab and UI changes into `Ryoku-dev/ryotunes` without these packaging files. Keep the NixOS packaging in its own branch of `Ryoku-dev/RyotunesNix`.

After merging and synchronizing the application source into the fork:

```bash
cd ~/Projects/ryoku-sprint/ryotunesnix
git switch -c feat/nix-flake
unzip -o ~/Downloads/ryotunesnix-flake.zip -d .
git add flake.nix nix/package.nix nix/wrapper.nix INSTALL.md
nix-instantiate --parse flake.nix >/dev/null
nix flake lock
nix eval --raw .#packages.x86_64-linux.ryotunes-unwrapped.version
git status --short
```

`unzip` will copy only these four files. Run it on a fresh RyotunesNix-only branch, never on the upstream PR branch.

The flake's `cargoLock.allowBuiltinFetchGit` uses the pinned Git revisions in Cargo.lock rather than a placeholder cargoHash. It can fetch these Git sources during Nix evaluation. The pnpm lockfile uses the same hash as the existing Ryoku-on-NixOS packaging, because the `ui/pnpm-lock.yaml` content has not changed. All inputs should be recorded by `flake.lock` and committed.

## Test and deploy

The source still needs a real Nix build and desktop playback check on the target NixOS system. Avoid a full second build until disk space permits and the source merge is complete.

```bash
nix build .#ryotunes -L
```

Only after the package builds and the active Soloist process remains functional should Ryoku-on-NixOS be changed.

## Ryoku-on-NixOS integration

Use the fork's `ryotunes-unwrapped` output with **Ryoku's existing wrapper and socket-activated daemon**. This avoids two service definitions, two installed app copies, and duplicate QML packages.

In Ryoku-on-NixOS `flake.nix`, replace `ryotunesSrc` with:

```nix
ryotunesNix = {
  url = "github:Ryoku-dev/RyotunesNix";
  inputs.nixpkgs.follows = "ryokuPackagesNixpkgs";
  inputs.ryoku.follows = "ryokuUpstream";
};
```

Pass `ryotunesNix` through the outputs arguments into `./nix/packages`. In `nix/packages/default.nix`, replace the old `ryotunesUnwrapped` import with:

```nix
ryotunesUnwrapped =
  ryotunesNix.packages.${pkgs.stdenv.hostPlatform.system}.ryotunes-unwrapped;
```

Keep `ryotunes = import ./ryoku-ryotunes.nix { ... };` intact, so Ryoku uses its own `ryokuQml` package. Keep `ryotunesd.socket` and `ryotunesd.service` and their existing paths. They will resolve through the replacement `ryoku-ryotunes` wrapper. Remove the obsolete pinned source input and old derivation only after validation.

The system currently may also have a **temporary user-level systemd override** pointing to the Cargo build. Inspect it before removing it, and don't stop or replace the working Soloist process until the new Nix-owned executable has passed a playback check.

## Current limitations

* The flake has been prepared from repository sources and existing NixOS packaging, but not built in this environment.
* Soloist remains externally managed and has a limited-lifetime binary.
* The QML audio scope uses `pactl` and FFmpeg with your PipeWire default output monitor, not arbitrary audio capture.
* This packaging does not claim to route Soloist audio through the libmpv equalizer.
