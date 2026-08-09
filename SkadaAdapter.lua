-- Optional adapter for the exact installed Skada 1.8.x family. PizzaRaidPlanner
-- remains standalone; every access is capability checked.
local PB = PizzaRaidPlanner
function PB:ApplySkadaProfile(p, unit)
  if not Skada then return end
  local ok,spec=pcall(function() return Skada.GetUnitSpec and Skada.GetUnitSpec(p.guid) end); if ok and spec then p.spec=tonumber(spec) or spec end
  local okRole,role=pcall(function() return Skada.GetUnitRole and Skada.GetUnitRole(p.guid) end); if okRole and role and role~="NONE" then p.skadaRole=role end
  local set=Skada.GetSet and Skada:GetSet("current")
  local actor=set and set.GetActor and set:GetActor(p.name,p.guid,true)
  if actor then p.spec=p.spec or tonumber(actor.spec) or actor.spec; p.skadaRole=p.skadaRole or actor.role; p.talentBuild=actor.talent end
  if LibStub and GetSpellInfo then
    local lgt=LibStub("LibGroupTalents-1.0",true)
    if lgt and lgt.UnitHasTalent and unit then
      local amName=GetSpellInfo(31821); local dsName=GetSpellInfo(64205)
      local am=amName and lgt:UnitHasTalent(unit,amName); local ds=dsName and lgt:UnitHasTalent(unit,dsName)
      if am~=nil then p.hasAuraMastery=am>0 end; if ds~=nil then p.hasDivineSacrifice=ds>0 end
    end
  end
  p.specName=self:GetSpecName(p); p.profileSource=(p.spec or p.skadaRole) and "Skada 1.8.x" or nil
end

-- Read-only fallback for the exact Skada API present in the user's client.
-- The internal combat-log segments stay authoritative; this snapshot is used
-- only when PizzaRaidPlanner has no valid stored boss segment yet.
function PB:GetSkadaSource()
  local now=self:Now()
  if self._skadaSourceCheckedAt and now-self._skadaSourceCheckedAt<5 then return self._skadaSourceCache end
  self._skadaSourceCheckedAt=now; self._skadaSourceCache=nil
  if not self:IsICCTrackingActive() or not Skada or not Skada.GetSet then return nil end
  local ok,set=pcall(function() return Skada:GetSet("current") end)
  if not ok or not set or not set.GetActor or not set.GetTime then return nil end
  local session=self.db and self.db.iccSession
  local setStarted=tonumber(set.starttime)
  if setStarted and session and session.startedAt and setStarted<session.startedAt then return nil end
  local okTime,duration=pcall(function() return set:GetTime() end)
  duration=okTime and tonumber(duration) or 0
  if duration<PB.MIN_SEGMENT_DURATION then return nil end

  local targetTotals,actors,totalDamage={},{},0
  for _,p in ipairs(self.roster) do
    local okActor,actor=pcall(function() return set:GetActor(p.name,p.guid,true) end)
    if okActor and actor then
      actors[p.guid]=actor
      local okDamage,damage=pcall(function() return actor:GetDamage(true) end)
      damage=okDamage and tonumber(damage) or 0
      totalDamage=totalDamage+damage
      local okTargets,targets=pcall(function() return actor:GetDamageTargets(set,{}) end)
      if okTargets and targets then
        for targetName,info in pairs(targets) do
          local amount=tonumber(info and (info.amount or info.total)) or 0
          local overkill=tonumber(info and info.o_amt) or 0
          targetTotals[targetName]=(targetTotals[targetName] or 0)+math.max(0,amount-overkill)
        end
      end
    end
  end
  local primaryName,primaryDamage
  for targetName,damage in pairs(targetTotals) do
    if not primaryDamage or damage>primaryDamage then primaryName,primaryDamage=targetName,damage end
  end
  if not primaryName or (primaryDamage or 0)<PB.MIN_SEGMENT_DAMAGE then return nil end
  if totalDamage>0 and primaryDamage/totalDamage<0.45 then return nil end
  local encounter=self:GetICCBossKey(nil,primaryName)
  if not encounter or encounter=="bql" or not PB.ICC_AVERAGE_ENCOUNTERS[encounter] then return nil end

  local players={}
  for _,p in ipairs(self.roster) do
    local actor=actors[p.guid]
    if actor then
      local okTotal,total=pcall(function() return actor:GetDamage(true) end)
      local okPrimary,damage,overkill=pcall(function() return actor:GetDamageOnTarget(primaryName) end)
      total=okTotal and tonumber(total) or 0
      damage=okPrimary and tonumber(damage) or 0
      overkill=okPrimary and tonumber(overkill) or 0
      local useful=math.max(0,damage-overkill)
      players[p.guid]={totalDamage=total,primaryDamage=useful,healing=0,dps=useful/duration}
    end
  end
  local id="skada-"..tostring(set.starttime or set.name or "current")
  self._skadaSourceCache={id=id,targetName=primaryName,targetGUID=nil,duration=duration,players=players,valid=true,confidence="Current ICC Skada boss fallback",dataSource="Skada 1.8.x"}
  return self._skadaSourceCache
end
