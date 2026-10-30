{
  description = "RyotunesNix: Ryoku-native music player for NixOS";

  inputs = {
    nixpkgs.url =
      "github:NixOS/nixpkgs/56c02bc00adcf003215cc4bd996d6efaf4cff188";

    ryoku = {
      url = "github:Ryoku-dev/ryoku/unstable-dev";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, ryoku, ... }:
    let
      system = "x86_64-linux";

      quickshellScreencopyFix = final: prev: {
        quickshell = prev.quickshell.overrideAttrs (old: {
          patches = (old.patches or [ ]) ++ [
            (prev.fetchurl {
              url = "https://github.com/quickshell-mirror/quickshell/commit/851ab0eac6bdfa9201a1a50e7bc3a6d29af25949.patch";
              hash = "sha256-g+8NQeFyGK9v76cPM9ogkMSfLH0SGPOyREFkTf6MJ7I=";
            })
          ];
        });
      };

      pkgs = import nixpkgs {
        inherit system;
        overlays = [ quickshellScreencopyFix ];
      };

      ryotunesUnwrapped = pkgs.callPackage ./nix/package.nix {
        src = self.outPath;
      };

      ryotunes = pkgs.callPackage ./nix/wrapper.nix {
        inherit ryotunesUnwrapped;
        ryokuQml = ryoku.packages.${system}.ryoku-qml;
      };

      # Optional local setup; never packages the external Soloist binary/key.
      soloistSetup = pkgs.writeShellApplication {
        name = "ryotunes-soloist-setup";
        runtimeInputs = [ pkgs.coreutils pkgs.gnugrep pkgs.nix pkgs.systemd ];
        text = builtins.readFile ./scripts/setup-soloist.sh;
      };
    in
    {
      packages.${system} = {
        inherit ryotunes;
        ryotunes-unwrapped = ryotunesUnwrapped;
        soloist-setup = soloistSetup;
        default = ryotunes;
      };

      apps.${system} = {
        default = {
          type = "app";
          program = "${ryotunes}/bin/ryotunes";
        };

        setup-soloist = {
          type = "app";
          program = "${soloistSetup}/bin/ryotunes-soloist-setup";
        };
      };
    };
}
