local PB = PizzaRaidPlanner
local function words(input) local t={}; for w in (input or ""):gmatch("%S+") do t[#t+1]=w end return t end
local function playerOrError(name)
  if not name or name=="" then PB:Print("A player name is required."); return nil end
  local p=PB:FindPlayer(name); if not p then PB:Print("Player not found: "..tostring(name)) end return p
end
local capabilityAliases={am="auraMastery",auramastery="auraMastery",dsac="divineSacrifice",divinesacrifice="divineSacrifice",kinetic="kinetic"}
local function setCapability(p,capability,value)
  local key=p.normalizedName
  PB.db.capabilityOverrides[key]=PB.db.capabilityOverrides[key] or {}
  PB.db.capabilityOverrides[key][capability]=value
end
function PB:ListSources()
  local history=self:EnsureFestergutHistorySafe()
  if #history==0 then self:Print("No saved Festergut kills yet."); return end
  for i=#history,1,-1 do
    local entry=history[i]
    self:Print(entry.id.." | Festergut "..date("%Y-%m-%d %H:%M",entry.recordedAt).." | "..math.floor(entry.duration or 0).."s | "..#(entry.roster or {}).." raiders")
  end
end
local function sendChatLine(text,channel)
  while #text>240 do
    local cut=240
    for i=240,180,-1 do if text:sub(i,i)==" " then cut=i; break end end
    SendChatMessage(text:sub(1,cut),channel)
    text=text:sub(cut+1):gsub("^%s+","")
  end
  if text~="" then SendChatMessage(text,channel) end
end
function PB:Announce()
  local channel=self.db.settings.announce; if channel=="off" then self:Print("Announcements are off."); return end
  if not (IsRaidLeader and (IsRaidLeader() or IsRaidOfficer and IsRaidOfficer())) then self:Print("Raid announcement requires raid leader or assistant."); return end
  local text=self:DiscordText(); local target=channel=="rw" and "RAID_WARNING" or "RAID"
  for line in text:gmatch("[^\n]+") do sendChatLine(line,target) end
end
function PB:Command(input)
  local a=words(input); local cmd=(a[1] or "show"):lower()
  if cmd=="show" then self:ShowUI()
  elseif cmd=="hide" then self:HideUI()
  elseif cmd=="scan" then self:ScanRoster(); self:Print("Raid scanned: "..#self.roster.." members.")
  elseif cmd=="status" then
    local source=self:GetSelectedSource(); local benchmark=self:GetBQLBenchmarkSource()
    local history=self:GetSelectedFestergutHistoryEntrySafe()
    self:Print("ICC tracking "..(self:IsICCTrackingActive() and "ACTIVE" or "paused")..", roster "..#self.roster..", mode "..(history and ("saved Festergut "..date("%Y-%m-%d %H:%M",history.recordedAt)) or (self.live.active and "live" or "current raid"))..", BPC/BQL benchmark "..(history and "selected history" or (benchmark and benchmark.targetName or "missing Festergut"))..".")
  elseif cmd=="sample" then if a[2]=="start" then self:StartManualSample() elseif a[2]=="stop" then self:StopSample() elseif a[2]=="reset" then self:ResetSample() else self:Print("Usage: /prp sample start|stop|reset") end
  elseif cmd=="source" then
    if a[2]=="list" then self:ListSources()
    elseif a[2]=="history" and a[3] then local result,err=self:SelectFestergutHistorySafe(a[3]); if result then self:Print("Selected saved Festergut history.") else self:Print(err) end
    elseif a[2]=="icc" or a[2]=="auto" then self:ClearFestergutHistorySelectionSafe(false); self.db.settings.source="auto"; self:ApplySourceToRoster(); self:Print("Using the current raid and current-session Festergut.")
    elseif a[2]=="last" then self:ClearFestergutHistorySelectionSafe(false); self.db.settings.source="last"; self:ApplySourceToRoster(); self:Print("Using last valid segment for roster review; BPC/BQL ranking remains Festergut-only.")
    elseif a[2]=="median" then self:ClearFestergutHistorySelectionSafe(false); self.db.settings.source="median"; self.db.settings.medianCount=math.max(2,math.min(5,tonumber(a[3]) or 3)); self:ApplySourceToRoster(); self:Print("Using median source for roster review; BPC/BQL ranking remains Festergut-only.")
    elseif a[2]=="segment" and a[3] then self:ClearFestergutHistorySelectionSafe(false); self.db.settings.source="segment"; self.db.selectedSegmentId=a[3]; self:ApplySourceToRoster(); self:Print("Selected segment "..a[3].." for roster review; BPC/BQL ranking remains Festergut-only.")
    elseif a[2]=="current" then self:ClearFestergutHistorySelectionSafe(false); self.db.settings.source="current"; self:Print("Current sample is displayed when stopped and saved.")
    else self:Print("Usage: /prp source list|history <id>|icc|last|median 3|segment <id>|current") end
  elseif cmd=="order" then local plan,err=self:PrepareBQLPlanSafe(); if not plan then self:Print(err); return end; for i,x in ipairs(plan.flatPriority or {}) do self:Print(i..". "..x.name.." - "..(x.dps and math.floor(x.dps).." Festergut DPS" or "No Festergut sample").." - "..(x.reason or "")) end
  elseif cmd=="plan" then local plan,err=self:PrepareBQLPlanSafe(); if not plan then self:Print(err); return end; self:ShowExport("discord","plan")
  elseif cmd=="publish" and (a[2] or "bql"):lower()=="bpc" then
    local plan,err=self:PrepareBPCPlanSafe(); if not plan then self:Print(err); return end; self:ShowExport("tsv","bpc")
    self:Print("Valanar-active BPC blocks selected. Paste at 'WoW TSV Dump' A1; then Ctrl+Shift+V A1:F10 to 'Blood Prince Council' A6 and A13:F15 to A20.")
  elseif cmd=="publish" then
    -- One-command, pre-pull workflow: refresh the current raid, rank BQL from
    -- the current-session Festergut benchmark, and show paste-ready TSV.
    local plan,err=self:PrepareBQLPlanSafe(); if not plan then self:Print(err); return end; self:ShowExport("tsv","plan")
    if plan and plan.first then self:Print("BQL blocks selected. Paste at 'WoW TSV Dump' A55; then Ctrl+Shift+V A55:Q62 to 'Blood Queen Lana'Thel' A28, A64:H73 to N6, and A76:G79 to N20.") else self:Print("No plan generated: collect a longer boss segment first or review role overrides.") end
  elseif cmd=="live" then if a[2]=="on" then self:StartLive() elseif a[2]=="off" then self:StopLive() else self:Print("Live mode is optional BQL pull monitoring that reroots the review plan after an unexpected vampire; it never casts or changes the pre-published sheet. Usage: /prp live on|off") end
  elseif cmd=="first" then local p=playerOrError(a[2]); if p then self.db.plannedFirst=p.normalizedName; self:GeneratePlan(); self:Print("Planned first bite: "..p.name) end
  elseif cmd=="role" then
    local p=playerOrError(a[2]); local v=a[3] and a[3]:lower()
    if p and (v=="dps" or v=="healer" or v=="tank" or v=="clear") then
      if v=="clear" then self:SetOverride("roleOverrides",p.name,nil) else self:SetOverride("roleOverrides",p.name,v) end
      self:GeneratePlan()
    else self:Print("Usage: /prp role <player> dps|healer|tank|clear") end
  elseif cmd=="position" then
    local p=playerOrError(a[2]); local v=a[3] and a[3]:lower()
    if p and (v=="melee" or v=="ranged" or v=="unknown" or v=="clear") then
      if v=="clear" then self:SetOverride("positionOverrides",p.name,nil) else self:SetOverride("positionOverrides",p.name,v) end
      self:GeneratePlan()
    else self:Print("Usage: /prp position <player> melee|ranged|unknown|clear") end
  elseif cmd=="include" then local p=playerOrError(a[2]); if p then self:SetOverride("inclusionOverrides",p.name,true); self:GeneratePlan() end
  elseif cmd=="exclude" then local p=playerOrError(a[2]); if p then self:SetOverride("inclusionOverrides",p.name,false); self.db.exclusionReasons=self.db.exclusionReasons or {}; self:SetOverride("exclusionReasons",p.name,table.concat(a," ",3)); self:GeneratePlan() end
  elseif cmd=="priority" then local p=playerOrError(a[2]); if p then local v=a[3]; if v=="clear" then self:SetOverride("manualPriorities",p.name,nil) elseif tonumber(v) then self:SetOverride("manualPriorities",p.name,tonumber(v)) else self:Print("Usage: /prp priority <player> <integer>|clear") return end; self:GeneratePlan() end
  elseif cmd=="capability" then
    local p=playerOrError(a[2]); local capability=a[3] and capabilityAliases[a[3]:lower()]; local value=a[4] and a[4]:lower()
    if p and capability and (value=="on" or value=="off" or value=="clear") then
      if value=="clear" then setCapability(p,capability,nil) else setCapability(p,capability,value=="on") end
      self:GeneratePlan(); self:Print(p.name.." "..capability.." override: "..value)
    else self:Print("Usage: /prp capability <player> am|dsac|kinetic on|off|clear") end
  elseif cmd=="competent" then
    local p=playerOrError(a[2]); local value=a[3] and a[3]:lower()
    if p and p.classToken=="MAGE" and (value=="on" or value=="off" or value=="clear") then
      if value=="clear" then self.db.competenceOverrides[p.normalizedName]=nil else self.db.competenceOverrides[p.normalizedName]=value=="on" end
      self:GeneratePlan(); self:Print(p.name.." mage competence override: "..value)
    else self:Print("Usage: /prp competent <mage> on|off|clear") end
  elseif cmd=="utility" then
    local p=playerOrError(a[2]); local value=a[3] and a[3]:lower()
    if p and value=="clear" then self.db.utilityPriorities[p.normalizedName]=nil; self:GeneratePlan()
    elseif p and tonumber(value) then self.db.utilityPriorities[p.normalizedName]=tonumber(value); self:GeneratePlan()
    else self:Print("Usage: /prp utility <player> <integer>|clear") end
  elseif cmd=="rules" then
    self:Print("BQL: targets come to stationary biters and return home. R1-R5 are left and R6-R10 are right. The second bite sends R6 to stationary R1, then R6 returns home as the right anchor; the third bite seeds one melee vampire per side. The last two rounds prefer same role, same side, then same class/spec (Hunter-Hunter, Shadow-Shadow, Balance-Balance). Shadow AM covers Pact links; DSac covers Bloodbolt Whirl only. Rogues and all DPS DKs use Middle, strong Ferals also use Middle, Rets stay on the sides, and melee groups remain balanced where hard constraints permit. BPC Valanar active: Boomkins R9/R10/R8; top Hunter R2, second Hunter R7; lower ranged use R4-R7; melee numbers run center-out, Rets favor M1/M2, and M9/M10 are overflow only.")
  elseif cmd=="test" and (a[2] or ""):lower()=="last" then
    local kind=(a[3] or "bql"):lower()
    if kind~="bpc" and kind~="bql" then self:Print("Usage: /prp test last bpc|bql"); return end
    local result,err=self:RunSavedRaidTest()
    if not result then self:Print("Saved-raid test failed: "..tostring(err)); return end
    self:ShowExport("tsv",kind=="bpc" and "bpc" or "plan")
    self:Print("Offline test rebuilt both plans from "..result.rosterCount.." saved raiders. Showing "..kind:upper().." TSV; no live roster or workbook was changed.")
  elseif cmd=="bpc" then local plan,err=self:PrepareBPCPlanSafe(); if not plan then self:Print(err); return end; self:ShowExport("discord","bpc")
  elseif cmd=="export" then local v=(a[2] or "plan"):lower(); if v=="plan" then self:ShowExport("tsv","plan") elseif v=="roster" then self:ShowExport("tsv","roster") elseif v=="bpc" then self:ShowExport("tsv","bpc") elseif v=="tsv" or v=="csv" or v=="json" or v=="discord" then self:ShowExport(v,"plan") else self:Print("Usage: /prp export plan|roster|bpc|tsv|csv|json|discord") end
  elseif cmd=="announce" then local v=(a[2] or "off"):lower(); if v=="off" or v=="raid" or v=="rw" then self.db.settings.announce=v; self:Print("Announcements: "..v) else self:Print("Usage: /prp announce off|raid|rw") end
  elseif cmd=="debug" then local v=(a[2] or "off"):lower(); self.db.settings.debug=(v=="on"); self:Print("Debug "..(self.db.settings.debug and "on" or "off"))
  elseif cmd=="help" then self:Print("Flow: open DPS Sources and select any saved Festergut, then use BQL Review, Copy BPC, or Copy BQL. Current raids save each valid Festergut automatically. Paste BPC at 'WoW TSV Dump' A1 and BQL at A55; use the printed Ctrl+Shift+V destinations. Review tools: rules; role/position/include/exclude/priority; capability; competent; utility. Other: show|scan|status; sample; source; order|plan|bpc|live; first; export; announce; debug.")
  else self:Print("Unknown command. Use /prp help.") end
end
SLASH_PIZZARAIDPLANNER1="/prp"; SLASH_PIZZARAIDPLANNER2="/pb"; SLASH_PIZZARAIDPLANNER3="/bql"
SlashCmdList["PIZZARAIDPLANNER"]=function(msg) PB:Command(msg) end
