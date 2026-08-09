local PB=PizzaRaidPlanner
PizzaRaidPlannerDB=nil; PizzaRaidPlannerExportDB=nil; PB:InitDB()

local function player(name,spec,skadaRole)
  return {guid=name,name=name,normalizedName=name:lower(),classToken="PALADIN",spec=spec,skadaRole=skadaRole,online=true,connected=true,dead=false,subgroup=1}
end

local holy=player("HolyPala",65,"DAMAGER")
assert(PB:GetSpecName(holy)=="Holy","Holy Paladin spec name")
assert(PB:ResolveRole(holy)=="healer","Holy Paladin resolves as healer before stale Skada role")
assert(PB:GetPosition(holy)=="ranged","Holy Paladin resolves to ranged position")

local protection=player("ProtPala",66,"DAMAGER")
assert(PB:ResolveRole(protection)=="tank","Protection Paladin resolves as tank")
assert(PB:GetPosition(protection)=="melee","Protection Paladin resolves to melee position")

local retribution=player("RetPala",70,"HEALER")
assert(PB:ResolveRole(retribution)=="dps","Retribution Paladin resolves as DPS before stale Skada role")
assert(PB:GetPosition(retribution)=="melee","Retribution Paladin resolves to melee position")

local deathKnight={guid="FrostDK",name="FrostDK",normalizedName="frostdk",classToken="DEATHKNIGHT",spec=251,skadaRole="TANK",online=true,connected=true,dead=false,subgroup=1}
assert(PB:ResolveRole(deathKnight)=="tank","ambiguous Death Knight spec defers to inspected Skada role")

PB.db.roleOverrides.retpala="healer"
assert(PB:ResolveRole(retribution)=="healer","manual override remains highest priority")
print("test_roles: OK")
