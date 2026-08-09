-- Blood Prince Council is a pre-fight composition and position review.  It
-- intentionally makes no protected in-combat assignments; it only creates a
-- pasteable review of the live raid roster for a blank staging worksheet.
local PB = PizzaRaidPlanner
local function byName(a,b) return (a.name or ""):lower() < (b.name or ""):lower() end
local function dps(p) return tonumber(p.expectedDPS) or -1 end
local function performanceSort(a,b)
  if dps(a)~=dps(b) then return dps(a)>dps(b) end
  if (a.bossDamage or 0)~=(b.bossDamage or 0) then return (a.bossDamage or 0)>(b.bossDamage or 0) end
  return byName(a,b)
end
local function addSlot(result,p,prefix,slotNumber,group,placement)
  result.assignments[#result.assignments+1]={
    type="position",slot=prefix..slotNumber,order=slotNumber,group=group,
    player=p.name,guid=p.guid,class=p.classToken,spec=PB:GetSpecName(p),role=PB:ResolveRole(p),roleEvidence=p.roleConfidence,
    position=p.position,subgroup=p.subgroup,online=p.online,alive=not p.dead,expectedDPS=p.expectedDPS,placement=placement,
  }
end
local function addSlots(result, members, prefix, limit, group)
  for i,p in ipairs(members) do
    if i <= limit then addSlot(result,p,prefix,i,group,"Raid-order placement.")
    else result.warnings[#result.warnings+1]=p.name.." exceeds available "..group.." slots." end
  end
end
local function mobilityFor(p)
  local spec=tonumber(p.spec) or p.spec
  if p.classToken=="ROGUE" then return "Sprint" end
  if p.classToken=="WARRIOR" then return "Charge / Intercept" end
  if p.classToken=="DRUID" and (spec==103 or spec==104) then return "Feral Charge" end
end
local function dpsLabel(p)
  return p.expectedDPS and (math.floor(p.expectedDPS).." DPS") or "no DPS sample"
end
local function benchmarkDPS(source,p)
  local sample=source and source.players and source.players[p.guid]
  return tonumber(sample and sample.dps) or -1
end
local function benchmarkLabel(source,p)
  local sample=source and source.players and source.players[p.guid]
  if sample and tonumber(sample.dps) then return math.floor(sample.dps).." Festergut DPS" end
  return "no Festergut sample"
end
local function benchmarkSort(source)
  return function(a,b)
    local adps,bdps=benchmarkDPS(source,a),benchmarkDPS(source,b)
    if adps~=bdps then return adps>bdps end
    return performanceSort(a,b)
  end
end
local function addMeleeSlots(result,members)
  local dpsPlayers={}
  for i,p in ipairs(members) do dpsPlayers[i]=p end
  table.sort(dpsPlayers,performanceSort)

  local preferred={}

  -- Alternate the best remaining performer with the best remaining player who
  -- lacks Sprint/Charge/Feral Charge. This protects pump and recovery risk
  -- without automatically pushing an exceptional mobile player outside.
  local remainingDPS={}
  for i,p in ipairs(dpsPlayers) do remainingDPS[i]=p end
  local choosePump=true
  while #preferred<#PB.BPC_MELEE_PREFERRED_SLOTS and #remainingDPS>0 do
    local index=1
    local reason="Top remaining melee output"
    if not choosePump then
      index=nil
      for i,p in ipairs(remainingDPS) do if not mobilityFor(p) then index=i; break end end
      if index then reason="Limited boss-return mobility" else index=1 end
    end
    local p=table.remove(remainingDPS,index)
    preferred[#preferred+1]={player=p,reason=reason}
    choosePump=not choosePump
  end

  for i,item in ipairs(preferred) do
    local p=item.player
    local mobility=mobilityFor(p)
    local detail=mobility and ("; "..mobility.." available") or "; no quick gap closer detected"
    addSlot(result,p,"M",PB.BPC_MELEE_PREFERRED_SLOTS[i],"melee DPS","Preferred M1/M2/M6/M7: "..item.reason.."; "..dpsLabel(p)..detail..".")
  end

  local recovery={}
  for _,p in ipairs(remainingDPS) do recovery[#recovery+1]=p end
  table.sort(recovery,function(a,b)
    local am,bm=mobilityFor(a)~=nil,mobilityFor(b)~=nil
    if am~=bm then return not am end
    return performanceSort(a,b)
  end)
  for i,p in ipairs(recovery) do
    local slotNumber=PB.BPC_MELEE_RECOVERY_SLOTS[i]
    if not slotNumber then
      result.warnings[#result.warnings+1]=p.name.." exceeds available melee DPS slots."
    else
      local mobility=mobilityFor(p)
      local detail=mobility and ("; "..mobility.." available.") or "; no quick gap closer detected."
      local reason
      if slotNumber==3 or slotNumber==10 then
        reason="Overflow M3/M10: used only after the normal eight-player melee footprint; "..dpsLabel(p)..detail
      else
        reason="Recovery M4/M5/M8/M9: lower protected-slot priority; "..dpsLabel(p)..detail
      end
      addSlot(result,p,"M",slotNumber,"melee DPS",reason)
    end
  end
end
local function addRangedSlots(result,members,festergutSource)
  local boomkins,hunters,others={},{},{}
  for _,p in ipairs(members) do
    if p.classToken=="DRUID" and tonumber(p.spec)==102 then boomkins[#boomkins+1]=p
    elseif p.classToken=="HUNTER" then hunters[#hunters+1]=p
    else others[#others+1]=p end
  end
  table.sort(boomkins,performanceSort); table.sort(hunters,performanceSort); table.sort(others,performanceSort)
  local used={}
  for i,p in ipairs(boomkins) do
    local slotNumber=PB.BPC_BOOMKIN_SLOTS[i]
    if slotNumber then
      used[slotNumber]=true
      addSlot(result,p,"R",slotNumber,"ranged","Valanar active: Balance Druid reserved at R9/R10/R8 so Starfall is separated from Keleseth's Dark Nuclei/orb area.")
    else others[#others+1]=p end
  end
  for i,p in ipairs(hunters) do
    local slotNumber=PB.BPC_HUNTER_SLOTS[i]
    if slotNumber then
      used[slotNumber]=true
      local reason=i==1 and "Valanar active: top-DPS Hunter anchored at R2 for Kinetic Orb coverage." or "Valanar active: second Hunter anchored at R7 for opposite-side Kinetic Orb coverage; deliberate exception to the lower-DPS R4-R7 band."
      addSlot(result,p,"R",slotNumber,"ranged",reason.." "..dpsLabel(p)..".")
    else others[#others+1]=p end
  end
  table.sort(others,benchmarkSort(festergutSource))
  local accessible,difficult={},{}
  for _,slotNumber in ipairs(PB.BPC_RANGED_ACCESSIBLE_SLOTS) do if not used[slotNumber] then accessible[#accessible+1]=slotNumber end end
  for _,slotNumber in ipairs(PB.BPC_RANGED_DIFFICULT_SLOTS) do if not used[slotNumber] then difficult[#difficult+1]=slotNumber end end
  for i,p in ipairs(others) do
    local slotNumber,reason
    if i<=#accessible then
      slotNumber=accessible[i]
      reason="Valanar active: higher non-reserved ranged output placed in the R3/R1/easy-position order and kept outside the difficult R4-R7 range band; "..benchmarkLabel(festergutSource,p).."."
    else
      slotNumber=difficult[i-#accessible]
      reason="Valanar active: lower non-reserved ranged output assigned to the difficult R4-R7 range band; "..benchmarkLabel(festergutSource,p).."."
    end
    if slotNumber then
      used[slotNumber]=true
      addSlot(result,p,"R",slotNumber,"ranged",reason)
    else result.warnings[#result.warnings+1]=p.name.." exceeds available ranged slots." end
  end
end
local function addUtility(result,key,label,capability,limit)
  local order=capability=="kinetic" and PB:GetBPCKineticOrder() or PB:GetUtilityOrder(capability,limit)
  result.utility[key]=order
  for i,item in ipairs(order) do
    local p=item.player
    result.utilityAssignments[#result.utilityAssignments+1]={
      type="utility",slot=label..i,order=i,group=label,capability=capability,
      player=p.name,guid=p.guid,class=p.classToken,spec=PB:GetSpecName(p),role=PB:ResolveRole(p),roleEvidence=p.roleConfidence,
      position=p.position,subgroup=p.subgroup,online=p.online,alive=not p.dead,
      capabilitySource=item.source,
    }
  end
  if #order<limit then
    result.warnings[#result.warnings+1]="Only "..#order.." of "..limit.." "..label.." assignment(s) could be verified from the active raid."
  end
end

function PB:GetBPCKineticOrder()
  local capable=self:GetUtilityOrder("kinetic")
  local result,used={},{ }
  local function append(item)
    local guid=item and item.player and item.player.guid
    if guid and not used[guid] then result[#result+1]=item; used[guid]=true; return true end
  end

  -- The two primary orb handlers remain the strongest available Hunters.
  for _,item in ipairs(capable) do
    if #result>=2 then break end
    if item.player.classToken=="HUNTER" then append(item) end
  end
  -- Preserve explicit fallbacks when the raid has fewer than two Hunters.
  for _,item in ipairs(capable) do
    if #result>=2 then break end
    append(item)
  end

  -- The third assignment is the strongest available Warlock, independent of
  -- their BPC room position. This is the normal backup-orb rule, not a claim
  -- that every Warlock has the Hunter kinetic capability globally.
  local warlocks={}
  for _,p in ipairs(self.roster or {}) do
    if p.online and p.connected and p.classToken=="WARLOCK" and not used[p.guid] then
      warlocks[#warlocks+1]={
        player=p,
        source="BPC Warlock backup rule",
        priority=tonumber(self.db.utilityPriorities[p.normalizedName]) or 0,
      }
    end
  end
  table.sort(warlocks,function(a,b)
    if a.priority~=b.priority then return a.priority>b.priority end
    if dps(a.player)~=dps(b.player) then return dps(a.player)>dps(b.player) end
    local ai,bi=a.player.raidIndex or 99,b.player.raidIndex or 99
    if ai~=bi then return ai<bi end
    return byName(a.player,b.player)
  end)
  append(warlocks[1])

  -- If no Warlock is present, retain the old verified-capability fallback and
  -- let the existing warning surface a genuinely unfilled third assignment.
  for _,item in ipairs(capable) do
    if #result>=3 then break end
    append(item)
  end
  return result
end
function PB:BuildBPCPlan()
  self:ScanRoster()
  local festergutSource=self:GetFestergutSource()
  self:ApplySourceToRoster(festergutSource,true)
  local healers, melee, ranged, tanks, unknown = {},{},{},{},{}
  local classCounts={}; local online=0
  for _,p in ipairs(self.roster) do
    classCounts[p.classToken]=(classCounts[p.classToken] or 0)+1
    if p.online and p.connected then
      online=online+1; p.position=self:GetPosition(p); local role=self:ResolveRole(p)
      if role=="healer" then healers[#healers+1]=p
      elseif role=="tank" then tanks[#tanks+1]=p
      elseif p.position=="melee" then melee[#melee+1]=p
      elseif p.position=="ranged" then ranged[#ranged+1]=p
      else unknown[#unknown+1]=p end
    end
  end
  table.sort(healers,byName); table.sort(unknown,byName)
  local plan={schemaVersion=PB.SCHEMA_VERSION,encounter="Blood Prince Council",phase="Valanar active",mechanic="Empowered Shock Vortex",generatedAt=self:Now(),source=festergutSource,assignments={},utilityAssignments={},utility={kinetics={},dsac={},fireAM={}},warnings={},classCounts=classCounts,summary={raidSize=#self.roster,online=online,healers=#healers,melee=#melee,ranged=#ranged,tanks=#tanks,unknown=#unknown}}
  addSlots(plan,healers,"H",5,"healer")
  addMeleeSlots(plan,melee)
  addRangedSlots(plan,ranged,festergutSource)
  addUtility(plan,"kinetics","Kinetic", "kinetic",3)
  addUtility(plan,"dsac","DSac", "divineSacrifice",3)
  addUtility(plan,"fireAM","FireAM", "auraMastery",3)
  if #healers<5 then plan.warnings[#plan.warnings+1]="Only "..#healers.." confirmed/suggested healers; H slots remain unfilled." end
  if not festergutSource then plan.warnings[#plan.warnings+1]="No valid Festergut sample is selected; every BPC DPS placement needs manual review." end
  if #unknown>0 then for _,p in ipairs(unknown) do plan.warnings[#plan.warnings+1]=p.name.." has unknown position; set /prp position before publishing." end end
  if online<#self.roster then plan.warnings[#plan.warnings+1]=(#self.roster-online).." roster member(s) are offline." end
  self.db.latestBPCPlan=plan
  return plan
end
