local PB = PizzaRaidPlanner

local HASH_MOD = 4294967296

local function copyTable(source)
  local result={}
  for key,value in pairs(source or {}) do result[key]=value end
  return result
end

local function copyRoster(entries)
  local result={}
  for _,player in ipairs(entries or {}) do result[#result+1]=copyTable(player) end
  table.sort(result,function(a,b)
    local an=(a.normalizedName or a.name or ""):lower()
    local bn=(b.normalizedName or b.name or ""):lower()
    if an~=bn then return an<bn end
    return tostring(a.guid or "")<tostring(b.guid or "")
  end)
  return result
end

local function hashText(value)
  local hash=5381
  for index=1,#value do hash=(hash*33+string.byte(value,index))%HASH_MOD end
  return tostring(math.floor(hash))
end

local function token(value)
  if value==nil then return "" end
  if value==true then return "1" end
  if value==false then return "0" end
  return tostring(value)
end

local function playerKey(PB,player)
  return (player and player.guid and ("guid:"..player.guid)) or ("name:"..PB:NormalizeName(player and player.name))
end

local function rosterIndex(PB,entries)
  local byKey,byName={},{ }
  for _,player in ipairs(entries or {}) do
    byKey[playerKey(PB,player)]=player
    byName[PB:NormalizeName(player.name)]=player
  end
  return byKey,byName
end

local function rosterPlayer(PB,entry,current)
  local byKey,byName=rosterIndex(PB,entry and entry.roster or {})
  return byKey[playerKey(PB,current)] or byName[PB:NormalizeName(current.name)]
end

local function sourcePlayer(source,recorded,current)
  if not source or not source.players then return nil end
  return source.players[current.guid] or (recorded and source.players[recorded.guid])
end

local function appendWarning(plan,message)
  if not plan or not message then return end
  plan.warnings=plan.warnings or {}
  for _,existing in ipairs(plan.warnings) do if existing==message then return end end
  plan.warnings[#plan.warnings+1]=message
end

function PB:SnapshotPlanningRoster(entries)
  return copyRoster(entries or self.roster or {})
end

function PB:RosterFingerprint(entries)
  local rows={}
  for _,player in ipairs(entries or {}) do
    local role=self.ResolveRole and self:ResolveRole(player) or player.suggestedRole or "unknown"
    local position=self.GetPosition and self:GetPosition(player) or player.position or "unknown"
    rows[#rows+1]=table.concat({
      self:NormalizeName(player.name),token(player.guid),token(player.classToken),token(player.spec),
      token(role),token(position),token(player.online~=false),token(player.connected~=false),
    },"|")
  end
  table.sort(rows)
  return hashText(table.concat(rows,"\n"))
end

function PB:BuildRosterDiff(previous,current)
  local oldByKey,oldByName=rosterIndex(self,previous)
  local newByKey,newByName=rosterIndex(self,current)
  local result={incoming={},outgoing={},specChanged={},roleChanged={},availabilityChanged={}}
  local seen={}

  for key,oldPlayer in pairs(oldByKey) do
    local normalized=self:NormalizeName(oldPlayer.name)
    local newPlayer=newByKey[key] or newByName[normalized]
    if not newPlayer then
      result.outgoing[#result.outgoing+1]={guid=oldPlayer.guid,name=oldPlayer.name,classToken=oldPlayer.classToken,spec=oldPlayer.spec}
    else
      seen[playerKey(self,newPlayer)]=true
      if token(oldPlayer.spec)~=token(newPlayer.spec) then
        result.specChanged[#result.specChanged+1]={guid=newPlayer.guid,name=newPlayer.name,from=oldPlayer.spec,to=newPlayer.spec}
      end
      local oldRole=self.ResolveRole and self:ResolveRole(oldPlayer) or oldPlayer.suggestedRole
      local newRole=self.ResolveRole and self:ResolveRole(newPlayer) or newPlayer.suggestedRole
      if token(oldRole)~=token(newRole) then
        result.roleChanged[#result.roleChanged+1]={guid=newPlayer.guid,name=newPlayer.name,from=oldRole,to=newRole}
      end
      local oldAvailable=oldPlayer.online~=false and oldPlayer.connected~=false
      local newAvailable=newPlayer.online~=false and newPlayer.connected~=false
      if oldAvailable~=newAvailable then
        result.availabilityChanged[#result.availabilityChanged+1]={guid=newPlayer.guid,name=newPlayer.name,available=newAvailable}
      end
    end
  end

  for key,newPlayer in pairs(newByKey) do
    local normalized=self:NormalizeName(newPlayer.name)
    if not seen[key] and not oldByKey[key] and not oldByName[normalized] then
      result.incoming[#result.incoming+1]={guid=newPlayer.guid,name=newPlayer.name,classToken=newPlayer.classToken,spec=newPlayer.spec}
    end
  end

  local function byName(a,b) return (a.name or ""):lower()<(b.name or ""):lower() end
  for _,bucket in pairs(result) do table.sort(bucket,byName) end
  result.replacements=math.max(#result.incoming,#result.outgoing)
  result.changed=result.replacements>0 or #result.specChanged>0 or #result.roleChanged>0 or #result.availabilityChanged>0
  return result
end

function PB:GetFestergutHistoryEntryForSource(source)
  if not source then return nil end
  local segmentId=source.segmentId
  local sourceId=source.baseSourceId or source.id
  for index=#(self:GetFestergutHistory() or {}),1,-1 do
    local entry=self:GetFestergutHistory()[index]
    local entrySource=entry.festergutSource or {}
    if (segmentId and entry.segmentId==segmentId) or entrySource.id==sourceId or entrySource.baseSourceId==sourceId then return entry end
  end
end

function PB:FindHistoricalFestergutSample(player,excludeEntryId)
  if not player then return nil end
  local history=self:GetFestergutHistory()
  for index=#history,1,-1 do
    local entry=history[index]
    local confirmed=self.IsConfirmedFestergutHistoryEntry and self:IsConfirmedFestergutHistoryEntry(entry) or entry.confirmedKill~=false
    if confirmed and entry.id~=excludeEntryId then
      local recorded=rosterPlayer(self,entry,player)
      local sameClass=recorded and recorded.classToken==player.classToken
      local sameSpec=recorded and token(recorded.spec)==token(player.spec)
      local sample=sameSpec and sameClass and sourcePlayer(entry.festergutSource,recorded,player) or nil
      if sample and tonumber(sample.dps) then return sample,entry,recorded end
    end
  end
end

function PB:BuildAudibleFestergutSource(baseSource,roster,baseEntry,allowHistoryFallback)
  if not baseSource then return nil,{} end
  local result=copyTable(baseSource)
  result.baseSourceId=baseSource.baseSourceId or baseSource.id
  result.id="audible-"..tostring(result.baseSourceId).."-"..self:RosterFingerprint(roster)
  result.players={}
  result.provenanceByGUID={}
  result.isAudibleComposite=true
  local evidence={historical={},missing={}}

  for _,player in ipairs(roster or {}) do
    local recorded=baseEntry and rosterPlayer(self,baseEntry,player) or nil
    local baseCompatible=not recorded or (recorded.classToken==player.classToken and token(recorded.spec)==token(player.spec))
    local sample=baseCompatible and sourcePlayer(baseSource,recorded,player) or nil
    local replacementReason=recorded and not baseCompatible and "spec-change" or "incoming"
    if sample then
      result.players[player.guid]=copyTable(sample)
      result.provenanceByGUID[player.guid]={kind=baseEntry and "selected" or "current",entryId=baseEntry and baseEntry.id or nil,recordedAt=baseSource.recordedAt,dps=sample.dps}
    elseif allowHistoryFallback and self:ResolveRole(player)=="dps" then
      local historical,entry=self:FindHistoricalFestergutSample(player,baseEntry and baseEntry.id)
      if historical then
        result.players[player.guid]=copyTable(historical)
        result.provenanceByGUID[player.guid]={kind="history",entryId=entry.id,recordedAt=entry.recordedAt,dps=historical.dps}
        evidence.historical[#evidence.historical+1]={player=player,entry=entry,dps=historical.dps,reason=replacementReason}
      else
        result.provenanceByGUID[player.guid]={kind="missing"}
        evidence.missing[#evidence.missing+1]={player=player,reason=replacementReason}
      end
    end
  end
  return result,evidence
end

local function assignmentDigest(bundle)
  local parts={bundle.sourceId or "",bundle.rosterHash or ""}
  for _,assignment in ipairs(bundle.bpc and bundle.bpc.assignments or {}) do
    parts[#parts+1]="BP:"..token(assignment.slot)..":"..token(assignment.guid or assignment.player)
  end
  for _,assignment in ipairs(bundle.bpc and bundle.bpc.utilityAssignments or {}) do
    parts[#parts+1]="BU:"..token(assignment.slot)..":"..token(assignment.guid or assignment.player)
  end
  local composition=bundle.bql and bundle.bql.composition or {}
  for _,position in ipairs(composition.positions or {}) do
    parts[#parts+1]="QP:"..token(position.slot)..":"..token(position.player and position.player.guid)
  end
  for _,assignment in ipairs(bundle.bql and bundle.bql.assignments or {}) do
    parts[#parts+1]="QB:"..token(assignment.wave)..":"..token(assignment.slot)..":"..token(assignment.biterGUID)..":"..token(assignment.targetGUID)
  end
  for _,item in ipairs(composition.utility and composition.utility.shadowAM or {}) do parts[#parts+1]="QA:"..token(item.player and item.player.guid) end
  for _,item in ipairs(composition.utility and composition.utility.dsac or {}) do parts[#parts+1]="QD:"..token(item.player and item.player.guid) end
  return hashText(table.concat(parts,"\n"))
end

local function mapAssignments(bundle)
  local result={}
  local function add(key,kind,scope,name,value)
    result[key]={kind=kind,scope=scope,name=name or "Unknown",value=value or "NONE"}
  end
  for _,assignment in ipairs(bundle and bundle.bpc and bundle.bpc.assignments or {}) do
    if assignment.guid then add("bpc:"..assignment.guid,"position","BPC",assignment.player,assignment.slot) end
  end
  for _,assignment in ipairs(bundle and bundle.bpc and bundle.bpc.utilityAssignments or {}) do
    add("bpc-utility:"..token(assignment.slot),"utility","BPC",assignment.slot,assignment.player)
  end
  local composition=bundle and bundle.bql and bundle.bql.composition or {}
  for _,position in ipairs(composition.positions or {}) do
    if position.player and position.player.guid then add("bql:"..position.player.guid,"position","BQL",position.player.name,position.slot) end
  end
  for _,assignment in ipairs(bundle and bundle.bql and bundle.bql.assignments or {}) do
    if assignment.targetGUID then add("bite:"..assignment.targetGUID,"bite","BQL BITE",assignment.target,"Wave "..token(assignment.wave).." from "..token(assignment.biter)) end
  end
  for index,item in ipairs(composition.utility and composition.utility.shadowAM or {}) do add("bql-am:"..index,"utility","BQL AM","AM "..index,item.player and item.player.name) end
  for index,item in ipairs(composition.utility and composition.utility.dsac or {}) do add("bql-dsac:"..index,"utility","BQL DSAC","DSac "..index,item.player and item.player.name) end
  return result
end

function PB:ComparePlanBundles(previous,current)
  local before,after=mapAssignments(previous),mapAssignments(current)
  local summary={positionChanges=0,biteChanges=0,utilityChanges=0,totalChanges=0,details={}}
  local seen={}
  local function record(key,oldEntry,newEntry)
    local entry=newEntry or oldEntry
    summary.totalChanges=summary.totalChanges+1
    if entry.kind=="bite" then summary.biteChanges=summary.biteChanges+1
    elseif entry.kind=="utility" then summary.utilityChanges=summary.utilityChanges+1
    else summary.positionChanges=summary.positionChanges+1 end
    summary.details[#summary.details+1]={
      key=key,kind=entry.kind,scope=entry.scope,name=entry.name,
      from=oldEntry and oldEntry.value or "NONE",to=newEntry and newEntry.value or "NONE",
    }
  end
  for key,oldEntry in pairs(before) do
    seen[key]=true
    local newEntry=after[key]
    if not newEntry or newEntry.value~=oldEntry.value then record(key,oldEntry,newEntry) end
  end
  for key,newEntry in pairs(after) do
    if not seen[key] then record(key,nil,newEntry) end
  end
  local order={position=1,bite=2,utility=3}
  table.sort(summary.details,function(a,b)
    if order[a.kind]~=order[b.kind] then return order[a.kind]<order[b.kind] end
    if a.scope~=b.scope then return a.scope<b.scope end
    return (a.name or ""):lower()<(b.name or ""):lower()
  end)
  return summary
end

local function criticalDeparture(previous,diff)
  if not previous or not diff then return false end
  local critical={}
  local composition=previous.bql and previous.bql.composition or {}
  if composition.primary then critical[composition.primary.guid]=true end
  if composition.secondary then critical[composition.secondary.guid]=true end
  for _,bucket in ipairs({composition.utility and composition.utility.shadowAM or {},composition.utility and composition.utility.dsac or {}}) do
    for _,item in ipairs(bucket) do if item.player then critical[item.player.guid]=true end end
  end
  for _,player in ipairs(diff.outgoing or {}) do if critical[player.guid] then return true end end
  return false
end

function PB:BuildPlanBundle(options)
  options=options or {}
  if not self.db then return nil,"Planner database is unavailable." end
  if self.live and self.live.active and options.reason~="live" then return nil,"Turn Live mode off before rebuilding the pre-pull plan bundle." end

  local selected=options.historyEntry or self:GetSelectedFestergutHistoryEntrySafe()
  if selected and self.IsConfirmedFestergutHistoryEntry and not self:IsConfirmedFestergutHistoryEntry(selected) then
    return nil,"Only confirmed Festergut kills can be used for BPC/BQL planning."
  end

  local roster
  if options.roster then roster=self:SnapshotPlanningRoster(options.roster)
  elseif selected then roster=self:SnapshotPlanningRoster(selected.roster)
  else
    self._capturingPlanBundle=true
    self:ScanRoster()
    self._capturingPlanBundle=nil
    roster=self:SnapshotPlanningRoster(self.roster)
  end
  if #roster==0 then return nil,"No raid roster is available for plan generation." end

  local baseSource=options.source or (selected and selected.festergutSource) or self:GetFestergutSource()
  if not baseSource then return nil,"No confirmed Festergut kill is available for BPC/BQL planning." end
  if self.IsConfirmedFestergutSegment and not self:IsConfirmedFestergutSegment(baseSource) then return nil,"A Festergut wipe or incomplete pull cannot be used for BPC/BQL planning." end
  local baseEntry=selected or self:GetFestergutHistoryEntryForSource(baseSource)
  local source,evidence=self:BuildAudibleFestergutSource(baseSource,roster,baseEntry,not selected and baseSource~=nil)
  local benchmarkRoster=baseEntry and self:SnapshotPlanningRoster(baseEntry.roster) or {}
  local sinceFestergut=#benchmarkRoster>0 and self:BuildRosterDiff(benchmarkRoster,roster) or {incoming={},outgoing={},specChanged={},roleChanged={},availabilityChanged={},replacements=0,changed=false}
  local previous=self.db.latestPlanBundle
  local previousRoster=previous and previous.rosterSnapshot or benchmarkRoster
  local sincePrevious=#(previousRoster or {})>0 and self:BuildRosterDiff(previousRoster,roster) or sinceFestergut

  local priorSaved=self.savedRaidTestRoster
  local priorPlanningRoster=self.planningRosterOverride
  local priorPlanningSource=self.planningSourceOverride
  local priorFestergutSource=self.festergutSourceOverride
  local priorBPCPlan=self.db.latestBPCPlan
  local priorBQLPlan=self.db.latestPlan
  local priorDirty=self.db.planDirty
  local priorDirtyReason=self.db.planDirtyReason
  self.planningRosterOverride=self:SnapshotPlanningRoster(roster)
  self.savedRaidTestRoster=nil
  self.planningSourceOverride=source
  self.festergutSourceOverride=source
  self._buildingPlanBundle=true
  local ok,bpc,bql=pcall(function()
    local bpcPlan=self:BuildBPCPlan()
    local bqlPlan=self:GeneratePlan()
    return bpcPlan,bqlPlan
  end)
  self._buildingPlanBundle=nil
  self.planningRosterOverride=priorPlanningRoster
  self.savedRaidTestRoster=priorSaved
  self.planningSourceOverride=priorPlanningSource
  self.festergutSourceOverride=priorFestergutSource

  self._restoringPlanBundle=true
  if self.ScanRoster then self:ScanRoster() end
  self._restoringPlanBundle=nil
  -- BuildBPCPlan and GeneratePlan retain their latest result for legacy callers.
  -- Restore those side effects until both halves have passed validation so a
  -- failed rebuild cannot expose a mixed revision to UI or export code.
  self.db.latestBPCPlan=priorBPCPlan
  self.db.latestPlan=priorBQLPlan
  self.db.planDirty=priorDirty
  self.db.planDirtyReason=priorDirtyReason
  if not ok then return nil,tostring(bpc) end
  if type(bpc)~="table" or type(bql)~="table" then return nil,"BPC and BQL did not both produce a complete plan." end

  for _,item in ipairs(evidence.historical or {}) do
    local subject=item.reason=="spec-change" and (item.player.name.." changed to "..self:GetSpecName(item.player).." after tonight's Festergut") or (item.player.name.." joined after tonight's Festergut")
    local message=subject.."; using that player's same-spec Festergut history from "..date("%Y-%m-%d %H:%M",item.entry.recordedAt).." ("..math.floor(item.dps or 0).." DPS)."
    appendWarning(bpc,message); appendWarning(bql,message)
  end
  for _,item in ipairs(evidence.missing or {}) do
    local subject=item.reason=="spec-change" and (item.player.name.." changed to "..self:GetSpecName(item.player).." after Festergut") or (item.player.name.." joined after Festergut")
    local message=subject.." with no same-spec Festergut history; ranked conservatively and needs manual review."
    appendWarning(bpc,message); appendWarning(bql,message)
  end

  local generatedAt=self:Now()
  local bundle={
    schemaVersion=PB.SCHEMA_VERSION,version=PB.VERSION,generatedAt=generatedAt,
    reason=options.reason or (selected and "history" or "plan"),mode=selected and "history" or "current",
    source=source,sourceId=source and (source.baseSourceId or source.id) or nil,sourceEntryId=baseEntry and baseEntry.id or nil,
    rosterHash=self:RosterFingerprint(roster),rosterSnapshot=self:SnapshotPlanningRoster(roster),
    benchmarkRosterSnapshot=benchmarkRoster,rosterDiff=sinceFestergut,previousRosterDiff=sincePrevious,
    benchmarkEvidence=evidence,bpc=bpc,bql=bql,historyEntry=selected,rosterCount=#roster,
  }
  bundle.digest=assignmentDigest(bundle)
  if previous and previous.digest==bundle.digest then bundle.revision=previous.revision or 1 else bundle.revision=(previous and previous.revision or 0)+1 end
  bundle.bundleId="prp-"..hashText(token(bundle.sourceId).."|"..bundle.rosterHash.."|"..bundle.digest)
  bundle.planChanges=self:ComparePlanBundles(previous,bundle)
  bundle.largeShuffle=sincePrevious.replacements>=5 or criticalDeparture(previous,sincePrevious)
  bundle.audible={
    generatedAt=generatedAt,revision=bundle.revision,bundleId=bundle.bundleId,
    largeShuffle=bundle.largeShuffle,rosterDiff=sincePrevious,planChanges=bundle.planChanges,
    historicalBenchmarks=#(evidence.historical or {}),missingBenchmarks=#(evidence.missing or {}),
  }

  bpc.generatedAt=generatedAt; bql.generatedAt=generatedAt
  bpc.bundleId=bundle.bundleId; bql.bundleId=bundle.bundleId
  bpc.planRevision=bundle.revision; bql.planRevision=bundle.revision
  bpc.rosterHash=bundle.rosterHash; bql.rosterHash=bundle.rosterHash
  bpc.sourceId=bundle.sourceId; bql.sourceId=bundle.sourceId
  bpc.rosterDiff=sinceFestergut; bql.rosterDiff=sinceFestergut

  self.db.latestPlanBundle=bundle
  self.db.latestBPCPlan=bpc
  self.db.latestPlan=bql
  self.db.planDirty=false
  self.db.planDirtyReason=nil
  self.db.pendingRosterDiff=nil
  if bundle.reason=="audible" then self.db.lastAudible=bundle.audible end
  if self.UpdateUI then self:UpdateUI() end
  return bundle
end

function PB:UpdatePlanDirtyState()
  if not self.db or self._buildingPlanBundle or self._capturingPlanBundle or self._restoringPlanBundle then return end
  local bundle=self.db.latestPlanBundle
  if not bundle or bundle.mode=="history" or self:GetSelectedFestergutHistoryEntrySafe() then return end
  local fingerprint=self:RosterFingerprint(self.roster)
  if fingerprint~=bundle.rosterHash then
    self.db.planDirty=true
    self.db.planDirtyReason="roster"
    self.db.pendingRosterDiff=self:BuildRosterDiff(bundle.rosterSnapshot,self.roster)
  else
    local currentSource=self:GetFestergutSource()
    local currentSourceId=currentSource and (currentSource.baseSourceId or currentSource.id) or nil
    if not currentSourceId or currentSourceId~=bundle.sourceId then
      self.db.planDirty=true
      self.db.planDirtyReason="benchmark"
      self.db.pendingRosterDiff=nil
    else
      self.db.planDirty=false
      self.db.planDirtyReason=nil
      self.db.pendingRosterDiff=nil
    end
  end
end

function PB:RunRosterAudible()
  if self.live and self.live.active then return nil,"Turn Live mode off before running a roster audible." end
  if self:GetSelectedFestergutHistoryEntrySafe() then self:ClearFestergutHistorySelectionSafe(false) end
  self:ScanRoster()
  if #self.roster==0 then return nil,"No live raid roster is available." end
  if not self:GetFestergutSource() then return nil,"No confirmed Festergut kill exists in the current ICC session." end
  return self:BuildPlanBundle({reason="audible"})
end

function PB:AudibleReviewLines(bundle)
  bundle=bundle or (self.db and self.db.latestPlanBundle)
  local audible=bundle and bundle.audible or self.db and self.db.lastAudible
  if not audible then return {"No roster audible has been generated."} end
  local diff=audible.rosterDiff or {}
  local changes=audible.planChanges or {}
  local lines={
    "ROSTER AUDIBLE | REVISION "..token(audible.revision).." | "..(audible.largeShuffle and "FULL REBUILD" or "STANDARD REBUILD"),
    "Roster: "..#(diff.outgoing or {}).." out / "..#(diff.incoming or {}).." in / "..#(diff.specChanged or {}).." spec changes / "..#(diff.roleChanged or {}).." role changes",
    "Plan changes: "..token(changes.positionChanges or 0).." positions / "..token(changes.biteChanges or 0).." bite links / "..token(changes.utilityChanges or 0).." cooldown or utility slots",
    "Replacement benchmarks: "..token(audible.historicalBenchmarks or 0).." same-spec history / "..token(audible.missingBenchmarks or 0).." missing",
  }
  local function names(label,items)
    if #(items or {})==0 then return end
    local values={}; for _,item in ipairs(items) do values[#values+1]=item.name end
    lines[#lines+1]=label..": "..table.concat(values,", ")
  end
  names("OUT",diff.outgoing); names("IN",diff.incoming)
  for _,change in ipairs(changes.details or {}) do
    lines[#lines+1]=change.scope.." | "..change.name.." | "..change.from.." -> "..change.to
  end
  lines[#lines+1]="Both BPC and BQL were regenerated from bundle "..token(audible.bundleId)..". Use /reload, then run the desktop publisher."
  return lines
end
