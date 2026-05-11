---
description: Add a commitment to today's Radar dashboard. Tracked in state/commitments.json with carryover memory — surfaces in the Commitments card and counts toward day progress until checked off.
argument-hint: <commitment description> [--due YYYY-MM-DD] [--priority urgent|warning|info] [--notion <url>]
---

The user wants to add a commitment. The text plus optional flags is in `$ARGUMENTS`.

If `$ARGUMENTS` is empty, ask the user what they want to add (one short prompt) and stop. Otherwise, parse out the flags first, then the leftover text is the title.

## Steps

1. Parse `$ARGUMENTS`:
   - `--due YYYY-MM-DD` → `due_date`
   - `--priority urgent|warning|info` → `priority` (default `info`)
   - `--notion <url>` → `notion_url` (default `null`)
   - Remaining text (trim leading/trailing whitespace and quotes) → `title`

2. Read `~/Documents/Radar/state/commitments.json`. If missing, treat as `[]`.

3. Build a stable id from the title: slugify the title and take the first 4–5 meaningful words. Prepend `commit-`. Example: title "Write & send canonical patient-access definition" → `commit-write-send-canonical-patient-access`. If that id already exists in the file, append `-2`, `-3`, etc. until unique.

4. Append a new commitment object:
   ```json
   {
     "id": "commit-{slug}",
     "title": "{title}",
     "first_seen": "{ISO date}",
     "last_seen": "{ISO date}",
     "days_carried": 1,
     "status": "open",
     "priority": "{priority}",
     "due_date": "{due_date or null}",
     "notion_url": "{notion_url or null}",
     "added_at": "{ISO timestamp with timezone offset}"
   }
   ```

5. Write back the updated `commitments.json`.

6. Confirm with one line: "Added `commit-{slug}`: {title}{due context if any}{priority emoji if not info}."

7. Ask (one line): "Regenerate dashboard now? (y/n)" — if `y`, invoke `/radar`. Otherwise stop.

## Notes

- Keep titles under 100 chars; if longer, ask the user to shorten before saving.
- Slug stability matters — once an id is in `commitments.json`, the dashboard's checked.json keys depend on it. Never re-slug an existing commitment's title.
- Don't auto-complete anything here. Completion comes from the dashboard checkbox flow or `/radar-act` deep-work completion gate.
- If `--due` is in the past, warn but still save (the user may be backfilling).
- For commitments with a `notion_url`, `/radar` renders an `↗` link on the card; for commitments without one, no link is rendered. `/radar-act`'s completion gate also skips the Notion-comment step when `notion_url` is null.
