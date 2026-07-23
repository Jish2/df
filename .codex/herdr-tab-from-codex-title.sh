#!/bin/sh
# Launches Herdr/Codex title synchronization without blocking the Codex hook.

set -eu

[ "${HERDR_ENV:-}" = "1" ] || exit 0
[ -n "${HERDR_TAB_ID:-}" ] || exit 0
[ -n "${HERDR_PANE_ID:-}" ] || exit 0
command -v python3 >/dev/null 2>&1 || exit 0
command -v herdr >/dev/null 2>&1 || exit 0
command -v codex >/dev/null 2>&1 || exit 0

hook_input_file="$(mktemp "${TMPDIR:-/tmp}/herdr-codex-tab-title.XXXXXX")" || exit 0
cat >"$hook_input_file" 2>/dev/null || true

codex_data_dir="${CODEX_HOME:-$HOME/.codex}"
nohup python3 "$codex_data_dir/herdr_codex_title.py" "$hook_input_file" \
    </dev/null >/dev/null 2>&1 &
exit 0
