local PB=PizzaRaidPlanner
PizzaRaidPlannerDB=nil; PizzaRaidPlannerExportDB=nil; PB:InitDB()
local one={guid="P1",name="MageOne",normalizedName="mageone",classToken="MAGE",online=true,connected=true,dead=false}
local two={guid="P2",name="MageTwo",normalizedName="magetwo",classToken="MAGE",online=true,connected=true,dead=false}
PB.roster={one,two}; PB.byGUID={P1=one,P2=two}; PB.byName={mageone=one,magetwo=two}; PB.live={active=false,vampires={},completed={},actualFirst=nil}
PB.GetSelectedSource=function() return {id="test"} end
PB.GetBQLBenchmarkSource=function() return {id="festergut",targetName="Festergut",players={}} end
local generate=PB.GeneratePlan; local calls=0
PB.GeneratePlan=function() calls=calls+1; PB.db.latestPlan=PB.db.latestPlan or {first="P1"}; return PB.db.latestPlan end
PB:HandleEncounterEvent({event="SPELL_AURA_APPLIED",spellId=71726,destGUID="P1",sourceGUID="BQL"})
assert(not PB.live.active and PB.live.actualFirst==nil and calls==0,"BQL events do not activate optional live mode automatically")
PB:StartLive()
PB:HandleEncounterEvent({event="SPELL_AURA_APPLIED",spellId=71726,destGUID="P1",sourceGUID="BQL"})
assert(PB.live.active and PB.live.actualFirst=="P1","armed live mode detects the first vampire")
PB:HandleEncounterEvent({event="SPELL_AURA_APPLIED",spellId=70946,destGUID="P2",sourceGUID="P1"})
assert(PB.live.vampires.P2 and #PB.live.completed==1,"aura-first player bite completion")
PB:HandleEncounterEvent({event="SPELL_CAST_SUCCESS",spellId=70946,destGUID="P2",sourceGUID="P1"})
assert(#PB.live.completed==1,"cast and aura do not duplicate completed bite")
assert(calls>=3,"live changes rebuild future plan")
PB.GeneratePlan=generate
print("test_encounter: OK")
