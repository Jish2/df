// emit.ts — render the complete karabiner.json from karabiner-config.ts.
//
// The whole file is generated, not just complex_modifications: `global`,
// `devices`, `virtual_hid_keyboard` and the profile's identity used to live
// only in the tracked JSON, which made the generator a merge into live state
// and left those facts untracked on any machine that had never opened the
// Karabiner GUI. They are declarations here now, so this is the only input.

import { complexModifications } from 'karabiner.ts'
import { devices, global, profileIdentity } from './karabiner-config.ts'

export { render }

function render(rules: readonly unknown[]): unknown {
  // complexModifications() always injects its five default parameters. Those
  // are Karabiner's own defaults, so omitting them changes nothing, and every
  // config the GUI has written here omits them — keep it that way rather
  // than adding a parameters block the GUI would never produce.
  const { parameters: _unusedParameters, ...cm } = complexModifications(
    rules as never,
  )
  return {
    global,
    profiles: [
      {
        complex_modifications: cm,
        devices,
        ...profileIdentity,
      },
    ],
  }
}

function renderText(rules: readonly unknown[]): string {
  return `${JSON.stringify(render(rules), null, 4)}\n`
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const { rules } = await import('./karabiner-config.ts')
  process.stdout.write(renderText(rules))
}
