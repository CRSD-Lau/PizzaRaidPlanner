local PB = PizzaRaidPlanner

local function dps(p) return tonumber(p.expectedDPS) or -1 end
local function name(p) return (p.name or ""):lower() end
local function raidOrder(a,b)
  local ai,bi=a.raidIndex or 99,b.raidIndex or 99
  if ai~=bi then return ai<bi end
  return name(a)<name(b)
end
local function appendUnique(out,seen,p)
  if p and not seen[p.guid] then out[#out+1]=p; seen[p.guid]=true end
end
local function isCenterPreferred(p)
  return p.classToken=="WARLOCK" or (p.classToken=="DRUID" and p.spec==102)
end

function PB:IsCompetentMage(p)
  if not p or p.classToken~="MAGE" then return false end
  local override=self.db.competenceOverrides[p.normalizedName]
  if override~=nil then return override end
  return p.expectedDPS~=nil and p.expectedDPS>0
end

function PB:GetUtilityOrder(capability,limit)
  local candidates={}
  for _,p in ipairs(self.roster) do
    if p.online and p.connected then
      local ok,source=self:GetCapability(p,capability)
      if ok then
        candidates[#candidates+1]={
          player=p,
          source=source,
          priority=tonumber(self.db.utilityPriorities[p.normalizedName]) or 0,
        }
      end
    end
  end
  table.sort(candidates,function(a,b)
    local verified={manual=4,["observed cast"]=3,["inspected talent"]=3,["class rule"]=3,["holy spec inference"]=1,["holy/protection inference"]=1}
    local av,bv=verified[a.source] or 0,verified[b.source] or 0
    if a.priority~=b.priority then return a.priority>b.priority end
    if av~=bv then return av>bv end
    if capability=="kinetic" and dps(a.player)~=dps(b.player) then return dps(a.player)>dps(b.player) end
    return raidOrder(a.player,b.player)
  end)
  local result={}
  for i=1,math.min(limit or #candidates,#candidates) do result[i]=candidates[i] end
  return result
end

function PB:GetBQLDSacOrder(shadowAM)
  local candidates=self:GetUtilityOrder("divineSacrifice")
  local result,used={},{}
  local hasManualPriority=false
  for _,item in ipairs(candidates) do if item.priority~=0 then hasManualPriority=true; break end end
  if hasManualPriority then
    for i=1,math.min(3,#candidates) do result[i]=candidates[i] end
    return result
  end

  local firstShadowGUID=shadowAM and shadowAM[1] and shadowAM[1].player.guid
  local function take(predicate)
    for _,item in ipairs(candidates) do
      local guid=item.player.guid
      if not used[guid] and predicate(item) then
        result[#result+1]=item; used[guid]=true; return true
      end
    end
  end

  -- Air phase happens while the raid is spread. Put a capable tank Paladin
  -- first, keep a different Paladin second when possible, and retain the first
  -- Shadow AM holder as the emergency backup instead of double-booking them.
  take(function(item) return self:ResolveRole(item.player)=="tank" end)
  take(function(item) return item.player.guid~=firstShadowGUID end)
  while #result<math.min(3,#candidates) do if not take(function() return true end) then break end end
  return result
end

local function takeSlot(pool,preferred)
  if #pool[preferred]>0 then return table.remove(pool[preferred],1),preferred end
  local other=preferred=="center" and "back" or "center"
  if #pool[other]>0 then return table.remove(pool[other],1),other end
  if pool.overflow and #pool.overflow>0 then return table.remove(pool.overflow,1),"overflow" end
end

local function assignRangedLane(plan,players,lane,pool)
  local center,hunters,normal={},{},{}
  for _,p in ipairs(players) do
    if isCenterPreferred(p) then center[#center+1]=p
    elseif p.classToken=="HUNTER" then hunters[#hunters+1]=p
    else normal[#normal+1]=p end
  end
  local groups={{members=center,depth="center"},{members=hunters,depth="back"},{members=normal,depth="center"}}
  for _,group in ipairs(groups) do
    for _,p in ipairs(group.members) do
      local slotNumber,depth=takeSlot(pool,group.depth)
      if slotNumber then
        local a={type="ranged",slot="R"..slotNumber,slotNumber=slotNumber,lane=lane,depth=depth,player=p,biteRank=plan.biteRankByGUID[p.guid]}
        plan.ranged[#plan.ranged+1]=a; plan.positions[#plan.positions+1]=a; plan.byGUID[p.guid]=a
      else
        plan.warnings[#plan.warnings+1]=p.name.." exceeds the R1-R10 ranged capacity."
      end
    end
  end
end

function PB:BuildBQLComposition(ranked)
  ranked=ranked or self:GetRankedPlayers(false)
  local plan={
    schemaVersion=PB.SCHEMA_VERSION,
    encounter="Blood-Queen Lana'thel",
    generatedAt=self:Now(),
    positions={},byGUID={},ranged={},healers={},melee={},tanks={},warnings={},
    bitePriority={},biteRankByGUID={},utility={shadowAM={},dsac={}},
    rules={
      "A competent Mage is preferred for R1; R4 is the strongest remaining Festergut ranged performer and does not have to be a Mage.",
      "R1 bites R4. R4 starts beside R1 near the center, then uses Blink, Demonic Circle, or assigned movement to reach the right lane.",
      "R1/R2/R3/R5 are left; R4 transitions right; R6-R10 are right. R10 is the final ranged slot.",
      "Ranged targets stay in their lane; melee are saved for the final wave.",
      "Balance Druids and Warlocks favor center slots; Hunters favor back/edge slots.",
      "Melee Rogues and Paladins are assigned to Middle; every other melee DPS is split between Left and Right.",
      "Tanks are detected but are not placed in the healer/ranged/melee DPS position blocks.",
    },
  }
  local rankByGUID={}
  for i,item in ipairs(ranked) do rankByGUID[item.player.guid]=i end
  local function performanceSort(a,b)
    local ar,br=rankByGUID[a.guid],rankByGUID[b.guid]
    if ar and br and ar~=br then return ar<br end
    if ar~=nil and br==nil then return true end
    if ar==nil and br~=nil then return false end
    if dps(a)~=dps(b) then return dps(a)>dps(b) end
    return name(a)<name(b)
  end

  local eligibleByGUID={}
  for _,item in ipairs(ranked) do eligibleByGUID[item.player.guid]=true end
  local ranged,meleeDPS,healers,tanks,mages={},{},{},{},{}
  for _,p in ipairs(self.roster) do
    p.position=self:GetPosition(p)
    local role=self:ResolveRole(p)
    if p.online and p.connected then
      if role=="healer" then
        healers[#healers+1]=p
      elseif role=="tank" and not eligibleByGUID[p.guid] then
        tanks[#tanks+1]=p
      elseif eligibleByGUID[p.guid] then
        if p.position=="ranged" then
          ranged[#ranged+1]=p
          if p.classToken=="MAGE" then mages[#mages+1]=p end
        else
          meleeDPS[#meleeDPS+1]=p
        end
      end
    end
  end
  table.sort(ranged,performanceSort); table.sort(meleeDPS,performanceSort)
  table.sort(healers,raidOrder); table.sort(tanks,raidOrder); plan.tanks=tanks
  table.sort(mages,function(a,b)
    local ac,bc=self:IsCompetentMage(a),self:IsCompetentMage(b)
    if ac~=bc then return ac end
    return performanceSort(a,b)
  end)

  local primary,secondary=mages[1],nil
  if self.db.plannedFirst then
    local forced=self.byName[self.db.plannedFirst]
    if forced and eligibleByGUID[forced.guid] and self:GetPosition(forced)=="ranged" then
      primary=forced
    elseif forced then
      plan.warnings[#plan.warnings+1]="Manual first-bite override "..forced.name.." is not ranged and was ignored by the BQL lane plan."
    end
  end
  if not primary then
    primary=ranged[1]
    plan.warnings[#plan.warnings+1]="No eligible mage found for bite one; using the best ranged DPS fallback."
  end
  for _,p in ipairs(ranged) do if not primary or p.guid~=primary.guid then secondary=p; break end end
  if not secondary then plan.warnings[#plan.warnings+1]="No second eligible ranged DPS is available for the opening handoff." end
  if primary and primary.classToken=="MAGE" and not self:IsCompetentMage(primary) then
    plan.warnings[#plan.warnings+1]=primary.name.." is mage one but has no DPS sample or competence override."
  end

  local ordered,seen={},{}
  appendUnique(ordered,seen,primary); appendUnique(ordered,seen,secondary)
  for _,p in ipairs(ranged) do appendUnique(ordered,seen,p) end
  for i,p in ipairs(ordered) do
    plan.bitePriority[i]=p
    plan.biteRankByGUID[p.guid]=i
  end

  if primary then
    local note=primary.classToken=="MAGE" and "Mage R1 anchor; stand close to the boss for Tricks." or "R1 ranged fallback; start left and close to the boss."
    local a={type="ranged",slot="R1",slotNumber=1,lane="left",startLane="left",depth="front",player=primary,biteRank=1,note=note}
    plan.ranged[#plan.ranged+1]=a; plan.positions[#plan.positions+1]=a; plan.byGUID[primary.guid]=a
  end
  if secondary then
    local handoff
    if secondary.classToken=="MAGE" then handoff="Start at R4 beside R1; after R1 bites you, Blink to the right lane."
    elseif secondary.classToken=="WARLOCK" then handoff="Start at R4 beside R1; pre-place Demonic Circle on the right and teleport after R1 bites you."
    else handoff="Start at R4 beside R1; move across the center to the right lane immediately after R1 bites you." end
    plan.secondaryHandoff=handoff
    local a={type="ranged",slot="R4",slotNumber=4,lane="right",startLane="left",depth="front",player=secondary,biteRank=2,note=handoff}
    plan.ranged[#plan.ranged+1]=a; plan.positions[#plan.positions+1]=a; plan.byGUID[secondary.guid]=a
  end

  local lanePlayers={left={},right={}}
  local laneOrder={"left","right","left","right","left","right","right","right"}
  for i=3,#ordered do
    local lane=laneOrder[i-2] or (#lanePlayers.left<=#lanePlayers.right and "left" or "right")
    lanePlayers[lane][#lanePlayers[lane]+1]=ordered[i]
  end
  assignRangedLane(plan,lanePlayers.left,"left",{center={3,2},back={5}})
  assignRangedLane(plan,lanePlayers.right,"right",{center={8,6},back={10,9,7}})
  table.sort(plan.ranged,function(a,b) return a.slotNumber<b.slotNumber end)

  for i,p in ipairs(healers) do
    if i<=5 then
      local a={type="healer",slot="H"..i,slotNumber=i,lane=(i%2==1) and "left" or "right",depth="support",player=p}
      plan.healers[#plan.healers+1]=a; plan.positions[#plan.positions+1]=a; plan.byGUID[p.guid]=a
    else
      plan.warnings[#plan.warnings+1]=p.name.." exceeds the H1-H5 healer capacity."
    end
  end

  local counts={left=0,right=0,middle=0}; local sidePattern={"left","right"}; local sideCursor=1; local positioned=0
  for _,p in ipairs(meleeDPS) do
    if positioned<10 then
      local centerClass=p.classToken=="ROGUE" or p.classToken=="PALADIN"
      local group
      if centerClass then
        group="middle"
      else
        group=sidePattern[sideCursor]; sideCursor=(sideCursor%#sidePattern)+1
      end
      counts[group]=counts[group]+1; positioned=positioned+1
      local note=centerClass and "Rogue/Paladin reserved for the Middle melee group." or "Non-Rogue/Paladin melee split between the Left and Right groups."
      local a={type="melee",slot="M"..positioned,slotNumber=positioned,lane=group,depth="melee",groupOrder=counts[group],player=p,biteEligible=eligibleByGUID[p.guid] and true or false,note=note}
      plan.melee[#plan.melee+1]=a; plan.positions[#plan.positions+1]=a; plan.byGUID[p.guid]=a
    else
      plan.warnings[#plan.warnings+1]=p.name.." exceeds the worksheet's 10 melee-position capacity."
    end
  end

  plan.primary=primary; plan.secondary=secondary
  plan.utility.shadowAM=self:GetUtilityOrder("auraMastery",4)
  plan.utility.dsac=self:GetBQLDSacOrder(plan.utility.shadowAM)
  if #plan.utility.shadowAM<2 then plan.warnings[#plan.warnings+1]="Fewer than two Aura Mastery Paladins found for the BQL Shadow AM order." end
  if #plan.utility.dsac<2 then plan.warnings[#plan.warnings+1]="Fewer than two Divine Sacrifice Paladins found for BQL air phases." end
  if #plan.bitePriority<4 then plan.warnings[#plan.warnings+1]="Fewer than four eligible ranged DPS; Azy's ranged-first opening cannot be completed." end
  self.db.latestBQLComposition=plan
  return plan
end
