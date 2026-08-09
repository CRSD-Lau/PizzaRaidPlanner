local PB=PizzaRaidPlanner
PizzaRaidPlannerDB=nil; PizzaRaidPlannerExportDB=nil; PB:InitDB(); PB.live={active=false,vampires={},completed={}}
local function actor(total,primary)
  return {
    GetDamage=function() return total end,
    GetDamageTargets=function() return {Festergut={amount=primary,o_amt=0}} end,
    GetDamageOnTarget=function() return primary,0,primary end,
  }
end
local actors={P1=actor(100000,90000),P2=actor(80000,70000)}
local set={starttime=MOCK_TIME,name="Festergut",GetTime=function() return 60 end,GetActor=function(_,_,guid) return actors[guid] end}
Skada={GetSet=function() return set end,GetUnitSpec=setmetatable({P1=63},{__call=function(t,guid) return t[guid] end}),GetUnitRole=setmetatable({P1="DAMAGER"},{__call=function(t,guid) return t[guid] end})}
PB.roster={{guid="P1",name="MageOne",normalizedName="mageone",classToken="MAGE",online=true,connected=true},{guid="P2",name="HunterOne",normalizedName="hunterone",classToken="HUNTER",online=true,connected=true}}
PB.insideICC=nil; PB:UpdateICCState(true)
PB:ApplySkadaProfile(PB.roster[1],"raid1")
assert(PB.roster[1].spec==63 and PB.roster[1].skadaRole=="DAMAGER","Skada spec/role adapter")
PB._skadaSourceCheckedAt=nil; PB._skadaSourceCache=nil
local source=PB:GetSkadaSource()
assert(source and source.targetName=="Festergut","Skada primary target fallback")
assert(math.floor(source.players.P1.dps)==1500,"Skada boss-target DPS")
Skada=nil; PB._skadaSourceCheckedAt=nil; PB._skadaSourceCache=nil
print("test_skada: OK")
