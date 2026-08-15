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

local function positionType(composition,p)
  local position=positionFor(composition,p)
  return (position and position.type) or (p and p.position) or "unknown"
end

local function visualKey(p)
  if not p then return "unknown" end
  return tostring(p.classToken or "unknown")
end

local function appendVampire(list,seen,p)
  if p and not seen[p.guid] then list[#list+1]=p; seen[p.guid]=true end
end

local function assignment(PB,composition,rankByGUID,wave,slot,biter,target,movement,routeLabel,routeMode)
  local bp,tp=positionFor(composition,biter),positionFor(composition,target.player)
  local biterLane=bp and bp.lane or "unknown"
  local targetLane=tp and tp.lane or "unknown"
  routeMode=routeMode or "target-to-biter"
  local biteLane=biterLane
  local returnLane=targetLane
  local temporaryCrossing=(biterLane=="left" or biterLane=="right") and (targetLane=="left" or targetLane=="right") and biterLane~=targetLane
  local exactClass=biter.classToken==target.player.classToken
  local exactSpec=exactClass and tonumber(biter.spec) and tonumber(biter.spec)==tonumber(target.player.spec)
  return {
    wave=wave,slot=slot,
    biter=biter.name,biterGUID=biter.guid,biterClass=biter.classToken,biterPosition=biter.position,
    biterSlot=bp and bp.slot or "",biterLane=biterLane,biterType=positionType(composition,biter),
    target=target.player.name,targetGUID=target.player.guid,targetClass=target.player.classToken,
    targetRole=PB:ResolveRole(target.player),targetPosition=target.player.position,
    targetSlot=tp and tp.slot or "",targetLane=targetLane,targetDepth=tp and tp.depth or "unknown",targetType=positionType(composition,target.player),
    expectedDPS=target.expected,dpsRank=rankByGUID[target.player.guid],
    biteLane=biteLane,returnLane=returnLane,temporaryCrossing=temporaryCrossing,
    routeMode=routeMode,biterHoldLane=biteLane,targetReturnLane=targetLane,
    traveler=target.player.name,travelerGUID=target.player.guid,biteTraveler=target.player.name,biteTravelerGUID=target.player.guid,
    returnActor="target",biterMoves=false,targetMoves=true,biterKeepsDPS=true,exactClassMatch=exactClass,exactSpecMatch=exactSpec and true or false,
    movement=movement,routeLabel=routeLabel,status="planned",
  }
end

local function itemLane(composition,item)
  local p=item and item.player
  local position=positionFor(composition,p)
  return position and position.lane or nil
end

local function hasLane(list,composition,lane)
  for _,item in ipairs(list) do if itemLane(composition,item)==lane then return true end end
  return false
end

local function popBalancedSideTarget(list,composition,counts)
  local hasLeft=hasLane(list,composition,"left")
  local hasRight=hasLane(list,composition,"right")
  local lane
  if hasLeft and hasRight then lane=counts.left<=counts.right and "left" or "right"
  elseif hasLeft then lane="left"
  elseif hasRight then lane="right"
  else return nil end
  local target=removeFirst(list,function(item) return itemLane(composition,item)==lane end)
  if target then counts[lane]=counts[lane]+1 end
  return target
end

local function buildWaveTargets(composition,ranged,melee,limit)
  local targets={}
  local counts={left=0,right=0,middle=0}
  while #targets<limit and #ranged>0 do
    local target=popBalancedSideTarget(ranged,composition,counts) or table.remove(ranged,1)
    if not target then break end
    local lane=itemLane(composition,target)
    if lane~="left" and lane~="right" then
      lane=lane or "middle"; counts[lane]=(counts[lane] or 0)+1
    end
    targets[#targets+1]=target
  end
  -- Once every ranged player is scheduled, fill the remaining bites from the
  -- side melee groups before using Middle. This preserves rear-attack space
  -- and keeps each wave's new Left/Right vampires as even as the roster allows.
  if #ranged==0 then
    while #targets<limit and #melee>0 do
      local target=popBalancedSideTarget(melee,composition,counts)
      if not target then
        target=removeFirst(melee,function(item) return itemLane(composition,item)=="middle" end) or table.remove(melee,1)
        if target then
          local lane=itemLane(composition,target) or "middle"
          counts[lane]=(counts[lane] or 0)+1
        end
      end
      if not target then break end
      targets[#targets+1]=target
    end
  end
  return targets
end

local function targetWrapper(item,pool)
  return {item=item,pool=pool}
end

local function removeTargetWrapper(targets,index)
  local wrapper=table.remove(targets,index)
  if wrapper then removeFirst(wrapper.pool,function(item) return item==wrapper.item end) end
  return wrapper and wrapper.item
end

local function targetPairScore(composition,biter,target)
  local bp,tp=positionFor(composition,biter),positionFor(composition,target.player)
  local biterType=positionType(composition,biter)
  local targetType=positionType(composition,target.player)
  local biterLane=bp and bp.lane or "unknown"
  local targetLane=tp and tp.lane or "unknown"
  local score=0
  if biterType==targetType then score=score+10000 end
  if biterLane==targetLane then score=score+5000
  elseif biterType=="melee" and targetType=="melee" and (biterLane=="middle" or targetLane=="middle") then score=score+4000
  elseif biterType==targetType then score=score+1000 end
  if biter.classToken==target.player.classToken then
    score=score+600
    if tonumber(biter.spec) and tonumber(biter.spec)==tonumber(target.player.spec) then score=score+300 end
  end
  return score
end

local function movementForPair(composition,wave,biter,target,roleSeed)
  local bp,tp=positionFor(composition,biter),positionFor(composition,target.player)
  local biterLane=bp and bp.lane or "unknown"
  local targetLane=tp and tp.lane or "unknown"
  local crossing=(biterLane=="left" or biterLane=="right") and (targetLane=="left" or targetLane=="right") and biterLane~=targetLane
  local movement,routeLabel,routeMode
  if crossing then
    movement=target.player.name.." moves from "..targetLane.." to "..biter.name.." on "..biterLane.."; "..biter.name.." holds position and keeps DPSing. Focus-bite when "..target.player.name.." is in range, then "..target.player.name.." returns "..targetLane.." for Bloodbolt Whirl."
    routeLabel="TARGET TO "..biterLane:sub(1,1):upper().." > HOME "..targetLane:sub(1,1):upper()
  elseif targetLane=="middle" then
    movement=target.player.name.." comes from Middle to "..biter.name.." on "..biterLane.."; "..biter.name.." holds position and keeps DPSing. Focus-bite when "..target.player.name.." is in range, then "..target.player.name.." returns Middle for Bloodbolt Whirl."
    routeLabel="TARGET TO "..biterLane:sub(1,1):upper().." > HOME M"
  elseif targetLane=="left" or targetLane=="right" then
    movement=target.player.name.." comes to "..biter.name.." on the same side while "..biter.name.." holds position and keeps DPSing. Focus-bite when in range, then "..target.player.name.." resumes the assigned "..targetLane.."-side spread for Bloodbolt Whirl."
    if roleSeed then routeLabel="MDPS SEED "..targetLane:sub(1,1):upper() end
  else
    movement=target.player.name.." comes to the stationary biter for the focus bite, then returns to the assigned spread position."
  end
  return movement,routeLabel,routeMode
end

local function makeAssignment(PB,composition,rankByGUID,wave,slot,biter,target,roleSeed)
  local movement,routeLabel,routeMode=movementForPair(composition,wave,biter,target,roleSeed)
  local result=assignment(PB,composition,rankByGUID,wave,slot,biter,target,movement,routeLabel,routeMode)
  if roleSeed then result.chainPurpose="ranged-to-melee-seed" end
  return result
end

local function pairBestMatches(PB,composition,rankByGUID,vampires,targets,wave,roleSeed)
  local pairs={}
  local biters={}
  for i,p in ipairs(vampires) do biters[i]=p end
  while #biters>0 and #targets>0 do
    local biterIndex,targetIndex,bestScore,bestDPS,bestBiterName,bestTargetName
    for bi,biter in ipairs(biters) do
      for ti,wrapper in ipairs(targets) do
        local target=wrapper.item
        local score=targetPairScore(composition,biter,target)
        local targetDPS=tonumber(target.expected) or -1
        local biterName=stableName(biter)
        local targetName=stableName(target.player)
        if not biterIndex or score>bestScore or
          (score==bestScore and targetDPS>bestDPS) or
          (score==bestScore and targetDPS==bestDPS and biterName<bestBiterName) or
          (score==bestScore and targetDPS==bestDPS and biterName==bestBiterName and targetName<bestTargetName) then
          biterIndex,targetIndex,bestScore,bestDPS,bestBiterName,bestTargetName=bi,ti,score,targetDPS,biterName,targetName
        end
      end
    end
    local biter=table.remove(biters,biterIndex)
    local target=removeTargetWrapper(targets,targetIndex)
    if target then pairs[#pairs+1]=makeAssignment(PB,composition,rankByGUID,wave,#pairs+1,biter,target,roleSeed) end
  end
  return pairs
end

local function takeLaneTarget(pool,composition,lane)
  return removeFirst(pool,function(item)
    local position=positionFor(composition,item.player)
    return position and position.lane==lane
  end)
end

local function buildMeleeSeedPairs(PB,composition,rankByGUID,vampires,ranged,melee,wave)
  local leftTarget=takeLaneTarget(melee,composition,"left")
  local rightTarget=takeLaneTarget(melee,composition,"right")
  if not leftTarget then leftTarget=takeLaneTarget(melee,composition,"middle") or table.remove(melee,1) end
  if not rightTarget then rightTarget=takeLaneTarget(melee,composition,"middle") or table.remove(melee,1) end
  if not leftTarget then leftTarget=takeLaneTarget(ranged,composition,"left") or table.remove(ranged,1) end
  if not rightTarget then rightTarget=takeLaneTarget(ranged,composition,"right") or table.remove(ranged,1) end

  local available={}
  for i,p in ipairs(vampires) do available[i]=p end
  local primary=composition.primary and removeFirst(available,function(p) return p.guid==composition.primary.guid end) or table.remove(available,1)
  local secondary=composition.secondary and removeFirst(available,function(p) return p.guid==composition.secondary.guid end) or table.remove(available,1)
  local pairs={}
  if primary and leftTarget then pairs[#pairs+1]=makeAssignment(PB,composition,rankByGUID,wave,#pairs+1,primary,leftTarget,true) end
  if secondary and rightTarget then pairs[#pairs+1]=makeAssignment(PB,composition,rankByGUID,wave,#pairs+1,secondary,rightTarget,true) end
  local leftovers={}
  if leftTarget and not primary then leftovers[#leftovers+1]=targetWrapper(leftTarget,melee) end
  if rightTarget and not secondary then leftovers[#leftovers+1]=targetWrapper(rightTarget,melee) end
  if #leftovers>0 and #available>0 then
    local extra=pairBestMatches(PB,composition,rankByGUID,available,leftovers,wave,true)
    for _,a in ipairs(extra) do pairs[#pairs+1]=a end
  end
  return pairs
end

local function categoryKey(composition,p)
  local position=positionFor(composition,p)
  if not position then return nil end
  local kind=position.type
  local lane=position.lane
  if (kind=="ranged" or kind=="melee") and (lane=="left" or lane=="right") then return kind..":"..lane end
end

local function countCategoryKey(players,composition,category,key)
  local count=0
  for _,p in ipairs(players) do if categoryKey(composition,p)==category and visualKey(p)==key then count=count+1 end end
  return count
end

local function countPoolCategoryKey(pool,composition,category,key)
  local count=0
  for _,item in ipairs(pool) do if categoryKey(composition,item.player)==category and visualKey(item.player)==key then count=count+1 end end
  return count
end

local function takeFutureMatchSeed(pool,composition,category,futureBiters)
  local bestIndex,bestGain,bestTargetCount,bestDPS,bestName
  for i,item in ipairs(pool) do
    if categoryKey(composition,item.player)==category then
      local key=visualKey(item.player)
      local biterCount=countCategoryKey(futureBiters,composition,category,key)
      local targetCount=countPoolCategoryKey(pool,composition,category,key)
      local before=math.min(biterCount,targetCount)
      local after=math.min(biterCount+1,targetCount-1)
      local gain=after-before
      local targetDPS=tonumber(item.expected) or -1
      local targetName=stableName(item.player)
      if not bestIndex or gain>bestGain or
        (gain==bestGain and targetCount<bestTargetCount) or
        (gain==bestGain and targetCount==bestTargetCount and targetDPS>bestDPS) or
        (gain==bestGain and targetCount==bestTargetCount and targetDPS==bestDPS and targetName<bestName) then
        bestIndex,bestGain,bestTargetCount,bestDPS,bestName=i,gain,targetCount,targetDPS,targetName
      end
    end
  end
  if bestIndex then return table.remove(pool,bestIndex) end
end

local function takeHighestRemaining(ranged,melee)
  local r,m=ranged[1],melee[1]
  if not r then return table.remove(melee,1),melee end
  if not m then return table.remove(ranged,1),ranged end
  if (tonumber(r.expected) or -1)>=(tonumber(m.expected) or -1) then return table.remove(ranged,1),ranged end
  return table.remove(melee,1),melee
end

local function buildRoleBalanceTargets(composition,vampires,ranged,melee,limit)
  local targets={}
  local futureBiters={}
  for i,p in ipairs(vampires) do futureBiters[i]=p end
  local finalCount=#vampires+limit
  local goal=math.floor(finalCount/4)
  local categories={"ranged:left","ranged:right","melee:left","melee:right"}
  local pools={ranged=ranged,melee=melee}
  local current={}
  for _,category in ipairs(categories) do current[category]=0 end
  for _,p in ipairs(vampires) do local category=categoryKey(composition,p); if current[category]~=nil then current[category]=current[category]+1 end end
  for _,category in ipairs(categories) do
    local kind=category:match("^(%a+):")
    while #targets<limit and current[category]<goal do
      local target=takeFutureMatchSeed(pools[kind],composition,category,futureBiters)
      if not target then break end
      targets[#targets+1]=targetWrapper(target,pools[kind])
      futureBiters[#futureBiters+1]=target.player
      current[category]=current[category]+1
    end
  end
  while #targets<limit and (#ranged>0 or #melee>0) do
    local target,pool=takeHighestRemaining(ranged,melee)
    if not target then break end
    targets[#targets+1]=targetWrapper(target,pool)
  end
  return targets
end

local function wrapSelectedTargets(targets)
  local result={}
  for _,target in ipairs(targets) do result[#result+1]=targetWrapper(target,{}) end
  return result
end

local function wrapAllTargets(ranged,melee)
  local result={}
  for _,target in ipairs(ranged) do result[#result+1]=targetWrapper(target,ranged) end
  for _,target in ipairs(melee) do result[#result+1]=targetWrapper(target,melee) end
  return result
end

local function pairWave(PB,composition,rankByGUID,vampires,ranged,melee,wave,forceOpeningHandoff)
  local pairs={}
  if forceOpeningHandoff and vampires[1] and composition.secondary then
    local target=removeFirst(ranged,function(item) return item.player.guid==composition.secondary.guid end)
    if target then
      pairs[1]=assignment(PB,composition,rankByGUID,wave,1,vampires[1],target,composition.secondaryHandoff or "R6 comes to the stationary R1 for the second bite, then returns to the R6 right-side home and stays there.","R6 TO R1 > HOME R","opening-cross")
      return pairs
    end
  end

  if not PB.live.active and wave==2 then
    return buildMeleeSeedPairs(PB,composition,rankByGUID,vampires,ranged,melee,wave)
  end

  if not PB.live.active and wave==3 then
    local targets=buildRoleBalanceTargets(composition,vampires,ranged,melee,#vampires)
    return pairBestMatches(PB,composition,rankByGUID,vampires,targets,wave,false)
  end

  if not PB.live.active and wave>=4 then
    return pairBestMatches(PB,composition,rankByGUID,vampires,wrapAllTargets(ranged,melee),wave,false)
  end

  local targets=buildWaveTargets(composition,ranged,melee,#vampires)
  return pairBestMatches(PB,composition,rankByGUID,vampires,wrapSelectedTargets(targets),wave,false)
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
      if #ranged>0 then plan.warnings[#plan.warnings+1]="No positioned vampire remains for "..#ranged.." ranged target(s); the automatic bite tree stopped." end
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
      local reason="Late role/side-matched bite"
      if a.wave==0 then reason=a.targetClass=="MAGE" and "Competent Mage R1 anchor" or "Ranged R1 fallback"
      elseif a.wave==1 then reason="Best remaining Festergut ranged performer; opening handoff"
      elseif a.wave==2 then reason="Third bite: ranged-to-melee side seed"
      elseif a.exactSpecMatch then reason="Same-role, same-side, same-spec bite"
      elseif a.exactClassMatch then reason="Same-role, same-side, same-class bite"
      elseif pos and pos.type==a.biterType and pos and pos.lane==a.biterLane then reason="Same-role, same-side bite"
      elseif pos and pos.type==a.biterType then reason="Same-role bite with spatial fallback" end
      addFlat(p,reason)
    end
  end
  for i=1,math.min(2,#plan.flatPriority) do
    local pos=positionFor(composition,self.byGUID[plan.flatPriority[i].guid])
    if not pos or pos.type~="ranged" then
      plan.warnings[#plan.warnings+1]="Opening vampire "..i.." is not ranged; the left-to-right opening needs review."
    end
  end
  for i=3,math.min(4,#plan.flatPriority) do
    local pos=positionFor(composition,self.byGUID[plan.flatPriority[i].guid])
    if not pos or pos.type~="melee" then
      plan.warnings[#plan.warnings+1]="Third-bite target "..(i-2).." is not melee; the ranged-to-melee seed needs review."
    end
  end
  if self.live.active and liveRebuild then plan.warnings[#plan.warnings+1]="Live plan recalculated; completed bites were retained." end
  self.db.latestPlan=plan
  if not self._buildingPlanBundle and self.db then self.db.planDirty=true; self.db.planDirtyReason="legacy-plan" end
  if self.UpdateUI then self:UpdateUI() end
  return plan
end
