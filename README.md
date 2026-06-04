# token-usage-counter

A plugin for **Claude Code** and **GitHub Copilot CLI** that tracks token usage and costs per session, with a skill to analyze daily spending. The same plugin installs into both runtimes.

## Installation

Claude Code:

```
/plugin marketplace add alQlagin/token-usage-counter
/plugin install token-usage-counter@token-usage-counter
```

GitHub Copilot CLI:

```
/plugin marketplace add alQlagin/token-usage-counter
/plugin install token-usage-counter
```

## How it works

A stop hook fires at the end of each agent turn. It reads the session transcript, aggregates token counts by model, calculates cost, and writes a JSON summary to `.aiusage/YYYY-MM-DD/`. Each runtime has its own hook and handler because their transcript formats differ:

| Runtime | Hook config | Event | Handler |
|---|---|---|---|
| Claude Code | `hooks/hooks.json` | `Stop` | `scripts/claude-log-summary.sh` |
| GitHub Copilot CLI | `hooks.json` (plugin root) | `agentStop` | `scripts/copilot-log-summary.sh` |

The two hook files live at different paths and never collide: Claude Code reads only `hooks/hooks.json`, while Copilot CLI auto-discovers the root `hooks.json` (and ignores the Claude file, which has no `version` field). Both handlers resolve their script and project paths from `${CLAUDE_PLUGIN_ROOT}` / `CLAUDE_PROJECT_DIR`, which Copilot CLI sets for Claude compatibility — so the wiring is portable across the marketplace install location of either runtime.

> **Copilot caveat:** Copilot's transcript records only **output tokens** (and the model) per turn — it has no input/cache token counts. Costs are therefore output-only, and only computed for models present in `pricing.json`. The default pricing file lists Claude models; add your Copilot/OpenAI model rates (e.g. `gpt-5`, `gpt-5-mini`) to get non-null Copilot costs.

## Output

Files are written to `<project>/.aiusage/YYYY-MM-DD/`:

| File | Contents |
|---|---|
| `claude-{session_id}_summary.json` | Aggregated token counts and cost summary per model (Claude Code) |
| `copilot-{session_id}_summary.json` | Same schema, from a Copilot CLI session |

Both runtimes write the **same schema**:

```json
{
  "session_id": "5c844b77-…",
  "source": "claude",
  "last_updated": "2026-06-04T19:00:44Z",
  "messages": 17,
  "total_cost_usd": 0.75,
  "usage": {
    "claude-opus-4-8": {
      "messages": 17,
      "input_tokens": 13639,
      "output_tokens": 8817,
      "cache_creation_input_tokens": 43232,
      "cache_read_input_tokens": 378350,
      "cost_usd": 0.747995,
      "pricing_unit": "per_million_tokens"
    }
  }
}
```

The `source` field identifies which runtime produced the summary — `"claude"` or `"copilot"` — matching the filename prefix. It lets tools tell the runtimes apart from the file contents alone, even after the files are moved or merged. (For Copilot sessions the per-model token fields other than `output_tokens` are `0` — see the caveat above.)

The `daily-usage` skill aggregates both `claude-*` and `copilot-*` summaries into one daily report.

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
