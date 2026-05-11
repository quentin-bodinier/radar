---
name: radar-daily-rebuild
description: Rebuilds Quentin's Radar dashboard hourly 7AM–7PM on weekdays — writes state/data.js, today.html is never modified.
---

Run /radar to refresh Quentin's daily Radar dashboard.

The /radar skill will:
1. Fetch fresh data from Google Calendar, Slack, Gmail, and Notion
2. Compute commitment carryover from state/commitments.json
3. Write ~/Documents/Radar/state/data.js with window.RADAR_DATA = { ... } — this is the only file that changes each run
4. Update ~/Documents/Radar/state/commitments.json
5. Write a daily snapshot to ~/Documents/Radar/state/history/YYYY-MM-DD.json

today.html is a permanent static file — do NOT write to it.