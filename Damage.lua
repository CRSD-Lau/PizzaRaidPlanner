local PB = PizzaRaidPlanner
function PB:DecodeCombatLog(...)
  local a={...}; local offset=0
  if type(a[3])=="boolean" then offset=1 end
  local event=a[2]; local extra=9+offset
  local amount,overkill
  if event=="SWING_DAMAGE" then amount,overkill=a[extra],a[extra+1]
  elseif PB.DAMAGE_EVENTS[event] then amount,overkill=a[extra+3],a[extra+4]
  elseif PB.HEAL_EVENTS[event] then amount=a[extra+3] end
  return { timestamp=a[1],event=event,sourceGUID=a[3+offset],sourceName=a[4+offset],sourceFlags=a[5+offset],destGUID=a[6+offset],destName=a[7+offset],destFlags=a[8+offset],amount=amount,overkill=overkill,spellId=a[extra],spellName=a[extra+1] }
end
function PB:OwnerForGUID(guid) return self.byGUID[guid] and guid or self.petOwners[guid] end
function PB:RecordTargetDamage(owner,target,amount)
  if not target then return end
  local s=self.segment; if s and s.active and s.players[owner] then
    s.perTarget=s.perTarget or {}; s.perTarget[owner]=s.perTarget[owner] or {}; s.perTarget[owner][target]=(s.perTarget[owner][target] or 0)+amount
    if not self.live.vampires[owner] then
      s.perTargetUnbuffed=s.perTargetUnbuffed or {}; s.perTargetUnbuffed[owner]=s.perTargetUnbuffed[owner] or {}; s.perTargetUnbuffed[owner][target]=(s.perTargetUnbuffed[owner][target] or 0)+amount
    end
  end
end
function PB:HandleCombatLog(...)
  local e=self:DecodeCombatLog(...); if not e.event then return end
  if PB.DAMAGE_EVENTS[e.event] then
    local amount=tonumber(e.amount) or 0; local overkill=tonumber(e.overkill) or 0; if overkill>0 then amount=math.max(0,amount-overkill) end
    local owner=self:OwnerForGUID(e.sourceGUID)
    if owner and amount>0 then self:StartAutomaticSegment(); self:RecordSegmentDamage(owner,e.destGUID,e.destName,amount,false); self:RecordTargetDamage(owner,e.destGUID,amount) end
    if self:IsBQL(e.sourceGUID,e.sourceName) and self.byGUID[e.destGUID] then self.byGUID[e.destGUID].bossDamageTaken=(self.byGUID[e.destGUID].bossDamageTaken or 0)+amount end
    if self:IsBQL(e.destGUID,e.destName) then self.bqlPulledAt=self:Now() end
  elseif PB.HEAL_EVENTS[e.event] then
    local owner=self:OwnerForGUID(e.sourceGUID); local amount=tonumber(e.amount) or 0; if owner and amount>0 and self.segment and self.segment.active then self:RecordSegmentDamage(owner,nil,nil,amount,true) end
  elseif e.event=="SPELL_SUMMON" then
    local owner=self:OwnerForGUID(e.sourceGUID); if owner and e.destGUID then self.petOwners[e.destGUID]=owner end
  elseif e.event=="UNIT_DIED" then local p=self.byGUID[e.destGUID]; if p then p.dead=true end; if self.live and self.live.active then self:GeneratePlan(true) end
  elseif e.event=="PARTY_KILL" then if self:IsBQL(e.destGUID,e.destName) then self:EndEncounter("kill") end end
  if e.event=="SPELL_CAST_SUCCESS" and PB.UTILITY_SPELLS[e.spellId] then self:ObserveCapability(e.sourceGUID,PB.UTILITY_SPELLS[e.spellId]) end
  if e.event=="SPELL_AURA_APPLIED" or e.event=="SPELL_AURA_REMOVED" or e.event=="SPELL_CAST_SUCCESS" then self:HandleEncounterEvent(e) end
end
