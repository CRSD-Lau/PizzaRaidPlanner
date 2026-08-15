local PB=PizzaRaidPlanner
PizzaRaidPlannerDB=nil; PizzaRaidPlannerExportDB=nil; PB:InitDB(); PB.live={active=false,vampires={},completed={}}
local mage={guid="Mage",name="Mage",normalizedName="mage",classToken="MAGE",online=true,connected=true,dead=false}
PB.roster={mage}; PB.byGUID={Mage=mage}; PB.byName={mage=mage}
assert(PB:NormalizeName("Mage-Lordaeron")=="mage","player realm suffix normalization")
assert(PB:NormalizeName("Blood-Queen Lana'thel")=="blood-queen lana'thel","boss hyphen preserved")
local generate=PB.GeneratePlan; PB.GeneratePlan=function() end
PB.db.roleOverrides.mage="healer"; PB:Command("role Mage clear"); assert(PB.db.roleOverrides.mage==nil,"role clear removes override")
PB.db.positionOverrides.mage="melee"; PB:Command("position Mage clear"); assert(PB.db.positionOverrides.mage==nil,"position clear removes override")
PB:Command("capability Mage am on"); assert(PB.db.capabilityOverrides.mage.auraMastery==true,"capability on")
PB:Command("capability Mage am off"); assert(PB.db.capabilityOverrides.mage.auraMastery==false,"capability off")
PB:Command("capability Mage am clear"); assert(PB.db.capabilityOverrides.mage.auraMastery==nil,"capability clear")
PB:Command("competent Mage on"); assert(PB.db.competenceOverrides.mage==true,"competence on")
PB:Command("competent Mage clear"); assert(PB.db.competenceOverrides.mage==nil,"competence clear")
local oldRunAudible,oldShowView,oldPrint=PB.RunRosterAudibleSafe,PB.ShowView,PB.Print
local audibleShown,audiblePrinted=false,false
PB.RunRosterAudibleSafe=function() return {revision=3,audible={rosterDiff={outgoing={{name="Old"}},incoming={{name="New"}}}}} end
PB.ShowView=function(_,view) audibleShown=view=="audible" end
PB.Print=function(_,message) if message:find("Roster audible r3",1,true) then audiblePrinted=true end end
PB:Command("audible")
assert(audibleShown and audiblePrinted,"/prp audible opens the delta review and reports the shared revision")
PB.RunRosterAudibleSafe,PB.ShowView,PB.Print=oldRunAudible,oldShowView,oldPrint
PB.GeneratePlan=generate
print("test_commands: OK")
