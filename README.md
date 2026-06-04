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

> **Copilot caveat:** Copilot's transcript records only **output tokens** (and the model) per turn — it has no input/cache token counts. Costs are therefore output-only, and computed from the dedicated `scripts/copilot-pricing.json` file (GitHub's usage-based rates for the GPT, Claude, and Gemini models Copilot offers). Add any model missing from that file to get its cost.

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

Prices are USD per million tokens, loaded at runtime. Each runtime has its own bundled file, because the two record different model identifiers — **Claude Code uses dashed IDs** (`claude-opus-4-6`), **Copilot CLI uses dotted IDs** (`claude-opus-4.6`, `gpt-5-mini`). A model with no matching key yields `cost_usd: null`.

| Runtime | Default file | Sample |
|---|---|---|
| Claude Code | `scripts/claude-pricing.json` | `claude-pricing.sample.json` |
| Copilot CLI | `scripts/copilot-pricing.json` | `copilot-pricing.sample.json` |

To customize rates or add models, copy the relevant sample over the active file and edit it:

```bash
cp claude-pricing.sample.json scripts/claude-pricing.json    # Claude Code
cp copilot-pricing.sample.json scripts/copilot-pricing.json  # Copilot CLI
```

To point at a file elsewhere (e.g. a shared team file), set the single `pricing_file` option via `/plugin` settings to its absolute path — it applies to **both** runtimes. Leave it unset to use the two bundled files above.

Sources: [Anthropic pricing](https://platform.claude.com/docs/en/about-claude/pricing) · [Anthropic model overview](https://platform.claude.com/docs/en/about-claude/models/overview) · [GitHub Copilot models and pricing](https://docs.github.com/en/copilot/reference/copilot-billing/models-and-pricing)

### Claude Code models — `scripts/claude-pricing.json` (dashed IDs)

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

### GitHub Copilot CLI models — `scripts/copilot-pricing.json` (dotted IDs)

GitHub Copilot moved to usage-based (per-token) billing on 2026-06-01; these are GitHub's published per-million-token rates. Cache Write is shown as the input rate for OpenAI/Google models, which have no separate cache-write surcharge.

| Model | Input | Output | Cache Write | Cache Read |
|---|---|---|---|---|
| gpt-5-mini | $0.25 | $2.00 | $0.25 | $0.025 |
| gpt-5.2 | $1.75 | $14.00 | $1.75 | $0.175 |
| gpt-5.2-codex | $1.75 | $14.00 | $1.75 | $0.175 |
| gpt-5.3-codex | $1.75 | $14.00 | $1.75 | $0.175 |
| gpt-5.4 | $2.50 | $15.00 | $2.50 | $0.25 |
| gpt-5.4-mini | $0.75 | $4.50 | $0.75 | $0.075 |
| gpt-5.4-nano | $0.20 | $1.25 | $0.20 | $0.02 |
| gpt-5.5 | $5.00 | $30.00 | $5.00 | $0.50 |
| claude-haiku-4.5 | $1.00 | $5.00 | $1.25 | $0.10 |
| claude-sonnet-4 | $3.00 | $15.00 | $3.75 | $0.30 |
| claude-sonnet-4.5 | $3.00 | $15.00 | $3.75 | $0.30 |
| claude-sonnet-4.6 | $3.00 | $15.00 | $3.75 | $0.30 |
| claude-opus-4.5 | $5.00 | $25.00 | $6.25 | $0.50 |
| claude-opus-4.6 | $5.00 | $25.00 | $6.25 | $0.50 |
| claude-opus-4.7 | $5.00 | $25.00 | $6.25 | $0.50 |
| claude-opus-4.8 | $5.00 | $25.00 | $6.25 | $0.50 |
| gemini-2.5-pro | $1.25 | $10.00 | $1.25 | $0.125 |
| gemini-3-flash | $0.50 | $3.00 | $0.50 | $0.05 |
| gemini-3.1-pro | $2.00 | $12.00 | $2.00 | $0.20 |
| gemini-3.5-flash | $1.50 | $9.00 | $1.50 | $0.15 |

> In practice only the **Output** rate affects Copilot costs, since Copilot's transcript records only output tokens (see the caveat above). The other columns apply if a future Copilot version logs full usage.

**Cost formula:**

```
total_cost_usd = round_to_cents(
  Σ (input_tokens × p.input
   + output_tokens × p.output
   + cache_creation_input_tokens × p.cache_write
   + cache_read_input_tokens × p.cache_read) / 1_000_000
)
```
