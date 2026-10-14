-- Production-source integration checks under Lua 5.1 (syntax separately compiled with Lua 5.0.3).
-- Isolate actual persistence, normalizer, pairing, session, full/delta and mode functions.
-- No WoW functions are called; this is not an in-game test.
local f = assert(io.open("pfQuest_Group.lua", "r"))
local source = f:read("*a")
f:close()
local env = {}
setmetatable(env, { __index = _G })
env.Addon = {}
env.peers = {}
env.party = {}
env.playerName = "Tourist"
env.touristPendingInstructions = {}
env.SafeString = function(value) return value == nil and "" or tostring(value) end
env.Trim = function(value)
  return string.gsub(env.SafeString(value), "^%s*(.-)%s*$", "%1")
end
env.NormalizeName = function(value)
  if type(value) ~= "string" or env.Trim(value) == "" then return nil end
  return string.lower(env.Trim(value))
end
env.NewSessionId = function() return "generated" end
env.Emit = function() end
env.CopyInstruction = function(record)
  local copy = {}
  for k, v in pairs(record) do copy[k] = v end
  return copy
end
env.CopyInstructionList = function(value) return value end
env.Addon.CacheTouristPendingInstructions = function() end
env.Addon.GetSession = function() return env.Addon.db and env.Addon.db.session end
env.Addon.UpdateGuideParticipant = function() end
env.BroadcastSessionDelta = function() end
env.requestCount = 0
env.Addon.RequestFullSync = function()
  env.requestCount = env.requestCount + 1
end
-- Identity/map/transport decoding is exercised separately by the addon; use
-- decoded component payloads here to test the production state mutators.
env.DecodeMap = function(payload) return payload end
env.DecodeInstructionWire = function(payload) return payload end
env.DecodeInstructionCompletionWire = function() return nil end
env.ApplyRemoteInstructionCompletionDelta = function() end
local function loadProduction(startText, endText, returnText)
  local a = assert(string.find(source, startText, 1, true), startText)
  local b = assert(string.find(source, endText, a + 1, true), endText)
  local code = string.sub(source, a, b - 1) .. "\nreturn " .. returnText
  local chunk, err = loadstring(code)
  assert(chunk, err)
  setfenv(chunk, env)
  return chunk()
end
local function check(value, message) assert(value, message) end
local normalizeSession = loadProduction("local function NormalizeSession(session)", "local function NormalizeInstructionRecord", "NormalizeSession")
env.NormalizeInstructionRecord = loadProduction("local function NormalizeInstructionRecord(record, fallbackSeq)", "-- Durable schema-v4 archive.", "NormalizeInstructionRecord")
loadProduction("function Addon.PreserveInstructionHistory(db, sourceSession)", "local function NormalizeInstructionStore", "Addon.PreserveInstructionHistory")
env.NormalizeInstructionStore = loadProduction("local function NormalizeInstructionStore(store, session)", "local function NormalizeUIState", "NormalizeInstructionStore")
env.ReconcileTouristInstructions = loadProduction("local function ReconcileTouristInstructions(sender)", "local function FilterRemoteInstructionCompletions", "ReconcileTouristInstructions")
env.ReconcileTouristPairing = loadProduction("local function ReconcileTouristPairing(sender)", "local function ApplyRemoteSession", "ReconcileTouristPairing")
env.ApplyRemoteSession = loadProduction("local function ApplyRemoteSession(sender, payload, checkInstructionSync)", "local function ApplyRemoteSessionFull", "ApplyRemoteSession")
env.ApplyRemoteInstructionFull = loadProduction("local function ApplyRemoteInstructionFull(sender, payload)", "local function ApplyRemoteInstructionDelta", "ApplyRemoteInstructionFull")
env.ApplyRemoteInstructionDelta = loadProduction("local function ApplyRemoteInstructionDelta(sender, payload)", "local function SessionSnapshot", "ApplyRemoteInstructionDelta")
env.Addon.SetMode = loadProduction("function Addon.SetMode(mode, guideName)", "function Addon.SetTouristSession", "Addon.SetMode")
env.Addon.SetTouristSession = loadProduction("function Addon.SetTouristSession(guideName, guideSessionId, joinBaseline)", "function Addon.ClearTouristSession", "Addon.SetTouristSession")
env.Addon.ClearTouristSession = loadProduction("function Addon.ClearTouristSession()", "local function CompleteTouristInstruction", "Addon.ClearTouristSession")
local function quest(seq)
  return { seq = seq, actionType = "ACCEPT", questID = 100 + seq,
    questTitle = "Quest " .. tostring(seq), npcName = "Quest NPC" }
end
local guide = { schema = 3,
  session = { mode = "GUIDE", guideSessionId = "A", guideActionSeq = 0 },
  instructions = { guideSessionId = "A", guideRecords = {
    [1] = quest(1), [32] = quest(32) },
    guideEligible = { [1] = { alice = true, bob = true } },
    guideAcknowledged = { [1] = { alice = true } },
    guideEligibilityKnown = { [1] = true },
    guideCompleted = {}, guideRemoved = { [32] = true },
    guideParticipants = { alice = 0, bob = 0 } } }
env.Addon.PreserveInstructionHistory(guide, guide.session)
guide.session = normalizeSession(guide.session)
guide.instructions = env.NormalizeInstructionStore(guide.instructions, guide.session)
check(guide.session.guideActionSeq == 32, "production cursor recovery")
check(guide.instructions.guideRecords[32] and guide.instructions.guideRemoved[32], "Guide Remove lost during production normalization")
check(guide.instructions.guideAcknowledged[1].alice, "production ack lost")
check(not guide.instructions.guideCompleted[1], "production fabricated completion")
check(guide.history.quarantine.original.session.guideActionSeq == 0, "raw schema-3 cursor overwritten")
env.Addon.PreserveInstructionHistory(guide, guide.session)
check(guide.history.guideSessions.A.records[32].status.removed, "repeated migration lost removal")

local mismatched = { schema = 3,
  session = { mode = "GUIDE", guideSessionId = "B", guideActionSeq = 0 },
  instructions = { guideSessionId = "A", guideRecords = { [32] = quest(32) } } }
env.Addon.PreserveInstructionHistory(mismatched, mismatched.session)
mismatched.session = normalizeSession(mismatched.session)
mismatched.instructions = env.NormalizeInstructionStore(mismatched.instructions, mismatched.session)
check(mismatched.session.guideActionSeq == 0, "cross-session cursor repair")
check(not next(mismatched.instructions.guideRecords), "mismatch replayed live records")
check(mismatched.history.guideSessions.A.records[32], "mismatch archive lost")
local damaged = { schema = 3, session = { mode = "GUIDE", guideSessionId = "A", guideActionSeq = 1 },
  instructions = { guideSessionId = "A", guideRecords = { [1] = quest(1),
    [2] = { actionType = "INVALID", seq = 2 } } } }
env.Addon.PreserveInstructionHistory(damaged, damaged.session)
check(damaged.history.guideSessions.A.anomalies["2"], "production validator did not quarantine malformed record")
check(not damaged.history.guideSessions.A.records[2], "invalid record entered history")

local tourist = { schema = 3, session = { mode = "TOURIST", guideName = "Guide",
  guideSessionId = "A", joinBaseline = 8, revision = 0 },
  instructions = { touristSessionId = "A", consumed = { [9] = true } } }
env.Addon.PreserveInstructionHistory(tourist, tourist.session)
tourist.session = normalizeSession(tourist.session)
tourist.instructions = env.NormalizeInstructionStore(tourist.instructions, tourist.session)
env.Addon.db = tourist
env.peers.guide = { compatible = true,
  session = { mode = "GUIDE", guideSessionId = "A", guideActionSeq = 12, revision = 1 },
  instructions = { sessionId = "A", cursor = 12, instructions = {
    [9] = quest(9), [10] = quest(10), [11] = quest(11) } } }
check(env.ReconcileTouristInstructions("Guide"), "initial live production reconcile")
check(not env.touristPendingInstructions[9], "Done replayed into pending")
check(env.touristPendingInstructions[10], "new live instruction missing")

-- A transient OFF is not a remote kick/leave or an instruction session reset.
env.ApplyRemoteSession("Guide", { mode = "OFF", revision = "2" }, true)
check(tourist.session.guideSessionId == "A" and tourist.session.joinBaseline == 8, "OFF erased pairing or frozen baseline")
check(tourist.instructions.consumed[9], "OFF lost Done")
check(not env.peers.guide.instructions, "remote OFF failed to invalidate volatile remote cache")
local pendingBefore = env.touristPendingInstructions
check(not env.ReconcileTouristInstructions("Guide"), "OFF permitted archived/stale instruction reconciliation")
check(env.touristPendingInstructions == pendingBefore, "transient OFF overwrote local live pending")
env.ApplyRemoteInstructionFull("Guide", { sessionId = "A", cursor = 12, instructions = { [10] = quest(10) } })
check(not env.peers.guide.instructions, "delayed S applied during OFF")

env.ApplyRemoteSession("Guide", { mode = "GUIDE", session = "A",
  revision = "3", action = "13" }, true)
check(tourist.session.joinBaseline == 8 and tourist.instructions.consumed[9], "same-session reconnect re-baselined")
check(env.requestCount > 0, "reconnect did not request missing authoritative S")
env.ApplyRemoteInstructionFull("Guide", { sessionId = "A", cursor = 12,
  instructions = { [9] = quest(9), [10] = quest(10), [12] = quest(12) } })
check(env.touristPendingInstructions[10] and env.touristPendingInstructions[12], "same-session full missing pending records")
check(not env.touristPendingInstructions[9], "same-session full replayed Done")
env.ApplyRemoteInstructionFull("Guide", { sessionId = "A", cursor = 10,
  instructions = { [9] = quest(9) } })
check(env.peers.guide.instructions.cursor == 12, "stale full regressed cursor")
env.ApplyRemoteInstructionDelta("Guide", { sessionId = "A", cursor = 13,
  instructions = { [13] = quest(13) } })
check(env.touristPendingInstructions[13], "sequential D missing")
local requests = env.requestCount
env.ApplyRemoteInstructionDelta("Guide", { sessionId = "A", cursor = 15,
  instructions = { [15] = quest(15) } })
check(env.requestCount == requests + 1, "gap D did not request resync")
check(not env.touristPendingInstructions[15], "gap D replayed")

-- Restore only a frozen baseline whose same-session live identity is still known.
tourist.session.joinBaseline = nil
check(env.Addon.SetTouristSession("Guide", "A", 13), "same-session repair refused")
check(tourist.session.joinBaseline == 8, "same-session lost frozen archive baseline")
check(tourist.instructions.consumed[9], "baseline-only repair lost live Done")
check(not env.touristPendingInstructions[9], "baseline repair replayed Done")

-- A genuinely different session never draws previous archive data into the live queue.
env.ApplyRemoteSession("Guide", { mode = "GUIDE", session = "B",
  revision = "4", action = "40" }, true)
check(tourist.session.guideSessionId == "B" and tourist.session.joinBaseline == 40, "new-session baseline wrong")
check(not tourist.instructions.consumed[9], "new session inherited previous Done")
check(tourist.history.touristSessions.guide.A.consumed[9], "old session archived Done lost")
check(not next(env.touristPendingInstructions), "new session replayed archived pending")
check(env.Addon.SetMode("OFF"), "explicit OFF refused")
check(tourist.session.mode == "OFF", "explicit OFF did not close local projection")
check(tourist.history.touristSessions.guide.A.joinBaseline == 8, "explicit OFF deleted history")
print("production normalization/reconnect regressions passed")
