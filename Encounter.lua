local PB = PizzaRaidPlanner
local function completedTarget(live,guid)
  for _,done in ipairs(live.completed or {}) do if done.targetGUID==guid then return true end end
  return false
end
function PB:StartLive()
  self.live.active=true; self.live.vampires={}; self.live.completed={}; self.live.actualFirst=nil; self.live.frozenSource=nil; self.live.frozenSource=self:GetBQLBenchmarkSource()
  self:GeneratePlan(); self:Print("Live mode armed; the Festergut benchmark is frozen and unexpected BQL bites can reroot the review plan.")
end
function PB:StopLive() self.live.active=false; self:Print("Live mode stopped."); self:GeneratePlan() end
function PB:EndEncounter(reason)
  if not self.live.active then return end
  self.db.encounterHistory[#self.db.encounterHistory+1]={at=self:Now(),reason=reason,first=self.live.actualFirst,completed=self.live.completed}
  while #self.db.encounterHistory>20 do table.remove(self.db.encounterHistory,1) end
  self:StopLive()
end
function PB:HandleEncounterEvent(e)
  local spell=e.spellId; local isEssence=self:SpellMatches(PB.BQL_SPELLS,spell,e.spellName) or self:SpellMatches(PB.BITE_SPELLS,spell,e.spellName)
  if not isEssence then return end
  if e.event=="SPELL_AURA_APPLIED" and isEssence then
    if not self.live.active then return end
    local p=self.byGUID[e.destGUID]; if p then
      if not self.live.actualFirst then
        local planned=self.db.latestPlan and self.db.latestPlan.first; self.live.actualFirst=p.guid; self.live.vampires[p.guid]=true
        if planned and planned~=p.guid then self:Print("Actual first vampire "..p.name.." differs from planned first; rerooting.") end
        self:GeneratePlan(true)
      elseif not self.live.vampires[p.guid] then
        self.live.vampires[p.guid]=true
        local biter=self.byGUID[e.sourceGUID]
        if biter and biter.guid~=p.guid and not completedTarget(self.live,p.guid) then
          self.live.completed[#self.live.completed+1]={at=self:Now(),biter=biter.name,biterGUID=biter.guid,target=p.name,targetGUID=p.guid,status="completed"}
        end
        self:GeneratePlan(true)
      end
    end
  elseif e.event=="SPELL_CAST_SUCCESS" and self:SpellMatches(PB.BITE_SPELLS,spell,e.spellName) and self.live.active then
    local biter,target=self.byGUID[e.sourceGUID],self.byGUID[e.destGUID]
    if biter and target then
      self.live.vampires[target.guid]=true
      if not completedTarget(self.live,target.guid) then self.live.completed[#self.live.completed+1]={at=self:Now(),biter=biter.name,biterGUID=biter.guid,target=target.name,targetGUID=target.guid,status="completed"} end
      self:GeneratePlan(true)
    end
  end
end
