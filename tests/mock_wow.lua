-- Minimal 3.3.5-like environment for pure logic tests; it is not a client emulator.
MOCK_TIME=1000
MOCK_INSTANCE_NAME="Icecrown Citadel"
MOCK_INSTANCE_TYPE="raid"
MOCK_DIFFICULTY_INDEX=4
MOCK_DIFFICULTY_NAME="25 Player (Heroic)"
MOCK_MAX_PLAYERS=25
MOCK_ZONE_NAME="Icecrown Citadel"
function time() return MOCK_TIME end
function date(_, value) return "2026-08-03 12:00" end
function GetInstanceInfo() return MOCK_INSTANCE_NAME,MOCK_INSTANCE_TYPE,MOCK_DIFFICULTY_INDEX,MOCK_DIFFICULTY_NAME,MOCK_MAX_PLAYERS end
function GetRealZoneText() return MOCK_ZONE_NAME end
DEFAULT_CHAT_FRAME={AddMessage=function() end}
UIParent={}
function CreateFrame(_,name,parent)
  local f={scripts={},shown=false,parent=parent}; local noop=function() end
  for _,k in ipairs({"RegisterEvent","SetWidth","SetHeight","SetPoint","ClearAllPoints","SetFrameStrata","EnableMouse","EnableMouseWheel","SetMovable","RegisterForDrag","SetBackdrop","SetBackdropColor","SetTemplate","StartMoving","StopMovingOrSizing","SetMultiLine","SetAutoFocus","SetFontObject","SetFont","SetTextInsets","SetWordWrap","SetFocus","SetCursorPosition","HighlightText","ClearFocus","SetVerticalScroll","UpdateScrollChildRect"}) do f[k]=noop end
  f.SetText=function(self,value) self.text=value end; f.GetText=function(self) return self.text end
  f.SetBackdropBorderColor=function(self,...) self.borderColor={...} end
  f.SetScrollChild=function(self,child) self.scrollChild=child end
  f.SetScript=function(self,event,handler) self.scripts[event]=handler end
  f.GetScript=function(self,event) return self.scripts[event] end
  f.HookScript=function(self,event,handler)
    local original=self.scripts[event]
    self.scripts[event]=function(frame,...)
      if original then original(frame,...) end
      handler(frame,...)
    end
  end
  f.Show=function(self) self.shown=true end; f.Hide=function(self) self.shown=false end
  f.IsShown=function(self) return self.shown end
  f.GetVerticalScroll=function() return 0 end; f.GetVerticalScrollRange=function() return 0 end
  f.CreateFontString=function()
    local font={shown=true,SetPoint=noop,SetJustifyH=noop,SetWidth=noop,SetHeight=noop,SetFont=noop,SetTextColor=noop}
    font.SetText=function(self,value) self.text=value end; font.GetText=function(self) return self.text end
    font.Show=function(self) self.shown=true end; font.Hide=function(self) self.shown=false end
    return font
  end
  f.CreateTexture=function()
    local texture={shown=true,SetTexCoord=noop,SetAlpha=noop}
    texture.SetPoint=function(self,...) self.point={...} end
    texture.SetWidth=function(self,value) self.width=value end
    texture.SetHeight=function(self,value) self.height=value end
    texture.SetTexture=function(self,value) self.texture=value end
    texture.Show=function(self) self.shown=true end; texture.Hide=function(self) self.shown=false end
    return texture
  end
  if name then _G[name]=f end
  return f
end
GameTooltip={shown=false,lines={}}
function GameTooltip:SetOwner(owner) self.owner=owner end
function GameTooltip:SetText(value) self.text=value; self.lines={} end
function GameTooltip:AddLine(value) self.lines[#self.lines+1]=value end
function GameTooltip:Show() self.shown=true end
function GameTooltip:Hide() self.shown=false; self.owner=nil end
function GameTooltip:IsOwned(owner) return self.owner==owner end
SlashCmdList={}; RAID_CLASS_COLORS={}
function GetNumRaidMembers() return 0 end
function UnitGUID() return nil end
function UnitIsConnected() return true end
function GetRaidRosterInfo() return nil end
function IsRaidLeader() return false end
function SendChatMessage() end
