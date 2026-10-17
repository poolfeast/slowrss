{
  description = "QuickRSS: RSS/Atom feeds as HTML articles for KOReader";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
      version = "0.3.0";
    in
    {
      packages = forAllSystems (pkgs: rec {
        default = quickrss;

        # The plugin directory, ready to copy into KOReader's plugins folder.
        quickrss = pkgs.stdenvNoCC.mkDerivation {
          pname = "quickrss.koplugin";
          inherit version;
          src = ./quickrss.koplugin;
          installPhase = ''
            mkdir -p $out
            cp -r . $out/quickrss.koplugin
          '';
        };

        # Release archive: nix build .#zip && cp result quickrss.koplugin.zip
        zip = pkgs.runCommand "quickrss.koplugin-${version}.zip" { nativeBuildInputs = [ pkgs.zip ]; } ''
          cd ${quickrss}
          zip -qr - quickrss.koplugin > $out
        '';
      });

      apps = forAllSystems (pkgs: {
        # nix run: sync the plugin into KOReader's data directory and start KOReader.
        # KO_HOME selects the data directory (default: ~/.config/koreader).
        default = {
          type = "app";
          program = pkgs.lib.getExe (pkgs.writeShellApplication {
            name = "quickrss-koreader";
            runtimeInputs = [ pkgs.koreader pkgs.rsync ];
            text = ''
              export KO_HOME="''${KO_HOME:-''${XDG_CONFIG_HOME:-$HOME/.config}/koreader}"
              mkdir -p "$KO_HOME/plugins"
              rsync -a --delete "${self}/quickrss.koplugin/" "$KO_HOME/plugins/quickrss.koplugin/"
              exec koreader "$@"
            '';
          });
          meta.description = "Start KOReader with the plugin installed";
        };

        # nix run .#smoke: headless end-to-end run against real feeds.
        smoke = {
          type = "app";
          program = pkgs.lib.getExe (pkgs.writeShellApplication {
            name = "quickrss-smoke";
            runtimeInputs = [ pkgs.koreader pkgs.curl pkgs.python3 ];
            text = ''
              export QUICKRSS_SRC="${self}/quickrss.koplugin"
            '' + builtins.readFile ./spec/smoke.sh;
          });
          meta.description = "Headless fetch and open against live feeds";
        };
      });

      checks = forAllSystems (pkgs: {
        luacheck = pkgs.runCommand "quickrss-luacheck" { nativeBuildInputs = [ pkgs.luajitPackages.luacheck ]; } ''
          cd ${self}
          luacheck quickrss.koplugin spec
          touch $out
        '';
        spec = pkgs.runCommand "quickrss-spec" { nativeBuildInputs = [ pkgs.luajit ]; } ''
          cd ${self}
          luajit spec/run.lua
          touch $out
        '';
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [ pkgs.koreader pkgs.luajit pkgs.luajitPackages.luacheck pkgs.rsync ];
        };
      });
    };
}
