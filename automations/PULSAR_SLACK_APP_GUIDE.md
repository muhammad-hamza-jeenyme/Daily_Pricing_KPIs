# Create Slack app: Pulsar (Pricing KPI alerts)

Bot display name: **Pulsar** (matches logo; not “Puslar”).  
Avatar file: `automations/pulsar-bot-avatar.png`  
Target channel: `C0BMWLMR03T` only.

This guide creates a **custom Slack app** so messages appear as **Pulsar**, not “Cursor AGENT”. Cursor Cloud Automation can keep running the analysis; Pulsar posts via **Incoming Webhook** or **Bot Token** (recommended long-term).

---

## 0. Prerequisites

- Slack workspace admin (or permission to create/install apps)
- Access to [https://api.slack.com/apps](https://api.slack.com/apps)
- The avatar PNG ready (`pulsar-bot-avatar.png`)
- Channel `C0BMWLMR03T` exists and you can invite bots into it

---

## 1. Create the Slack app

1. Open [https://api.slack.com/apps](https://api.slack.com/apps) → **Create New App**.
2. Choose **From scratch**.
3. **App Name:** `Pulsar`
4. Pick your Jeeny workspace → **Create App**.

---

## 2. Branding (name + profile picture)

### 2.1 Display name

1. Left sidebar → **Basic Information**.
2. Under **Display Information**:
   - **App name:** `Pulsar`
   - **Short description:** e.g. `Daily Pricing fare-integrity alerts for major cities`
   - **Background color:** dark blue close to the logo border (e.g. `#0B1F3A`)
3. **App icon / profile:** upload `automations/pulsar-bot-avatar.png`
   - Prefer **square** crop; Slack rounds it in the UI.
   - Min recommended: **512×512** (upscale if needed; your circular art is fine).
   - Animated: use a **GIF** if you want motion later; PNG is fine for v1.
4. Click **Save Changes**.

### 2.2 Bot user name (what shows in channels)

1. Left sidebar → **App Home** (or **Bot User** under Features).
2. Ensure **Always Show My Bot as Online** is optional (your choice).
3. **Default username** / bot display: set to `Pulsar` (Slack may append a number if taken, e.g. `pulsar`).
4. Save.

> In-channel appearance = App display name + icon from Display Information, plus the bot user.

---

## 3. Permissions (OAuth scopes)

1. Left sidebar → **OAuth & Permissions**.
2. Under **Bot Token Scopes**, add:

| Scope | Why |
|-------|-----|
| `chat:write` | Post messages as Pulsar |
| `chat:write.public` | Post to public channels without joining (optional; still invite is cleaner) |
| `canvases:read` | Read Pricing Alerts canvas before update |
| `canvases:write` | **Required** to update canvas `F0BN0E7RJ31` daily |
| `files:read` | Often needed with canvas APIs |
| `channels:read` | Resolve channel metadata (optional) |

**Channel message:** Incoming Webhook is enough.  
**Canvas update:** requires Bot Token (`xoxb-…`) with `canvases:read` + `canvases:write`. Webhook alone → `Canvas update failed (bot token missing)`.

## Fix: `Canvas update failed (missing_scope)`

This means `PULSAR_SLACK_BOT_TOKEN` exists, but the token was issued **without** canvas scopes (or Cloud still has the **old** token).

### Do these in order

1. Open [api.slack.com/apps](https://api.slack.com/apps) → **Pulsar**.
2. **OAuth & Permissions** → **Bot Token Scopes** → add if missing:
   - `canvases:read`
   - `canvases:write`
3. Click **Reinstall to Workspace** (required — adding scopes does nothing until reinstall).
4. Copy the **new** Bot User OAuth Token (`xoxb-…`).
5. Cursor Cloud → **My Secrets** → edit `PULSAR_SLACK_BOT_TOKEN` → paste the **new** token → Save.
6. In Slack, open canvas [Pricing Alerts](https://easytaxime.slack.com/docs/T33U3F6CW/F0BN0E7RJ31) → share/access → give **Pulsar** **can edit** (write), not view-only.
7. Re-run the **existing** Pricing KPI Alerts automation.

### Quick local check (optional)

After updating the secret locally in a temp env var (do not commit):

```powershell
$token = "xoxb-YOUR-NEW-TOKEN"
# Should return ok:true and list scopes including canvases:write
Invoke-RestMethod -Uri "https://slack.com/api/auth.test" -Headers @{ Authorization = "Bearer $token" }
```

If `auth.test` works but canvas still fails, the token is valid but Pulsar still needs **edit** access on canvas `F0BN0E7RJ31`.

---

## 4. Install the app to the workspace

1. Still on **OAuth & Permissions** → **Install to Workspace** → **Allow**.
2. Copy and store securely:
   - **Bot User OAuth Token** (`xoxb-…`) — keep in a password manager / secrets store; **never commit to GitHub**.
3. If you rotate tokens later: **OAuth & Permissions** → reinstall / regenerate.

---

## 5. Add Pulsar to the alert channel only

1. In Slack, open channel `C0BMWLMR03T`.
2. Channel details → **Integrations** → **Add apps** → add **Pulsar**.
   - Or type: `/invite @Pulsar`
3. Confirm Pulsar is **only** in this channel (do not invite to other channels).

---

## 6. Choose how Pulsar sends messages

### Option A — Incoming Webhook (simplest for daily digest)

1. Left sidebar → **Incoming Webhooks** → **Activate Incoming Webhooks** = On.
2. **Add New Webhook to Workspace**.
3. Select channel **`C0BMWLMR03T`** only → Allow.
4. Copy the **Webhook URL** (`https://hooks.slack.com/services/...`).
5. Store as a secret (e.g. `PULSAR_SLACK_WEBHOOK_URL`). Never commit it.

**Post test (PowerShell):**

```powershell
$uri = $env:PULSAR_SLACK_WEBHOOK_URL
$body = @{ text = "Pulsar online — Pricing fare-integrity channel check." } | ConvertTo-Json
Invoke-RestMethod -Uri $uri -Method Post -ContentType "application/json" -Body $body
```

Webhook posts **only** to the channel you selected at creation — good channel lock.

### Option B — Bot token + Web API `chat.postMessage` (more control)

1. Use Bot Token `xoxb-…`.
2. POST to `https://slack.com/api/chat.postMessage` with:
   - `channel`: `C0BMWLMR03T`
   - `text` or Block Kit `blocks`
3. Hard-code / secret-config **only** that channel ID in your runner so it cannot post elsewhere.

---

## 7. Message format (recommended)

Keep posts short. Suggested structure:

1. **Header:** `Pulsar · Pricing fare-integrity · {report_date}`
2. **Major shifts** (only KPIs where yesterday > prior 7d avg), each line: `Area_Code · KPI · yesterday vs 7d avg · DoD/WoW/MoM`
3. **City snapshot table** (8 cities): rides, `% increase_pricing`, `% withinB`, key deltas
4. Optional: link to a Canvas **in the same channel**

Avoid long “blocked / setup / fix needed” essays. If Snowflake fails, one short failure line only.

---

## 8. Wire to Cursor Cloud Automation (two patterns)

### Pattern 1 — Cursor posts as Cursor (current)

Automation keeps using Cursor’s Slack action → still shows as **Cursor AGENT**. Branding stays Cursor’s.

### Pattern 2 — Cursor analyzes; Pulsar posts (recommended for your brand)

1. Cloud Agent runs `sql/fare_integrity_slack_rollup.sql` via Snowflake.
2. Agent formats the digest text.
3. Agent (or a tiny script) POSTs to **Pulsar Incoming Webhook** or `chat.postMessage` with Pulsar bot token.
4. Secrets: store webhook/token in Cursor Cloud secrets / env — **not** in the public repo.

Until webhook/token is available to the Cloud Agent, you can:
- Run the rollup in chat and post a test via webhook from your machine, or
- Add the webhook URL as a Cloud Agent secret once Cursor supports it for that automation.

---

## 9. Security checklist

- [ ] No `xoxb-` / webhook URL in git
- [ ] Webhook bound only to `C0BMWLMR03T`
- [ ] Bot invited only to that channel
- [ ] Rotate token if leaked
- [ ] Repo stays public-safe (SQL + docs only)

---

## 10. Verification checklist

- [ ] App name / icon show as **Pulsar** in channel
- [ ] Test message appears from Pulsar in `C0BMWLMR03T` only
- [ ] No posts in other channels
- [ ] Re-run after Snowflake is attached to automation → real KPI numbers
- [ ] Major-shift rule = yesterday > **prior 7-day** average (not 14)

---

## 11. Optional later upgrades

| Upgrade | Notes |
|---------|--------|
| Animated avatar | Export logo as looping **GIF**, re-upload under Display Information |
| Block Kit | Richer tables/buttons via `chat.postMessage` |
| Bolt app | Full Slack app (events, slash commands) — only if you need interactivity |
| Slash command | e.g. `/pulsar digest` for on-demand runs |

---

## Quick reference

| Item | Value |
|------|--------|
| App / bot name | Pulsar |
| Avatar | `automations/pulsar-bot-avatar.png` |
| Channel | `C0BMWLMR03T` |
| Create apps | https://api.slack.com/apps |
| Rollup SQL | `sql/fare_integrity_slack_rollup.sql` |
| Alert rules | `docs/alert-rules.md` |

When the app is created and you have either the **webhook URL** or **bot token**, share that you’re ready (do **not** paste secrets in chat if the repo is shared — say “webhook ready” and we can wire the Cloud Agent / a small poster script next).
