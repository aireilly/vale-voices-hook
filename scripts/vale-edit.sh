#!/bin/sh
#
# Vale Voices PostToolUse hook for Claude Code and Codex.
# Adapted from vale-cli/agent-tools/hooks/vale-edit.sh.
#
# Lints .md and .adoc files after an edit and returns error-level alerts
# to the agent as additionalContext. Setup problems go to the user as a
# systemMessage with exit 0, so the agent is not nagged on every edit.
#
# Config lookup order:
#   1. $VALE_CONFIG
#   2. the .vale.ini bundled with this hook (../vale/.vale.ini)
#
set -u

hook_dir=$(cd "$(dirname "$0")" && pwd)
vale_config=${VALE_CONFIG:-"$hook_dir/../vale/.vale.ini"}
vale_bin=${VALE_BIN:-vale}
template=$hook_dir/vale-hook.tmpl

setup_warning() {
  # jq might be missing, so build the JSON by hand. Messages are fixed strings.
  printf '{"systemMessage":"vale-voices hook disabled: %s"}\n' "$1"
  exit 0
}

command -v jq >/dev/null 2>&1 || setup_warning 'jq is not installed.'

# Checked only once a .md or .adoc file turns up, so other edits stay quiet.
check_vale_setup() {
  command -v "$vale_bin" >/dev/null 2>&1 || setup_warning 'vale is not on PATH.'
  [ -f "$vale_config" ] || setup_warning 'Vale config not found. Set VALE_CONFIG.'
  [ -f "$template" ] || setup_warning 'vale-hook.tmpl is missing from the hook directory.'
}

payload=$(cat)
event=$(printf '%s\n' "$payload" | jq -r '.hook_event_name // empty')
case "$event" in
  PostToolUse) ;;
  *) exit 0 ;;
esac

tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/vale-voices.XXXXXX") || exit 0
cleanup() {
  rm -f "$tmpdir/out" "$tmpdir/err" "$tmpdir/paths" "$tmpdir/reports" "$tmpdir/response.md"
  rmdir "$tmpdir" 2>/dev/null || :
}
trap cleanup 0
trap 'exit 1' HUP INT TERM

emit_post_context() {
  jq -cn --arg message "$1" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$message}}'
}

format_errors() {
  awk -F '\t' -v label="$1" '
    $1 == "error" && NF >= 4 {
      message = $4
      for (i = 5; i <= NF; i++) message = message FS $i
      printf "  %s:%s: %s [%s] — %s\n", label, $2, $3, $1, message
    }
  ' "$tmpdir/out"
}

run_vale() {
  target=$1
  : > "$tmpdir/out"
  : > "$tmpdir/err"
  if ! "$vale_bin" --config="$vale_config" --no-exit --output="$template" --no-color --no-wrap --no-global "$target" >"$tmpdir/out" 2>"$tmpdir/err"; then
    code=$(head -n 1 "$tmpdir/err" | cut -d ' ' -f 1)
    why=$(grep -v '^[[:space:]]*$' "$tmpdir/err" | grep -v '^Execution stopped' | tail -n 1)
    RUN_FAILURE="Vale could not check this file: ${code:-error}: ${why:-unknown error}"
    return 1
  fi
  return 0
}

handle_post_tool_use() {
  file_path=$(printf '%s\n' "$payload" | jq -r '.tool_input.file_path // .tool_input.path // empty')
  patch=$(printf '%s\n' "$payload" | jq -r '.tool_input.command // empty')
  cwd=$(printf '%s\n' "$payload" | jq -r '.cwd // empty')
  [ -n "$cwd" ] || cwd=$(pwd)

  : > "$tmpdir/paths"
  [ -z "$file_path" ] || printf '%s\n' "$file_path" >> "$tmpdir/paths"
  printf '%s\n' "$patch" | awk '
    /^\*\*\* (Update|Add) File: / {
      sub(/^\*\*\* (Update|Add) File: /, "")
      print
    }
  ' >> "$tmpdir/paths"
  : > "$tmpdir/reports"

  raw_path=''
  while IFS= read -r raw_path || [ -n "$raw_path" ]; do
    [ -n "$raw_path" ] || continue
    lower_path=$(printf '%s' "$raw_path" | tr '[:upper:]' '[:lower:]')
    case "$lower_path" in
      *.md | *.adoc) ;;
      *) continue ;;
    esac

    case "$raw_path" in
      /*) target_path=$raw_path ;;
      *) target_path=$cwd/$raw_path ;;
    esac
    [ -f "$target_path" ] || continue
    check_vale_setup

    if ! run_vale "$target_path"; then
      emit_post_context "Vale could not check $raw_path: $RUN_FAILURE"
      return 0
    fi

    errors=$(format_errors "$raw_path")
    [ -z "$errors" ] || printf '%s\n' "$errors" >> "$tmpdir/reports"
  done < "$tmpdir/paths"

  reports=$(cat "$tmpdir/reports")
  [ -n "$reports" ] || return 0
  count=$(printf '%s\n' "$reports" | awk 'NF { n++ } END { print n + 0 }')
  emit_post_context "Vale reports $count error-level alert(s):
$reports

Fix these before moving on, preserving the markup exactly. Do not disable a rule to clear one."
}

case "$event" in
  PostToolUse) handle_post_tool_use ;;
esac
