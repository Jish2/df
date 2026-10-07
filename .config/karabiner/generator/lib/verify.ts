// lib/verify.ts — prove the generator reproduces the live karabiner.json
// byte-for-byte.
//
//   npm run verify   (from .config/karabiner/generator)
//
// Reads the live config, swaps in the generated complex_modifications
// (exactly like writeProfile does), canonicalizes + formats through the
// same pipeline, and compares to the file on disk. Exits non-zero and
// writes the expected bytes to /tmp on divergence.

import { readFileSync, writeFileSync } from 'node:fs'
import { canonicalize, format, KARABINER_JSON } from './write.ts'

async function main() {
  const live = readFileSync(KARABINER_JSON, 'utf8')
  const expected = await renderExpected(live)
  if (expected === live) {
    console.log('✓ Generator output is byte-identical to live karabiner.json')
    return
  }
  console.error('✗ Generator output diverges from live karabiner.json')
  console.error(`  generated: ${expected.length} bytes, live: ${live.length} bytes`)
  writeFileSync('/tmp/karabiner-generated-expected.json', expected)
  console.error('  expected bytes written to /tmp/karabiner-generated-expected.json')
  process.exitCode = 1
}

/** Build the expected bytes for a given live-config body. */
async function renderExpected(live: string) {
  const { complexModifications } = await import('karabiner.ts')
  const { rules } = await import('../karabiner-config.ts')
  const existing = JSON.parse(live)
  const cm = complexModifications(rules)
  const profile = existing.profiles.find(
    (p: { name: string }) => p.name === 'Default profile',
  )
  if (!profile) throw new Error('Profile "Default profile" not found')
  profile.complex_modifications = { rules: cm.rules }
  return format(canonicalize(existing))
}

main()
