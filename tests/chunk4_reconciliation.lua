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
-- Guide eligibility and no-empty-set-completion remain independent.
guide.loadProduction("function Addon.CaptureGuideInstructionEligibility(session, seq)",
  "function Addon.RecordGuideInstructionCompletions", nil)
guide.loadProduction("function Addon.RecomputeGuideCompletion()", "function Addon.SetMode", nil)
guide.Addon.GetGuideInstructions = function() return {} end
guide.Addon.db.session.guideActionSeq = 5
guide.Addon.db.instructions.guideParticipants = { gaia = 0, may = 0 }
guide.Addon.db.instructions.guideEligibilityKnown = {}
guide.Addon.db.instructions.guideCompleted = {}
guide.Addon.db.instructions.guideRemoved = {}
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
check(not guide.Addon.db.instructions.guideEligible[6].gaia
  and guide.Addon.db.instructions.guideCompleted[6],
  "late Pause boundary failed to re-evaluate other acknowledged Tourist")
guide.Addon.db.instructions.guideEligible[7] = { gaia = true }
guide.Addon.db.instructions.guideEligibilityKnown[7] = true
guide.Addon.db.instructions.guideAcknowledged[7] = {}
guide.Addon.db.instructions.guideRecords[7] = { seq = 7, actionType = "ACCEPT",
  questID = 1235, questTitle = "Quest B" }
guide.Addon.ApplyJournalFull("Gaia", guide.EncodeMap({
  kind = "S", sid = "A", high = 2, paused = "0", ranges = "7-7" }))
check(not guide.Addon.db.instructions.guideCompleted[7],
  "empty Pause eligibility fabricated completion")
print("chunk4 retrospective, migration, Pause and journal integration passed")
