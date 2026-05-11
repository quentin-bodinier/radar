---
description: Add a focus task to today's Radar dashboard. Surfaces at the top of the Focus strip and in a dedicated "My focus today" card.
argument-hint: <focus task description>
---

The user wants to add a focus task. The task description is in `$ARGUMENTS`.

If `$ARGUMENTS` is empty, ask the user what they want to add (one short prompt) and stop. Otherwise:

## Steps

1. Read `~/Documents/Radar/state/focus.json`.

2. Append a new task object:
   ```json
   {
     "id": "focus-{ISO_DATE}-{NNN}",
     "title": "{user's text, trimmed}",
     "added_at": "{current ISO timestamp with timezone offset}",
     "active": true,
     "completed_at": null
   }
   ```
   `NNN` is a 3-digit sequence (count of tasks added today + 1).

3. Write back the updated `focus.json`.

4. Ask the user (one line): "Added. Regenerate dashboard now? (y/n)" — if yes, invoke `/radar`. If no, just confirm and stop.

## Notes

- Don't auto-archive old tasks here — `/radar` handles that based on checkbox state in the rendered HTML (it can read `active: false` if user manually edits the JSON, but the source of truth for "done" is the dashboard's checkbox state in sessionStorage).
- Trim leading/trailing whitespace and quotes from `$ARGUMENTS`.
- Keep titles under 80 chars — if longer, ask the user to shorten.
