# Changelog

## 1.0.1 - 2026-08-13

- Renumbered BPC melee center-out in symmetric pairs: M1/M2 retain Retribution priority, M3/M4 use Festergut output and return mobility, M5-M8 complete the normal eight-player footprint, and M9/M10 are now the obvious far-edge overflow pair.
- Rebuilt BQL melee groups around encounter mechanics: Rogues and DPS Death Knights are hard-assigned Middle, adequately performing Ferals also use Middle for rear attacks, Retribution Paladins stay on the sides, and low-output Ferals may use a side.
- Rebuilt the BQL tree around encounter progression: the second bite spreads ranged Left to Right, the third bite seeds one melee vampire per side, and the fourth bite establishes two ranged plus two melee branches per side whenever the roster permits it.
- Made the chaotic final rounds prefer same-role, same-side pairings before same class/spec, allowing local Hunter-to-Hunter, Shadow-to-Shadow, Balance-to-Balance, and equivalent visual matches. Repeated ranged classes/specs form local pairs, with four of one kind split two per side.
- Kept biters planted and DPSing: every target comes to the assigned vampire, receives the focus bite, and returns home. The second vampire now owns the physically right-side R6 position, comes to stationary R1 for the second bite, then returns to R6 as the right ranged anchor.
- Added export and 25-player regression coverage for the ranged-to-melee third bite, balanced four-branch setup, strict final-round role/side preservation, same-class matching, stationary biters, and target return routes.
- Replaced the old generic cooldown rotation with the approved four-links / air / three-links / air / two-links cadence: Shadow AM covers Pact of the Darkfallen links only, and Divine Sacrifice covers Bloodbolt Whirl air phases only. Incite Terror and bite rounds no longer receive invented cooldown assignments.
- Updated the BQL worksheet position, bite, and cooldown blocks to match these rules while retaining the existing fixed paste ranges and desktop publisher contract. Bite cells now contain only `Biter -> Target`; route annotations remain internal review data.
- Rebuilds a persisted Festergut-history selection on login so a rule update cannot leave the desktop publisher reading an older cached BPC/BQL plan from SavedVariables.
- Converts only detected outer white margins in the native 4096px Discord PNGs to transparency, preserving the full canvas dimensions and every visible raid-plan pixel.

## 1.0.0 - 2026-08-08

- First public release of Pizza Warriors Raid Planner.
- Reserved melee Rogues and Retribution Paladins for the BQL Middle group while balancing every other melee DPS only between Left and Right.
- Filled BPC Kinetic assignments as two highest-priority Hunters followed by the strongest available Warlock, regardless of that Warlock's room position; a missing third assignment now warns only when neither the Warlock rule nor an existing verified fallback can fill it.
- Treated **WoW TSV Dump** as one shared staging tab: BPC remains at row 1, row 54 is intentionally blank, and BQL helpers now reference `A55:Q62`, `A64:H73`, and `A76:G79`.
- Added the Pizza Warriors Discord emblem to the in-game ElvUI-style header and reused the emblem for the desktop sheet-sync shortcut.
- Enlarged the in-game emblem and moved it beneath the version beside Live Mode, leaving the title line clean and reserving enough status width to prevent text overlap.
- Added a bounded, token-authenticated Apps Script endpoint and Windows launcher that read only Base64 fields from flushed SavedVariables, combine both exports, and replace the managed `A1:Z250` contents of **WoW TSV Dump** without changing sheet formatting or encounter tabs.
- Added a separate one-click desktop publisher that values-only updates the five fixed live BPC/BQL ranges, renders the two raid PNGs, posts them to `#raid-positions`, and fingerprints each Festergut snapshot to prevent duplicate Discord posts. The sync-only shortcut remains available as a manual fallback.
- Replaced Google Drive's observed 1024px thumbnail output with an authenticated two-stage 4K publisher: Apps Script prepares cropped vector PDFs, Windows renders dependency-free `4096×1795` and `4096×2359` PNGs, and the endpoint verifies dimensions and Discord's returned attachment metadata before recording success.
- Fixed the desktop publisher's failure path so freshness and rendering errors appear in a visible dialog instead of terminating behind the brief PowerShell window; the latest failure is also retained in `last-error.log` for diagnosis.
- Treated a successful Discord HTTP response as authoritative after both 4096px payloads pass server validation, even when Discord omits an attachment record from its response; ambiguous protocol-v2 state is conservatively finalized without reposting, and the desktop shortcut now uses a hidden Windows Script host so no terminal remains behind the result dialog.

## 0.11.0 - 2026-08-08

- Added a persistent, scrollable Festergut history that stores both the kill's DPS benchmark and the contemporaneous raid class/spec/role roster; the newest 52 valid kills remain selectable across raid nights.
- Made saved Festergut rows clickable in **DPS Sources**. A selection rebuilds **BQL Review**, **Copy BPC**, and **Copy BQL** while leaving the live raid roster untouched; **Current Raid** and **Scan Raid** exit rehearsal mode.
- Standardized every BPC and BQL DPS decision on the same selected Festergut kill. BPC melee, Hunters, Balance Druids, and other ranged no longer mix in the ICC running average.
- Added ElvUI-accent hover borders and explanatory tooltips to every header/tab button and each DPS-source row; the active tab remains highlighted after the pointer leaves.
- Added guarded recovery for a pre-0.11 Festergut segment using a local seed or the matching saved Skada encounter. New kills require neither recovery path because their roster is captured natively.
- Kept Festergut history inside the established ICC session module so a running 3.3.5a client can receive the update with `/reload`, and guarded UI/command entry points against partial module loads and repeated missing-method errors.

## 0.10.0 - 2026-08-08

- Removed the nonexistent R11 position from BPC, BQL, the in-game copy surfaces, and every current paste instruction; ranged layouts now end permanently at R10.
- Matched the raid leader's manual BPC ranged layout by ranking non-reserved ranged DPS from the current-session Festergut benchmark, preferring R3 then R1, and placing the lower remaining performers into R4-R7. The ICC running average remains the fallback when a player lacks a Festergut sample.
- Kept the existing BPC Balance Druid, Hunter, melee mobility, healer, and cooldown assignments because they already matched the reviewed manual sheet.
- Matched the manual BQL Airphase DSac layout by preferring a capable Paladin tank first, avoiding the first Shadow AM holder for the second assignment when possible, and retaining that player as the emergency backup. Explicit `/prp utility` priorities still take precedence.
- Reduced the copy rectangles to `A1:F10` for BPC positions and `A10:H19` for BQL positions so they map exactly to the occupied rows in the visible worksheets.
- Added a dedicated persistent full-raid roster snapshot for `/prp test last`, preventing a later solo plan, reload, or post-raid UI check from erasing the composition needed for rehearsal.

## 0.9.0 - 2026-08-08

- Marked every BPC position export and Discord summary as the Valanar-active / Empowered Shock Vortex layout.
- Kept Balance Druids at R9, R10, then R8 so Starfall remains separated from Keleseth's Dark Nuclei/orb area.
- Anchored the highest-output Hunter at R2 and the second Hunter at R7 for spread Kinetic Bomb coverage; Kinetic assignment order now follows Hunter DPS unless manually overridden.
- Reserved the remaining difficult R4-R7 positions for lower ranged DPS while placing higher ranged output in the easier available slots.
- Retargeted all paste-ready rectangles to the current visible `Blood Prince Council` and `Blood Queen Lana'Thel` worksheets instead of the retired combined-sheet coordinates.
- Added `/prp test last bpc|bql` for a one-shot solo rehearsal from the most recently saved raid composition and DPS data.
- Replaced Unicode bite arrows in the in-game copy surface with ASCII `->` so the 3.3.5 client does not copy them as question marks.

## 0.8.0 - 2026-08-08

- Corrected BPC melee topology from a sequential close/outer model to the actual position image: M1/M2/M6/M7 are preferred, M4/M5/M8/M9 complete the normal eight-player footprint, and M3/M10 are overflow-only.
- Balanced protected BPC slots between top output and players without Sprint, Charge/Intercept, or Feral Charge.
- Kept detected tanks out of both bosses' DPS position blocks, matching the image's normal 5 healer + 10 ranged DPS + 8 melee DPS layout.
- Changed the planned BQL opening handoff from R1 → R2 to R1 → R4, matching R4's center-left bridge position in the raid image.
- Replaced the old odd/even ranged-lane assumption with the room's actual R-slot topology and retained hard same-side bites after R4 transitions right.
- Anchored the highest Festergut-ranked eligible Rogue as the first left-side melee player for Tricks of the Trade on R1.

## 0.7.0 - 2026-08-08

- Reshaped the in-game BPC export into two complete main-sheet-compatible rectangles: positions and cooldown rotations.
- Reshaped the BQL export into three complete rectangles: the entire bite tree, raid positions/groups, and Shadow AM/Airphase DSac rotations.
- Added slot labels, arrows, separators, group names, intentional blanks, and exact source/destination instructions so each area can be transferred as one block.
- Corrected the live bite-tree destination to `X6:AJ13`; the workbook's adjacent `AK` column is unused.
- Standardized the safe handoff on Google Sheets **Paste values only** (`Ctrl+Shift+V`) to preserve the main sheet's existing formatting and merged headings.

## 0.6.0 - 2026-08-08

- Changed BQL bite ranking from the multi-boss ICC aggregate to a dedicated current-session Festergut DPS benchmark.
- Persisted the latest valid Festergut snapshot separately so it survives the bounded individual-sample history and cannot leak across raid sessions.
- Kept a competent Mage as the preferred R1 anchor while selecting R2 from the strongest remaining Festergut ranged performer, including a higher-output Demonology Warlock.
- Added class-specific R2 movement text for Blink, Demonic Circle, or ordinary movement while preserving the left-to-right opening handoff and later same-side chains.
- Reserved BPC R9, R10, then R8 for Balance Druids.
- Added DPS/mobility-aware BPC melee placement: tanks and non-mobile pumpers favor M1-M6, while Sprint, Charge/Intercept, and Feral Charge candidates take M7-M10.
- Fixed the ElvUI-styled top-right close button so it hides the entire planner window.
- Made live mode explicitly opt-in; BQL combat-log events no longer arm it automatically.

## 0.5.0 - 2026-08-07

- Rebuilt the in-game window to inherit the installed ElvUI font, color, panel, button, close-button, and scrollbar styling, with a legacy fallback when ElvUI is unavailable.
- Replaced the workbook connector with plain BPC and BQL A1 staging worksheets whose labeled blocks match the existing `BPC & BQL` destination ranges.
- Added inspected Wrath spec names and unambiguous spec-to-role resolution, including Holy Paladin healer, Protection Paladin tank, and Retribution Paladin melee DPS handling.
- Added class/spec/role/position evidence beneath each copy surface for quick review before updating the main sheet.
- Removed the Google Apps Script and connector setup files; the addon performs no spreadsheet or network writes.

## 0.4.0 - 2026-08-07

- Restricted automatic damage capture and storage to Icecrown Citadel.
- Added a persistent ICC raid-session lifecycle that starts on entry, survives reloads/reconnects and short exits, and automatically rolls over after 18 hours away.
- Replaced the newest-fight automatic ranking with a per-player running mean across the current session's valid pre-BQL ICC boss samples.
- Discarded automatic trash segments instead of allowing them to consume the 20-sample history.
- Combined all three Blood Princes into one boss-target sample and excluded BQL from the pre-fight average while retaining it for audit.
- Guarded the optional Skada fallback against non-ICC, stale pre-session, trash, and BQL data.
- Improved `/prp status`, source help, and the export window's Ctrl+C instruction.

## 0.3.0 - 2026-08-03

- Added Azy's BQL composition rules: competent Mage R1/R2 anchors, R2 left-to-right Blink handoff, odd/even left/right lanes, first-four ranged priority, hard same-side ranged bites, and melee-last scheduling.
- Separated physical position from bite priority so Boomkins/Warlocks can favor center and Hunters can favor back/edge without forcing their bite timing.
- Added BQL healer/ranged/melee maps plus Shadow Aura Mastery and Airphase Divine Sacrifice orders.
- Added BPC Hunter Kinetics, Divine Sacrifice, and Fire Aura Mastery orders.
- Added optional, capability-checked Skada 1.8.x role/spec/talent detection and boss-target DPS fallback; the standalone tracker remains primary.
- Added a workbook-specific Google Apps Script bridge for the existing `BPC & BQL` tab and its Discord workflow.
- Tightened automatic segment validity to reject cleave-heavy pulls and track unbuffed BQL primary-target damage.
- Added composition, lane, cooldown, Skada, damage, and combined-export tests.

## 0.2.0 - 2026-08-03

- Completed the clean pre-install rename to `PizzaRaidPlanner`: addon folder, TOC, Lua namespace, SavedVariables, UI frame, companion tool, fixtures, documentation, and release package now share one identity.
- Made `/prp` the primary command while retaining `/pb` and `/bql` as convenient aliases.
- Added Blood Prince Council raid-composition review and H1-H5, M1-M10, R1-R10 position exports.

## 0.1.0 - 2026-08-03

- Initial WotLK 3.3.5a Blood-Queen planner with roster, segment, damage, optimizer, live detection, exports, UI, tests, and safe SavedVariables bridge.
- Defaulted the intended raid-night flow to automatic segment selection and added `/pb publish`: scan, plan, and present paste-ready TSV in one pre-BQL command.
