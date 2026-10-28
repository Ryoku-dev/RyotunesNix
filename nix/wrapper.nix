{
  lib,
  symlinkJoin,
  makeWrapper,
  quickshell,
  qt6,
  kdePackages,
  python3,
  ffmpeg,
  pulseaudio,
  xdg-utils,
  ryotunesUnwrapped,
  ryokuQml,
}:

let
  qmlPackages = [
    ryokuQml
    qt6.qtdeclarative
    qt6.qtmultimedia
    qt6.qtwayland
    qt6.qt5compat
    qt6.qtsvg
    qt6.qtimageformats
    kdePackages.kirigami.unwrapped
  ];

  qmlImports = lib.makeSearchPath "lib/qt-6/qml" qmlPackages;
  qtPlugins = lib.makeSearchPath "lib/qt-6/plugins" qmlPackages;
  runtimePath = lib.makeBinPath [ python3 ffmpeg pulseaudio xdg-utils ];
in
symlinkJoin {
  name = "ryotunesnix-${ryotunesUnwrapped.version}";
  paths = [ ryotunesUnwrapped ];
  nativeBuildInputs = [ makeWrapper ];
  preferLocalBuild = false;
  allowSubstitutes = true;

  postBuild = ''
    # The desktop entry and default flake app must launch native Quickshell.
    makeWrapper ${quickshell}/bin/qs "$out/bin/ryotunes" \
      --add-flags "-p ${ryotunesUnwrapped}/share/ryotunes/client" \
      --prefix QML_IMPORT_PATH : "${qmlImports}" \
      --prefix QML2_IMPORT_PATH : "${qmlImports}" \
      --prefix QT_PLUGIN_PATH : "${qtPlugins}" \
      --prefix PATH : "${runtimePath}"

    ln -s ryotunes "$out/bin/ryotunes-qml"

    rm "$out/bin/ryotunesd"
    makeWrapper ${ryotunesUnwrapped}/bin/ryotunesd "$out/bin/ryotunesd" \
      --prefix PATH : "$out/bin:${runtimePath}"
  '';

  meta = ryotunesUnwrapped.meta // {
    description = "Ryotunes with native Ryoku QML integration";
  };
}
