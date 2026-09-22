# HM baseline for all five machines.
{ user, ... }:
{
  home.username = user;
  home.stateVersion = "25.05";
  programs.home-manager.enable = true;

  # when a yadm-managed file's port wave lands, HM replaces the real file
  # with a store symlink and keeps the original around as <file>.bak
  # (without this, activation fails instead of clobbering)
  home-manager.backupFileExtension = "bak";

  # IMPORTANT: yadm still owns ~/.zshrc, git config, tmux.conf, nvim, karabiner,
  # ghostty, etc. Do NOT enable programs.zsh / programs.git / programs.tmux or
  # add home.file entries for those paths until each file's port wave lands
  # (FLEET.md "Migration from yadm") — HM would fight yadm over the same files.
  #
  # packages wanted on all five machines get promoted here; until then hosts
  # own their own lists.
}
