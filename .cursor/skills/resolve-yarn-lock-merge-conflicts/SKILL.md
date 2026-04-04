---
name: resolve-yarn-lock-merge-conflicts
description: Resolve yarn.lock merge or rebase conflicts safely by regenerating the lockfile from resolved manifests, staging results, and continuing git operations. Use when yarn.lock shows conflict markers, git reports UU yarn.lock, or a merge/rebase fails on yarn.lock.
disable-model-invocation: true
---

# Resolve Yarn Lock Merge Conflicts

## When to use

Use this skill when:

- `git status` shows `UU yarn.lock`
- merge/rebase stops with a `yarn.lock` conflict
- `yarn.lock` contains conflict markers

## Default strategy

Do not hand-edit `yarn.lock` conflict markers. Use a clean base lockfile, then regenerate from the final `package.json` state.

## Workflow

1. Confirm conflict scope:
   - Run `git status --short --branch`
   - Resolve `package.json` conflicts first
2. Choose a lockfile base:
   - `git checkout --ours yarn.lock` (default), or `--theirs` if requested
3. Regenerate lockfile:
   - Run `yarn install` at repo root
4. Stage and continue:
   - `git add yarn.lock`
   - For rebase: `GIT_EDITOR=true git rebase --continue`
   - For merge: `git merge --continue`
5. If another commit re-introduces lock conflicts during rebase, repeat the same steps.

## Safety rules

- Never use destructive git commands unless explicitly requested.
- Do not change git config.
- Keep user changes in non-conflicting files untouched.
- If conflicts appear outside `yarn.lock`, resolve intentionally (do not auto-discard without checking intent).

## Command template

```bash
git status --short --branch
git checkout --ours yarn.lock
yarn install
git add yarn.lock
GIT_EDITOR=true git rebase --continue
```

For merge conflicts (not rebase), replace the last command with:

```bash
git merge --continue
```

## Notes

- In Yarn workspace repos, `yarn install` may run setup scripts. This is expected.
- If `yarn install` fails, fix dependency or registry/auth issues first, then rerun.
