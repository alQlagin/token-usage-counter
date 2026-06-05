#!/usr/bin/env bash
set -euo pipefail

input=$(cat)
sid=$(jq -r '.session_id // empty' <<<"$input")
tp=$(jq -r '.transcript_path // empty' <<<"$input")

[[ -z "$sid" || -z "$tp" || ! -f "$tp" ]] && exit 0

root="${CLAUDE_PROJECT_DIR:-.}"
out_dir="$root/.aiusage/$(date +%Y-%m-%d)"
mkdir -p "$out_dir"

transcripts=("$tp")
sub_dir="${tp%.jsonl}/subagents"
if [[ -d "$sub_dir" ]]; then
  while IFS= read -r f; do transcripts+=("$f"); done \
    < <(find "$sub_dir" -maxdepth 1 -name '*.jsonl')
fi

# All transcript events, one JSONL line each.
# session_id and source are added for downstream identification.
jq -sc --arg sid "$sid" '
  .[] | . + {session_id: $sid, source: "claude"}
' "${transcripts[@]}" > "$out_dir/claude-${sid}_messages.jsonl"
