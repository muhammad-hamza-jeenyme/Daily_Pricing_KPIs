# Alert rules — severity & thresholds

Status: **v1 decisions locked** (2026-08-04).

## Slack channel vs Canvas

| Surface | Content |
|---------|---------|
| **Channel message (Pulsar)** | Short bizfin-style: country **% rides with fare increase** + city table (majors + Others) for SA and JO. Template: `automations/SLACK_MESSAGE_TEMPLATE.md` |
| **Canvas** | Detailed watches/alerts by area (DX-style). Template: `automations/CANVAS_WATCH_TEMPLATE.md` · reference https://easytaxime.slack.com/docs/T33U3F6CW/F0BL188MU3C |

## In-scope cities (channel table)

| Country | Columns |
|---------|---------|
| SA | `RUH`, `JED`, `MAD`, `DMM`, `MEC`, **Others** |
| JO | `AMM`, `IRB`, `ZRQ`, **Others** |

Others = all other boarded+destination areas in that country.

## Primary channel KPI

`pct_increase_pricing` = share of rides with `issue_type = increase_pricing` (fare up after removing waiting/cancel non-issue residual).

## Comparisons

| Window | Definition |
|--------|------------|
| **DoD** | Yesterday vs day before |
| **WoW** | Yesterday vs 7 days earlier |
| **MoM** | Yesterday vs 28 days earlier |
| **vs 7d avg** | Yesterday vs average of prior 7 complete days |

## Major shift (Canvas watches)

Flag when yesterday KPI > prior 7d average. Show on **Canvas**, not as a wall of text in the channel.

## SQL

| File | Use |
|------|-----|
| `sql/fare_integrity_channel_summary.sql` | Channel message |
| `sql/fare_integrity_slack_rollup.sql` | Canvas detail (majors) |

## Ownership

Pricing Slack channel `C0BMWLMR03T` · existing **Pricing KPI Alerts Slack** automation only · Pulsar webhook.
