---
description: Rebuild the daily Radar dashboard at ~/Documents/Radar/today.html with fresh data from Calendar, Slack, Gmail, and optionally Notion. Tracks commitment carryover.
---

You are rebuilding the Radar dashboard.

## Architecture

- **Display**: `~/Documents/Radar/today.html` — permanent static file, never rewritten. Loads `state/data.js` at startup and renders from `window.RADAR_DATA`.
- **Data**: `~/Documents/Radar/state/data.js` — overwrite each run. Contains `window.RADAR_DATA = { ... }`.
- **State**:
  - `~/Documents/Radar/state/commitments.json` — **source of truth** for commitments (not a cache). Added/edited via `/radar-commit` and the dashboard checkboxes. `/radar` bumps carryover counters and marks completions, but never creates new commitments.
  - `~/Documents/Radar/state/focus.json` — manually-added focus tasks (read, do not modify).
  - `~/Documents/Radar/state/slack_flagged.json` — bridge between dashboard checkbox keys for `sl-flagged-*` items and Slack message coordinates `{channel_id, ts, emoji, permalink}`. Rewritten each `/radar` run from the fresh flagged-search results. Used by Step 4 to remove reactions when the user checks off a flagged item.
  - `~/Documents/Radar/state/history/YYYY-MM-DD.json` — write a snapshot of today's commitments + dashboard summary at end of run.
- **Config**: `~/Documents/Radar/state/config.json` — per-user identity, Notion settings, Gmail filters. Loaded in Step 0.

## Step-by-step

### 0. Load config

Read `~/Documents/Radar/state/config.json`. If missing, abort with:
> Config missing. Run `/radar-setup` in Claude Code, or copy `state/config.example.json` to `state/config.json` and edit.

Bind into local vars for the rest of the run:
- `identity = config.identity` — `{name, role, company}`. Use the name in the closing report.
- `notion_enabled = config.notion.enabled` — boolean. If false, skip all Notion calls entirely.
- `notion_extra_pages = config.notion.extra_pages || []` — array of `{label, url}` pages to fetch for surfacing meeting context.
- `meeting_notes_enabled = config.notion.meeting_notes_enabled` — boolean (independent of `notion_enabled`; meeting notes only fire if both are true).
- `meeting_notes_window_days = config.notion.meeting_notes_window_days || 7`.
- `gmail_exclude_senders = config.gmail.exclude_senders || []` — substrings to filter out of Gmail results.
- `slack_flagged_emoji = config.slack?.flagged_emoji || null` — when set (e.g. `"eyes"`), `/radar` runs an extra Slack search to surface messages the user reacted to with that emoji, regardless of age. Treat as the user's persistent "deal-with-this" queue.

### 1. Get the date
Use the current date from the conversation context. Format the header as e.g. "Thursday, April 23, 2026". Compute ISO date `2026-04-23` for the storage key. Compute "tomorrow" date — skip weekends (Friday → Monday).

### 2. Read state files (in parallel)
- `~/Documents/Radar/state/commitments.json` — **source of truth**. Shape: `[{ id, title, first_seen, last_seen, days_carried, status, priority, due_date, notion_url, added_at, ... }]`. If missing, treat as `[]`.
- `~/Documents/Radar/state/focus.json`
- `~/Documents/Radar/state/checked.json` — dashboard-synced checkbox state (written by today.html when the user checks items in the UI). Shape: `{ version, date, updated_at, keys: ["commit-...", "sl-...", ...] }`. If the file is missing or stale (date != today), treat as empty.
- `~/Documents/Radar/state/slack_flagged.json` — prior-run map of `sl-flagged-*` data-keys to Slack message coordinates. Shape: `{ <data-key>: { channel_id, ts, emoji, permalink, captured_at } }`. Used by Step 4 to remove reactions for checked-off items. If missing, treat as `{}`.
- `~/Documents/Radar/state/history/` listing — find the most recent prior snapshot (yesterday's, or last weekday's)

If state files don't exist or are corrupted, treat as empty and continue.

### 3. Pull external data (parallel where possible)

Tools are deferred MCP tools — load via ToolSearch as needed.

**Google Calendar** — list today's events.
- Tool: `mcp__google-calendar__list_events` (search ToolSearch: "select:mcp__google-calendar__list_events")
- For each: time, title, attendees, response status (confirmed/tentative/declined), `htmlLink`.

**Slack** — search mentions/DMs needing reply (last 24h), plus the user's persistent flagged queue.
- Tool: `mcp__slack__slack_search_public_and_private` (or `slack_search_users`).
- **Time-window search**: mentions and DMs from the last 24h. Capture `permalink`. Filter out automated digests (Google Calendar daily digest, etc.).
- **Flagged search** — only if `slack_flagged_emoji` is set. Run a second query `hasmy::EMOJI:` (no time filter) to fetch every message the user has reacted to with that emoji. These are the user's persistent triage queue — they stay until the user removes the reaction.
  - Dedupe by `permalink` against the time-window results to avoid duplicates.
  - Tag flagged items so Step 5 can render them with the `🚩` priority marker and sort them to the top of the Slack section.
  - For each flagged result, capture `channel_id` and message `ts` from the search result so the dashboard checkbox can later trigger reaction removal (see Step 4 reaction-removal flow).
  - If the search returns 0 results, that's fine — no separate "no flagged items" empty state needed.

**Gmail** — threads requiring action (last 24h).
- Tool: `mcp__gmail__search_threads`
- For each thread: build link `https://mail.google.com/mail/u/0/#inbox/THREAD_ID` from `id`.
- Drop any thread whose sender or subject contains a substring from `gmail_exclude_senders` (config-driven).

**Notion** — only if `notion_enabled`. Fetch in parallel:
1. For each entry in `notion_extra_pages`: `mcp__notion__notion-fetch` the page. Extract any action items / decisions / status relevant to your commitments. These do NOT become new commitments automatically — they surface as meeting context (see below) and in the "From recent Notion pages" panel.
2. If `meeting_notes_enabled`: call `mcp__notion__notion-query-meeting-notes` for the last `meeting_notes_window_days` days. From the notes, extract:
   - **Decisions made** — surface in `autoFocusChipsHtml` as 🟣 chips when relevant to an open commitment
   - **Suggested action items** — render in a separate `meetingNotesItemsHtml` section with an "Add to commitments?" CTA (see Step 5). Never write to `commitments.json` automatically — the human runs `/radar-commit` if they want them tracked.
   - **Meeting context for open commitments** — for each open commitment in `commitments.json`, check if its title/id was discussed; if yes, add a `data-meeting-context` attribute with a short tooltip (e.g. "Last discussed Apr 22 · decided to push to next sprint")

If any source fails (auth expired, etc.), continue with the others and put a small note in that section's empty state. Don't abort the whole run.

### 4. Compute commitment carryover and process dashboard checks

`commitments.json` is the source of truth. Reconcile it with today's date and dashboard-synced completions:

- For each open commitment in `commitments.json` (`status == "open"`):
  - If `last_seen != today`: bump `days_carried`, set `last_seen = today`. Preserve `first_seen`.
  - If `last_seen == today`: leave counters alone (re-run within the same day).
- **Dashboard-synced completions**: for each `commit-*` id in `checked.json.keys` (when `checked.json.date == today`), mark that commitment `status = "completed"`, `completed_at = today`. Exclude it from `commitmentItemsHtml` and from `commitmentsCount`. Include it in `commitments_completed_today` in the history snapshot.
- **Cleanup**: commitments with `status == "completed"` and `completed_at < today` are dropped from the file (one-day grace already elapsed).
- **/radar never creates commitments.** New commitments come from `/radar-commit` only.

**Slack flagged-message reaction removal** — when the user checks a `sl-flagged-*` item on the dashboard, the next `/radar` run removes the trigger reaction from the original Slack message so it falls out of the flagged queue permanently. Flow:

1. Before this step, load `~/Documents/Radar/state/slack_flagged.json` if it exists. Shape: `{ <data-key>: { channel_id, ts, emoji, permalink, captured_at } }`. This file is the bridge between dashboard checkbox keys and Slack message coordinates.
2. From `checked.json.keys` (when `checked.json.date == today`), pick every key matching `sl-flagged-*`.
3. For each such key, look up its entry in `slack_flagged.json`. If found:
   - Load `mcp__slack__slack_remove_reaction` via ToolSearch (`select:` form — search for "slack remove_reaction" or similar) and call it with `channel = entry.channel_id`, `name = entry.emoji`, `timestamp = entry.ts`.
   - On success: delete the entry from `slack_flagged.json` and add the key to the run report's "Flagged reactions removed" list.
   - On error (already removed, not found, auth): log the error in the run report but don't abort the rest of the run.
4. After Step 3 in the data-pull phase produces the fresh flagged-search results, **rewrite** `slack_flagged.json` to reflect today's flagged set: `{ <data-key>: { channel_id, ts, emoji, permalink, captured_at: today } }` for every flagged item still present (skipping the ones just removed). Use the same `data-key` convention as Step 5 (`sl-flagged-{slug}` derived from `permalink` or `channel_id + ts` — keep it stable across runs).
5. The reaction-removal write is a "soft" 2-way action: the dashboard checkbox is the user's explicit consent, so no extra confirmation prompt is needed. But include a one-line summary in the closing report (Step 7): "Removed :{emoji}: reaction from N Slack messages." If N is 0, omit the line.

Use these badges in the rendered HTML (next to the title):
- `days_carried <= 1`: no badge
- `days_carried == 2 or 3`: `<span class="carryover-badge">🔁 {n}d carried</span>`
- `days_carried == 4 or 5`: `<span class="carryover-badge warm">🔁 {n}d carried</span>`
- `days_carried >= 6`: `<span class="carryover-badge hot">🔁 {n}d carried</span>`
- `first_seen == today`: `<span class="new-badge">NEW</span>`

### 5. Build data and write state/data.js

Build the `window.RADAR_DATA` object with all dynamic content. Write it to `~/Documents/Radar/state/data.js`.

**Format:**
```js
window.RADAR_DATA = {
  headerDate: "Thursday, April 23, 2026",
  headerMeta: "Refreshed today at HH:MM",
  isoDate: "2026-04-23",
  autoFocusChipsHtml: "...",
  calendarCount: N,
  calendarEventsHtml: "...",
  commitmentsCount: N,
  commitmentItemsHtml: "...",
  meetingNotesItemsHtml: "...",
  slackBadge: "...",
  slackItemsHtml: "...",
  gmailCount: N,
  gmailItemsHtml: "...",
  tomorrowDate: "Friday, April 24",
  tomorrowBadge: "...",
  tomorrowItemsHtml: "..."
};
```

**Field details:**

- `headerDate` → e.g. "Thursday, April 23, 2026"
- `headerMeta` → "Refreshed today at HH:MM" (use current time)
- `isoDate` → "2026-04-23"
- `autoFocusChipsHtml` → 3-4 auto-prioritized chips only (user focus chips are rendered by the page's own JS from focus.json — do NOT include them here). Add 🔴 urgent (commitments due today, prep needed for upcoming meeting), 🟠 warning (multi-day carryovers, structural decisions). Also surface 🟣 chips for anything flagged as urgent/blocked in the AI meeting notes from the window (e.g. "🟣 Discussed in sync: X is blocked"). Each must `scrollToItem(...)` an existing element id. Example: `<span class="focus-chip urgent" onclick="scrollToItem('commit-patient-access')">🔴 Patient access due today</span>`.
- `calendarCount` → number of today's events
- `calendarEventsHtml` → for each event, render:
  ```html
  <div class="event [past|tentative|declined|personal|async]" data-time="HH:MM" id="event-{slug}">
    <div class="event-time">HH:MM</div>
    <div class="event-bar"></div>
    <div class="event-body">
      <div class="event-title">{title}</div>
      <div class="event-sub">{context, attendees, duration}</div>
    </div>
    <div class="event-actions">
      [if joinUrl:] <a href="{joinUrl}" target="_blank" class="event-join" title="Join {provider}">Join</a>
      <a href="{htmlLink}" target="_blank" class="event-link" title="Open in Calendar">↗</a>
    </div>
  </div>
  ```
  Add `past` class to events whose end time is before now. Use `personal` for non-work events, `async` for `[Async]`-prefixed events, `declined` if the user declined or majority declined, `tentative` for tentative responses.

  **Extracting `joinUrl`** (in priority order — pick the first match):
  1. `event.hangoutLink` (Google Meet) — if present
  2. `event.conferenceData.entryPoints[]` where `entryPointType == "video"` — use `uri`
  3. `event.location` if it matches any of: `meet.google.com`, `zoom.us/j/`, `zoom.us/my/`, `teams.microsoft.com/l/meetup-join`, `teams.live.com/meet`, `webex.com/meet/`, `goldcast.io`, `hopin.com`, `whereby.com`
  4. First URL in `event.description` matching the same patterns as (3)

  Skip the Join button for `personal` events and for events whose only link is a Lattice / Notion / doc URL (not a video conference). Derive `provider` label from the URL host for the tooltip (e.g. "Zoom", "Google Meet", "Goldcast", "Teams").

  If empty: use `<div class="empty">No events today.</div>`

- `commitmentsCount` → number of open commitments
- `commitmentItemsHtml` → for each open commitment:
  ```html
  <div class="commit-item [due-today]" id="commit-{slug}">
    <div class="item-check"><input type="checkbox" data-key="commit-{slug}" onchange="handleCheck(this)"></div>
    <div class="item-body">
      <div class="item-title">{title}{carryover/new badge if applicable}</div>
      <div class="item-sub">{priority emoji} {due context} · {description}</div>
    </div>
    [if commitment.notion_url:] <a href="{notion_url}" target="_blank" class="item-source-link" title="Open in Notion">↗</a>
  </div>
  ```
  The `↗` link is only rendered if the commitment has a `notion_url` field. Commitments added via `/radar-commit` without `--notion <url>` have no link.

  If empty: `<div class="empty">No open commitments. Add one with <code>/radar-commit "your task"</code>.</div>`

- `meetingNotesItemsHtml` → only populated if Notion + meeting notes are enabled and there are suggested action items from the window. For each suggestion:
  ```html
  <div class="meeting-note-item">
    <div class="item-body">
      <div class="item-title">{action item text}</div>
      <div class="item-sub">From {meeting title} · {date}</div>
    </div>
    <button class="item-add-cta" onclick="copyCommitCommand('{action item text}')" title="Copy /radar-commit command">+ Track</button>
  </div>
  ```
  If empty or Notion is disabled: `<div class="empty">No suggestions from recent meeting notes.</div>` (or omit the section entirely from the template if you remove the panel).

- `slackBadge` → e.g. "0 urgent" or "{n} pending". If any items are flagged, prefix with "🚩 {n} flagged · " (e.g. "🚩 2 flagged · 3 pending").
- `slackItemsHtml` → for each Slack item:
  ```html
  <div class="item [flagged]">
    <div class="item-priority">🚩|🔴|🟡|·</div>
    <div class="item-check"><input type="checkbox" data-key="sl-{slug}|sl-flagged-{slug}" onchange="handleCheck(this)"></div>
    <div class="item-body">
      <div class="item-title">{summary of message}</div>
      <div class="item-sub">{from, channel, when}{ · :EMOJI: flagged if applicable}</div>
    </div>
    <a href="{permalink}" target="_blank" class="item-source-link" title="Open in Slack">↗</a>
  </div>
  ```
  **Data-key convention**:
  - Non-flagged items: `sl-{slug}` where `{slug}` is derived from message text (first few words slugified).
  - Flagged items: `sl-flagged-{slug}` where `{slug}` is a stable hash of `{channel_id}:{ts}` (e.g. first 12 chars of SHA-1 of `channel_id + ":" + ts`). Stability across runs matters — the same Slack message must produce the same key so reaction removal can find it in `slack_flagged.json`.

  After rendering, write `state/slack_flagged.json` with `{ "sl-flagged-{slug}": { channel_id, ts, emoji, permalink, captured_at: today } }` for every flagged item rendered this run. This is the lookup table for Step 4's reaction removal on the next run.

  Sort order: flagged items first (priority 🚩), then by urgency (🔴 → 🟡 → ·) within each group. Add the `flagged` class to flagged items so styling can lift them visually. Mention `:{emoji}: flagged` in the sub-line so the user knows why the item is surfacing.

  If empty: `<div class="empty">No Slack DMs, mentions, or flagged messages.</div>`

- `gmailCount` → number of action items
- `gmailItemsHtml` → same pattern as Slack, with Gmail thread links. If empty: `<div class="empty">No Gmail threads needing action.</div>`
- `tomorrowDate` → e.g. "Friday, April 24"
- `tomorrowBadge` → e.g. "Deep work" (Fri), "5 meetings" otherwise
- `tomorrowItemsHtml` → list of tomorrow's recurring meetings + carryover hint. Recurring schedule (edit this list in your fork to match your own week):
  - Mon: Weekly Product Marketing Connect (9am)
  - Tue: Quentin↔Kourosh 1:1, Site Weekly GTM, Quentin/Anatole Weekly
  - Wed: 3 scope reviews (CPD/Hugo, Win Trials/Romain, P&E/Charles), Bastien sync, Roadmap alignment
  - Thu: 1:1 Hugo (11am), 1:1 Charles, Expand Globally workstream, Sanofi Steering Committee
  - Fri: No recurring — deep work day

**Escaping for JS string:** When building HTML strings for the data.js file, the entire value is a JS string literal. Escape backslashes and any backticks if using template literals, or use single-quoted JS strings with escaped single quotes. Prefer double-quoted JS strings for the outer object, with inner HTML using single-quoted attributes.

### 6. Write output and update state

**MANDATORY: every run MUST write `~/Documents/Radar/state/data.js` AND update `~/Documents/Radar/state/commitments.json`.** No early exit, no skipping. If sources failed, still write data.js (with empty-state HTML for affected sections) and still update commitments.json (preserve prior state for the failed source rather than dropping items). Treat a run that does not produce both files as a failed run.

In a single batch:
- Write `~/Documents/Radar/state/data.js` with the `window.RADAR_DATA` object. **Required, every run.**
- Update `~/Documents/Radar/state/commitments.json` with the reconciled state from step 4. **Required, every run.** Use either `Write` (full overwrite — appropriate when you have full reconciled state) or `Edit` (surgical change — appropriate when you only need to bump `last_seen` / `days_carried` / `status` on existing entries and want to avoid clobbering fields you didn't read). Both are permitted via `Edit(...state/*)` / `Write(...state/*)`.
- Write `~/Documents/Radar/state/slack_flagged.json` with the lookup map for this run's flagged items (`{ "sl-flagged-{slug}": {channel_id, ts, emoji, permalink, captured_at} }`). Required whenever `slack_flagged_emoji` is set, even if the map is empty — write `{}` so the next run reads a fresh state. Skip the write entirely when `slack_flagged_emoji` is null.
- Write today's snapshot to `~/Documents/Radar/state/history/{ISO_DATE}.json` containing: `{date, commitments_open: N, commitments_completed_today: [ids], gmail_count, slack_count, calendar_count, focus_chips: [titles], flagged_reactions_removed: [data_keys]}`.

Do NOT write to `~/Documents/Radar/today.html` — it is a permanent static file.
Do NOT write to `~/Documents/Radar/state/checked.json` — it is owned by the dashboard (today.html writes it via File System Access API when the user ticks checkboxes). /radar only reads it.

### 7. Report back to user (concise)

One paragraph: what got refreshed, count of carried-over commitments (with the longest-carrying one called out), any source that failed. Mention if any commitments hit "hot" (6+ days). If meeting notes surfaced action-item suggestions, mention the count and remind them to use `/radar-commit` to track any. Don't include the HTML in your response — they open it in the browser.

## Important

- **data.js write is non-negotiable**: every /radar invocation must end with a fresh `state/data.js`. If you didn't write it, the run failed — even if all sources succeeded. Partial-data runs still write; missing sections use the empty-state HTML.
- **commitments.json update is non-negotiable**: every /radar invocation must also leave `state/commitments.json` reflecting today's reconciled state (carryover counters bumped, completions marked). Edit or Write — both are permitted.
- **/radar never creates commitments**: it only bumps counters, marks completions, and renders. New commitments are added via `/radar-commit` (and only that path). Meeting-note suggestions surface in a separate section with a CTA — they are not auto-added.
- **Slug stability**: ids like `commit-patient-access` must be derived from the commitment content, not the position. Slugify the title → first 4-5 meaningful words. This keeps state continuity across runs.
- **today.html is immutable**: never write to it. Data goes in `state/data.js` only.
- **All MCP tools are deferred** — use ToolSearch with `select:` to load schemas before calling.
- If a field has no data available, use the empty-state HTML pattern (see above) rather than an empty string.
