# token-counter

Tracks Claude token usage and costs per session via a `Stop` hook.

## How it works

`log-usage.sh` runs automatically when a Claude Code session ends. It reads the session transcript, aggregates token counts by model, calculates cost, and writes a JSON summary.

## Output

Files are written to `.claude/usage/YYYY-MM-DD/`:

| File | Contents |
|---|---|
| `{session_id}_summary.json` | Aggregated token counts and cost summary per model |
| `{session_id}_messages.jsonl` | Filtered user + assistant turns from the transcript |

### Example summary

```json
{
  "session_id": "966eec66-...",
  "last_updated": "2026-06-04T12:32:32Z",
  "messages": 48,
  "total_cost_usd": 1.34,
  "usage": {
    "claude-sonnet-4-6": {
      "messages": 44,
      "input_tokens": 88,
      "output_tokens": 15394,
      "cache_creation_input_tokens": 117934,
      "cache_read_input_tokens": 1227862,
      "cost_usd": 1.04,
      "pricing_unit": "per_million_tokens"
    }
  }
}
```

## Pricing

Prices are defined in `.claude/scripts/pricing.json` (USD per million tokens) and loaded at runtime — update that file to add models or adjust rates without touching the script.

Sources: [Anthropic pricing](https://platform.claude.com/docs/en/about-claude/pricing) · [Anthropic model overview](https://platform.claude.com/docs/en/about-claude/models/overview) · [AWS Bedrock pricing](https://aws.amazon.com/bedrock/pricing/)

| Model | Input | Output | Cache Write | Cache Read |
|---|---|---|---|---|
| claude-opus-4-8 | $5.00 | $25.00 | $6.25 | $0.50 |
| claude-opus-4-7 | $5.00 | $25.00 | $6.25 | $0.50 |
| claude-opus-4-6 | $5.00 | $25.00 | $6.25 | $0.50 |
| claude-opus-4-5 | $5.00 | $25.00 | $6.25 | $0.50 |
| claude-opus-4-1 | $15.00 | $75.00 | $18.75 | $1.50 |
| claude-sonnet-4-6 | $3.00 | $15.00 | $3.75 | $0.30 |
| claude-sonnet-4-5 | $3.00 | $15.00 | $3.75 | $0.30 |
| claude-haiku-4-5 | $1.00 | $5.00 | $1.25 | $0.10 |

**Cost formula:**

```
cost_usd = (input_tokens × p.input
          + output_tokens × p.output
          + cache_creation_input_tokens × p.cache_write
          + cache_read_input_tokens × p.cache_read) / 1_000_000
```

Per-model cost is rounded to cents before being summed into `total_cost_usd`.
