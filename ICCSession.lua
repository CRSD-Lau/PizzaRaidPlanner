local PB = PizzaRaidPlanner

local function normalizeLocation(name)
  return tostring(name or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
end

function PB:GetICCContext()
  local instanceName, instanceType, difficultyIndex, difficultyName, maxPlayers
  if GetInstanceInfo then
    instanceName, instanceType, difficultyIndex, difficultyName, maxPlayers = GetInstanceInfo()
  end
  local zoneName = GetRealZoneText and GetRealZoneText() or nil
  local expected = normalizeLocation(PB.ICC_NAME)
  local nameMatches = normalizeLocation(instanceName) == expected or normalizeLocation(zoneName) == expected
  return {
    inside = nameMatches and (instanceType == nil or instanceType == "raid"),
    instanceName = instanceName or zoneName or "Unknown",
    zoneName = zoneName,
    instanceType = instanceType,
    difficultyIndex = difficultyIndex,
    difficultyName = difficultyName,
    maxPlayers = maxPlayers,
  }
end

function PB:UpdateICCState(silent)
  if not self.db then return false end
  local context = self:GetICCContext()
  local wasInside = self.insideICC == true
  local now = self:Now()
  local session = self.db.iccSession or {}
  self.db.iccSession = session

  if context.inside then
    local lastSeen = tonumber(session.lastSeenAt)
    local expired = not lastSeen or now < lastSeen or now - lastSeen > PB.ICC_SESSION_TIMEOUT
    if not session.id or expired then
      session = {
        id = "icc-"..tostring(now).."-"..tostring(context.difficultyIndex or 0),
        startedAt = now,
        lastSeenAt = now,
        active = true,
        instanceName = context.instanceName,
        difficultyIndex = context.difficultyIndex,
        difficultyName = context.difficultyName,
        maxPlayers = context.maxPlayers,
        average = {sampleCount=0,duration=0,players={},sampleIds={}},
        benchmarks = {},
      }
      self.db.iccSession = session
      self._skadaSourceCheckedAt, self._skadaSourceCache = nil, nil
      if not silent then self:Print("ICC detected: new DPS session started automatically.") end
    else
      session.active = true
      session.lastSeenAt = now
      session.instanceName = context.instanceName
      session.difficultyIndex = context.difficultyIndex or session.difficultyIndex
      session.difficultyName = context.difficultyName or session.difficultyName
      session.maxPlayers = context.maxPlayers or session.maxPlayers
      session.benchmarks = session.benchmarks or {}
      if not wasInside and not silent then self:Print("ICC detected: DPS session resumed automatically.") end
    end
    self.insideICC, self.iccContext = true, context
    return true
  end

  if wasInside then
    if self.segment and self.segment.active then
      self.segment = nil
      self:Debug("Active damage sample discarded when leaving ICC")
    end
    session.lastSeenAt = now
    if not silent then self:Print("Outside ICC: DPS tracking paused.") end
  end
  session.active = false
  self.insideICC, self.iccContext = false, context
  return false
end

function PB:IsICCTrackingActive()
  if self.insideICC == nil or not (self.db and self.db.iccSession and self.db.iccSession.id) then self:UpdateICCState(true) end
  return self.insideICC == true and self.db and self.db.iccSession and self.db.iccSession.id ~= nil
end

function PB:TouchICCSession()
  if self.insideICC and self.db and self.db.iccSession then
    self.db.iccSession.lastSeenAt = self:Now()
    self.db.iccSession.active = true
  end
end

function PB:GetICCBossKey(guid, name)
  local npc = self:GetNPCID(guid)
  if npc and PB.ICC_BOSS_NPCS[npc] then return PB.ICC_BOSS_NPCS[npc] end
  return PB.ICC_BOSS_NAMES[normalizeLocation(name)]
end

function PB:GetICCBossSummary(segment)
  local totals, guids = {}, {}
  for guid,target in pairs(segment and segment.targets or {}) do
    local key = self:GetICCBossKey(guid, target.name)
    if key then
      totals[key] = (totals[key] or 0) + (tonumber(target.damage) or 0)
      guids[key] = guids[key] or {}
      guids[key][guid] = true
    end
  end
  local selected, damage
  for key,total in pairs(totals) do
    if not damage or total > damage then selected, damage = key, total end
  end
  if not selected then return nil end
  return {
    key = selected,
    name = PB.ICC_ENCOUNTER_NAMES[selected] or selected,
    damage = damage or 0,
    targetGUIDs = guids[selected],
  }
end

function PB:RememberICCEncounterBenchmark(segment)
  local session=self.db and self.db.iccSession
  if not session or not session.id or not segment or not segment.valid or not segment.iccEncounter or segment.iccSessionId~=session.id then return end
  session.benchmarks=session.benchmarks or {}
  session.benchmarks[segment.iccEncounter]={
    id="benchmark-"..segment.iccEncounter.."-"..tostring(segment.id),
    segmentId=segment.id,
    targetName=segment.targetName,
    duration=segment.duration,
    players=segment.players,
    valid=true,
    confidence=segment.targetName.." boss benchmark",
    dataSource="PizzaRaidPlanner current ICC session",
    iccEncounter=segment.iccEncounter,
    sessionId=session.id,
    recordedAt=segment.endTime,
  }
end

function PB:GetICCEncounterBenchmark(encounter)
  local session=self.db and self.db.iccSession
  if not session or not session.id then return nil end
  session.benchmarks=session.benchmarks or {}
  local stored=session.benchmarks[encounter]
  if stored and stored.sessionId==session.id and stored.valid then return stored end
  for i=#(self.db.segments or {}),1,-1 do
    local segment=self.db.segments[i]
    if segment.valid and segment.iccSessionId==session.id and segment.iccEncounter==encounter then
      self:RememberICCEncounterBenchmark(segment)
      return session.benchmarks[encounter]
    end
  end
end

function PB:GetFestergutSource()
  if self.festergutSourceOverride then return self.festergutSourceOverride end
  return self:GetICCEncounterBenchmark("festergut")
end

function PB:GetBQLBenchmarkSource()
  if self.live and self.live.active and self.live.frozenSource then return self.live.frozenSource end
  return self:GetFestergutSource()
end

function PB:AddICCSampleToAverage(segment)
  local session = self.db and self.db.iccSession
  if not session or not session.id or not segment or not segment.valid or not segment.averageEligible or segment.iccSessionId ~= session.id then return end
  self:RememberICCEncounterBenchmark(segment)
  local average=session.average
  if not average then average={sampleCount=0,duration=0,players={},sampleIds={}}; session.average=average end
  average.players=average.players or {}; average.sampleIds=average.sampleIds or {}
  if average.sampleIds[segment.id] then return end
  average.sampleIds[segment.id]=true
  average.sampleCount=(tonumber(average.sampleCount) or 0)+1
  average.duration=(tonumber(average.duration) or 0)+(tonumber(segment.duration) or 0)
  for guid,player in pairs(segment.players or {}) do
    local entry=average.players[guid] or {dpsTotal=0,sampleCount=0,totalDamage=0,primaryDamage=0,healing=0}
    average.players[guid]=entry
    entry.dpsTotal=(tonumber(entry.dpsTotal) or 0)+(tonumber(player.dps) or 0)
    entry.sampleCount=(tonumber(entry.sampleCount) or 0)+1
    entry.totalDamage=(tonumber(entry.totalDamage) or 0)+(tonumber(player.totalDamage) or 0)
    entry.primaryDamage=(tonumber(entry.primaryDamage) or 0)+(tonumber(player.primaryDamage) or 0)
    entry.healing=(tonumber(entry.healing) or 0)+(tonumber(player.healing) or 0)
  end
end

function PB:EnsureICCAverage()
  local session=self.db and self.db.iccSession
  if not session or not session.id then return nil end
  if session.average and session.average.sampleCount~=nil then return session.average end
  session.average={sampleCount=0,duration=0,players={},sampleIds={}}
  for _,segment in ipairs(self.db.segments or {}) do
    if segment.iccSessionId==session.id and segment.valid and segment.averageEligible then
      self:AddICCSampleToAverage(segment)
    end
  end
  return session.average
end

function PB:GetICCAverageSource()
  local session = self.db and self.db.iccSession
  if not session or not session.id then return nil end
  local average=self:EnsureICCAverage()
  local sampleCount=average and tonumber(average.sampleCount) or 0
  if sampleCount == 0 then return nil end

  local result = {
    id = "icc-average-"..session.id,
    targetName = "ICC running average ("..sampleCount.." boss sample"..(sampleCount == 1 and "" or "s")..")",
    duration = tonumber(average.duration) or 0,
    players = {},
    valid = true,
    confidence = "Current ICC session average",
    dataSource = "PizzaRaidPlanner ICC session",
    sampleCount = sampleCount,
    sessionId = session.id,
  }
  for guid,stored in pairs(average.players or {}) do
    local count=tonumber(stored.sampleCount) or 0
    result.players[guid]={
      dps=count>0 and (tonumber(stored.dpsTotal) or 0)/count or 0,
      sampleCount=count,
      totalDamage=tonumber(stored.totalDamage) or 0,
      primaryDamage=tonumber(stored.primaryDamage) or 0,
      healing=tonumber(stored.healing) or 0,
      confidence=count.."/"..sampleCount.." ICC boss samples",
    }
  end
  return result
end

function PB:GetICCBossSampleCount()
  local source = self:GetICCAverageSource()
  return source and source.sampleCount or 0
end

-- Festergut history lives in this established module so a running 3.3.5a
-- client can pick up the feature with /reload. That client can reject brand
-- new addon files added after the process has already started.
PizzaRaidPlannerLocalHistorySeed = PizzaRaidPlannerLocalHistorySeed or {}

local FESTERGUT_HISTORY_PLAYER_CLASSES = {
  DEATHKNIGHT=true,DRUID=true,HUNTER=true,MAGE=true,PALADIN=true,
  PRIEST=true,ROGUE=true,SHAMAN=true,WARLOCK=true,WARRIOR=true,
}

local function copyFestergutHistorySource(source, fallbackId)
  if not source then return nil end
  local result={
    id=source.id or fallbackId,
    segmentId=source.segmentId,
    targetGUID=source.targetGUID,
    targetName=source.targetName or "Festergut",
    duration=tonumber(source.duration) or 0,
    valid=source.valid~=false,
    confidence=source.confidence or "Saved Festergut benchmark",
    dataSource=source.dataSource or "PizzaRaidPlanner Festergut history",
    iccEncounter=source.iccEncounter or "festergut",
    sessionId=source.sessionId or source.iccSessionId,
    recordedAt=source.recordedAt or source.endTime,
    sampleCount=source.sampleCount,
    players={},
  }
  for guid,player in pairs(source.players or {}) do
    result.players[guid]={
      dps=tonumber(player.dps) or 0,
      totalDamage=tonumber(player.totalDamage) or 0,
      primaryDamage=tonumber(player.primaryDamage) or 0,
      primaryUnbuffedDamage=tonumber(player.primaryUnbuffedDamage) or nil,
      healing=tonumber(player.healing) or 0,
      confidence=player.confidence or source.confidence,
      sampleCount=player.sampleCount,
    }
  end
  return result
end

local function festergutHistoryId(segment)
  local segmentId=segment and (segment.segmentId or segment.id) or "unknown"
  return "festergut-history-"..tostring(segmentId)
end

function PB:GetFestergutHistory()
  if not self.db then return {} end
  self.db.festergutHistory=self.db.festergutHistory or {}
  return self.db.festergutHistory
end

function PB:GetFestergutHistoryEntry(id)
  if not id then return nil end
  for _,entry in ipairs(self:GetFestergutHistory()) do if entry.id==id then return entry end end
end

function PB:GetSelectedFestergutHistoryEntry()
  return self:GetFestergutHistoryEntry(self.db and self.db.selectedFestergutHistoryId)
end

local function localFestergutSeedRoster(segmentId,sourceId)
  local seeds=PizzaRaidPlannerLocalHistorySeed
  if type(seeds)~="table" then return nil end
  local seed=seeds[segmentId] or seeds[sourceId]
  if type(seed)=="table" and seed.roster then return seed.roster end
  return type(seed)=="table" and seed or nil
end

function PB:RecoverFestergutRoster(source,segmentId)
  local seeded=localFestergutSeedRoster(segmentId,source and source.id)
  if seeded and #seeded>0 then return self:SnapshotRaidRoster(seeded),"local legacy recovery" end

  if type(SkadaCharDB)~="table" then return {},nil end
  local recordedAt=tonumber(source and source.recordedAt) or 0
  local best,bestDistance
  for _,set in ipairs(SkadaCharDB) do
    if type(set)=="table" and self:NormalizeName(set.name)=="festergut" then
      local setAt=tonumber(set.endtime) or tonumber(set.starttime) or 0
      local distance=recordedAt>0 and math.abs(setAt-recordedAt) or 0
      if not bestDistance or distance<bestDistance then best,bestDistance=set,distance end
    end
  end
  if not best or (recordedAt>0 and bestDistance>1800) then return {},nil end

  local roster={}
  for actorName,actor in pairs(best.actors or {}) do
    if type(actor)=="table" and actor.id and FESTERGUT_HISTORY_PLAYER_CLASSES[actor.class] and not actor.enemy then
      roster[#roster+1]={
        guid=actor.id,name=actorName,normalizedName=self:NormalizeName(actorName),
        className=actor.class,classToken=actor.class,spec=tonumber(actor.spec) or actor.spec,
        skadaRole=actor.role,talentBuild=actor.talent,online=true,connected=true,dead=false,
      }
    end
  end
  table.sort(roster,function(a,b) return a.normalizedName<b.normalizedName end)
  for i,player in ipairs(roster) do player.raidIndex=i; player.subgroup=math.floor((i-1)/5)+1 end
  return self:SnapshotRaidRoster(roster),"Skada saved encounter recovery"
end

function PB:RememberFestergutHistory(segment,roster)
  if not self.db or not segment or segment.valid==false then return nil end
  if (segment.iccEncounter or "festergut")~="festergut" then return nil end
  local segmentId=segment.segmentId or segment.id
  local id=festergutHistoryId(segment)
  local history=self:GetFestergutHistory()
  local entry=self:GetFestergutHistoryEntry(id)
  local festergutSource=copyFestergutHistorySource(segment,"benchmark-festergut-"..tostring(segmentId))
  local snapshot=self:SnapshotRaidRoster(roster or {})
  local recoverySource
  if #snapshot==0 then snapshot,recoverySource=self:RecoverFestergutRoster(festergutSource,segmentId) end
  if entry then
    if #(entry.roster or {})<#snapshot then entry.roster=snapshot; entry.rosterSource=recoverySource or "recorded raid roster" end
    if not entry.festergutSource then entry.festergutSource=festergutSource end
    return entry
  end

  entry={
    id=id,segmentId=segmentId,sessionId=festergutSource.sessionId,
    recordedAt=festergutSource.recordedAt or self:Now(),duration=festergutSource.duration,
    difficultyName=segment.difficultyName or "Raid",raidSize=tonumber(segment.raidSize) or #snapshot,
    festergutSource=festergutSource,
    roster=snapshot,rosterSource=recoverySource or (#snapshot>0 and "recorded raid roster" or "missing"),
  }
  history[#history+1]=entry
  while #history>PB.MAX_FESTERGUT_HISTORY do
    local removed=table.remove(history,1)
    if self.db.selectedFestergutHistoryId==removed.id then self.db.selectedFestergutHistoryId=nil end
  end
  return entry
end

function PB:EnsureFestergutHistory()
  if not self.db then return {} end
  for _,segment in ipairs(self.db.segments or {}) do
    if segment.valid and segment.iccEncounter=="festergut" then self:RememberFestergutHistory(segment,{}) end
  end
  local current=self:GetICCEncounterBenchmark("festergut")
  if current then self:RememberFestergutHistory(current,{}) end
  return self:GetFestergutHistory()
end

function PB:GenerateFestergutHistoryPlans(entryOrId)
  local entry=type(entryOrId)=="table" and entryOrId or self:GetFestergutHistoryEntry(entryOrId)
  if not entry then return nil,"Saved Festergut entry was not found." end
  if self.live and self.live.active then return nil,"Turn Live mode off before loading a historical rehearsal." end
  if #(entry.roster or {})==0 then return nil,"This Festergut entry has DPS but no recoverable raid roster." end

  local previousRoster=self.savedRaidTestRoster
  local previousGeneral=self.planningSourceOverride
  local previousFestergut=self.festergutSourceOverride
  self.savedRaidTestRoster=self:SnapshotRaidRoster(entry.roster)
  self.planningSourceOverride=entry.festergutSource
  self.festergutSourceOverride=entry.festergutSource
  self._historyBuildInProgress=true
  local ok,bpc,bql=pcall(function()
    local bpcPlan=self:BuildBPCPlan()
    local bqlPlan=self:GeneratePlan()
    return bpcPlan,bqlPlan
  end)
  self._historyBuildInProgress=nil
  self.savedRaidTestRoster=previousRoster
  self.planningSourceOverride=previousGeneral
  self.festergutSourceOverride=previousFestergut
  self:ScanRoster()
  if not ok then return nil,tostring(bpc) end

  bpc.historyEntryId=entry.id; bpc.historyRecordedAt=entry.recordedAt
  bql.historyEntryId=entry.id; bql.historyRecordedAt=entry.recordedAt
  self.db.latestBPCPlan=bpc; self.db.latestPlan=bql
  if self.UpdateUI then self:UpdateUI() end
  return {entry=entry,rosterCount=#entry.roster,bpc=bpc,bql=bql}
end

function PB:SelectFestergutHistory(id)
  self:EnsureFestergutHistory()
  local entry=self:GetFestergutHistoryEntry(id)
  if not entry then return nil,"Saved Festergut entry was not found." end
  local previous=self.db.selectedFestergutHistoryId
  self.db.selectedFestergutHistoryId=id
  local result,err=self:GenerateFestergutHistoryPlans(entry)
  if not result then self.db.selectedFestergutHistoryId=previous; return nil,err end
  return result
end

function PB:ClearFestergutHistorySelection(rebuild)
  if not self.db then return end
  self.db.selectedFestergutHistoryId=nil
  self.db.settings.source="auto"
  if rebuild then
    self:BuildBPCPlan()
    self:GeneratePlan()
  else
    self:ScanRoster()
    if self.UpdateUI then self:UpdateUI() end
  end
end

function PB:PrepareBPCPlanForUI()
  local entry=self:GetSelectedFestergutHistoryEntry()
  if entry then
    local result,err=self:GenerateFestergutHistoryPlans(entry)
    return result and result.bpc or nil,err
  end
  self.db.settings.source="auto"
  return self:BuildBPCPlan()
end

function PB:PrepareBQLPlanForUI()
  local entry=self:GetSelectedFestergutHistoryEntry()
  if entry then
    local result,err=self:GenerateFestergutHistoryPlans(entry)
    return result and result.bql or nil,err
  end
  return self:GeneratePlan()
end
