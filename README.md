# token-usage-counter

A Claude Code plugin that tracks token usage and costs per session, with a skill to analyze daily spending.

## Installation

```
/plugin marketplace add alQlagin/token-usage-counter
/plugin install token-usage-counter@token-usage-counter
```

## How it works

A `Stop` hook fires when each Claude Code session ends. `scripts/claude-log-summary.sh` reads the session transcript, aggregates token counts by model, calculates cost, and writes a JSON summary to `.aiusage/YYYY-MM-DD/`.

## Output

Files are written to `<project>/.aiusage/YYYY-MM-DD/`:

| File | Contents |
|---|---|
| `claude-{session_id}_summary.json` | Aggregated token counts and cost summary per model |

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
      "cost_usd": 1.0418,
      "pricing_unit": "per_million_tokens"
    }
  }
}
```

`cost_usd` per model stores full precision; `total_cost_usd` is rounded to cents.

## Daily usage skill

Ask Claude about your spending and it will use the bundled `daily-usage` skill automatically:

> "How much did I spend today?"
> "Show my token usage for 2026-06-03"

## Pricing

Prices are defined in `scripts/pricing.json` (USD per million tokens) and loaded at runtime. To customize rates or add models, copy the sample file and edit it:

```bash
cp pricing.sample.json scripts/pricing.json
```

To use a completely different file (e.g. a shared team pricing file), set the `pricing_file` option via `/plugin` settings — the value is the absolute path to your custom `pricing.json`.

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
total_cost_usd = round_to_cents(
  Σ (input_tokens × p.input
   + output_tokens × p.output
   + cache_creation_input_tokens × p.cache_write
   + cache_read_input_tokens × p.cache_read) / 1_000_000
)
```
