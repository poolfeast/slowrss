{
  description = "SlowRSS: RSS/Atom feeds as HTML articles for KOReader";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
      version = "0.3.0";
    in
    {
      packages = forAllSystems (pkgs: rec {
        default = slowrss;

        # The plugin directory, ready to copy into KOReader's plugins folder.
        slowrss = pkgs.stdenvNoCC.mkDerivation {
          pname = "slowrss.koplugin";
          inherit version;
          src = ./slowrss.koplugin;
          installPhase = ''
            mkdir -p $out
            cp -r . $out/slowrss.koplugin
          '';
        };

        # Release archive: nix build .#zip && cp result slowrss.koplugin.zip
        zip = pkgs.runCommand "slowrss.koplugin-${version}.zip" { nativeBuildInputs = [ pkgs.zip ]; } ''
          cd ${slowrss}
          zip -qr - slowrss.koplugin > $out
        '';
      });

      apps = forAllSystems (pkgs: {
        # nix run: sync the plugin into KOReader's data directory and start KOReader.
        # KO_HOME selects the data directory (default: ~/.config/koreader).
        default = {
          type = "app";
          program = pkgs.lib.getExe (pkgs.writeShellApplication {
            name = "slowrss-koreader";
            runtimeInputs = [ pkgs.koreader pkgs.rsync ];
            text = ''
              export KO_HOME="''${KO_HOME:-''${XDG_CONFIG_HOME:-$HOME/.config}/koreader}"
              mkdir -p "$KO_HOME/plugins"
              rsync -a --delete "${self}/slowrss.koplugin/" "$KO_HOME/plugins/slowrss.koplugin/"
              exec koreader "$@"
            '';
          });
          meta.description = "Start KOReader with the plugin installed";
        };

        # nix run .#smoke: headless end-to-end run against real feeds.
        smoke = {
          type = "app";
          program = pkgs.lib.getExe (pkgs.writeShellApplication {
            name = "slowrss-smoke";
            runtimeInputs = [ pkgs.koreader pkgs.curl pkgs.python3 ];
            text = ''
              export SLOWRSS_SRC="${self}/slowrss.koplugin"
            '' + builtins.readFile ./spec/smoke.sh;
          });
          meta.description = "Headless fetch and open against live feeds";
        };
      });

      checks = forAllSystems (pkgs: {
        luacheck = pkgs.runCommand "slowrss-luacheck" { nativeBuildInputs = [ pkgs.luajitPackages.luacheck ]; } ''
          cd ${self}
          luacheck slowrss.koplugin spec
          touch $out
        '';
        spec = pkgs.runCommand "slowrss-spec" { } ''
          cd ${pkgs.koreader}/lib/koreader
          ./luajit ${self}/spec/run.lua
          touch $out
        '';
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [ pkgs.koreader pkgs.luajitPackages.luacheck pkgs.rsync ];
        };
      });
    };
}
