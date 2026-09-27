local ADDON_NAME = "pfQuest_Group"
local ADDON_VERSION = GetAddOnMetadata(ADDON_NAME, "Version")

pfQuest_Group = pfQuest_Group or {}
local Addon = pfQuest_Group

local PROTOCOL_PREFIX = "PFQGROUP"
local PROTOCOL_VERSION = 1
local DB_SCHEMA_VERSION = 1
local CHUNK_SIZE = 180
local MAX_CHUNKS = 64
local INCOMING_TIMEOUT = 30

local frame = CreateFrame("Frame")
local initialized = false
local playerName = nil
local bootId = nil
local messageCounter = 0
local party = {}
local peers = {}
local incoming = {}
local components = {}
local listeners = {}
local questState = {
  revision = 0,
  ready = false,
  quests = {}
}
local questScanPending = false
local questScanAt = 0
local questBaselineAt = 0
local questHooksInstalled = false
local pendingAccept = nil
local pendingTurnin = nil
local pendingAbandon = nil

local function SafeString(value)
  if value == nil then
    return ""
  end
  return tostring(value)
end

local function Escape(value)
  local text = SafeString(value)
  return string.gsub(text, "([^%w%-%_%.])", function(char)
    return string.format("%%%02X", string.byte(char))
  end)
end

local function Unescape(value)
  if not value then
    return ""
  end

  return string.gsub(value, "%%(%x%x)", function(hex)
    return string.char(tonumber(hex, 16))
  end)
end

local function EncodeMap(values)
  local keys = {}
  local output = {}
  local key
  local value

  for key, value in pairs(values) do
    if value ~= nil then
      table.insert(keys, SafeString(key))
    end
  end

  table.sort(keys)

  for key, value in ipairs(keys) do
    local mapValue = values[value]
    table.insert(output, Escape(value) .. "=" .. Escape(mapValue))
  end

  return table.concat(output, "&")
end

local function DecodeMap(payload)
  local values = {}
  local startAt = 1
  local payloadLength = string.len(payload or "")

  while startAt <= payloadLength do
    local ampStart = string.find(payload, "&", startAt, true)
    local item

    if ampStart then
      item = string.sub(payload, startAt, ampStart - 1)
      startAt = ampStart + 1
    else
      item = string.sub(payload, startAt)
      startAt = payloadLength + 1
    end

    local equals = string.find(item, "=", 1, true)
    if equals then
      local key = Unescape(string.sub(item, 1, equals - 1))
      local value = Unescape(string.sub(item, equals + 1))
      if key ~= "" then
        values[key] = value
      end
    end
  end

  return values
end

local function NormalizeName(name)
  if not name or name == "" then
    return nil
  end
  return string.lower(name)
end

local function Trim(value)
  local text = SafeString(value)
  text = string.gsub(text, "^%s+", "")
  text = string.gsub(text, "%s+$", "")
  return text
end

local function HexEncode(value)
  local text = SafeString(value)
  local output = {}
  local index

  for index = 1, string.len(text) do
    table.insert(output, string.format("%02X", string.byte(text, index)))
  end

  return table.concat(output, "")
end

local function HexDecode(value)
  local text = SafeString(value)
  local output = {}
  local index

  if math.mod(string.len(text), 2) ~= 0 then
    return ""
  end

  for index = 1, string.len(text), 2 do
    local byteValue = tonumber(string.sub(text, index, index + 1), 16)
    if not byteValue then
      return ""
    end
    table.insert(output, string.char(byteValue))
  end

  return table.concat(output, "")
end

local function SplitPlain(value, separator)
  local output = {}
  local text = SafeString(value)
  local startAt = 1
  local separatorLength = string.len(separator)

  if separator == "" then
    table.insert(output, text)
    return output
  end

  while true do
    local foundAt = string.find(text, separator, startAt, true)
    if not foundAt then
      table.insert(output, string.sub(text, startAt))
      break
    end

    table.insert(output, string.sub(text, startAt, foundAt - 1))
    startAt = foundAt + separatorLength
  end

  return output
end

local function Emit(eventName, argA, argB, argC)
  local handlers = listeners[eventName]
  local index

  if not handlers then
    return
  end

  for index = 1, table.getn(handlers) do
    handlers[index](argA, argB, argC)
  end
end

local function NewSessionId()
  local now = time and time() or 0
  local randomPart = math.random(100000, 999999)
  return SafeString(playerName or "player") .. ":" .. SafeString(now) .. ":" .. SafeString(randomPart)
end

local function NormalizeSession(session)
  if type(session) ~= "table" then
    session = {}
  end

  if session.mode ~= "GUIDE" and session.mode ~= "TOURIST" then
    session.mode = "OFF"
  end

  session.revision = tonumber(session.revision) or 0

  if type(session.hiddenDisparities) ~= "table" then
    session.hiddenDisparities = {}
  end

  if session.mode == "OFF" then
    session.guideName = nil
    session.guideSessionId = nil
    session.joinBaseline = nil
    session.hiddenDisparities = {}
  elseif session.mode == "GUIDE" then
    session.guideName = nil
    session.joinBaseline = nil
    if not session.guideSessionId or session.guideSessionId == "" then
      session.guideSessionId = NewSessionId()
    end
  elseif session.mode == "TOURIST" then
    session.hiddenDisparities = {}
    if session.guideName == "" then
      session.guideName = nil
    end
    if session.guideSessionId == "" then
      session.guideSessionId = nil
    end
    if session.joinBaseline == "" then
      session.joinBaseline = nil
    end
  end

  return session
end

local function InitializeDatabase()
  if type(pfQuest_GroupDB) ~= "table" then
    pfQuest_GroupDB = {}
  end

  pfQuest_GroupDB.schema = DB_SCHEMA_VERSION
  pfQuest_GroupDB.session = NormalizeSession(pfQuest_GroupDB.session)
  Addon.db = pfQuest_GroupDB
end

local function IsPartyMember(name)
  local normalized = NormalizeName(name)
  return normalized and party[normalized] ~= nil
end

local function CurrentDistributionTarget(target)
  if target and IsPartyMember(target) then
    return "WHISPER", target
  end

  if not target and GetNumPartyMembers() > 0 then
    return "PARTY", nil
  end

  return nil, nil
end

local function NextMessageId()
  messageCounter = messageCounter + 1
  if messageCounter > 99999 then
    messageCounter = 1
  end
  return SafeString(messageCounter)
end

local function SendWire(messageType, payload, target)
  local distribution
  local whisperTarget
  local messageId
  local total
  local part

  if not initialized then
    return false
  end

  distribution, whisperTarget = CurrentDistributionTarget(target)
  if not distribution then
    return false
  end

  payload = payload or ""
  messageId = NextMessageId()
  total = math.ceil(string.len(payload) / CHUNK_SIZE)
  if total < 1 then
    total = 1
  end

  if total > MAX_CHUNKS then
    return false
  end

  for part = 1, total do
    local first = ((part - 1) * CHUNK_SIZE) + 1
    local last = part * CHUNK_SIZE
    local chunk = string.sub(payload, first, last)
    local wire = SafeString(PROTOCOL_VERSION) .. "\t" .. messageType .. "\t" .. messageId .. "\t" .. SafeString(part) .. "\t" .. SafeString(total) .. "\t" .. chunk

    if whisperTarget then
      SendAddonMessage(PROTOCOL_PREFIX, wire, distribution, whisperTarget)
    else
      SendAddonMessage(PROTOCOL_PREFIX, wire, distribution)
    end
  end

  return true
end

local function BuildFullState()
  local snapshot = {}
  local componentName
  local component

  for componentName, component in pairs(components) do
    if component.snapshot then
      local payload = component.snapshot()
      if payload ~= nil then
        snapshot[componentName] = payload
      end
    end
  end

  return EncodeMap(snapshot)
end

local function SendFullState(target)
  return SendWire("F", BuildFullState(), target)
end

local function SendHello(target)
  local hello = EncodeMap({
    version = ADDON_VERSION or "unknown",
    boot = bootId or ""
  })
  return SendWire("H", hello, target)
end

local function RequestFullState(target)
  return SendWire("R", "", target)
end

local function ApplyFullState(sender, payload)
  local snapshot = DecodeMap(payload)
  local componentName
  local componentPayload

  for componentName, componentPayload in pairs(snapshot) do
    local component = components[componentName]
    if component and component.applyFull then
      component.applyFull(sender, componentPayload)
    end
  end

  Emit("REMOTE_FULL_STATE", sender)
end

local function ApplyDelta(sender, payload)
  local delta = DecodeMap(payload)
  local componentName = delta.component
  local component = componentName and components[componentName]

  if component and component.applyDelta then
    component.applyDelta(sender, delta.payload or "")
    Emit("REMOTE_DELTA", sender, componentName)
  end
end

local function CleanIncoming()
  local now = GetTime()
  local senderKey
  local senderMessages
  local messageKey
  local state

  for senderKey, senderMessages in pairs(incoming) do
    for messageKey, state in pairs(senderMessages) do
      if not state.updated or now - state.updated > INCOMING_TIMEOUT then
        senderMessages[messageKey] = nil
      end
    end

    local hasMessages = false
    for messageKey, state in pairs(senderMessages) do
      hasMessages = true
      break
    end
    if not hasMessages then
      incoming[senderKey] = nil
    end
  end
end

local function DispatchMessage(sender, protocolVersion, messageType, payload)
  local senderKey = NormalizeName(sender)
  local peer

  if not senderKey or not IsPartyMember(sender) then
    return
  end

  if messageType == "H" then
    local hello = DecodeMap(payload)
    peer = peers[senderKey] or { name = sender }

    if peer.bootId and hello.boot and hello.boot ~= "" and peer.bootId ~= hello.boot then
      peer.session = nil
      peer.questState = nil
      incoming[senderKey] = nil
      Emit("PEER_RESTARTED", sender)
    end

    peer.name = sender
    peer.version = hello.version
    peer.protocol = protocolVersion
    peer.bootId = hello.boot
    peer.compatible = protocolVersion == PROTOCOL_VERSION
    if not peer.compatible then
      peer.session = nil
      peer.questState = nil
    end
    peers[senderKey] = peer
    Emit("PEER_STATUS", sender, peer.compatible)

    if peer.compatible then
      SendFullState(sender)
    end
    return
  end

  if protocolVersion ~= PROTOCOL_VERSION then
    return
  end

  peer = peers[senderKey]
  if not peer then
    peer = {
      name = sender,
      protocol = protocolVersion,
      compatible = true
    }
    peers[senderKey] = peer
    Emit("PEER_STATUS", sender, true)
  end

  if messageType == "R" then
    SendFullState(sender)
  elseif messageType == "F" then
    ApplyFullState(sender, payload)
  elseif messageType == "D" then
    ApplyDelta(sender, payload)
  end
end

local function ReceiveWire(prefix, wire, channel, sender)
  local _, _, protocolText, messageType, messageId, partText, totalText, payload
  local protocolVersion
  local part
  local total
  local senderKey
  local messageKey
  local senderMessages
  local state
  local index

  if prefix ~= PROTOCOL_PREFIX or not wire or not sender then
    return
  end

  if channel ~= "PARTY" and channel ~= "WHISPER" then
    return
  end

  if playerName and NormalizeName(sender) == NormalizeName(playerName) then
    return
  end

  if not IsPartyMember(sender) then
    return
  end

  _, _, protocolText, messageType, messageId, partText, totalText, payload = string.find(wire, "^(%d+)\t([A-Z])\t(%d+)\t(%d+)\t(%d+)\t(.*)$")
  if not protocolText then
    return
  end

  protocolVersion = tonumber(protocolText)
  part = tonumber(partText)
  total = tonumber(totalText)

  if not protocolVersion or not part or not total or part < 1 or total < 1 or part > total or total > MAX_CHUNKS then
    return
  end

  if total == 1 then
    DispatchMessage(sender, protocolVersion, messageType, payload or "")
    return
  end

  CleanIncoming()
  senderKey = NormalizeName(sender)
  messageKey = protocolText .. ":" .. messageType .. ":" .. messageId
  senderMessages = incoming[senderKey]
  if not senderMessages then
    senderMessages = {}
    incoming[senderKey] = senderMessages
  end

  state = senderMessages[messageKey]
  if not state or state.total ~= total then
    state = {
      total = total,
      received = 0,
      chunks = {},
      updated = GetTime()
    }
    senderMessages[messageKey] = state
  end

  if not state.chunks[part] then
    state.chunks[part] = payload or ""
    state.received = state.received + 1
  end
  state.updated = GetTime()

  if state.received == state.total then
    local chunks = {}
    for index = 1, state.total do
      if not state.chunks[index] then
        return
      end
      chunks[index] = state.chunks[index]
    end

    senderMessages[messageKey] = nil
    DispatchMessage(sender, protocolVersion, messageType, table.concat(chunks, ""))
  end
end

local function RefreshParty()
  local nextParty = {}
  local index
  local unit
  local name
  local className
  local classToken
  local normalized
  local peerKey
  local peer

  for index = 1, 4 do
    unit = "party" .. index
    if UnitExists(unit) then
      name = UnitName(unit)
      if name then
        className, classToken = UnitClass(unit)
        normalized = NormalizeName(name)
        nextParty[normalized] = {
          name = name,
          unit = unit,
          className = className,
          classToken = classToken
        }
      end
    end
  end

  party = nextParty
  Addon.party = party

  for peerKey, peer in pairs(peers) do
    if not party[peerKey] then
      peers[peerKey] = nil
      incoming[peerKey] = nil
      Emit("PEER_LEFT", peer.name)
    end
  end

  Emit("PARTY_CHANGED")

  if initialized and GetNumPartyMembers() > 0 then
    SendHello()
    SendFullState()
  end
end

local function ReadQuestLogTitle(index)
  if pfQuestCompat and pfQuestCompat.GetQuestLogTitle then
    return pfQuestCompat.GetQuestLogTitle(index)
  end

  return GetQuestLogTitle(index)
end

local function QuestKey(questID, title)
  if questID then
    return "i:" .. SafeString(questID)
  end

  return "t:" .. SafeString(title)
end

local function ResolveQuestID(qlogIndex, title)
  local questID
  local data
  local key

  if pfQuest and type(pfQuest.questlog) == "table" then
    for key, data in pairs(pfQuest.questlog) do
      if data and data.qlogid == qlogIndex and data.title == title then
        questID = tonumber(key)
        if questID then
          return questID
        end
      end
    end

    questID = nil
    for key, data in pairs(pfQuest.questlog) do
      if data and data.title == title and tonumber(key) then
        if questID and questID ~= tonumber(key) then
          questID = nil
          break
        end
        questID = tonumber(key)
      end
    end
    if questID then
      return questID
    end
  end

  if pfDatabase and type(pfDatabase.GetQuestIDs) == "function" then
    local ok
    local result
    ok, result = pcall(function()
      return pfDatabase:GetQuestIDs(qlogIndex)
    end)

    if ok and type(result) == "table" and result[1] then
      questID = tonumber(result[1])
      if questID then
        return questID
      end
    end
  end

  return nil
end

local function NormalizeObjective(index, text, objectiveType, done)
  local normalized = string.gsub(SafeString(text), "\239\188\154", ":")
  local _, _, label, current, required = string.find(normalized, "(.*):%s*([%d]+)%s*/%s*([%d]+)")
  local isDone = done == true or done == 1

  if current and required then
    return {
      index = index,
      text = Trim(label),
      current = tonumber(current) or 0,
      required = tonumber(required) or 0,
      done = isDone,
      objectiveType = SafeString(objectiveType)
    }
  end

  return {
    index = index,
    text = Trim(normalized),
    current = isDone and 1 or 0,
    required = 1,
    done = isDone,
    objectiveType = SafeString(objectiveType)
  }
end

local function BuildQuest(qlogIndex)
  local title, _, _, header, _, complete = ReadQuestLogTitle(qlogIndex)
  local questID
  local objectiveCount
  local objectives = {}
  local index

  if not title or header then
    return nil
  end

  questID = ResolveQuestID(qlogIndex, title)
  objectiveCount = GetNumQuestLeaderBoards(qlogIndex) or 0

  for index = 1, objectiveCount do
    local text, objectiveType, done = GetQuestLogLeaderBoard(index, qlogIndex)
    table.insert(objectives, NormalizeObjective(index, text, objectiveType, done))
  end

  return {
    key = QuestKey(questID, title),
    questID = questID,
    title = title,
    complete = complete == true or complete == 1,
    qlogIndex = qlogIndex,
    objectives = objectives
  }
end

local function CopyObjective(source)
  return {
    index = source.index,
    text = source.text,
    current = source.current,
    required = source.required,
    done = source.done,
    objectiveType = source.objectiveType
  }
end

local function CopyQuest(source)
  local copy = {
    key = source.key,
    questID = source.questID,
    title = source.title,
    complete = source.complete,
    qlogIndex = source.qlogIndex,
    objectives = {}
  }
  local index

  for index = 1, table.getn(source.objectives or {}) do
    table.insert(copy.objectives, CopyObjective(source.objectives[index]))
  end

  return copy
end

local function CopyQuestState(source)
  local copy = {
    revision = source.revision or 0,
    ready = source.ready and true or false,
    quests = {}
  }
  local key
  local quest

  for key, quest in pairs(source.quests or {}) do
    copy.quests[key] = CopyQuest(quest)
  end

  return copy
end

local function EncodeQuestRecord(quest)
  local objectives = quest.objectives or {}
  local fields = {
    "Q",
    HexEncode(quest.key),
    SafeString(quest.questID or 0),
    quest.complete and "1" or "0",
    HexEncode(quest.title),
    SafeString(table.getn(objectives))
  }
  local index
  local objective

  for index = 1, table.getn(objectives) do
    objective = objectives[index]
    table.insert(fields, SafeString(objective.index or index))
    table.insert(fields, SafeString(objective.current or 0))
    table.insert(fields, SafeString(objective.required or 0))
    table.insert(fields, objective.done and "1" or "0")
    table.insert(fields, HexEncode(objective.objectiveType))
    table.insert(fields, HexEncode(objective.text))
  end

  return table.concat(fields, ".")
end

local function EncodeQuestWire(kind, revision, quests, removals)
  local records = {
    kind .. "." .. SafeString(revision or 0)
  }
  local keys = {}
  local key
  local quest
  local index

  for key, quest in pairs(quests or {}) do
    table.insert(keys, key)
  end
  table.sort(keys)

  for index = 1, table.getn(keys) do
    table.insert(records, EncodeQuestRecord(quests[keys[index]]))
  end

  keys = {}
  for key, quest in pairs(removals or {}) do
    table.insert(keys, key)
  end
  table.sort(keys)

  for index = 1, table.getn(keys) do
    table.insert(records, "R." .. HexEncode(keys[index]))
  end

  return table.concat(records, "_")
end

local function DecodeQuestRecord(record)
  local fields = SplitPlain(record, ".")
  local objectiveCount
  local quest
  local fieldIndex
  local index

  if fields[1] ~= "Q" then
    return nil
  end

  objectiveCount = tonumber(fields[6])
  if not objectiveCount or objectiveCount < 0 then
    return nil
  end

  if table.getn(fields) < 6 + (objectiveCount * 6) then
    return nil
  end

  quest = {
    key = HexDecode(fields[2]),
    questID = tonumber(fields[3]),
    complete = fields[4] == "1",
    title = HexDecode(fields[5]),
    objectives = {}
  }

  if quest.questID == 0 then
    quest.questID = nil
  end

  if quest.key == "" then
    quest.key = QuestKey(quest.questID, quest.title)
  end

  fieldIndex = 7
  for index = 1, objectiveCount do
    table.insert(quest.objectives, {
      index = tonumber(fields[fieldIndex]) or index,
      current = tonumber(fields[fieldIndex + 1]) or 0,
      required = tonumber(fields[fieldIndex + 2]) or 0,
      done = fields[fieldIndex + 3] == "1",
      objectiveType = HexDecode(fields[fieldIndex + 4]),
      text = HexDecode(fields[fieldIndex + 5])
    })
    fieldIndex = fieldIndex + 6
  end

  return quest
end

local function DecodeQuestWire(payload, expectedKind)
  local records = SplitPlain(payload, "_")
  local header = records[1] and SplitPlain(records[1], ".") or nil
  local decoded = {
    revision = 0,
    quests = {},
    removals = {}
  }
  local index
  local quest
  local fields
  local key

  if not header or header[1] ~= expectedKind then
    return nil
  end

  decoded.revision = tonumber(header[2])
  if not decoded.revision then
    return nil
  end

  for index = 2, table.getn(records) do
    if string.sub(records[index], 1, 2) == "Q." then
      quest = DecodeQuestRecord(records[index])
      if not quest or not quest.key or quest.key == "" then
        return nil
      end
      decoded.quests[quest.key] = quest
    elseif string.sub(records[index], 1, 2) == "R." then
      fields = SplitPlain(records[index], ".")
      key = HexDecode(fields[2])
      if key ~= "" then
        decoded.removals[key] = true
      end
    elseif records[index] ~= "" then
      return nil
    end
  end

  return decoded
end

local function QuestSignature(quest)
  return EncodeQuestRecord(quest)
end

local function ScanCurrentQuests()
  local quests = {}
  local _, numQuests = GetNumQuestLogEntries()
  local found = 0
  local qlogIndex
  local quest

  for qlogIndex = 1, 40 do
    quest = BuildQuest(qlogIndex)
    if quest then
      quests[quest.key] = quest
      found = found + 1
      if numQuests and found >= numQuests then
        break
      end
    end
  end

  return quests
end

local function FindFallbackMatch(quests, quest)
  local key
  local candidate

  for key, candidate in pairs(quests or {}) do
    if candidate.title == quest.title and (not candidate.questID or not quest.questID) then
      return key, candidate
    end
  end

  return nil, nil
end

local function ResolveQuestNpc(questID, phase, capturedName)
  local questData
  local units
  local unitID
  local count = 0
  local onlyID = nil
  local localizedName

  if questID and pfDB and pfDB.quests and pfDB.quests.data then
    questData = pfDB.quests.data[questID]
  end

  units = questData and questData[phase] and questData[phase]["U"]
  if units then
    for _, unitID in pairs(units) do
      count = count + 1
      onlyID = tonumber(unitID) or unitID

      if capturedName and pfDB.units and pfDB.units.loc then
        localizedName = pfDB.units.loc[unitID]
        if localizedName == capturedName then
          return tonumber(unitID) or unitID, capturedName
        end
      end
    end
  end

  if count == 1 and onlyID then
    localizedName = pfDB and pfDB.units and pfDB.units.loc and pfDB.units.loc[onlyID]
    return tonumber(onlyID) or onlyID, capturedName or localizedName
  end

  return nil, capturedName
end

local function CurrentQuestNpcName()
  local name = UnitName("npc")
  if not name or name == "" then
    name = UnitName("target")
  end
  return name
end

local function CurrentDialogQuestTitle()
  if type(GetTitleText) == "function" then
    local title = GetTitleText()
    if title and title ~= "" then
      return title
    end
  end

  return nil
end

local function ScheduleQuestScan(delay)
  local nextAt = GetTime() + (delay or 0)

  questScanPending = true
  if questScanAt == 0 or nextAt < questScanAt then
    questScanAt = nextAt
  end
end

local function InstallQuestActionHooks()
  if questHooksInstalled then
    return
  end
  questHooksInstalled = true

  if type(AcceptQuest) == "function" then
    local previousAcceptQuest = AcceptQuest
    AcceptQuest = function()
      pendingAccept = {
        title = CurrentDialogQuestTitle(),
        npcName = CurrentQuestNpcName(),
        time = GetTime()
      }
      previousAcceptQuest()
      ScheduleQuestScan(0.05)
    end
  end

  if type(GetQuestReward) == "function" then
    local previousGetQuestReward = GetQuestReward
    GetQuestReward = function(choice)
      pendingTurnin = {
        title = CurrentDialogQuestTitle(),
        npcName = CurrentQuestNpcName(),
        time = GetTime()
      }
      previousGetQuestReward(choice)
      ScheduleQuestScan(0.05)
    end
  end

  if type(AbandonQuest) == "function" then
    local previousAbandonQuest = AbandonQuest
    AbandonQuest = function()
      local title = type(GetAbandonQuestName) == "function" and GetAbandonQuestName() or nil
      pendingAbandon = {
        title = title,
        time = GetTime()
      }
      previousAbandonQuest()
      ScheduleQuestScan(0.05)
    end
  end
end

local function ClearStalePendingActions()
  local now = GetTime()

  if pendingAccept and now - (pendingAccept.time or 0) > 10 then
    pendingAccept = nil
  end
  if pendingTurnin and now - (pendingTurnin.time or 0) > 10 then
    pendingTurnin = nil
  end
  if pendingAbandon and now - (pendingAbandon.time or 0) > 10 then
    pendingAbandon = nil
  end
end

local function BuildActionContext(quest, phase, pending)
  local context = {
    questID = quest.questID,
    questTitle = quest.title
  }

  if pending and phase then
    context.mobID, context.npcName = ResolveQuestNpc(quest.questID, phase, pending.npcName)
  end

  return context
end

local function QuestSnapshot()
  return EncodeQuestWire("S", questState.revision, questState.quests)
end

local function ApplyRemoteQuestFull(sender, payload)
  local decoded = DecodeQuestWire(payload, "S")
  local senderKey = NormalizeName(sender)
  local peer = senderKey and peers[senderKey]

  if not decoded or not peer then
    return
  end

  if peer.questState and peer.questState.revision and decoded.revision < peer.questState.revision then
    return
  end

  peer.questState = {
    revision = decoded.revision,
    ready = true,
    quests = decoded.quests
  }

  Emit("REMOTE_QUEST_STATE_CHANGED", sender, CopyQuestState(peer.questState))
end

local function ApplyRemoteQuestDelta(sender, payload)
  local decoded = DecodeQuestWire(payload, "D")
  local senderKey = NormalizeName(sender)
  local peer = senderKey and peers[senderKey]
  local key
  local quest

  if not decoded or not peer then
    return
  end

  if not peer.questState then
    if decoded.revision ~= 1 then
      Addon.RequestFullSync(sender)
      return
    end
    peer.questState = {
      revision = 0,
      ready = true,
      quests = {}
    }
  end

  if decoded.revision <= (peer.questState.revision or 0) then
    return
  end

  if decoded.revision ~= (peer.questState.revision or 0) + 1 then
    Addon.RequestFullSync(sender)
    return
  end

  for key, quest in pairs(decoded.quests) do
    peer.questState.quests[key] = quest
  end

  for key, quest in pairs(decoded.removals) do
    peer.questState.quests[key] = nil
  end

  peer.questState.revision = decoded.revision
  peer.questState.ready = true
  Emit("REMOTE_QUEST_STATE_CHANGED", sender, CopyQuestState(peer.questState))
end

local function ScanQuestState()
  local nextQuests
  local changes = {}
  local removals = {}
  local actions = {}
  local migrated = {}
  local key
  local quest
  local previous
  local fallbackKey
  local fallbackQuest
  local action
  local changed = false

  questScanPending = false
  questScanAt = 0
  ClearStalePendingActions()
  nextQuests = ScanCurrentQuests()

  if not questState.ready then
    questState.ready = true
    questState.quests = nextQuests
    questState.revision = questState.revision + 1

    for key, quest in pairs(nextQuests) do
      changes[key] = quest
    end

    Addon.SendDelta("quests", EncodeQuestWire("D", questState.revision, changes))
    Emit("LOCAL_QUEST_STATE_CHANGED", CopyQuestState(questState))
    return
  end

  for key, quest in pairs(nextQuests) do
    previous = questState.quests[key]

    if not previous then
      fallbackKey, fallbackQuest = FindFallbackMatch(questState.quests, quest)
      if fallbackQuest and fallbackKey ~= key then
        migrated[fallbackKey] = true
        removals[fallbackKey] = true
        changes[key] = quest
        changed = true
      else
        local acceptPending = nil

        changes[key] = quest
        changed = true

        if pendingAccept and (not pendingAccept.title or pendingAccept.title == quest.title) then
          acceptPending = pendingAccept
          pendingAccept = nil
        end

        action = {
          actionType = "ACCEPT",
          quest = CopyQuest(quest),
          context = BuildActionContext(quest, acceptPending and "start" or nil, acceptPending)
        }
        table.insert(actions, action)
      end
    elseif QuestSignature(previous) ~= QuestSignature(quest) then
      changes[key] = quest
      changed = true
      table.insert(actions, {
        actionType = "PROGRESS",
        quest = CopyQuest(quest),
        context = {
          questID = quest.questID,
          questTitle = quest.title
        }
      })
    end
  end

  for key, previous in pairs(questState.quests) do
    if not nextQuests[key] and not migrated[key] then
      removals[key] = true
      changed = true

      if pendingTurnin and (not pendingTurnin.title or pendingTurnin.title == previous.title) then
        table.insert(actions, {
          actionType = "TURNIN",
          quest = CopyQuest(previous),
          context = BuildActionContext(previous, "end", pendingTurnin)
        })
        pendingTurnin = nil
      else
        table.insert(actions, {
          actionType = "REMOVE",
          quest = CopyQuest(previous),
          context = {
            questID = previous.questID,
            questTitle = previous.title,
            reason = pendingAbandon and (not pendingAbandon.title or pendingAbandon.title == previous.title) and "ABANDON" or "UNKNOWN"
          }
        })

        if pendingAbandon and (not pendingAbandon.title or pendingAbandon.title == previous.title) then
          pendingAbandon = nil
        end
      end
    end
  end

  questState.quests = nextQuests

  if not changed then
    return
  end

  questState.revision = questState.revision + 1
  Addon.SendDelta("quests", EncodeQuestWire("D", questState.revision, changes, removals))
  Emit("LOCAL_QUEST_STATE_CHANGED", CopyQuestState(questState))

  for key = 1, table.getn(actions) do
    action = actions[key]
    Emit("LOCAL_QUEST_ACTION", action.actionType, action.quest, action.context)
  end
end

local function SessionSnapshot()
  local session = Addon.db and Addon.db.session
  if not session then
    return ""
  end

  return EncodeMap({
    mode = session.mode,
    revision = session.revision,
    guide = session.guideName,
    session = session.guideSessionId,
    baseline = session.joinBaseline
  })
end

local function ApplyRemoteSession(sender, payload)
  local values = DecodeMap(payload)
  local mode = values.mode
  local senderKey = NormalizeName(sender)
  local peer = senderKey and peers[senderKey]
  local revision

  if not peer then
    return
  end

  if mode ~= "GUIDE" and mode ~= "TOURIST" then
    mode = "OFF"
  end

  revision = tonumber(values.revision) or 0
  if peer.session and peer.session.revision and revision < peer.session.revision then
    return
  end

  peer.session = {
    mode = mode,
    revision = revision,
    guideName = values.guide ~= "" and values.guide or nil,
    guideSessionId = values.session ~= "" and values.session or nil,
    joinBaseline = values.baseline ~= "" and values.baseline or nil
  }

  Emit("REMOTE_SESSION_CHANGED", sender, peer.session)
end

local function BroadcastSessionDelta(target)
  return Addon.SendDelta("session", SessionSnapshot(), target)
end

function Addon.RegisterListener(eventName, handler)
  if type(eventName) ~= "string" or type(handler) ~= "function" then
    return false
  end

  if not listeners[eventName] then
    listeners[eventName] = {}
  end

  table.insert(listeners[eventName], handler)
  return true
end

function Addon.RegisterStateComponent(name, snapshotHandler, fullHandler, deltaHandler)
  if type(name) ~= "string" or name == "" then
    return false
  end

  if not string.find(name, "^[%w_%-]+$") then
    return false
  end

  components[name] = {
    snapshot = snapshotHandler,
    applyFull = fullHandler,
    applyDelta = deltaHandler
  }
  return true
end

function Addon.SendDelta(componentName, payload, target)
  if not components[componentName] then
    return false
  end

  return SendWire("D", EncodeMap({
    component = componentName,
    payload = payload or ""
  }), target)
end

function Addon.RequestFullSync(target)
  if target and not IsPartyMember(target) then
    return false
  end
  return RequestFullState(target)
end

function Addon.GetPartyMember(name)
  local normalized = NormalizeName(name)
  return normalized and party[normalized] or nil
end

function Addon.GetPeer(name)
  local normalized = NormalizeName(name)
  return normalized and peers[normalized] or nil
end

function Addon.GetLocalQuestState()
  return CopyQuestState(questState)
end

function Addon.GetRemoteQuestState(name)
  local normalized = NormalizeName(name)
  local peer = normalized and peers[normalized]

  if not peer or not peer.questState then
    return nil
  end

  return CopyQuestState(peer.questState)
end

function Addon.GetSession()
  local source = Addon.db and Addon.db.session
  if not source then
    return nil
  end

  return {
    mode = source.mode,
    revision = source.revision,
    guideName = source.guideName,
    guideSessionId = source.guideSessionId,
    joinBaseline = source.joinBaseline,
    hiddenDisparities = source.hiddenDisparities
  }
end

function Addon.SetMode(mode, guideName)
  local session
  local changed = false

  if not Addon.db then
    return false
  end

  mode = string.upper(SafeString(mode))
  if mode ~= "OFF" and mode ~= "GUIDE" and mode ~= "TOURIST" then
    return false
  end

  if mode == "TOURIST" and (not guideName or guideName == "") then
    return false
  end

  session = Addon.db.session

  if mode == "OFF" then
    if session.mode ~= "OFF" or session.guideName or session.guideSessionId or session.joinBaseline then
      changed = true
    end
    session.mode = "OFF"
    session.guideName = nil
    session.guideSessionId = nil
    session.joinBaseline = nil
    session.hiddenDisparities = {}
  elseif mode == "GUIDE" then
    if session.mode ~= "GUIDE" then
      changed = true
      session.guideSessionId = NewSessionId()
      session.hiddenDisparities = {}
    elseif not session.guideSessionId then
      changed = true
      session.guideSessionId = NewSessionId()
    end
    session.mode = "GUIDE"
    session.guideName = nil
    session.joinBaseline = nil
  else
    if session.mode ~= "TOURIST" or NormalizeName(session.guideName) ~= NormalizeName(guideName) then
      changed = true
      session.guideSessionId = nil
      session.joinBaseline = nil
    end
    session.mode = "TOURIST"
    session.guideName = guideName
    session.hiddenDisparities = {}
  end

  if changed then
    session.revision = session.revision + 1
    BroadcastSessionDelta()
    Emit("SESSION_CHANGED", Addon.GetSession())
  end

  return true
end

function Addon.SetTouristSession(guideName, guideSessionId, joinBaseline)
  local session

  if not Addon.db or not guideName or guideName == "" or not guideSessionId or guideSessionId == "" then
    return false
  end

  session = Addon.db.session
  if session.mode ~= "TOURIST" or NormalizeName(session.guideName) ~= NormalizeName(guideName) then
    return false
  end

  if session.guideSessionId == guideSessionId and session.joinBaseline == joinBaseline then
    return true
  end

  session.guideSessionId = guideSessionId
  session.joinBaseline = joinBaseline
  session.revision = session.revision + 1
  BroadcastSessionDelta()
  Emit("SESSION_CHANGED", Addon.GetSession())
  return true
end

function Addon.ClearTouristSession()
  local session

  if not Addon.db then
    return false
  end

  session = Addon.db.session
  if session.mode ~= "TOURIST" then
    return false
  end

  if not session.guideSessionId and not session.joinBaseline then
    return true
  end

  session.guideSessionId = nil
  session.joinBaseline = nil
  session.revision = session.revision + 1
  BroadcastSessionDelta()
  Emit("SESSION_CHANGED", Addon.GetSession())
  return true
end

Addon.name = ADDON_NAME
Addon.version = ADDON_VERSION
Addon.protocolVersion = PROTOCOL_VERSION
Addon.protocolPrefix = PROTOCOL_PREFIX
Addon.peers = peers
Addon.party = party

Addon.RegisterStateComponent("session", SessionSnapshot, ApplyRemoteSession, ApplyRemoteSession)
Addon.RegisterStateComponent("quests", QuestSnapshot, ApplyRemoteQuestFull, ApplyRemoteQuestDelta)

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PARTY_MEMBERS_CHANGED")
frame:RegisterEvent("QUEST_LOG_UPDATE")
frame:RegisterEvent("QUEST_WATCH_UPDATE")
frame:RegisterEvent("QUEST_FINISHED")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:SetScript("OnEvent", function()
  if event == "ADDON_LOADED" then
    if arg1 ~= ADDON_NAME then
      return
    end

    playerName = UnitName("player")
    bootId = NewSessionId()
    messageCounter = math.floor(GetTime() * 10)
    InitializeDatabase()
    InstallQuestActionHooks()
    initialized = true
    RefreshParty()
    return
  end

  if not initialized then
    return
  end

  if event == "PLAYER_ENTERING_WORLD" or event == "PARTY_MEMBERS_CHANGED" then
    playerName = UnitName("player") or playerName
    RefreshParty()

    if event == "PLAYER_ENTERING_WORLD" then
      questBaselineAt = GetTime() + 1
      ScheduleQuestScan(1)
    end
  elseif event == "QUEST_LOG_UPDATE" or event == "QUEST_WATCH_UPDATE" or event == "QUEST_FINISHED" then
    ScheduleQuestScan(0.05)
  elseif event == "CHAT_MSG_ADDON" then
    ReceiveWire(arg1, arg2, arg3, arg4)
  end
end)

frame:SetScript("OnUpdate", function()
  if not initialized or not questScanPending then
    return
  end

  if GetTime() < questScanAt or (not questState.ready and GetTime() < questBaselineAt) then
    return
  end

  ScanQuestState()
end)
