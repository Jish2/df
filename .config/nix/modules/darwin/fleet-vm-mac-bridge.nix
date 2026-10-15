{
  config,
  lib,
  pkgs,
  user,
  ...
}:
let
  cfg = config.fleet.vmMacBridge;
  source = ../../packages/vm-mac-bridge;
  notifier = pkgs.callPackage ../../packages/vm-mac-bridge/notifier.nix { };
  home = "/Users/${user}";
  app = "${home}/Applications/vm-mac-bridge.app";
  terminalCommand = "${home}/Library/Application Support/vm-mac-bridge/start.command";
  settings = pkgs.writeText "vm-mac-bridge.json" (
    builtins.toJSON {
      python = "${pkgs.python3}/bin/python3";
      git = "${pkgs.git}/bin/git";
      repository = "https://github.rbx.com/jgoon/vm-mac-bridge.git";
      branch = "main";
      update_timeout = 60;
      host = cfg.host;
      remote_script = cfg.remoteScript;
      notifier = "${app}/Contents/MacOS/terminal-notifier";
      terminal_command = terminalCommand;
      reconnect_seconds = cfg.reconnectSeconds;
      max_timeout = cfg.maxTimeout;
      notification_timeout = cfg.notificationTimeout;
    }
  );
  launcher = pkgs.writeShellScriptBin "vm-mac-bridge" ''
    exec ${pkgs.python3}/bin/python3 ${source}/runner.py --config ${settings} "$@"
  '';
in
{
  options.fleet.vmMacBridge = {
    enable = lib.mkEnableOption "the VM–Mac approval bridge at graphical login";
    host = lib.mkOption {
      type = lib.types.str;
      default = "devspace";
      description = "Existing SSH alias for the VM; its authentication remains separately managed.";
    };
    remoteScript = lib.mkOption {
      type = lib.types.str;
      default = "/home/coder/.codex/skills/mac-command/scripts/bridge.py";
      description = "Installed transport script on the VM; keep it compatible with the latest upstream helper.";
    };
    reconnectSeconds = lib.mkOption {
      type = lib.types.ints.positive;
      default = 15;
      description = "Delay before reconnecting after SSH exits.";
    };
    maxTimeout = lib.mkOption {
      type = lib.types.ints.positive;
      default = 120;
      description = "Maximum command execution time, independently of approval expiry.";
    };
    notificationTimeout = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.positive;
      default = null;
      description = "Optional shorter approval limit; null uses the request's remaining expiry window.";
    };
  };

  config = lib.mkIf cfg.enable {
    home-manager.users.${user} = { lib, ... }: {
      home.packages = [ launcher ];
      home.file."Library/Application Support/vm-mac-bridge/start.command" = {
        executable = true;
        text = ''
          #!/bin/sh
          exec ${launcher}/bin/vm-mac-bridge run
        '';
      };
      home.activation.installVmMacBridgeNotifier =
        lib.hm.dag.entryBetween [ "setupLaunchAgents" ] [ "writeBoundary" "linkGeneration" ]
          ''
            run ${pkgs.python3}/bin/python3 ${source}/install_notifier.py \
              ${notifier}/Applications/vm-mac-bridge.app ${lib.escapeShellArg app}
          '';
      launchd.agents.vm-mac-bridge = {
        enable = true;
        config = {
          Label = "org.jgoon.vm-mac-bridge";
          ProgramArguments = [
            "${launcher}/bin/vm-mac-bridge"
            "start"
          ];
          RunAtLoad = true;
          LimitLoadToSessionType = "Aqua";
          # Terminal owns the interactive helper. Keeping this opener alive
          # would create new windows; the helper handles reconnects itself.
          KeepAlive = false;
        };
      };
    };
  };
}
