local PB=PizzaRaidPlanner
local function eq(a,b,msg) assert(a==b,(msg or "").." expected "..tostring(b)..", got "..tostring(a)) end
local function setup()
  PizzaRaidPlannerDB=nil; PizzaRaidPlannerExportDB=nil; PB:InitDB(); PB.roster={}; PB.byGUID={}; PB.byName={}; PB.live={active=false,vampires={},completed={}}
  for i=1,10 do local p={guid="P"..i,name=(i==1 and "Lau" or "Dps"..i),normalizedName=(i==1 and "lau" or "dps"..i):lower(),classToken=i%2==0 and "ROGUE" or "MAGE",className="Test",subgroup=(i%5)+1,online=true,connected=true,dead=false,expectedDPS=11000-i*100,bossDamage=1000}; PB.roster[#PB.roster+1]=p; PB.byGUID[p.guid]=p; PB.byName[p.normalizedName]=p end
  local benchmark={id="test-festergut",targetName="Festergut",iccEncounter="festergut",duration=60,confidence="Good",valid=true,players={}}
  for _,p in ipairs(PB.roster) do benchmark.players[p.guid]={dps=p.expectedDPS,totalDamage=p.expectedDPS*60,primaryDamage=p.expectedDPS*60,healing=0} end
  PB.GetSelectedSource=function() return benchmark end
  PB.GetBQLBenchmarkSource=function() return benchmark end
  PB.ScanRoster=function() end
end
setup(); local plan=PB:GeneratePlan(); eq(#plan.flatPriority,10,"DPS count"); eq(plan.flatPriority[1].name,"Lau","mage anchor"); eq(#plan.waves[1],1,"wave 1"); eq(#plan.waves[2],2,"wave 2"); eq(#plan.waves[3],4,"wave 3"); eq(#plan.waves[4],2,"wave 4")
local seen={}; for _,a in ipairs(plan.assignments) do assert(not seen[a.targetGUID],"duplicate target"); seen[a.targetGUID]=true end
for _,a in ipairs(plan.assignments) do
  if a.wave>=2 and a.temporaryCrossing then
    if a.routeMode=="r6-seed" then
      eq(a.returnActor,"both","R6 seed returns the setup biter and preserves the target's home")
      eq(a.travelerGUID,a.targetGUID,"the bite target still comes to R6 at the seed point")
      eq(a.setupTravelerGUID,a.biterGUID,"R6 is the special setup traveler")
      eq(a.biterReturnLane,a.biterLane,"R6 special seed returns to the biter's right home")
      assert(a.biterMoves and a.targetMoves,"R6 stages for the seed and the target still comes to the biter")
    else
      eq(a.returnActor,"target","normal crossover returns the bite target")
      eq(a.travelerGUID,a.targetGUID,"normal crossover sends the target to the biter")
      eq(a.returnLane,a.targetLane,"traveling target returns to its own home lane")
      eq(a.biteLane,a.biterLane,"normal bite happens at the stationary biter")
      assert(a.targetMoves and not a.biterMoves and a.biterKeepsDPS,"normal biter stays planted and keeps DPSing")
    end
    assert(a.movement:find("return",1,true) and a.movement:find("DPS",1,true),"crossover carries explicit traveler and stationary-biter instructions")
  end
end
PB.roster[9].manualRole="tank"; PB.db.roleOverrides["dps9"]="tank"; PB.roster[10].manualRole="healer"; PB.db.roleOverrides["dps10"]="healer"; plan=PB:GeneratePlan(); eq(#plan.flatPriority,8,"tank/healer excluded")
PB.db.inclusionOverrides["dps9"]=true; plan=PB:GeneratePlan(); eq(#plan.flatPriority,9,"manual include")
PB.db.inclusionOverrides["dps2"]=false; plan=PB:GeneratePlan(); eq(#plan.flatPriority,8,"manual exclude")
PB.db.plannedFirst="dps3"; plan=PB:GeneratePlan(); eq(plan.assignments[1].target,"Dps3","manual first")
PB.live.active=true; PB.live.actualFirst="P4"; PB.live.vampires={P4=true,P5=true}; PB.live.completed={{biter="Dps4",biterGUID="P4",target="Dps5",targetGUID="P5",status="completed"}}; plan=PB:GeneratePlan(true); eq(plan.first,"P4","actual first reroot"); assert(plan.completedAssignments[1].targetGUID=="P5","completed retained")
PB.roster[6].dead=true; plan=PB:GeneratePlan(true); for _,a in ipairs(plan.assignments) do assert(a.targetGUID~="P6","dead replacement") end
print("test_optimizer: OK")
