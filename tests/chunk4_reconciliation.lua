-- Chunk 4 production-source integration: Lua 5.0.3, no game client.
local f = assert(io.open("pfQuest_Group.lua", "r"))
local source = f:read("*a")
f:close()
local function check(value, reason) assert(value, reason) end
local function make()
  local e = { Addon = {}, peers = {}, party = {},
    touristPendingInstructions = {}, playerName = "Gaia",
    bootId = "bootGaia", questState = { revision = 1 } }
  setmetatable(e, { __index = _G })
  e.SafeString = function(x) return x == nil and "" or tostring(x) end
  e.Trim = function(x)
    return string.gsub(e.SafeString(x), "^%s*(.-)%s*$", "%1")
  end
  e.NormalizeName = function(x)
    return x and string.lower(x) or nil
  end
  e.QuestKey = function(id, title)
    return id and "i:" .. tostring(id) or "t:" .. tostring(title)
  end
  e.Addon.PreserveInstructionHistory = function() end
  e.NormalizeInstructionStore = function(store) return store end
  e.CopyInstruction = function(record) return record end
  e.CopyInstructionList = function(records) return records end
  e.Addon.CacheTouristPendingInstructions = function() end
  e.Addon.GetTouristInstructions = function() return {} end
  e.Addon.HasCompatiblePeer = function(name)
    return e.peers[e.NormalizeName(name)] ~= nil
  end
  e.delivered = {}
  e.Addon.SendDelta = function(kind, payload, target)
    table.insert(e.delivered, { kind = kind, payload = payload, target = target })
    return true
  end
  e.EncodeInstructionCompletionWire = function()
    return "ack"
  end
  e.notices = {}
  e.Emit = function(kind, sender, n)
    if kind == "GUIDE_JOURNAL_CAUGHT_UP" then
      table.insert(e.notices, { sender = sender, count = n })
    end
  end
  local function loadProduction(first, last, returnName)
    local a = assert(string.find(source, first, 1, true), first)
    local b = assert(string.find(source, last, a + 1, true), last)
    local code = string.sub(source, a, b - 1)
    if returnName then code = code .. "\nreturn " .. returnName end
    local chunk, err = loadstring(code)
    assert(chunk, err)
    setfenv(chunk, e)
    return chunk()
  end
  e.Escape = loadProduction("local function Escape(value)", "local function Unescape(value)", "Escape")
  e.Unescape = loadProduction("local function Unescape(value)", "local function EncodeMap(values)", "Unescape")
  e.loadProduction = loadProduction
  loadProduction("Addon.classHeaderNames = {",
    "local function ReadQuestLogTitle(index)", nil)
  e.HexEncode = loadProduction("local function HexEncode(value)", "local function HexDecode(value)", "HexEncode")
  e.HexDecode = loadProduction("local function HexDecode(value)", "local function SplitPlain(value", "HexDecode")
  e.SplitPlain = loadProduction("local function SplitPlain(value, separator)", "local function Emit(eventName", "SplitPlain")
  e.EncodeMap = loadProduction("local function EncodeMap(values)", "local function DecodeMap(payload)", "EncodeMap")
  e.DecodeMap = loadProduction("local function DecodeMap(payload)", "local function NormalizeName(name)", "DecodeMap")
  e.EncodeQuestRecord = loadProduction("local function EncodeQuestRecord(quest)", "local function EncodeQuestWire", "EncodeQuestRecord")
  e.DecodeQuestRecord = loadProduction("local function DecodeQuestRecord(record)", "local function DecodeQuestWire", "DecodeQuestRecord")
  e.InstructionMatchesAction = loadProduction("local function InstructionMatchesAction(instruction", "-- Phase 4b owns", "InstructionMatchesAction")
  loadProduction("function Addon.NormalizeQuestJournal(journal)", "-- Called ONLY from Phase 2", nil)
  loadProduction("-- Chunk 4: journal uses the existing component", "local function InstructionSnapshot()", nil)
  loadProduction("local function CompleteTouristInstruction(seq)", "function Addon.CreateGuideInstruction", nil)
  return e
end
local tourist = make()
local guide = make()
guide.playerName = "Guide"
guide.bootId = "bootGuide"
tourist.peers.guide = { compatible = true, session = {
  mode = "GUIDE", guideSessionId = "A", guideActionSeq = 2 } }
guide.peers.gaia = { compatible = true, session = {
  mode = "TOURIST", guideName = "Guide", guideSessionId = "A",
  joinBaseline = 0, paused = false } }
local tour = { mode = "TOURIST", guideSessionId = "A", guideName = "Guide",
  joinBaseline = 0, pauseRanges = {}, revision = 0 }
tourist.Addon.db = { session = tour, instructions = {
  touristSessionId = "A", consumed = {} },
  questJournal = { schema = 1, sessions = { A = { participants = {
    gaia = { guide = "guide", nextSeq = 2, events = {
      [1] = { seq = 1, actionType = "TURNIN", questKey = "i:1234",
        questID = 1234, questTitle = "Quest A", attempt = 1,
        attemptOrdinal = 1, questRevision = 1, observedAt = 100,
        complete = true, objectives = {} },
      [2] = { seq = 2, actionType = "ACCEPT", questKey = "i:1235",
        questID = 1235, questTitle = "Quest B", attempt = 2,
        attemptOrdinal = 1, questRevision = 2, observedAt = 101,
        complete = false, objectives = {} }
    }, attempts = {}, active = {}, applied = {} }
  } } }, quarantine = {} } }
guide.Addon.db = { session = { mode = "GUIDE", guideSessionId = "A" },
  instructions = { guideSessionId = "A", guideEligible = {},
    guideRecords = {}, guideAcknowledged = {} },
  questJournal = { schema = 1, sessions = {}, quarantine = {} } }
tourist.touristPendingInstructions = {
  [1] = { seq = 1, actionType = "TURNIN",
    questID = 1234, questTitle = "Quest A", attemptOrdinal = 1 },
  [2] = { seq = 2, actionType = "ACCEPT",
    questID = 1235, questTitle = "Quest B", attemptOrdinal = 1 }
}
-- The production owner consumes both AFTER Gaia already recorded actions.
check(tourist.Addon.ReconcileJournalInstructions() == 2,
  "Gaia-first A TURNIN/B ACCEPT did not auto-complete")
check(tourist.Addon.db.instructions.consumed[1]
  and tourist.Addon.db.instructions.consumed[2],
  "missing persisted completions")
check(tourist.Addon.ReconcileJournalInstructions() == 0,
  "duplicate reconciliation acknowledged twice")
local events = tourist.Addon.db.questJournal.sessions.A.participants.gaia.events
check(events[1].appliedInstruction == 1 and events[2].appliedInstruction == 2,
  "event ownership missing")
check(table.getn(tourist.delivered) == 2, "duplicate ACK sent")
-- Removed/abandoned/unknown completion is not positive proof.
tourist.touristPendingInstructions[3] = {
  seq = 3, actionType = "TURNIN", questID = 999, questTitle = "Abandoned",
  attemptOrdinal = 1 }
events[3] = { seq = 3, actionType = "DISAPPEAR", questID = 999,
  questTitle = "Abandoned", attemptOrdinal = 1 }
check(tourist.Addon.ReconcileJournalInstructions() == 0,
  "disappearance falsely satisfied TURNIN")
-- Repeatable attempts cannot use prior evidence to satisfy a newer attempt.
tourist.touristPendingInstructions[3] = {
  seq = 3, actionType = "TURNIN", questID = 1234,
  questTitle = "Quest A", attemptOrdinal = 2 }
check(tourist.Addon.ReconcileJournalInstructions() == 0,
  "old quest attempt replayed as repeat")
tour.paused = true
tourist.touristPendingInstructions[4] = {
  seq = 4, actionType = "ACCEPT", questID = 1235,
  questTitle = "Quest B", attemptOrdinal = 2 }
events[4] = { seq = 4, actionType = "ACCEPT", questID = 1235,
  questTitle = "Quest B", attemptOrdinal = 2 }
check(tourist.Addon.ReconcileJournalInstructions() == 0,
  "paused Tourist auto-acknowledged")
tour.paused = false
-- Bounded journal summary is independent of the full event payload.
local snapshot = tourist.Addon.JournalSnapshot()
check(string.len(snapshot) < 200, "full sync embedded journal history")
guide.Addon.ApplyJournalFull("Gaia", snapshot)
check(table.getn(guide.delivered) == 1
  and guide.delivered[1].kind == "journal", "Guide did not request missing history")
local req = guide.delivered[1]
guide.delivered = {}
tourist.Addon.ApplyJournalDelta("Guide", req.payload)
check(table.getn(tourist.delivered) == 3, "Tourist did not upload bounded batch")
local batch = tourist.delivered[3]
check(batch.kind == "journal", "Tourist used wrong component")
guide.Addon.ApplyJournalDelta("Gaia", batch.payload)
local uploaded = guide.Addon.db.questJournal.sessions.A.participants.gaia
check(uploaded.events[1].actionType == "TURNIN"
  and uploaded.events[2].actionType == "ACCEPT"
  and uploaded.receivedThrough == 2,
  "Guide failed to durably merge Gaia-first observations")
check(table.getn(guide.notices) == 1 and guide.notices[1].count == 2,
  "Guide catch-up notice not batched once")
guide.Addon.ApplyJournalFull("Gaia", snapshot)
guide.Addon.ApplyJournalDelta("Gaia", batch.payload)
check(table.getn(guide.notices) == 1, "unchanged reconnect spammed Guide")
-- A mismatched source/session cannot update Guide's journal.
guide.peers.gaia.session.guideSessionId = "other"
guide.Addon.ApplyJournalDelta("Gaia", batch.payload)
check(uploaded.receivedThrough == 2, "cross-session mutation occurred")
-- Ensure Pause intervals are carried even when there are no quest events.
tourist.Addon.db.questJournal.sessions.A.participants.gaia.events = {}
tourist.Addon.db.questJournal.sessions.A.participants.gaia.nextSeq = 0
tour.pauseRanges = { { first = 3, last = 5 } }
local pausedSnapshot = tourist.DecodeMap(tourist.Addon.JournalSnapshot())
check(pausedSnapshot.ranges == "3-5", "Pause boundary omitted from summary")
-- Stage-1 journal upgrade is additive and idempotent, not a forced replay.
local migrated = { schema = 1, sessions = { old = { participants = {
  gaia = { attempts = {
    [1] = { questTitle = "Repeat", questKey = "i:77" },
    [2] = { questTitle = "Repeat", questKey = "i:77" }
  }, events = {
    [1] = { attempt = 1, actionType = "ACCEPT" },
    [2] = { attempt = 2, actionType = "ACCEPT" }
  } }
} } }, quarantine = {} }
check(tourist.Addon.NormalizeQuestJournal(migrated) == migrated
  and migrated.schema == 2
  and migrated.sessions.old.participants.gaia.events[1].attemptOrdinal == 1
  and migrated.sessions.old.participants.gaia.events[2].attemptOrdinal == 2,
  "stage-1 attempt ordinal migration failed")
check(tourist.Addon.NormalizeQuestJournal(migrated) == migrated,
  "repeated journal migration must be idempotent")
-- Production pause controls: no session reset and no paused-range instruction replay.
tourist.Addon.GetSession = function() return tour end
tourist.BroadcastSessionDelta = function() end
tourist.ReconcileTouristInstructions = function() end
tourist.loadProduction("function Addon.SetPaused(paused)", "function Addon.SetTouristSession", nil)
tour.pauseRanges = {}
tourist.peers.guide.session.guideActionSeq = 2
check(tourist.Addon.SetPaused(true) and tour.paused
  and tour.guideSessionId == "A" and tour.joinBaseline == 0
  and tour.pauseRanges[1].first == 3,
  "pause replaced same Guide session/baseline")
tourist.peers.guide.session.guideActionSeq = 4
check(tourist.Addon.SetPaused(false) and not tour.paused
  and tour.pauseRanges[1].last == 4
  and tourist.Addon.InstructionInPauseRange(tour, 3)
  and not tourist.Addon.InstructionInPauseRange(tour, 2),
  "resume did not preserve paused cursor interval")
check(tourist.Addon.db.questJournal.sessions.A.participants.gaia.pauseRanges
  == tour.pauseRanges, "pause boundary not retained in SavedVariables")
tourist.peers.guide = nil
check(tourist.Addon.SetPaused(true), "Guide-offline Pause failed")
check(tourist.Addon.SetPaused(false), "Guide-offline Resume failed")
local lastRange = tour.pauseRanges[table.getn(tour.pauseRanges)]
check(lastRange.waiting == true and lastRange.last == nil,
  "offline Pause incorrectly inferred remote cursor")
tourist.Addon.ClosePendingPauseRange("Guide",
  { mode = "GUIDE", guideSessionId = "A", guideActionSeq = 7 })
check(lastRange.last == 7 and not lastRange.waiting,
  "reconnect did not conservatively close paused interval")
-- A Guide may issue instructions for a confirmed paired Tourist who has
-- temporarily disconnected; missing peers are not unknown new members.
guide.loadProduction("function Addon.GuideHasActiveTourist(session)",
  "function Addon.UpdateGuideParticipant", nil)
guide.Addon.db.instructions.guideParticipants = { gaia = 0 }
guide.peers.gaia = nil
guide.party = {}
check(guide.Addon.GuideHasActiveTourist(guide.Addon.db.session),
  "offline known Tourist stopped Guide instruction creation")
guide.Addon.db.instructions.guideParticipants = {}
check(not guide.Addon.GuideHasActiveTourist(guide.Addon.db.session),
  "empty/unknown participant set authorized a Guide instruction")
guide.peers.gaia = { compatible = true, session = {
  mode = "TOURIST", guideName = "Guide", guideSessionId = "A",
  joinBaseline = 0, paused = false } }
-- Guide eligibility and no-empty-set-completion remain independent.
guide.loadProduction("function Addon.CaptureGuideInstructionEligibility(session, seq, requiredClass)",
  "function Addon.RecordGuideInstructionCompletions", nil)
guide.loadProduction("function Addon.RecomputeGuideCompletion()", "function Addon.SetMode", nil)
guide.Addon.GetGuideInstructions = function() return {} end
guide.Addon.db.session.guideActionSeq = 5
guide.Addon.db.instructions.guideParticipants = { gaia = 0, may = 0 }
guide.Addon.db.instructions.guideEligibilityKnown = {}
guide.Addon.db.instructions.guideCompleted = {}
guide.Addon.db.instructions.guideRemoved = {}
guide.peers.gaia.session.guideSessionId = "A"
guide.peers.gaia.session.paused = true
guide.peers.may = { compatible = true, session = { mode = "TOURIST",
  guideName = "Guide", guideSessionId = "A", joinBaseline = 0, paused = false } }
guide.party = { gaia = {}, may = {} }
check(guide.Addon.CaptureGuideInstructionEligibility(guide.Addon.db.session, 5),
  "paused Tourist blocked active Tourist eligibility")
check(not guide.Addon.db.instructions.guideEligible[5].gaia
  and guide.Addon.db.instructions.guideEligible[5].may,
  "paused Tourist included in new Guide instruction")
guide.Addon.db.instructions.guideEligible[6] = { gaia = true, may = true }
guide.Addon.db.instructions.guideEligibilityKnown[6] = true
guide.Addon.db.instructions.guideAcknowledged[6] = { may = true }
guide.Addon.db.instructions.guideRecords[6] = { seq = 6, actionType = "ACCEPT",
  questID = 1235, questTitle = "Quest B" }
guide.Addon.db.questJournal.sessions.A.participants.gaia.pauseRanges = {}
guide.peers.gaia.session.paused = false
guide.Addon.ApplyJournalFull("Gaia", guide.EncodeMap({
  kind = "S", sid = "A", high = 2, paused = "0", ranges = "6-6" }))
check(not guide.Addon.db.instructions.guideEligible[6].gaia,
  "late Pause interval did not remove Gaia eligibility")
check(guide.Addon.db.instructions.guideCompleted[6],
  "Guide completion did not recompute after confirmed Pause exclusion")
guide.Addon.db.instructions.guideEligible[7] = { gaia = true }
guide.Addon.db.instructions.guideEligibilityKnown[7] = true
guide.Addon.db.instructions.guideAcknowledged[7] = {}
guide.Addon.db.instructions.guideRecords[7] = { seq = 7, actionType = "ACCEPT",
  questID = 1235, questTitle = "Quest B" }
guide.Addon.ApplyJournalFull("Gaia", guide.EncodeMap({
  kind = "S", sid = "A", high = 2, paused = "0", ranges = "7-7" }))
check(not guide.Addon.db.instructions.guideCompleted[7],
  "empty Pause eligibility fabricated completion")

-- Guide abandon notices use the existing durable instruction wire and
-- only a verified local AbandonQuest + removal may create them.
local noticeGuide = make()
noticeGuide.L = {}
noticeGuide.Addon.db = {session={mode="GUIDE",guideSessionId="A",paused=false}}
local created = {}
noticeGuide.Addon.CreateGuideInstruction = function(record)
  table.insert(created,record)
  return true
end
local handleGuide = noticeGuide.loadProduction(
  "local function HandleInstructionQuestAction(",
  "function Addon.HandleFlightAction", "HandleInstructionQuestAction")
handleGuide("REMOVE",{questID=77,title="Old Quest"},
  {reason="UNKNOWN",questID=77,questTitle="Old Quest"})
check(table.getn(created)==0,"unknown disappearance created abandon notice")
handleGuide("REMOVE",{questID=77,title="Old Quest"},
  {reason="ABANDON",questID=77,questTitle="Old Quest",journalAttemptOrdinal=3})
check(table.getn(created)==1 and created[1].actionType=="ABANDON"
  and created[1].questID==77 and created[1].questTitle=="Old Quest"
  and created[1].attemptOrdinal==3,"verified Guide abandon did not emit instruction")
noticeGuide.Addon.db.session.paused=true
handleGuide("REMOVE",{questID=77,title="Old Quest"},
  {reason="ABANDON",questID=77,questTitle="Old Quest"})
check(table.getn(created)==1,"paused Guide emitted abandon notice")
noticeGuide.Addon.db.session.paused=false
local normalize = noticeGuide.loadProduction(
  "local function NormalizeInstructionRecord(",
  "-- Durable schema-v4 archive.", "NormalizeInstructionRecord")
local normalized = normalize(created[1],12)
check(normalized and normalized.actionType=="ABANDON"
  and normalized.questTitle=="Old Quest","abandon instruction rejected by persistence")
local wireEncode, wireDecode, wireEncodeList, wireDecodeList =
  noticeGuide.loadProduction("local function EncodeInstructionRecord(",
  "local function EncodeInstructionCompletionWire(",
  "EncodeInstructionRecord, DecodeInstructionRecord, EncodeInstructionWire, DecodeInstructionWire")
local wire = wireEncode(normalized)
check(wireDecode(wire).actionType=="ABANDON"
  and wireDecode(wire).questTitle=="Old Quest","abandon instruction wire did not roundtrip")
local decoded = wireDecodeList(wireEncodeList("D","A",12,{[12]=normalized}),"D")
check(decoded and decoded.instructions[12]
  and decoded.instructions[12].actionType=="ABANDON",
  "Guide abandon notice not transferred through existing instruction protocol")
local displayAbandon = noticeGuide.loadProduction(
  "local function GuideTouristInstructionText(",
  "local function GuideInstructionAllTouristsComplete(",
  "GuideTouristInstructionText")
local textAbandon = displayAbandon(normalized)
check(string.find(textAbandon,"Abandon",1,true)
  and string.find(textAbandon,"Old Quest",1,true),
  "Tourist abandon message lacks instruction label/quest title")
check(string.find(source,'row.questIcon:SetTexture(abandon',1,true),
  "abandon message missing chained Guide/Tourist icon treatment")
local noticeTourist = make()
noticeTourist.Addon.db={session={mode="TOURIST",guideName="Guide",
  guideSessionId="A",joinBaseline=0,paused=false}}
local reconciliation=0
noticeTourist.Addon.ReconcileJournalInstructions=function()
  reconciliation=reconciliation+1
end
local handleTourist=noticeTourist.loadProduction(
  "local function HandleInstructionQuestAction(",
  "function Addon.HandleFlightAction", "HandleInstructionQuestAction")
handleTourist("REMOVE",{questID=77,title="Old Quest"},{reason="UNKNOWN"})
check(reconciliation==0,"Tourist unrelated disappearance fired reconciliation")
handleTourist("REMOVE",{questID=77,title="Old Quest"},{reason="ABANDON"})
check(reconciliation==1,"Tourist verified abandon did not invoke journal reconciliation")

-- ABANDON evidence may satisfy ABANDON only, never TURNIN or vice versa.
local abandonTourist=make()
abandonTourist.peers.guide={compatible=true,session={mode="GUIDE",
  guideSessionId="A",guideActionSeq=3}}
abandonTourist.Addon.db={session={mode="TOURIST",guideSessionId="A",
  guideName="Guide",joinBaseline=0,paused=false},
  instructions={touristSessionId="A",consumed={}},
  questJournal={schema=2,sessions={A={participants={gaia={
    guide="guide",nextSeq=2,events={
      [1]={seq=1,actionType="DISAPPEAR",questID=77,questTitle="Old Quest",
        attemptOrdinal=3},
      [2]={seq=2,actionType="ABANDON",questID=77,questTitle="Old Quest",
        attemptOrdinal=3}},
    attempts={},active={},applied={}}}}},quarantine={}}}
abandonTourist.touristPendingInstructions={
  [3]={seq=3,actionType="ABANDON",questID=77,
    questTitle="Old Quest",attemptOrdinal=3},
  [4]={seq=4,actionType="TURNIN",questID=77,
    questTitle="Old Quest",attemptOrdinal=3}}
check(abandonTourist.Addon.ReconcileJournalInstructions()==1
  and abandonTourist.Addon.db.instructions.consumed[3]
  and not abandonTourist.Addon.db.instructions.consumed[4],
  "verified ABANDON did not exclusively acknowledge abandon row")
check(abandonTourist.Addon.ReconcileJournalInstructions()==0,
  "duplicate abandon event replayed an acknowledgement")

-- Class-specific Guide instructions/abandon notices are relevant only to
-- matching Tourist classes; ordinary quests remain universal.
local classEnv = make()
check(classEnv.Addon.ClassQuestHeaderToken("Paladin")=="PALADIN"
  and classEnv.Addon.ClassQuestHeaderToken("Priest")=="PRIEST"
  and not classEnv.Addon.ClassQuestHeaderToken("Redridge Mountains"),
  "class-header classifier returned wrong subgroup")
check(classEnv.Addon.ClassQuestForPlayer("PALADIN","PALADIN")
  and not classEnv.Addon.ClassQuestForPlayer("PALADIN","PRIEST")
  and classEnv.Addon.ClassQuestForPlayer(nil,"PRIEST"),
  "quest class relevance error")
local headerRows={
  [1]={"Redridge Mountains",true},[2]={"Ordinary Quest",false},
  [3]={"Paladin",true},[4]={"Paladin Quest",false},
  [5]={"Priest",true},[6]={"Priest Quest",false},
  [7]={"Westfall",true},[8]={"Last Normal Quest",false}}
classEnv.ReadQuestLogTitle=function(i)
  local r=headerRows[i]
  if r then return r[1],1,nil,r[2],false,false end
end
classEnv.GetNumQuestLogEntries=function() return 8,4 end
classEnv.BuildQuest=function(i,token)
  return {key="i:"..i,questID=i,title=headerRows[i][1],classToken=token}
end
local scan=classEnv.loadProduction("local function ScanCurrentQuests()",
  "local function FindFallbackMatch(", "ScanCurrentQuests")
local mapped=scan()
check(mapped["i:2"] and not mapped["i:2"].classToken
  and mapped["i:4"].classToken=="PALADIN"
  and mapped["i:6"].classToken=="PRIEST"
  and mapped["i:8"] and not mapped["i:8"].classToken,
  "scanner did not scope class category by header")
local guideClass=make()
guideClass.playerName="Guide"
guideClass.party={gaia={classToken="PRIEST"},may={classToken="PALADIN"}}
guideClass.peers={
 gaia={compatible=true,session={mode="TOURIST",guideName="Guide",
   guideSessionId="A",joinBaseline=0,paused=false}},
 may={compatible=true,session={mode="TOURIST",guideName="Guide",
   guideSessionId="A",joinBaseline=0,paused=false}}
}
guideClass.Addon.db={
 session={mode="GUIDE",guideSessionId="A",guideActionSeq=0},
 instructions={guideSessionId="A",guideParticipants={},guideParticipantClasses={},
  guideRecords={},guideEligible={},guideAcknowledged={},guideEligibilityKnown={},
  guideCompleted={},guideRemoved={}},
 questJournal={sessions={}}
}
guideClass.loadProduction("function Addon.GuideHasMatchingClassTourist(",
  "function Addon.UpdateGuideParticipant", nil)
guideClass.loadProduction("function Addon.CaptureGuideInstructionEligibility(",
  "function Addon.RecordGuideInstructionCompletions",nil)
check(guideClass.Addon.GuideHasMatchingClassTourist(guideClass.Addon.db.session,"PALADIN"),
  "same-class Tourist not eligible")
check(not guideClass.Addon.GuideHasMatchingClassTourist(guideClass.Addon.db.session,"MAGE"),
  "wrong-class Tourist authorizes Mage instruction")
check(guideClass.Addon.CaptureGuideInstructionEligibility(
  guideClass.Addon.db.session,1,"PALADIN"),
  "Paladin target cohort empty")
check(guideClass.Addon.db.instructions.guideEligible[1].may
  and not guideClass.Addon.db.instructions.guideEligible[1].gaia,
  "Paladin instruction targeted Priest")
check(guideClass.Addon.CaptureGuideInstructionEligibility(
  guideClass.Addon.db.session,2,nil)
  and guideClass.Addon.db.instructions.guideEligible[2].may
  and guideClass.Addon.db.instructions.guideEligible[2].gaia,
  "normal quest excluded tourists")
guideClass.party={}
guideClass.peers={}
check(guideClass.Addon.GuideHasMatchingClassTourist(
  guideClass.Addon.db.session,"PALADIN"),
  "known paired offline Paladin lost class")
guideClass.Addon.db.instructions.guideParticipants.gaia=nil
guideClass.Addon.db.instructions.guideParticipantClasses.gaia=nil
check(not guideClass.Addon.GuideHasMatchingClassTourist(
  guideClass.Addon.db.session,"PRIEST"),
  "mismatched offline class authorized")
local normalizeClass=classEnv.loadProduction("local function NormalizeInstructionRecord(",
  "-- Durable schema-v4 archive.", "NormalizeInstructionRecord")
local classRecord=normalizeClass({seq=25,actionType="ABANDON",
  questID=77,questTitle="Paladin Task",classToken="PALADIN"},25)
check(classRecord and classRecord.classToken=="PALADIN",
  "abandon class not persisted")
local iEncode,iDecode,iWireEncode,iWireDecode=classEnv.loadProduction(
  "local function EncodeInstructionRecord(",
  "local function EncodeInstructionCompletionWire(",
  "EncodeInstructionRecord, DecodeInstructionRecord, EncodeInstructionWire, DecodeInstructionWire")
local decoded=iWireDecode(iWireEncode("D","A",25,{[25]=classRecord}),"D")
check(decoded and decoded.instructions[25].classToken=="PALADIN",
  "class quest instruction lost class on wire")
local qEncode=classEnv.loadProduction("local function EncodeQuestRecord(quest)",
  "local function EncodeQuestWire", "EncodeQuestRecord")
local qDecode=classEnv.loadProduction("local function DecodeQuestRecord(record)",
  "local function DecodeQuestWire", "DecodeQuestRecord")
check(qDecode(qEncode({key="i:77",questID=77,title="Paladin Task",
  classToken="PALADIN",objectives={}})).classToken=="PALADIN",
  "quest-state wire lost class")
print("chunk4 retrospective, migration, Pause and journal integration passed")
