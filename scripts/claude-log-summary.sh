#!/usr/bin/env bash
set -euo pipefail

input=$(cat)
sid=$(jq -r '.session_id // empty' <<<"$input")
tp=$(jq -r '.transcript_path // empty' <<<"$input")

[[ -z "$sid" || -z "$tp" || ! -f "$tp" ]] && exit 0

root="${CLAUDE_PROJECT_DIR:-.}"
out_dir="$root/.aiusage/$(date +%Y-%m-%d)"
pricing_file="${CLAUDE_PLUGIN_OPTION_PRICING_FILE:-${CLAUDE_PLUGIN_ROOT}/scripts/claude-pricing.json}"
mkdir -p "$out_dir"

[[ ! -f "$pricing_file" ]] && exit 0

# Claude Code stores each subagent's turns in a sibling directory
# (<transcript>/subagents/agent-*.jsonl), separate from the main transcript.
# Slurp those alongside the main file so subagent tokens fold into this
# session's summary instead of being silently dropped.
transcripts=("$tp")
sub_dir="${tp%.jsonl}/subagents"
if [[ -d "$sub_dir" ]]; then
  while IFS= read -r f; do transcripts+=("$f"); done \
    < <(find "$sub_dir" -maxdepth 1 -name '*.jsonl')
fi

jq -s --arg sid "$sid" --arg tp "$tp" --slurpfile prices "$pricing_file" '
  # Strip a trailing -YYYYMMDD release suffix (e.g. claude-haiku-4-5-20251001,
  # which subagents may report) so the ID matches the bare pricing keys.
  def norm: (. // "unknown") | sub("-[0-9]{8}$"; "");

  def cost(model; inp; out; cw; cr):
    $prices[0][model] as $p
    | if $p then (inp * $p.input + out * $p.output + cw * $p.cache_write + cr * $p.cache_read) / 1000000
      else null end;

  [.[] | select(.message.usage)] as $msgs
  | ($msgs
     | group_by(.message.model | norm)
     | map(
         (.[0].message.model | norm) as $model
         | (map(.message.usage.input_tokens // 0) | add // 0) as $inp
         | (map(.message.usage.output_tokens // 0) | add // 0) as $out
         | (map(.message.usage.cache_creation_input_tokens // 0) | add // 0) as $cw
         | (map(.message.usage.cache_read_input_tokens // 0) | add // 0) as $cr
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
      source: "claude",
      transcript_path: $tp,
      last_updated: (now | todate),
      messages: ($msgs | length),
      total_cost_usd: ([$by_model[].value.cost_usd | select(. != null)] | if length > 0 then (add * 100 | round) / 100 else null end),
      usage: ($by_model | from_entries)
    }
' "${transcripts[@]}" > "$out_dir/claude-${sid}_summary.json"
