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
assert(comp.byGUID[comp.secondary.guid].slot=="R4","second anchor occupies R4")
for _,index in ipairs({1,3,5,7}) do assert(comp.byGUID["Melee"..index].lane=="middle","Rogues and Retribution Paladins stay in Middle") end
for _,index in ipairs({2,4,6,8}) do local lane=comp.byGUID["Melee"..index].lane; assert(lane=="left" or lane=="right","other melee stay on Left or Right") end
local meleeCounts={left=0,middle=0,right=0}; for _,a in ipairs(comp.melee) do meleeCounts[a.lane]=meleeCounts[a.lane]+1 end
assert(meleeCounts.left==2 and meleeCounts.middle==4 and meleeCounts.right==2,"eight melee DPS reserve four Rogue/Paladin players for Middle and balance the rest 2 Left / 2 Right")
for _,a in ipairs(comp.ranged) do assert(a.slotNumber<=10 and a.slot~="R11","BQL ranged topology permanently stops at R10") end
assert(#plan.flatPriority==16,"worksheet-supported 1+1+2+4+8 bite capacity")
assert(#plan.waves[4]==8 and plan.waves[5]==nil,"plan stops at fifth displayed bite")
local rangedTargets=0
for _,a in ipairs(plan.assignments) do
  if a.targetPosition=="ranged" then
    rangedTargets=rangedTargets+1
    if a.wave>=2 then assert(a.biterLane==a.targetLane,"25-player same-side ranged chain") end
  end
end
assert(rangedTargets==10,"every ranged DPS scheduled before melee")
assert(table.concat(plan.warnings," | "):find("2 lower%-priority DPS"),"unassigned melee warning")
print("test_bql_25: OK")
