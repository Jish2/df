---
name: karabiner
description: Edit or inspect this machine's Karabiner-Elements config (~/.config/karabiner/). Use whenever the user mentions Karabiner, a key remap, caps-lock/layer behavior, a keyboard shortcut change, or files like karabiner.json — the config is generated from TypeScript; editing the JSON directly loses work on the next build.
---

# Karabiner config is generated

`~/.config/karabiner/karabiner.json` is build output. The source of truth is
`~/.config/karabiner/generator/karabiner-config.ts` (karabiner.ts DSL). Any
remap, rule, condition, or threshold change goes there. The Karabiner GUI may
rewrite the JSON — that is expected; hand edits are what get lost.

## Workflow

1. Edit `generator/karabiner-config.ts`. The file is commented rule-by-rule;
   match the existing style (`map()`, `rule()`, condition factories like
   `capsPressed()`).
2. `cd ~/.config/karabiner/generator && npm ci` — first time only on a
   machine (node_modules is not tracked).
3. `npm run build` — regenerates the JSON and writes it to the **live**
   `~/.config/karabiner/karabiner.json` ($HOME, never the nearest copy — in
   a yadm worktree those are different files). Karabiner-Elements watches
   the file and hot-reloads.
4. `npm run verify` — asserts the generator reproduces the live JSON
   byte-for-byte.

Done means verify prints `✓ Generator output is byte-identical to live
karabiner.json`. Byte-exactness matters: the df repo's pre-commit hook
rejects karabiner.json in any other format, so a failing verify blocks the
next commit.

## If karabiner.json was hand-edited

The GUI or another agent may have changed the JSON. Recovery:

1. `git -C ~/.config/karabiner diff` or compare against
   `git show HEAD:.config/karabiner/karabiner.json` (run from the yadm
   checkout / worktree that owns the file)
2. Port the semantic change into `generator/karabiner-config.ts`
3. `npm run build && npm run verify` until verify passes

## Gotchas

- Rule order is load-bearing: later rules take precedence. The vim nav rule
  (8/11) must stay before the toggle rule (1/11) so the toggle's any-key
  exit doesn't shadow navigation keys.
- Disabled rules (`enabled: false`) are intentional history — port them,
  don't drop them.
- Build reads the live JSON to preserve everything outside
  `complex_modifications` (devices, virtual_hid_keyboard, global). If a
  rule needs adding while the live file is stale, fix the live file first
  via the recovery path above.
- Devices: Adv360 Pro BLE = vendor 7504 / product 24926; its USB mode =
  10730/866; gaming keyboard = 7847/2311.
