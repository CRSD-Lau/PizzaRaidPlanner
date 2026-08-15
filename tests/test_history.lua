local PB=PizzaRaidPlanner
PizzaRaidPlannerDB=nil; PizzaRaidPlannerExportDB=nil; PB:InitDB(); PB.live={active=false,vampires={},completed={}}

local roster={}
for i=1,20 do
  roster[i]={
    guid="History"..i,name="History"..i,normalizedName=("History"..i):lower(),
    classToken=i==20 and "PALADIN" or "MAGE",spec=i==20 and 66 or 63,
    raidIndex=i,subgroup=math.floor((i-1)/5)+1,online=true,connected=true,dead=false,
  }
end
local segment={
  id="history-seg",iccEncounter="festergut",iccSessionId="history-session",targetName="Festergut",
  endTime=900,duration=120,difficultyName="25 Player",raidSize=20,valid=true,
  result="kill",confirmedKill=true,killEvidence="test",
  players={History1={dps=9000,totalDamage=1080000,primaryDamage=1080000,healing=0}},
}
local entry=PB:RememberFestergutHistory(segment,roster)
assert(entry and #PB.db.festergutHistory==1 and #entry.roster==20,"valid Festergut stores a persistent roster-backed history entry")
assert(entry.festergutSource.players.History1.dps==9000,"history stores the Festergut-only DPS snapshot")
segment.players.History1.dps=1
assert(entry.festergutSource.players.History1.dps==9000,"history DPS is a defensive copy")

local oldScan,oldBPC,oldBQL,oldUpdate=PB.ScanRoster,PB.BuildBPCPlan,PB.GeneratePlan,PB.UpdateUI
local scans,bpcCalls,bqlCalls=0,0,0
PB.ScanRoster=function() scans=scans+1 end
PB.BuildBPCPlan=function(self)
  bpcCalls=bpcCalls+1
  assert(self.planningSourceOverride and self.planningSourceOverride.baseSourceId==entry.festergutSource.id and self.festergutSourceOverride==self.planningSourceOverride,"BPC rehearsal receives only the selected Festergut source")
  return {warnings={},source=self:GetFestergutSource()}
end
PB.GeneratePlan=function(self)
  bqlCalls=bqlCalls+1
  assert(self.planningSourceOverride and self.planningSourceOverride.baseSourceId==entry.festergutSource.id and self.festergutSourceOverride==self.planningSourceOverride,"BQL rehearsal receives only the selected Festergut source")
  return {warnings={},source=self:GetFestergutSource()}
end
PB.UpdateUI=nil
local result,err=PB:SelectFestergutHistory(entry.id)
assert(result and not err and result.rosterCount==20 and bpcCalls==1 and bqlCalls==1,"click selection rebuilds both encounter plans")
assert(PB.db.selectedFestergutHistoryId==entry.id and PB.planningSourceOverride==nil and PB.festergutSourceOverride==nil,"history selection persists while temporary planning overrides are restored")
PB:OnEvent("PLAYER_LOGIN")
assert(bpcCalls==2 and bqlCalls==2,"login automatically rebuilds a persisted Festergut selection instead of exporting a stale cached plan")
PB:ClearFestergutHistorySelection(false)
assert(PB.db.selectedFestergutHistoryId==nil and scans>=2,"current-raid mode clears the saved selection and restores the live roster")
PB.ScanRoster,PB.BuildBPCPlan,PB.GeneratePlan,PB.UpdateUI=oldScan,oldBPC,oldBQL,oldUpdate

local wipe=PB:RememberFestergutHistory({id="history-wipe",iccEncounter="festergut",iccSessionId="history-session",targetName="Festergut",endTime=950,duration=90,difficultyName="25 Player",raidSize=20,valid=true,result="wipe",confirmedKill=false,players={}},roster)
assert(wipe and not PB:IsConfirmedFestergutHistoryEntry(wipe),"valid Festergut wipe remains auditable but is not a confirmed benchmark")
local rejected,rejectedError=PB:SelectFestergutHistory(wipe.id)
assert(not rejected and rejectedError:find("confirmed Festergut kills",1,true),"Festergut wipe cannot be selected for automatic planning")

PizzaRaidPlannerDB=nil; PizzaRaidPlannerExportDB=nil; PB:InitDB()
PizzaRaidPlannerLocalHistorySeed["legacy-seg"]={roster=roster}
PB.db.segments={{id="legacy-seg",iccEncounter="festergut",iccSessionId="legacy-session",targetName="Festergut",endTime=800,duration=100,difficultyName="25 Player",raidSize=20,valid=true,players={}}}
PB:EnsureFestergutHistory()
assert(#PB.db.festergutHistory==1 and #PB.db.festergutHistory[1].roster==20 and PB.db.festergutHistory[1].rosterSource=="local legacy recovery" and PB.db.festergutHistory[1].result=="legacy-kill","pre-history Festergut is preserved as an explicitly labeled legacy kill")
PizzaRaidPlannerLocalHistorySeed["legacy-seg"]=nil
print("test_history: OK")
