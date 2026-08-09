PizzaRaidPlanner = PizzaRaidPlanner or {}
local PB = PizzaRaidPlanner

PB.VERSION = "1.0.0"
PB.SCHEMA_VERSION = 11
PB.MAX_SEGMENTS = 20
PB.MAX_FESTERGUT_HISTORY = 52
PB.SEGMENT_GRACE = 8
PB.MIN_SEGMENT_DURATION = 30
PB.MIN_SEGMENT_DAMAGE = 50000
PB.ICC_SESSION_TIMEOUT = 18 * 60 * 60
PB.ICC_NAME = "Icecrown Citadel"
PB.BQL_NPC_ID = 37955
PB.BQL_NAME = "Blood-Queen Lana'thel"
PB.ICC_BOSS_NPCS = {
  [36612]="marrowgar", [36855]="deathwhisper", [37813]="saurfang",
  [36626]="festergut", [36627]="rotface", [36678]="putricide",
  [37970]="council", [37972]="council", [37973]="council",
  [37955]="bql", [36789]="valithria", [36853]="sindragosa", [36597]="lichking",
}
PB.ICC_BOSS_NAMES = {
  ["lord marrowgar"]="marrowgar", ["lady deathwhisper"]="deathwhisper",
  ["deathbringer saurfang"]="saurfang", ["festergut"]="festergut",
  ["rotface"]="rotface", ["professor putricide"]="putricide",
  ["prince valanar"]="council", ["prince keleseth"]="council", ["prince taldaram"]="council",
  ["blood-queen lana'thel"]="bql", ["blood queen lana'thel"]="bql",
  ["valithria dreamwalker"]="valithria", ["sindragosa"]="sindragosa",
  ["the lich king"]="lichking",
}
PB.ICC_ENCOUNTER_NAMES = {
  marrowgar="Lord Marrowgar", deathwhisper="Lady Deathwhisper", saurfang="Deathbringer Saurfang",
  festergut="Festergut", rotface="Rotface", putricide="Professor Putricide",
  council="Blood Prince Council", bql="Blood-Queen Lana'thel", valithria="Valithria Dreamwalker",
  sindragosa="Sindragosa", lichking="The Lich King",
}
PB.ICC_AVERAGE_ENCOUNTERS = {
  marrowgar=true, deathwhisper=true, saurfang=true, festergut=true, rotface=true,
  putricide=true, council=true, sindragosa=true, lichking=true,
}
PB.BQL_SPELLS = { [70867]=true,[71473]=true,[71532]=true,[71533]=true,[70879]=true,[71525]=true,[71530]=true,[71531]=true }
PB.BITE_SPELLS = { [70946]=true,[71475]=true,[71476]=true,[71477]=true,[71726]=true }
PB.FRENZY_SPELLS = { [70877]=true,[71474]=true,[70923]=true }
PB.UTILITY_SPELLS = { [31821]="auraMastery", [64205]="divineSacrifice" }
PB.SPEC_NAMES = {
  [62]="Arcane",[63]="Fire",[64]="Frost",
  [65]="Holy",[66]="Protection",[70]="Retribution",
  [71]="Arms",[72]="Fury",[73]="Protection",
  [102]="Balance",[103]="Feral DPS",[104]="Feral Tank",[105]="Restoration",
  [250]="Blood",[251]="Frost",[252]="Unholy",
  [253]="Beast Mastery",[254]="Marksmanship",[255]="Survival",
  [256]="Discipline",[257]="Holy",[258]="Shadow",
  [259]="Assassination",[260]="Combat",[261]="Subtlety",
  [262]="Elemental",[263]="Enhancement",[264]="Restoration",
  [265]="Affliction",[266]="Demonology",[267]="Destruction",
}
-- These specs have an unambiguous raid role in Wrath. Death Knight trees are
-- deliberately omitted because all three could tank on 3.3.5; Skada's
-- inspected role or a manual override resolves those players instead.
PB.SPEC_ROLES = {
  [62]="dps",[63]="dps",[64]="dps",
  [65]="healer",[66]="tank",[70]="dps",
  [71]="dps",[72]="dps",[73]="tank",
  [102]="dps",[103]="dps",[104]="tank",[105]="healer",
  [253]="dps",[254]="dps",[255]="dps",
  [256]="healer",[257]="healer",[258]="dps",
  [259]="dps",[260]="dps",[261]="dps",
  [262]="dps",[263]="dps",[264]="healer",
  [265]="dps",[266]="dps",[267]="dps",
}
PB.RANGED_SPECS = { [62]=true,[63]=true,[64]=true,[65]=true,[102]=true,[105]=true,[253]=true,[254]=true,[255]=true,[256]=true,[257]=true,[258]=true,[262]=true,[264]=true,[265]=true,[266]=true,[267]=true }
PB.HEALER_SPECS = { [65]=true,[105]=true,[256]=true,[257]=true,[264]=true }
PB.TANK_SPECS = { [66]=true,[73]=true,[104]=true }
-- BPC worksheet topology from the raid team's actual position image. M1, M2,
-- M6, and M7 are the protected boss-return positions. An eight-melee-DPS layout
-- then uses M4, M5, M8, and M9; M3 and M10 are distant overflow positions.
-- Balance Druids remain reserved in the preferred R9/R10/R8 area. R3 then R1
-- are the best unreserved ranged positions; R4-R7 are the difficult range band.
-- The worksheet and room plan permanently stop at R10.
PB.BPC_BOOMKIN_SLOTS = { 9, 10, 8 }
PB.BPC_HUNTER_SLOTS = { 2, 7 }
PB.BPC_RANGED_ACCESSIBLE_SLOTS = { 3, 1, 2, 8, 9, 10 }
PB.BPC_RANGED_DIFFICULT_SLOTS = { 4, 5, 6, 7 }
PB.BPC_MELEE_PREFERRED_SLOTS = { 1, 2, 6, 7 }
PB.BPC_MELEE_RECOVERY_SLOTS = { 4, 5, 8, 9, 3, 10 }
-- One shared WoW TSV Dump tab: BPC occupies rows 1-53, row 54 is the
-- deliberate spacer, and the BQL export begins at row 55.
PB.WORKSHEET_BPC_LAST_ROW = 53
PB.WORKSHEET_BQL_DUMP_ROW = 55
PB.DAMAGE_EVENTS = { SWING_DAMAGE=true, RANGE_DAMAGE=true, SPELL_DAMAGE=true, SPELL_PERIODIC_DAMAGE=true, DAMAGE_SHIELD=true, DAMAGE_SPLIT=true }
PB.HEAL_EVENTS = { SPELL_HEAL=true, SPELL_PERIODIC_HEAL=true }
PB.DEFAULTS = {
  schemaVersion = PB.SCHEMA_VERSION,
  -- The aggregate remains available for roster review; BPC and BQL planning are Festergut-only.
  settings = { allowEmergencyFallback=false, announce="off", debug=false, source="auto", medianCount=3 },
  ui = { point="CENTER", x=0, y=0, width=860, height=520 },
  roleOverrides = {}, inclusionOverrides = {}, exclusionReasons = {}, positionOverrides = {}, manualPriorities = {},
  capabilityOverrides = {}, capabilityEvidence = {}, competenceOverrides = {}, utilityPriorities = {},
  segments = {}, selectedSegmentId = nil, iccSession = {}, encounterHistory = {}, latestPlan = nil,
  festergutHistory = {}, selectedFestergutHistoryId = nil,
  lastRaidRoster = {},
  debugLog = {},
}
function PB:NormalizeName(name) return (name or ""):gsub("%-[^%s]+$", ""):lower() end
function PB:Now() return time and time() or 0 end
function PB:GetNPCID(guid)
  if not guid then return nil end
  local hex = guid:match("^0xF130(%x%x%x%x%x%x)")
  if hex then return tonumber(hex, 16) end
  local id = guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)")
  return id and tonumber(id) or nil
end
function PB:IsBQL(guid, name) return PB:GetNPCID(guid) == PB.BQL_NPC_ID or PB:NormalizeName(name) == PB:NormalizeName(PB.BQL_NAME) end
function PB:SpellMatches(set, spellId, spellName)
  if set[spellId] then return true end
  if not spellName or not GetSpellInfo then return false end
  for id in pairs(set) do local localized=GetSpellInfo(id); if localized and localized==spellName then return true end end
  return false
end
