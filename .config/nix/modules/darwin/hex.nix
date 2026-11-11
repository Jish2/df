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
# Three layers for fixing misheard words, cheapest to strongest:
#   - vocabulary: `hex vocabulary add <term> --sounds-like <spellings>`
#     (transcription-time; Parakeet needs Labs > Vocabulary biasing on).
#     Cannot help short terms — the engine ignores terms under 5 letters
#     and spellings whose length ratio is outside 2x, so `yadm`, `ROS`,
#     `Tuo` never become candidates no matter the boost.
#   - corrections (below): `{ matched_phrase, output }` fixed swaps at
#     paste time. Whole-phrase, case-insensitive. This is the reliable
#     layer for short or very differently-spelled terms.
#   - transformations in hex.config.ts (paste-time, JS, trust prompt)
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

  # Corrections ride in Hex's own settings.json, which is NOT managed as a
  # file: it holds the local API token and dictation history next to it, and
  # Hex rewrites it on every hotkey or vocabulary change. So declare them
  # here and merge them in at activation, leaving every other key alone.
  correctionsJson = pkgs.writeText "fleet-hex-corrections.json" (
    builtins.toJSON cfg.corrections
  );

  # Merge `corrections` into the Global mode's replacements: keep whatever is
  # already there, append only phrases not already present. Idempotent, so a
  # rebuild never duplicates a rule. No-op while Hex has no settings file.
  installCorrections = pkgs.writeShellScript "fleet-hex-corrections" ''
    set -eu
    settings="$HOME/Library/Application Support/hex/settings.json"
    [ -f "$settings" ] || exit 0
    ${pkgs.jq}/bin/jq --slurpfile declared ${correctionsJson} '
      .dictation_processing.default_mode.replacements = (
        (.dictation_processing.default_mode.replacements // []) as $cur
        | $cur + ($declared[0]
            | map(select(.matched_phrase as $p | $cur | any(.matched_phrase == $p) | not)))
      )
    ' "$settings" > "$settings.fleet-hex-new"
    ${pkgs.diffutils}/bin/diff -q "$settings" "$settings.fleet-hex-new" >/dev/null 2>&1 && {
      rm -f "$settings.fleet-hex-new"
      exit 0
    }
    mv "$settings.fleet-hex-new" "$settings"
  '';
in
{
  options.fleet.hex = {
    enable = lib.mkEnableOption "Hex voice dictation transformations config";

    configFile = lib.mkOption {
      type = lib.types.path;
      default = ./hex.config.ts;
      description = "hex.config.ts source to install into ~/.config/hex";
    };

    corrections = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          matched_phrase = lib.mkOption {
            type = lib.types.str;
            description = "Phrase as the transcript shows it (whole-phrase, case-insensitive)";
          };
          output = lib.mkOption {
            type = lib.types.str;
            description = "What to paste instead";
          };
        };
      });
      default = [ ];
      example = lib.literalExpression ''
        [
          { matched_phrase = "remind cuddle"; output = "remindctl"; }
          { matched_phrase = "yeah dum"; output = "yadm"; }
        ]
      '';
      description = ''
        Fixed swaps merged into Hex's Global dictation mode at activation.
        Appended only when the phrase is absent, so rules added by hand in
        Hex survive a rebuild.
      '';
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

      # Corrections merge into Hex's settings, not a managed file.
      # A plain string: this is a darwin module, so `lib` is nixpkgs lib and
      # has no `lib.hm.dag`. Home Manager coerces a string into a DAG entry.
      home.activation.fleetHexCorrections = lib.mkIf (cfg.corrections != [ ]) ''
        run ${installCorrections}
      '';
    };
  };
}
