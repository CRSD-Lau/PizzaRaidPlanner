local PB=PizzaRaidPlanner
PizzaRaidPlannerDB=nil; PizzaRaidPlannerExportDB=nil; PB:InitDB(); PB.roster={}; PB.byGUID={}; PB.byName={}; PB.live={active=false,vampires={},completed={}}
local function add(name,class,spec,dps,role)
  local p={guid=name,name=name,normalizedName=name:lower(),classToken=class,spec=spec,online=true,connected=true,dead=false,subgroup=1,expectedDPS=dps,bossDamage=dps*60,raidIndex=#PB.roster+1}
  PB.roster[#PB.roster+1]=p; PB.byGUID[p.guid]=p; PB.byName[p.normalizedName]=p; PB.db.roleOverrides[p.normalizedName]=role or "dps"; return p
end
add("MageAlpha","MAGE",63,12000); add("MageBeta","MAGE",63,11500)
add("Boomkin","DRUID",102,11000); add("Warlock","WARLOCK",266,13500)
add("HunterAlpha","HUNTER",253,12500); add("PriestShadow","PRIEST",258,10700)
add("HunterBeta","HUNTER",254,10600); add("Elemental","SHAMAN",262,10500)
add("Rogue","ROGUE",259,13000); add("Warrior","WARRIOR",71,12900); add("DeathKnight","DEATHKNIGHT",252,12800); add("RetributionPaladin","PALADIN",70,12700); add("RogueJunior","ROGUE",259,12000)
local firstShadow=add("HolyPaladin","PALADIN",65,0,"healer"); firstShadow.hasAuraMastery=true; firstShadow.hasDivineSacrifice=true
local secondDSac=add("HolyPaladinTwo","PALADIN",65,0,"healer"); secondDSac.hasDivineSacrifice=true
local tankDSac=add("ProtectionPaladin","PALADIN",66,0,"tank"); tankDSac.hasDivineSacrifice=true
add("HolyPriest","PRIEST",257,0,"healer")
PB.ScanRoster=function() end
local benchmark={id="test",targetName="Festergut",iccEncounter="festergut",duration=60,confidence="Good",valid=true,players={}}
for _,p in ipairs(PB.roster) do benchmark.players[p.guid]={dps=p.expectedDPS,totalDamage=(p.expectedDPS or 0)*60,primaryDamage=(p.expectedDPS or 0)*60,healing=0} end
PB.GetSelectedSource=function() return benchmark end
PB.GetBQLBenchmarkSource=function() return benchmark end
local plan=PB:GeneratePlan(); local comp=plan.composition
assert(comp.primary.name=="MageAlpha" and comp.secondary.name=="Warlock","competent Mage R1 with stronger Festergut ranged R4")
assert(comp.byGUID.MageAlpha.slot=="R1" and comp.byGUID.Warlock.slot=="R4","opening anchor slots follow the room image")
assert(comp.byGUID.Warlock.startLane=="left" and comp.byGUID.Warlock.lane=="right","second anchor lane transition")
assert(comp.secondaryHandoff:find("Demonic Circle",1,true),"Warlock R4 receives portal movement")
assert(comp.byGUID.Boomkin.depth=="center","non-anchor Boomkin keeps center preference")
assert(comp.byGUID.Warlock.depth=="front","performance-selected R4 uses the opening handoff position")
assert(comp.byGUID.HunterAlpha.depth=="back" or comp.byGUID.HunterBeta.depth=="back","hunter back/edge preference")
assert(comp.byGUID.Rogue.lane=="middle" and comp.byGUID.Rogue.groupOrder==1,"top Rogue is reserved for the Middle melee group")
assert(comp.byGUID.RetributionPaladin.lane=="middle" and comp.byGUID.RetributionPaladin.groupOrder==2,"Retribution Paladin is reserved for the Middle melee group")
assert(comp.byGUID.RogueJunior.lane=="middle" and comp.byGUID.RogueJunior.groupOrder==3,"every melee Rogue stays in the Middle group")
assert(comp.byGUID.Warrior.lane=="left" and comp.byGUID.DeathKnight.lane=="right","other melee DPS alternate only between Left and Right")
assert(comp.utility.shadowAM[1].player.name=="HolyPaladin","first Shadow AM holder follows verified cooldown order")
assert(comp.utility.dsac[1].player.name=="ProtectionPaladin" and comp.utility.dsac[2].player.name=="HolyPaladinTwo" and comp.utility.dsac[3].player.name=="HolyPaladin","BQL Airphase DSac uses tank first, avoids double-booking first Shadow AM, and keeps that Paladin as emergency")
for i=1,math.min(4,#plan.flatPriority) do local pos=comp.byGUID[plan.flatPriority[i].guid]; assert(pos and pos.type=="ranged","first four vampires ranged") end
for _,a in ipairs(plan.assignments) do
  if a.wave>=2 and a.targetPosition=="ranged" then assert(a.biterLane==a.targetLane,"same-side ranged bite") end
end
local handoff=plan.waves[1][1]
assert(handoff.biterSlot=="R1" and handoff.targetSlot=="R4" and handoff.biterLane=="left" and handoff.targetLane=="right","intentional R1 to R4 bridge")
assert(handoff.target=="Warlock" and handoff.movement:find("Demonic Circle",1,true),"opening handoff follows performance-selected R4")
PB.db.utilityPriorities.holypaladin=30; PB.db.utilityPriorities.holypaladintwo=20; PB.db.utilityPriorities.protectionpaladin=10
comp=PB:BuildBQLComposition(PB:GetRankedPlayers(false))
assert(comp.utility.dsac[1].player.name=="HolyPaladin" and comp.utility.dsac[2].player.name=="HolyPaladinTwo" and comp.utility.dsac[3].player.name=="ProtectionPaladin","explicit utility priorities override the automatic BQL DSac reshuffle")
local sawMelee=false
for _,a in ipairs(plan.assignments) do
  if a.targetPosition=="melee" then sawMelee=true else assert(not sawMelee,"ranged targets scheduled before melee") end
end
print("test_bql: OK")
