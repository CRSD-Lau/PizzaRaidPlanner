local PB=PizzaRaidPlanner
PizzaRaidPlannerDB=nil; PizzaRaidPlannerExportDB=nil; PB:InitDB()
PB.segment=nil; PB.live={active=false,vampires={},completed={}}
PB.roster={
  {guid="P1",name="MageOne",normalizedName="mageone",classToken="MAGE",online=true,connected=true,dead=false},
  {guid="P2",name="HunterOne",normalizedName="hunterone",classToken="HUNTER",online=true,connected=true,dead=false},
}
PB.byGUID={P1=PB.roster[1],P2=PB.roster[2]}; PB.byName={mageone=PB.roster[1],hunterone=PB.roster[2]}; PB.petOwners={}

MOCK_INSTANCE_NAME="Dalaran"; MOCK_INSTANCE_TYPE="none"; MOCK_ZONE_NAME="Dalaran"
PB.insideICC=nil; PB:UpdateICCState(true); PB:StartAutomaticSegment()
assert(PB.segment==nil,"damage tracking stays off outside ICC")

MOCK_TIME=2000; MOCK_INSTANCE_NAME="Icecrown Citadel"; MOCK_INSTANCE_TYPE="raid"; MOCK_ZONE_NAME="Icecrown Citadel"
PB:UpdateICCState(true)
local firstSession=PB.db.iccSession.id
assert(PB.insideICC and firstSession,"entering ICC starts a session")

local function bossSample(name,duration,p1Damage,p2Damage,killed)
  assert(PB:StartAutomaticSegment(),"ICC segment starts")
  PB.segment.started=MOCK_TIME-duration
  PB:RecordSegmentDamage("P1","BOSS",name,p1Damage,false); PB:RecordTargetDamage("P1","BOSS",p1Damage)
  PB:RecordSegmentDamage("P2","BOSS",name,p2Damage,false); PB:RecordTargetDamage("P2","BOSS",p2Damage)
  if killed~=false then PB:MarkSegmentBossKill("BOSS",name,"test") end
  PB:FinishSegment()
end

bossSample("Lord Marrowgar",60,60000,30000)
MOCK_TIME=2100; bossSample("Festergut",60,120000,90000)
local average=PB:GetICCAverageSource()
local festergut=PB:GetFestergutSource()
assert(average and average.sampleCount==2,"two valid ICC bosses feed the running average")
assert(math.floor(average.players.P1.dps)==1500,"ICC average uses mean boss DPS")
assert(math.floor(average.players.P2.dps)==1000,"ICC average is per player")
assert(PB:GetSelectedSource().id==average.id,"automatic source prefers ICC running average")
assert(festergut and festergut.targetName=="Festergut","Festergut is retained as the dedicated BQL benchmark")
assert(math.floor(festergut.players.P1.dps)==2000 and math.floor(festergut.players.P2.dps)==1500,"Festergut benchmark keeps encounter-only DPS")
assert(PB:GetBQLBenchmarkSource().id==festergut.id,"BQL source uses Festergut instead of the aggregate")
assert(#PB.db.festergutHistory==1 and #PB.db.festergutHistory[1].roster==2,"a valid Festergut automatically stores its DPS and raid roster in history")
PB.db.iccSession.benchmarks=nil; local rebuiltFestergut=PB:GetFestergutSource()
assert(rebuiltFestergut and rebuiltFestergut.segmentId==festergut.segmentId,"0.5-era segment history rebuilds the dedicated Festergut benchmark")
festergut=rebuiltFestergut

local stored=#PB.db.segments
MOCK_TIME=2200; bossSample("Deathbound Ward",60,80000,40000)
assert(#PB.db.segments==stored,"automatic trash segments are not stored")
for i=1,PB.MAX_SEGMENTS+1 do MOCK_TIME=2200+i*100; bossSample("Rotface",60,60000,40000) end
local preBQLCount=PB:GetICCAverageSource().sampleCount
assert(#PB.db.segments==PB.MAX_SEGMENTS,"individual review history remains bounded")
assert(preBQLCount>PB.MAX_SEGMENTS,"cumulative average survives review-history rollover")
assert(PB:GetFestergutSource() and PB:GetFestergutSource().segmentId==festergut.segmentId,"Festergut benchmark survives bounded review-history rollover")
local historyBeforeBQL=#PB.db.segments
MOCK_TIME=MOCK_TIME+100; bossSample("Blood-Queen Lana'thel",60,100000,60000)
assert(#PB.db.segments==historyBeforeBQL and PB.db.segments[#PB.db.segments].isBQL,"BQL remains auditable as an individual sample")
assert(PB:GetICCAverageSource().sampleCount==preBQLCount,"BQL vampire encounter never changes the pre-fight average")

MOCK_INSTANCE_NAME="Dalaran"; MOCK_INSTANCE_TYPE="none"; MOCK_ZONE_NAME="Dalaran"; PB:UpdateICCState(true)
MOCK_TIME=MOCK_TIME+PB.ICC_SESSION_TIMEOUT+1
MOCK_INSTANCE_NAME="Icecrown Citadel"; MOCK_INSTANCE_TYPE="raid"; MOCK_ZONE_NAME="Icecrown Citadel"; PB:UpdateICCState(true)
assert(PB.db.iccSession.id~=firstSession,"a long break starts a fresh ICC session")
assert(PB:GetICCAverageSource()==nil,"a new ICC session does not reuse an old raid average")
assert(PB:GetFestergutSource()==nil,"a new ICC session does not reuse an old Festergut benchmark")
MOCK_TIME=MOCK_TIME+100; bossSample("Festergut",60,120000,90000,false)
assert(PB:GetFestergutSource()==nil and not PB:IsConfirmedFestergutHistoryEntry(PB.db.festergutHistory[#PB.db.festergutHistory]),"a valid Festergut wipe is retained for audit but never becomes the current planning benchmark")
print("test_icc_session: OK")
