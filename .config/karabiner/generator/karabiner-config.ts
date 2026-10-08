// Karabiner-Elements configuration — source of truth for the
// "Default profile" complex_modifications rules.
//
//   npm run build     generate ~/.config/karabiner/karabiner.json
//   npm run verify    build + format + compare against live config (byte-exact)
//
// The generator output is normalized to the Karabiner-Elements GUI's
// canonical format (alphabetized keys) and formatted with the repo's
// prettier-plugin-karabiner (json_writer byte format), so a clean build
// produces zero diff against a GUI-maintained karabiner.json.
//
// Ported 1:1 from the hand-maintained karabiner.json, including:
//   - all three disabled rules (control+tab, MS RDP, home-row mods)
//   - the previously-uncommitted Ctrl+Space input-source rule
//     and scripts/toggle-input-source.sh (now tracked)
//   - the two hand-written rules re-keyed to the GUI's canonical order
//     (content unchanged), so the whole file round-trips byte-identically
//
// Device IDs (from Karabiner-Elements event viewer):
//   Adv360 Pro (BLE)     vendor 7504  product 24926
//   Adv360 Pro (USB)     vendor 10730 product 866     (wired QMK mode)
//   gaming keyboard      vendor 7847  product 2311    (COMPX 2.4G dongle)

import {
  ifApp,
  ifDevice,
  ifVar,
  map,
  mapConsumerKey,
  mapSimultaneous,
  rule,
  withCondition,
  withMapper,
  type Rule,
} from 'karabiner.ts'

// ---------------------------------------------------------------------------
// Devices
// ---------------------------------------------------------------------------

const adv360Ble = { vendor_id: 7504, product_id: 24926 }
const adv360Usb = { vendor_id: 10730, product_id: 866 }
const gamingKeyboard = { vendor_id: 7847, product_id: 2311 }
// USB-C EarPods inline remote (Karabiner Event Viewer: is_consumer).
const appleEarpods = { vendor_id: 1452, product_id: 4363 }

// Condition factories — the live config repeats these on every manipulator.
const zenApps = () => ifApp(['app.zen-browser.zen', /^com\.jgoon\.satori$/])
const capsPressed = () => ifVar('caps_lock pressed', 1)
const vimMode = () => ifVar('vim_mode', 1)
const notAdv360 = () => ifDevice(adv360Ble).unless()
const notTerminalApps = () =>
  ifApp(['com.googlecode.iterm2', 'com.github.atom', 'com.jetbrains.pycharm']).unless()

/** Live config uses side-specific left_* modifiers; keep them explicit. */
const hyper4 = ['left_command', 'left_option', 'left_control', 'left_shift']

/** Add `enabled: false` / `title` to a built rule (karabiner.ts has no API). */
function disable(built: Rule, title?: string): Rule {
  return title ? { ...built, enabled: false, title } : { ...built, enabled: false }
}

// ---------------------------------------------------------------------------
// Rule 1 — Zen Browser tab switching
// ---------------------------------------------------------------------------

const zenRule = rule(
  'Zen Browser - Cmd+Option+Left/Right to previous/next tab (all keyboards, including QMK macro order)',
).manipulators([
  // QMK macros arrive as left_option+left_command+arrow; fired strictly in
  // macro order with a 500ms window, on either Adv360 connection mode.
  mapSimultaneous(
    ['left_arrow', 'left_command', 'left_option'],
    { detect_key_down_uninterruptedly: true, key_down_order: 'strict', key_up_when: 'all' },
    500,
  )
    .modifiers('optionalAny')
    .to('open_bracket', ['command', 'shift'])
    .condition(zenApps(), ifDevice([adv360Ble, adv360Usb])),
  mapSimultaneous(
    ['right_arrow', 'left_command', 'left_option'],
    { detect_key_down_uninterruptedly: true, key_down_order: 'strict', key_up_when: 'all' },
    500,
  )
    .modifiers('optionalAny')
    .to('close_bracket', ['command', 'shift'])
    .condition(zenApps(), ifDevice([adv360Ble, adv360Usb])),
  // Vanilla Cmd+Option+←/→ on every other keyboard.
  map('left_arrow', ['command', 'option'])
    .to('open_bracket', ['command', 'shift'])
    .condition(zenApps()),
  map('right_arrow', ['command', 'option'])
    .to('close_bracket', ['command', 'shift'])
    .condition(zenApps()),
  // Mac keyboard, caps held (layer var from rule 4): ctrl+h / ctrl+l.
  map('h', 'left_control')
    .to('open_bracket', ['command', 'shift'])
    .condition(zenApps(), capsPressed(), notAdv360())
    .description('Mac keyboard Caps+Control+H to previous Zen tab'),
  map('l', 'left_control')
    .to('close_bracket', ['command', 'shift'])
    .condition(zenApps(), capsPressed(), notAdv360())
    .description('Mac keyboard Caps+Control+L to next Zen tab'),
])

// ---------------------------------------------------------------------------
// Rule 2 (disabled) — Control+Tab -> immediate Cmd+Tab
// ---------------------------------------------------------------------------

const controlTabRule = disable(
  rule('Control+Tab -> immediate Cmd+Tab on keydown')
    .manipulators(
      map('tab', 'control', 'any')
        .to$(
          'osascript -e \'tell application "System Events" to key code 48 using {command down}\'',
        )
        .condition(notAdv360()),
    )
    .build(),
)

// ---------------------------------------------------------------------------
// Rule 3 (disabled) — MS Remote Desktop: left cmd -> left ctrl
// ---------------------------------------------------------------------------

const msrdRule = disable(
  rule('MS Remote Desktop - Left cmd to Left ctrl')
    .manipulators(
      map({ key_code: 'left_gui' })
        .to('left_control', undefined, { repeat: true })
        .condition(ifApp('com.microsoft.rdc.macos'), notAdv360()),
    )
    .build(),
  'MS Remote Desktop',
)

// ---------------------------------------------------------------------------
// Rule 4 — caps layer: ESC alone, hjkl arrows, du page keys, fg hyper
// ---------------------------------------------------------------------------

const capsNavRule = rule(
  'CAPS > ESC, CAPS+H/J/K/L > ←↓↑→, CAPS+D/U > PG↓↑',
).manipulators([
  // The descriptions in live are legacy labels from when these were
  // control-chords; behavior kept verbatim from the original config.
  map('h', 'left_control')
    .to('left_arrow', ['left_command', 'left_option'])
    .condition(capsPressed(), notAdv360())
    .description('caps + left_control + h for moving to right tab'),
  map('l', 'left_control')
    .to('right_arrow', ['left_command', 'left_option'])
    .condition(capsPressed(), notAdv360())
    .description('caps + left_control + l for moving to left tab'),
  map('k', 'left_control')
    .to('w', 'left_command')
    .condition(capsPressed(), notAdv360())
    .description('caps + left_control + k for closing tabs'),
  map('j', 'optionalAny').to('down_arrow').condition(capsPressed(), notAdv360()),
  map('k', 'optionalAny').to('up_arrow').condition(capsPressed(), notAdv360()),
  map('h', 'optionalAny').to('left_arrow').condition(capsPressed(), notAdv360()),
  map('l', 'optionalAny').to('right_arrow').condition(capsPressed(), notAdv360()),
  map('d', 'optionalAny').to('page_down').condition(capsPressed(), notAdv360()),
  map('u', 'optionalAny').to('page_up').condition(capsPressed(), notAdv360()),
  // Layer toggle: press = var on, release = var off, alone = ESC.
  map('caps_lock', 'optionalAny')
    .toVar('caps_lock pressed', 1)
    .toAfterKeyUp({ set_variable: { name: 'caps_lock pressed', value: 0 } })
    .toIfAlone('escape')
    .condition(notAdv360()),
  map('f', 'optionalAny')
    .to('f', hyper4)
    .condition(capsPressed(), notAdv360())
    .description('caps + f -> cmd+opt+ctrl+shift+f'),
  map('g', 'optionalAny')
    .to('g', hyper4)
    .condition(capsPressed(), notAdv360())
    .description('caps + g -> cmd+opt+ctrl+shift+g'),
])

// ---------------------------------------------------------------------------
// Rule 5 — caps+A / caps+1..0 -> ctrl+A / ctrl+1..0
// ---------------------------------------------------------------------------

const capsWorkflowRule = rule(
  'CAPS+A / CAPS+1..0 > CTRL+A / CTRL+1..0 (workflow)',
).manipulators(
  withCondition(capsPressed(), notAdv360())(
    withMapper(['a', ...'1234567890'.split('')])((key) =>
      map(key)
        .to(key, 'left_control')
        .description(`caps + ${key} -> control + ${key}`),
    ),
  ),
)

// ---------------------------------------------------------------------------
// Rule 6 — vim mode toggle (caps_lock)
// ---------------------------------------------------------------------------

/** Turn vim_mode off and clear its notification. */
const vimOff = () => [
  { set_variable: { name: 'vim_mode', value: 0 } },
  { set_notification_message: { id: 'vim_mode_plus_enabled', text: '' } },
]

const vimToggleRule = rule(
  '(Vim 1/11) caps_lock -> on, caps_lock, esc, control+[ or any pointing_button -> off',
).manipulators([
  // Hold caps (>=100ms) or tap it: both arm vim_mode. Key-up disarms.
  map('caps_lock')
    .toIfAlone({ set_variable: { name: 'vim_mode', value: 1 } })
    .toIfHeldDown({ set_variable: { name: 'vim_mode', value: 1 } })
    .toAfterKeyUp(vimOff())
    .parameters({
      'basic.to_if_alone_threshold_milliseconds': 0,
      'basic.to_if_held_down_threshold_milliseconds': 100,
    })
    .condition(notTerminalApps(), ifVar('vim_mode').unless(), notAdv360()),
  map('caps_lock')
    .to(vimOff())
    .condition(notTerminalApps(), vimMode(), notAdv360()),
  map('escape')
    .to(vimOff())
    .condition(notTerminalApps(), vimMode(), notAdv360()),
  map('open_bracket', 'control')
    .to(vimOff())
    .condition(notTerminalApps(), vimMode(), notAdv360()),
  // Inside terminal/editor apps the mode is meaningless: any key exits it.
  map({ any: 'key_code' })
    .to(vimOff())
    .condition(
      ifApp(['com.googlecode.iterm2', 'com.github.atom', 'com.jetbrains.pycharm']),
      vimMode(),
      notAdv360(),
    ),
  // Any mouse button exits, on any device.
  map({ any: 'pointing_button' })
    .to(vimOff())
    .condition(vimMode(), notAdv360()),
])

// ---------------------------------------------------------------------------
// Rule 7 — vim navigation while vim_mode == 1
// ---------------------------------------------------------------------------

/** Shared conditions for every vim navigation manipulator. */
const vimNavConds = () => [notTerminalApps(), vimMode(), notAdv360()]

const vimNavRule = rule(
  '(Vim 8/11) h,j,k,l (+ control/option/command/shift),e,b,0,^,$,gg,G,{,}',
).manipulators([
  // hjkl + u/d as arrows / page keys (any optional modifiers).
  ...withCondition(...vimNavConds())([
    map('h', { optional: ['control', 'option', 'command', 'shift'] }).to('left_arrow'),
    map('j', { optional: ['control', 'option', 'command', 'shift'] }).to('down_arrow'),
    map('k', { optional: ['control', 'option', 'command', 'shift'] }).to('up_arrow'),
    map('l', { optional: ['control', 'option', 'command', 'shift'] }).to('right_arrow'),
    map('u', { optional: ['control', 'option', 'command', 'shift'] }).to('page_up'),
    map('d', { optional: ['control', 'option', 'command', 'shift'] }).to('page_down'),
    // Word-wise motion.
    map('e').to('right_arrow', 'left_alt'),
    map('b').to('left_arrow', 'left_alt'),
    map('w').to('right_arrow', 'left_alt'),
    // 0 -> cmd+left twice (line start); 6^/4$ via shifted digits.
    map('0').to('left_arrow', 'left_command').to('left_arrow', 'left_command'),
    map('6', 'shift').to('left_arrow', 'left_command'),
    map('4', 'shift').to('right_arrow', 'left_command'),
  ]),
  // gg: first g sets a var; delayed action (500ms) clears it. Second g
  // while set jumps to top. These two carry g_pressed in the middle of
  // their condition list (matching the original rule's order).
  map('g')
    .toVar('g_pressed', 1)
    .toDelayedAction([{ set_variable: { name: 'g_pressed', value: 0 } }], [])
    .parameters({ 'basic.to_delayed_action_delay_milliseconds': 500 })
    .condition(notTerminalApps(), vimMode(), ifVar('g_pressed').unless(), notAdv360()),
  map('g')
    .to('up_arrow', 'left_command')
    .toVar('g_pressed', 0)
    .condition(notTerminalApps(), vimMode(), ifVar('g_pressed'), notAdv360()),
  ...withCondition(...vimNavConds())([
    map('g', 'shift').to('down_arrow', 'left_command'),
    // {[ ]} -> ctrl+a / ctrl+e (bracketed paragraph jumps).
    map('open_bracket', 'shift').to('a', 'left_control'),
    map('close_bracket', 'shift').to('e', 'left_control'),
  ]),
])

// ---------------------------------------------------------------------------
// Rule 8 (disabled) — home-row mods
// ---------------------------------------------------------------------------

const homeRowModsRule = disable(
  rule('Home Row Mods: ASDF -> GACS, JKL; -> SCAG')
    .manipulators(
      withMapper({
        a: 'left_command',
        s: 'left_option',
        d: 'left_control',
        f: 'left_shift',
        j: 'right_shift',
        k: 'right_control',
        l: 'right_option',
        semicolon: 'right_command',
      })((key, mod) =>
        map(key, 'optionalAny')
          .toIfAlone({ halt: true, key_code: key })
          .toIfHeldDown(mod)
          .toDelayedAction([], [{ key_code: key }])
          .parameters({
            'basic.to_delayed_action_delay_milliseconds': 150,
            'basic.to_if_held_down_threshold_milliseconds': 150,
          })
          .condition(notAdv360()),
      ),
    )
    .build(),
)

// ---------------------------------------------------------------------------
// Rule 9 — EarPods center button
// ---------------------------------------------------------------------------
// Device-scoped so MacBook F8 does not fire Handy. USB enumerate ghosts
// are ignored by press duration (<30ms), not a Karabiner device-list on
// every tap. Handy PTT is F18: tap starts on keydown, hold ≥250ms cancels
// that start and toggles music. Hardware Fn remaps to F18 for the hold.

const earpodsRule = rule(
  'EarPods: tap = toggle Handy dictation, hold ≥250ms = play/pause music (fires mid-press)',
).manipulators(
  mapConsumerKey('play_or_pause')
    .to({
      shell_command: '/Users/jgoon/.config/karabiner/scripts/earpods-press.sh',
    })
    .toAfterKeyUp({
      shell_command: '/Users/jgoon/.config/karabiner/scripts/earpods-release.sh',
    })
    .toIfHeldDown({
      halt: true,
      shell_command: '/Users/jgoon/.config/karabiner/scripts/earpods-music-toggle.sh',
    })
    .parameters({ 'basic.to_if_held_down_threshold_milliseconds': 250 })
    .condition(ifDevice(appleEarpods)),
)

// ---------------------------------------------------------------------------
// Rule 10 — Fn hold = F18 hold (Handy PTT)
// ---------------------------------------------------------------------------
// macOS drops CGEvent / virtual-HID Fn, so Handy is bound to F18 instead.
// A basic remap holds F18 for as long as Fn is held — true push-to-talk.
// notAdv360: same Mac-keyboard scope as the caps layer.

const fnPassthroughRule = rule(
  'Fn → F18 hold (Handy push-to-talk; EarPods scripts hold the same F18)',
).manipulators(
  map('fn', 'optionalAny').to('f18').condition(notAdv360()),
)

// ---------------------------------------------------------------------------
// Rule 10 — Ctrl+Space input source toggle
// ---------------------------------------------------------------------------

const inputSourceRule = rule(
  'Ctrl+Space toggles EN/Chinese via macism on all keyboards EXCEPT gaming keyboard; never in Roblox',
).manipulators(
  map('spacebar', 'control')
    .to$('$HOME/.config/karabiner/scripts/toggle-input-source.sh')
    .condition(
      ifApp(/^com\.roblox\./).unless(),
      ifDevice([gamingKeyboard, adv360Usb]).unless(),
    ),
)

// ---------------------------------------------------------------------------
// Assemble + write
// ---------------------------------------------------------------------------

const rules = [
  zenRule,
  controlTabRule,
  msrdRule,
  capsNavRule,
  capsWorkflowRule,
  // NOTE: live order puts the nav rule (Vim 8/11) before the toggle rule
  // (Vim 1/11) — later rules take precedence, and the toggle's `any key`
  // exit-off manipulator must not shadow navigation keys.
  vimNavRule,
  vimToggleRule,
  homeRowModsRule,
  earpodsRule,
  fnPassthroughRule,
  inputSourceRule,
]

export { rules }

// When run directly (npm run build / verify), write the profile.
if (import.meta.url === `file://${process.argv[1]}`) {
  const { writeProfile } = await import('./lib/write.ts')
  writeProfile(rules)
}
