local PB = PizzaRaidPlanner

local function stableName(p) return (p.name or ""):lower() end

function PB:GetRankedPlayers(live)
  local eligible,fallbacks={},{}
  for _,p in ipairs(self.roster) do
    p.position=self:GetPosition(p)
    local ok,reason=self:IsEligible(p,live)
    p.eligible=ok; p.exclusionReason=reason
    local entry={
      player=p,
      expected=p.expectedDPS,
      adjust=tonumber(self:GetOverride("manualPriorities",p.name)) or 0,
      pinned=self.db.plannedFirst==p.normalizedName,
    }
    if ok then
      eligible[#eligible+1]=entry
    elseif self.db.settings.allowEmergencyFallback and (self:ResolveRole(p)=="tank" or self:ResolveRole(p)=="healer") and p.online and p.connected and (not live or not p.dead) and not self.live.vampires[p.guid] then
      entry.emergency=true; fallbacks[#fallbacks+1]=entry
    end
  end
  local function sort(a,b)
    if a.pinned~=b.pinned then return a.pinned end
    local ad,bd=a.expected~=nil,b.expected~=nil
    if ad~=bd then return ad end
    if ad and a.expected~=b.expected then return a.expected>b.expected end
    if a.adjust~=b.adjust then return a.adjust>b.adjust end
    if (a.player.bossDamage or 0)~=(b.player.bossDamage or 0) then return (a.player.bossDamage or 0)>(b.player.bossDamage or 0) end
    return stableName(a.player)<stableName(b.player)
  end
  table.sort(eligible,sort); table.sort(fallbacks,sort)
  for _,v in ipairs(fallbacks) do eligible[#eligible+1]=v end
  return eligible
end

local function removeFirst(list,predicate)
  for i,item in ipairs(list) do
    if predicate(item) then return table.remove(list,i) end
  end
end

local function positionFor(composition,p)
  return p and composition.byGUID[p.guid] or nil
end

local function appendVampire(list,seen,p)
  if p and not seen[p.guid] then list[#list+1]=p; seen[p.guid]=true end
end

local function assignment(PB,composition,rankByGUID,wave,slot,biter,target,movement)
  local bp,tp=positionFor(composition,biter),positionFor(composition,target.player)
  return {
    wave=wave,slot=slot,
    biter=biter.name,biterGUID=biter.guid,biterClass=biter.classToken,biterPosition=biter.position,
    biterSlot=bp and bp.slot or "",biterLane=bp and bp.lane or "unknown",
    target=target.player.name,targetGUID=target.player.guid,targetClass=target.player.classToken,
    targetRole=PB:ResolveRole(target.player),targetPosition=target.player.position,
    targetSlot=tp and tp.slot or "",targetLane=tp and tp.lane or "unknown",targetDepth=tp and tp.depth or "unknown",
    expectedDPS=target.expected,dpsRank=rankByGUID[target.player.guid],
    movement=movement,status="planned",
  }
end

local function pairWave(PB,composition,rankByGUID,vampires,ranged,melee,wave,forceOpeningHandoff)
  local pairs,usedBiters={},{}
  if forceOpeningHandoff and vampires[1] and composition.secondary then
    local target=removeFirst(ranged,function(item) return item.player.guid==composition.secondary.guid end)
    if target then
      pairs[1]=assignment(PB,composition,rankByGUID,wave,1,vampires[1],target,composition.secondaryHandoff or "Intentional opening handoff; R4 moves to the right lane after the bite.")
      usedBiters[vampires[1].guid]=true
      return pairs
    end
  end

  -- Ranged pairings are a hard same-lane rule after the intentional R1 -> R4
  -- bridge. We do not silently send a positioned player across the room.
  for _,biter in ipairs(vampires) do
    local bp=positionFor(composition,biter)
    local lane=bp and bp.lane
    local target
    if lane=="left" or lane=="right" then
      target=removeFirst(ranged,function(item)
        local tp=positionFor(composition,item.player)
        return tp and tp.lane==lane
      end)
    elseif #ranged>0 then
      -- This is only reachable after an unexpected live first bite with no
      -- ranged lane.  The warning is added by GeneratePlan.
      target=table.remove(ranged,1)
    end
    if target then
      local movement="Unexpected live-root ranged fallback."
      if lane=="left" or lane=="right" then movement="Same-side ranged bite." end
      pairs[#pairs+1]=assignment(PB,composition,rankByGUID,wave,#pairs+1,biter,target,movement)
      usedBiters[biter.guid]=true
    end
  end

  -- Melee enter only after every positioned ranged target is scheduled.  The
  -- final melee wave may be taken from any side, with same-group preference.
  if #ranged==0 then
    for _,biter in ipairs(vampires) do
      if not usedBiters[biter.guid] and #melee>0 then
        local bp=positionFor(composition,biter); local lane=bp and bp.lane
        local target=removeFirst(melee,function(item)
          local tp=positionFor(composition,item.player)
          return tp and lane and tp.lane==lane
        end)
        if not target then target=removeFirst(melee,function(item)
          local tp=positionFor(composition,item.player)
          return tp and tp.lane=="middle"
        end) end
        if not target then target=table.remove(melee,1) end
        if target then
          pairs[#pairs+1]=assignment(PB,composition,rankByGUID,wave,#pairs+1,biter,target,"Final melee wave; same group preferred, any side allowed.")
        end
      end
    end
  end
  return pairs
end

function PB:GeneratePlan(liveRebuild)
  if not self.db then return end
  self:ScanRoster()
  local benchmark=self:GetBQLBenchmarkSource()
  self:ApplySourceToRoster(benchmark,true)

  local ranked=self:GetRankedPlayers(self.live.active)
  local compositionRanked=self.live.active and self:GetRankedPlayers(false) or ranked
  local composition=self:BuildBQLComposition(compositionRanked)
  local plan={
    schemaVersion=PB.SCHEMA_VERSION,generatedAt=self:Now(),
    encounter="Blood-Queen Lana'thel",mode=self.live.active and "live" or "planned",
    flatPriority={},waves={},assignments={},completedAssignments=self.live.completed,
    warnings={},source=benchmark,composition=composition,
  }
  for _,w in ipairs(composition.warnings or {}) do plan.warnings[#plan.warnings+1]=w end
  if not benchmark then plan.warnings[#plan.warnings+1]="No valid Festergut sample exists in the current ICC session; BQL DPS order needs manual review." end

  local rankByGUID,itemByGUID={},{}
  for i,item in ipairs(compositionRanked) do rankByGUID[item.player.guid]=i; itemByGUID[item.player.guid]=item end
  local first
  if self.live.active and self.live.actualFirst then first=self.byGUID[self.live.actualFirst] end
  if not first then first=composition.primary end
  if not first and ranked[1] then first=ranked[1].player end
  if not first then
    plan.warnings[#plan.warnings+1]="No eligible players."
    self.db.latestPlan=plan
    return plan
  end

  plan.first=first.guid
  local assigned={[first.guid]=true}
  local vampires,vampireSeen={},{[first.guid]=true}
  vampires[1]=first
  for _,done in ipairs(self.live.completed or {}) do
    if done.targetGUID then
      assigned[done.targetGUID]=true
      appendVampire(vampires,vampireSeen,self.byGUID[done.targetGUID])
    end
  end
  if self.live.active then
    local extra={}
    for guid in pairs(self.live.vampires or {}) do
      local p=self.byGUID[guid]
      if p and not vampireSeen[guid] then extra[#extra+1]=p end
      assigned[guid]=true
    end
    table.sort(extra,function(a,b)
      local ap,bp=positionFor(composition,a),positionFor(composition,b)
      local ar=ap and ap.biteRank or 99; local br=bp and bp.biteRank or 99
      if ar~=br then return ar<br end
      return stableName(a)<stableName(b)
    end)
    for _,p in ipairs(extra) do appendVampire(vampires,vampireSeen,p) end
  end

  if not self.live.active then
    local fp=positionFor(composition,first)
    local initial={
      wave=0,slot=1,biter=PB.BQL_NAME,biterGUID=nil,biterSlot="Boss",biterLane="center",
      target=first.name,targetGUID=first.guid,targetClass=first.classToken,targetRole=self:ResolveRole(first),targetPosition=first.position,
      targetSlot=fp and fp.slot or "",targetLane=fp and fp.lane or "unknown",targetDepth=fp and fp.depth or "unknown",
      expectedDPS=first.expectedDPS,dpsRank=rankByGUID[first.guid],movement=(fp and fp.note) or "R1 starts left and close to the boss.",status="planned",
    }
    plan.assignments[#plan.assignments+1]=initial; plan.waves[0]={initial}
  elseif not positionFor(composition,first) or positionFor(composition,first).type~="ranged" then
    plan.warnings[#plan.warnings+1]="The actual first vampire has no ranged lane; live fallback movement requires raid-leader review."
  end

  local ranged,melee={},{},{}
  for _,p in ipairs(composition.bitePriority or {}) do
    local item=itemByGUID[p.guid]
    local pos=positionFor(composition,p)
    if item and not assigned[p.guid] then
      if pos and pos.type=="ranged" then ranged[#ranged+1]=item
      else plan.warnings[#plan.warnings+1]=p.name.." has no usable R1-R10 lane and was left out of the automatic bite tree." end
    end
  end
  for _,item in ipairs(ranked) do
    if not assigned[item.player.guid] then
      local pos=positionFor(composition,item.player)
      if pos and pos.type=="melee" then melee[#melee+1]=item
      elseif item.emergency then melee[#melee+1]=item end
    end
  end

  local round=1; local maxRounds=self.live.active and 8 or 4
  while (#ranged>0 or #melee>0) and #vampires>0 and round<=maxRounds do
    local forceOpeningHandoff=not self.live.active and round==1 and first==composition.primary
    local pairs=pairWave(self,composition,rankByGUID,vampires,ranged,melee,round,forceOpeningHandoff)
    if #pairs==0 then
      if #ranged>0 then plan.warnings[#plan.warnings+1]="No same-side vampire remains for "..#ranged.." ranged target(s); no cross-room bite was generated." end
      break
    end
    plan.waves[round]=pairs
    for _,a in ipairs(pairs) do
      plan.assignments[#plan.assignments+1]=a
      assigned[a.targetGUID]=true
    end
    for _,a in ipairs(pairs) do appendVampire(vampires,vampireSeen,self.byGUID[a.targetGUID]) end
    round=round+1
  end
  if not self.live.active and (#ranged>0 or #melee>0) then
    plan.warnings[#plan.warnings+1]=(#ranged+#melee).." lower-priority DPS remain intentionally unassigned after the worksheet's fifth bite."
  end

  local flatSeen={}
  local function addFlat(p,reason)
    if not p or flatSeen[p.guid] then return end
    flatSeen[p.guid]=true
    local pos=positionFor(composition,p)
    plan.flatPriority[#plan.flatPriority+1]={
      name=p.name,guid=p.guid,class=p.classToken,dps=p.expectedDPS,
      rank=#plan.flatPriority+1,dpsRank=rankByGUID[p.guid],position=p.position,
      slot=pos and pos.slot or "",lane=pos and pos.lane or "unknown",reason=reason,
    }
  end
  if self.live.active then
    addFlat(first,"Actual first vampire")
    for _,done in ipairs(self.live.completed or {}) do addFlat(self.byGUID[done.targetGUID],"Completed bite") end
  end
  for _,a in ipairs(plan.assignments) do
    if a.targetGUID and not flatSeen[a.targetGUID] then
      local p=self.byGUID[a.targetGUID]; local pos=positionFor(composition,p)
      local reason="Final melee wave"
      if a.wave==0 then reason=a.targetClass=="MAGE" and "Competent Mage R1 anchor" or "Ranged R1 fallback"
      elseif a.wave==1 then reason="Best remaining Festergut ranged performer; opening handoff"
      elseif pos and pos.type=="ranged" then reason="Ranged-first, same-side chain" end
      addFlat(p,reason)
    end
  end
  local firstFour=math.min(4,#plan.flatPriority)
  for i=1,firstFour do
    local pos=positionFor(composition,self.byGUID[plan.flatPriority[i].guid])
    if not pos or pos.type~="ranged" then
      plan.warnings[#plan.warnings+1]="Opening vampire "..i.." is not ranged; review the raid composition."
    end
  end
  if self.live.active and liveRebuild then plan.warnings[#plan.warnings+1]="Live plan recalculated; completed bites were retained." end
  self.db.latestPlan=plan
  self:BuildExports()
  if self.UpdateUI then self:UpdateUI() end
  return plan
end
