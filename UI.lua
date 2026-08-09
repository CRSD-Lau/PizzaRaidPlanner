local PB = PizzaRaidPlanner

local function getElvUI()
  if type(ElvUI)~="table" or not ElvUI[1] then return nil,nil end
  local engine=ElvUI[1]
  local skins
  if engine.GetModule then
    local ok,module=pcall(engine.GetModule,engine,"Skins")
    if ok then skins=module end
  end
  return engine,skins
end

local function elvFont(fontString,engine,size)
  if fontString and fontString.SetFont and engine and engine.media and engine.media.normFont then
    fontString:SetFont(engine.media.normFont,size or 12,"OUTLINE")
  end
end

local function fallbackBackdrop(frame,alpha)
  frame:SetBackdrop({bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",tile=true,tileSize=16,edgeSize=16,insets={left=4,right=4,top=4,bottom=4}})
  frame:SetBackdropColor(0,0,0,alpha or .92)
end

local TAB_HELP={
  roster={"Roster","Shows the currently detected live raid, including class, spec, role, position, subgroup, and the selected Festergut DPS value."},
  sources={"DPS Sources","Lists saved Festergut kills. Selecting one rebuilds BPC, BQL Review, Copy BPC, and Copy BQL from that kill's DPS and recorded raid composition."},
  plan={"BQL Review","Reviews the complete Blood Queen bite chain, assigned room slots, movement handoffs, and any warnings before you copy the worksheet blocks."},
  ["copy-bpc"]={"Copy BPC","Builds the Blood Prince Council position and cooldown TSV from the selected Festergut kill, anchored at WoW TSV Dump A1."},
  ["copy-bql"]={"Copy BQL","Builds the Blood Queen position, cooldown, and bite-order TSV from the selected Festergut kill, anchored at WoW TSV Dump A55 below BPC."},
  scan={"Scan Raid","Returns to current-raid mode and refreshes names, classes, specs, roles, groups, and connectivity from the live raid roster."},
  live={"Live Mode","Optional Blood Queen pull monitoring. It tracks unexpected bites for review; it does not cast, assign protected actions, or alter the published sheet."},
}

local function showButtonHelp(button)
  local help=button and button._prpHelp
  if not help or not GameTooltip then return end
  GameTooltip:SetOwner(button,"ANCHOR_TOP")
  GameTooltip:SetText(help[1],1,.82,0)
  GameTooltip:AddLine(help[2],1,1,1,true)
  GameTooltip:Show()
end

local function hideButtonHelp(button)
  if not GameTooltip then return end
  if not GameTooltip.IsOwned or GameTooltip:IsOwned(button) then GameTooltip:Hide() end
end

function PB:SetEditorText(text)
  if not self.ui or not self.ui.edit then return end
  self:SetContentMode("edit")
  text=tostring(text or "")
  local _,lineBreaks=text:gsub("\n","")
  self.ui.edit:SetHeight(math.max(self.ui.editorViewportHeight or 350,(lineBreaks+1)*14+16))
  self.ui.edit:SetText(text)
  if self.ui.edit.SetCursorPosition then self.ui.edit:SetCursorPosition(0) end
  if self.ui.scroll and self.ui.scroll.SetVerticalScroll then self.ui.scroll:SetVerticalScroll(0) end
  if self.ui.scroll and self.ui.scroll.UpdateScrollChildRect then self.ui.scroll:UpdateScrollChildRect() end
end

function PB:AttachButtonHelp(button,title,description)
  if not button then return end
  button._prpHelp={title,description}
  if button._prpHelpAttached then return end
  button._prpHelpAttached=true
  local function onEnter(self)
    self._prpHovered=true
    showButtonHelp(self)
    PB:UpdateTabStyles()
  end
  local function onLeave(self)
    self._prpHovered=nil
    hideButtonHelp(self)
    PB:UpdateTabStyles()
  end
  if button.HookScript then
    button:HookScript("OnEnter",onEnter); button:HookScript("OnLeave",onLeave)
  else
    local oldEnter=button.GetScript and button:GetScript("OnEnter")
    local oldLeave=button.GetScript and button:GetScript("OnLeave")
    button:SetScript("OnEnter",function(self,...) if oldEnter then oldEnter(self,...) end; onEnter(self) end)
    button:SetScript("OnLeave",function(self,...) if oldLeave then oldLeave(self,...) end; onLeave(self) end)
  end
end

function PB:UpdateTabStyles()
  if not self.ui or not self.ui.tabButtons then return end
  local engine=self.ui.elvui
  local border=engine and engine.media and engine.media.bordercolor or {.2,.2,.2,1}
  local accent=engine and engine.media and engine.media.rgbvaluecolor or {1,.48,.17,1}
  local active=self.uiView
  if active=="export" then active=self.exportKind=="bpc" and "copy-bpc" or "copy-bql" end
  for key,button in pairs(self.ui.tabButtons) do
    if button.SetBackdropBorderColor then
      if key==active or button._prpHovered then button:SetBackdropBorderColor(accent[1],accent[2],accent[3],accent[4] or 1) else button:SetBackdropBorderColor(border[1],border[2],border[3],border[4] or 1) end
    end
  end
  local selected=self.db and self.db.selectedFestergutHistoryId or "current"
  for _,button in ipairs(self.ui.sourceButtons or {}) do
    if button.SetBackdropBorderColor then
      local highlighted=button._prpHovered or button._prpSourceId==selected
      if highlighted then button:SetBackdropBorderColor(accent[1],accent[2],accent[3],accent[4] or 1) else button:SetBackdropBorderColor(border[1],border[2],border[3],border[4] or 1) end
    end
  end
end

function PB:SetContentMode(mode)
  if not self.ui or not self.ui.scroll then return end
  local sources=mode=="sources"
  if sources then
    self.ui.edit:Hide(); self.ui.sourceContent:Show(); self.ui.scroll:SetScrollChild(self.ui.sourceContent)
    if self.ui.selectAll then self.ui.selectAll:Hide() end
    self.ui.helper:SetText("Select a saved Festergut kill to rehearse; the live raid roster is not changed.")
  else
    self.ui.sourceContent:Hide(); self.ui.edit:Show(); self.ui.scroll:SetScrollChild(self.ui.edit)
    if self.ui.selectAll then self.ui.selectAll:Show() end
    self.ui.helper:SetText("Copy BPC to WoW TSV Dump A1; Copy BQL to A55. Use each printed values-only range on its encounter tab.")
  end
  if self.ui.scroll.SetVerticalScroll then self.ui.scroll:SetVerticalScroll(0) end
  if self.ui.scroll.UpdateScrollChildRect then self.ui.scroll:UpdateScrollChildRect() end
end

function PB:CreateUI()
  if self.ui then return end
  local engine,skins=getElvUI()
  local f=CreateFrame("Frame","PizzaRaidPlannerFrame",UIParent)
  f:SetWidth(self.db.ui.width); f:SetHeight(self.db.ui.height)
  f:SetPoint(self.db.ui.point,UIParent,self.db.ui.point,self.db.ui.x,self.db.ui.y)
  f:SetFrameStrata("DIALOG"); f:EnableMouse(true); f:SetMovable(true); f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart",f.StartMoving)
  f:SetScript("OnDragStop",function()
    f:StopMovingOrSizing(); local _,_,_,x,y=f:GetPoint(); PB.db.ui.x,PB.db.ui.y=x,y
  end)

  local header=CreateFrame("Frame",nil,f); header:SetPoint("TOPLEFT",4,-4); header:SetPoint("TOPRIGHT",-4,-4); header:SetHeight(30)
  local logo=f:CreateTexture(nil,"ARTWORK")
  logo:SetWidth(56); logo:SetHeight(56); logo:SetPoint("TOPRIGHT",f,"TOPRIGHT",-30,-38)
  logo:SetTexture("Interface\\AddOns\\PizzaRaidPlanner\\Media\\PizzaWarriorsLogo")
  local title=header:CreateFontString(nil,"OVERLAY","GameFontNormalLarge"); title:SetPoint("LEFT",12,0); title:SetText("Pizza Warriors Raid Planner")
  local version=header:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); version:SetPoint("RIGHT",-34,0); version:SetText("v"..PB.VERSION)
  local close=CreateFrame("Button",nil,header,"UIPanelCloseButton"); close:SetPoint("RIGHT",2,0)
  close:SetScript("OnClick",function()
    if PB.ui and PB.ui.edit then PB.ui.edit:ClearFocus() end
    f:Hide()
  end)

  local status=f:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
  status:SetPoint("TOPLEFT",16,-42); status:SetJustifyH("LEFT"); status:SetWidth(math.max(300,(self.db.ui.width or 860)-116)); status:SetHeight(18); f.status=status

  local tabButtons={}
  local function button(key,text,x,width,fn)
    local b=CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
    b:SetWidth(width or 100); b:SetHeight(26); b:SetPoint("TOPLEFT",x,-62); b:SetText(text); b:SetScript("OnClick",fn)
    tabButtons[key]=b
    return b
  end
  button("roster","Roster",16,92,function() PB:ShowView("roster") end)
  button("sources","DPS Sources",112,104,function() PB:ShowView("sources") end)
  button("plan","BQL Review",220,100,function()
    local plan,err=PB:PrepareBQLPlanSafe()
    if not plan and err then PB:Print(err); return end
    PB:ShowView("plan")
  end)
  button("copy-bpc","Copy BPC",324,100,function()
    local plan,err=PB:PrepareBPCPlanSafe()
    if not plan then PB:Print(err or "BPC plan could not be generated."); return end
    PB:ShowExport("tsv","bpc")
  end)
  button("copy-bql","Copy BQL",428,100,function()
    local plan,err=PB:PrepareBQLPlanSafe()
    if not plan then PB:Print(err or "BQL plan could not be generated."); return end
    PB:ShowExport("tsv","plan")
  end)
  button("scan","Scan Raid",532,100,function() PB:ClearFestergutHistorySelectionSafe(false); PB:ScanRoster(); PB:UpdateUI() end)
  local liveButton=button("live","Live: Off",636,100,function()
    if PB.live.active then PB:StopLive() else PB:ClearFestergutHistorySelectionSafe(false); PB:StartLive() end
  end)

  local editorPanel=CreateFrame("Frame",nil,f); editorPanel:SetPoint("TOPLEFT",16,-98); editorPanel:SetPoint("BOTTOMRIGHT",-16,42)
  local scroll=CreateFrame("ScrollFrame","PizzaRaidPlannerScrollFrame",editorPanel,"UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT",8,-8); scroll:SetPoint("BOTTOMRIGHT",-28,8)
  local edit=CreateFrame("EditBox",nil,scroll)
  edit:SetMultiLine(true); edit:SetAutoFocus(false); edit:SetFontObject(ChatFontNormal); edit:SetWidth(778); edit:SetHeight(350)
  if edit.SetWordWrap then edit:SetWordWrap(false) end
  if edit.SetTextInsets then edit:SetTextInsets(4,4,4,4) end
  edit:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
  edit:SetScript("OnEnterPressed",function(self) self:ClearFocus() end)
  edit:SetScript("OnTextChanged",function() if scroll.UpdateScrollChildRect then scroll:UpdateScrollChildRect() end end)
  scroll:SetScrollChild(edit)

  local sourceContent=CreateFrame("Frame",nil,scroll)
  sourceContent:SetWidth(778); sourceContent:SetHeight(350); sourceContent:Hide()
  local sourceHeader=sourceContent:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
  sourceHeader:SetPoint("TOPLEFT",8,-10); sourceHeader:SetText("SAVED FESTERGUT HISTORY")
  local sourceSummary=sourceContent:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
  sourceSummary:SetPoint("TOPLEFT",8,-32); sourceSummary:SetJustifyH("LEFT"); sourceSummary:SetWidth(744); sourceSummary:SetHeight(18)
  if scroll.EnableMouseWheel then
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel",function(self,delta)
      if not self.GetVerticalScroll or not self.SetVerticalScroll then return end
      local current=self:GetVerticalScroll() or 0; local range=self.GetVerticalScrollRange and self:GetVerticalScrollRange() or 0
      self:SetVerticalScroll(math.max(0,math.min(range,current-delta*28)))
    end)
  end

  local helper=f:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); helper:SetPoint("BOTTOMLEFT",18,15); helper:SetText("Copy BPC to WoW TSV Dump A1; Copy BQL to A55. Use each printed values-only range on its encounter tab.")
  local selectAll=CreateFrame("Button",nil,f,"UIPanelButtonTemplate"); selectAll:SetWidth(104); selectAll:SetHeight(24); selectAll:SetPoint("BOTTOMRIGHT",-16,8); selectAll:SetText("Select All"); selectAll:SetScript("OnClick",function() edit:SetFocus(); edit:HighlightText() end)

  f.edit=edit; f.scroll=scroll; f.editorPanel=editorPanel; f.editorViewportHeight=350; f.tabButtons=tabButtons; f.liveButton=liveButton; f.helper=helper; f.close=close; f.logo=logo
  f.selectAll=selectAll; f.sourceContent=sourceContent; f.sourceHeader=sourceHeader; f.sourceSummary=sourceSummary; f.sourceButtons={}; f.skins=skins
  if engine and f.SetTemplate then
    f:SetTemplate("Transparent"); header:SetTemplate("Default"); editorPanel:SetTemplate("Default")
    if skins then
      if skins.HandleButton then
        for _,b in pairs(tabButtons) do skins:HandleButton(b) end
        skins:HandleButton(selectAll)
      end
      if skins.HandleCloseButton then skins:HandleCloseButton(close) end
      local scrollBar=_G.PizzaRaidPlannerScrollFrameScrollBar
      if scrollBar and skins.HandleScrollBar then skins:HandleScrollBar(scrollBar) end
    end
    elvFont(title,engine,14); elvFont(version,engine,11); elvFont(status,engine,11); elvFont(helper,engine,11); elvFont(sourceHeader,engine,13); elvFont(sourceSummary,engine,11)
    if edit.SetFont and engine.media and engine.media.normFont then edit:SetFont(engine.media.normFont,12,"") end
    if title.SetTextColor and engine.media and engine.media.rgbvaluecolor then local color=engine.media.rgbvaluecolor; title:SetTextColor(color[1],color[2],color[3],color[4] or 1) end
    f.elvui=engine; f.elvuiStyled=true
  else
    fallbackBackdrop(f,.94); fallbackBackdrop(header,.98); fallbackBackdrop(editorPanel,.98); f.elvuiStyled=false
  end
  self.ui=f
  for key,b in pairs(tabButtons) do local help=TAB_HELP[key]; if help then self:AttachButtonHelp(b,help[1],help[2]) end end
  self:SetEditorText("Enter ICC and raid normally. Before Princes use /prp publish bpc and paste at WoW TSV Dump A1; before Blood Queen use /prp publish and paste at A55. Each ready-sized block prints its exact visible-tab destination; use Ctrl+Shift+V there to preserve formatting.")
end

function PB:GetSourceHistoryButton(index)
  local button=self.ui.sourceButtons[index]
  if button then return button end
  button=CreateFrame("Button",nil,self.ui.sourceContent,"UIPanelButtonTemplate")
  button:SetWidth(744); button:SetHeight(28)
  if self.ui.skins and self.ui.skins.HandleButton then self.ui.skins:HandleButton(button) end
  self.ui.sourceButtons[index]=button
  return button
end

function PB:UpdateSourceHistoryUI()
  if not self.ui then return end
  local history=self:EnsureFestergutHistorySafe()
  local selected=self:GetSelectedFestergutHistoryEntrySafe()
  if self.db.selectedFestergutHistoryId and not selected then self.db.selectedFestergutHistoryId=nil end
  local rows={{id="current",current=true}}
  for i=#history,1,-1 do rows[#rows+1]={id=history[i].id,entry=history[i]} end

  if selected then
    self.ui.sourceSummary:SetText("Selected: Festergut "..date("%Y-%m-%d %H:%M",selected.recordedAt).." | "..#(selected.roster or {}).." recorded raiders | BPC and BQL use this kill")
  else
    self.ui.sourceSummary:SetText("Current raid mode | "..#history.." saved Festergut kill"..(#history==1 and "" or "s").." available")
  end

  for index,row in ipairs(rows) do
    local button=self:GetSourceHistoryButton(index)
    button:ClearAllPoints(); button:SetPoint("TOPLEFT",8,-56-(index-1)*34)
    button._prpSourceId=row.id
    if row.current then
      button:SetText("CURRENT RAID | live roster + current-session Festergut")
      button:SetScript("OnClick",function()
        PB:ClearFestergutHistorySelectionSafe(true)
        PB:ShowView("sources")
        PB:Print("Returned to current-raid planning.")
      end)
      self:AttachButtonHelp(button,"Current Raid","Use the live raid roster and the latest valid Festergut benchmark from the current ICC session. This exits historical rehearsal mode.")
    else
      local entry=row.entry
      local difficulty=entry.difficultyName or "Raid"
      button:SetText("FESTERGUT | "..date("%Y-%m-%d %H:%M",entry.recordedAt).." | "..difficulty.." | "..math.floor(entry.duration or 0).."s | "..#(entry.roster or {}).." raiders")
      button:SetScript("OnClick",function()
        local result,err=PB:SelectFestergutHistorySafe(entry.id)
        if not result then PB:Print("History load failed: "..tostring(err)); return end
        PB:ShowView("sources")
        PB:Print("Loaded saved Festergut from "..date("%Y-%m-%d %H:%M",entry.recordedAt).."; BPC, BQL Review, and both Copy tabs are ready.")
      end)
      self:AttachButtonHelp(button,"Saved Festergut Kill","Loads this kill's Festergut-only DPS and recorded raid composition into BPC and BQL rehearsal outputs. It does not overwrite or replace the live raid roster.")
    end
    button:Show()
  end
  for index=#rows+1,#self.ui.sourceButtons do self.ui.sourceButtons[index]:Hide() end
  self.ui.sourceContent:SetHeight(math.max(self.ui.editorViewportHeight or 350,72+#rows*34))
  self:UpdateTabStyles()
end

function PB:ShowUI() self:CreateUI(); self.uiView=self.uiView or "roster"; self.ui:Show(); self:UpdateUI() end
function PB:HideUI() if self.ui then self.ui:Hide() end end
function PB:ShowView(view) self:CreateUI(); self.uiView=view; self.exportKind=nil; self.ui.edit:ClearFocus(); self.ui:Show(); self:UpdateUI() end
function PB:ShowExport(format,kind)
  self:CreateUI(); self.uiView="export"; self.exportKind=kind=="bpc" and "bpc" or "bql"
  self:SetEditorText(self:GetExport(format,kind)); self.ui:Show(); self:UpdateUI(); self.ui.edit:SetFocus(); self.ui.edit:HighlightText()
end

function PB:UpdateUI()
  if not self.ui or not self.ui:IsShown() then return end
  local plan=self.db.latestPlan
  local bpcPlan=self.db.latestBPCPlan
  local historyEntry=self:GetSelectedFestergutHistoryEntrySafe()
  local bqlView=self.uiView=="plan" or (self.uiView=="export" and self.exportKind=="bql")
  local source
  if historyEntry then source=historyEntry.festergutSource
  elseif bqlView then source=plan and plan.source
  elseif self.uiView=="export" and self.exportKind=="bpc" then source=bpcPlan and bpcPlan.source
  else source=self:GetFestergutSource() end
  local prefix=self.uiView=="export" and "COPY READY - CTRL+C | " or ""
  local raidCount=historyEntry and #(historyEntry.roster or {}) or #self.roster
  local mode=historyEntry and ("HISTORY "..date("%Y-%m-%d %H:%M",historyEntry.recordedAt)) or ("ICC "..(self:IsICCTrackingActive() and "ON" or "OFF"))
  self.ui.status:SetText(prefix..mode.." | "..raidCount.." raiders | Source: "..(source and source.targetName or "missing Festergut").." | Reviews: "..(plan and #(plan.warnings or {}) or 0))
  if self.ui.liveButton then self.ui.liveButton:SetText(self.live.active and "Live: On" or "Live: Off") end
  self:UpdateTabStyles()
  if self.uiView=="export" then return end
  if self.uiView=="sources" then
    self:SetContentMode("sources")
    self:UpdateSourceHistoryUI()
    return
  end
  self:SetContentMode("edit")
  local lines={}
  if self.uiView=="plan" then
    lines[#lines+1]="BQL BITE REVIEW"..(historyEntry and (" | SAVED FESTERGUT "..date("%Y-%m-%d %H:%M",historyEntry.recordedAt)) or "")
    if plan then
      for _,a in ipairs(plan.assignments or {}) do lines[#lines+1]=(a.wave==0 and "Initial" or "Bite "..a.wave)..": "..a.biter.." ["..(a.biterSlot or "").."] -> "..a.target.." ["..(a.targetSlot or "").."] | "..(a.movement or "") end
      for _,w in ipairs(plan.warnings or {}) do lines[#lines+1]="REVIEW: "..w end
    else lines[#lines+1]="Generate a plan with /prp publish." end
  else
    lines[#lines+1]="ROSTER (rank | name | class / spec | role | position | group | expected DPS | eligibility)"
    local ranked=self:GetRankedPlayers(self.live.active)
    for i,x in ipairs(ranked) do local p=x.player; lines[#lines+1]=i.." | "..p.name.." | "..p.classToken.." / "..self:GetSpecName(p).." | "..self:ResolveRole(p).." | "..p.position.." | "..p.subgroup.." | "..(p.expectedDPS and math.floor(p.expectedDPS) or "no sample").." | "..p.exclusionReason end
    for _,p in ipairs(self.roster) do if not p.eligible then lines[#lines+1]="Excluded | "..p.name.." | "..self:GetSpecName(p).." | "..(p.exclusionReason or "unknown") end end
  end
  self:SetEditorText(table.concat(lines,"\n"))
end
