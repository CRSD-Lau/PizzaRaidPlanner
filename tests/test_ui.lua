local PB=PizzaRaidPlanner
PizzaRaidPlannerDB=nil; PizzaRaidPlannerExportDB=nil; PB:InitDB(); PB.ui=nil
local handled=0
local skins={
  HandleButton=function() handled=handled+1 end,
  HandleCloseButton=function() handled=handled+1 end,
  HandleScrollBar=function() handled=handled+1 end,
}
local engine={media={normFont="ElvUIFont",rgbvaluecolor={1,.4,.1},bordercolor={.1,.1,.1}},GetModule=function(_,name) if name=="Skins" then return skins end end}
ElvUI={engine}
PB.db.festergutHistory={{id="festergut-history-ui",recordedAt=900,duration=120,difficultyName="25 Player",roster={{guid="UI1",name="UI1"}},festergutSource={id="ui-source",targetName="Festergut",players={}}}}
PB:CreateUI()
assert(PB.ui and PB.ui.edit and PB.ui.status and PB.ui.scroll and PB.ui.editorPanel,"frame and scrollable editor constructs")
assert(PB.ui.logo and PB.ui.logo.texture=="Interface\\AddOns\\PizzaRaidPlanner\\Media\\PizzaWarriorsLogo","Pizza Warriors logo texture is loaded")
assert(PB.ui.logo.width==56 and PB.ui.logo.height==56,"Pizza Warriors logo is enlarged")
assert(PB.ui.logo.point and PB.ui.logo.point[1]=="TOPRIGHT" and PB.ui.logo.point[2]==PB.ui and PB.ui.logo.point[3]=="TOPRIGHT" and PB.ui.logo.point[4]==-30 and PB.ui.logo.point[5]==-38,"Pizza Warriors logo sits below the version beside Live")
assert(PB.ui.elvuiStyled==true and PB.ui.elvui==engine,"ElvUI theme integration selected")
assert(handled>=9,"ElvUI skins applied to controls")
assert(PB.ui.tabButtons["copy-bpc"] and PB.ui.tabButtons["copy-bql"],"separate BPC and BQL copy actions")
PB:ShowView("sources")
assert(PB.ui.sourceContent:IsShown() and not PB.ui.edit:IsShown() and #PB.ui.sourceButtons==2,"DPS Sources renders current mode plus clickable Festergut history rows")
local sourcesTab=PB.ui.tabButtons.sources
sourcesTab.scripts.OnEnter(sourcesTab)
assert(sourcesTab._prpHovered and GameTooltip.shown and GameTooltip.text=="DPS Sources","tab mouseover keeps the accent border and shows explanatory help")
sourcesTab.scripts.OnLeave(sourcesTab)
assert(not sourcesTab._prpHovered and sourcesTab.borderColor[1]==1 and sourcesTab.borderColor[2]==.4,"active tab remains highlighted after mouseover ends")
PB:ShowView("plan")
assert(PB.ui.edit:IsShown() and not PB.ui.sourceContent:IsShown(),"leaving DPS Sources restores the text review surface")
PB.ui:Show(); assert(PB.ui:IsShown(),"planner window can be shown")
PB.ui.close.scripts.OnClick(); assert(not PB.ui:IsShown(),"top-right close button hides the full planner window")
ElvUI=nil
PB.ui=nil
PB:CreateUI()
assert(PB.ui.elvuiStyled==false,"legacy visual fallback remains available without ElvUI")
print("test_ui: OK")
