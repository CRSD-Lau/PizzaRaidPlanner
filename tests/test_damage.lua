local PB=PizzaRaidPlanner
local oldGetSelectedSource,oldApplySourceToRoster,oldPrint=PB.GetSelectedSource,PB.ApplySourceToRoster,PB.Print
PizzaRaidPlannerDB=nil; PizzaRaidPlannerExportDB=nil; PB:InitDB(); PB.roster={}; PB.byGUID={P1={guid="P1",name="Lau",online=true,dead=false},P2={guid="P2",name="PetOwner",online=true,dead=false}}; PB.petOwners={PET="P2"}; PB.live={active=false,vampires={},completed={}}; PB.GetSelectedSource=function() return nil end; PB.ApplySourceToRoster=function() end; PB.Print=function() end
PB:StartAutomaticSegment()
PB:HandleCombatLog(1,"SWING_DAMAGE","P1","Lau",0,"BOSS","Boss",0,1000,100)
assert(PB.segment.players.P1.totalDamage==900,"swing overkill")
PB:HandleCombatLog(2,"SPELL_DAMAGE","PET","Wolf",0,"BOSS","Boss",0,123,"Bite",1,500,0)
assert(PB.segment.players.P2.totalDamage==500,"pet spell attribution")
PB:HandleCombatLog(3,"SPELL_PERIODIC_DAMAGE","P1","Lau",0,"BOSS","Boss",0,124,"Dot",1,300,0)
assert(PB.segment.players.P1.totalDamage==1200,"periodic damage")
PB:HandleCombatLog(4,"SPELL_SUMMON","P1","Lau",0,"GUARD","Ghoul",0,46584,"Raise",1)
assert(PB.petOwners.GUARD=="P1","guardian ownership")
PB.live.vampires.P1=true; PB:HandleCombatLog(5,"SPELL_DAMAGE","P1","Lau",0,"BOSS","Boss",0,125,"Buffed",1,200,0)
assert(PB.segment.players.P1.unbuffedDamage==1200,"vampire damage excluded from baseline")
assert(PB.segment.perTargetUnbuffed.P1.BOSS==1200,"vampire target damage excluded from baseline")
PB.segment=nil; PB:HandleCombatLog(6,"SPELL_HEAL","P1","Lau",0,"P2","PetOwner",0,126,"Heal",1,500,0)
assert(PB.segment==nil,"out-of-combat healing does not create a damage segment")
PB.GetSelectedSource,PB.ApplySourceToRoster,PB.Print=oldGetSelectedSource,oldApplySourceToRoster,oldPrint
print("test_damage: OK")
