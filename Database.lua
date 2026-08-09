local PB = PizzaRaidPlanner
local function copyDefaults(target, defaults)
  for k,v in pairs(defaults) do
    if target[k] == nil then target[k] = type(v) == "table" and {} or v end
    if type(v) == "table" and type(target[k]) == "table" then copyDefaults(target[k], v) end
  end
end
function PB:InitDB()
  PizzaRaidPlannerDB = PizzaRaidPlannerDB or {}
  copyDefaults(PizzaRaidPlannerDB, PB.DEFAULTS)
  while (PizzaRaidPlannerDB.schemaVersion or 0) < PB.SCHEMA_VERSION do
    PizzaRaidPlannerDB.schemaVersion = PB.SCHEMA_VERSION
  end
  PizzaRaidPlannerExportDB = PizzaRaidPlannerExportDB or { schemaVersion=PB.SCHEMA_VERSION, payload={} }
  PizzaRaidPlannerExportDB.schemaVersion = PB.SCHEMA_VERSION
  self.db, self.exportDB = PizzaRaidPlannerDB, PizzaRaidPlannerExportDB
end
function PB:Debug(message)
  if not self.db then return end
  local log = self.db.debugLog; log[#log+1] = { at=self:Now(), message=tostring(message) }
  while #log > 100 do table.remove(log, 1) end
  if self.db.settings.debug and DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffcc8844PizzaRaidPlanner:|r " .. tostring(message)) end
end
function PB:GetOverride(bucket, name) return self.db[bucket] and self.db[bucket][self:NormalizeName(name)] end
function PB:SetOverride(bucket, name, value) self.db[bucket][self:NormalizeName(name)] = value end
