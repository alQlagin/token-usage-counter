---
name: daily-usage
description: This skill should be used when the user asks to "show usage for today", "analyze daily usage", "how much did I spend today", "summarize token usage", "show costs for a day", "usage report", or "how many tokens did I use". Aggregates all per-session usage summaries for a given day into a single daily report with totals by model.
version: 0.1.0
---

# Daily Usage Analysis

## Overview

Aggregate all session-level token usage summaries for a given date into a single daily report. Each session produces a JSON file in `.aiusage/YYYY-MM-DD/`; this skill merges them into totals broken down by model.

## Workflow

### Step 1: Run the aggregation script

Execute the bundled script, passing the target date (defaults to today):

```bash
bash .claude/skills/daily-usage/scripts/summarize-day.sh [YYYY-MM-DD] [data-dir]
```

The script reads all `*.json` session summary files (excluding `*_messages.jsonl`) from `.aiusage/<date>/`, merges them with `jq`, and prints a JSON report to stdout.

### Step 2: Present the report

Parse and present the output to the user. Key fields to highlight:

- `date` — the day being reported
- `sessions` — number of sessions that ran
- `total_cost_usd` — total spend for the day
- `total_messages` — total assistant messages
- `by_model` — per-model breakdown with tokens and cost
- `token_totals` — aggregate token counts across all models

### Step 3: Handle edge cases

- If no usage directory exists for the date, report that no data was found.
- If some session files are missing `total_cost_usd` (null), they are excluded from the cost total — note this in the summary.
- If the user asks for a date range, run the script once per day and aggregate results.

## Output Schema

```json
{
  "date": "2026-06-04",
  "sessions": 3,
  "total_messages": 120,
  "total_cost_usd": 4.52,
  "token_totals": {
    "input_tokens": 238,
    "output_tokens": 45746,
    "cache_creation_input_tokens": 315640,
    "cache_read_input_tokens": 4406879
  },
  "by_model": {
    "claude-sonnet-4-6": {
      "sessions": 3,
      "messages": 116,
      "input_tokens": 238,
      "output_tokens": 45746,
      "cache_creation_input_tokens": 315640,
      "cache_read_input_tokens": 4406879,
      "cost_usd": 4.52
    }
  }
}
```

## Additional Resources

- **`scripts/summarize-day.sh`** — the aggregation script; read it if environment-specific adjustments are needed
