local PB=PizzaRaidPlanner
PizzaRaidPlannerDB=nil; PizzaRaidPlannerExportDB=nil; PB:InitDB(); PB.roster={}; PB.byGUID={}; PB.byName={}; PB.live={active=false,vampires={},completed={}}
local function add(name,class,spec,dps,role)
  local p={guid=name,name=name,normalizedName=name:lower(),classToken=class,spec=spec,expectedDPS=dps,bossDamage=(dps or 0)*60,online=true,connected=true,dead=false,subgroup=1}; PB.roster[#PB.roster+1]=p; PB.byGUID[name]=p; PB.byName[p.normalizedName]=p; PB.db.roleOverrides[p.normalizedName]=role
  return p
end
add("HealerOne","PRIEST",257,0,"healer"); add("TankOne","WARRIOR",73,0,"tank")
add("PumpDK","DEATHKNIGHT",252,15000,"dps"); add("SprintRogue","ROGUE",259,11000,"dps"); add("ChargeWarrior","WARRIOR",71,10000,"dps")
add("NoGapShaman","SHAMAN",263,10500,"dps"); add("FeralDruid","DRUID",103,9500,"dps"); add("RetPaladin","PALADIN",70,9000,"dps"); add("UnholyLow","DEATHKNIGHT",252,8500,"dps"); add("RogueLow","ROGUE",259,8000,"dps")
add("RangedOne","MAGE",63,12000,"dps")
add("WarlockHigh","WARLOCK",266,13000,"dps"); add("ShadowMid","PRIEST",258,11500,"dps"); add("ElementalLow","SHAMAN",262,9000,"dps")
add("BoomHigh","DRUID",102,13000,"dps"); add("BoomMid","DRUID",102,12500,"dps"); add("BoomLow","DRUID",102,12000,"dps")
add("HunterOne","HUNTER",254,11000,"dps"); add("HunterTwo","HUNTER",254,10500,"dps"); add("HunterThree","HUNTER",254,10000,"dps")
local paladins={}
for i=1,3 do local p=add("Paladin"..i,"PALADIN",65,0,"healer"); p.hasAuraMastery=true; p.hasDivineSacrifice=true; paladins[#paladins+1]=p end
local festergut={id="festergut-test",targetName="Festergut",players={}}
for _,p in ipairs(PB.roster) do festergut.players[p.guid]={dps=p.expectedDPS or 0} end
for name,value in pairs({RangedOne=15000,WarlockHigh=14000,ShadowMid=13000,HunterThree=12000,ElementalLow=11000}) do festergut.players[name]={dps=value} end
PB.GetFestergutSource=function() return festergut end
PB.ScanRoster=function() end
local plan=PB:BuildBPCPlan(); assert(plan.assignments[1].slot=="H1","healer assigned to H1")
assert(plan.source==festergut,"BPC plan records the Festergut-only benchmark")
assert(PB.byGUID.PumpDK.dataSource=="festergut-test","all BPC player rankings use the Festergut-only benchmark: "..tostring(PB.byGUID.PumpDK.dataSource))
local slots={}; for _,a in ipairs(plan.assignments) do assert(not slots[a.slot],"duplicate BPC slot"); slots[a.slot]=a.player end
assert(plan.summary.melee==8 and plan.summary.tanks==1,"tank and melee DPS counts remain distinct")
for i=1,10 do assert(slots["M"..i]~="TankOne","tank is detected but excluded from the eight melee DPS positions") end
assert(slots.M1=="PumpDK" and slots.M2=="NoGapShaman" and slots.M6=="SprintRogue" and slots.M7=="RetPaladin","M1/M2/M6/M7 balance top output and limited-mobility DPS")
assert(slots.M4=="UnholyLow" and slots.M5=="ChargeWarrior" and slots.M8=="FeralDruid" and slots.M9=="RogueLow","normal eight-player recovery footprint uses M4/M5/M8/M9")
assert(slots.M3==nil and slots.M10==nil,"M3 and M10 remain unused with eight melee-position occupants")
assert(slots.R9=="BoomHigh" and slots.R10=="BoomMid" and slots.R8=="BoomLow","Balance Druids reserve the R9/R10/R8 area")
assert(slots.R2=="HunterThree" and slots.R7=="HunterOne","top two Festergut Hunters are spread between R2 and R7")
assert(slots.R3=="RangedOne" and slots.R1=="WarlockHigh","Festergut-ranked non-reserved ranged use R3 then R1")
assert(slots.R4=="ShadowMid" and slots.R5=="ElementalLow" and slots.R6=="HunterTwo","remaining lower Festergut ranged fill unused R4-R7 positions")
assert(slots.R11==nil,"BPC ranged positions permanently stop at R10")
assert(#plan.utility.kinetics==3 and plan.utility.kinetics[1].player.name=="HunterThree" and plan.utility.kinetics[2].player.name=="HunterOne","first two Kinetic assignments follow Festergut Hunter DPS and spread anchors")
assert(plan.utility.kinetics[3].player.name=="WarlockHigh" and plan.utility.kinetics[3].source=="BPC Warlock backup rule","third Kinetic assignment uses the strongest available Warlock regardless of position")
for _,warning in ipairs(plan.warnings) do assert(not warning:find("Kinetic assignment",1,true),"three filled Kinetic assignments do not emit an unassigned warning") end
assert(#plan.utility.dsac==3 and #plan.utility.fireAM==3,"paladin cooldown orders")
assert(#plan.utilityAssignments==9,"BPC utility rows")
assert(PB:BPCRows(function(v) return tostring(v) end):find("Blood Prince Council"),"BPC TSV")
local worksheet=PB:BPCWorksheetRows(function(v) return tostring(v or "") end)
local worksheetRows={}; for line in (worksheet.."\n"):gmatch("(.-)\n") do worksheetRows[#worksheetRows+1]=line end
local function cell(rowNumber,columnNumber)
  local fields,start={},1; local line=worksheetRows[rowNumber]
  while true do local stop=line:find("\t",start,true); if not stop then fields[#fields+1]=line:sub(start); break end; fields[#fields+1]=line:sub(start,stop-1); start=stop+1 end
  return fields[columnNumber]
end
assert(cell(8,6)=="BoomLow" and cell(9,6)=="BoomHigh" and cell(10,6)=="BoomMid","sparse Boomkin slots survive A1:F10 worksheet block")
assert(cell(2,6)=="HunterThree" and cell(7,6)=="HunterOne" and cell(6,6)=="HunterTwo","Hunter R2/R7 spread and lower-band placement survive worksheet export")
assert(cell(1,4)=="PumpDK" and cell(2,4)=="NoGapShaman" and cell(6,4)=="SprintRogue" and cell(7,4)=="RetPaladin","preferred melee slots survive A1:F10 worksheet block")
assert(cell(3,4)=="—" and cell(10,4)=="—","eight-player worksheet marks unused M3 and M10 so stale names are cleared")
assert(worksheet:find("VALANAR ACTIVE",1,true) and worksheet:find("Festergut DPS",1,true) and worksheet:find("Preferred M1/M2/M6/M7",1,true) and worksheet:find("Recovery M4/M5/M8/M9",1,true),"BPC worksheet identifies Valanar phase and explains benchmark and melee placement")
add("OverflowWarrior","WARRIOR",71,7000,"dps"); add("OverflowRogue","ROGUE",259,6500,"dps")
plan=PB:BuildBPCPlan(); slots={}; for _,a in ipairs(plan.assignments) do slots[a.slot]=a.player end
assert(slots.M3 and slots.M10,"M3 and M10 activate only for ninth and tenth melee-position occupants")
print("test_bpc: OK")
