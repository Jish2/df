# Karabiner config is generated — never hand-edit karabiner.json

`karabiner.json` is build output. The source of truth is `generator/karabiner-config.ts`
(karabiner.ts DSL). Any key remap, rule, or condition change goes there — a hand edit
to the JSON is silently lost the next time anyone runs the build.

## Workflow

From this directory:

1. Edit `generator/karabiner-config.ts`
2. `cd generator && npm ci` — first time only (node_modules is not tracked)
3. `npm run build` — regenerates `karabiner.json`; Karabiner-Elements hot-reloads it
4. `npm run verify` — asserts the generator reproduces the live file byte-for-byte

Done means `npm run verify` prints `✓ Generator output is byte-identical to live karabiner.json`.
The byte-exactness matters: the pre-commit hook rejects karabiner.json in any other format,
so a failing verify (or a hand-edited JSON) blocks the next commit.

## If karabiner.json changed by hand

The Karabiner GUI or a rogue agent may have edited the JSON directly. Recovery:

- diff the change against `git show HEAD:.config/karabiner/karabiner.json`
- port the semantic change into `generator/karabiner-config.ts`
- `npm run build && npm run verify` until verify passes

## Gotchas

- `npm run build` writes to `$HOME/.config/karabiner/karabiner.json` (the live file),
  not the nearest `karabiner.json` — in a yadm worktree those are different files.
- Rule order is load-bearing: later rules take precedence. The vim nav rule (8/11)
  must stay before the toggle rule (1/11) so the toggle's any-key exit doesn't
  shadow navigation keys.
- Disabled rules (`enabled: false`) are intentional history — port them, don't drop them.
