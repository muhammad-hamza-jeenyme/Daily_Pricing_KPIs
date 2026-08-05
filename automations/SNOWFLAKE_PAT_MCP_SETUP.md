# Snowflake MCP via custom PAT (Programmatic Access Token)

Use this so Cursor (and Cloud Automations) can run SQL like `sql/fare_integrity_slack_rollup.sql` without interactive login each time.

Official refs:
- [Programmatic Access Tokens](https://docs.snowflake.com/en/user-guide/programmatic-access-tokens)
- [Snowflake-managed MCP](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-mcp)
- [Snowflake Cursor plugin](https://github.com/snowflakedb/snowflake-cursor-plugin)

**Never commit the PAT or paste it into the public GitHub repo / Slack.**

---

## Why PAT (not only browser OAuth)

| Method | Good for |
|--------|----------|
| OAuth / `mcp_auth` click | Local Cursor chat (you’re at the laptop) |
| **PAT (Bearer token)** | Stable local MCP + Cloud Agent / Automation (laptop off) |

Your first automation failure (“Snowflake MCP not attached”) is fixed by: **attach Snowflake in the Automation** + **auth that Snowflake connection with a PAT** (or dashboard OAuth if offered). PAT is the usual custom path.

---

## Step 1 — Snowflake side: role & access

Ask a Snowflake admin (or do this if you have rights):

1. Use a **least-privilege role** that can:
   - `USAGE` on warehouse
   - `USAGE` on database/schema needed for Pricing tables
   - `SELECT` on:
     - `JEENY_PROD.RIDE.DETAILS`
     - `JEENY_PROD.RIDE.UPFRONT`
     - `JEENY_PROD.RIDE.RECEIPTS`
     - `JEENY_PROD.PASSENGERS.PRICECHECKS`
     - `JEENY_PROD.GENERAL.AREAS`
2. If you use a **Snowflake-managed MCP server** object, grant `USAGE` on that MCP server to the same role.

Example pattern (admin adjusts names):

```sql
-- Illustrative only — use your real role / warehouse / MCP object names
GRANT USAGE ON WAREHOUSE <YOUR_WH> TO ROLE <PRICING_MCP_ROLE>;
GRANT USAGE ON DATABASE JEENY_PROD TO ROLE <PRICING_MCP_ROLE>;
GRANT USAGE ON SCHEMA JEENY_PROD.RIDE TO ROLE <PRICING_MCP_ROLE>;
GRANT USAGE ON SCHEMA JEENY_PROD.PASSENGERS TO ROLE <PRICING_MCP_ROLE>;
GRANT USAGE ON SCHEMA JEENY_PROD.GENERAL TO ROLE <PRICING_MCP_ROLE>;
GRANT SELECT ON ALL TABLES IN SCHEMA JEENY_PROD.RIDE TO ROLE <PRICING_MCP_ROLE>;
GRANT SELECT ON ALL TABLES IN SCHEMA JEENY_PROD.PASSENGERS TO ROLE <PRICING_MCP_ROLE>;
GRANT SELECT ON ALL TABLES IN SCHEMA JEENY_PROD.GENERAL TO ROLE <PRICING_MCP_ROLE>;
```

---

## Step 2 — Network policy (often required for PAT)

Snowflake often **requires a network policy** on the user before PAT generation (especially service users).

1. In Snowsight: **Admin → Security → Network Policies** (or ask admin).
2. Ensure **your user** (or the service user for the bot) has a network policy that allows:
   - Your office / home IP (for local Cursor), **and**
   - Cursor Cloud Agent egress IPs (if Cloud Automation must call Snowflake) — confirm with Cursor/Snowflake admin what to allowlist.

Without this, PAT create/use may fail with network-policy errors.

---

## Step 3 — Generate the custom PAT in Snowsight

1. Log into **Snowsight**.
2. Click your avatar → **Settings** → **Authentication** → **Programmatic access tokens**.
3. **Generate new token** (wording may be “Add token”).
4. Set:
   - **Name:** e.g. `cursor-pricing-kpis-mcp`
   - **Role restriction:** the least-privilege role from Step 1 (important)
   - **Expiry:** e.g. 90 days (then rotate)
5. **Generate** → **copy the token immediately** (you won’t see it again).
6. Store in a password manager as `SNOWFLAKE_PAT`.

### Optional: create PAT via SQL (admin)

```sql
ALTER USER <YOUR_USER> ADD PROGRAMMATIC ACCESS TOKEN cursor_pricing_kpis_mcp
  ROLE_RESTRICTION = '<PRICING_MCP_ROLE>'
  DAYS_TO_EXPIRY = 90
  COMMENT = 'Cursor MCP / Cloud Automation for Daily Pricing KPIs';
```

Save the returned `token_secret`.

---

## Step 4 — Get your Snowflake MCP server URL

You need the **Managed MCP endpoint** (not just the account login URL).

Format:

```text
https://<ORG>-<ACCOUNT>.snowflakecomputing.com/api/v2/databases/<DATABASE>/schemas/<SCHEMA>/mcp-servers/<MCP_SERVER_NAME>
```

Notes:
- Use **hyphens** in the hostname, not underscores (SSL errors if wrong).
- `<DATABASE>`, `<SCHEMA>`, `<MCP_SERVER_NAME>` are wherever your team created the MCP server object in Snowflake.
- Ask BI/platform for the exact URL if you don’t own the MCP object.

If your team instead uses Cursor’s **Snowflake plugin / dashboard Snowflake** connection (account + user + PAT fields in UI), use that UI and paste the PAT there — same token, different form.

---

## Step 5 — Configure Cursor MCP with PAT

### Option A — Cursor Settings UI

1. Cursor → **Settings** → **Tools & MCP** (or **MCP**).
2. **Add Custom MCP** / edit Snowflake.
3. Set:
   - **URL** = MCP server URL from Step 4  
   - **Header** `Authorization` = `Bearer <YOUR_PAT>`  
   (UI may have a single “Token / PAT” field — paste PAT only if it auto-adds `Bearer`.)

### Option B — `mcp.json` (user-level)

Create/edit MCP config (path depends on Cursor version; often user MCP settings, not the git repo).

Example shape:

```json
{
  "mcpServers": {
    "snowflake": {
      "url": "https://<ORG>-<ACCOUNT>.snowflakecomputing.com/api/v2/databases/<DB>/schemas/<SCHEMA>/mcp-servers/<SERVER>",
      "headers": {
        "Authorization": "Bearer <YOUR_PAT>"
      }
    }
  }
}
```

Replace placeholders. **Do not** commit this file if it contains the real PAT.

4. Restart Cursor or toggle the MCP server **Off → On**.
5. Confirm tools appear (e.g. SQL exec / list tools).

---

## Step 6 — Quick verify (local)

In Cursor chat (this project), ask the agent to run a tiny query, e.g.:

```sql
SELECT CURRENT_DATE() AS d, CURRENT_ROLE() AS role;
```

Then run a one-liner from the rollup (or full `sql/fare_integrity_slack_rollup.sql`).

If that works locally, PAT + MCP URL are correct.

---

## Step 7 — Cloud Automation (laptop off)

Local `mcp.json` does **not** automatically apply to Cloud Agents.

1. Open your **Daily Pricing** automation in Automations.
2. **Tools** → enable / select **Snowflake**.
3. Complete Snowflake auth for Cloud:
   - Paste the **same PAT** (and MCP URL / account fields) where the editor asks, **or**
   - Connect Snowflake in [Cloud Agents dashboard](https://cursor.com/dashboard?tab=cloud-agents) so automations can use it.
4. Save → **Run once** manually.
5. Success = Pulsar (or Cursor) gets real city KPIs, not “Snowflake MCP not attached”.

---

## Step 8 — Rotate / revoke

| When | Action |
|------|--------|
| Every 60–90 days | Generate new PAT, update Cursor + Automation, revoke old |
| If leaked | Revoke immediately in Snowsight Authentication |
| Person leaves | Revoke their PAT / disable user |

---

## Troubleshooting

| Symptom | Likely fix |
|---------|------------|
| Network policy / PAT create blocked | Assign network policy to user; allowlist needed IPs |
| 401 Unauthorized | Wrong PAT, expired, or missing `Bearer ` |
| SSL / certificate hostname error | Use hyphens in account URL |
| Tools list empty | Role lacks `USAGE` on MCP server / tools |
| SQL works in Snowsight, fails in MCP | Role restriction on PAT too narrow; grant SELECT |
| Automation: “Snowflake not attached” | Enable Snowflake on that automation + Cloud PAT/auth |
| Works in chat, fails in Cloud | Cloud doesn’t see local mcp.json — configure Cloud/Automation secrets |

---

## Checklist for Pricing KPIs

- [ ] Least-privilege role can SELECT Pricing tables  
- [ ] Network policy allows PAT use  
- [ ] PAT created with role restriction + expiry  
- [ ] MCP URL known (or Snowflake plugin fields filled)  
- [ ] Cursor MCP shows Snowflake tools  
- [ ] Local test query works  
- [ ] Cloud Automation has Snowflake + PAT/auth  
- [ ] Manual automation run returns rollup KPIs  
- [ ] Pulsar webhook posts the digest  

---

## What to send back (no secrets)

When done, reply with only:

1. “Local Snowflake MCP: OK / not OK”  
2. “Cloud Automation Snowflake: attached / not attached”  
3. Whether a manual automation run posted **real KPIs** via Pulsar  

Do **not** paste the PAT or webhook URL.
