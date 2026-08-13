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
add("Rogue","ROGUE",259,13000); add("Warrior","WARRIOR",71,12900); add("DeathKnight","DEATHKNIGHT",252,12800); local ret=add("RetributionPaladin","PALADIN",70,12700); ret.hasAuraMastery=true; add("RogueJunior","ROGUE",259,12000)
local firstShadow=add("HolyPaladin","PALADIN",65,0,"healer"); firstShadow.hasAuraMastery=true; firstShadow.hasDivineSacrifice=true
local secondDSac=add("HolyPaladinTwo","PALADIN",65,0,"healer"); secondDSac.hasAuraMastery=true; secondDSac.hasDivineSacrifice=true
local tankDSac=add("ProtectionPaladin","PALADIN",66,0,"tank"); tankDSac.hasAuraMastery=true; tankDSac.hasDivineSacrifice=true
add("HolyPriest","PRIEST",257,0,"healer")
local reserve=add("HolyPaladinThree","PALADIN",65,0,"healer"); reserve.hasAuraMastery=true; reserve.hasDivineSacrifice=true
PB.db.utilityPriorities.protectionpaladin=100
for _,item in ipairs(PB:GetBQLShadowAMOrder()) do
  assert(item.player.name~="ProtectionPaladin","BQL Shadow AM excludes tanks even with talent evidence and top utility priority")
end
PB.db.utilityPriorities.protectionpaladin=nil
PB.ScanRoster=function() end
local benchmark={id="test",targetName="Festergut",iccEncounter="festergut",duration=60,confidence="Good",valid=true,players={}}
for _,p in ipairs(PB.roster) do benchmark.players[p.guid]={dps=p.expectedDPS,totalDamage=(p.expectedDPS or 0)*60,primaryDamage=(p.expectedDPS or 0)*60,healing=0} end
PB.GetSelectedSource=function() return benchmark end
PB.GetBQLBenchmarkSource=function() return benchmark end
local plan=PB:GeneratePlan(); local comp=plan.composition
assert(comp.primary.name=="MageAlpha" and comp.secondary.name=="Warlock","competent Mage R1 with stronger Festergut ranged R6")
assert(comp.byGUID.MageAlpha.slot=="R1" and comp.byGUID.Warlock.slot=="R6","opening anchors occupy the physical left and right homes")
assert(comp.byGUID.Warlock.startLane=="right" and comp.byGUID.Warlock.lane=="right" and comp.byGUID.Warlock.returnLane=="right","second anchor has a true right-side home before and after the second bite")
assert(comp.secondaryHandoff:find("Demonic Circle",1,true) and comp.secondaryHandoff:find("R6",1,true) and comp.secondaryHandoff:find("return home",1,true) and comp.secondaryHandoff:find("port",1,true) and comp.secondaryHandoff:find("stay there",1,true) and comp.secondaryHandoff:find("comes to you",1,true) and comp.secondaryHandoff:find("DPS",1,true),"Warlock R6 ports home, holds DPS, and receives the melee target")
assert(comp.byGUID.Boomkin.depth=="center","non-anchor Boomkin keeps center preference")
assert(comp.byGUID.Warlock.depth=="front","performance-selected R6 uses the right anchor position")
assert(comp.byGUID.HunterAlpha.depth=="back" or comp.byGUID.HunterBeta.depth=="back","hunter back/edge preference")
assert(comp.byGUID.HunterAlpha.lane==comp.byGUID.HunterBeta.lane,"a two-Hunter visual pair shares one side for a local Hunter-to-Hunter bite")
assert(comp.byGUID.Rogue.lane=="middle" and comp.byGUID.Rogue.groupOrder==1,"top Rogue is reserved for the Middle melee group")
assert(comp.byGUID.RogueJunior.lane=="middle","every melee Rogue stays in the Middle group")
assert(comp.byGUID.DeathKnight.lane=="middle","every DPS Death Knight stays in the Middle group for reliable AMS flame handling")
assert(comp.byGUID.RetributionPaladin.lane=="left" or comp.byGUID.RetributionPaladin.lane=="right","Retribution Paladin stays on a side")
assert(comp.byGUID.Warrior.lane=="left","remaining non-Rogue, non-DK melee are assigned to the side groups")
assert(comp.utility.shadowAM[1].player.name=="RetributionPaladin" and comp.utility.shadowAM[3].player.name=="HolyPaladinTwo" and comp.utility.shadowAM[4].player.name=="HolyPaladinThree","BQL Shadow AM starts with Ret and reserves a fourth holder for P3")
assert(comp.utility.dsac[1].player.name=="ProtectionPaladin" and comp.utility.dsac[2].player.name=="HolyPaladin" and comp.utility.dsac[3].player.name=="HolyPaladinTwo" and comp.utility.dsac[4].player.name=="HolyPaladinThree","BQL DSac keeps tank-first cadence and enough holders for the late overlap")
local cooldownRows=comp.utility.cooldowns.rows
assert(cooldownRows[1].leftPlayers=="RetributionPaladin" and cooldownRows[1].rightPlayers=="RetributionPaladin / HolyPaladin","phase timeline repeats the first two Shadow AM holders in P2")
assert(cooldownRows[2].leftPlayers=="HolyPaladin" and cooldownRows[2].rightPlayers=="HolyPaladinTwo","third P2 link uses the third Shadow AM holder")
assert(cooldownRows[3].leftPlayers=="HolyPaladinTwo / HolyPaladinThree" and cooldownRows[3].leftCooldown=="AM" and cooldownRows[3].rightEvent=="AIR" and cooldownRows[3].rightPlayers=="HolyPaladin" and cooldownRows[3].rightCooldown=="DSAC","P1 links three and four remain Shadow AM while air two uses the second DSac")
assert(cooldownRows[4].leftEvent=="AIR" and cooldownRows[4].leftPlayers=="ProtectionPaladin" and cooldownRows[4].leftCooldown=="DSAC" and cooldownRows[4].rightEvent=="1st / 2nd" and cooldownRows[4].rightPlayers=="HolyPaladinThree / RetributionPaladin","air one uses the first DSac and P3 links use Shadow AM four then one with standardized link numbering")
for _,event in ipairs(comp.utility.cooldowns.events) do
  if event.mechanic=="Bloodbolt Whirl" then assert(event.ability=="DSac","only Bloodbolt Whirl uses DSac")
  else assert(event.mechanic:find("Link",1,true) and event.ability=="Shadow AM","every non-air cooldown event is a Pact link covered by Shadow AM") end
  assert(not event.mechanic:find("Terror",1,true) and not event.mechanic:find("bite",1,true),"fear and bites are absent from the cooldown plan")
end
for i=1,math.min(2,#plan.flatPriority) do local pos=comp.byGUID[plan.flatPriority[i].guid]; assert(pos and pos.type=="ranged","opening two vampires are ranged") end
for i=3,math.min(4,#plan.flatPriority) do local pos=comp.byGUID[plan.flatPriority[i].guid]; assert(pos and pos.type=="melee","third bite seeds one melee vampire per side") end
for _,a in ipairs(plan.assignments) do
  if a.wave>=2 and a.targetPosition=="ranged" then
    assert(a.movement:find("Bloodbolt Whirl",1,true),"ranged bite returns players to home-side whirl spacing")
  end
  if a.temporaryCrossing then
    assert(a.biterLane~=a.targetLane and a.movement:find("return",1,true),"every cross-room route has an explicit return")
    assert(a.travelerGUID==a.targetGUID and a.returnActor=="target" and a.returnLane==a.targetLane and a.biteLane==a.biterLane and a.targetMoves and not a.biterMoves and a.biterKeepsDPS,"cross-room target travels to the stationary biter and returns home")
  end
end
local function waveLaneCounts(wave)
  local counts={left=0,right=0}
  for _,a in ipairs(wave or {}) do if counts[a.targetLane]~=nil then counts[a.targetLane]=counts[a.targetLane]+1 end end
  return counts.left,counts.right
end
local waveTwoLeft,waveTwoRight=waveLaneCounts(plan.waves[2])
assert(waveTwoLeft==1 and waveTwoRight==1,"third displayed bite grows one melee vampire on each home side")
for _,a in ipairs(plan.waves[2]) do assert(a.biterType=="ranged" and a.targetType=="melee" and a.chainPurpose=="ranged-to-melee-seed","third displayed bite is explicitly ranged-to-melee") end
local handoff=plan.waves[1][1]
assert(handoff.biterSlot=="R1" and handoff.targetSlot=="R6" and handoff.biterLane=="left" and handoff.targetLane=="right" and handoff.routeLabel=="R6 TO R1 > HOME R","R6 comes to the stationary R1 for the second bite, then returns to the right home")
assert(handoff.target=="Warlock" and handoff.movement:find("Demonic Circle",1,true) and handoff.movement:find("return home",1,true) and handoff.movement:find("port",1,true) and handoff.movement:find("R6",1,true),"opening handoff explains the permanent left-to-right branch spread")
local secondarySeed,secondaryLater
for _,a in ipairs(plan.assignments) do
  if a.biter=="Warlock" and a.wave==2 then secondarySeed=a
  elseif a.biter=="Warlock" and a.wave>2 then secondaryLater=a end
end
assert(secondarySeed and secondarySeed.biterLane=="right" and secondarySeed.targetLane=="right" and secondarySeed.targetType=="melee" and not secondarySeed.temporaryCrossing and secondarySeed.routeMode=="target-to-biter" and secondarySeed.routeLabel=="MDPS SEED R" and not secondarySeed.biterMoves and secondarySeed.targetMoves,"R6 stays right and receives the right-side melee seed target")
assert(secondaryLater and secondaryLater.biterLane=="right" and secondaryLater.routeMode=="target-to-biter" and not secondaryLater.biterMoves and secondaryLater.targetMoves,"R6 remains planted on the right for later bites")
PB.db.utilityPriorities.holypaladin=30; PB.db.utilityPriorities.holypaladintwo=20; PB.db.utilityPriorities.protectionpaladin=10
comp=PB:BuildBQLComposition(PB:GetRankedPlayers(false))
assert(comp.utility.dsac[1].player.name=="HolyPaladin" and comp.utility.dsac[2].player.name=="HolyPaladinTwo" and comp.utility.dsac[3].player.name=="ProtectionPaladin","explicit utility priorities override the automatic BQL DSac reshuffle")
for _,a in ipairs(plan.assignments) do
  if a.wave>=3 then assert(a.biterKeepsDPS and a.targetMoves,"late bite assignments keep the biter working while the target comes in") end
end
print("test_bql: OK")
