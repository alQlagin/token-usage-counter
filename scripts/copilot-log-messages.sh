#!/usr/bin/env bash
set -euo pipefail

input=$(cat)
sid=$(jq -r '.session_id // .sessionId // empty' <<<"$input")
tp=$(jq -r '.transcript_path // .transcriptPath // empty' <<<"$input")
cwd=$(jq -r '.cwd // empty' <<<"$input")

[[ -z "$sid" || -z "$tp" || ! -f "$tp" ]] && exit 0

root="${cwd:-${COPILOT_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-$PWD}}}"
out_dir="$root/.aiusage/$(date +%Y-%m-%d)"
mkdir -p "$out_dir"

# All transcript events, one JSONL line each.
# session_id and source are added for downstream identification.
jq -sc --arg sid "$sid" '
  .[] | . + {session_id: $sid, source: "copilot"}
' "$tp" > "$out_dir/copilot-${sid}_messages.jsonl"
