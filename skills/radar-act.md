---
description: Interactive — pick the top item from today's Radar and either draft a reply (Slack/Gmail/Notion) or run a deep-work session on a commitment/focus task. Always confirms before any external write.
argument-hint: [optional: item key or natural language hint, e.g. "barnsley dpa", "patient access definition"]
---

The user wants to take action on something from today's Radar. `$ARGUMENTS` is an optional hint pointing to a specific item.

## Step 0 — Load config

Read `~/Documents/Radar/state/config.json`. If missing, abort with: "Config missing. Run `/radar-setup` or copy `state/config.example.json` to `state/config.json`." Bind `identity = config.identity` — `{name, role, company}` — used to shape the voice when drafting replies (Step 3R).

## Step 1 — Find the target item

### 1a. If `$ARGUMENTS` is provided

Search today's dashboard for the matching item:
- Read `~/Documents/Radar/today.html`
- Match against `data-key` attributes (e.g. `gm-barnsley-dpa`, `sl-...`, `commit-...`, `focus-...`) and `.item-title` text.
- If multiple matches, show the user a numbered list and ask which one.

### 1b. If `$ARGUMENTS` is empty — auto-pick

Read all three sources to rank open items:
- `~/Documents/Radar/today.html`
- `~/Documents/Radar/state/focus.json`
- `~/Documents/Radar/state/commitments.json`

Ranking (highest priority first):
1. **Active focus tasks** from `focus.json` where `active: true` and `completed_at: null`, ordered by `added_at` ascending (oldest first — they've been waiting longest).
2. **Open commitments** (`status: "open"`), sorted by `priority` (urgent → warning → info), then `due_date` ascending, then `days_carried` descending (slipping items rise).
3. **Slack/Gmail items** as fallback only if 1 and 2 are empty.

Present the top pick on one line, then up to 4 alternatives, then the prompt — exactly this shape:

```
Top pick: [commit-patient-access] Write & send canonical one-paragraph definition of "patient access" — due today, urgent

Or pick another:
  1. [commit-patient-metric] Decide on patient access metric — due tomorrow
  2. [commit-charles-feedback] Structured feedback for Charles — due tomorrow
  3. [commit-audrey-role] Make structural decision on Audrey's role — due 2026-04-30
  4. [sl-carly-notion-comment] Reply to Carly on Notion comment

Go with top pick? (y / number / describe)
```

`y` → use the top pick. A number → use that item. Free text → re-match per Step 1a.

## Step 2 — Route on item type

Once the target is identified, branch on its `data-key` prefix:

- `gm-*` or `sl-*` → **reply flow** (Step 3R below).
- `commit-*` or `focus-*` → **deep-work flow** (Step 3W below).

---

## Step 3R — Reply flow (Slack / Gmail / Notion replies)

### Pull full context

- **Gmail**: load `mcp__gmail__get_thread` (ToolSearch select). Fetch the full thread by `THREAD_ID` from the link. Read the latest message the user needs to reply to.
- **Slack**: load `mcp__slack__slack_read_thread` or `slack_read_channel`. Fetch the message and any thread replies.

### Draft the action

Draft a response in the user's voice. Use `identity` from config to shape tone — for a senior IC or executive, default to concise, direct, decision-oriented language; short paragraphs, no fluff, no "I hope this finds you well." Show the draft clearly:

```
── DRAFT REPLY ──
To: <recipient>
Re: <subject>

<draft body>
── END ──
```

### Confirm before sending

**ALWAYS ASK** before sending. One line:
> "Send this? (y / edit / cancel)"

- `y` or `yes` → execute via the appropriate MCP tool:
  - Gmail: `mcp__gmail__create_draft` (NOT a direct send — create a draft the user can review and send manually from Gmail). NEVER auto-send emails.
  - Slack: `mcp__slack__slack_send_message_draft` (use the draft variant — same reasoning).
- `edit` → ask what to change, show revised draft, confirm again.
- `cancel` → stop, do nothing.

### Confirm completion

After action executes: one line confirming what was done and where (e.g. "Draft saved in Gmail — review and send from your inbox: [link]").

---

## Step 3W — Deep-work flow (commitments and focus tasks)

### Pull context

- **Commitment** (`commit-*`): load `mcp__notion__notion-fetch` (ToolSearch select). Fetch the page at `notion_url` from `commitments.json` to get the surrounding tracker context.
- **Focus task** (`focus-*`): read the entry from `~/Documents/Radar/state/focus.json`. No external fetch needed.

### Diagnose work mode

Pick the mode from the task's verb/shape and announce it on one line so the user can override:

| Verb pattern | Mode | What Claude does |
|---|---|---|
| Write / Draft / Send / Document | **Co-produce** | Drafts the deliverable in the user's voice; iterates turn-by-turn |
| Decide / Choose / Resolve / Clarify | **Think-partner** | Lays out the decision frame, tradeoffs, devil's advocate; the user writes |
| Update / Restructure / Build | **Decompose** | Breaks into 3–5 concrete subtasks; asks which to tackle first |

State the mode like:
> Mode: co-produce. I'll draft the paragraph; you steer. (Switch with `mode: decide` or `mode: decompose`.)

### Run the session

Multi-turn working session. The user can at any point type:
- `done` → satisfied, go to the completion gate (Step 4).
- `pause` → stop without changing any state. Resumable later via `/radar-act <key>`.
- `cancel` → stop, change nothing.
- `mode: <co-produce|decide|decompose>` → switch modes.

Mode-specific behavior:
- **Co-produce**: produce a first draft right away, then iterate on the user's edits. Keep their voice — short paragraphs, concrete asks, no fluff, no "I hope this finds you well."
- **Think-partner**: lay out the decision frame in 3–5 bullets (options, tradeoffs, what would change the user's mind). Ask one focused question at a time. Don't write the conclusion for them.
- **Decompose**: return 3–5 concrete subtasks with rough effort estimates. Ask which to tackle now; the others stay on the commitment for next session.

## Step 4 — Completion gate (deep-work flow only)

Only when the user types `done`:

1. Show a one-line summary of what was produced or decided.
2. Propose updates and ask. The set of options depends on whether the commitment has a `notion_url`:

   **If `notion_url` is set on the commitment**:
   > Apply both? (y / state-only / cancel)
   - **Local state**: set `status: "done"` and `completed_at: <ISO timestamp with TZ offset>` in `commitments.json`, OR `active: false` and `completed_at: <ISO>` in `focus.json`.
   - **Notion comment**: `mcp__notion__notion-create-comment` on the commitment's `notion_url` with a 1–2 sentence summary of what changed/was decided. (Comment, not page edit — the tracker is shared.)

   **If `notion_url` is null/missing** (default for commitments added via `/radar-commit` without `--notion`):
   > Mark done in commitments.json? (y / cancel)
   - Only the local state update is offered. Skip the Notion step entirely.

3. On `y` → do the offered updates. On `state-only` → JSON file only, skip Notion. On `cancel` → do neither.
4. Confirm with one line: e.g. "Marked done in commitments.json. Run /radar to refresh." Append "Notion comment posted: <link>." only if Notion was updated.

### Optional handoff (co-produced drafts)

If the deep-work session produced a deliverable that needs to be sent elsewhere (e.g. a one-paragraph definition going to a few colleagues), after the completion gate offer:
> Send this to <recipients> via Gmail? (y/n)

If `y`, fall through to Step 3R's Gmail draft path (`mcp__gmail__create_draft`) — never auto-send.

---

## Important

- **Never auto-send emails or Slack messages.** Always create drafts. The "ask first" gate is firm at every external write.
- **User's voice**: short paragraphs, concrete asks, no fluff. Direct but warm. Shape tone using `identity.role` from config (e.g. exec/VP defaults to terser than IC).
- For Notion updates that touch the shared tracker page, default to `notion-create-comment` rather than page edits.
- All MCP tools are deferred — load via ToolSearch with `select:` before calling.
- Don't write to `commitments.json` / `focus.json` until the completion gate is passed. `pause` and `cancel` leave state untouched.
