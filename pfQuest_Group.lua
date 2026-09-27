local ADDON_NAME = "pfQuest_Group"
local ADDON_VERSION = GetAddOnMetadata(ADDON_NAME, "Version")

pfQuest_Group = pfQuest_Group or {}
local Addon = pfQuest_Group
local L = pfQuest_Group_L or {}

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
local touristPendingInstructions = {}

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
  local baseline
  local actionSeq

  if type(session) ~= "table" then
    session = {}
  end

  if session.mode ~= "GUIDE" and session.mode ~= "TOURIST" then
    session.mode = "OFF"
  end

  session.revision = tonumber(session.revision) or 0
  if session.revision < 0 then
    session.revision = 0
  else
    session.revision = math.floor(session.revision)
  end

  if type(session.hiddenDisparities) ~= "table" then
    session.hiddenDisparities = {}
  end

  baseline = tonumber(session.joinBaseline)
  if baseline and baseline >= 0 then
    baseline = math.floor(baseline)
  else
    baseline = nil
  end

  actionSeq = tonumber(session.guideActionSeq)
  if actionSeq and actionSeq >= 0 then
    actionSeq = math.floor(actionSeq)
  else
    actionSeq = 0
  end

  if session.mode == "OFF" then
    session.guideName = nil
    session.guideSessionId = nil
    session.joinBaseline = nil
    session.guideActionSeq = nil
    session.hiddenDisparities = {}
  elseif session.mode == "GUIDE" then
    session.guideName = nil
    session.joinBaseline = nil
    session.guideActionSeq = actionSeq
    if type(session.guideSessionId) ~= "string" or session.guideSessionId == "" then
      session.guideSessionId = NewSessionId()
      session.guideActionSeq = 0
    end
  elseif session.mode == "TOURIST" then
    session.guideActionSeq = nil
    session.hiddenDisparities = {}

    if type(session.guideName) == "string" then
      session.guideName = Trim(session.guideName)
    else
      session.guideName = nil
    end

    if not session.guideName or session.guideName == "" then
      session.mode = "OFF"
      session.guideName = nil
      session.guideSessionId = nil
      session.joinBaseline = nil
    else
      if type(session.guideSessionId) ~= "string" or session.guideSessionId == "" then
        session.guideSessionId = nil
      end
      session.joinBaseline = baseline
      if not session.guideSessionId then
        session.joinBaseline = nil
      end
    end
  end

  return session
end

local function NormalizeInstructionRecord(record, fallbackSeq)
  local seq
  local actionType
  local questID
  local mobID
  local questTitle
  local npcName

  if type(record) ~= "table" then
    return nil
  end

  seq = tonumber(record.seq) or tonumber(fallbackSeq)
  if not seq or seq < 1 then
    return nil
  end
  seq = math.floor(seq)

  actionType = string.upper(SafeString(record.actionType))
  if actionType ~= "ACCEPT" and actionType ~= "TURNIN" then
    return nil
  end

  questID = tonumber(record.questID)
  mobID = tonumber(record.mobID)
  questTitle = SafeString(record.questTitle)
  npcName = SafeString(record.npcName)

  if not questID and questTitle == "" then
    return nil
  end

  return {
    seq = seq,
    actionType = actionType,
    questID = questID,
    questTitle = questTitle,
    mobID = mobID,
    npcName = npcName
  }
end

local function NormalizeInstructionStore(store, session)
  local guideRecords = {}
  local consumed = {}
  local guideCursor = tonumber(session and session.guideActionSeq) or 0
  local baseline = tonumber(session and session.joinBaseline)
  local key
  local record
  local normalized
  local seq

  if type(store) ~= "table" then
    store = {}
  end

  if type(store.guideRecords) == "table" then
    for key, record in pairs(store.guideRecords) do
      normalized = NormalizeInstructionRecord(record, key)
      if normalized and normalized.seq <= guideCursor then
        guideRecords[normalized.seq] = normalized
      end
    end
  end

  if session and session.mode == "GUIDE" and session.guideSessionId then
    if store.guideSessionId ~= session.guideSessionId then
      guideRecords = {}
    end
    store.guideSessionId = session.guideSessionId
    store.guideRecords = guideRecords
  else
    store.guideSessionId = nil
    store.guideRecords = {}
  end

  if type(store.consumed) == "table" then
    for key, record in pairs(store.consumed) do
      seq = tonumber(key)
      if record and seq and seq >= 1 then
        seq = math.floor(seq)
        if not baseline or seq > baseline then
          consumed[seq] = true
        end
      end
    end
  end

  if session and session.mode == "TOURIST" and session.guideSessionId then
    if store.touristSessionId ~= session.guideSessionId then
      consumed = {}
    end
    store.touristSessionId = session.guideSessionId
    store.consumed = consumed
  else
    store.touristSessionId = nil
    store.consumed = {}
  end

  return store
end

local function InitializeDatabase()
  if type(pfQuest_GroupDB) ~= "table" then
    pfQuest_GroupDB = {}
  end

  pfQuest_GroupDB.schema = DB_SCHEMA_VERSION
  pfQuest_GroupDB.session = NormalizeSession(pfQuest_GroupDB.session)
  pfQuest_GroupDB.instructions = NormalizeInstructionStore(pfQuest_GroupDB.instructions, pfQuest_GroupDB.session)
  touristPendingInstructions = {}
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
      peer.instructions = nil
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
      peer.instructions = nil
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


local GROUP_CLASS_ICON_TEXTURE = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"
local GROUP_CLASS_ICON_COORDS = {
  WARRIOR = { 0, 0.25, 0, 0.25 },
  MAGE = { 0.25, 0.49609375, 0, 0.25 },
  ROGUE = { 0.49609375, 0.7421875, 0, 0.25 },
  DRUID = { 0.7421875, 0.98828125, 0, 0.25 },
  HUNTER = { 0, 0.25, 0.25, 0.5 },
  SHAMAN = { 0.25, 0.49609375, 0.25, 0.5 },
  PRIEST = { 0.49609375, 0.7421875, 0.25, 0.5 },
  WARLOCK = { 0.7421875, 0.98828125, 0.25, 0.5 },
  PALADIN = { 0, 0.25, 0.5, 0.75 }
}
local GROUP_CLASS_COLORS = {
  WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
  MAGE = { r = 0.41, g = 0.80, b = 0.94 },
  ROGUE = { r = 1.00, g = 0.96, b = 0.41 },
  DRUID = { r = 1.00, g = 0.49, b = 0.04 },
  HUNTER = { r = 0.67, g = 0.83, b = 0.45 },
  SHAMAN = { r = 0.14, g = 0.35, b = 1.00 },
  PRIEST = { r = 1.00, g = 1.00, b = 1.00 },
  WARLOCK = { r = 0.58, g = 0.51, b = 0.79 },
  PALADIN = { r = 0.96, g = 0.55, b = 0.73 }
}
local groupTrackerInstalled = false
local originalTrackerButtonEvent = nil

local function GroupClassColor(classToken)
  if RAID_CLASS_COLORS and classToken and RAID_CLASS_COLORS[classToken] then
    return RAID_CLASS_COLORS[classToken]
  end

  if classToken and GROUP_CLASS_COLORS[classToken] then
    return GROUP_CLASS_COLORS[classToken]
  end

  return { r = 1, g = 1, b = 1 }
end

local function GroupClassColorHex(classToken)
  local color = GroupClassColor(classToken)
  local red = math.floor((color.r or 1) * 255 + 0.5)
  local green = math.floor((color.g or 1) * 255 + 0.5)
  local blue = math.floor((color.b or 1) * 255 + 0.5)
  return string.format("%02x%02x%02x", red, green, blue)
end

local function SetGroupClassIcon(texture, classToken)
  local coords = classToken and GROUP_CLASS_ICON_COORDS[classToken]

  texture:SetTexture(GROUP_CLASS_ICON_TEXTURE)
  if coords then
    texture:SetTexCoord(unpack(coords))
  else
    texture:SetTexCoord(0, 1, 0, 1)
  end
end

local function GetGroupTrackerFontSize(button)
  local objective
  local _, fontSize

  if button and button.objectives then
    for _, objective in pairs(button.objectives) do
      if objective and objective:IsShown() then
        _, fontSize = objective:GetFont()
        if fontSize then
          return fontSize
        end
      end
    end
  end

  return tonumber(pfQuest_config and pfQuest_config["trackerfontsize"]) or 12
end

local function CopyGroupTrackerFont(source, target, fallbackSize)
  local fontPath
  local fontSize
  local fontFlags

  if source and source.GetFont then
    fontPath, fontSize, fontFlags = source:GetFont()
  end

  if fontPath and fontSize then
    if fontFlags then
      target:SetFont(fontPath, fontSize, fontFlags)
    else
      target:SetFont(fontPath, fontSize)
    end
  elseif pfUI and pfUI.font_default then
    target:SetFont(pfUI.font_default, fallbackSize or 12)
  end
end

local function FindLocalTrackerQuest(button)
  local numericQuestID
  local key
  local quest

  if not questState.ready or not button then
    return nil
  end

  numericQuestID = tonumber(button.questid)
  if numericQuestID then
    quest = questState.quests[QuestKey(numericQuestID, button.title)]
    if quest then
      return quest
    end
  end

  for key, quest in pairs(questState.quests) do
    if quest.title == button.title then
      return quest
    end
  end

  return nil
end

local function FindRemoteTrackerQuest(remoteState, localQuest)
  local key
  local quest

  if not remoteState or not remoteState.ready or not localQuest then
    return nil
  end

  if localQuest.questID then
    quest = remoteState.quests[QuestKey(localQuest.questID, localQuest.title)]
    if quest then
      return quest
    end
  end

  for key, quest in pairs(remoteState.quests or {}) do
    if quest.title == localQuest.title then
      return quest
    end
  end

  return nil
end

local function GetCompatibleGroupPeers()
  local output = {}
  local index
  local unit
  local name
  local normalized
  local member
  local peer

  for index = 1, 4 do
    unit = "party" .. index
    if UnitExists(unit) then
      name = UnitName(unit)
      normalized = NormalizeName(name)
      member = normalized and party[normalized]
      peer = normalized and peers[normalized]

      if member and peer and peer.compatible then
        table.insert(output, {
          name = peer.name or member.name or name,
          classToken = member.classToken,
          questState = peer.questState
        })
      end
    end
  end

  return output
end

local function GetRemoteObjective(peerInfo, localQuest, objectiveIndex)
  local remoteQuest = FindRemoteTrackerQuest(peerInfo and peerInfo.questState, localQuest)
  if not remoteQuest or not remoteQuest.objectives then
    return nil
  end

  return remoteQuest.objectives[objectiveIndex]
end

local function RemoteObjectiveDone(objective)
  local current
  local required

  if not objective then
    return false
  end

  if objective.done then
    return true
  end

  current = tonumber(objective.current) or 0
  required = tonumber(objective.required) or 1
  return required > 0 and current >= required
end

local function EnsureBinaryGroupStatus(button, objectiveIndex, peerIndex)
  local objectiveStatuses
  local entry

  button.pfqGroupBinary = button.pfqGroupBinary or {}
  objectiveStatuses = button.pfqGroupBinary[objectiveIndex]
  if not objectiveStatuses then
    objectiveStatuses = {}
    button.pfqGroupBinary[objectiveIndex] = objectiveStatuses
  end

  entry = objectiveStatuses[peerIndex]
  if not entry then
    entry = {}
    entry.icon = button:CreateTexture(nil, "ARTWORK")
    entry.mark = button:CreateFontString(nil, "HIGH", "GameFontNormal")
    entry.mark:SetJustifyH("CENTER")
    objectiveStatuses[peerIndex] = entry
  end

  return entry
end

local function EnsureCountGroupRow(button, objectiveIndex, peerIndex)
  local objectiveRows
  local row

  button.pfqGroupRows = button.pfqGroupRows or {}
  objectiveRows = button.pfqGroupRows[objectiveIndex]
  if not objectiveRows then
    objectiveRows = {}
    button.pfqGroupRows[objectiveIndex] = objectiveRows
  end

  row = objectiveRows[peerIndex]
  if not row then
    row = {}
    row.icon = button:CreateTexture(nil, "ARTWORK")
    row.text = button:CreateFontString(nil, "HIGH", "GameFontNormal")
    row.text:SetJustifyH("LEFT")
    objectiveRows[peerIndex] = row
  end

  return row
end

local function HideGroupTrackerRegions(button)
  local objectiveEntries
  local entry

  if button.pfqGroupBinary then
    for _, objectiveEntries in pairs(button.pfqGroupBinary) do
      for _, entry in pairs(objectiveEntries) do
        entry.icon:Hide()
        entry.mark:Hide()
      end
    end
  end

  if button.pfqGroupRows then
    for _, objectiveEntries in pairs(button.pfqGroupRows) do
      for _, entry in pairs(objectiveEntries) do
        entry.icon:Hide()
        entry.text:Hide()
      end
    end
  end

  button.pfqGroupStatusWidth = {}
end

local function CaptureGroupObjectiveBase(objective)
  local red
  local green
  local blue

  objective.pfqGroupBaseText = objective:GetText()
  red, green, blue = objective:GetTextColor()
  objective.pfqGroupBaseColor = {
    r = red,
    g = green,
    b = blue
  }
end

local function RestoreGroupObjectiveBase(objective)
  local color = objective.pfqGroupBaseColor

  if objective.pfqGroupBaseText then
    objective:SetText(objective.pfqGroupBaseText)
  end

  if color then
    objective:SetTextColor(color.r, color.g, color.b)
  end
end

local function RestoreGroupTrackerButton(button)
  local fontSize = GetGroupTrackerFontSize(button)
  local entryHeight = math.ceil(fontSize * 1.6)
  local objective
  local maxVisible = 0
  local index

  HideGroupTrackerRegions(button)

  if button.objectives then
    for index, objective in pairs(button.objectives) do
      RestoreGroupObjectiveBase(objective)
      objective:ClearAllPoints()
      objective:SetPoint("TOPLEFT", 20, -fontSize * index - 6)
      objective:SetPoint("TOPRIGHT", -10, -fontSize * index - 6)
      if objective:IsShown() and index > maxVisible then
        maxVisible = index
      end
    end
  end

  if button.title and not button.empty then
    button:SetHeight(entryHeight + maxVisible * fontSize)
  end
end

local function RelayoutGroupTracker()
  local trackerFrame = pfQuest and pfQuest.tracker
  local panelHeight
  local height
  local width = 100
  local count
  local buttonIndex
  local button
  local objectiveIndex
  local objective
  local rowEntries
  local row
  local candidateWidth

  if not trackerFrame or not trackerFrame.buttons then
    return
  end

  panelHeight = trackerFrame.panel and trackerFrame.panel:GetHeight() or 16
  height = panelHeight
  count = table.getn(trackerFrame.buttons)

  for buttonIndex = 1, count do
    button = trackerFrame.buttons[buttonIndex]
    if button then
      button:ClearAllPoints()
      button:SetPoint("TOPRIGHT", trackerFrame, "TOPRIGHT", 0, -height)
      button:SetPoint("TOPLEFT", trackerFrame, "TOPLEFT", 0, -height)

      if not button.empty then
        height = height + button:GetHeight()

        if button.text and button.text:GetStringWidth() > width then
          width = button.text:GetStringWidth()
        end

        if button.objectives then
          for objectiveIndex, objective in pairs(button.objectives) do
            if objective:IsShown() then
              candidateWidth = objective:GetStringWidth() + (button.pfqGroupStatusWidth and button.pfqGroupStatusWidth[objectiveIndex] or 0)
              if candidateWidth > width then
                width = candidateWidth
              end
            end
          end
        end

        if button.pfqGroupRows then
          for _, rowEntries in pairs(button.pfqGroupRows) do
            for _, row in pairs(rowEntries) do
              if row.text:IsShown() then
                candidateWidth = row.text:GetStringWidth() + 20
                if candidateWidth > width then
                  width = candidateWidth
                end
              end
            end
          end
        end
      end
    end
  end

  trackerFrame:SetHeight(height)
  trackerFrame:SetWidth(math.min(width, 300) + 30)
end

local function ApplyGroupProgressToButton(button, captureBase)
  local trackerFrame = pfQuest and pfQuest.tracker
  local peersInOrder
  local localQuest
  local fontSize
  local entryHeight
  local lineCount = 0
  local objectiveIndex
  local objective
  local localObjective
  local required
  local peerIndex
  local peerInfo
  local remoteObjective
  local entry
  local row
  local iconSize
  local pairWidth
  local statusWidth
  local rightOffset
  local progressText

  if not button then
    return
  end

  HideGroupTrackerRegions(button)

  if not trackerFrame or trackerFrame.mode ~= "QUEST_TRACKING" or button.empty or not button.title then
    RestoreGroupTrackerButton(button)
    return
  end

  localQuest = FindLocalTrackerQuest(button)
  peersInOrder = GetCompatibleGroupPeers()
  if not localQuest or table.getn(peersInOrder) == 0 then
    RestoreGroupTrackerButton(button)
    return
  end

  fontSize = GetGroupTrackerFontSize(button)
  entryHeight = math.ceil(fontSize * 1.6)
  iconSize = math.max(8, fontSize - 2)
  pairWidth = iconSize + 8

  for objectiveIndex = 1, table.getn(localQuest.objectives or {}) do
    objective = button.objectives and button.objectives[objectiveIndex]
    localObjective = localQuest.objectives[objectiveIndex]

    if objective and objective:IsShown() and localObjective then
      if captureBase or not objective.pfqGroupBaseText then
        CaptureGroupObjectiveBase(objective)
      else
        RestoreGroupObjectiveBase(objective)
      end

      lineCount = lineCount + 1
      objective:ClearAllPoints()
      objective:SetPoint("TOPLEFT", 20, -fontSize * lineCount - 6)

      required = tonumber(localObjective.required) or 1
      if required <= 1 then
        statusWidth = table.getn(peersInOrder) * pairWidth
        button.pfqGroupStatusWidth[objectiveIndex] = statusWidth
        objective:SetPoint("TOPRIGHT", -10 - statusWidth - 4, -fontSize * lineCount - 6)

        for peerIndex = 1, table.getn(peersInOrder) do
          peerInfo = peersInOrder[peerIndex]
          remoteObjective = GetRemoteObjective(peerInfo, localQuest, objectiveIndex)
          entry = EnsureBinaryGroupStatus(button, objectiveIndex, peerIndex)

          entry.icon:ClearAllPoints()
          rightOffset = -10 - ((table.getn(peersInOrder) - peerIndex) * pairWidth) - (pairWidth - iconSize)
          entry.icon:SetPoint("TOPRIGHT", button, "TOPRIGHT", rightOffset, -fontSize * lineCount - 6)
          entry.icon:SetWidth(iconSize)
          entry.icon:SetHeight(iconSize)
          SetGroupClassIcon(entry.icon, peerInfo.classToken)
          entry.icon:Show()

          entry.mark:ClearAllPoints()
          entry.mark:SetPoint("LEFT", entry.icon, "RIGHT", 1, 0)
          entry.mark:SetWidth(7)
          entry.mark:SetHeight(iconSize)
          CopyGroupTrackerFont(objective, entry.mark, fontSize)
          entry.mark:SetText(RemoteObjectiveDone(remoteObjective) and "✓" or "✗")
          entry.mark:SetTextColor(1, 1, 1)
          entry.mark:Show()
        end
      else
        objective:SetPoint("TOPRIGHT", -10, -fontSize * lineCount - 6)

        for peerIndex = 1, table.getn(peersInOrder) do
          peerInfo = peersInOrder[peerIndex]
          remoteObjective = GetRemoteObjective(peerInfo, localQuest, objectiveIndex)
          row = EnsureCountGroupRow(button, objectiveIndex, peerIndex)
          lineCount = lineCount + 1

          row.icon:ClearAllPoints()
          row.icon:SetPoint("TOPLEFT", button, "TOPLEFT", 32, -fontSize * lineCount - 6)
          row.icon:SetWidth(iconSize)
          row.icon:SetHeight(iconSize)
          SetGroupClassIcon(row.icon, peerInfo.classToken)
          row.icon:Show()

          row.text:ClearAllPoints()
          row.text:SetPoint("TOPLEFT", button, "TOPLEFT", 44, -fontSize * lineCount - 6)
          row.text:SetPoint("TOPRIGHT", button, "TOPRIGHT", -10, -fontSize * lineCount - 6)
          CopyGroupTrackerFont(objective, row.text, fontSize)

          if remoteObjective then
            progressText = SafeString(tonumber(remoteObjective.current) or 0) .. "/" .. SafeString(tonumber(remoteObjective.required) or required)
          else
            progressText = "--"
          end

          row.text:SetText("|cff" .. GroupClassColorHex(peerInfo.classToken) .. SafeString(peerInfo.name) .. "|r  " .. progressText)
          row.text:SetTextColor(0.85, 0.85, 0.85)
          row.text:Show()
        end
      end
    end
  end

  button:SetHeight(entryHeight + lineCount * fontSize)
end

local function RefreshGroupProgress()
  local trackerFrame = pfQuest and pfQuest.tracker
  local buttonIndex
  local button

  if not groupTrackerInstalled or not trackerFrame or not trackerFrame.buttons then
    return
  end

  for buttonIndex = 1, table.getn(trackerFrame.buttons) do
    button = trackerFrame.buttons[buttonIndex]
    if button then
      ApplyGroupProgressToButton(button, false)
    end
  end

  RelayoutGroupTracker()
end

local function GroupTrackerButtonEvent(self)
  local button = self or this

  if originalTrackerButtonEvent then
    originalTrackerButtonEvent(button)
  end

  ApplyGroupProgressToButton(button, true)
  RelayoutGroupTracker()
end

local function InstallGroupProgressTracker()
  local trackerFrame = pfQuest and pfQuest.tracker
  local buttonIndex
  local button

  if groupTrackerInstalled then
    return true
  end

  if not trackerFrame or type(trackerFrame.ButtonEvent) ~= "function" then
    return false
  end

  originalTrackerButtonEvent = trackerFrame.ButtonEvent
  trackerFrame.ButtonEvent = GroupTrackerButtonEvent
  groupTrackerInstalled = true

  for buttonIndex = 1, table.getn(trackerFrame.buttons or {}) do
    button = trackerFrame.buttons[buttonIndex]
    if button then
      button:SetScript("OnEvent", GroupTrackerButtonEvent)
    end
  end

  RefreshGroupProgress()
  return true
end


local function CopyInstruction(source)
  if not source then
    return nil
  end

  return {
    seq = source.seq,
    actionType = source.actionType,
    questID = source.questID,
    questTitle = source.questTitle,
    mobID = source.mobID,
    npcName = source.npcName
  }
end

local function CopyInstructionList(records)
  local output = {}
  local keys = {}
  local key
  local index

  for key in pairs(records or {}) do
    table.insert(keys, tonumber(key) or key)
  end
  table.sort(keys)

  for index = 1, table.getn(keys) do
    if records[keys[index]] then
      table.insert(output, CopyInstruction(records[keys[index]]))
    end
  end

  return output
end

local function EncodeInstructionRecord(instruction)
  local actionCode = instruction.actionType == "ACCEPT" and "A" or "T"

  return table.concat({
    "I",
    SafeString(instruction.seq or 0),
    actionCode,
    SafeString(instruction.questID or 0),
    SafeString(instruction.mobID or 0),
    HexEncode(instruction.questTitle),
    HexEncode(instruction.npcName)
  }, ".")
end

local function DecodeInstructionRecord(record)
  local fields = SplitPlain(record, ".")
  local seq
  local actionType
  local questID
  local mobID
  local questTitle
  local npcName

  if fields[1] ~= "I" or table.getn(fields) < 7 then
    return nil
  end

  seq = tonumber(fields[2])
  if not seq or seq < 1 then
    return nil
  end
  seq = math.floor(seq)

  if fields[3] == "A" then
    actionType = "ACCEPT"
  elseif fields[3] == "T" then
    actionType = "TURNIN"
  else
    return nil
  end

  questID = tonumber(fields[4])
  if questID == 0 then
    questID = nil
  end

  mobID = tonumber(fields[5])
  if mobID == 0 then
    mobID = nil
  end

  questTitle = HexDecode(fields[6])
  npcName = HexDecode(fields[7])
  if not questID and questTitle == "" then
    return nil
  end

  return {
    seq = seq,
    actionType = actionType,
    questID = questID,
    questTitle = questTitle,
    mobID = mobID,
    npcName = npcName
  }
end

local function EncodeInstructionWire(kind, guideSessionId, cursor, records)
  local output = {
    kind .. "." .. HexEncode(guideSessionId or "") .. "." .. SafeString(cursor or 0)
  }
  local keys = {}
  local key
  local index

  for key in pairs(records or {}) do
    table.insert(keys, tonumber(key) or key)
  end
  table.sort(keys)

  for index = 1, table.getn(keys) do
    if records[keys[index]] then
      table.insert(output, EncodeInstructionRecord(records[keys[index]]))
    end
  end

  return table.concat(output, "_")
end

local function DecodeInstructionWire(payload, expectedKind)
  local records = SplitPlain(payload, "_")
  local header = records[1] and SplitPlain(records[1], ".") or nil
  local decoded = {
    sessionId = nil,
    cursor = 0,
    instructions = {}
  }
  local index
  local instruction

  if not header or header[1] ~= expectedKind or table.getn(header) < 3 then
    return nil
  end

  decoded.sessionId = HexDecode(header[2])
  if decoded.sessionId == "" then
    decoded.sessionId = nil
  end

  decoded.cursor = tonumber(header[3])
  if not decoded.cursor or decoded.cursor < 0 then
    return nil
  end
  decoded.cursor = math.floor(decoded.cursor)

  for index = 2, table.getn(records) do
    if records[index] ~= "" then
      instruction = DecodeInstructionRecord(records[index])
      if not instruction or not decoded.sessionId or instruction.seq > decoded.cursor or decoded.instructions[instruction.seq] then
        return nil
      end
      decoded.instructions[instruction.seq] = instruction
    end
  end

  return decoded
end

local function InstructionSnapshot()
  local session = Addon.db and Addon.db.session
  local store = Addon.db and Addon.db.instructions

  if not session or session.mode ~= "GUIDE" or not session.guideSessionId or not store or store.guideSessionId ~= session.guideSessionId then
    return EncodeInstructionWire("S", nil, 0, {})
  end

  return EncodeInstructionWire("S", session.guideSessionId, tonumber(session.guideActionSeq) or 0, store.guideRecords)
end

local function InstructionMatchesAction(instruction, actionType, quest, context)
  local actionQuestID
  local actionTitle

  if not instruction or instruction.actionType ~= actionType then
    return false
  end

  actionQuestID = tonumber(context and context.questID) or tonumber(quest and quest.questID)
  actionTitle = SafeString((context and context.questTitle) or (quest and quest.title))

  if instruction.questID and actionQuestID then
    return instruction.questID == actionQuestID
  end

  return instruction.questTitle ~= "" and actionTitle ~= "" and instruction.questTitle == actionTitle
end

local function ReconcileTouristInstructions(sender)
  local session = Addon.db and Addon.db.session
  local store = Addon.db and Addon.db.instructions
  local guideKey
  local peer
  local baseline
  local nextPending = {}
  local seq
  local instruction

  if not session or session.mode ~= "TOURIST" or not session.guideName or not session.guideSessionId or session.joinBaseline == nil then
    return false
  end

  if sender and NormalizeName(sender) ~= NormalizeName(session.guideName) then
    return false
  end

  guideKey = NormalizeName(session.guideName)
  peer = guideKey and peers[guideKey]
  if not peer or not peer.compatible or not peer.instructions or peer.instructions.sessionId ~= session.guideSessionId then
    return false
  end

  baseline = tonumber(session.joinBaseline) or 0
  store = NormalizeInstructionStore(store, session)
  Addon.db.instructions = store

  for seq, instruction in pairs(peer.instructions.instructions or {}) do
    seq = tonumber(seq)
    if seq and seq > baseline and not store.consumed[seq] then
      nextPending[seq] = CopyInstruction(instruction)
    end
  end

  touristPendingInstructions = nextPending
  Emit("TOURIST_INSTRUCTIONS_CHANGED", CopyInstructionList(touristPendingInstructions))
  return true
end

local function ApplyRemoteInstructionFull(sender, payload)
  local decoded = DecodeInstructionWire(payload, "S")
  local senderKey = NormalizeName(sender)
  local peer = senderKey and peers[senderKey]

  if not decoded or not peer then
    return
  end

  if not decoded.sessionId then
    peer.instructions = nil
    Emit("REMOTE_INSTRUCTIONS_CHANGED", sender, nil)
    ReconcileTouristInstructions(sender)
    return
  end

  if peer.instructions and peer.instructions.sessionId == decoded.sessionId and decoded.cursor < (peer.instructions.cursor or 0) then
    return
  end

  peer.instructions = {
    sessionId = decoded.sessionId,
    cursor = decoded.cursor,
    instructions = decoded.instructions
  }

  Emit("REMOTE_INSTRUCTIONS_CHANGED", sender, peer.instructions)
  ReconcileTouristInstructions(sender)
end

local function ApplyRemoteInstructionDelta(sender, payload)
  local decoded = DecodeInstructionWire(payload, "D")
  local senderKey = NormalizeName(sender)
  local peer = senderKey and peers[senderKey]
  local currentCursor
  local instruction

  if not decoded or not decoded.sessionId or not peer then
    return
  end

  if not peer.instructions or peer.instructions.sessionId ~= decoded.sessionId then
    if peer.session and peer.session.mode == "GUIDE" and peer.session.guideSessionId == decoded.sessionId and decoded.cursor == 1 then
      peer.instructions = {
        sessionId = decoded.sessionId,
        cursor = 0,
        instructions = {}
      }
    else
      Addon.RequestFullSync(sender)
      return
    end
  end

  currentCursor = tonumber(peer.instructions.cursor) or 0
  if decoded.cursor <= currentCursor then
    return
  end

  if decoded.cursor ~= currentCursor + 1 then
    Addon.RequestFullSync(sender)
    return
  end

  instruction = decoded.instructions[decoded.cursor]
  if not instruction then
    Addon.RequestFullSync(sender)
    return
  end

  peer.instructions.instructions[decoded.cursor] = instruction
  peer.instructions.cursor = decoded.cursor
  Emit("REMOTE_INSTRUCTIONS_CHANGED", sender, peer.instructions)
  ReconcileTouristInstructions(sender)
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
    baseline = session.joinBaseline,
    action = session.guideActionSeq
  })
end

local function BroadcastSessionDelta(target)
  return Addon.SendDelta("session", SessionSnapshot(), target)
end

local function ReconcileTouristPairing(sender)
  local session = Addon.db and Addon.db.session
  local guideKey
  local peer
  local remoteSession
  local baseline

  if not session or session.mode ~= "TOURIST" or not session.guideName then
    return false
  end

  if sender and NormalizeName(sender) ~= NormalizeName(session.guideName) then
    return false
  end

  guideKey = NormalizeName(session.guideName)
  peer = guideKey and peers[guideKey]
  if not peer or not peer.compatible or not peer.session then
    return false
  end

  remoteSession = peer.session
  if remoteSession.mode == "GUIDE" and remoteSession.guideSessionId then
    baseline = tonumber(remoteSession.guideActionSeq) or 0
    if baseline < 0 then
      baseline = 0
    else
      baseline = math.floor(baseline)
    end

    if session.guideSessionId ~= remoteSession.guideSessionId or session.joinBaseline == nil then
      return Addon.SetTouristSession(session.guideName, remoteSession.guideSessionId, baseline)
    end

    return true
  end

  if session.guideSessionId or session.joinBaseline ~= nil then
    return Addon.ClearTouristSession()
  end

  return false
end

local function ApplyRemoteSession(sender, payload)
  local values = DecodeMap(payload)
  local mode = values.mode
  local senderKey = NormalizeName(sender)
  local peer = senderKey and peers[senderKey]
  local revision
  local guideName
  local guideSessionId
  local joinBaseline
  local guideActionSeq

  if not peer then
    return
  end

  if mode ~= "GUIDE" and mode ~= "TOURIST" then
    mode = "OFF"
  end

  revision = tonumber(values.revision) or 0
  if revision < 0 then
    revision = 0
  else
    revision = math.floor(revision)
  end

  if peer.session and peer.session.revision and revision < peer.session.revision then
    return
  end

  guideName = values.guide ~= "" and values.guide or nil
  guideSessionId = values.session ~= "" and values.session or nil
  joinBaseline = tonumber(values.baseline)
  guideActionSeq = tonumber(values.action)

  if joinBaseline and joinBaseline >= 0 then
    joinBaseline = math.floor(joinBaseline)
  else
    joinBaseline = nil
  end

  if guideActionSeq and guideActionSeq >= 0 then
    guideActionSeq = math.floor(guideActionSeq)
  else
    guideActionSeq = 0
  end

  if mode == "OFF" then
    guideName = nil
    guideSessionId = nil
    joinBaseline = nil
    guideActionSeq = nil
    peer.instructions = nil
  elseif mode == "GUIDE" then
    guideName = nil
    joinBaseline = nil
    if peer.instructions and peer.instructions.sessionId ~= guideSessionId then
      peer.instructions = nil
    end
  else
    peer.instructions = nil
    guideActionSeq = nil
    if not guideSessionId then
      joinBaseline = nil
    end
  end

  peer.session = {
    mode = mode,
    revision = revision,
    guideName = guideName,
    guideSessionId = guideSessionId,
    joinBaseline = joinBaseline,
    guideActionSeq = guideActionSeq
  }

  Emit("REMOTE_SESSION_CHANGED", sender, peer.session)
  ReconcileTouristPairing(sender)
  ReconcileTouristInstructions(sender)
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

function Addon.GetGuideInstructions()
  local session = Addon.db and Addon.db.session
  local store = Addon.db and Addon.db.instructions

  if not session or session.mode ~= "GUIDE" or not store or store.guideSessionId ~= session.guideSessionId then
    return {}
  end

  return CopyInstructionList(store.guideRecords)
end

function Addon.GetTouristInstructions()
  local session = Addon.db and Addon.db.session

  if not session or session.mode ~= "TOURIST" or not session.guideSessionId or session.joinBaseline == nil then
    return {}
  end

  return CopyInstructionList(touristPendingInstructions)
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
    guideActionSeq = source.guideActionSeq,
    hiddenDisparities = source.hiddenDisparities
  }
end

function Addon.SetMode(mode, guideName)
  local session
  local changed = false
  local normalizedGuide

  if not Addon.db then
    return false
  end

  mode = string.upper(SafeString(mode))
  if mode ~= "OFF" and mode ~= "GUIDE" and mode ~= "TOURIST" then
    return false
  end

  if mode == "TOURIST" then
    guideName = Trim(guideName)
    normalizedGuide = NormalizeName(guideName)
    if not normalizedGuide or normalizedGuide == NormalizeName(playerName) then
      return false
    end

    if party[normalizedGuide] and party[normalizedGuide].name then
      guideName = party[normalizedGuide].name
    end
  end

  session = Addon.db.session

  if mode == "OFF" then
    if session.mode ~= "OFF" or session.guideName or session.guideSessionId or session.joinBaseline ~= nil or session.guideActionSeq ~= nil then
      changed = true
    end
    session.mode = "OFF"
    session.guideName = nil
    session.guideSessionId = nil
    session.joinBaseline = nil
    session.guideActionSeq = nil
    session.hiddenDisparities = {}
  elseif mode == "GUIDE" then
    if session.mode ~= "GUIDE" then
      changed = true
      session.guideSessionId = NewSessionId()
      session.guideActionSeq = 0
      session.hiddenDisparities = {}
    elseif not session.guideSessionId then
      changed = true
      session.guideSessionId = NewSessionId()
      session.guideActionSeq = 0
    elseif session.guideActionSeq == nil then
      changed = true
      session.guideActionSeq = 0
    end
    session.mode = "GUIDE"
    session.guideName = nil
    session.joinBaseline = nil
  else
    if session.mode ~= "TOURIST" or NormalizeName(session.guideName) ~= normalizedGuide then
      changed = true
      session.guideSessionId = nil
      session.joinBaseline = nil
    elseif session.guideName ~= guideName then
      changed = true
    end
    session.mode = "TOURIST"
    session.guideName = guideName
    session.guideActionSeq = nil
    session.hiddenDisparities = {}
  end

  if changed then
    Addon.db.instructions = NormalizeInstructionStore(Addon.db.instructions, session)
    touristPendingInstructions = {}
    session.revision = session.revision + 1
    BroadcastSessionDelta()
    Emit("SESSION_CHANGED", Addon.GetSession())
  end

  if mode == "TOURIST" then
    ReconcileTouristPairing()
    ReconcileTouristInstructions()
  end

  return true
end

function Addon.SetTouristSession(guideName, guideSessionId, joinBaseline)
  local session
  local baseline

  if not Addon.db or not guideName or guideName == "" or not guideSessionId or guideSessionId == "" then
    return false
  end

  baseline = tonumber(joinBaseline)
  if not baseline or baseline < 0 then
    return false
  end
  baseline = math.floor(baseline)

  session = Addon.db.session
  if session.mode ~= "TOURIST" or NormalizeName(session.guideName) ~= NormalizeName(guideName) then
    return false
  end

  if session.guideSessionId == guideSessionId and session.joinBaseline ~= nil then
    return true
  end

  session.guideSessionId = guideSessionId
  session.joinBaseline = baseline
  Addon.db.instructions = NormalizeInstructionStore(Addon.db.instructions, session)
  touristPendingInstructions = {}
  session.revision = session.revision + 1
  BroadcastSessionDelta()
  Emit("SESSION_CHANGED", Addon.GetSession())
  ReconcileTouristInstructions(guideName)
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

  if not session.guideSessionId and session.joinBaseline == nil then
    return true
  end

  session.guideSessionId = nil
  session.joinBaseline = nil
  Addon.db.instructions = NormalizeInstructionStore(Addon.db.instructions, session)
  touristPendingInstructions = {}
  session.revision = session.revision + 1
  BroadcastSessionDelta()
  Emit("SESSION_CHANGED", Addon.GetSession())
  Emit("TOURIST_INSTRUCTIONS_CHANGED", {})
  return true
end

local function HandleInstructionQuestAction(actionType, quest, context)
  local session = Addon.db and Addon.db.session
  local store
  local seq
  local instruction
  local pendingSeq
  local candidateSeq
  local candidate

  if not session or (actionType ~= "ACCEPT" and actionType ~= "TURNIN") then
    return
  end

  if session.mode == "GUIDE" and session.guideSessionId then
    session.guideActionSeq = (tonumber(session.guideActionSeq) or 0) + 1
    seq = session.guideActionSeq
    Addon.db.instructions = NormalizeInstructionStore(Addon.db.instructions, session)
    store = Addon.db.instructions

    instruction = NormalizeInstructionRecord({
      seq = seq,
      actionType = actionType,
      questID = tonumber(context and context.questID) or tonumber(quest and quest.questID),
      questTitle = SafeString((context and context.questTitle) or (quest and quest.title)),
      mobID = tonumber(context and context.mobID),
      npcName = SafeString(context and context.npcName)
    }, seq)

    if not instruction then
      return
    end

    store.guideSessionId = session.guideSessionId
    store.guideRecords[seq] = instruction
    session.revision = session.revision + 1
    BroadcastSessionDelta()
    Addon.SendDelta("instructions", EncodeInstructionWire("D", session.guideSessionId, seq, {
      [seq] = instruction
    }))
    Emit("SESSION_CHANGED", Addon.GetSession())
    Emit("GUIDE_INSTRUCTION_CREATED", CopyInstruction(instruction))
    Emit("GUIDE_INSTRUCTIONS_CHANGED", Addon.GetGuideInstructions())
    return
  end

  if session.mode ~= "TOURIST" or not session.guideSessionId or session.joinBaseline == nil then
    return
  end

  for candidateSeq, candidate in pairs(touristPendingInstructions) do
    candidateSeq = tonumber(candidateSeq)
    if candidateSeq and InstructionMatchesAction(candidate, actionType, quest, context) then
      if not pendingSeq or candidateSeq < pendingSeq then
        pendingSeq = candidateSeq
        instruction = candidate
      end
    end
  end

  if not pendingSeq or not instruction then
    return
  end

  Addon.db.instructions = NormalizeInstructionStore(Addon.db.instructions, session)
  store = Addon.db.instructions
  store.consumed[pendingSeq] = true
  touristPendingInstructions[pendingSeq] = nil
  Emit("TOURIST_INSTRUCTION_COMPLETED", CopyInstruction(instruction))
  Emit("TOURIST_INSTRUCTIONS_CHANGED", Addon.GetTouristInstructions())
end

local function SessionStatusText()
  local session = Addon.GetSession()

  if not session or session.mode == "OFF" then
    return L.STATUS_OFF or "Mode: Off."
  end

  if session.mode == "GUIDE" then
    return L.STATUS_GUIDE or "Mode: Guide."
  end

  if session.guideSessionId and session.joinBaseline ~= nil then
    return string.format(L.STATUS_TOURIST_PAIRED or "Mode: Tourist - following %s (paired).", SafeString(session.guideName))
  end

  return string.format(L.STATUS_TOURIST_WAITING or "Mode: Tourist - following %s (waiting for an active Guide session).", SafeString(session.guideName))
end

local function PrintSessionText(text)
  if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
    DEFAULT_CHAT_FRAME:AddMessage("|cffffd100pfQuest_Group:|r " .. SafeString(text))
  end
end

local function HandleSlashCommand(message)
  local text = Trim(message)
  local command = ""
  local argument = ""
  local splitAt

  if text ~= "" then
    splitAt = string.find(text, "%s")
    if splitAt then
      command = string.lower(string.sub(text, 1, splitAt - 1))
      argument = Trim(string.sub(text, splitAt + 1))
    else
      command = string.lower(text)
    end
  end

  if command == "off" then
    Addon.SetMode("OFF")
    PrintSessionText(SessionStatusText())
  elseif command == "guide" then
    Addon.SetMode("GUIDE")
    PrintSessionText(SessionStatusText())
  elseif command == "tourist" then
    if argument == "" or not Addon.SetMode("TOURIST", argument) then
      PrintSessionText(L.TOURIST_REQUIRES_GUIDE or "Tourist mode requires another player name.")
    else
      PrintSessionText(SessionStatusText())
    end
  elseif command == "status" then
    PrintSessionText(SessionStatusText())
  else
    PrintSessionText(L.COMMAND_HELP or "Usage: /pfqgroup off | guide | tourist <player> | status")
  end
end

Addon.name = ADDON_NAME
Addon.version = ADDON_VERSION
Addon.protocolVersion = PROTOCOL_VERSION
Addon.protocolPrefix = PROTOCOL_PREFIX
Addon.peers = peers
Addon.party = party

Addon.RegisterStateComponent("session", SessionSnapshot, ApplyRemoteSession, ApplyRemoteSession)
Addon.RegisterStateComponent("quests", QuestSnapshot, ApplyRemoteQuestFull, ApplyRemoteQuestDelta)
Addon.RegisterStateComponent("instructions", InstructionSnapshot, ApplyRemoteInstructionFull, ApplyRemoteInstructionDelta)

Addon.RegisterListener("LOCAL_QUEST_ACTION", HandleInstructionQuestAction)
Addon.RegisterListener("LOCAL_QUEST_STATE_CHANGED", RefreshGroupProgress)
Addon.RegisterListener("REMOTE_QUEST_STATE_CHANGED", RefreshGroupProgress)
Addon.RegisterListener("PEER_STATUS", RefreshGroupProgress)
Addon.RegisterListener("PEER_LEFT", RefreshGroupProgress)
Addon.RegisterListener("PARTY_CHANGED", RefreshGroupProgress)


SLASH_PFQUESTGROUP1 = "/pfqgroup"
SLASH_PFQUESTGROUP2 = "/pfqg"
SlashCmdList["PFQUESTGROUP"] = HandleSlashCommand

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
    InstallGroupProgressTracker()
    initialized = true
    RefreshParty()
    return
  end

  if not initialized then
    return
  end

  if event == "PLAYER_ENTERING_WORLD" or event == "PARTY_MEMBERS_CHANGED" then
    playerName = UnitName("player") or playerName
    InstallGroupProgressTracker()
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
