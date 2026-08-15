# Companion tools

These tools bridge a flushed WoW SavedVariables export to a raid team's own Google workbook and Discord channel. They are reference components for maintainers, not a hosted service.

## Files

- `DiscordPost.gs` — bind this to the adapting team's workbook. First-time setup stores that workbook's ID and secrets in document properties; no live identifier is committed.
- `Sync-PizzaRaidPlannerToSheets.ps1` — reads only quoted Base64 export fields, requires one clean atomic BPC/BQL plan revision, validates the fixed layout, renders native 4096px PNGs, converts only detected outer white margins to transparency without resizing, and calls the authenticated Apps Script endpoint.
- `Publish-PizzaRaidPlannerHidden.vbs` — launches the configured publisher without leaving a terminal window open.
- `Export-PizzaRaidPlanner.ps1` — optional manual exporter for reviewing TSV files locally.
- `PizzaWarriorsSheetSync.ico` — upstream desktop icon; forks must replace reserved Pizza Warriors branding.

See [the adaptation guide](../docs/ADAPTATION_GUIDE.md) for setup and [the architecture guide](../docs/ARCHITECTURE.md) for trust boundaries.

## Local state

Runtime configuration is stored beneath `%LOCALAPPDATA%\PizzaRaidPlanner` and must never be committed. It can contain an encrypted upload token, workbook endpoint, local account path, audit metadata, and the most recent TSV transfer.

WoW writes SavedVariables only during `/reload`, logout, or exit. The publisher intentionally rejects stale files unless the maintainer uses the explicit recovery switch after verifying the selected plan.

If the roster changes after Festergut, run `/prp audible` before `/reload`. The launcher deliberately refuses a SavedVariables export whose roster fingerprint is dirty or whose BPC/BQL bundle IDs differ.
