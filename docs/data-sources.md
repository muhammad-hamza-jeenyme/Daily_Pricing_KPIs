# Data sources — Snowflake

Status: **TBD** — populate after pricing / BI guidance.

## Runtime

- **Agent**: Cursor Cloud Agent
- **Schedule**: Daily **11:30 AM PKT**
- **Access**: Snowflake MCP (`sql_exec_tool`)

## Conventions

- Do not invent schemas or table names.
- Document warehouse, database, schema, table, grain, and freshness for every KPI input.
- Prefer certified / production marts over ad-hoc extracts when available.

## Tables & views

| Object | Grain | Key columns | Freshness | Used by KPIs | Notes |
|--------|-------|-------------|-----------|--------------|-------|
| _TBD_ | | | | | |

## Timezone & “yesterday”

| Item | Value |
|------|-------|
| Business timezone for digests | PKT (UTC+5) unless Pricing says otherwise |
| Agent run time | 11:30 AM PKT |
| “Yesterday” definition | TBD (PKT calendar day vs city local day) |

## Query drafts

SQL drafts will live under `sql/` once tables are known.
