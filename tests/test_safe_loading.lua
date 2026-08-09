local PB=PizzaRaidPlanner

local originalSelected=PB.GetSelectedFestergutHistoryEntry
local originalEnsure=PB.EnsureFestergutHistory
local originalSelect=PB.SelectFestergutHistory
local originalPrepareBPC=PB.PrepareBPCPlanForUI
local originalPrepareBQL=PB.PrepareBQLPlanForUI
local originalBuildBPC=PB.BuildBPCPlan
local originalGenerate=PB.GeneratePlan

PB.GetSelectedFestergutHistoryEntry=nil
PB.EnsureFestergutHistory=nil
PB.SelectFestergutHistory=nil
assert(PB:GetSelectedFestergutHistoryEntrySafe()==nil,"missing history getter is harmless")
assert(#PB:EnsureFestergutHistorySafe()==0,"missing history list returns an empty list")
local selected,selectError=PB:SelectFestergutHistorySafe("missing")
assert(selected==nil and selectError:find("history is unavailable",1,true),"missing history selector returns a useful error")

PB.PrepareBPCPlanForUI=nil
PB.BuildBPCPlan=function() return {safeFallback="bpc"} end
local bpc,bpcError=PB:PrepareBPCPlanSafe()
assert(bpc and bpc.safeFallback=="bpc" and bpcError==nil,"BPC safely falls back to current-raid planning")

PB.PrepareBQLPlanForUI=function() error("simulated partial load") end
local bql,bqlError=PB:PrepareBQLPlanSafe()
assert(bql==nil and bqlError:find("simulated partial load",1,true),"BQL wrapper contains planner errors")
PB.PrepareBQLPlanForUI=nil
PB.GeneratePlan=function() return {safeFallback="bql"} end
bql,bqlError=PB:PrepareBQLPlanSafe()
assert(bql and bql.safeFallback=="bql" and bqlError==nil,"BQL safely falls back to current-raid planning")

PB.GetSelectedFestergutHistoryEntry=originalSelected
PB.EnsureFestergutHistory=originalEnsure
PB.SelectFestergutHistory=originalSelect
PB.PrepareBPCPlanForUI=originalPrepareBPC
PB.PrepareBQLPlanForUI=originalPrepareBQL
PB.BuildBPCPlan=originalBuildBPC
PB.GeneratePlan=originalGenerate

print("test_safe_loading: OK")
