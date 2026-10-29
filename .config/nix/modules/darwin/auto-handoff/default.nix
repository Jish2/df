# fleet.autoHandoff — compact idle T3 Claude threads while their prompt cache
# is still warm (FLEET.md "Auto-handoff"; the name predates compacting).
#
# Reopening a thread after its 1-hour cache expires re-bills its whole
# context. Every 5 minutes auto_handoff.py reads Claude Code's session logs;
# a T3 thread that has sat idle 40–50 minutes with enough context gets a
# signed POST to a T3 webhook task, whose Haiku agent queues `/compact` into
# the thread. The watcher itself makes no model calls.
#
# LaunchAgent, not a daemon: T3's own service is a LaunchAgent (no T3 → no
# threads to compact), and the webhook URL + signing secret live in the
# login Keychain, which is only unlocked inside a login session.
#
# Declared through Home Manager (~/Library/LaunchAgents, bootstrapped into
# gui/<uid>), not nix-darwin's launchd.agents: nix-darwin's activation runs
# as root and `launchctl load`s /Library/LaunchAgents into the SYSTEM domain,
# so the job ran as root with HOME=/var/root (no skill, no Keychain).
#
# Runtime dependencies outside nix:
#   - handoffs.py from the catch-up skill (Jish2/skills, linked to
#     ~/.claude/skills/catch-up by skills-sync)
#   - Keychain items session-handoff-webhook-{url,secret}, set up once by
#     hand (FLEET.md); until then each run logs "missing webhook url/secret"
#   - T3's state DB (~/.t3/userdata/statev2.sqlite), read-only, to map a
#     session to its thread. That's T3's private schema: if an update
#     changes it, runs log "no T3 thread found" and send nothing.
{
  config,
  lib,
  user,
  ...
}:
let
  cfg = config.fleet.autoHandoff;
  home = "/Users/${user}";
in
{
  options.fleet.autoHandoff = {
    enable = lib.mkEnableOption "auto-compact watcher for idle T3 Claude threads";

    idleMin = lib.mkOption {
      type = lib.types.int;
      default = 40;
      description = "Minutes idle before a thread is compacted.";
    };

    idleMax = lib.mkOption {
      type = lib.types.int;
      default = 50;
      description = ''
        Latest idle minute to compact at. The cache lasts 60, and the
        window must be wider than the 5-minute run interval so every idle
        stretch is caught once.
      '';
    };

    minTokens = lib.mkOption {
      type = lib.types.int;
      default = 60000;
      description = ''
        Skip threads with less context. Every T3 Claude thread starts at
        ~25k, so compacting a small one saves little.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home-manager.users.${user}.launchd.agents.auto-handoff = {
      enable = true;
      config = {
        Label = "org.jgoon.auto-handoff";
        # system python (stdlib only); the store copy of the script imports
        # handoffs.py from the synced skill at run time
        ProgramArguments = [
          "/usr/bin/python3"
          "-I"
          "${./auto_handoff.py}"
          "--idle-min"
          (toString cfg.idleMin)
          "--idle-max"
          (toString cfg.idleMax)
          "--min-tokens"
          (toString cfg.minTokens)
        ];
        EnvironmentVariables.PATH = "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin";
        StartInterval = 300;
        StandardOutPath = "${home}/Library/Logs/auto-handoff.log";
        StandardErrorPath = "${home}/Library/Logs/auto-handoff.log";
      };
    };
  };
}
