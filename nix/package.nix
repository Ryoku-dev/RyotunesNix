{
  lib,
  rustPlatform,
  pkg-config,
  wrapGAppsHook3,
  glib,
  gtk3,
  gdk-pixbuf,
  cairo,
  pango,
  webkitgtk_4_1,
  libsoup_3,
  mpv,
  libappindicator-gtk3,
  libayatana-appindicator,
  openssl,
  librsvg,
  src,
}:

rustPlatform.buildRustPackage rec {
  pname = "ryotunesnix-unwrapped";
  version = "1.2.3";

  inherit src;

  cargoLock = {
    lockFile = ../Cargo.lock;
    allowBuiltinFetchGit = true;
  };

  nativeBuildInputs = [
    pkg-config
    wrapGAppsHook3
    rustPlatform.bindgenHook
  ];

  buildInputs = [
    glib
    gtk3
    gdk-pixbuf
    cairo
    pango
    webkitgtk_4_1
    libsoup_3
    mpv
    libappindicator-gtk3
    libayatana-appindicator
    openssl
    librsvg
  ];

  preBuild = ''
    export HOME="$TMPDIR"
  '';

  cargoBuildFlags = [
    "--package" "sync-server"
    "--package" "ryotunesd"
    "--package" "ryotunes-cli"
  ];

  doCheck = false;

  installPhase = ''
    runHook preInstall

    install_bin() {
      local name="$1"
      local binary
      binary="$(find target -type f -path "*/release/$name" -perm -0100 -print -quit)"
      if [ -z "$binary" ]; then
        printf 'Ryotunes binary not built: %s\n' "$name" >&2
        exit 1
      fi
      install -Dm755 "$binary" "$out/bin/$name"
    }

    install_bin ryotunes-sync
    install_bin ryotunesd
    install_bin ryotunes-cli

    mkdir -p \
      "$out/share/ryotunes/client" \
      "$out/share/ryotunes/skins" \
      "$out/share/ryotunes/matugen" \
      "$out/share/applications" \
      "$out/share/metainfo" \
      "$out/share/licenses/ryotunes" \
      "$out/share/doc/ryotunes"

    cp -r client/. "$out/share/ryotunes/client/"
    rm -rf "$out/share/ryotunes/client/tests"
    cp -r skins/. "$out/share/ryotunes/skins/"

    find "$out/share/ryotunes/client" "$out/share/ryotunes/skins" \
      -type d -exec chmod 755 {} +
    find "$out/share/ryotunes/client" "$out/share/ryotunes/skins" \
      -type f -exec chmod 644 {} +

    install -Dm644 matugen/ryotunes.json \
      "$out/share/ryotunes/matugen/ryotunes.json"
    install -Dm644 packaging/linux/ryotunes.desktop \
      "$out/share/applications/ryotunes.desktop"
    install -Dm644 packaging/linux/dev.ryoku.ryotunes.metainfo.xml \
      "$out/share/metainfo/dev.ryoku.ryotunes.metainfo.xml"

    for size in 32 64 128; do
      install -Dm644 "src-tauri/icons/''${size}x''${size}.png" \
        "$out/share/icons/hicolor/''${size}x''${size}/apps/ryotunes.png"
    done
    install -Dm644 src-tauri/icons/128x128@2x.png \
      "$out/share/icons/hicolor/256x256/apps/ryotunes.png"
    install -Dm644 src-tauri/icons/icon.png \
      "$out/share/icons/hicolor/512x512/apps/ryotunes.png"

    install -Dm755 scripts/diagnostics.sh \
      "$out/bin/ryotunes-diagnostics"
    install -Dm644 LICENSE "$out/share/licenses/ryotunes/LICENSE"
    install -Dm644 README.md "$out/share/doc/ryotunes/README.md"
    install -Dm644 UPSTREAM.md "$out/share/doc/ryotunes/UPSTREAM.md"

    runHook postInstall
  '';

  meta = {
    description = "Ryotunes playback daemon, CLI and native Quickshell client";
    homepage = "https://github.com/Ryoku-dev/RyotunesNix";
    license = lib.licenses.gpl3Plus;
    platforms = [ "x86_64-linux" ];
    mainProgram = "ryotunes";
  };
}
