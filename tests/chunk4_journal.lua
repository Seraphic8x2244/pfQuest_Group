-- Chunk 4 stage 1: execute the exact production journal functions on Lua 5.0.3.
local f = assert(io.open("pfQuest_Group.lua", "r"))
local source = f:read("*a")
f:close()
local a = assert(string.find(source, "function Addon.NormalizeQuestJournal(journal)", 1, true))
local b = assert(string.find(source, "local function InitializeDatabase()", a + 1, true))
local env = {}
setmetatable(env, { __index = _G })
env.Addon = {}
env.playerName = "Gaia"
env.bootId = "bootA"
env.questState = { revision = 1 }
env.SafeString = function(v) return v == nil and "" or tostring(v) end
env.NormalizeName = function(v) return v and string.lower(v) or nil end
env.QuestKey = function(id, title)
  return id and ("i:" .. tostring(id)) or ("t:" .. tostring(title or ""))
end
local chunk = assert(loadstring(string.sub(source, a, b - 1)))
setfenv(chunk, env)
chunk()
local function check(ok, why) assert(ok, why) end
local accept = { questID = 1234, title = "A", complete = false, objectives = {} }
local questB = { questID = 1235, title = "B", complete = false, objectives = {} }
local session = { mode = "TOURIST", guideSessionId = "guide:session1",
  guideName = "Guide", joinBaseline = 0 }
env.Addon.db = { session = session }
check(env.Addon.RecordQuestJournalAction("ACCEPT", accept, {}), "accept not captured")
env.questState.revision = 2
check(not env.Addon.RecordQuestJournalAction("TURNIN", accept, {}),
  "unverified hand-in captured")
check(env.Addon.RecordQuestJournalAction("TURNIN", accept, { turninConfirmed = true }),
  "confirmed hand-in missing")
env.questState.revision = 3
check(env.Addon.RecordQuestJournalAction("ACCEPT", questB, {}),
  "followup accept missing")
local j = env.Addon.db.questJournal
local p = j.sessions["guide:session1"].participants.gaia
check(p.nextSeq == 3 and p.events[2].actionType == "TURNIN"
  and p.events[3].questID == 1235, "Gaia-first ordering lost")
check(p.events[1].attempt == p.events[2].attempt, "turn-in attempt drift")
check(not env.Addon.RecordQuestJournalAction("ACCEPT", questB, {}),
  "duplicate scan evidence was recorded")
check(p.nextSeq == 3, "duplicate event advanced cursor")
-- Simulate a stale cursor after reload: append must not overwrite old events.
p.nextSeq = 0
p.nextAttempt = 0
local stored = env.Addon.NormalizeQuestJournal(j)
check(stored == j and stored.sessions["guide:session1"].participants.gaia.events[2],
  "repeated migration discarded evidence")
env.bootId = "bootB"
env.questState.revision = 1
check(env.Addon.RecordQuestJournalAction("REMOVE", questB, { reason = "UNKNOWN" }),
  "unknown disappearance missing")
check(p.events[4].actionType == "DISAPPEAR"
  and p.events[3].actionType == "ACCEPT", "absence overwrote older evidence")
env.questState.revision = 2
check(env.Addon.RecordQuestJournalAction("ACCEPT", questB, {}),
  "reaccept missing")
check(p.events[5].attempt ~= p.events[3].attempt, "repeat attempt reused")
env.questState.revision = 3
check(env.Addon.RecordQuestJournalAction("PROGRESS",
  { questID = 1235, title = "B", complete = false,
    objectives = { { index = 1, text = "Ore", objectiveType = "item",
      current = 1, required = 2, done = false } } }, {}),
  "progress missing")
check(p.events[6].objectives[1].current == 1 and p.events[6].attempt == p.events[5].attempt,
  "objective evidence/attempt missing")
env.questState.revision = 4
check(env.Addon.RecordQuestJournalAction("COMPLETE",
  { questID = 1235, title = "B", complete = true, objectives = {} }, {}),
  "quest completion missing")
check(p.events[7].actionType == "COMPLETE", "completion not distinct")
env.questState.revision = 5
check(env.Addon.RecordQuestJournalAction("REMOVE", questB, { reason = "ABANDON" }),
  "abandon missing")
check(p.events[8].actionType == "ABANDON", "abandon confused with turn-in")
session.mode = "OFF"
env.questState.revision = 6
check(not env.Addon.RecordQuestJournalAction("ACCEPT", accept, {}), "OFF leaked events")
session.mode = "TOURIST"
session.guideSessionId = "guide:session2"
env.questState.revision = 7
check(env.Addon.RecordQuestJournalAction("ACCEPT", accept, {}), "new session no record")
check(j.sessions["guide:session2"].participants.gaia.nextSeq == 1
  and p.nextSeq == 8, "new session mixed prior events")
session.guideSessionId = nil
env.questState.revision = 8
check(not env.Addon.RecordQuestJournalAction("ACCEPT", accept, {}),
  "unbound Tourist recorded sessionless action")
check(string.find(source, "becameComplete = quest.complete and not previous.complete", 1, true),
  "production scanner must mark only actual completion transitions")
check(string.find(source, "context and context.becameComplete then", 1, true),
  "completion listener must reject unrelated later progress")
print("chunk4 production journal capture fixtures passed")
