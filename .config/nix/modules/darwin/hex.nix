# fleet.hex — Hex voice dictation (brew cask anomalyco/tap/hex) config.
#
# Declares fleet.hex at the darwin level (same pattern as fleet-t3s.nix)
# and manages ~/.config/hex/hex.config.ts through home-manager.
#
# Hex reads that file and hot-reloads it ~1/3s after it changes. Hex OWNS
# the other files in ~/.config/hex (hex.d.ts, AGENTS.md, tsconfig.json —
# it rewrites them itself); only the config is managed here. The source
# of truth is hex.config.ts next to this file.
#
# Two layers for fixing misheard words:
#   - vocabulary: `hex vocabulary add <term> --sounds-like <spellings>`
#     (transcription-time; Parakeet needs Labs > Vocabulary biasing on)
#   - transformations in hex.config.ts (paste-time, deterministic)
# Validate after editing: `hex commands check` (loads it as Hex does), or
# `npx -y -p typescript tsc` in ~/.config/hex.
{
  config,
  user,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.fleet.hex;
in
{
  options.fleet.hex = {
    enable = lib.mkEnableOption "Hex voice dictation transformations config";

    configFile = lib.mkOption {
      type = lib.types.path;
      default = ./hex.config.ts;
      description = "hex.config.ts source to install into ~/.config/hex";
    };
  };

  config = lib.mkIf cfg.enable {
    home-manager.users.${user} = {
      # hex CLI on PATH (brew installs the app but not the binary; the CLI
      # talks to the running app over its owner-only local API)
      home.packages = [
        (pkgs.writeShellScriptBin "hex" ''
          exec /Applications/Hex.app/Contents/MacOS/hex "$@"
        '')
      ];

      # Hex watches the folder and reloads on change; a store symlink is
      # enough — Hex only ever reads the config.
      home.file.".config/hex/hex.config.ts".source = cfg.configFile;
    };
  };
}
