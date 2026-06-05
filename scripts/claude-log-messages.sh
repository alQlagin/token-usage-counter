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

transcripts=("$tp")
sub_dir="${tp%.jsonl}/subagents"
if [[ -d "$sub_dir" ]]; then
  while IFS= read -r f; do transcripts+=("$f"); done \
    < <(find "$sub_dir" -maxdepth 1 -name '*.jsonl')
fi

# One JSONL line per assistant turn.
# Handles both Claude-format (.message.usage) and Copilot/VS Code native
# format (.type=="assistant.message") so VS Code Copilot Chat sessions
# produce real lines even when token data is absent.
jq -sc --arg sid "$sid" --slurpfile prices "$pricing_file" '
  def norm: (. // "unknown") | sub("-[0-9]{8}$"; "");
  def cost(model; inp; out; cw; cr):
    $prices[0][model] as $p
    | if $p then (inp * $p.input + out * $p.output + cw * $p.cache_write + cr * $p.cache_read) / 1000000
      else null end;

  .[] | (
    (
      select(.message.usage) |
      (.message.model | norm) as $model |
      (.message.usage.input_tokens // 0) as $inp |
      (.message.usage.output_tokens // 0) as $out |
      (.message.usage.cache_creation_input_tokens // 0) as $cw |
      (.message.usage.cache_read_input_tokens // 0) as $cr |
      {
        session_id: $sid,
        source: "claude",
        timestamp,
        model: $model,
        input_tokens: $inp,
        output_tokens: $out,
        cache_creation_input_tokens: $cw,
        cache_read_input_tokens: $cr,
        cost_usd: cost($model; $inp; $out; $cw; $cr)
      }
    ),
    (
      select(.type == "assistant.message" and .message == null) |
      (.data.model | norm) as $model |
      (.data.usage.input_tokens // null) as $inp |
      (.data.outputTokens // .data.usage.output_tokens // null) as $out |
      (.data.usage.cache_creation_input_tokens // null) as $cw |
      (.data.usage.cache_read_input_tokens // null) as $cr |
      {
        session_id: $sid,
        source: "claude",
        timestamp,
        model: $model,
        input_tokens: $inp,
        output_tokens: $out,
        cache_creation_input_tokens: $cw,
        cache_read_input_tokens: $cr,
        cost_usd: (if ($inp != null or $out != null)
          then cost($model; ($inp // 0); ($out // 0); ($cw // 0); ($cr // 0))
          else null end)
      }
    )
  )
' "${transcripts[@]}" > "$out_dir/claude-${sid}_messages.jsonl"
