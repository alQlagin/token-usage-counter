#!/usr/bin/env bash
set -euo pipefail

date_arg="${1:-$(date +%Y-%m-%d)}"
data_dir="${2:-$PWD/.aiusage}"
usage_dir="$data_dir/$date_arg"

if [[ ! -d "$usage_dir" ]]; then
  echo '{"error": "no data found for '"$date_arg"'"}' >&2
  exit 1
fi

# Collect all session summary files (not message logs) from every supported
# runtime: Claude Code (claude-*) and GitHub Copilot CLI (copilot-*).
mapfile -t files < <(find "$usage_dir" -maxdepth 1 \( -name 'claude-*_summary.json' -o -name 'copilot-*_summary.json' \))

if [[ ${#files[@]} -eq 0 ]]; then
  echo '{"error": "no session files found in '"$usage_dir"'"}' >&2
  exit 1
fi

jq -s --arg date "$date_arg" '
  . as $sessions
  | ($sessions | length) as $session_count
  | ($sessions | map(.messages // 0) | add // 0) as $total_messages
  | ($sessions | map(.total_cost_usd | select(. != null)) | if length > 0 then (add * 100 | round) / 100 else null end) as $total_cost

  # Collect all model entries across sessions
  | [ $sessions[].usage // {} | to_entries[] ] as $all_model_entries

  # Group by model and aggregate
  | ($all_model_entries
     | group_by(.key)
     | map(
         (.[0].key) as $model
         | (map(.value.messages // 0) | add // 0) as $msgs
         | (map(.value.input_tokens // 0) | add // 0) as $inp
         | (map(.value.output_tokens // 0) | add // 0) as $out
         | (map(.value.cache_creation_input_tokens // 0) | add // 0) as $cw
         | (map(.value.cache_read_input_tokens // 0) | add // 0) as $cr
         | (map(.value.cost_usd | select(. != null)) | if length > 0 then (add * 100 | round) / 100 else null end) as $cost
         | {
             key: $model,
             value: {
               sessions: (map(select(.value.messages != null)) | length),
               messages: $msgs,
               input_tokens: $inp,
               output_tokens: $out,
               cache_creation_input_tokens: $cw,
               cache_read_input_tokens: $cr,
               cost_usd: $cost
             }
           }
       )
     | from_entries
    ) as $by_model

  | {
      date: $date,
      sessions: $session_count,
      total_messages: $total_messages,
      total_cost_usd: $total_cost,
      token_totals: {
        input_tokens: ([$by_model[].input_tokens] | add // 0),
        output_tokens: ([$by_model[].output_tokens] | add // 0),
        cache_creation_input_tokens: ([$by_model[].cache_creation_input_tokens] | add // 0),
        cache_read_input_tokens: ([$by_model[].cache_read_input_tokens] | add // 0)
      },
      by_model: $by_model
    }
' "${files[@]}"
