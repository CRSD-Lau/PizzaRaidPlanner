local PB = PizzaRaidPlanner

local function clean(v) return tostring(v or ""):gsub("[\r\n\t]"," "):gsub("[%z\1-\8\11\12\14-\31]","") end
local function csv(v) v=clean(v); if v:find('[,"]') then return '"'..v:gsub('"','""')..'"' end return v end
local function tsv(v) return clean(v) end
local function jsonString(v) return '"'..tostring(v or ""):gsub('\\','\\\\'):gsub('"','\\"'):gsub('\n','\\n'):gsub('\r','\\r'):gsub('\t','\\t')..'"' end

function PB:JSON(value)
  local kind=type(value)
  if kind=="nil" then return "null"
  elseif kind=="boolean" then return value and "true" or "false"
  elseif kind=="number" then return tostring(value)
  elseif kind=="string" then return jsonString(value)
  elseif kind~="table" then return jsonString(tostring(value)) end
  local isArray,max,count=true,0,0
  for k in pairs(value) do
    count=count+1
    if type(k)~="number" or k<1 or k~=math.floor(k) then isArray=false break end
    if k>max then max=k end
  end
  if isArray and count~=max then isArray=false end
  local out={}
  if isArray then
    for i=1,max do out[#out+1]=self:JSON(value[i]) end
    return "["..table.concat(out,",").."]"
  end
  for k,v in pairs(value) do out[#out+1]=jsonString(k)..":"..self:JSON(v) end
  table.sort(out)
  return "{"..table.concat(out,",").."}"
end

function PB:Base64(data)
  local alphabet='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
  return ((data:gsub('.', function(x)
    local r,b='',x:byte()
    for i=8,1,-1 do r=r..(b%2^i-b%2^(i-1)>0 and '1' or '0') end
    return r
  end)..'0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
    if #x<6 then return '' end
    local c=0
    for i=1,6 do c=c+(x:sub(i,i)=='1' and 2^(6-i) or 0) end
    return alphabet:sub(c+1,c+1)
  end)..({ '', '==', '=' })[#data%3+1])
end

-- Long-form rows remain available for CSV/JSON diagnostics. The normal TSV
-- export is a worksheet-shaped copy surface whose rectangular blocks match the
-- unmerged data areas in the raid team's main BPC & BQL worksheet.
local plannerHeaders={"SchemaVersion","GeneratedAt","Encounter","RecordType","Order","Wave","WaveSlot","Slot","Group","Lane","Depth","Player","GUID","Class","Role","Subgroup","Biter","BiterSlot","BiterLane","Target","TargetSlot","TargetLane","TargetDepth","ExpectedDPS","DPSRank","Capability","CapabilitySource","Movement","Status","Notes"}
local rosterHeaders={"SchemaVersion","GeneratedAt","Name","GUID","Class","Spec","Role","RoleSource","Position","Subgroup","Online","Alive","TotalDamage","BossDamage","RawDPS","ExpectedDPS","DataSource","Confidence","Eligible","ExclusionReason","ManualPriority"}
local function row(values,formatter,columnCount)
  local result={}
  for i=1,(columnCount or #values) do result[#result+1]=formatter(values[i]==nil and "" or values[i]) end
  return table.concat(result,formatter==csv and "," or "\t")
end
local function namedRow(data,formatter)
  local values={}
  for i,header in ipairs(plannerHeaders) do values[i]=data[header]==nil and "" or data[header] end
  return row(values,formatter,#plannerHeaders)
end
local function sortedPositions(positions)
  local result={}; for i,p in ipairs(positions or {}) do result[i]=p end
  local order={healer=1,ranged=2,melee=3}
  table.sort(result,function(a,b)
    local ao,bo=order[a.type] or 9,order[b.type] or 9
    if ao~=bo then return ao<bo end
    return (a.slotNumber or 99)<(b.slotNumber or 99)
  end)
  return result
end

function PB:PlanRows(formatter)
  local plan=self.db.latestPlan or self:GeneratePlan()
  local composition=plan.composition or self:BuildBQLComposition()
  local rows={row(plannerHeaders,formatter,#plannerHeaders)}
  local source=plan.source or {}
  rows[#rows+1]=namedRow({SchemaVersion=PB.SCHEMA_VERSION,GeneratedAt=plan.generatedAt,Encounter=plan.encounter,RecordType="METADATA",Status=plan.mode,Notes="Source: "..clean(source.id).." | Target: "..clean(source.targetName).." | Duration: "..clean(source.duration)},formatter)
  for _,a in ipairs(sortedPositions(composition.positions)) do
    local p=a.player
    local positionMovement=""
    if a.seedLane then positionMovement="Home "..(a.lane or "unknown").."; temporarily seed "..a.seedLane.."; return "..(a.returnLane or a.lane or "home")
    elseif a.startLane then positionMovement="Start "..a.startLane.."; settle "..a.lane end
    rows[#rows+1]=namedRow({SchemaVersion=PB.SCHEMA_VERSION,GeneratedAt=plan.generatedAt,Encounter=plan.encounter,RecordType="POSITION",Order=a.slotNumber,Slot=a.slot,Group=a.type,Lane=a.lane,Depth=a.depth,Player=p.name,GUID=p.guid,Class=p.classToken,Role=self:ResolveRole(p),Subgroup=p.subgroup,DPSRank=a.biteRank,Movement=positionMovement,Status="planned",Notes=a.note},formatter)
  end
  for i,item in ipairs(composition.utility.shadowAM or {}) do
    local p=item.player
    rows[#rows+1]=namedRow({SchemaVersion=PB.SCHEMA_VERSION,GeneratedAt=plan.generatedAt,Encounter=plan.encounter,RecordType="UTILITY",Order=i,Slot="ShadowAM"..i,Group="Shadow AM",Player=p.name,GUID=p.guid,Class=p.classToken,Role=self:ResolveRole(p),Subgroup=p.subgroup,Capability="auraMastery",CapabilitySource=item.source,Status="planned",Notes="Shadow Resistance Aura Mastery order"},formatter)
  end
  for i,item in ipairs(composition.utility.dsac or {}) do
    local p=item.player; local emergency=i==3
    rows[#rows+1]=namedRow({SchemaVersion=PB.SCHEMA_VERSION,GeneratedAt=plan.generatedAt,Encounter=plan.encounter,RecordType="UTILITY",Order=i,Slot=emergency and "AirDSacEmergency" or "AirDSac"..i,Group="Airphase DSac",Player=p.name,GUID=p.guid,Class=p.classToken,Role=self:ResolveRole(p),Subgroup=p.subgroup,Capability="divineSacrifice",CapabilitySource=item.source,Status=emergency and "emergency" or "planned",Notes=emergency and "Emergency backup" or "Airphase Divine Sacrifice order"},formatter)
  end
  local biteOrder=0
  for _,a in ipairs(plan.assignments or {}) do
    biteOrder=biteOrder+1
    rows[#rows+1]=namedRow({SchemaVersion=PB.SCHEMA_VERSION,GeneratedAt=plan.generatedAt,Encounter=plan.encounter,RecordType="BITE",Order=biteOrder,Wave=a.wave,WaveSlot=a.slot,Slot="W"..a.wave.."."..a.slot,Group="Bite",Biter=a.biter,BiterSlot=a.biterSlot,BiterLane=a.biterLane,Target=a.target,TargetSlot=a.targetSlot,TargetLane=a.targetLane,TargetDepth=a.targetDepth,ExpectedDPS=a.expectedDPS,DPSRank=a.dpsRank,Movement=a.movement,Status=a.status},formatter)
  end
  for i,w in ipairs(plan.warnings or {}) do
    rows[#rows+1]=namedRow({SchemaVersion=PB.SCHEMA_VERSION,GeneratedAt=plan.generatedAt,Encounter=plan.encounter,RecordType="WARNING",Order=i,Status="review",Notes=w},formatter)
  end
  return table.concat(rows,"\n")
end

function PB:RosterRows(formatter)
  local rows={row(rosterHeaders,formatter,#rosterHeaders)}
  for _,p in ipairs(self.roster) do
    local eligible,reason=self:IsEligible(p,self.live.active)
    rows[#rows+1]=row({PB.SCHEMA_VERSION,self:Now(),p.name,p.guid,p.classToken,self:GetSpecName(p),self:ResolveRole(p),p.roleConfidence,p.position,p.subgroup,p.online,not p.dead,p.damage,p.bossDamage,p.dps,p.expectedDPS,p.dataSource,p.confidence,eligible,reason,self:GetOverride("manualPriorities",p.name)},formatter,#rosterHeaders)
  end
  return table.concat(rows,"\n")
end

function PB:BPCRows(formatter)
  local plan=self.db.latestBPCPlan or self:BuildBPCPlan()
  local rows={row(plannerHeaders,formatter,#plannerHeaders)}
  for _,a in ipairs(plan.assignments or {}) do
    rows[#rows+1]=namedRow({SchemaVersion=PB.SCHEMA_VERSION,GeneratedAt=plan.generatedAt,Encounter=plan.encounter,RecordType="POSITION",Order=a.order,Slot=a.slot,Group=a.group,Player=a.player,GUID=a.guid,Class=a.class,Role=a.role,Subgroup=a.subgroup,Status="planned"},formatter)
  end
  for _,a in ipairs(plan.utilityAssignments or {}) do
    rows[#rows+1]=namedRow({SchemaVersion=PB.SCHEMA_VERSION,GeneratedAt=plan.generatedAt,Encounter=plan.encounter,RecordType="UTILITY",Order=a.order,Slot=a.slot,Group=a.group,Player=a.player,GUID=a.guid,Class=a.class,Role=a.role,Subgroup=a.subgroup,Capability=a.capability,CapabilitySource=a.capabilitySource,Status="planned"},formatter)
  end
  for i,w in ipairs(plan.warnings or {}) do
    rows[#rows+1]=namedRow({SchemaVersion=PB.SCHEMA_VERSION,GeneratedAt=plan.generatedAt,Encounter=plan.encounter,RecordType="WARNING",Order=i,Status="review",Notes=w},formatter)
  end
  return table.concat(rows,"\n")
end

local function setCell(matrix,rowNumber,columnNumber,value)
  matrix[rowNumber]=matrix[rowNumber] or {}
  matrix[rowNumber][columnNumber]=value or ""
end

local function worksheetText(matrix,formatter,columnCount)
  local rows={}
  local lastRow=0
  for rowNumber in pairs(matrix) do if rowNumber>lastRow then lastRow=rowNumber end end
  for rowNumber=1,lastRow do rows[#rows+1]=row(matrix[rowNumber] or {},formatter,columnCount) end
  return table.concat(rows,"\n")
end

local function assignedNames(assignments,prefix)
  local values={}
  for _,assignment in ipairs(assignments or {}) do
    local slotPrefix=assignment.slot and assignment.slot:sub(1,1)
    if slotPrefix==prefix then values[assignment.order]=assignment.player end
  end
  return values
end

local function utilityNames(assignments,group)
  local values={}
  for _,assignment in ipairs(assignments or {}) do if assignment.group==group then values[assignment.order]=assignment.player end end
  return values
end

function PB:BPCWorksheetRows(formatter)
  local plan=self.db.latestBPCPlan or self:BuildBPCPlan()
  local matrix={}
  local healers=assignedNames(plan.assignments,"H")
  local melee=assignedNames(plan.assignments,"M")
  local ranged=assignedNames(plan.assignments,"R")
  -- A1:F10 has the exact shape of the visible BPC tab's A6:F15 data area. Include slot labels so
  -- the entire block can be copied in one values-only paste and stale names are
  -- cleared when the current composition has fewer players in a section.
  for i=1,10 do
    setCell(matrix,i,1,i<=5 and ("H"..i) or "")
    setCell(matrix,i,2,healers[i] or (i<=5 and "—" or ""))
    setCell(matrix,i,3,i<=10 and ("M"..i) or "")
    setCell(matrix,i,4,melee[i] or (i<=10 and "—" or ""))
    setCell(matrix,i,5,"R"..i)
    setCell(matrix,i,6,ranged[i] or "—")
  end
  setCell(matrix,1,8,"VALANAR ACTIVE / EMPOWERED SHOCK VORTEX | COPY A1:F10 -> 'Blood Prince Council'!A6:F15 | Ctrl+Shift+V")

  -- A13:F15 matches the visible BPC tab's A20:F22 cooldown data area.
  local kinetics=utilityNames(plan.utilityAssignments,"Kinetic")
  local dsac=utilityNames(plan.utilityAssignments,"DSac")
  local fireAM=utilityNames(plan.utilityAssignments,"FireAM")
  local ordinals={"1st","2nd","3rd"}
  for i=1,3 do
    local rowNumber=12+i
    setCell(matrix,rowNumber,1,ordinals[i])
    setCell(matrix,rowNumber,2,kinetics[i] or "—")
    setCell(matrix,rowNumber,3,ordinals[i])
    setCell(matrix,rowNumber,4,dsac[i] or "—")
    setCell(matrix,rowNumber,5,ordinals[i])
    setCell(matrix,rowNumber,6,fireAM[i] or "—")
  end
  setCell(matrix,13,8,"COPY A13:F15 -> 'Blood Prince Council'!A20:F22 | Ctrl+Shift+V")

  local reviewStart=18
  setCell(matrix,reviewStart,1,"BPC ROLE / SPEC REVIEW")
  local reviewHeaders={"Assignment","Player","Class","Spec","Role","Position","Raid Group","Evidence"}
  for columnNumber,label in ipairs(reviewHeaders) do setCell(matrix,reviewStart+1,columnNumber,label) end
  local reviewRow=reviewStart+2
  local reviewAssignments={}
  for i,assignment in ipairs(plan.assignments or {}) do reviewAssignments[i]=assignment end
  local groupOrder={H=1,M=2,R=3}
  table.sort(reviewAssignments,function(a,b)
    local ap,bp=(a.slot or ""):sub(1,1),(b.slot or ""):sub(1,1)
    if (groupOrder[ap] or 9)~=(groupOrder[bp] or 9) then return (groupOrder[ap] or 9)<(groupOrder[bp] or 9) end
    return (a.order or 99)<(b.order or 99)
  end)
  for _,assignment in ipairs(reviewAssignments) do
    local evidence=assignment.roleEvidence or (self.byGUID[assignment.guid] and self.byGUID[assignment.guid].roleConfidence) or ""
    if assignment.placement then evidence=evidence.." | "..assignment.placement end
    local values={assignment.slot,assignment.player,assignment.class,assignment.spec or self:GetSpecName(self.byGUID[assignment.guid]),assignment.role,assignment.position,assignment.subgroup,evidence}
    for columnNumber,value in ipairs(values) do setCell(matrix,reviewRow,columnNumber,value) end
    reviewRow=reviewRow+1
  end
  for _,assignment in ipairs(plan.utilityAssignments or {}) do
    local evidence=(assignment.roleEvidence or "").."; "..(assignment.capabilitySource or "")
    local values={assignment.slot,assignment.player,assignment.class,assignment.spec or self:GetSpecName(self.byGUID[assignment.guid]),assignment.role,assignment.position,assignment.subgroup,evidence}
    for columnNumber,value in ipairs(values) do setCell(matrix,reviewRow,columnNumber,value) end
    reviewRow=reviewRow+1
  end
  reviewRow=reviewRow+1; setCell(matrix,reviewRow,1,"WARNINGS - review before copying")
  for i,warning in ipairs(plan.warnings or {}) do setCell(matrix,reviewRow+i,1,"WARNING"); setCell(matrix,reviewRow+i,2,warning) end
  return worksheetText(matrix,formatter,10)
end

local function compositionNames(assignments)
  local values={}
  for _,assignment in ipairs(assignments or {}) do values[assignment.slotNumber or (#values+1)]=assignment.player.name end
  return values
end

local function meleeLaneNames(assignments,lane)
  local values={}
  for _,assignment in ipairs(assignments or {}) do if assignment.lane==lane then values[assignment.groupOrder or (#values+1)]=assignment.player.name end end
  return values
end

local function utilityPlayerNames(assignments)
  local values={}
  for i,assignment in ipairs(assignments or {}) do values[i]=assignment.player.name end
  return values
end

local function putBiteColumn(matrix,startColumn,startRow,wave)
  for i,assignment in ipairs(wave or {}) do
    -- The 3.3.5 client replaces the Unicode arrow with "?" when the EditBox
    -- selection is copied to Windows. Keep this ASCII so the worksheet receives
    -- an unambiguous bite handoff. Position slots already encode the travel
    -- pattern, so the publish block deliberately omits internal route labels.
    local label=assignment.biter.." -> "..assignment.target
    setCell(matrix,startRow+i-1,startColumn,label)
  end
end

function PB:BQLWorksheetRows(formatter)
  local plan=self.db.latestPlan or self:GeneratePlan()
  local composition=plan.composition or self:BuildBQLComposition()
  local matrix={}
  local dumpStart=PB.WORKSHEET_BQL_DUMP_ROW or 55
  local function dumpRow(relativeRow) return dumpStart+relativeRow-1 end
  -- A55:Q62 matches the visible BQL tab's five bite columns at A28:Q35.
  -- BPC occupies rows 1-53 of the same WoW TSV Dump tab; row 54 stays blank.
  -- The blank columns preserve the four-column spacing between each wave.
  if plan.waves and plan.waves[0] and plan.waves[0][1] then setCell(matrix,1,1,plan.waves[0][1].target) end
  putBiteColumn(matrix,5,1,plan.waves and plan.waves[1])
  putBiteColumn(matrix,9,1,plan.waves and plan.waves[2])
  putBiteColumn(matrix,13,1,plan.waves and plan.waves[3])
  putBiteColumn(matrix,17,1,plan.waves and plan.waves[4])
  setCell(matrix,1,19,"COPY A"..dumpRow(1)..":Q"..dumpRow(8).." -> 'Blood Queen Lana'Thel'!A28:Q35 | Ctrl+Shift+V")

  -- Relative A10:H19 (dump A64:H73) matches N6:U15: healer slots, a separator, ranged slots, another
  -- separator, and compact Left/Middle/Right melee-side labels.
  local healers=compositionNames(composition.healers)
  local ranged=compositionNames(composition.ranged)
  local left=meleeLaneNames(composition.melee,"left")
  local middle=meleeLaneNames(composition.melee,"middle")
  local right=meleeLaneNames(composition.melee,"right")
  local meleeRows={}
  for _,lane in ipairs({{names=left,prefix="L"},{names=middle,prefix="MID"},{names=right,prefix="R"}}) do
    for i,name in ipairs(lane.names) do meleeRows[#meleeRows+1]={label=lane.prefix..i,name=name} end
  end
  for i=1,10 do
    local rowNumber=9+i
    setCell(matrix,rowNumber,1,i<=5 and ("H"..i) or "")
    setCell(matrix,rowNumber,2,healers[i] or (i<=5 and "—" or ""))
    setCell(matrix,rowNumber,3,"")
    setCell(matrix,rowNumber,4,"R"..i)
    setCell(matrix,rowNumber,5,ranged[i] or "—")
    setCell(matrix,rowNumber,6,"")
    setCell(matrix,rowNumber,7,meleeRows[i] and meleeRows[i].label or "")
    setCell(matrix,rowNumber,8,meleeRows[i] and meleeRows[i].name or "")
  end
  setCell(matrix,10,10,"COPY A"..dumpRow(10)..":H"..dumpRow(19).." -> 'Blood Queen Lana'Thel'!N6:U15 | Ctrl+Shift+V")

  -- Relative A22:G25 (dump A76:G79) matches N20:T23. The fixed four-row
  -- shape carries the encounter cadence: four Shadow AM links before air one,
  -- three Shadow AM links before air two, then two Shadow AM links after air
  -- two. DSac is reserved for the two Bloodbolt Whirls. Column U on the live
  -- sheet is a static cooldown legend, so the seven-column sync stays valid.
  local cooldowns=composition.utility and composition.utility.cooldowns
  if not cooldowns then cooldowns=self:BuildBQLCooldownPlan(composition.utility and composition.utility.shadowAM,composition.utility and composition.utility.dsac) end
  for i=1,4 do
    local rowNumber=21+i
    local item=cooldowns.rows and cooldowns.rows[i] or {}
    setCell(matrix,rowNumber,1,item.leftEvent or "")
    setCell(matrix,rowNumber,2,item.leftPlayers or "—")
    setCell(matrix,rowNumber,3,"")
    setCell(matrix,rowNumber,4,item.leftCooldown or "")
    setCell(matrix,rowNumber,5,item.rightEvent or "")
    setCell(matrix,rowNumber,6,"")
    setCell(matrix,rowNumber,7,item.rightPlayers or "—")
  end
  setCell(matrix,22,9,"COPY A"..dumpRow(22)..":G"..dumpRow(25).." -> 'Blood Queen Lana'Thel'!N20:T23 | Ctrl+Shift+V")

  local reviewStart=28
  setCell(matrix,reviewStart,1,"BQL ROLE / SPEC / POSITION REVIEW")
  local reviewHeaders={"Slot","Player","Class","Spec","Role","Position","Lane / Depth","Evidence"}
  for columnNumber,label in ipairs(reviewHeaders) do setCell(matrix,reviewStart+1,columnNumber,label) end
  local reviewRow=reviewStart+2
  for _,assignment in ipairs(sortedPositions(composition.positions)) do
    local p=assignment.player
    local evidence=p.roleConfidence or ""
    if assignment.note then evidence=evidence..(evidence~="" and " | " or "")..assignment.note end
    local values={assignment.slot,p.name,p.classToken,self:GetSpecName(p),self:ResolveRole(p),p.position,(assignment.lane or "")..(assignment.depth and (" / "..assignment.depth) or ""),evidence}
    for columnNumber,value in ipairs(values) do setCell(matrix,reviewRow,columnNumber,value) end
    reviewRow=reviewRow+1
  end
  reviewRow=reviewRow+1; setCell(matrix,reviewRow,1,"WARNINGS - review before copying")
  for i,warning in ipairs(plan.warnings or {}) do setCell(matrix,reviewRow+i,1,"WARNING"); setCell(matrix,reviewRow+i,2,warning) end
  return worksheetText(matrix,formatter,19)
end

local function utilityText(label,items,regularCount)
  local parts={}
  for i,item in ipairs(items or {}) do
    local suffix=regularCount and i>regularCount and " (emergency)" or ""
    parts[#parts+1]=i..". "..item.player.name..suffix
  end
  return label..": "..(#parts>0 and table.concat(parts," | ") or "REVIEW - none detected")
end

function PB:BPCDiscordText()
  local plan=self.db.latestBPCPlan or self:BuildBPCPlan(); local groups={H={},M={},R={}}
  for _,a in ipairs(plan.assignments or {}) do
    local prefix=a.slot:sub(1,1); groups[prefix][a.order]=a.slot..": "..a.player
  end
  local function compactGroup(group,limit)
    local result={}; for i=1,limit do if group[i] then result[#result+1]=group[i] end end; return table.concat(result," | ")
  end
  local lines={
    "Blood Prince Council Positions - Valanar Active / Empowered Shock Vortex",
    "Healers - "..compactGroup(groups.H,5),
    "Melee/Tanks - "..compactGroup(groups.M,10),
    "Ranged - "..compactGroup(groups.R,10),
    utilityText("Kinetic Orbs",plan.utility.kinetics),
    utilityText("Divine Sacrifice",plan.utility.dsac),
    utilityText("Fire Aura Mastery",plan.utility.fireAM),
  }
  for _,w in ipairs(plan.warnings or {}) do lines[#lines+1]="Review: "..w end
  return table.concat(lines,"\n")
end

local function compactPositions(composition,kind,label)
  local parts={}
  for _,a in ipairs(composition[kind] or {}) do
    local detail=a.lane and (" ["..a.lane..(a.depth and "/"..a.depth or "").."]") or ""
    parts[#parts+1]=a.slot..": "..a.player.name..detail
  end
  return label.." - "..table.concat(parts," | ")
end

local function splitDiscord(lines)
  local chunks,cur={},""
  for _,line in ipairs(lines) do
    if #cur+#line+1>1900 then chunks[#chunks+1]=cur; cur=line else cur=(cur=="" and line or cur.."\n"..line) end
  end
  if cur~="" then chunks[#chunks+1]=cur end
  for i,c in ipairs(chunks) do if #chunks>1 then chunks[i]="("..i.."/"..#chunks..")\n"..c end end
  return table.concat(chunks,"\n\n")
end

function PB:DiscordText()
  local plan=self.db.latestPlan or self:GeneratePlan(); local composition=plan.composition or {}
  local lines={"Blood Queen Plan",compactPositions(composition,"ranged","Ranged DPS"),compactPositions(composition,"healers","Healers"),compactPositions(composition,"melee","Melee")}
  if composition.secondary then lines[#lines+1]="Opening handoff: R6 comes to stationary R1 for the focus bite, then returns home to the right. "..(composition.secondaryHandoff or "R6 remains the right ranged anchor.") end
  local waves=plan.waves or {}
  if waves[0] and waves[0][1] then lines[#lines+1]="Initial: BQL -> "..waves[0][1].target end
  local n=1
  while waves[n] do
    local parts={}; for _,a in ipairs(waves[n]) do parts[#parts+1]=a.biter.." -> "..a.target end
    lines[#lines+1]="Bite "..n..": "..table.concat(parts," | "); n=n+1
  end
  lines[#lines+1]=utilityText("Shadow AM",composition.utility and composition.utility.shadowAM or {})
  lines[#lines+1]=utilityText("Airphase DSac",composition.utility and composition.utility.dsac or {},2)
  for _,w in ipairs(plan.warnings or {}) do lines[#lines+1]="Review: "..w end
  lines[#lines+1]="Source: "..((plan.source and plan.source.targetName) or "No valid segment").." | Generated: "..date("%Y-%m-%d %H:%M",plan.generatedAt)
  return splitDiscord(lines)
end

function PB:BuildExports()
  if not self.db then return end
  if not self.db.latestPlan then self:GeneratePlan() end
  local plan=self.db.latestPlan or {}
  local bpc=self.db.latestBPCPlan or self:BuildBPCPlan()
  local json={schemaVersion=PB.SCHEMA_VERSION,metadata={generatedAt=plan.generatedAt,realm="Lordaeron",version=PB.VERSION},selectedDataSource=plan.source and plan.source.id,roster=self.roster,flatPriority=plan.flatPriority,waves=plan.waves,assignments=plan.assignments,completedAssignments=plan.completedAssignments,warnings=plan.warnings,bqlComposition=plan.composition,bpcPlan=bpc}
  local payload={schemaVersion=PB.SCHEMA_VERSION,generatedAt=self:Now(),planTSV=self:BQLWorksheetRows(tsv),rosterTSV=self:RosterRows(tsv),bpcTSV=self:BPCWorksheetRows(tsv),planCSV=self:PlanRows(csv),rosterCSV=self:RosterRows(csv),bpcCSV=self:BPCRows(csv),json=self:JSON(json),discord=self:DiscordText(),bpcDiscord=self:BPCDiscordText()}
  self.exportDB.payload=payload
  self.exportDB.planTSVB64=self:Base64(payload.planTSV)
  self.exportDB.rosterTSVB64=self:Base64(payload.rosterTSV)
  self.exportDB.bpcTSVB64=self:Base64(payload.bpcTSV)
  self.exportDB.jsonB64=self:Base64(payload.json)
  self.exportDB.discordB64=self:Base64(payload.discord)
  return payload
end

function PB:GetExport(format,kind)
  local p=self:BuildExports()
  if format=="csv" then if kind=="bpc" then return p.bpcCSV end return kind=="roster" and p.rosterCSV or p.planCSV end
  if format=="json" then return p.json end
  if format=="discord" then return kind=="bpc" and p.bpcDiscord or p.discord end
  if kind=="bpc" then return p.bpcTSV end
  return kind=="roster" and p.rosterTSV or p.planTSV
end
