# Adaptation guide

This guide is for a maintainer adapting Pizza Warriors Raid Planner to another raid team. It assumes familiarity with Lua, PowerShell, Google Sheets, Google Apps Script, and Discord webhooks.

## Before you begin

The reference implementation encodes Pizza Warriors strategy and a fixed workbook contract. Do not deploy it unchanged and assume its assignments match another group.

Prepare:

- A fork created under the included noncommercial license
- A clean 3.3.5a test client with Skada and optionally ElvUI
- A separate Google Sheets test workbook
- A disposable Discord test webhook
- Test rosters representing your real healer, melee, ranged, tank, and Paladin variations

Never use production credentials during development.

## 1. Replace reserved branding

Replace the addon title, emblem, desktop icon, dialog titles, and Discord copy with your own raid identity. Keep the required copyright and license notices. The Pizza Warriors name and emblem are not licensed for derivative branding.

Key locations:

- `PizzaRaidPlanner.toc`
- `Constants.lua`
- `UI.lua`
- `Media/`
- `tools/Sync-PizzaRaidPlannerToSheets.ps1`
- `tools/Publish-PizzaRaidPlannerHidden.vbs`
- `tools/DiscordPost.gs`

## 2. Review the strategy engine

The most consequential contracts live in:

| File | Responsibility |
|---|---|
| `BPC.lua` | Valanar-active position layout, Kinetics, DSac, and Aura Mastery assignments |
| `BQL.lua` | Bite eligibility, wave construction, and side-aware bite routing |
| `Optimizer.lua` | Stable ranking and slot assignment helpers |
| `PlanBundle.lua` | Atomic BPC/BQL revisions, roster fingerprints, audible diffs, and Festergut provenance |
| `Roles.lua` | Spec, role, melee/ranged, and utility inference |
| `Damage.lua` | Boss-death evidence plus Festergut benchmark collection and safeguards |
| `Export.lua` | Fixed TSV rectangles consumed by the workbook |

Write or update offline tests before changing a rule. In-game evidence is still required for combat-log identifiers and server-specific behavior.

## 3. Prepare your workbook

Your workbook must provide these sheet names and managed ranges unless you deliberately update both the Apps Script and tests:

| Source | Destination |
|---|---|
| `WoW TSV Dump!A1:F10` | `Blood Prince Council!A6:F15` |
| `WoW TSV Dump!A13:F15` | `Blood Prince Council!A20:F22` |
| `WoW TSV Dump!A55:Q62` | `Blood Queen Lana'Thel!A28:Q35` |
| `WoW TSV Dump!A64:H73` | `Blood Queen Lana'Thel!N6:U15` |
| `WoW TSV Dump!A76:G79` | `Blood Queen Lana'Thel!N20:T23` |

The public Apps Script contains no workbook ID. When **Raid Positions → Configure desktop TSV sync** is run from a bound workbook, it records that workbook's ID in its own document properties. The web endpoint then opens only that bound workbook.

## 4. Bind and deploy Apps Script

1. Open your test workbook.
2. Select **Extensions → Apps Script**.
3. Replace the default script with `tools/DiscordPost.gs`.
4. Save and reload the workbook.
5. Select **Raid Positions → Set Discord webhook** and enter the disposable test webhook.
6. Select **Raid Positions → Configure desktop TSV sync** once so the workbook is bound and a private token is generated.
7. In Apps Script, select **Deploy → New deployment → Web app**.
8. Execute as yourself and grant only the access level needed by your desktop publisher.
9. Reopen the configuration dialog and copy the web-app URL and token into the desktop setup.

Treat the deployment URL and token as credentials even though neither appears in this repository.

## 5. Configure the Windows publisher

Place the files from `tools/` in a local application directory, then run:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\Sync-PizzaRaidPlannerToSheets.ps1 -Configure
```

The first-time dialog asks for:

- Your web-app URL
- Your private upload token
- `WTF\Account\YOUR_ACCOUNT\SavedVariables\PizzaRaidPlanner.lua`

The token is stored using Windows user encryption. Do not move the generated configuration into source control or share it between Windows accounts.

## 6. Validate before raid use

Run the offline suite:

```powershell
lua5.1 .\tests\run_tests.lua
node .\tests\test_discord_post.js
powershell.exe -NoProfile -File .\tests\test_sheet_sync.ps1
powershell.exe -NoProfile -File .\scripts\Test-PublicRepository.ps1
```

Then complete [IN_GAME_TEST_CHECKLIST.md](IN_GAME_TEST_CHECKLIST.md) with a disposable workbook and Discord channel. Do not point an unreviewed fork at a live raid workbook.

## 7. Build release archives

```powershell
powershell.exe -NoProfile -File .\scripts\Build-Release.ps1
```

The builder produces separate addon and desktop archives plus SHA-256 checksums under `dist/`. It deliberately excludes tests, development assets, local configuration, SavedVariables, and secrets.
