# fleet.karabiner — Karabiner-Elements config, generated from TypeScript.
#
# karabiner-config.ts is the source of truth for the whole karabiner.json:
# complex_modifications rules, the profile's devices and identity, and the
# `global` block. It is built here by nix and copied onto the machine at
# activation — the JSON itself is a build artifact and is NOT tracked.
#
# Why copy instead of home.file: Karabiner rewrites karabiner.json whenever
# the GUI changes a rule or a device is paired, and it rewrites through the
# path it opened. A read-only /nix/store symlink makes those writes fail
# (same problem modules/darwin/hex.nix solves for Hex). So this is a real
# file, refreshed at activation, and left alone when already correct.
#
# Consequence: the GUI is no longer an authoring surface. Toggling a rule in
# the Karabiner GUI lasts until the next `make here`. Durable changes go in
# karabiner-config.ts (`enabled: false` to disable a rule — the three
# disabled rules there are intentional history, keep them).
{
  config,
  user,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.fleet.karabiner;

  # Generated config as a store file. buildNpmPackage handles npm ci + the
  # node build; dependencies are pinned by package-lock.json (karabiner.ts is
  # an exact version there, not a caret range — two machines must build the
  # same bytes).
  generated = pkgs.buildNpmPackage {
    pname = "karabiner-config";
    version = "1.0.0";
    src = ./.;
    nodejs = pkgs.nodejs;
    npmDepsHash = "sha256-rwyVYrBzo59qk/PdrhMdFVU5vr3wtlnZcFKyyfxnR+M=";
    buildPhase = ''
      runHook preBuild
      node emit.ts > karabiner.json
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      install -m 0644 karabiner.json $out
      runHook postInstall
    '';
    dontStrip = true;
  };

  # Copy in, but only when the content actually differs. Karabiner watches
  # this file and hot-reloads; rewriting it on every rebuild would make the
  # app re-read its config for no reason and drop in-flight key state.
  #
  # `install -m 0644`, not `cp`: the store source is 0444, and cp would leave
  # the destination read-only, so the NEXT content change would fail writing
  # to a file Karabiner expects to own.
  installConfig = pkgs.writeShellScript "fleet-karabiner-config" ''
    set -eu
    src=${generated}
    dest="$HOME/.config/karabiner/karabiner.json"
    mkdir -p "$HOME/.config/karabiner"
    # An earlier generation may have left a store symlink here; install would
    # write through it into the read-only store and fail.
    if [ -L "$dest" ]; then
      rm -f "$dest"
      ${pkgs.coreutils}/bin/install -m 0644 "$src" "$dest"
      exit 0
    fi
    if [ -f "$dest" ] && ${pkgs.diffutils}/bin/cmp -s "$src" "$dest"; then
      exit 0
    fi
    ${pkgs.coreutils}/bin/install -m 0644 "$src" "$dest"
  '';
in
{
  options.fleet.karabiner.enable = lib.mkEnableOption "generated Karabiner-Elements config";

  config = lib.mkIf cfg.enable {
    # Only karabiner.json is generated. Karabiner also rewrites
    # automatic_backups/ next to it and reads assets/ — none of which this
    # module manages; those stay as the app left them.
    #
    # A plain string, not lib.hm.dag.entryAfter: this is a darwin module, so
    # `lib` is nixpkgs lib and has no `lib.hm`. Home Manager coerces a string
    # into a DAG entry (same as modules/darwin/hex.nix).
    home-manager.users.${user} = {
      home.activation.fleetKarabinerConfig = ''
        run ${installConfig}
      '';
    };
  };
}
