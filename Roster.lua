local PB = PizzaRaidPlanner

local function copyPlayer(source)
  local copy={}
  for key,value in pairs(source or {}) do copy[key]=value end
  copy.online=true; copy.connected=true; copy.dead=false; copy.unitToken=nil
  return copy
end

local function addSavedPlayer(list, seen, entry)
  local player=entry and (entry.player or entry)
  if not player or not player.guid or not player.name or seen[player.guid] then return end
  seen[player.guid]=true
  list[#list+1]=copyPlayer(player)
end

local function sortedSavedPlayers(entries)
  local roster,seen={},{ }
  for _,entry in ipairs(entries or {}) do addSavedPlayer(roster,seen,entry) end
  table.sort(roster,function(a,b)
    local ai,bi=tonumber(a.raidIndex) or 99,tonumber(b.raidIndex) or 99
    if ai~=bi then return ai<bi end
    return (a.normalizedName or a.name)<(b.normalizedName or b.name)
  end)
  return roster
end

function PB:SnapshotRaidRoster(entries)
  return sortedSavedPlayers(entries or self.roster or {})
end

function PB:RememberRaidTestRoster()
  if self.savedRaidTestRoster or not self.db or #(self.roster or {})<20 then return end
  local previous=self.db.lastRaidRoster or {}
  -- Do not replace a full saved raid with a temporarily smaller roster while
  -- people zone, disconnect, or the group is disbanding after the raid.
  if #previous>#self.roster then return end
  local snapshot=self:SnapshotRaidRoster(self.roster)
  if #snapshot<20 then return end
  self.db.lastRaidRoster=snapshot
  self.db.lastRaidRosterSavedAt=self:Now()
end

function PB:GetSavedRaidTestRoster()
  local remembered=self.db and self.db.lastRaidRoster
  if remembered and #remembered>0 then return self:SnapshotRaidRoster(remembered) end

  -- Migration fallback for snapshots created before the dedicated roster was
  -- introduced. New scans use lastRaidRoster and cannot be erased by solo UI.
  local plan=self.db and self.db.latestPlan
  local composition=plan and plan.composition
  if not composition then return {} end

  local roster,seen={},{}
  for _,bucket in ipairs({"positions","healers","ranged","melee","tanks"}) do
    for _,entry in ipairs(composition[bucket] or {}) do addSavedPlayer(roster,seen,entry) end
  end
  return self:SnapshotRaidRoster(roster)
end

function PB:RunSavedRaidTest()
  local snapshot=self:GetSavedRaidTestRoster()
  if #snapshot==0 then return nil,"No saved raid composition is available. Generate a plan while in the raid first." end

  local priorSource=self.db.settings.source
  self.savedRaidTestRoster=snapshot
  self.db.settings.source="auto"
  local ok,bpc,bql=pcall(function()
    local bpcPlan=self:BuildBPCPlan()
    local bqlPlan=self:GeneratePlan()
    return bpcPlan,bqlPlan
  end)
  self.savedRaidTestRoster=nil
  self.db.settings.source=priorSource
  self:ScanRoster()
  if not ok then return nil,tostring(bpc) end
  return {rosterCount=#snapshot,bpc=bpc,bql=bql}
end

function PB:ScanRoster()
  self.roster, self.byGUID, self.byName, self.petOwners = {}, {}, {}, {}
  if self.savedRaidTestRoster then
    for _,saved in ipairs(self.savedRaidTestRoster) do
      local rec=copyPlayer(saved); local n=self:NormalizeName(rec.name)
      rec.normalizedName=n
      self.roster[#self.roster+1],self.byGUID[rec.guid],self.byName[n]=rec,rec,rec
    end
    self:ApplySourceToRoster()
    return
  end
  local count = GetNumRaidMembers and GetNumRaidMembers() or 0
  for i=1,count do
    local name, rank, subgroup, level, className, classToken, zone, online, dead, raidRole = GetRaidRosterInfo(i)
    local unit = "raid"..i; local guid = UnitGUID(unit)
    if name and guid then
      local n = self:NormalizeName(name)
      local rec = { guid=guid,name=name,normalizedName=n,className=className or "Unknown",classToken=classToken or "UNKNOWN",raidIndex=i,subgroup=subgroup or 0,raidRank=rank or 0,raidRole=raidRole,unitToken=unit,online=online ~= false,dead=dead == true,connected=UnitIsConnected and UnitIsConnected(unit) ~= false or online ~= false,damage=0,bossDamage=0,healing=0,bossDamageTaken=0,dps=0,expectedDPS=nil,confidence="No sample",position="unknown" }
      self.roster[#self.roster+1],self.byGUID[guid],self.byName[n]=rec,rec,rec
      local petGUID = UnitGUID("raidpet"..i); if petGUID then self.petOwners[petGUID]=guid end
      if self.ApplySkadaProfile then self:ApplySkadaProfile(rec,unit) end
    end
  end
  self:ApplySourceToRoster()
  self:RememberRaidTestRoster()
end
function PB:FindPlayer(query)
  local key=self:NormalizeName(query); if self.byName[key] then return self.byName[key] end
  for _,p in ipairs(self.roster) do if p.normalizedName:find(key,1,true) then return p end end
end
function PB:ApplySourceToRoster(source, explicitSource)
  if not explicitSource then source = self:GetSelectedSource() end
  for _,p in ipairs(self.roster) do
    local s = source and source.players and source.players[p.guid]
    p.damage=s and s.totalDamage or 0; p.bossDamage=s and s.primaryDamage or 0; p.healing=s and s.healing or 0
    p.sampleDuration=source and source.duration or 0; p.dps=s and s.dps or 0; p.expectedDPS=s and s.dps or nil
    p.confidence=s and s.confidence or (source and source.confidence or "No valid sample"); p.dataSource=source and source.id or "None"
    if self.ResolveRole then self:ResolveRole(p); p.position=self:GetPosition(p); p.specName=self:GetSpecName(p) end
  end
end
