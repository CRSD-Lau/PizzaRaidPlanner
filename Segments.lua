local PB = PizzaRaidPlanner
function PB:StartAutomaticSegment()
  if not self:IsICCTrackingActive() then return false end
  if self.segment and self.segment.active then self.segment.leftAt=nil; return true end
  local session=self.db.iccSession
  self.segment={ active=true,id="seg-"..self:Now(),started=self:Now(),lastHostile=self:Now(),players={},targets={},killedBosses={},petDamage=0,manual=false,iccSessionId=session.id,instanceName=session.instanceName,difficultyName=session.difficultyName }
  self:Debug("Damage segment started")
  return true
end
function PB:StartManualSample()
  if not self:StartAutomaticSegment() then self:Print("Damage samples are available only inside Icecrown Citadel."); return end
  self.segment.manual=true; self:Print("Damage sample started.")
end
function PB:MarkCombatLeft() if self.segment and self.segment.active then self.segment.leftAt=self:Now() end end
function PB:StopSample()
  if self.segment and self.segment.active then self:FinishSegment(true) else self:Print("No active sample.") end
end
function PB:ResetSample() self.segment=nil; self:Print("Current sample discarded.") end
function PB:MarkSegmentBossKill(guid,name,evidence)
  local segment=self.segment
  if not segment or not segment.active then return nil end
  local key=self.GetICCBossKey and self:GetICCBossKey(guid,name)
  if not key then return nil end
  segment.killedBosses=segment.killedBosses or {}
  segment.killedBosses[key]={guid=guid,name=name,evidence=evidence or "combat log",at=self:Now()}
  return key
end
function PB:RecordSegmentDamage(ownerGuid,targetGuid,targetName,amount,healing)
  local s=self.segment; if not s or not s.active or not ownerGuid then return end
  local p=s.players[ownerGuid] or { totalDamage=0,primaryDamage=0,healing=0,rawDamage=0,unbuffedDamage=0 }; s.players[ownerGuid]=p
  if healing then p.healing=p.healing+amount; return end
  p.totalDamage=p.totalDamage+amount; p.rawDamage=p.rawDamage+amount
  if not self.live.vampires[ownerGuid] then p.unbuffedDamage=p.unbuffedDamage+amount end
  if targetGuid then local t=s.targets[targetGuid] or {name=targetName or "Unknown",damage=0}; s.targets[targetGuid]=t; t.damage=t.damage+amount end
  s.lastHostile=self:Now()
end
function PB:FinishSegment(forced)
  local s=self.segment; if not s or not s.active then return end
  s.active=false; local ended=self:Now(); local duration=math.max(1,ended-s.started)
  local primaryGUID,primary=nil,nil
  for guid,t in pairs(s.targets) do if not primary or t.damage>primary.damage then primaryGUID,primary=guid,t end end
  local total=0; for _,p in pairs(s.players) do total=total+p.totalDamage; p.primaryDamage=0 end
  local boss=self:GetICCBossSummary(s)
  local focusGUIDs=boss and boss.targetGUIDs or (primaryGUID and {[primaryGUID]=true} or {})
  local isBQL=(boss and boss.key=="bql") or (primary and self:IsBQL(primaryGUID,primary.name))
  if primaryGUID then for guid,p in pairs(s.players) do
    local primaryDamage,primaryUnbuffedDamage=0,0
    for targetGUID in pairs(focusGUIDs) do
      primaryDamage=primaryDamage+((s.perTarget and s.perTarget[guid] and s.perTarget[guid][targetGUID]) or 0)
      primaryUnbuffedDamage=primaryUnbuffedDamage+((s.perTargetUnbuffed and s.perTargetUnbuffed[guid] and s.perTargetUnbuffed[guid][targetGUID]) or ((s.perTarget and s.perTarget[guid] and s.perTarget[guid][targetGUID]) or 0))
    end
    p.primaryDamage=primaryDamage
    p.primaryUnbuffedDamage=primaryUnbuffedDamage
    local baseline=isBQL and p.primaryUnbuffedDamage or p.primaryDamage
    p.dps=baseline/duration
  end end
  local focusDamage=boss and boss.damage or (primary and primary.damage or 0)
  local primaryShare=total>0 and focusDamage/total or 0
  local valid=duration>=PB.MIN_SEGMENT_DURATION and focusDamage>=PB.MIN_SEGMENT_DAMAGE and primary~=nil and primaryShare>=0.45
  if not boss and not s.manual then
    self.segment=nil
    self:Debug("Non-boss ICC damage segment ignored")
    return
  end
  local averageEligible=valid and boss and PB.ICC_AVERAGE_ENCOUNTERS[boss.key] or false
  local kill=boss and s.killedBosses and s.killedBosses[boss.key] or nil
  local result=kill and "kill" or (boss and "wipe" or "unknown")
  local record={id=s.id,targetGUID=primaryGUID,targetName=boss and boss.name or (primary and primary.name or "Unknown"),startTime=s.started,endTime=ended,duration=duration,raidSize=#self.roster,totalDamage=total,bossDamage=focusDamage,primaryShare=primaryShare,isBQL=isBQL,isICCBoss=boss~=nil,iccEncounter=boss and boss.key or nil,averageEligible=averageEligible,iccSessionId=s.iccSessionId,instanceName=s.instanceName,difficultyName=s.difficultyName,players=s.players,valid=valid,confidence=valid and "Good" or "Low",manual=s.manual,result=result,confirmedKill=result=="kill",killEvidence=kill and kill.evidence or nil}
  if averageEligible then self:AddICCSampleToAverage(record) end
  if valid and record.iccEncounter=="festergut" and self.RememberFestergutHistory then self:RememberFestergutHistory(record,self.roster) end
  local list=self.db.segments; list[#list+1]=record; while #list>PB.MAX_SEGMENTS do table.remove(list,1) end
  self.segment=nil; self:Print((boss and "ICC boss sample "..record.targetName or "Manual sample").." saved ("..(boss and result or (valid and "valid" or "flagged"))..", "..math.floor(duration).."s).")
  self:ApplySourceToRoster()
end
function PB:GetSelectedSource()
  if not self.db then return nil end
  if self.planningSourceOverride then return self.planningSourceOverride end
  if self.live and self.live.active and self.live.frozenSource then return self.live.frozenSource end
  local setting=self.db.settings.source or "auto"; local segments=self.db.segments
  if setting=="current" and self.segment and self.segment.active then
    local targetGUID,target=nil,nil; for guid,t in pairs(self.segment.targets) do if not target or t.damage>target.damage then targetGUID,target=guid,t end end
    if target then
      local duration=math.max(1,self:Now()-self.segment.started); local snapshot={id="current",targetGUID=targetGUID,targetName=target.name,duration=duration,players={},confidence="Live sample"}
      local isBQL=self:IsBQL(targetGUID,target.name)
      for guid,p in pairs(self.segment.players) do
        local primary=self.segment.perTarget and self.segment.perTarget[guid] and self.segment.perTarget[guid][targetGUID] or 0
        local unbuffed=self.segment.perTargetUnbuffed and self.segment.perTargetUnbuffed[guid] and self.segment.perTargetUnbuffed[guid][targetGUID] or primary
        snapshot.players[guid]={totalDamage=p.totalDamage,primaryDamage=primary,primaryUnbuffedDamage=unbuffed,healing=p.healing,dps=(isBQL and unbuffed or primary)/duration}
      end
      return snapshot
    end
  end
  if setting=="segment" and self.db.selectedSegmentId then for _,s in ipairs(segments) do if s.id==self.db.selectedSegmentId then return s end end end
  if setting=="median" then
    local valid={}; for i=#segments,1,-1 do if segments[i].valid then valid[#valid+1]=segments[i]; if #valid>=(self.db.settings.medianCount or 3) then break end end end
    if #valid==0 then return nil end
    local result={id="median-"..#valid,targetName="Median of "..#valid.." segments",duration=1,players={},confidence="Median"}
    for _,s in ipairs(valid) do for guid,p in pairs(s.players) do local r=result.players[guid] or {values={},totalDamage=0,healing=0}; result.players[guid]=r; r.values[#r.values+1]=p.dps or 0; r.totalDamage=r.totalDamage+(p.totalDamage or 0); r.healing=r.healing+(p.healing or 0) end end
    for _,p in pairs(result.players) do table.sort(p.values); p.dps=p.values[math.ceil(#p.values/2)]; p.primaryDamage=p.dps; p.values=nil end
    return result
  end
  if setting=="auto" or setting=="icc" then
    local average=self:GetICCAverageSource()
    if average then return average end
    if setting=="icc" then return nil end
  end
  -- Explicit "last" can inspect history. Automatic mode is constrained to
  -- the current ICC session so an old raid night can never silently rank BQL.
  local sessionId=self.db.iccSession and self.db.iccSession.id
  for i=#segments,1,-1 do
    local candidate=segments[i]
    if candidate.valid and (setting~="auto" or (candidate.iccSessionId==sessionId and not candidate.isBQL)) then return candidate end
  end
  if setting=="auto" and self.GetSkadaSource then return self:GetSkadaSource() end
end
function PB:Tick(elapsed)
  self._tick=(self._tick or 0)+elapsed
  self._iccTouchTick=(self._iccTouchTick or 0)+elapsed
  if self._iccTouchTick>=30 then self._iccTouchTick=0; if self.TouchICCSession then self:TouchICCSession() end end
  if self.segment and self.segment.active and self.segment.leftAt and self:Now()-self.segment.leftAt>=PB.SEGMENT_GRACE and self:Now()-(self.segment.lastHostile or 0)>=PB.SEGMENT_GRACE then self:FinishSegment() end
  if self._tick>.5 then self._tick=0; if self.UpdateUI then self:UpdateUI() end end
end
