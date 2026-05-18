# Onboarding: set up your own Radar

This guide takes you from `git clone` to a working dashboard in about 10 minutes.

## What you'll get

A static HTML dashboard at `~/Documents/Radar/today.html` that Claude Code rebuilds for you each morning. Sections: today's calendar with one-click join links, your open commitments with carryover counters ("3 days carried" badges so slipping items rise), Slack DMs and mentions needing reply, Gmail threads needing action, focus chips for the day, and a "tomorrow" preview. You drive it with four slash commands inside Claude Code.

## Prerequisites

- **Claude Code** installed. The CLI or the desktop app — either works.
- **MCP connectors** authenticated for the data sources you want:
  - **Required**: Google Calendar, Slack, Gmail. Without these the dashboard has no input data.
  - **Optional**: Notion. Only needed if you want recent meeting notes and tracked-page context.
- A shell with `bash`, `git`, and `ln -s` (any macOS or Linux terminal — Windows users use WSL).

You don't need: any database, a Notion accountability tracker, a deployed server, or any third-party hosting. Everything lives in `~/Documents/Radar/`.

## 1. Clone

Clone to **`~/Documents/Radar/`**. The path is fixed — the skills use absolute `~/Documents/Radar/` paths internally. If you want a different location, you'll need to find/replace those references in `skills/*.md` after cloning.

```sh
git clone <REPO_URL> ~/Documents/Radar
cd ~/Documents/Radar
```

## 2. Install the slash commands

```sh
./scripts/install.sh
```

This symlinks the four skill files (`radar.md`, `radar-focus.md`, `radar-act.md`, `radar-commit.md`) into `~/.claude/commands/` and the scheduled task into `~/.claude/scheduled-tasks/`. Future `git pull`s are picked up automatically — the install is a one-time step.

If the installer reports `SKIP` for any path, you already have a file with that name in `~/.claude/`. Back it up, remove it, and re-run.

## 3. Configure

```sh
cp state/config.example.json state/config.json
$EDITOR state/config.json
```

Required fields:
- `identity.name`, `identity.role`, `identity.company` — used to shape voice in `/radar-act` drafts.
- `gmail.exclude_senders` — list of substrings (sender or subject) to skip. Start with `["noreply", "newsletter", "digest"]`, add more as you see automated mail clutter your dashboard.

Optional:
- `notion.enabled: true` — turn on if you want the Notion sections. If false, `/radar` makes zero Notion calls.
- `notion.extra_pages` — array of `{label, url}` for any Notion pages you want fetched for meeting-context cross-referencing.
- `notion.meeting_notes_enabled: true` — surfaces suggested action items from your recent AI meeting notes in a side panel with an "Add to commitments" CTA.
- `notion.meeting_notes_window_days` — defaults to 7.
- `slack.flagged_emoji` — a Slack emoji name (no colons, e.g. `"eyes"` or `"bookmark"`). When set, `/radar` runs an extra Slack search for every message you've reacted to with that emoji and surfaces them with a 🚩 marker at the top of the Slack section. Acts as a persistent triage queue — messages stay until you remove the reaction (or check them off in the dashboard, see below). Pick an emoji you don't already use socially.
  - **Check-off behavior**: when you tick the checkbox on a flagged Slack item in the dashboard, the next `/radar` run removes the trigger reaction from the original message in Slack. The message drops out of the flagged queue and won't come back until you re-react. The closing report lists how many reactions were removed.

## 4. Create your empty state files

```sh
cp state/commitments.example.json state/commitments.json
```

`commitments.json` starts as `[]`. You'll fill it with `/radar-commit` over time.

## 5. First run

In Claude Code (from any directory):

```
/radar
```

The first run will:
- Authenticate the MCPs if you haven't yet (Claude Code will prompt for each).
- Write `~/Documents/Radar/state/data.js`.
- Write the daily history snapshot.

Open `~/Documents/Radar/today.html` in your browser. Calendar, Slack, Gmail sections render with today's data. Commitments is empty — that's expected on day one.

## 6. Add your first commitment

```
/radar-commit "Finish Q2 planning doc" --due 2026-05-20 --priority urgent
```

Re-run `/radar` (or accept the prompt at the end of `/radar-commit`). The commitment shows up with a `NEW` badge. Tomorrow it'll show no badge; the day after, `🔁 2d carried`; and so on. Carryover gets warmer as days pile up.

## 7. Daily routine

Three slash commands carry most of the work:

- **`/radar`** — rebuild. Run once in the morning (or let the scheduled task do it for you, see step 8). Re-run any time data feels stale.
- **`/radar-commit "..."`** — add a commitment.
- **`/radar-focus "..."`** — add a one-day focus task (separate from commitments — these are "do this today, then it's gone unless you re-add").
- **`/radar-act`** — interactive. Picks the top open item and either drafts a Slack/Gmail reply (always as a draft, never auto-sent) or runs a deep-work session on a commitment.

In the dashboard, press `N` to add a focus task without leaving the browser.

## 8. Optional: schedule the daily rebuild

The repo ships a scheduled task at `scheduled-tasks/radar-daily-rebuild/SKILL.md` that runs `/radar` at 8am every weekday. To register it, in Claude Code:

```
Register a scheduled task that runs /radar at 8am Mon–Fri using radar-daily-rebuild.
```

Claude will use the `mcp__scheduled-tasks__create_scheduled_task` tool. Verify with `mcp__scheduled-tasks__list_scheduled_tasks`.

## 9. Customize

- **Change the dashboard look**: edit `template.html`. CSS variables for colors and spacing are at the top of the `<style>` block. Then re-run `/radar` (or just refresh — the template loads `state/data.js` at startup).
- **Change the keyboard shortcut for adding focus tasks**: search `template.html` for `keydown` — the `N` key handler is right there.
- **Change the "tomorrow" preview's recurring schedule**: edit lines ~168–173 of `skills/radar.md`. Currently shipped with the maintainer's recurring meetings — replace with yours.
- **Change Gmail filtering rules** beyond the sender list: edit `skills/radar.md` Step 3, "Gmail" section.

## 10. Update

```sh
cd ~/Documents/Radar
git pull
./scripts/install.sh   # idempotent — re-runs cleanly
```

Your `state/` is gitignored, so updates never overwrite your commitments or focus tasks.

## Troubleshooting

- **`/radar` aborts with "Config missing"** → you skipped step 3. Copy `state/config.example.json` to `state/config.json`.
- **Commitments section says "No open commitments"** even though you ran `/radar-commit`** → check `state/commitments.json` exists and is valid JSON; re-run `/radar`.
- **Calendar / Slack / Gmail section is empty with no error** → the MCP probably failed silently. Open Claude Code, run `/radar`, and read the closing summary — failed sources are called out.
- **`today.html` is blank** → `state/data.js` is missing or malformed. Re-run `/radar`; if it still fails, check the closing summary for write errors.
- **Wrong identity in drafted replies** → `state/config.json` has the wrong `identity.role` (e.g. set to "Engineer" instead of "VP Product"). Edit and re-run.

## Removing Radar

```sh
./scripts/uninstall.sh   # (not included — manual cleanup)
# or:
rm ~/.claude/commands/radar*.md
rm -r ~/.claude/scheduled-tasks/radar-daily-rebuild
# Unregister the 8am scheduled task in Claude Code if you set it up.
# Repo can be deleted from ~/Documents/Radar/ — state lives there too.
```
