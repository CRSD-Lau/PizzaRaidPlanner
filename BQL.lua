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
local function isRet(p) return p.classToken=="PALADIN" and tonumber(p.spec)==70 end
local function isFeral(p) return p.classToken=="DRUID" and tonumber(p.spec)==103 end
local function isRogue(p) return p.classToken=="ROGUE" end
local function isDeathKnight(p) return p.classToken=="DEATHKNIGHT" end

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
    for i=1,math.min(4,#candidates) do result[i]=candidates[i] end
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
  while #result<math.min(4,#candidates) do if not take(function() return true end) then break end end
  return result
end

function PB:GetBQLShadowAMOrder()
  local candidates={}
  for _,item in ipairs(self:GetUtilityOrder("auraMastery")) do
    -- BQL tanks remain available for Bloodbolt Whirl DSac, but are never
    -- placed in the Pact Shadow AM rotation. This also prevents stale talent
    -- evidence or a utility priority from assigning a Protection Paladin AM.
    if self:ResolveRole(item.player)~="tank" then candidates[#candidates+1]=item end
  end
  local hasManualPriority=false
  for _,item in ipairs(candidates) do if item.priority~=0 then hasManualPriority=true; break end end

  -- The normal BQL cadence uses Retribution AMs first, then a third holder for
  -- the late P1/P2 links, while a fourth holder is deliberately saved for the
  -- first link after air two. Explicit /prp priority values still override this
  -- automatic role order.
  if not hasManualPriority then
    table.sort(candidates,function(a,b)
      local function roleOrder(item)
        local p=item.player
        if isRet(p) then return 1 end
        local role=self:ResolveRole(p)
        if role=="healer" then return 2 end
        if role=="tank" then return 3 end
        return 4
      end
      local ar,br=roleOrder(a),roleOrder(b)
      if ar~=br then return ar<br end
      return raidOrder(a.player,b.player)
    end)
  end

  local result={}
  for i=1,math.min(4,#candidates) do result[i]=candidates[i] end
  return result
end

function PB:BuildBQLCooldownPlan(shadowAM,dsac)
  shadowAM=shadowAM or {}
  dsac=dsac or {}
  local a1=shadowAM[1] and shadowAM[1].player
  local a2=shadowAM[2] and shadowAM[2].player
  local a3=shadowAM[3] and shadowAM[3].player
  local a4=shadowAM[4] and shadowAM[4].player
  local d1=dsac[1] and dsac[1].player
  local d2=dsac[2] and dsac[2].player
  local function display(p) return p and p.name or "—" end
  local function pair(a,b) return display(a).." / "..display(b) end

  local plan={
    rows={
      {leftEvent="1st",leftPlayers=display(a1),leftCooldown="AM",rightEvent="1st / 2nd",rightPlayers=pair(a1,a2),rightCooldown="AM"},
      {leftEvent="2nd",leftPlayers=display(a2),leftCooldown="AM",rightEvent="3rd",rightPlayers=display(a3),rightCooldown="AM"},
      {leftEvent="3rd / 4th",leftPlayers=pair(a3,a4),leftCooldown="AM",rightEvent="AIR",rightPlayers=display(d2),rightCooldown="DSAC"},
      {leftEvent="AIR",leftPlayers=display(d1),leftCooldown="DSAC",rightEvent="1st / 2nd",rightPlayers=pair(a4,a1),rightCooldown="AM"},
    },
    events={
      {phase="P1",mechanic="Link 1",ability="Shadow AM",players={a1}},
      {phase="P1",mechanic="Link 2",ability="Shadow AM",players={a2}},
      {phase="P1",mechanic="Link 3",ability="Shadow AM",players={a3}},
      {phase="P1",mechanic="Link 4",ability="Shadow AM",players={a4}},
      {phase="Air 1",mechanic="Bloodbolt Whirl",ability="DSac",players={d1}},
      {phase="P2",mechanic="Link 1",ability="Shadow AM",players={a1}},
      {phase="P2",mechanic="Link 2",ability="Shadow AM",players={a2}},
      {phase="P2",mechanic="Link 3",ability="Shadow AM",players={a3}},
      {phase="Air 2",mechanic="Bloodbolt Whirl",ability="DSac",players={d2}},
      {phase="P3",mechanic="Link 1",ability="Shadow AM",players={a4}},
      {phase="P3",mechanic="Link 2",ability="Shadow AM",players={a1}},
    },
    warnings={},
  }
  if #shadowAM<4 then plan.warnings[#plan.warnings+1]="Fewer than four Shadow Aura Mastery Paladins found for the 4 / 3 / 2 Pact of the Darkfallen link rotation." end
  if #dsac<2 then plan.warnings[#plan.warnings+1]="Fewer than two Divine Sacrifice Paladins found for the two Bloodbolt Whirl air phases." end
  return plan
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
      "A competent Mage is preferred for R1; R6 is the strongest remaining Festergut ranged performer and does not have to be a Mage.",
      "Bite targets come to their assigned vampire; the biter holds position and keeps DPSing, then the target returns to their home-side spread.",
      "The second bite spreads the vampire from left to right: R6 comes to the stationary R1 for the focus bite, then returns to the R6 right-side home and stays there.",
      "The third bite deliberately goes from ranged to melee: R1 bites a left-side melee DPS while R6 bites a right-side melee DPS.",
      "R1-R5 are left-side homes and R6-R10 are right-side homes. R1 anchors the left branch and R6 anchors the right branch.",
      "The fourth and fifth bites prefer same-role and same-side pairings. Same class/spec is the next tiebreaker so visually similar players are deliberately paired.",
      "Repeated ranged classes/specs are grouped into local pairs, then those pairs are balanced across the room. Four Balance Druids become two per side; two Hunters or Shadow Priests stay together for an unambiguous same-look bite.",
      "Balance Druids and Warlocks favor center slots; Hunters favor back/edge slots.",
      "Rogues and DPS Death Knights use Middle; adequately performing Feral Druids also use Middle for rear attacks.",
      "Retribution Paladins stay on the sides because Wings and Divine Shield lock each other out; all three melee groups remain as even as the hard constraints allow.",
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
    if secondary.classToken=="MAGE" then
      handoff="R6 is your right-side home. Come to the stationary R1 for the second focus bite, then return home to R6 with Blink and stay there. For the third bite, the assigned right-side melee target comes to you while you hold position and keep DPSing."
    elseif secondary.classToken=="WARLOCK" then
      handoff="R6 is your right-side home. Pre-place Demonic Circle at R6, come to the stationary R1 for the second focus bite, then return home to R6 with the port and stay there. For the third bite, the assigned right-side melee target comes to you while you hold position and keep DPSing."
    else
      handoff="R6 is your right-side home. Come to the stationary R1 for the second focus bite, then return home to R6 and stay there. For the third bite, the assigned right-side melee target comes to you while you hold position and keep DPSing."
    end
    plan.secondaryHandoff=handoff
    local a={type="ranged",slot="R6",slotNumber=6,lane="right",startLane="right",returnLane="right",depth="front",player=secondary,biteRank=2,note=handoff}
    plan.ranged[#plan.ranged+1]=a; plan.positions[#plan.positions+1]=a; plan.byGUID[secondary.guid]=a
  end

  local lanePlayers={left={},right={}}
  local laneCapacity={left=4,right=4}
  local visualCounts={left={},right={}}
  local function rangedVisualKey(p) return tostring(p.classToken or "unknown") end
  local function countVisual(lane,key) return visualCounts[lane][key] or 0 end
  local function rememberVisual(lane,p)
    local key=rangedVisualKey(p)
    visualCounts[lane][key]=countVisual(lane,key)+1
  end
  if primary then rememberVisual("left",primary) end
  if secondary then rememberVisual("right",secondary) end
  local visualGroups,groupOrder={},{ }
  for i=3,#ordered do
    local p=ordered[i]
    local key=rangedVisualKey(p)
    if not visualGroups[key] then visualGroups[key]={}; groupOrder[#groupOrder+1]=key end
    visualGroups[key][#visualGroups[key]+1]=p
  end
  local function room(lane) return laneCapacity[lane]-#lanePlayers[lane] end
  local function addToLane(lane,p)
    lanePlayers[lane][#lanePlayers[lane]+1]=p
    rememberVisual(lane,p)
  end
  local function balancedLane(required)
    local leftRoom,rightRoom=room("left"),room("right")
    if leftRoom<required then return "right" end
    if rightRoom<required then return "left" end
    local leftFill=#lanePlayers.left/laneCapacity.left
    local rightFill=#lanePlayers.right/laneCapacity.right
    return leftFill<=rightFill and "left" or "right"
  end
  for _,key in ipairs(groupOrder) do
    local group=visualGroups[key]
    -- First complete an anchor's odd local pair (for example, a third Mage
    -- beside the R1 or R6 Mage). Then place repeated specs in two-player
    -- chunks so four Boomkins become two per side instead of alternating
    -- every individual and destroying same-look bite pairs.
    local oddLane
    if countVisual("left",key)%2==1 and room("left")>0 then oddLane="left"
    elseif countVisual("right",key)%2==1 and room("right")>0 then oddLane="right" end
    if oddLane and #group>0 then addToLane(oddLane,table.remove(group,1)) end
    while #group>=2 do
      local lane=balancedLane(2)
      if room(lane)<2 then break end
      addToLane(lane,table.remove(group,1)); addToLane(lane,table.remove(group,1))
    end
    while #group>0 do
      local lane=balancedLane(1)
      if room(lane)<1 then lane=lane=="left" and "right" or "left" end
      if room(lane)<1 then break end
      addToLane(lane,table.remove(group,1))
    end
  end
  assignRangedLane(plan,lanePlayers.left,"left",{center={2,3},back={5,4}})
  assignRangedLane(plan,lanePlayers.right,"right",{center={7,8},back={10,9}})
  table.sort(plan.ranged,function(a,b) return a.slotNumber<b.slotNumber end)

  for i,p in ipairs(healers) do
    if i<=5 then
      local a={type="healer",slot="H"..i,slotNumber=i,lane=(i%2==1) and "left" or "right",depth="support",player=p}
      plan.healers[#plan.healers+1]=a; plan.positions[#plan.positions+1]=a; plan.byGUID[p.guid]=a
    else
      plan.warnings[#plan.warnings+1]=p.name.." exceeds the H1-H5 healer capacity."
    end
  end

  local positionedMelee={}
  for i,p in ipairs(meleeDPS) do
    if i<=10 then positionedMelee[#positionedMelee+1]=p
    else plan.warnings[#plan.warnings+1]=p.name.." exceeds the worksheet's 10 melee-position capacity." end
  end
  local totalMelee=#positionedMelee
  local middleTarget=math.ceil(totalMelee/3)
  local bottomQuartileStart=math.floor(totalMelee*0.75)+1
  local lowFeral={}
  for i,p in ipairs(positionedMelee) do
    if isFeral(p) and (not p.expectedDPS or i>=bottomQuartileStart) then lowFeral[p.guid]=true end
  end

  local laneByGUID,noteByGUID,middlePlayers={},{},{}
  local function putMiddle(p,note)
    if laneByGUID[p.guid] then return end
    laneByGUID[p.guid]="middle"; noteByGUID[p.guid]=note; middlePlayers[#middlePlayers+1]=p
  end
  -- Rear-position requirements and reliable Death Knight AMS are hard Middle
  -- constraints unless a Feral is in the bottom Festergut quartile. Place all
  -- of them before filling the three-way balancing target.
  for _,p in ipairs(positionedMelee) do
    if isRogue(p) then putMiddle(p,"Middle: rear attacks stay behind the boss without collapsing the side groups; Cloak can handle flames.")
    elseif isDeathKnight(p) then putMiddle(p,"Middle: AMS reliably handles Swarming Shadows.")
    elseif isFeral(p) and not lowFeral[p.guid] then putMiddle(p,"Middle: rear attacks stay behind the boss; Festergut output is above the bottom melee quartile.") end
  end
  if #middlePlayers>middleTarget then middleTarget=#middlePlayers end
  for _,p in ipairs(positionedMelee) do
    if #middlePlayers>=middleTarget then break end
    if not laneByGUID[p.guid] and not isRet(p) and not lowFeral[p.guid] then putMiddle(p,"Middle balance fill; maintain rear access and three-way splash spacing.") end
  end
  for _,p in ipairs(positionedMelee) do
    if #middlePlayers>=middleTarget then break end
    if lowFeral[p.guid] and not laneByGUID[p.guid] then putMiddle(p,"Middle balance fallback; lower-output Feral needs manual flame-risk review.") end
  end
  if #middlePlayers<middleTarget then
    plan.warnings[#plan.warnings+1]="Retribution side constraints leave the Middle melee group smaller than the ideal three-way split."
  end

  local sidePlayers={}
  for _,p in ipairs(positionedMelee) do if not laneByGUID[p.guid] then sidePlayers[#sidePlayers+1]=p end end
  local leftTarget=math.ceil(#sidePlayers/2); local leftCount,rightCount=0,0
  for _,p in ipairs(sidePlayers) do
    local lane
    if leftCount<leftTarget and leftCount<=rightCount then lane="left"; leftCount=leftCount+1
    else lane="right"; rightCount=rightCount+1 end
    laneByGUID[p.guid]=lane
    if isRet(p) then noteByGUID[p.guid]="Side: Wings and Divine Shield lock each other out, so bubble flame dodging is not treated as reliable."
    elseif lowFeral[p.guid] then noteByGUID[p.guid]="Side: bottom-quartile Festergut Feral keeps avoidable flame risk out of Middle."
    else noteByGUID[p.guid]="Side balance: evenly split for air-phase splash spacing." end
  end

  local counts={left=0,right=0,middle=0}; local positioned=0
  for _,p in ipairs(positionedMelee) do
    local group=laneByGUID[p.guid]
    counts[group]=counts[group]+1; positioned=positioned+1
    local a={type="melee",slot="M"..positioned,slotNumber=positioned,lane=group,depth="melee",groupOrder=counts[group],player=p,biteEligible=eligibleByGUID[p.guid] and true or false,note=noteByGUID[p.guid]}
    plan.melee[#plan.melee+1]=a; plan.positions[#plan.positions+1]=a; plan.byGUID[p.guid]=a
  end
  local largest=math.max(counts.left,counts.middle,counts.right); local smallest=math.min(counts.left,counts.middle,counts.right)
  if totalMelee>=3 and largest-smallest>1 then
    plan.warnings[#plan.warnings+1]="Hard rear-position or Retribution constraints prevent a perfectly even Left/Middle/Right melee split ("..counts.left.."/"..counts.middle.."/"..counts.right..")."
  end

  plan.primary=primary; plan.secondary=secondary
  plan.utility.shadowAM=self:GetBQLShadowAMOrder()
  plan.utility.dsac=self:GetBQLDSacOrder(plan.utility.shadowAM)
  plan.utility.cooldowns=self:BuildBQLCooldownPlan(plan.utility.shadowAM,plan.utility.dsac)
  for _,warning in ipairs(plan.utility.cooldowns.warnings or {}) do plan.warnings[#plan.warnings+1]=warning end
  if #plan.bitePriority<2 then plan.warnings[#plan.warnings+1]="Fewer than two eligible ranged DPS; the ranged opening and left-to-right second bite cannot be completed." end
  self.db.latestBQLComposition=plan
  return plan
end
