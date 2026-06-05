#!/usr/bin/env bash
set -euo pipefail

input=$(cat)
sid=$(jq -r '.session_id // .sessionId // empty' <<<"$input")
tp=$(jq -r '.transcript_path // .transcriptPath // empty' <<<"$input")
cwd=$(jq -r '.cwd // empty' <<<"$input")

[[ -z "$sid" || -z "$tp" || ! -f "$tp" ]] && exit 0

root="${cwd:-${COPILOT_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-$PWD}}}"
plugin_root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
pricing_file="${CLAUDE_PLUGIN_OPTION_PRICING_FILE:-$plugin_root/scripts/copilot-pricing.json}"
out_dir="$root/.aiusage/$(date +%Y-%m-%d)"
mkdir -p "$out_dir"

[[ ! -f "$pricing_file" ]] && exit 0

# One JSONL line per assistant.message event.
jq -sc --arg sid "$sid" --slurpfile prices "$pricing_file" '
  def cost(model; inp; out; cw; cr):
    $prices[0][model] as $p
    | if $p then (inp * $p.input + out * $p.output + cw * $p.cache_write + cr * $p.cache_read) / 1000000
      else null end;

  .[] | select(.type == "assistant.message") |
  (.data.model // "unknown") as $model |
  (.data.usage.input_tokens // null) as $inp |
  (.data.outputTokens // .data.usage.output_tokens // null) as $out |
  (.data.usage.cache_creation_input_tokens // null) as $cw |
  (.data.usage.cache_read_input_tokens // null) as $cr |
  {
    session_id: $sid,
    source: "copilot",
    timestamp,
    model: $model,
    input_tokens: $inp,
    output_tokens: $out,
    cache_creation_input_tokens: $cw,
    cache_read_input_tokens: $cr,
    cost_usd: (if ($out != null)
      then cost($model; ($inp // 0); ($out // 0); ($cw // 0); ($cr // 0))
      else null end)
  }
' "$tp" > "$out_dir/copilot-${sid}_messages.jsonl"
