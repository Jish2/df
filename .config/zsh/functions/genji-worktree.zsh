# create a genji worktree and open it in VS Code
create_genji_worktree() {
  if [ -z "$1" ]; then
    echo "Error: no branch name provided"
    return 1
  fi

  local branch_name="${1:10}"
  local worktree_path="../$branch_name"

  echo "Creating worktree for branch $1 at $worktree_path"

  if git show-ref --verify --quiet refs/heads/"$1"; then
    git worktree add "$worktree_path" "$1"
    (cd "$worktree_path" && git reset --hard origin/$1 && git branch --set-upstream-to=origin/$1 $1)
  else
    git worktree add "$worktree_path" -b "$1"
  fi

  (cd "$worktree_path" && cp ~/github/genjis/main/.env.development.local .env.development.local)
  (cd "$worktree_path" && yarn > /dev/null 2>&1 &)

  code "$worktree_path"
}
