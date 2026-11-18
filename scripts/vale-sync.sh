#!/bin/sh
#
# SessionStart hook: download the Vale packages once if the styles are missing.
#
set -u

hook_dir=$(cd "$(dirname "$0")" && pwd)
vale_config=${VALE_CONFIG:-"$hook_dir/../vale/.vale.ini"}
vale_bin=${VALE_BIN:-vale}

command -v "$vale_bin" >/dev/null 2>&1 || exit 0
[ -f "$vale_config" ] || exit 0

styles_dir=$(dirname "$vale_config")/styles
[ -d "$styles_dir/Voices" ] && exit 0

if "$vale_bin" --config="$vale_config" sync >/dev/null 2>&1; then
  printf '%s\n' '{"systemMessage":"vale-voices: downloaded the Voices styles."}'
else
  printf '%s\n' '{"systemMessage":"vale-voices: vale sync failed. Run it by hand to see why."}'
fi
exit 0
