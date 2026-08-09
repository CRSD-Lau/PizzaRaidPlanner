local PB=PizzaRaidPlanner
PizzaRaidPlannerDB=nil; PizzaRaidPlannerExportDB=nil; PB:InitDB(); PB.roster={}; PB.byGUID={}; PB.byName={}; PB.live={active=false,vampires={},completed={}}

local function fields(line)
  local result,start={},1
  while true do
    local stop=line:find("\t",start,true)
    if not stop then result[#result+1]=line:sub(start); return result end
    result[#result+1]=line:sub(start,stop-1); start=stop+1
  end
end
local function rows(text)
  local result={}
  for line in (text.."\n"):gmatch("(.-)\n") do result[#result+1]=fields(line) end
  return result
end
local function player(name,classToken,spec,role,position)
  local p={guid=name,name=name,normalizedName=name:lower(),classToken=classToken,spec=spec,specName=PB:GetSpecName(spec),suggestedRole=role,roleConfidence="Inspected "..PB:GetSpecName(spec).." spec",position=position,subgroup=1,online=true,connected=true,dead=false}
  PB.byGUID[p.guid]=p; PB.byName[p.normalizedName]=p; PB.roster[#PB.roster+1]=p
  return p
end

local holy=player("HolyPala","PALADIN",65,"healer","ranged")
local ret=player("RetPala","PALADIN",70,"dps","melee")
local mage=player("MageOne","MAGE",63,"dps","ranged")
local hunter=player("HunterOne","HUNTER",254,"dps","ranged")

PB.db.latestBPCPlan={generatedAt=1000,encounter="Blood Prince Council",assignments={
  {slot="H1",order=1,group="healer",player=holy.name,guid=holy.guid,class=holy.classToken,spec="Holy",role="healer",roleEvidence=holy.roleConfidence,position="ranged",subgroup=1},
  {slot="M1",order=1,group="melee/tank",player=ret.name,guid=ret.guid,class=ret.classToken,spec="Retribution",role="dps",roleEvidence=ret.roleConfidence,position="melee",subgroup=1},
  {slot="R1",order=1,group="ranged",player=mage.name,guid=mage.guid,class=mage.classToken,spec="Fire",role="dps",roleEvidence=mage.roleConfidence,position="ranged",subgroup=1},
},utilityAssignments={
  {slot="Kinetic1",order=1,group="Kinetic",player=hunter.name,guid=hunter.guid,class=hunter.classToken,spec="Marksmanship",role="dps",position="ranged",subgroup=1,capabilitySource="class rule"},
  {slot="DSac1",order=1,group="DSac",player=holy.name,guid=holy.guid,class=holy.classToken,spec="Holy",role="healer",position="ranged",subgroup=1,capabilitySource="inspected talent"},
  {slot="FireAM1",order=1,group="FireAM",player=holy.name,guid=holy.guid,class=holy.classToken,spec="Holy",role="healer",position="ranged",subgroup=1,capabilitySource="inspected talent"},
},warnings={}}

local bpcText=PB:BPCWorksheetRows(function(v) return tostring(v or "") end)
local bpc=rows(bpcText)
assert(bpc[1][1]=="H1" and bpc[1][2]=="HolyPala" and bpc[1][3]=="M1" and bpc[1][4]=="RetPala" and bpc[1][5]=="R1" and bpc[1][6]=="MageOne","BPC A1:F10 position block")
assert(bpc[10][5]=="R10" and bpc[10][6]=="—" and bpc[11][1]=="" and bpc[11][5]=="","BPC position block ends at R10 and leaves the spacer row blank")
assert(bpc[1][8]:find("VALANAR ACTIVE",1,true) and bpc[1][8]:find("A1:F10",1,true) and bpc[1][8]:find("A6:F15",1,true),"BPC phase and visible-tab position destination instruction")
assert(bpc[13][1]=="1st" and bpc[13][2]=="HunterOne" and bpc[13][3]=="1st" and bpc[13][4]=="HolyPala" and bpc[13][5]=="1st" and bpc[13][6]=="HolyPala","BPC A13:F15 ability block")
assert(bpc[13][8]:find("A13:F15",1,true) and bpc[13][8]:find("A20:F22",1,true),"BPC visible-tab ability destination instruction")
assert(bpc[20][4]=="Holy" and bpc[20][5]=="healer","BPC role/spec review")
for _,r in ipairs(bpc) do assert(#r==10,"BPC worksheet keeps fixed ten-column shape") end

local leftMelee=ret
local rightMelee=player("RogueOne","ROGUE",260,"dps","melee")
local healerAssignment={type="healer",slot="H1",slotNumber=1,lane="center",depth="middle",player=holy}
local rangedOne={type="ranged",slot="R1",slotNumber=1,lane="left",depth="front",player=mage}
local rangedTwo={type="ranged",slot="R4",slotNumber=4,lane="right",startLane="left",depth="front",player=hunter}
local meleeLeft={type="melee",slot="M1",slotNumber=1,groupOrder=1,lane="left",depth="boss",player=leftMelee}
local meleeRight={type="melee",slot="M2",slotNumber=2,groupOrder=1,lane="right",depth="boss",player=rightMelee}
local composition={healers={healerAssignment},ranged={rangedOne,rangedTwo},melee={meleeLeft,meleeRight},positions={healerAssignment,rangedOne,rangedTwo,meleeLeft,meleeRight},utility={shadowAM={{player=holy}},dsac={{player=holy}}}}
PB.db.latestPlan={generatedAt=1000,encounter="Blood-Queen Lana'thel",source={targetName="Festergut"},composition=composition,waves={
  [0]={{target="MageOne"}},
  [1]={{biter="MageOne",target="HunterOne"}},
  [2]={{biter="MageOne",target="RetPala"},{biter="HunterOne",target="RogueOne"}},
},assignments={},warnings={}}

local bqlText=PB:BQLWorksheetRows(function(v) return tostring(v or "") end)
local bql=rows(bqlText)
assert(bql[1][1]=="MageOne" and bql[1][5]=="MageOne -> HunterOne","BQL initial and first handoff in the visible-tab bite shape")
assert(bql[1][9]=="MageOne -> RetPala","BQL next-wave first assignment")
assert(bql[2][9]=="HunterOne -> RogueOne","BQL next-wave second assignment")
assert(bql[1][19]:find("A55:Q62",1,true) and bql[1][19]:find("A28:Q35",1,true),"BQL bite helper uses the shared dump tab row-55 anchor")
assert(bql[10][1]=="H1" and bql[10][2]=="HolyPala" and bql[10][3]=="" and bql[10][4]=="R1" and bql[10][5]=="MageOne" and bql[10][6]=="" and bql[10][7]=="L1" and bql[10][8]=="RetPala","BQL A10:H19 group block")
assert(bql[13][4]=="R4" and bql[13][5]=="HunterOne","BQL position block carries the R4 secondary anchor")
assert(bql[10][10]:find("A64:H73",1,true) and bql[22][9]:find("A76:G79",1,true),"BQL group and cooldown helpers follow the shifted shared-dump coordinates")
assert(bql[11][7]=="R1" and bql[11][8]=="RogueOne","BQL melee sides are compact and labelled")
assert(bql[19][4]=="R10" and bql[20][1]=="" and bql[20][4]=="","BQL position block ends at R10 and leaves the next row blank")
assert(bql[10][10]:find("A64:H73",1,true) and bql[10][10]:find("N6:U15",1,true),"BQL visible-tab group destination instruction")
assert(bql[22][1]=="1st" and bql[22][2]=="HolyPala" and bql[22][3]=="" and bql[22][4]=="Shadow AM" and bql[22][5]=="1st" and bql[22][6]=="" and bql[22][7]=="HolyPala","BQL A22:G25 utility block")
assert(bql[24][5]=="Emergency" and bql[25][5]=="","BQL utility labels preserve emergency and empty fourth row")
assert(bql[22][9]:find("A76:G79",1,true) and bql[22][9]:find("N20:T23",1,true),"BQL visible-tab utility destination instruction")
for _,r in ipairs(bql) do assert(#r==19,"BQL worksheet keeps fixed nineteen-column shape") end
print("test_worksheet_export: OK")
