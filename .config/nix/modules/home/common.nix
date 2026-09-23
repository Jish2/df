# HM baseline for all five machines.
{ user, ... }:
{
  home.username = user;
  home.stateVersion = "25.05";
  programs.home-manager.enable = true;

  # NOTE: backupFileExtension ("bak") is declared by the flake itself in the
  # darwin HM block (system-level) — can't live here; this file is a user
  # module on the darwin path. standalone HM sets it in mkHome.

  # IMPORTANT: yadm still owns ~/.zshrc, git config, tmux.conf, nvim, karabiner,
  # ghostty, etc. Do NOT enable programs.zsh / programs.git / programs.tmux or
  # add home.file entries for those paths until each file's port wave lands
  # (FLEET.md "Migration from yadm") — HM would fight yadm over the same files.
  #
  # packages wanted on all five machines get promoted here; until then hosts
  # own their own lists.
}
