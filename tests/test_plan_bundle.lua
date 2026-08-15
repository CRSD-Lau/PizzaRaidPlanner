local PB=PizzaRaidPlanner
PizzaRaidPlannerDB=nil; PizzaRaidPlannerExportDB=nil; PB:InitDB(); PB.live={active=false,vampires={},completed={}}

local function player(name,classToken,spec,role,dps,index)
  PB.db.roleOverrides[name:lower()]=role
  return {
    guid=name,name=name,normalizedName=name:lower(),classToken=classToken,spec=spec,
    raidIndex=index,subgroup=math.floor((index-1)/5)+1,online=true,connected=true,dead=false,
    expectedDPS=dps and dps>0 and dps or nil,
  }
end

local roster={}
local function add(name,classToken,spec,role,dps)
  roster[#roster+1]=player(name,classToken,spec,role,dps,#roster+1)
end
add("MageOne","MAGE",63,"dps",15000); add("MageTwo","MAGE",63,"dps",14500)
add("WarlockOne","WARLOCK",266,"dps",14200); add("WarlockTwo","WARLOCK",266,"dps",14000)
add("HunterOne","HUNTER",254,"dps",13900); add("HunterTwo","HUNTER",254,"dps",13700)
add("BoomkinOne","DRUID",102,"dps",13600); add("ShadowOne","PRIEST",258,"dps",13500)
add("ElementalOne","SHAMAN",262,"dps",13400); add("HunterThree","HUNTER",254,"dps",13300)
add("RogueOne","ROGUE",259,"dps",14800); add("RogueTwo","ROGUE",259,"dps",14600)
add("DeathKnightOne","DEATHKNIGHT",252,"dps",14400); add("RetOne","PALADIN",70,"dps",14300)
add("RetTwo","PALADIN",70,"dps",14100); add("WarriorOne","WARRIOR",71,"dps",13800)
add("EnhancementOne","SHAMAN",263,"dps",13200); add("WarriorTwo","WARRIOR",71,"dps",13100)
add("TankOne","WARRIOR",73,"tank",0); add("TankTwo","PALADIN",66,"tank",0)
add("HolyOne","PALADIN",65,"healer",0); add("HolyTwo","PALADIN",65,"healer",0)
add("HealerThree","PRIEST",256,"healer",0); add("HealerFour","DRUID",105,"healer",0); add("HealerFive","SHAMAN",264,"healer",0)

local function sourceFor(id,recordedAt,entries)
  local source={id=id,segmentId=id,targetName="Festergut",iccEncounter="festergut",sessionId="bundle-session",recordedAt=recordedAt,duration=180,valid=true,result="kill",confirmedKill=true,players={}}
  for _,p in ipairs(entries) do
    local dps=p.expectedDPS or 0
    source.players[p.guid]={dps=dps,totalDamage=dps*180,primaryDamage=dps*180,healing=0}
  end
  return source
end

local historicalRoster={
  player("ReplacementMage","MAGE",63,"dps",14150,1),
  player("ReplacementHunter","HUNTER",254,"dps",13850,2),
  player("ReplacementRogue","ROGUE",259,"dps",14750,3),
}
local missingSourceBundle,missingSourceError=PB:BuildPlanBundle({roster=roster,reason="current"})
assert(not missingSourceBundle and missingSourceError:find("No confirmed Festergut kill",1,true),"an atomic plan cannot be created without a confirmed Festergut benchmark")
local wipeSource=sourceFor("wipe-source",650,roster); wipeSource.result="wipe"; wipeSource.confirmedKill=false
local wipeBundle,wipeBundleError=PB:BuildPlanBundle({roster=roster,source=wipeSource,reason="current"})
assert(not wipeBundle and wipeBundleError:find("wipe or incomplete pull",1,true),"an explicit Festergut wipe source is rejected even when passed directly")
local historicalSource=sourceFor("older-kill",700,historicalRoster)
PB:RememberFestergutHistory(historicalSource,historicalRoster)

local currentSource=sourceFor("current-kill",900,roster)
local currentEntry=PB:RememberFestergutHistory(currentSource,roster)
assert(currentEntry and PB:IsConfirmedFestergutHistoryEntry(currentEntry),"confirmed Festergut kill is selectable planning evidence")

local changedSpec=player("MageOne","MAGE",62,"dps",0,1)
local changedSpecSource,changedSpecEvidence=PB:BuildAudibleFestergutSource(currentSource,{changedSpec},currentEntry,true)
assert(changedSpecSource.players.MageOne==nil and changedSpecSource.provenanceByGUID.MageOne.kind=="missing","a post-Festergut spec change cannot inherit the player's old-spec DPS")
assert(changedSpecEvidence.missing[1].reason=="spec-change","spec-change provenance is distinct from an incoming replacement")

local first,firstError=PB:BuildPlanBundle({roster=roster,source=currentSource,reason="current"})
assert(first and not firstError and first.bpc.bundleId==first.bql.bundleId,"initial BPC/BQL plans share one atomic bundle")
assert(first.rosterCount==25 and first.revision==1 and first.mode=="current","initial bundle records the exact 25-player context")

local shuffled={}
local removed={MageTwo=true,WarlockTwo=true,HunterThree=true,RogueTwo=true,WarriorTwo=true}
for _,p in ipairs(roster) do if not removed[p.name] then shuffled[#shuffled+1]=p end end
for _,p in ipairs(historicalRoster) do shuffled[#shuffled+1]=p end
shuffled[#shuffled+1]=player("ReplacementBoomkin","DRUID",102,"dps",0,#shuffled+1)
shuffled[#shuffled+1]=player("ReplacementRet","PALADIN",70,"dps",0,#shuffled+1)
for index,p in ipairs(shuffled) do p.raidIndex=index; p.subgroup=math.floor((index-1)/5)+1 end

local audible,audibleError=PB:BuildPlanBundle({roster=shuffled,source=currentSource,reason="audible"})
assert(audible and not audibleError and audible.bpc.bundleId==audible.bql.bundleId,"roster audible regenerates both encounters as one bundle")
assert(audible.revision==2 and audible.largeShuffle,"five replacements produce a new full-rebuild revision")
assert(#audible.previousRosterDiff.outgoing==5 and #audible.previousRosterDiff.incoming==5,"audible records the exact five-out/five-in roster delta")
assert(audible.planChanges.totalChanges>0 and #audible.planChanges.details==audible.planChanges.totalChanges,"audible retains every changed position, bite link, and utility slot for review")
assert(#audible.benchmarkEvidence.historical==3 and #audible.benchmarkEvidence.missing==2,"replacement DPS uses same-spec Festergut history only and flags missing evidence")
assert(math.floor(audible.source.players.ReplacementMage.dps)==14150 and math.floor(audible.source.players.ReplacementRogue.dps)==14750,"historical same-spec Festergut DPS is mapped onto substitutes")
assert(audible.source.players.ReplacementBoomkin==nil and audible.source.players.ReplacementRet==nil,"unbenchmarked replacements never receive an ICC-average fallback")
assert(audible.bpc.source==audible.bql.source and audible.bpc.rosterHash==audible.bql.rosterHash,"both planners consume the same composite source and roster fingerprint")

local committedBundle=PB.db.latestPlanBundle
local committedBPC=PB.db.latestBPCPlan
local committedBQL=PB.db.latestPlan
local originalGeneratePlan=PB.GeneratePlan
PB.GeneratePlan=function() error("simulated BQL planner failure") end
local failedBundle,failedError=PB:BuildPlanBundle({roster=shuffled,source=currentSource,reason="audible"})
PB.GeneratePlan=originalGeneratePlan
assert(not failedBundle and failedError:find("simulated BQL planner failure",1,true),"bundle generation reports a failed encounter half")
assert(PB.db.latestPlanBundle==committedBundle and PB.db.latestBPCPlan==committedBPC and PB.db.latestPlan==committedBQL,"a failed rebuild preserves the last complete atomic pair")

local payload=PB:BuildExports()
assert(payload and payload.bundleMeta:find(audible.bundleId,1,true),"SavedVariables export carries the atomic plan bundle id")
assert(PB.exportDB.bundleMetaB64 and PB.exportDB.bundleMetaB64~="","desktop publisher receives Base64 bundle metadata")

PB.roster=PB:SnapshotPlanningRoster(shuffled)
PB.roster[#PB.roster+1]=player("LateSwap","WARLOCK",266,"dps",0,#PB.roster+1)
PB:UpdatePlanDirtyState()
assert(PB.db.planDirty and PB.db.planDirtyReason=="roster" and PB.db.pendingRosterDiff and PB.db.pendingRosterDiff.changed,"a post-plan roster change marks the publish bundle dirty")
local dirtyPayload=PB:BuildExports()
assert(PB.db.latestPlanBundle==audible and PB.db.planDirty,"/reload export cannot silently replace a dirty bundle")
assert(dirtyPayload.bundleMeta:find('"dirty":true',1,true) and dirtyPayload.bundleMeta:find(audible.bundleId,1,true),"dirty metadata preserves the last complete pair for publisher rejection")

PB.roster=PB:SnapshotPlanningRoster(shuffled)
PB.festergutSourceOverride=sourceFor("next-kill",1100,shuffled)
PB:UpdatePlanDirtyState()
assert(PB.db.planDirty and PB.db.planDirtyReason=="benchmark" and PB.db.pendingRosterDiff==nil,"a new Festergut benchmark invalidates an otherwise identical roster plan")
PB.festergutSourceOverride=nil

print("test_plan_bundle: OK")
