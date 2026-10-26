-- Lua 5.0.3 production-source regressions for unique reminders, sharing, tracker.
local f = assert(io.open("pfQuest_Group.lua", "r"))
local source = f:read("*a")
f:close()

local function extract(startMarker, endMarker, functionName, env)
  local a = assert(string.find(source, startMarker, 1, true))
  local b = assert(string.find(source, endMarker, a + 1, true))
  local chunk = assert(loadstring(string.sub(source, a, b - 1)
    .. "\nreturn " .. functionName))
  setfenv(chunk, env)
  return chunk()
end
local env = {}
setmetatable(env, {__index = _G})
env.SafeString = function(v) if v == nil then return "" end return tostring(v) end
env.Trim = function(v) return v end
env.NewSessionId = function() return "new-id" end
local normalize = extract("local function NormalizeSession(", "local function NormalizeInstructionRecord(", "NormalizeSession", env)
local guide = normalize({mode="GUIDE",guideSessionId="live",dismissedObjectiveAlerts={["i:99#1"]=true}})
assert(guide.dismissedObjectiveAlerts["i:99#1"] and not next(guide.acknowledgedObjectiveAlerts))
local off = normalize({mode="OFF",dismissedObjectiveAlerts={x=true},acknowledgedObjectiveAlerts={y=true}})
assert(not next(off.dismissedObjectiveAlerts) and not next(off.acknowledgedObjectiveAlerts))
local tourist = normalize({mode="TOURIST",guideName="Guide",guideSessionId="live",joinBaseline=0,
  acknowledgedObjectiveAlerts={["i:99#1"]=true}})
assert(tourist.acknowledgedObjectiveAlerts["i:99#1"])
assert(not next(tourist.dismissedObjectiveAlerts))
assert(not next(normalize({mode="TOURIST",guideName="Guide",guideSessionId=nil,
  acknowledgedObjectiveAlerts={foo=true}}).acknowledgedObjectiveAlerts))

env.Addon = {db={session={mode="GUIDE",guideSessionId="live"}}}
env.guideTouristUI = {refresh=function() env.refreshes=(env.refreshes or 0)+1 end}
local acknowledge = extract("local function AcknowledgeSingleObjectiveReminder(",
  "local function EnsureSingleObjectiveRow(", "AcknowledgeSingleObjectiveReminder", env)
assert(acknowledge(true,"i:99#1","live"))
assert(env.Addon.db.session.dismissedObjectiveAlerts["i:99#1"])
assert(not env.Addon.db.session.acknowledgedObjectiveAlerts)
assert(not acknowledge(true,"i:99#2","stale"))
env.Addon.db.session = {mode="TOURIST",guideSessionId="live"}
assert(acknowledge(false,"i:99#1","live"))
assert(env.Addon.db.session.acknowledgedObjectiveAlerts["i:99#1"])
assert(not env.Addon.db.session.dismissedObjectiveAlerts)
assert(not acknowledge(true,"i:99#1","live"))
assert(env.refreshes == 2)
assert(string.find(source, 'row.action:SetText(guideMode and "X"', 1, true))
assert(not string.find(source, "row.statusX", 1, true))
assert(string.find(source, "GameTooltip:AddLine(SafeString(participant.name)", 1, true))

local messages = {}
local selected = 4
local pushCount = 0
local canPush = true
env.L = {}
env.DEFAULT_CHAT_FRAME = {AddMessage=function(_,v) table.insert(messages,v) end}
env.GetNumPartyMembers = function() return 2 end
env.GetNumQuestLogEntries = function() return 4 end
env.GetQuestLogSelection = function() return selected end
env.SelectQuestLogEntry = function(n) selected=n end
env.ReadQuestLogTitle = function(n)
  if n==2 then return "A real quest",nil,nil,false end
  if n==3 then return "A header",nil,nil,true end
  return "Other",nil,nil,false
end
env.ResolveQuestID = function(n) if n==2 then return 123 end end
env.GetQuestLogPushable = function() return canPush end
env.QuestLogPushQuest = function() pushCount=pushCount+1 end
env.Addon.db.session.mode="GUIDE"
local share=extract("local function TryNativeShareGuideQuest(",
  "local function EnsureGuideTouristRow(", "TryNativeShareGuideQuest",env)
assert(share({title="A real quest",questID=123}))
assert(pushCount==1 and selected==4,"native selection not restored")
canPush=nil
assert(not share({title="A real quest",questID=123}))
assert(pushCount==1 and selected==4,"nonshareable quest pushed or selection changed")
canPush=true
env.QuestLogPushQuest=function() error("API error") end
assert(not share({title="A real quest",questID=123}))
assert(selected==4,"API exception left wrong selection")
assert(not share({title="A missing quest",questID=124}))
assert(selected==4)
env.Addon.db.session.mode="TOURIST"
assert(not share({title="A real quest",questID=123}))
assert(pushCount==1)
assert(string.find(source, "row.share:Show()", 1, true))

-- Exercise both production row constructors: the share button belongs to Guide rows.
-- Earlier API-only tests missed the nil access during Guide panel rendering.
local function fakeRegion()
  local region = {scripts={}}
  setmetatable(region, {__index=function(_, name)
    if name=="CreateFontString" or name=="CreateTexture" then
      return function() return fakeRegion() end
    elseif name=="GetFont" then
      return function() return "font", 12, "" end
    elseif name=="SetScript" then
      return function(self, event, fn) self.scripts[event]=fn end
    elseif name=="Hide" then
      return function(self) self.hidden=true end
    elseif name=="Show" then
      return function(self) self.hidden=false end
    end
    return function() end
  end})
  return region
end
env.CreateFrame=function() return fakeRegion() end
env.CopyGroupTrackerFont=function() end
env.SkinGuideTouristButton=function() end
env.guideTouristUI.rows={}
env.guideTouristUI.touristRows={}
env.guideTouristUI.scrollChild=fakeRegion()
local makeTouristRow=extract("local function EnsureTouristRow(",
  "guideTouristUI.GetRowWidth = function()", "EnsureTouristRow",env)
local touristRow=makeTouristRow(1)
assert(touristRow and not touristRow.share, "Tourist row must not own native share")
local makeGuideRow=extract("local function EnsureGuideTouristRow(",
  "local function SaveGuideTouristWindowPosition(", "EnsureGuideTouristRow",env)
local guideRow=makeGuideRow(1)
assert(guideRow and guideRow.share and guideRow.shareText, "Guide share button absent")
assert(guideRow.share.hidden==true and guideRow.share.scripts.OnClick)
guideRow.share:Hide() -- exact operation that failed on 0.3.34-dev line 7285
assert(makeGuideRow(1)==guideRow, "Guide row reuse lost share button")
env.Addon.db.session.mode="GUIDE"
env.TryNativeShareGuideQuest=share
env.QuestLogPushQuest=function() pushCount=pushCount+1 end
guideRow.disparityQuest={title="A real quest",questID=123}
guideRow.share.scripts.OnClick()
assert(pushCount==2 and selected==4, "Guide name click failed native share/selection restoration")
assert(string.find(source, "SetGuideDisparityHidden(row.disparityKey", 1, true))

local remoteQuest={questID=123,title="A real quest",objectives={{index=1,current=1,required=1}}}
local remote={compatible=true,questState={ready=true,quests={["i:123"]=remoteQuest}}}
env.UnitExists = function(unit) return unit=="party1" end
env.UnitName = function() return "Tara" end
env.NormalizeName = function(name) return string.lower(name) end
env.peers = {tara=remote}
env.RemoteObjectiveDone = function(o)
  return o and (o.done or (o.current or 0)>=(o.required or 1))
end
env.FindRemoteTrackerQuest = function(st,q) return st.quests["i:" .. q.questID] end
env.FindQuestObjective = function(q,i) return q.objectives[i] end
local allDone=extract("local function TrackerObjectiveAllDone(",
  "local function PreserveSharedTrackerObjectives(", "TrackerObjectiveAllDone",env)
local q={questID=123,objectives={{index=1,current=1,required=1},{index=2,current=0,required=1}}}
assert(allDone(q,1,{remote}),"verified shared objective must hide")
assert(not allDone(q,2,{remote}),"local unfinished must stay visible")
remoteQuest.objectives[1].current=0
assert(not allDone(q,1,{remote}),"remote unfinished must stay visible")
remote.questState.ready=false
assert(not allDone(q,1,{remote}),"unready remote is not evidence")
remote.questState.ready=true
remoteQuest.objectives[1].current=1
env.peers={}
assert(not allDone(q,1,{remote}),"unknown peer cannot be assumed complete")
env.peers={tara=remote}
assert(not allDone(q,1,{}),"no matched quest peers means native view")
assert(string.find(source, "objective.pfqGroupHiddenCompleted = true", 1, true))
assert(string.find(source, "button:SetHeight(entryHeight + lineCount * fontSize)", 1, true))
print("three targeted production regressions passed")
