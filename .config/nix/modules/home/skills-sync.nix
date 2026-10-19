# Private agent skills sync (see github.com/Jish2/skills).
#
# Home Manager owns the loader TOOL only; skill content lives outside the
# Nix store in a git checkout at ~/private-skills (kept private, never
# evaluated by Nix). Each `make here` activation runs skills-sync, which
# fast-forwards the checkout to origin/main, refreshes pinned third-party
# sources, and links the resolved skills into every harness's discovery
# directory. The fleet role comes from `make skills-machine` (the host map
# in the top-level Makefile), so one implementation serves all five hosts.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
{
  home.file.".local/bin/skills-sync" = {
    source = "${inputs.skills}/loader/skills-sync";
    executable = true;
  };

  # Sync private skills on every activation, after the profile is in place.
  # Failures warn but never break the switch: a machine without network
  # access (or without Jish2 credentials yet) keeps its last-known links.
  home.activation.skillsSync = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ -x "$HOME/.local/bin/skills-sync" ]; then
      run --silence "$HOME/.local/bin/skills-sync" --optional || true
    fi
  '';
}
