-- Run from repository root with Lua 5.0: lua tests/schema_v4_fixtures.lua
-- Pure persistence fixtures: no WoW client, wire protocol or UI assertions.
local file = assert(io.open("pfQuest_Group.lua", "r"))
local source = file:read("*a")
file:close()
local first = assert(string.find(source, "function Addon.PreserveInstructionHistory", 1, true))
local last = assert(string.find(source, "local function NormalizeInstructionStore", first, true))
local extracted = string.sub(source, first, last - 1)
local Addon = {}
local function NormalizeName(name)
  if type(name) ~= "string" or name == "" then return nil end
  return string.lower(name)
end
local function NormalizeInstructionRecord(record, key)
  if type(record) ~= "table" then return nil end
  if record.actionType ~= "ACCEPT" and record.actionType ~= "TURNIN"
    and record.actionType ~= "GOSSIP" and record.actionType ~= "FLIGHT" then return nil end
  local seq = tonumber(record.seq) or tonumber(key)
  if not seq or seq < 1 then return nil end
  return { seq = math.floor(seq), actionType = record.actionType }
end
-- Lua 5.0 loadstring captures globals, so compile fixture in an explicit env.
local chunk = assert(loadstring(extracted))
setfenv(chunk, { Addon = Addon, type = type, pairs = pairs, next = next,
  tonumber = tonumber, tostring = tostring, math = math, string = string,
  NormalizeName = NormalizeName, NormalizeInstructionRecord = NormalizeInstructionRecord })
chunk()
local function check(value, message)
  assert(value, message)
end
local function guide()
  return { schema = 3,
    session = { mode = "GUIDE", guideSessionId = "A", guideActionSeq = 0 },
    instructions = { guideSessionId = "A", guideRecords = {
      [1] = { seq = 1, actionType = "ACCEPT" },
      [32] = { seq = 32, actionType = "TURNIN" } },
      guideEligible = { [1] = { alice = true, bob = true } },
      guideAcknowledged = { [1] = { alice = true } },
      guideEligibilityKnown = { [1] = true },
      guideCompleted = {}, guideRemoved = { [32] = true },
      guideParticipants = { alice = 0, bob = 0 } } }
end
local db = guide()
Addon.PreserveInstructionHistory(db, db.session)
check(db.session.guideActionSeq == 32, "verified cursor repair")
check(db.history.guideSessions.A.records[1].acknowledged.alice, "acknowledgement lost")
check(not db.history.guideSessions.A.records[1].status.completed, "invented completion")
check(db.history.guideSessions.A.records[32].status.removed, "remove flag lost")
check(db.history.quarantine.original.session.guideActionSeq == 0, "raw cursor overwritten")
check(db.history.migration.completed, "migration did not finish")
db.schema = 4
Addon.PreserveInstructionHistory(db, db.session)
check(db.history.guideSessions.A.records[32] ~= nil, "non-idempotent migration")

local mismatch = guide()
mismatch.session.guideSessionId = "B"
Addon.PreserveInstructionHistory(mismatch, mismatch.session)
check(mismatch.history.guideSessions.A.records[32] ~= nil, "orphan dropped")
check(mismatch.history.guideSessions.B == nil, "orphan assigned to new session")
check(mismatch.session.guideActionSeq == 0, "mismatch advanced new cursor")
check(mismatch.history.quarantine.guideMismatch ~= nil, "missing mismatch evidence")

local corrupt = guide()
corrupt.instructions.guideRecords["invalid"] = { actionType = "UNRECOGNIZED" }
corrupt.instructions.guideRecords[7] = { seq = 7, actionType = "UNRECOGNIZED" }
Addon.PreserveInstructionHistory(corrupt, corrupt.session)
check(corrupt.history.guideSessions.A.anomalies.invalid ~= nil, "bad key dropped")
check(corrupt.history.guideSessions.A.anomalies["7"] ~= nil, "bad action dropped")

local transitioned = guide()
Addon.PreserveInstructionHistory(transitioned, transitioned.session)
transitioned.session = { mode = "OFF" }
transitioned.instructions = {}
Addon.PreserveInstructionHistory(transitioned, transitioned.session)
check(transitioned.history.guideSessions.A.records[32] ~= nil, "OFF erased archive")
check(transitioned.history.guideSessions.A.state == "active"
  or transitioned.history.guideSessions.A.state == "archived", "invalid status")
-- Archived records are in db.history only, never reintroduced into the live store.
check(transitioned.instructions.guideRecords == nil, "archived replay")

local tourist = { schema = 3,
  session = { mode = "TOURIST", guideName = "Guide", guideSessionId = "A",
    joinBaseline = 8 },
  instructions = { touristSessionId = "A", consumed = { [9] = true } } }
Addon.PreserveInstructionHistory(tourist, tourist.session)
tourist.instructions = {}
tourist.session = { mode = "OFF" }
Addon.PreserveInstructionHistory(tourist, tourist.session)
check(tourist.history.touristSessions.guide.A.consumed[9], "Tourist Done lost")
check(tourist.history.touristSessions.guide.A.joinBaseline == 8, "baseline lost")
check(tourist.history.quarantine.original.instructions.consumed[9], "raw Done lost")
print("schema-v4 persistence fixtures passed")
