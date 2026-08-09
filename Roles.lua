local PB = PizzaRaidPlanner
function PB:GetSpecName(p)
  local spec=type(p)=="table" and p.spec or p
  spec=tonumber(spec) or spec
  return PB.SPEC_NAMES[spec] or (spec and ("Spec "..tostring(spec)) or "Unknown")
end
function PB:ResolveRole(p)
  local manual=self:GetOverride("roleOverrides",p.name)
  if manual then p.manualRole=manual; p.suggestedRole=manual; p.roleConfidence="Manual"; return manual end
  if p.raidRole=="MAINTANK" then p.suggestedRole="tank"; p.roleConfidence="Raid assignment"; return "tank" end
  local spec=tonumber(p.spec) or p.spec; local specRole=PB.SPEC_ROLES[spec]
  if specRole then p.specName=self:GetSpecName(spec); p.suggestedRole=specRole; p.roleConfidence="Inspected "..p.specName.." spec"; return specRole end
  if p.skadaRole=="TANK" then p.suggestedRole="tank"; p.roleConfidence="Skada inspected role"; return "tank" end
  if p.skadaRole=="HEALER" then p.suggestedRole="healer"; p.roleConfidence="Skada inspected role"; return "healer" end
  if p.skadaRole=="DAMAGER" then p.suggestedRole="dps"; p.roleConfidence="Skada inspected role"; return "dps" end
  if (p.healing or 0) > ((p.damage or 0) * .5) and (p.healing or 0) > 10000 then p.suggestedRole="healer"; p.roleConfidence="Behavioural"
  elseif (p.bossDamageTaken or 0) > 50000 then p.suggestedRole="tank"; p.roleConfidence="Behavioural"
  else p.suggestedRole="dps"; p.roleConfidence="Default" end
  return p.suggestedRole
end
function PB:GetPosition(p)
  local manual=self:GetOverride("positionOverrides",p.name); if manual then return manual end
  local role=self:ResolveRole(p); if role=="healer" then return "ranged" elseif role=="tank" then return "melee" end
  local spec=tonumber(p.spec) or p.spec
  if spec and PB.RANGED_SPECS[spec] then return "ranged" elseif spec then return "melee" end
  local melee={WARRIOR=true,ROGUE=true,DEATHKNIGHT=true,DRUID=true,PALADIN=true,SHAMAN=true}
  return melee[p.classToken] and "melee" or "ranged"
end
function PB:GetCapability(p, capability)
  local key=self:NormalizeName(p.name); local manual=self.db.capabilityOverrides[key]
  if manual and manual[capability]~=nil then return manual[capability],"manual" end
  if capability=="kinetic" then return p.classToken=="HUNTER",p.classToken=="HUNTER" and "class rule" or "not hunter" end
  if capability=="auraMastery" and p.hasAuraMastery~=nil then return p.hasAuraMastery,"inspected talent" end
  if capability=="divineSacrifice" and p.hasDivineSacrifice~=nil then return p.hasDivineSacrifice,"inspected talent" end
  local evidence=self.db.capabilityEvidence[key]
  if evidence and evidence[capability] then return true,"observed cast" end
  if p.classToken=="PALADIN" and capability=="auraMastery" and p.spec==65 then return true,"holy spec inference" end
  if p.classToken=="PALADIN" and capability=="divineSacrifice" and (p.spec==65 or p.spec==66) then return true,"holy/protection inference" end
  return false,"unverified"
end
function PB:ObserveCapability(guid, capability)
  local p=self.byGUID[guid]; if not p or not capability then return end
  local key=p.normalizedName; self.db.capabilityEvidence[key]=self.db.capabilityEvidence[key] or {}; self.db.capabilityEvidence[key][capability]=true
end
function PB:IsEligible(p, live)
  local forced=self:GetOverride("inclusionOverrides",p.name)
  if forced == false then return false, self:GetOverride("exclusionReasons",p.name) or "Manually excluded" end
  if forced == true then return true, "Manually included" end
  if not p.online or not p.connected then return false,"Offline" end
  if live and p.dead then return false,"Dead" end
  local role=self:ResolveRole(p)
  if role=="tank" or role=="healer" then
    if self.db.settings.allowEmergencyFallback then return false,"Emergency fallback only ("..role..")" end
    return false,"Confirmed "..role
  end
  if live and self.live.vampires[p.guid] then return false,"Already vampire" end
  return true,"Eligible"
end
