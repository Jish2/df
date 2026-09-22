# mini — M1 Mac Mini, always on (aarch64-darwin), server-ish profile
# TODO on first touch: hostname/user, import pass, then decide what it serves
{ ... }:
{
  # networking.hostName = "...";

  # no GUI app casks declared yet — add what the machine actually runs.
  # shared services later look like:
  #
  #   launchd.agents.tailscaled = {
  #     serviceConfig.ProgramArguments = [ ... ];
  #     serviceConfig.RunAtLoad = true;
  #     serviceConfig.KeepAlive = true;
  #   };
}
