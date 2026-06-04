# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A single plugin that installs into **both** Claude Code and GitHub Copilot CLI. It tracks per-session token usage and cost via a stop hook, and bundles a `daily-usage` skill that aggregates those summaries into a daily report. There is no build step, package manager, or test suite — it is Bash + `jq` + JSON config. `jq` is the hard dependency for everything.

## Architecture

The whole system is a pipeline: **stop hook → handler script → per-session summary JSON → skill aggregator → daily report.** Understanding it means seeing why each piece is duplicated per runtime.

### Two runtimes, two of almost everything

Claude Code and Copilot CLI have *different transcript formats* and *different hook event names*, so each gets its own hook config, handler script, and pricing file. The pair is intentionally kept parallel — when you change one side, check whether the other needs the mirror change.

| Concern | Claude Code | Copilot CLI |
|---|---|---|
| Hook config | `hooks/hooks.json` (event `Stop`, key `command`) | `hooks.json` at repo root (event `agentStop`, key `bash`, `version: 1`) |
| Handler | `scripts/claude-log-summary.sh` | `scripts/copilot-log-summary.sh` |
| Pricing | `scripts/claude-pricing.json` | `scripts/copilot-pricing.json` |
| Model IDs | dashed (`claude-opus-4-8`) | dotted (`claude-opus-4.8`, `gpt-5.2`) |
| Transcript usage location | `.message.usage.{input,output,cache_*}_tokens` on every message | `.data.outputTokens` on `assistant.message` events only |

The two hook files coexist without colliding: Claude Code reads only `hooks/hooks.json`; Copilot CLI auto-discovers the root `hooks.json` and ignores the Claude file (which lacks the `version` field). Copilot sets `CLAUDE_PLUGIN_ROOT` / `CLAUDE_PROJECT_DIR` and delivers snake_case hook input for Claude compatibility, which is why the two handlers can be near-identical.

### The two handlers produce one shared schema

Both `*-log-summary.sh` scripts run essentially the same `jq` program: group messages by model, sum the four token fields, compute `cost_usd` per model from the pricing file, round the daily total to cents, and write `<source>-<session_id>_summary.json` to `<project>/.aiusage/YYYY-MM-DD/`. The output schema (including the `source: "claude"|"copilot"` discriminator and `pricing_unit`) is **identical across runtimes by design** — downstream tooling reads files of either origin uniformly. If you change a field name, shape, or rounding rule, change it in *both* handlers and in the skill aggregator, or the daily report breaks.

The Copilot caveat drives the schema: Copilot's transcript records only `outputTokens`, so its summaries have `0` for input/cache fields and the cost is output-only. The non-output token fields are read defensively (`// 0`) precisely so the schema still matches Claude's.

### Cost model

`cost(model; inp; out; cw; cr)` looks the model up in the slurped pricing file; **a missing model key yields `cost_usd: null`** (not an error, not zero) and that session/model is excluded from totals. Pricing is USD per million tokens. The `pricing_file` user config option (env `CLAUDE_PLUGIN_OPTION_PRICING_FILE`) overrides the bundled file for *both* runtimes — note it must therefore contain whichever ID convention the active runtime uses.

### The skill

`skills/daily-usage/` is a second-stage aggregator. `summarize-day.sh [YYYY-MM-DD] [data-dir]` globs `claude-*_summary.json` and `copilot-*_summary.json` from `.aiusage/<date>/`, merges them across sessions and models, and re-rounds totals. It is invoked by the `daily-usage` skill (SKILL.md) when the user asks about spending. Sessions with `null` cost are silently dropped from cost totals — the skill is expected to note this.

## Conventions when editing

- **Keep the two handlers in lockstep.** They share a schema and a cost function; a fix to one usually belongs in the other.
- **`.sample.json` files are documentation/templates**, not the active config. The active files are `scripts/{claude,copilot}-pricing.json`. README tables enumerate the shipped models — update them when you add a model.
- **`set -euo pipefail`** in every script; hooks are wired with `… 2>/dev/null || true` so a failure never blocks the agent turn. Preserve that — a logging hook must not break the user's session.
- `.aiusage/` (generated output) and `*.local.json` are gitignored.

## Manual testing

No test framework. Exercise a handler by piping it the hook JSON it expects:

```bash
# Claude handler: needs session_id + transcript_path pointing at a real JSONL transcript
echo '{"session_id":"test","transcript_path":"/path/to/transcript.jsonl"}' \
  | CLAUDE_PROJECT_DIR=/tmp/usagetest CLAUDE_PLUGIN_ROOT="$PWD" scripts/claude-log-summary.sh
cat /tmp/usagetest/.aiusage/$(date +%Y-%m-%d)/claude-test_summary.json

# Daily aggregation for a date
bash skills/daily-usage/scripts/summarize-day.sh 2026-06-05 /tmp/usagetest/.aiusage
```

The Copilot handler is the same shape but expects a Copilot `events.jsonl` with `assistant.message` events.
