local PB=PizzaRaidPlanner
PizzaRaidPlannerDB=nil; PizzaRaidPlannerExportDB=nil; PB:InitDB(); PB.roster={}; PB.byGUID={}; PB.byName={}; PB.live={active=false,vampires={},completed={}}
local function add(name,class,spec,dps,role)
  local p={guid=name,name=name,normalizedName=name:lower(),classToken=class,spec=spec,online=true,connected=true,dead=false,subgroup=((#PB.roster)%5)+1,expectedDPS=dps>0 and dps or nil,bossDamage=dps*60,raidIndex=#PB.roster+1}
  PB.roster[#PB.roster+1]=p; PB.byGUID[p.guid]=p; PB.byName[p.normalizedName]=p; PB.db.roleOverrides[p.normalizedName]=role or "dps"; return p
end
add("MageOne","MAGE",63,14000); add("MageTwo","MAGE",63,13800)
for i=1,2 do add("Warlock"..i,"WARLOCK",266,13600-i*50) end
for i=1,3 do add("Hunter"..i,"HUNTER",253,13400-i*50) end
add("Boomkin","DRUID",102,13200); add("Shadow","PRIEST",258,13100); add("Elemental","SHAMAN",262,13000)
local meleeClasses={
  {"ROGUE",259},{"WARRIOR",71},{"PALADIN",70},{"DEATHKNIGHT",252},
  {"ROGUE",259},{"SHAMAN",263},{"PALADIN",70},{"WARRIOR",71},
}
for i,entry in ipairs(meleeClasses) do add("Melee"..i,entry[1],entry[2],14500-i*100) end
add("TankOne","WARRIOR",73,0,"tank"); add("TankTwo","PALADIN",66,0,"tank")
for i=1,5 do add("Healer"..i,i==1 and "PALADIN" or "PRIEST",i==1 and 65 or 257,0,"healer") end
PB.ScanRoster=function() end
local benchmark={id="test25",targetName="Festergut",iccEncounter="festergut",duration=60,confidence="Good",valid=true,players={}}
for _,p in ipairs(PB.roster) do benchmark.players[p.guid]={dps=p.expectedDPS,totalDamage=(p.expectedDPS or 0)*60,primaryDamage=(p.expectedDPS or 0)*60,healing=0} end
PB.GetSelectedSource=function() return benchmark end
PB.GetBQLBenchmarkSource=function() return benchmark end
local plan=PB:GeneratePlan(); local comp=plan.composition
assert(#PB.roster==25 and #comp.ranged==10 and #comp.healers==5 and #comp.melee==8 and #comp.tanks==2,"typical 10 ranged DPS, 8 melee DPS, 2 tank, 5 healer composition mapped")
assert(comp.byGUID[comp.secondary.guid].slot=="R6","second vampire has a physical right-side home at R6")
for _,index in ipairs({1,4,5}) do assert(comp.byGUID["Melee"..index].lane=="middle","Rogues and DPS Death Knights are hard-Middle") end
for _,index in ipairs({2,3,6,7,8}) do local lane=comp.byGUID["Melee"..index].lane; assert(lane=="left" or lane=="right","Retribution and remaining melee stay on balanced sides") end
local meleeCounts={left=0,middle=0,right=0}; for _,a in ipairs(comp.melee) do meleeCounts[a.lane]=meleeCounts[a.lane]+1 end
assert(meleeCounts.left==3 and meleeCounts.middle==3 and meleeCounts.right==2,"eight melee DPS stay within one player across Left / Middle / Right")
local rangedCounts={left=0,right=0}
for _,a in ipairs(comp.ranged) do
  assert(a.slotNumber<=10 and a.slot~="R11","BQL ranged topology permanently stops at R10")
  assert((a.slotNumber<=5 and a.lane=="left") or (a.slotNumber>=6 and a.lane=="right"),"R1-R5 are left homes and R6-R10 are right homes")
  rangedCounts[a.lane]=rangedCounts[a.lane]+1
end
assert(rangedCounts.left==5 and rangedCounts.right==5,"ten ranged DPS split evenly across the physical left and right homes")
assert(#plan.flatPriority==16,"worksheet-supported 1+1+2+4+8 bite capacity")
assert(#plan.waves[4]==8 and plan.waves[5]==nil,"plan stops at fifth displayed bite")
local function waveLaneCounts(wave)
  local counts={left=0,right=0,middle=0}
  for _,a in ipairs(wave or {}) do if counts[a.targetLane]~=nil then counts[a.targetLane]=counts[a.targetLane]+1 end end
  return counts.left,counts.right,counts.middle
end
local waveTwoLeft,waveTwoRight=waveLaneCounts(plan.waves[2])
local waveFourLeft,waveFourRight,waveFourMiddle=waveLaneCounts(plan.waves[4])
assert(waveTwoLeft==1 and waveTwoRight==1,"third displayed bite seeds one melee vampire on each side")
for _,a in ipairs(plan.waves[2]) do assert(a.biterType=="ranged" and a.targetType=="melee" and a.chainPurpose=="ranged-to-melee-seed","third displayed bite is an explicit ranged-to-melee seed") end

local vampireCategories={['ranged:left']=0,['ranged:right']=0,['melee:left']=0,['melee:right']=0}
for wave=0,3 do
  for _,a in ipairs(plan.waves[wave] or {}) do
    local key=(a.targetType or (comp.byGUID[a.targetGUID] and comp.byGUID[a.targetGUID].type))..":"..a.targetLane
    if vampireCategories[key]~=nil then vampireCategories[key]=vampireCategories[key]+1 end
  end
end
for category,count in pairs(vampireCategories) do assert(count==2,"fourth displayed bite creates two vampire branches in "..category) end
assert(math.abs(waveFourLeft-waveFourRight)<=1 and waveFourLeft+waveFourRight+waveFourMiddle==8,"fifth displayed bite keeps new targets spatially balanced")
local openingCrossing
local exactClassMatches=0
for _,a in ipairs(plan.assignments) do
  if a.targetPosition=="ranged" then
    if a.wave>=2 then
      assert(a.movement:find("Bloodbolt Whirl",1,true),"25-player ranged bite returns to home-side whirl spacing")
    end
  end
  if a.temporaryCrossing then
    assert(a.movement:find("return",1,true),"25-player cross-room route includes the correct return")
    assert(a.returnActor=="target" and a.travelerGUID==a.targetGUID and a.returnLane==a.targetLane and a.biteLane==a.biterLane and a.targetMoves and not a.biterMoves and a.biterKeepsDPS,"25-player crossover sends the target to a stationary biter")
  end
  if a.wave==1 and a.targetGUID==comp.secondary.guid then openingCrossing=a end
  if a.wave==4 then
    assert(a.biterType==a.targetType,"fifth displayed bite keeps ranged-to-ranged and melee-to-melee")
    if a.biterType=="ranged" then assert(a.biterLane==a.targetLane,"fifth displayed ranged bite stays on the same side") end
    assert(not ((a.biterLane=="left" and a.targetLane=="right") or (a.biterLane=="right" and a.targetLane=="left")),"fifth displayed bite never sends a target across hard left/right lanes")
    if a.exactClassMatch then exactClassMatches=exactClassMatches+1 end
  end
end
assert(openingCrossing and openingCrossing.biterLane=="left" and openingCrossing.targetLane=="right" and openingCrossing.targetSlot=="R6" and openingCrossing.routeLabel=="R6 TO R1 > HOME R","second bite spreads the ranged branch from left to right")
assert(comp.byGUID[comp.secondary.guid].lane=="right","R6 remains the right-side ranged anchor after the second bite")
assert(exactClassMatches>=2,"fifth displayed bite preserves available same-class visual matches")
local hunterMatch=false
for _,a in ipairs(plan.waves[4]) do if a.biterClass=="HUNTER" and a.targetClass=="HUNTER" then hunterMatch=true end end
assert(hunterMatch,"a Hunter bites a same-side Hunter when the roster offers that match")
assert(table.concat(plan.warnings," | "):find("2 lower%-priority DPS"),"unassigned melee warning")
PB.byGUID.Melee6.classToken="DRUID"; PB.byGUID.Melee6.spec=103
PB.byGUID.Melee8.classToken="DRUID"; PB.byGUID.Melee8.spec=103
PB:ApplySourceToRoster(benchmark,true)
local feralComp=PB:BuildBQLComposition(PB:GetRankedPlayers(false))
assert(feralComp.byGUID.Melee6.lane=="middle","Feral above the bottom Festergut quartile keeps rear access in Middle")
assert(feralComp.byGUID.Melee8.lane=="left" or feralComp.byGUID.Melee8.lane=="right","bottom-quartile Feral moves to a side to reduce center flame risk")
for _,playerName in ipairs({"Boomkin","Warlock1","Warlock2","Elemental"}) do PB.byGUID[playerName].classToken="DRUID"; PB.byGUID[playerName].spec=102 end
PB:ApplySourceToRoster(benchmark,true)
local fourBoomkinComp=PB:BuildBQLComposition(PB:GetRankedPlayers(false))
local boomkinSides={left=0,right=0}
for _,playerName in ipairs({"Boomkin","Warlock1","Warlock2","Elemental"}) do
  local lane=fourBoomkinComp.byGUID[playerName].lane
  boomkinSides[lane]=boomkinSides[lane]+1
end
assert(boomkinSides.left==2 and boomkinSides.right==2,"four Balance Druids split into a local pair on each side")
print("test_bql_25: OK")
