#!/bin/sh
#
# Smoke tests for vale-edit.sh. Run from the repo root: sh tests/run.sh
#
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
hook=$root/scripts/vale-edit.sh
work=$(mktemp -d)
trap 'rm -rf "$work"' 0
fails=0

check() {
  name=$1 expect=$2 out=$3
  if [ "$expect" = EMPTY ] && [ -z "$out" ]; then
    printf 'ok    %s\n' "$name"
  elif [ "$expect" != EMPTY ] && printf '%s' "$out" | grep -q -- "$expect"; then
    printf 'ok    %s\n' "$name"
  else
    printf 'FAIL  %s\n      expected: %s\n      got: %s\n' "$name" "$expect" "$out"
    fails=$((fails + 1))
  fi
}

# Long, hedgy sentence that Voices and Direct should flag at error level.
printf '# Test\n\nIt is basically very important to note that we might possibly want to consider simply leveraging the synergies of this incredibly robust, innovative, and cutting-edge solution in order to effectively facilitate the optimization of various different workflows across the entire organization going forward.\n' > "$work/bad.md"
printf '# Test\n\nRun the installer.\n' > "$work/good.md"
printf 'x = 1\n' > "$work/code.py"

claude() { printf '{"hook_event_name":"PostToolUse","tool_name":"%s","cwd":"%s","tool_input":{"file_path":"%s"}}' "$1" "$work" "$2"; }

out=$(claude Write "$work/bad.md" | "$hook")
check 'Claude Write, bad prose' 'additionalContext' "$out"
out=$(claude Edit bad.md | "$hook")
check 'Claude Edit, relative path' 'bad.md:' "$out"
out=$(claude MultiEdit "$work/good.md" | "$hook")
check 'Claude MultiEdit, clean prose' EMPTY "$out"
out=$(claude Write "$work/code.py" | "$hook")
check 'Non-prose file ignored' EMPTY "$out"

patch=$(printf '*** Begin Patch\\n*** Update File: bad.md\\n*** End Patch')
out=$(printf '{"hook_event_name":"PostToolUse","tool_name":"apply_patch","cwd":"%s","tool_input":{"command":"%s"}}' "$work" "$patch" | "$hook")
check 'Codex apply_patch' 'bad.md:' "$out"

out=$(claude Write "$work/bad.md" | VALE_BIN=no-such-vale "$hook"; echo "exit=$?")
check 'Missing vale warns user, exit 0' 'systemMessage.*exit=0' "$(printf '%s' "$out" | tr '\n' ' ')"
out=$(claude Write "$work/code.py" | VALE_BIN=no-such-vale "$hook")
check 'Missing vale silent for non-prose' EMPTY "$out"

[ "$fails" -eq 0 ] && echo 'All tests passed.' || { echo "$fails test(s) failed."; exit 1; }
