// lib/write.ts — merge generated rules into the live karabiner.json.
//
// karabiner.ts's writeToProfile() replaces complex_modifications wholesale
// and injects five default parameters the live config doesn't have, so we
// do the merge ourselves with complexModifications() + a strict writer:
//
//   - profile "Default profile" complex_modifications is replaced by the
//     generated rules (no parameters object, matching the live file)
//   - everything else (global, devices, virtual_hid_keyboard, …) is
//     preserved verbatim from the existing file
//   - output is canonicalized to GUI key order (alphabetical, like
//     nlohmann::json's std::map) and formatted byte-identically to
//     Karabiner-Elements' json_writer via prettier + prettier-plugin-karabiner

import { complexModifications } from 'karabiner.ts'
import prettier from 'prettier'
import { readFileSync, writeFileSync } from 'node:fs'

export const KARABINER_JSON =
  process.env.KARABINER_JSON ?? `${process.env.HOME}/.config/karabiner/karabiner.json`

export { canonicalize, format }

/**
 * Sort keys recursively, matching Karabiner-Elements' GUI writer output.
 * `global` is exempt: the GUI (and writeToGlobal) preserve declaration
 * order there, e.g. show_in_menu_bar before enable_cgeventtap_fallback.
 * Also drops empty `to_if_invoked`/`to_if_canceled` arrays that
 * karabiner.ts emits but json_writer never writes.
 */
function canonicalize(value: unknown, isGlobal = false): unknown {
  if (Array.isArray(value)) return value.map((v) => canonicalize(v))
  if (typeof value === 'object' && value !== null) {
    const out: Record<string, unknown> = {}
    const keys = Object.keys(value as Record<string, unknown>)
    for (const key of isGlobal ? keys : keys.sort()) {
      const v = (value as Record<string, unknown>)[key]
      const childIsGlobal = key === 'global' && !isGlobal
      out[key] = canonicalize(v, childIsGlobal)
    }
    // Prune empty delayed-action branches (json_writer omits them).
    if ('to_delayed_action' in out) {
      const da = out.to_delayed_action as Record<string, unknown>
      for (const branch of ['to_if_invoked', 'to_if_canceled']) {
        if (Array.isArray(da[branch]) && da[branch].length === 0) delete da[branch]
      }
      if (Object.keys(da).length === 0) delete out.to_delayed_action
    }
    return out
  }
  return value
}

/** Format with the repo's karabiner prettier plugin (json_writer bytes). */
async function format(json: unknown): Promise<string> {
  const text = JSON.stringify(json)
  const out = await prettier.format(text, {
    parser: 'karabiner-json',
    plugins: [prettierPlugin()],
  })
  // Karabiner's json_writer never emits a trailing newline.
  return out.replace(/\n$/, '')
}

function prettierPlugin() {
  // The repo-local plugin, one directory above the generator project.
  const url = new URL('../../prettier-plugin-karabiner.mjs', import.meta.url)
  return import(url.href)
}

export async function writeProfile(rules: unknown[]) {
  const cm = complexModifications(rules as never)
  // Live config omits a profile-level parameters object; complexModifications
  // always injects five defaults, so strip them back out for byte parity.
  const generated = { rules: cm.rules }
  const existing = JSON.parse(readFileSync(KARABINER_JSON, 'utf8'))
  const profile = existing.profiles.find(
    (p: { name: string }) => p.name === 'Default profile',
  )
  if (!profile) throw new Error('Profile "Default profile" not found')
  profile.complex_modifications = generated

  const formatted = await format(canonicalize(existing))
  writeFileSync(KARABINER_JSON, formatted)
  console.log(`✓ Wrote ${cm.rules.length} rules to ${KARABINER_JSON}`)
}
