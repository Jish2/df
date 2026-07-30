# fuzzy cd into a git worktree
cwt() {
  local selection worktree_path

  selection=$(
    git worktree list --porcelain |
    awk '
      /^worktree / {
        path = substr($0, 10)
      }
      /^branch / {
        branch = $2
        sub("refs/heads/", "", branch)
        print branch "\t" path
      }
      /^detached/ {
        print "(detached)\t" path
      }
    ' |
    fzf --delimiter=$'\t' --with-nth=1,2
  ) || return

  worktree_path="${selection#*$'\t'}"
  cd "$worktree_path"
}
