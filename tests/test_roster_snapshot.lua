local PB=PizzaRaidPlanner
PizzaRaidPlannerDB=nil; PizzaRaidPlannerExportDB=nil; PB:InitDB()
PB.roster={}
for i=1,20 do
  PB.roster[i]={guid="Saved"..i,name="Saved"..i,normalizedName=("Saved"..i):lower(),classToken=i==20 and "PALADIN" or "MAGE",spec=i==20 and 66 or 63,raidIndex=i,subgroup=math.floor((i-1)/5)+1,online=true,connected=true,dead=false,expectedDPS=10000-i}
end
PB:RememberRaidTestRoster()
assert(#PB.db.lastRaidRoster==20 and PB.db.lastRaidRosterSavedAt==PB:Now(),"full raid roster is remembered independently of the latest plan")
PB.db.latestPlan={composition={positions={}}}
local recovered=PB:GetSavedRaidTestRoster()
assert(#recovered==20 and recovered[1].name=="Saved1" and recovered[20].name=="Saved20","dedicated saved roster wins over a later empty solo plan")
recovered[1].name="Changed"
assert(PB.db.lastRaidRoster[1].name=="Saved1","saved raid test returns defensive player copies")
PB.roster={PB.roster[1]}
PB:RememberRaidTestRoster()
assert(#PB.db.lastRaidRoster==20,"partial or solo roster cannot overwrite the last full raid")
print("test_roster_snapshot: OK")
