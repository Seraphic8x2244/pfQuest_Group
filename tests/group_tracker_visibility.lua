-- Production-source tracker visibility regression fixtures for Lua 5.0.3.
-- Covers pfQuest native auto-collapse with an unfinished Tourist objective.
local file = assert(io.open("pfQuest_Group.lua", "r"))
local source = file:read("*a")
file:close()
local startAt = assert(string.find(source, "local function PreserveSharedTrackerObjectives(", 1, true))
local endAt = assert(string.find(source, "local function RelayoutGroupTracker()", startAt, true))
local env = {}
setmetatable(env, { __index = _G })
env.RemoteObjectiveDone = function(objective)
  return objective and (objective.done or (tonumber(objective.current) or 0) >= (tonumber(objective.required) or 1))
end
env.GetRemoteObjective = function(peer, _, index)
  return peer.objectives and peer.objectives[index]
end
env.CopyGroupTrackerFont = function(_, obj, fontSize) obj.fontSize = fontSize end
env.SafeString = function(value) return value == nil and "" or tostring(value) end
local chunk = assert(loadstring(string.sub(source, startAt, endAt - 1) .. "\nreturn PreserveSharedTrackerObjectives"))
setfenv(chunk, env)
local preserve = chunk()
local function assertThat(value, message) assert(value, message) end
local function mockObjective(shown)
  return {
    shown = shown,
    IsShown = function(self) return self.shown end,
    Show = function(self) self.shown = true end,
    Hide = function(self) self.shown = false end,
    SetJustifyH = function(self, value) self.justify = value end,
    SetPoint = function() end,
    SetText = function(self, value) self.text = value end
  }
end
local function buttonWith(objectives)
  return {
    objectives = objectives,
    CreateFontString = function(self)
      self.created = (self.created or 0) + 1
      return mockObjective(false)
    end
  }
end
local function quest(current, required)
  return { objectives = {{ current = current, required = required, text = "Gather relics" }} }
end
local function peer(current, required)
  return { objectives = {{ current = current, required = required }} }
end

-- pfQuest has hidden its finished local objectives.
local native = mockObjective(false)
local b = buttonWith({native})
preserve(b, quest(8, 8), {peer(3, 8)}, 12)
assertThat(native:IsShown(), "finished local quest remained collapsed despite unfinished Tourist")
assertThat(native.pfqGroupForcedVisible, "forced visibility ownership missing")
preserve(b, quest(8, 8), {peer(8, 8)}, 12)
assertThat(not native:IsShown() and not native.pfqGroupForcedVisible, "completed Tourist did not restore native collapse")

-- Quest tracked after completion: pfQuest never created objective fontstrings.
local created = buttonWith(nil)
preserve(created, quest(8, 8), {peer(2, 8)}, 12)
assertThat(created.created == 1 and created.objectives[1]:IsShown(), "missing native row not synthesized")
assertThat(created.objectives[1].text and string.find(created.objectives[1].text, "Gather relics", 1, true), "synthetic objective text missing")
preserve(created, quest(8, 8), {}, 12)
assertThat(not created.objectives[1]:IsShown(), "synthetic objective persisted without peer")

-- Native open state stays under pfQuest's control; local incompletion does not
-- force an otherwise collapsed tracker row.
local nativeExpanded = mockObjective(true)
local bExpanded = buttonWith({nativeExpanded})
preserve(bExpanded, quest(8, 8), {peer(8, 8)}, 12)
assertThat(nativeExpanded:IsShown(), "native-expanded objective was unexpectedly collapsed")
local partial = mockObjective(false)
local bPartial = buttonWith({partial})
preserve(bPartial, quest(4, 8), {peer(3, 8)}, 12)
assertThat(not partial:IsShown(), "local partial progress overrode native collapse")
local noPeer = mockObjective(false)
preserve(buttonWith({noPeer}), quest(8, 8), {{}}, 12)
assertThat(not noPeer:IsShown(), "unknown remote progress treated as incomplete")

-- Multi-objective quests stay expanded if any confirmed peer objective
-- remains incomplete, even when all of our local objectives are complete.
local multi = buttonWith({mockObjective(false), mockObjective(false)})
local q = { objectives = {
  {current = 1, required = 1, text = "First"},
  {current = 5, required = 5, text = "Second"}
} }
preserve(multi, q, {{objectives = {{current = 1, required = 1}, {current = 2, required = 5}}}}, 12)
assertThat(multi.objectives[1]:IsShown() and multi.objectives[2]:IsShown(), "multi-objective peer needs failed to expand tracker")
print("group tracker visibility regressions passed")
