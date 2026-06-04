#!/usr/bin/env bash
set -euo pipefail

# GitHub Copilot CLI `agentStop` hook handler.
# Copilot delivers command-hook input in Claude-compatible snake_case
# (session_id, transcript_path, cwd) and sets CLAUDE_PLUGIN_ROOT /
# {CLAUDE,COPILOT}_PROJECT_DIR env vars, so the wiring mirrors the Claude hook.
# The transcript is Copilot's events.jsonl, which differs from Claude's: usage
# lives on `assistant.message` events as data.model + data.outputTokens.

input=$(cat)
sid=$(jq -r '.session_id // .sessionId // empty' <<<"$input")
tp=$(jq -r '.transcript_path // .transcriptPath // empty' <<<"$input")
cwd=$(jq -r '.cwd // empty' <<<"$input")

[[ -z "$sid" || -z "$tp" || ! -f "$tp" ]] && exit 0

root="${cwd:-${COPILOT_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-$PWD}}}"
plugin_root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
pricing_file="${CLAUDE_PLUGIN_OPTION_PRICING_FILE:-$plugin_root/scripts/pricing.json}"
out_dir="$root/.aiusage/$(date +%Y-%m-%d)"
mkdir -p "$out_dir"

[[ ! -f "$pricing_file" ]] && exit 0

jq -s --arg sid "$sid" --slurpfile prices "$pricing_file" '
  def cost(model; inp; out; cw; cr):
    $prices[0][model] as $p
    | if $p then (inp * $p.input + out * $p.output + cw * $p.cache_write + cr * $p.cache_read) / 1000000
      else null end;

  # Copilot events.jsonl: assistant turns are `assistant.message` events.
  # Only outputTokens is recorded for non-Anthropic models; input/cache fields
  # are read defensively and default to 0 so the schema matches claude summaries.
  [.[] | select(.type == "assistant.message")] as $msgs
  | ($msgs
     | group_by(.data.model)
     | map(
         (.[0].data.model // "unknown") as $model
         | (map(.data.usage.input_tokens // 0) | add // 0) as $inp
         | (map(.data.outputTokens // .data.usage.output_tokens // 0) | add // 0) as $out
         | (map(.data.usage.cache_creation_input_tokens // 0) | add // 0) as $cw
         | (map(.data.usage.cache_read_input_tokens // 0) | add // 0) as $cr
         | {
             key: $model,
             value: {
               messages: length,
               input_tokens: $inp,
               output_tokens: $out,
               cache_creation_input_tokens: $cw,
               cache_read_input_tokens: $cr,
               cost_usd: cost($model; $inp; $out; $cw; $cr),
               pricing_unit: "per_million_tokens"
             }
           }
       )
    ) as $by_model
  | {
      session_id: $sid,
      source: "copilot",
      last_updated: (now | todate),
      messages: ($msgs | length),
      total_cost_usd: ([$by_model[].value.cost_usd | select(. != null)] | if length > 0 then (add * 100 | round) / 100 else null end),
      usage: ($by_model | from_entries)
    }
' "$tp" > "$out_dir/copilot-${sid}_summary.json"
