import { defineHexConfig } from "@hex/commands"

// Hex personal transformations — managed by the df nix flake
// (modules/darwin/hex.nix symlinks this file into ~/.config/hex).
//
// Edit here, then `make here` (or copy to ~/.config/hex/hex.config.ts for an
// immediate test). Hex hot-reloads the config ~1/3s after the file changes.
//
// Vocabulary is the fix layer for misheard words (transcription-time, needs
// Labs > Vocabulary biasing ON, currently on). This file only carries
// generic text transformations.

export default defineHexConfig({
  transformations: {
    "trim-whitespace": {
      name: "Trim whitespace",
      description: "Remove leading and trailing whitespace",
      transform: (text) => text.trim(),
    },
  },
})
