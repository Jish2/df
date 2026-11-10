# fleet.desktopCommander — shell + file access to this box for cloud agents
# (Meta Muse, the xAI Grok bot) over MCP, at mini-mcp.jgoon.com.
#
#   agent → Cloudflare Access (service tokens) → tunnel mini-mcp
#         → proxy.mjs on 127.0.0.1:<port> → Desktop Commander (stdio)
#
# The tunnel, Access app, DNS and per-agent service tokens live in
# ~/github/terraform (envs/cloudflare/mini-mcp-tunnel.tf). A separate tunnel
# from cloudflared-ssh on purpose: breaking or removing this one never
# touches the ssh lifeline.
#
# Desktop Commander's own limits (blockedCommands, allowedDirectories) are
# not a boundary: the agent has a shell, and DC matches blocked commands by
# first word only. The boundary is Access plus proxy.mjs, which re-verifies
# the Access JWT and exposes only allowedTools (never set_config_value).
#
# Two jobs, split the same way as their dependencies:
#   - proxy: Home Manager LaunchAgent (gui/<uid>), not a daemon. imsg and
#     remindctl need the login session — Messages.app automation and the
#     Reminders/Full Disk Access grants are per-session TCC — so it runs only
#     while jgoon is logged in, like BlueBubbles. TCC grants attach to the
#     nix node binary; a nodejs bump changes its path, so re-grant after a
#     flake update if `remindctl status` / imsg start failing (make doctor).
#   - connector: nix-darwin LaunchDaemon as the user, like cloudflared-ssh,
#     reading a 0600 token file installed once by hand:
#       terraform output -raw mini_mcp_tunnel_token > ~/.cloudflared/mini-mcp.token
#       chmod 600 ~/.cloudflared/mini-mcp.token
#     With the proxy down (logged out) Cloudflare answers 502.
{
  config,
  lib,
  pkgs,
  user,
  ...
}:
let
  cfg = config.fleet.desktopCommander;
  home = "/Users/${user}";
  tokenFile = "${home}/.cloudflared/mini-mcp.token";

  # the npm tarball ships the prebuilt dist/ but no lockfile; dependencies
  # come from the lockfile at the release's tag commit
  desktop-commander = pkgs.buildNpmPackage rec {
    pname = "desktop-commander";
    version = "0.3.1";
    src = pkgs.fetchurl {
      url = "https://registry.npmjs.org/@wonderwhy-er/desktop-commander/-/desktop-commander-${version}.tgz";
      hash = "sha512-cx7KTscLF951adHmDLVCDIVTqJ/Bg1LtdRILZoo5wa/UMeyOfMAuOJOEBulNMKBKb5Xd3nHDQnB9aXroN9Fw5A==";
    };
    lockfile = pkgs.fetchurl {
      url = "https://raw.githubusercontent.com/wonderwhy-er/DesktopCommanderMCP/7251da501d760e6eb5f95d802d9b42c741190950/package-lock.json";
      hash = "sha256-qmxFanWYGw7RDSR521xcuAklV56YG3dEPSSNiQmt8OA=";
    };
    postPatch = "cp ${lockfile} package-lock.json";
    npmDepsHash = "sha256-Yp8XjPUwXtAyCJ7vvigyhkaGZekelKo0Adk7appXuVg=";
    dontNpmBuild = true;
    # no install scripts: DC's postinstall is an install-tracking ping, and
    # dependencies' would download Chromium (puppeteer, for the hidden
    # write_pdf) and ripgrep (nix's is on PATH instead)
    npmFlags = [ "--ignore-scripts" ];
    npmRebuildFlags = [ "--ignore-scripts" ];
    postInstall = ''
      cp ${./proxy.mjs} $out/lib/node_modules/@wonderwhy-er/desktop-commander/mini-mcp-proxy.mjs
    '';
  };
  proxyScript = "${desktop-commander}/lib/node_modules/@wonderwhy-er/desktop-commander/mini-mcp-proxy.mjs";

  # copied over ~/.claude-server-commander/config.json on every start
  dcConfig = pkgs.writeText "desktop-commander-config.json" (
    builtins.toJSON {
      inherit (cfg) blockedCommands allowedDirectories;
      defaultShell = "/bin/zsh";
      telemetryEnabled = false;
      fileReadLineLimit = 1000;
      fileWriteLineLimit = 50;
      pendingWelcomeOnboarding = false;
      welcomeOnboardingEligible = false;
    }
  );

  connectorScript = pkgs.writeShellScript "cloudflared-mcp-start" ''
    if [ ! -r "${tokenFile}" ]; then
      echo "cloudflared-mcp: missing ${tokenFile} (see modules/darwin/desktop-commander)" >&2
      exit 1
    fi
    exec ${pkgs.cloudflared}/bin/cloudflared tunnel \
      --no-autoupdate \
      run \
      --token-file "${tokenFile}"
  '';
in
{
  options.fleet.desktopCommander = {
    enable = lib.mkEnableOption "Desktop Commander MCP for cloud agents at mini-mcp.jgoon.com";

    port = lib.mkOption {
      type = lib.types.port;
      default = 7801;
      description = "Loopback port for the proxy; must match mini_mcp_port in terraform.";
    };

    accessAudience = lib.mkOption {
      type = lib.types.str;
      description = "Access app audience (terraform output mini_mcp_access_audience).";
    };

    accessTeamDomain = lib.mkOption {
      type = lib.types.str;
      default = "jgoon.cloudflareaccess.com";
      description = "Cloudflare Access team domain that issues the JWTs.";
    };

    allowedTools = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "start_process"
        "interact_with_process"
        "read_process_output"
        "force_terminate"
        "list_sessions"
        "read_file"
        "read_multiple_files"
        "write_file"
        "edit_block"
        "list_directory"
        "get_file_info"
        "create_directory"
        "move_file"
        "start_search"
        "get_more_search_results"
        "stop_search"
        "list_searches"
      ];
      description = ''
        Desktop Commander tools agents may see and call. Left out on
        purpose: set_config_value/get_config (self-unlocking), kill_process/
        list_processes (any pid on the box), write_pdf, and DC's usage,
        history and feedback tools.
      '';
    };

    allowedDirectories = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ home ];
      description = "Directories DC's file tools may touch (shell commands are not limited by this).";
    };

    blockedCommands = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "sudo"
        "su"
        "passwd"
        "shutdown"
        "reboot"
        "halt"
        "mkfs"
        "dd"
        "diskutil"
        "csrutil"
        "launchctl"
        "darwin-rebuild"
        "tailscale"
        "cloudflared"
        "tccutil"
      ];
      description = ''
        First-word command blocks. A guard against an agent casually
        touching the lifelines, not a security boundary.
      '';
    };

    instructions = lib.mkOption {
      type = lib.types.str;
      default = ''
        Shell and file access to jgoon's Mac mini (macOS, always on). Run
        commands with start_process; they run as jgoon in zsh. Useful CLIs:
        remindctl (Apple Reminders: show, list, add, edit, complete, delete;
        `remindctl <command> --help`), imsg (iMessage/SMS: chats, history,
        send; `imsg <command> --help`), gcalcli (Google Calendar), gh, rg.
        Prefer --json output where a CLI offers it. Confirm with the user
        before sending messages, deleting anything, or changing system
        settings.
      '';
      description = "MCP server instructions shown to connecting agents.";
    };
  };

  config = lib.mkIf cfg.enable {
    home-manager.users.${user}.launchd.agents.mini-mcp = {
      enable = true;
      config = {
        Label = "org.jgoon.mini-mcp";
        # node directly as the job's program, so the TCC grants (Reminders,
        # Automation → Messages, Full Disk Access) attach to one binary
        ProgramArguments = [
          "${pkgs.nodejs}/bin/node"
          proxyScript
        ];
        EnvironmentVariables = {
          HOME = home;
          USER = user;
          SHELL = "/bin/zsh";
          LANG = "en_US.UTF-8";
          PATH = lib.concatStringsSep ":" [
            "${pkgs.ripgrep}/bin" # DC's search tools look for rg on PATH
            "/opt/homebrew/bin" # imsg, remindctl, gcalcli
            "/etc/profiles/per-user/${user}/bin"
            "/run/current-system/sw/bin"
            "/usr/bin"
            "/bin"
            "/usr/sbin"
            "/sbin"
          ];
          DESKTOP_COMMANDER_DISABLE_TELEMETRY = "1";
          # DC fetches remote feature flags (A/B tests, onboarding) at start;
          # point it at a closed port so it fails fast and keeps defaults
          DC_FLAG_URL = "http://127.0.0.1:9/";
          MINI_MCP_PORT = toString cfg.port;
          MINI_MCP_ACCESS_AUD = cfg.accessAudience;
          MINI_MCP_ACCESS_TEAM_DOMAIN = cfg.accessTeamDomain;
          MINI_MCP_ALLOWED_TOOLS = lib.concatStringsSep "," cfg.allowedTools;
          MINI_MCP_INSTRUCTIONS = cfg.instructions;
          MINI_MCP_DC_CONFIG = "${dcConfig}";
        };
        RunAtLoad = true;
        KeepAlive = true;
        ThrottleInterval = 30;
        StandardOutPath = "${home}/Library/Logs/mini-mcp.log";
        StandardErrorPath = "${home}/Library/Logs/mini-mcp.log";
      };
    };

    launchd.daemons.cloudflared-mcp = {
      # wait4path-wrapped, like tailscaled (see modules/darwin/tailscaled.nix)
      command = "${connectorScript}";
      serviceConfig = {
        Label = "org.jgoon.cloudflared-mcp";
        UserName = user;
        EnvironmentVariables.HOME = home;
        RunAtLoad = true;
        KeepAlive = true;
        ThrottleInterval = 30; # a missing token file retries slowly, not hot
        StandardErrorPath = "${home}/Library/Logs/cloudflared-mcp.err.log";
        StandardOutPath = "${home}/Library/Logs/cloudflared-mcp.out.log";
      };
    };
  };
}
