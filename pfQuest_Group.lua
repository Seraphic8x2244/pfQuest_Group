local ADDON_NAME = "pfQuest_Group"
local ADDON_VERSION = GetAddOnMetadata(ADDON_NAME, "Version")

pfQuest_Group = pfQuest_Group or {}
local Addon = pfQuest_Group
local L = pfQuest_Group_L or {}
Addon.groupContextKey = nil

local PROTOCOL_PREFIX = "PFQGROUP"
local PROTOCOL_VERSION = 3
local DB_SCHEMA_VERSION = 3
local CHUNK_SIZE = 180
local MAX_CHUNKS = 64
local INCOMING_TIMEOUT = 30
local SINGLE_OBJECTIVE_SOUND = "Sound\\Interface\\levelup2.wav"
local SINGLE_OBJECTIVE_ICON = "Interface\\AddOns\\pfQuest\\img\\icon_npc"

local frame = CreateFrame("Frame")
local questScanFrame = CreateFrame("Frame")
questScanFrame:Hide()
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
local guideTouristUI = {
  frame = nil,
  title = nil,
  rows = {},
  touristRows = {},
  objectiveRows = {},
  completing = {},
  completed = {},
  completionDuration = 0.9,
  sessionKey = nil,
  showHidden = false,
  showHiddenButton = nil,
  resizeGrip = nil,
  refresh = nil
}

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
  local flightName

  if type(record) ~= "table" then
    return nil
  end

  seq = tonumber(record.seq) or tonumber(fallbackSeq)
  if not seq or seq < 1 then
    return nil
  end
  seq = math.floor(seq)

  actionType = string.upper(SafeString(record.actionType))
  if actionType ~= "ACCEPT" and actionType ~= "TURNIN" and actionType ~= "FLIGHT" then
    return nil
  end

  questID = tonumber(record.questID)
  mobID = tonumber(record.mobID)
  questTitle = SafeString(record.questTitle)
  npcName = SafeString(record.npcName)
  flightName = Trim(SafeString(record.flightName))

  if actionType == "FLIGHT" then
    if flightName == "" then
      return nil
    end
    questID = nil
    mobID = nil
    questTitle = ""
    npcName = ""
  elseif not questID and questTitle == "" then
    return nil
  end

  return {
    seq = seq,
    actionType = actionType,
    questID = questID,
    questTitle = questTitle,
    mobID = mobID,
    npcName = npcName,
    flightName = flightName
  }
end

local function NormalizeInstructionStore(store, session)
  local guideRecords = {}
  local guideParticipants = {}
  local guideEligible = {}
  local guideAcknowledged = {}
  local guideCompleted = {}
  local guideRemoved = {}
  local guideEligibilityKnown = {}
  local consumed = {}
  local guideCursor = tonumber(session and session.guideActionSeq) or 0
  local baseline = tonumber(session and session.joinBaseline)
  local sameGuideSession
  local key
  local record
  local normalized
  local seq
  local name
  local normalizedName
  local participantBaseline
  local names
  local normalizedNames
  local hasEligible
  local allAcknowledged

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
    sameGuideSession = store.guideSessionId == session.guideSessionId
    if not sameGuideSession then
      guideRecords = {}
    end

    if sameGuideSession and type(store.guideParticipants) == "table" then
      for name, participantBaseline in pairs(store.guideParticipants) do
        normalizedName = NormalizeName(name)
        participantBaseline = tonumber(participantBaseline)
        if normalizedName and participantBaseline and participantBaseline >= 0 and participantBaseline <= guideCursor then
          guideParticipants[normalizedName] = math.floor(participantBaseline)
        end
      end
    end

    if sameGuideSession and type(store.guideEligible) == "table" then
      for key, names in pairs(store.guideEligible) do
        seq = tonumber(key)
        if seq and guideRecords[seq] and type(names) == "table" then
          seq = math.floor(seq)
          normalizedNames = {}
          for name in pairs(names) do
            normalizedName = NormalizeName(name)
            if normalizedName then
              normalizedNames[normalizedName] = true
            end
          end
          if next(normalizedNames) then
            guideEligible[seq] = normalizedNames
          end
        end
      end
    end

    if sameGuideSession and type(store.guideAcknowledged) == "table" then
      for key, names in pairs(store.guideAcknowledged) do
        seq = tonumber(key)
        if seq and guideRecords[seq] and guideEligible[seq] and type(names) == "table" then
          seq = math.floor(seq)
          normalizedNames = {}
          for name in pairs(names) do
            normalizedName = NormalizeName(name)
            if normalizedName and guideEligible[seq][normalizedName] then
              normalizedNames[normalizedName] = true
            end
          end
          if next(normalizedNames) then
            guideAcknowledged[seq] = normalizedNames
          end
        end
      end
    end

    if sameGuideSession and type(store.guideEligibilityKnown) == "table" then
      for key, record in pairs(store.guideEligibilityKnown) do
        seq = tonumber(key)
        if record and seq and guideRecords[seq] then
          guideEligibilityKnown[math.floor(seq)] = true
        end
      end
    end

    if sameGuideSession and type(store.guideCompleted) == "table" then
      for key, record in pairs(store.guideCompleted) do
        seq = tonumber(key)
        if record and seq and guideRecords[seq] then
          guideCompleted[math.floor(seq)] = true
        end
      end
    end

    if sameGuideSession and type(store.guideRemoved) == "table" then
      for key, record in pairs(store.guideRemoved) do
        seq = tonumber(key)
        if record and seq and guideRecords[seq] then
          guideRemoved[math.floor(seq)] = true
        end
      end
    end

    for seq in pairs(guideRecords) do
      if guideEligibilityKnown[seq] then
        hasEligible = false
        allAcknowledged = true
        for name in pairs(guideEligible[seq] or {}) do
          hasEligible = true
          if not guideAcknowledged[seq] or not guideAcknowledged[seq][name] then
            allAcknowledged = false
          end
        end
        if hasEligible and allAcknowledged then
          guideCompleted[seq] = true
        end
      end
    end

    store.guideSessionId = session.guideSessionId
    store.guideRecords = guideRecords
    store.guideParticipants = guideParticipants
    store.guideEligible = guideEligible
    store.guideAcknowledged = guideAcknowledged
    store.guideCompleted = guideCompleted
    store.guideRemoved = guideRemoved
    store.guideEligibilityKnown = guideEligibilityKnown
  else
    store.guideSessionId = nil
    store.guideRecords = {}
    store.guideParticipants = {}
    store.guideEligible = {}
    store.guideAcknowledged = {}
    store.guideCompleted = {}
    store.guideRemoved = {}
    store.guideEligibilityKnown = {}
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

local function NormalizeUIState(state)
  local validPoints = {
    TOPLEFT = true,
    TOP = true,
    TOPRIGHT = true,
    LEFT = true,
    CENTER = true,
    RIGHT = true,
    BOTTOMLEFT = true,
    BOTTOM = true,
    BOTTOMRIGHT = true
  }
  local window

  if type(state) ~= "table" then
    state = {}
  end

  if type(state.guideWindow) ~= "table" then
    state.guideWindow = {}
  end

  window = state.guideWindow
  if not validPoints[window.point] then
    window.point = "CENTER"
  end
  if not validPoints[window.relativePoint] then
    window.relativePoint = window.point
  end
  window.x = tonumber(window.x) or 0
  window.y = tonumber(window.y) or 0
  window.width = math.max(280, tonumber(window.width) or 280)
  window.height = math.max(34, tonumber(window.height) or 34)

  return state
end

local function InitializeDatabase()
  if type(pfQuest_GroupDB) ~= "table" then
    pfQuest_GroupDB = {}
  end

  pfQuest_GroupDB.schema = DB_SCHEMA_VERSION
  pfQuest_GroupDB.session = NormalizeSession(pfQuest_GroupDB.session)
  pfQuest_GroupDB.instructions = NormalizeInstructionStore(pfQuest_GroupDB.instructions, pfQuest_GroupDB.session)
  pfQuest_GroupDB.ui = NormalizeUIState(pfQuest_GroupDB.ui)
  pfQuest_GroupDB.groupHold = Addon.NormalizeGroupHoldState(pfQuest_GroupDB.groupHold, pfQuest_GroupDB.session)
  touristPendingInstructions = {}
  Addon.db = pfQuest_GroupDB
end

local function IsPartyMember(name)
  local normalized = NormalizeName(name)
  return normalized and party[normalized] ~= nil
end

local function CurrentDistribution(target)
  if target and not IsPartyMember(target) then
    return nil
  end

  -- Vanilla 1.12 has no addon-message WHISPER channel. Directed recovery
  -- validates the requested peer but travels over the PARTY addon channel.
  if GetNumPartyMembers() > 0 then
    return "PARTY"
  end

  return nil
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
  local messageId
  local total
  local part

  if not initialized then
    return false
  end

  distribution = CurrentDistribution(target)
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

    SendAddonMessage(PROTOCOL_PREFIX, wire, distribution)
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
  local hello = {
    version = ADDON_VERSION or "unknown",
    boot = bootId or ""
  }

  if target then
    hello.target = NormalizeName(target)
  end

  return SendWire("H", EncodeMap(hello), target)
end

local function RequestFullState(target)
  local requested = target and NormalizeName(target) or ""
  return SendWire("R", requested or "", target)
end

local function ApplyFullState(sender, payload)
  local snapshot = DecodeMap(payload)
  local componentName
  local componentPayload
  local component

  componentPayload = snapshot.session
  component = components.session
  if componentPayload ~= nil and component and component.applyFull then
    component.applyFull(sender, componentPayload)
  end

  for componentName, componentPayload in pairs(snapshot) do
    if componentName ~= "session" then
      component = components[componentName]
      if component and component.applyFull then
        component.applyFull(sender, componentPayload)
      end
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
    local helloTarget = NormalizeName(hello.target)
    local previousBoot
    local incomingBoot
    local establishBoot = false
    local restarted = false
    local hadRemoteState

    if helloTarget and helloTarget ~= NormalizeName(playerName) then
      return
    end

    peer = peers[senderKey] or { name = sender }

    previousBoot = peer.bootId
    incomingBoot = hello.boot
    hadRemoteState = peer.session or peer.questState or peer.instructions or peer.instructionCompletions

    if incomingBoot and incomingBoot ~= "" then
      if previousBoot and previousBoot ~= "" then
        if previousBoot ~= incomingBoot then
          establishBoot = true
          restarted = true
        end
      else
        establishBoot = true
      end
    end

    if establishBoot and ((previousBoot and previousBoot ~= "") or hadRemoteState) then
      peer.session = nil
      peer.questState = nil
      peer.instructions = nil
      peer.instructionCompletions = nil
      incoming[senderKey] = nil
      if restarted then
        Emit("PEER_RESTARTED", sender)
      end
    end

    peer.name = sender
    peer.version = hello.version
    peer.protocol = protocolVersion
    peer.bootId = incomingBoot
    peer.compatible = protocolVersion == PROTOCOL_VERSION
    if not peer.compatible then
      peer.session = nil
      peer.questState = nil
      peer.instructions = nil
      peer.instructionCompletions = nil
    end
    peers[senderKey] = peer
    Emit("PEER_STATUS", sender, peer.compatible)

    if peer.compatible then
      if establishBoot and not helloTarget then
        SendHello(sender)
      end
      if establishBoot or not hadRemoteState then
        RequestFullState(sender)
      end
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
    local requested = NormalizeName(payload)
    if not requested or requested == NormalizeName(playerName) then
      SendFullState(sender)
    end
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

local function PartyRosterChanged(previousParty, nextParty)
  local key
  local previous
  local current

  for key, previous in pairs(previousParty or {}) do
    current = nextParty and nextParty[key]
    if not current
      or current.unit ~= previous.unit
      or current.classToken ~= previous.classToken then
      return true
    end
  end

  for key in pairs(nextParty or {}) do
    if not previousParty or not previousParty[key] then
      return true
    end
  end

  return false
end

function Addon.LocalGroupContextKey()
  local raidCount = GetNumRaidMembers and GetNumRaidMembers() or 0
  local selfKey = NormalizeName(playerName or UnitName("player"))
  local index
  local name
  local subgroup

  if raidCount and raidCount > 0 and GetRaidRosterInfo then
    for index = 1, raidCount do
      name, _, subgroup = GetRaidRosterInfo(index)
      if selfKey and NormalizeName(name) == selfKey then
        return "GROUP:" .. SafeString(subgroup or 1)
      end
    end
    return "GROUP"
  end

  if GetNumPartyMembers() > 0 then
    return "GROUP:1"
  end

  return "SOLO"
end

function Addon.AnnounceOwnGroupContext()
  local current = Addon.LocalGroupContextKey()
  local previous = Addon.groupContextKey

  Addon.groupContextKey = current

  if initialized and current ~= "SOLO" and current ~= previous then
    return SendHello()
  end

  return false
end

local function RefreshParty()
  local previousParty = party
  local nextParty = {}
  local changed
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

  changed = PartyRosterChanged(previousParty, nextParty)
  party = nextParty
  Addon.party = party

  for peerKey, peer in pairs(peers) do
    if not party[peerKey] then
      peers[peerKey] = nil
      incoming[peerKey] = nil
      Emit("PEER_LEFT", peer.name)
    end
  end

  if changed then
    Emit("PARTY_CHANGED")
  end

  Addon.AnnounceOwnGroupContext()
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
  if not decoded.revision or decoded.revision < 0 then
    return nil
  end
  decoded.revision = math.floor(decoded.revision)

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
  questScanFrame:Show()
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

  if type(TakeTaxiNode) == "function" then
    local previousTakeTaxiNode = TakeTaxiNode
    TakeTaxiNode = function(slot)
      local destination
      local nodeType
      local nodeCost
      local canTake = true

      if type(TaxiNodeName) == "function" then
        destination = TaxiNodeName(slot)
      end
      if type(TaxiNodeGetType) == "function" then
        nodeType = TaxiNodeGetType(slot)
      end
      if type(TaxiNodeCost) == "function" then
        nodeCost = tonumber(TaxiNodeCost(slot))
      end

      if nodeType and nodeType ~= "REACHABLE" then
        canTake = false
      end
      if nodeCost and type(GetMoney) == "function" and nodeCost > GetMoney() then
        canTake = false
      end

      -- Synchronize while the taxi map/group context is still stable.
      -- Sending after TakeTaxiNode can race the taxi transition: the Guide
      -- may update locally while the Tourist misses both instruction/session
      -- deltas.
      if canTake
        and destination
        and destination ~= ""
        and destination ~= "INVALID"
        and Addon.HandleFlightAction then
        Addon.HandleFlightAction(destination)
      end

      previousTakeTaxiNode(slot)
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
  if not questState.ready then
    return nil
  end

  return EncodeQuestWire("S", questState.revision, questState.quests)
end

local function SingleObjectiveDone(objective)
  local current
  local required

  if not objective then
    return false
  end

  if objective.done then
    return true
  end

  current = tonumber(objective.current) or 0
  required = tonumber(objective.required) or 0
  return required > 0 and current >= required
end

local function IsSharedSingleObjective(objective)
  local objectiveType = string.lower(SafeString(objective and objective.objectiveType))
  local required = tonumber(objective and objective.required) or 0

  return required == 1 and (objectiveType == "item" or objectiveType == "object")
end

local function FindQuestStateMatch(state, sourceQuest)
  local key
  local quest

  if not state or not state.ready or not sourceQuest then
    return nil
  end

  if sourceQuest.questID then
    quest = state.quests and state.quests[QuestKey(sourceQuest.questID, sourceQuest.title)]
    if quest then
      return quest
    end
  end

  for key, quest in pairs(state.quests or {}) do
    if quest.title == sourceQuest.title and (not sourceQuest.questID or not quest.questID) then
      return quest
    end
  end

  return nil
end

local function FindQuestObjective(quest, objectiveIndex)
  local index
  local objective

  objectiveIndex = tonumber(objectiveIndex)
  if not quest or not objectiveIndex then
    return nil
  end

  for index = 1, table.getn(quest.objectives or {}) do
    objective = quest.objectives[index]
    if tonumber(objective and objective.index) == objectiveIndex then
      return objective
    end
  end

  return nil
end

local function RemoteGuideSingleObjectiveCompleted(sender, previousQuest, nextQuest)
  local session = Addon.db and Addon.db.session
  local senderKey = NormalizeName(sender)
  local guideKey
  local peer
  local remoteSession
  local localQuest
  local index
  local nextObjective
  local previousObjective
  local localObjective

  if not session
    or session.mode ~= "TOURIST"
    or not session.guideName
    or not session.guideSessionId
    or session.joinBaseline == nil
    or not previousQuest
    or not nextQuest then
    return false
  end

  guideKey = NormalizeName(session.guideName)
  if not senderKey or senderKey ~= guideKey then
    return false
  end

  peer = peers[senderKey]
  remoteSession = peer and peer.session
  if not peer
    or not peer.compatible
    or not remoteSession
    or remoteSession.mode ~= "GUIDE"
    or remoteSession.guideSessionId ~= session.guideSessionId then
    return false
  end

  localQuest = FindQuestStateMatch(questState, nextQuest)
  if not localQuest then
    return false
  end

  for index = 1, table.getn(nextQuest.objectives or {}) do
    nextObjective = nextQuest.objectives[index]
    if IsSharedSingleObjective(nextObjective) and SingleObjectiveDone(nextObjective) then
      previousObjective = FindQuestObjective(previousQuest, nextObjective.index or index)
      localObjective = FindQuestObjective(localQuest, nextObjective.index or index)
      if previousObjective
        and localObjective
        and IsSharedSingleObjective(localObjective)
        and not SingleObjectiveDone(previousObjective) then
        return true
      end
    end
  end

  return false
end

local function ApplyRemoteQuestFull(sender, payload)
  local decoded = DecodeQuestWire(payload, "S")
  local senderKey = NormalizeName(sender)
  local peer = senderKey and peers[senderKey]

  if not decoded or not peer then
    return
  end

  if decoded.revision == 0 then
    if not peer.questState or (tonumber(peer.questState.revision) or 0) <= 0 then
      peer.questState = {
        revision = 0,
        ready = false,
        quests = {}
      }
      Emit("REMOTE_QUEST_STATE_CHANGED", sender, CopyQuestState(peer.questState))
    end
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

  local playSingleObjectiveCue = false
  local previousQuest

  for key, quest in pairs(decoded.quests) do
    previousQuest = peer.questState.quests[key]
    if not playSingleObjectiveCue
      and RemoteGuideSingleObjectiveCompleted(sender, previousQuest, quest) then
      playSingleObjectiveCue = true
    end
    peer.questState.quests[key] = quest
  end

  for key, quest in pairs(decoded.removals) do
    peer.questState.quests[key] = nil
  end

  peer.questState.revision = decoded.revision
  peer.questState.ready = true

  if playSingleObjectiveCue and type(PlaySoundFile) == "function" then
    PlaySoundFile(SINGLE_OBJECTIVE_SOUND)
  end

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
  questScanFrame:Hide()
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

local function GroupProgressColorHex(current, required)
  local red = 0.65
  local green = 0.65
  local blue = 0.65

  current = tonumber(current) or 0
  required = tonumber(required) or 1
  if required <= 0 then
    required = 1
  end

  if pfMap and pfMap.tooltip and pfMap.tooltip.GetColor then
    red, green, blue = pfMap.tooltip:GetColor(current, required)
    red = math.min(1, (tonumber(red) or 0.65) + 0.2)
    green = math.min(1, (tonumber(green) or 0.65) + 0.2)
    blue = math.min(1, (tonumber(blue) or 0.65) + 0.2)
  end

  return string.format(
    "%02x%02x%02x",
    math.floor(red * 255 + 0.5),
    math.floor(green * 255 + 0.5),
    math.floor(blue * 255 + 0.5)
  )
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
    if quest.title == button.title and (not numericQuestID or not quest.questID) then
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
    if quest.title == localQuest.title and (not localQuest.questID or not quest.questID) then
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

local function EnsureGroupProgressRow(button, objectiveIndex, peerIndex)
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
  local row

  if button.pfqGroupRows then
    for _, objectiveEntries in pairs(button.pfqGroupRows) do
      for _, row in pairs(objectiveEntries) do
        row.icon:Hide()
        row.text:Hide()
      end
    end
  end
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
  local holdFrame

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
              candidateWidth = objective:GetStringWidth()
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

  holdFrame = Addon.groupHoldTrackerFrame
  if holdFrame and holdFrame:IsShown() then
    holdFrame:ClearAllPoints()
    holdFrame:SetPoint("TOPLEFT", trackerFrame, "TOPLEFT", 0, -height)
    holdFrame:SetPoint("TOPRIGHT", trackerFrame, "TOPRIGHT", 0, -height)
    height = height + holdFrame:GetHeight()
    if holdFrame.pfqGroupWidth and holdFrame.pfqGroupWidth > width then
      width = holdFrame.pfqGroupWidth
    end
  end

  trackerFrame:SetHeight(height)
  trackerFrame:SetWidth(math.min(width, 300) + 30)
end

local function ApplyGroupProgressToButton(button, captureBase)
  local trackerFrame = pfQuest and pfQuest.tracker
  local peersInOrder
  local questPeers = {}
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
  local row
  local iconSize
  local progressText
  local progressColor
  local localClassName
  local localClassToken
  local localName
  local heldNeed
  local heldRows
  local heldIndex
  local heldParticipant

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
  if not localQuest then
    RestoreGroupTrackerButton(button)
    return
  end

  for peerIndex = 1, table.getn(peersInOrder) do
    peerInfo = peersInOrder[peerIndex]
    if FindRemoteTrackerQuest(peerInfo.questState, localQuest) then
      table.insert(questPeers, peerInfo)
    end
  end

  peersInOrder = questPeers
  fontSize = GetGroupTrackerFontSize(button)
  entryHeight = math.ceil(fontSize * 1.6)
  iconSize = math.max(8, fontSize - 2)
  localName = playerName or UnitName("player") or "Player"
  localClassName, localClassToken = UnitClass("player")

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
      heldNeed = Addon.FindGroupHoldNeed and Addon.FindGroupHoldNeed(localQuest, objectiveIndex) or nil

      if heldNeed then
        objective:SetText("|cffffffff- " .. SafeString(localObjective.text) .. "|r")
        objective:SetTextColor(1, 1, 1)
        objective:SetPoint("TOPRIGHT", -10, -fontSize * lineCount - 6)

        row = EnsureGroupProgressRow(button, objectiveIndex, 0)
        lineCount = lineCount + 1

        row.icon:ClearAllPoints()
        row.icon:SetPoint("TOPLEFT", button, "TOPLEFT", 32, -fontSize * lineCount - 6)
        row.icon:SetWidth(iconSize)
        row.icon:SetHeight(iconSize)
        SetGroupClassIcon(row.icon, localClassToken)
        row.icon:Show()

        row.text:ClearAllPoints()
        row.text:SetPoint("TOPLEFT", button, "TOPLEFT", 44, -fontSize * lineCount - 6)
        row.text:SetPoint("TOPRIGHT", button, "TOPRIGHT", -10, -fontSize * lineCount - 6)
        CopyGroupTrackerFont(objective, row.text, fontSize)
        row.text:SetText(
          "|cff" .. GroupClassColorHex(localClassToken) .. SafeString(localName) .. ":|r "
          .. Addon.GroupHoldProgressText(localObjective)
        )
        row.text:SetTextColor(1, 1, 1)
        row.text:Show()

        heldRows = Addon.GetGroupHoldParticipantRows(heldNeed)
        for heldIndex = 1, table.getn(heldRows) do
          heldParticipant = heldRows[heldIndex]
          row = EnsureGroupProgressRow(button, objectiveIndex, heldIndex)
          lineCount = lineCount + 1

          row.icon:ClearAllPoints()
          row.icon:SetPoint("TOPLEFT", button, "TOPLEFT", 32, -fontSize * lineCount - 6)
          row.icon:SetWidth(iconSize)
          row.icon:SetHeight(iconSize)
          SetGroupClassIcon(row.icon, heldParticipant.classToken)
          row.icon:Show()

          row.text:ClearAllPoints()
          row.text:SetPoint("TOPLEFT", button, "TOPLEFT", 44, -fontSize * lineCount - 6)
          row.text:SetPoint("TOPRIGHT", button, "TOPRIGHT", -10, -fontSize * lineCount - 6)
          CopyGroupTrackerFont(objective, row.text, fontSize)
          row.text:SetText(
            "|cff" .. GroupClassColorHex(heldParticipant.classToken) .. SafeString(heldParticipant.name) .. ":|r "
            .. Addon.GroupHoldProgressText(heldParticipant.objective)
          )
          row.text:SetTextColor(1, 1, 1)
          row.text:Show()
        end
      else
        objective:SetText("|cffffffff- " .. SafeString(localObjective.text) .. "|r")
        objective:SetTextColor(1, 1, 1)
        objective:SetPoint("TOPRIGHT", -10, -fontSize * lineCount - 6)

        row = EnsureGroupProgressRow(button, objectiveIndex, 0)
        lineCount = lineCount + 1

        row.icon:ClearAllPoints()
        row.icon:SetPoint("TOPLEFT", button, "TOPLEFT", 32, -fontSize * lineCount - 6)
        row.icon:SetWidth(iconSize)
        row.icon:SetHeight(iconSize)
        SetGroupClassIcon(row.icon, localClassToken)
        row.icon:Show()

        row.text:ClearAllPoints()
        row.text:SetPoint("TOPLEFT", button, "TOPLEFT", 44, -fontSize * lineCount - 6)
        row.text:SetPoint("TOPRIGHT", button, "TOPRIGHT", -10, -fontSize * lineCount - 6)
        CopyGroupTrackerFont(objective, row.text, fontSize)
        progressText = SafeString(tonumber(localObjective.current) or 0) .. "/" .. SafeString(required)
        progressColor = GroupProgressColorHex(localObjective.current, required)
        row.text:SetText(
          "|cff" .. GroupClassColorHex(localClassToken) .. SafeString(localName) .. ":|r "
          .. "|cff" .. progressColor .. progressText .. "|r"
        )
        row.text:SetTextColor(1, 1, 1)
        row.text:Show()

        for peerIndex = 1, table.getn(peersInOrder) do
          peerInfo = peersInOrder[peerIndex]
          remoteObjective = GetRemoteObjective(peerInfo, localQuest, objectiveIndex)
          row = EnsureGroupProgressRow(button, objectiveIndex, peerIndex)
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
            progressColor = GroupProgressColorHex(remoteObjective.current, remoteObjective.required or required)
            progressText = "|cff" .. progressColor .. progressText .. "|r"
          else
            progressText = "|cffaaaaaa--|r"
          end

          row.text:SetText(
            "|cff" .. GroupClassColorHex(peerInfo.classToken) .. SafeString(peerInfo.name) .. ":|r "
            .. progressText
          )
          row.text:SetTextColor(1, 1, 1)
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

  if Addon.RefreshGroupHoldTracker then
    Addon.RefreshGroupHoldTracker()
  end
  RelayoutGroupTracker()
end

local function GroupTrackerButtonEvent(self)
  local button = self or this

  if originalTrackerButtonEvent then
    originalTrackerButtonEvent(button)
  end

  ApplyGroupProgressToButton(button, true)
  if Addon.RefreshGroupHoldTracker then
    Addon.RefreshGroupHoldTracker()
  end
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


function Addon.GroupHoldSessionKey(session)
  session = session or (Addon.db and Addon.db.session)
  if not session then
    return nil
  end

  if session.mode == "GUIDE" and session.guideSessionId then
    return SafeString(session.guideSessionId)
  end

  if session.mode == "TOURIST" and session.guideSessionId and session.joinBaseline ~= nil then
    return SafeString(session.guideSessionId)
  end

  return nil
end

function Addon.NormalizeGroupHoldState(state, session)
  local sessionKey = Addon.GroupHoldSessionKey(session)
  local output = {
    sessionKey = sessionKey,
    participants = {},
    localSeen = {},
    localTracked = {}
  }
  local key
  local value
  local participant
  local normalized
  local ok
  local copied

  if not sessionKey or type(state) ~= "table" or state.sessionKey ~= sessionKey then
    return output
  end

  if type(state.localSeen) == "table" then
    for key, value in pairs(state.localSeen) do
      if value and type(key) == "string" and key ~= "" then
        output.localSeen[key] = true
      end
    end
  end

  if type(state.localTracked) == "table" then
    for key, value in pairs(state.localTracked) do
      if value and type(key) == "string" and key ~= "" then
        output.localTracked[key] = true
      end
    end
  end

  if type(state.participants) == "table" then
    for key, participant in pairs(state.participants) do
      if type(participant) == "table" then
        normalized = NormalizeName(participant.name or key)
        if normalized then
          copied = nil
          if type(participant.questState) == "table" and participant.questState.ready then
            ok, copied = pcall(CopyQuestState, participant.questState)
            if not ok then
              copied = nil
            end
          end

          output.participants[normalized] = {
            name = SafeString((participant.name and participant.name ~= "") and participant.name or key),
            classToken = SafeString(participant.classToken),
            order = tonumber(participant.order) or 99,
            questState = copied
          }
        end
      end
    end
  end

  return output
end

function Addon.SyncGroupHoldSession()
  local session
  local sessionKey
  local state

  if not Addon.db then
    return nil
  end

  session = Addon.db.session
  sessionKey = Addon.GroupHoldSessionKey(session)
  state = Addon.db.groupHold

  if type(state) ~= "table" or state.sessionKey ~= sessionKey then
    state = Addon.NormalizeGroupHoldState(nil, session)
    Addon.db.groupHold = state
  else
    state.participants = type(state.participants) == "table" and state.participants or {}
    state.localSeen = type(state.localSeen) == "table" and state.localSeen or {}
    state.localTracked = type(state.localTracked) == "table" and state.localTracked or {}
  end

  return state
end

function Addon.MarkGroupHoldLocalState()
  local state = Addon.SyncGroupHoldSession()
  local trackerFrame = pfQuest and pfQuest.tracker
  local key
  local quest
  local index
  local button
  local localQuest
  local titleKey

  if not state or not state.sessionKey or not questState.ready then
    return
  end

  for key, quest in pairs(questState.quests or {}) do
    state.localSeen[key] = true
    if quest.title and quest.title ~= "" then
      state.localSeen[QuestKey(nil, quest.title)] = true
    end
  end

  if trackerFrame and trackerFrame.buttons then
    for index = 1, table.getn(trackerFrame.buttons) do
      button = trackerFrame.buttons[index]
      localQuest = FindLocalTrackerQuest(button)
      if localQuest then
        state.localTracked[localQuest.key] = true
        titleKey = localQuest.title and QuestKey(nil, localQuest.title) or nil
        if titleKey then
          state.localTracked[titleKey] = true
        end
      end
    end
  end
end

function Addon.GroupHoldPeerRelevant(sender, remoteSession, session)
  local senderKey
  local guideKey

  session = session or (Addon.db and Addon.db.session)
  if not session or not remoteSession or not session.guideSessionId then
    return false
  end

  senderKey = NormalizeName(sender)
  if not senderKey then
    return false
  end

  if session.mode == "GUIDE" then
    return remoteSession.mode == "TOURIST"
      and remoteSession.guideSessionId == session.guideSessionId
      and NormalizeName(remoteSession.guideName) == NormalizeName(playerName)
  end

  if session.mode == "TOURIST" and session.guideName and session.joinBaseline ~= nil then
    guideKey = NormalizeName(session.guideName)
    if senderKey == guideKey then
      return remoteSession.mode == "GUIDE"
        and remoteSession.guideSessionId == session.guideSessionId
    end

    return remoteSession.mode == "TOURIST"
      and remoteSession.guideSessionId == session.guideSessionId
      and NormalizeName(remoteSession.guideName) == guideKey
  end

  return false
end

function Addon.GroupHoldPartyOrder(senderKey)
  local member = senderKey and party[senderKey]
  local unit = member and member.unit
  local _, _, index

  if unit then
    _, _, index = string.find(unit, "party([%d]+)")
  end

  return tonumber(index) or 99
end

function Addon.UpdateGroupHoldParticipantSession(sender, remoteSession)
  local state = Addon.SyncGroupHoldSession()
  local session = Addon.db and Addon.db.session
  local senderKey = NormalizeName(sender)
  local member
  local peer
  local participant

  if not state or not state.sessionKey or not senderKey then
    return false
  end

  if not Addon.GroupHoldPeerRelevant(sender, remoteSession, session) then
    if state.participants[senderKey] then
      state.participants[senderKey] = nil
      return true
    end
    return false
  end

  member = party[senderKey]
  peer = peers[senderKey]
  participant = state.participants[senderKey] or {}
  participant.name = SafeString((peer and peer.name) or (member and member.name) or sender)
  participant.classToken = SafeString((member and member.classToken) or participant.classToken)
  participant.order = Addon.GroupHoldPartyOrder(senderKey)
  if peer and peer.questState and peer.questState.ready then
    participant.questState = CopyQuestState(peer.questState)
  end
  state.participants[senderKey] = participant
  return true
end

function Addon.UpdateGroupHoldParticipantQuest(sender, remoteState)
  local state = Addon.SyncGroupHoldSession()
  local senderKey = NormalizeName(sender)
  local peer = senderKey and peers[senderKey]
  local participant

  if not state
    or not state.sessionKey
    or not senderKey
    or not peer
    or not Addon.GroupHoldPeerRelevant(sender, peer.session)
    or not remoteState
    or not remoteState.ready then
    return false
  end

  Addon.UpdateGroupHoldParticipantSession(sender, peer.session)
  participant = state.participants[senderKey]
  if not participant then
    return false
  end

  participant.questState = CopyQuestState(remoteState)
  return true
end

function Addon.HasActiveGroupHoldPeer()
  local session = Addon.db and Addon.db.session
  local normalized
  local peer

  if not Addon.GroupHoldSessionKey(session) then
    return false
  end

  for normalized in pairs(party) do
    peer = peers[normalized]
    if peer and peer.compatible and Addon.GroupHoldPeerRelevant(peer.name or normalized, peer.session, session) then
      return true
    end
  end

  return false
end

function Addon.BuildGroupHoldNeeds()
  local output = {}
  local byKey = {}
  local state = Addon.SyncGroupHoldSession()
  local participantKey
  local participant
  local remoteQuest
  local localQuest
  local localObjective
  local objective
  local objectiveIndex
  local seen
  local tracked
  local needKey
  local need

  if not state or not state.sessionKey or not Addon.HasActiveGroupHoldPeer() then
    return output
  end

  Addon.MarkGroupHoldLocalState()

  for participantKey, participant in pairs(state.participants or {}) do
    if participant.questState and participant.questState.ready then
      for _, remoteQuest in pairs(participant.questState.quests or {}) do
        localQuest = FindRemoteTrackerQuest(questState, remoteQuest)
        seen = localQuest
          or state.localSeen[remoteQuest.key]
          or state.localSeen[QuestKey(nil, remoteQuest.title)]
        tracked = state.localTracked[remoteQuest.key]
          or state.localTracked[QuestKey(nil, remoteQuest.title)]

        if localQuest or (seen and tracked) then
          for objectiveIndex = 1, table.getn(remoteQuest.objectives or {}) do
            objective = remoteQuest.objectives[objectiveIndex]
            localObjective = localQuest and localQuest.objectives and localQuest.objectives[objectiveIndex] or nil

            if objective
              and not RemoteObjectiveDone(objective)
              and (not localObjective or RemoteObjectiveDone(localObjective)) then
              needKey = SafeString(remoteQuest.key) .. "#" .. SafeString(objectiveIndex)
              need = byKey[needKey]
              if not need then
                need = {
                  key = needKey,
                  quest = CopyQuest(remoteQuest),
                  objectiveIndex = objectiveIndex,
                  objective = CopyObjective(objective),
                  playersNeeded = {}
                }
                byKey[needKey] = need
                table.insert(output, need)
              end
              need.playersNeeded[participantKey] = true
            end
          end
        end
      end
    end
  end

  table.sort(output, function(left, right)
    local leftTitle = string.lower(SafeString(left.quest and left.quest.title))
    local rightTitle = string.lower(SafeString(right.quest and right.quest.title))
    if leftTitle ~= rightTitle then
      return leftTitle < rightTitle
    end
    return (tonumber(left.objectiveIndex) or 0) < (tonumber(right.objectiveIndex) or 0)
  end)

  return output
end

function Addon.FindGroupHoldNeed(quest, objectiveIndex)
  local needs = Addon.groupHoldNeeds or {}
  local index
  local need
  local localID
  local needID
  local matches

  objectiveIndex = tonumber(objectiveIndex)
  if not quest or not objectiveIndex then
    return nil
  end

  localID = tonumber(quest.questID)
  for index = 1, table.getn(needs) do
    need = needs[index]
    if need and tonumber(need.objectiveIndex) == objectiveIndex and need.quest then
      needID = tonumber(need.quest.questID)
      if localID and needID then
        matches = localID == needID
      else
        matches = SafeString(quest.title) ~= "" and SafeString(quest.title) == SafeString(need.quest.title)
      end

      if matches then
        return need
      end
    end
  end

  return nil
end

function Addon.GetGroupHoldParticipantRows(need)
  local output = {}
  local state = Addon.SyncGroupHoldSession()
  local key
  local participant
  local remoteQuest
  local objective

  if not state or not need then
    return output
  end

  for key, participant in pairs(state.participants or {}) do
    if participant.questState and participant.questState.ready then
      remoteQuest = FindRemoteTrackerQuest(participant.questState, need.quest)
      objective = remoteQuest
        and remoteQuest.objectives
        and remoteQuest.objectives[need.objectiveIndex]
        or nil
      if objective then
        table.insert(output, {
          key = key,
          name = participant.name or key,
          classToken = participant.classToken,
          order = tonumber(participant.order) or 99,
          objective = objective
        })
      end
    end
  end

  table.sort(output, function(left, right)
    if left.order ~= right.order then
      return left.order < right.order
    end
    return string.lower(SafeString(left.name)) < string.lower(SafeString(right.name))
  end)

  return output
end

function Addon.GroupHoldLocalObjective(need)
  local localQuest

  if not need then
    return nil
  end

  localQuest = FindRemoteTrackerQuest(questState, need.quest)
  if not localQuest or not localQuest.objectives then
    return nil
  end

  return localQuest.objectives[need.objectiveIndex]
end

function Addon.GroupHoldProgressText(objective)
  local current
  local required

  if not objective then
    return "|cffaaaaaa--|r"
  end

  current = tonumber(objective.current) or 0
  required = tonumber(objective.required) or 1
  if required <= 0 then
    required = 1
  end

  return "|cff" .. GroupProgressColorHex(current, required)
    .. SafeString(current) .. "/" .. SafeString(required) .. "|r"
end

function Addon.EnsureGroupHoldTrackerFrame()
  local trackerFrame = pfQuest and pfQuest.tracker

  if Addon.groupHoldTrackerFrame then
    return Addon.groupHoldTrackerFrame
  end

  if not trackerFrame then
    return nil
  end

  Addon.groupHoldTrackerFrame = CreateFrame("Frame", nil, trackerFrame)
  Addon.groupHoldTrackerFrame.rows = {}
  Addon.groupHoldTrackerFrame.pfqGroupWidth = 0
  Addon.groupHoldTrackerFrame:Hide()
  return Addon.groupHoldTrackerFrame
end

function Addon.EnsureGroupHoldTrackerRow(index)
  local frame = Addon.EnsureGroupHoldTrackerFrame()
  local row

  if not frame then
    return nil
  end

  row = frame.rows[index]
  if not row then
    row = {}
    row.icon = frame:CreateTexture(nil, "ARTWORK")
    row.text = frame:CreateFontString(nil, "HIGH", "GameFontNormal")
    row.text:SetJustifyH("LEFT")
    frame.rows[index] = row
  end

  return row
end

function Addon.GroupHoldNativeTrackerVisible(need)
  local trackerFrame = pfQuest and pfQuest.tracker
  local index
  local button
  local localQuest
  local objective
  local matches

  if not trackerFrame or not trackerFrame.buttons or not need then
    return false
  end

  for index = 1, table.getn(trackerFrame.buttons) do
    button = trackerFrame.buttons[index]
    localQuest = FindLocalTrackerQuest(button)
    matches = localQuest
      and ((localQuest.questID and need.quest.questID and localQuest.questID == need.quest.questID)
        or localQuest.title == need.quest.title)

    if matches then
      objective = button.objectives and button.objectives[need.objectiveIndex]
      if objective and objective:IsShown() then
        return true
      end
    end
  end

  return false
end

function Addon.SetGroupHoldTrackerPlayerRow(row, name, classToken, objective, fontSize, lineIndex)
  local frame = Addon.groupHoldTrackerFrame
  local iconSize = math.max(8, fontSize - 2)
  local lineHeight = math.ceil(fontSize * 1.35)
  local text

  if not row or not frame then
    return 0
  end

  row.icon:ClearAllPoints()
  row.icon:SetPoint("TOPLEFT", frame, "TOPLEFT", 22, -((lineIndex - 1) * lineHeight))
  row.icon:SetWidth(iconSize)
  row.icon:SetHeight(iconSize)
  SetGroupClassIcon(row.icon, classToken)
  row.icon:Show()

  row.text:ClearAllPoints()
  row.text:SetPoint("TOPLEFT", frame, "TOPLEFT", 36, -((lineIndex - 1) * lineHeight))
  row.text:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -((lineIndex - 1) * lineHeight))
  CopyGroupTrackerFont(nil, row.text, fontSize)
  text = "|cff" .. GroupClassColorHex(classToken) .. SafeString(name) .. ":|r "
    .. Addon.GroupHoldProgressText(objective)
  row.text:SetText(text)
  row.text:SetTextColor(1, 1, 1)
  row.text:Show()
  return row.text:GetStringWidth() + 44
end

function Addon.RefreshGroupHoldTracker()
  local frame = Addon.groupHoldTrackerFrame
  local index

  if not frame then
    return
  end

  for index = 1, table.getn(frame.rows or {}) do
    frame.rows[index].icon:Hide()
    frame.rows[index].text:Hide()
  end

  frame:Hide()
  frame:SetHeight(0)
  frame.pfqGroupWidth = 0
end

function Addon.ClearGroupHoldNodes()
  local spawn
  local titles
  local title
  local maps
  local map
  local meta

  if not pfMap then
    return
  end

  if pfMap.DeleteNode then
    pfMap:DeleteNode("PFQGROUP")
  end

  for spawn, titles in pairs(pfMap.tooltips or {}) do
    for title, maps in pairs(titles) do
      for map, meta in pairs(maps) do
        if meta and meta.addon == "PFQGROUP" then
          maps[map] = nil
        end
      end
      if not next(maps) then
        titles[title] = nil
      end
    end
    if not next(titles) then
      pfMap.tooltips[spawn] = nil
    end
  end
end

function Addon.NewGroupHoldNodeMeta(need)
  return {
    addon = "PFQGROUP",
    quest = "PFQG:" .. SafeString(need.key),
    questid = need.quest and need.quest.questID,
    QTYPE = "PFQGROUP_OBJECTIVE",
    layer = 2,
    cluster = true,
    pfqGroupNeedKey = need.key,
    pfqGroupQuestKey = need.quest and need.quest.key,
    pfqGroupQuestTitle = need.quest and need.quest.title,
    pfqGroupObjectiveIndex = need.objectiveIndex,
    pfqGroupObjectiveText = need.objective and need.objective.text
  }
end

function Addon.GroupHoldTextContainsName(textValue, nameValue)
  local text = string.lower(Trim(SafeString(textValue)))
  local name = string.lower(Trim(SafeString(nameValue)))
  return text ~= "" and name ~= "" and string.find(text, name, 1, true) ~= nil
end

function Addon.AddGroupHoldSource(kind, id, need)
  local meta

  if not pfDatabase or not id or not need then
    return false
  end

  meta = Addon.NewGroupHoldNodeMeta(need)
  if kind == "U" and pfDatabase.SearchMobID then
    pfDatabase:SearchMobID(id, meta)
    return true
  elseif kind == "O" and pfDatabase.SearchObjectID then
    pfDatabase:SearchObjectID(id, meta)
    return true
  elseif kind == "I" and pfDatabase.SearchItemID then
    pfDatabase:SearchItemID(id, meta)
    return true
  elseif kind == "A" and pfDatabase.SearchAreaTriggerID then
    pfDatabase:SearchAreaTriggerID(id, meta)
    return true
  elseif kind == "Z" and pfDatabase.SearchZoneID then
    pfDatabase:SearchZoneID(id, meta)
    return true
  end

  return false
end

function Addon.AddGroupHoldNamedSources(kind, ids, names, need)
  local matched = 0
  local _
  local id
  local name

  for _, id in pairs(ids or {}) do
    name = names and names[id]
    if name and Addon.GroupHoldTextContainsName(need.objective.text, name) then
      if Addon.AddGroupHoldSource(kind, id, need) then
        matched = matched + 1
      end
    end
  end

  return matched
end

function Addon.AddSingleGroupHoldSource(kinds, objectives, need)
  local count = 0
  local soleKind
  local soleId
  local index
  local kind
  local _
  local id

  for index = 1, table.getn(kinds or {}) do
    kind = kinds[index]
    for _, id in pairs(objectives[kind] or {}) do
      count = count + 1
      soleKind = kind
      soleId = id
    end
  end

  if count == 1 and soleKind and soleId then
    return Addon.AddGroupHoldSource(soleKind, soleId, need) and 1 or 0
  end

  return 0
end

function Addon.FinalizeGroupHoldNodes(need)
  local maps
  local coords
  local titles
  local meta
  local _

  if not pfMap or not pfMap.nodes or not need then
    return
  end

  maps = pfMap.nodes["PFQGROUP"]
  if not maps then
    return
  end

  for _, coords in pairs(maps) do
    for _, titles in pairs(coords) do
      for _, meta in pairs(titles) do
        if meta and meta.pfqGroupNeedKey == need.key then
          meta.cluster = nil
        end
      end
    end
  end
end

function Addon.AddGroupHoldObjectiveNodes(need)
  local questID = tonumber(need and need.quest and need.quest.questID)
  local questData
  local objectives
  local objectiveType
  local matched = 0

  if not questID
    or not pfDB
    or not pfDB.quests
    or not pfDB.quests.data
    or not pfDB.quests.data[questID] then
    return false
  end

  questData = pfDB.quests.data[questID]
  objectives = questData and questData.obj
  if not objectives then
    return false
  end

  objectiveType = string.lower(SafeString(need.objective and need.objective.objectiveType))

  if objectiveType == "item" then
    matched = Addon.AddGroupHoldNamedSources("I", objectives.I, pfDB.items and pfDB.items.loc, need)
    if matched == 0 then matched = Addon.AddSingleGroupHoldSource({ "I" }, objectives, need) end
  elseif objectiveType == "monster" then
    matched = Addon.AddGroupHoldNamedSources("U", objectives.U, pfDB.units and pfDB.units.loc, need)
    matched = matched + Addon.AddGroupHoldNamedSources("O", objectives.O, pfDB.objects and pfDB.objects.loc, need)
    if matched == 0 then matched = Addon.AddSingleGroupHoldSource({ "U", "O" }, objectives, need) end
  else
    matched = Addon.AddGroupHoldNamedSources("O", objectives.O, pfDB.objects and pfDB.objects.loc, need)
    matched = matched + Addon.AddGroupHoldNamedSources("U", objectives.U, pfDB.units and pfDB.units.loc, need)
    matched = matched + Addon.AddGroupHoldNamedSources("I", objectives.I, pfDB.items and pfDB.items.loc, need)
    if matched == 0 then matched = Addon.AddSingleGroupHoldSource({ "O", "U", "I" }, objectives, need) end
    if matched == 0 then matched = Addon.AddSingleGroupHoldSource({ "A", "Z" }, objectives, need) end
  end

  if matched > 0 then
    Addon.FinalizeGroupHoldNodes(need)
    return true
  end

  return false
end

function Addon.RefreshGroupHoldNodes()
  local needs = Addon.groupHoldNeeds or {}
  local index

  Addon.ClearGroupHoldNodes()

  if not Addon.HasActiveGroupHoldPeer()
    or not pfMap
    or not pfDatabase
    or (pfQuest_config and pfQuest_config["trackingmethod"] == "4") then
    return
  end

  for index = 1, table.getn(needs) do
    Addon.AddGroupHoldObjectiveNodes(needs[index])
  end
end

function Addon.FindTooltipLocalQuest(meta)
  local numericQuestID = tonumber(meta and meta.questid)
  local title = SafeString(meta and meta.quest)
  local key
  local quest

  if not questState.ready or title == "" then
    return nil
  end

  if numericQuestID then
    quest = questState.quests[QuestKey(numericQuestID, title)]
    if quest then
      return quest
    end
  end

  for key, quest in pairs(questState.quests or {}) do
    if quest.title == title and (not numericQuestID or not quest.questID) then
      return quest
    end
  end

  return nil
end

function Addon.AppendGroupProgressTooltip(meta, tooltip)
  local localQuest = Addon.FindTooltipLocalQuest(meta)
  local peers = GetCompatibleGroupPeers()
  local sharedPeers = {}
  local localName = playerName or UnitName("player") or "Player"
  local _, localClassToken = UnitClass("player")
  local peerIndex
  local peerInfo
  local remoteQuest
  local objectiveIndex
  local localObjective
  local remoteObjective
  local progressText

  if not localQuest then
    return false
  end

  for peerIndex = 1, table.getn(peers) do
    peerInfo = peers[peerIndex]
    remoteQuest = FindRemoteTrackerQuest(peerInfo.questState, localQuest)
    if remoteQuest then
      peerInfo.remoteQuest = remoteQuest
      table.insert(sharedPeers, peerInfo)
    end
  end

  if table.getn(sharedPeers) == 0 then
    return false
  end

  tooltip = tooltip or GameTooltip
  tooltip:AddLine(" ")
  tooltip:AddLine(L.GROUP_PROGRESS_TOOLTIP or "Group Progress", 1, 0.82, 0)

  for objectiveIndex = 1, table.getn(localQuest.objectives or {}) do
    localObjective = localQuest.objectives[objectiveIndex]
    if localObjective then
      tooltip:AddLine("|cffffffff- " .. SafeString(localObjective.text) .. "|r", 1, 1, 1)
      tooltip:AddLine(
        "  |cff" .. GroupClassColorHex(localClassToken) .. SafeString(localName) .. ":|r "
          .. Addon.GroupHoldProgressText(localObjective),
        1, 1, 1
      )

      for peerIndex = 1, table.getn(sharedPeers) do
        peerInfo = sharedPeers[peerIndex]
        remoteObjective = peerInfo.remoteQuest
          and peerInfo.remoteQuest.objectives
          and peerInfo.remoteQuest.objectives[objectiveIndex]
        if remoteObjective then
          progressText = Addon.GroupHoldProgressText(remoteObjective)
        else
          progressText = "|cffaaaaaa--|r"
        end
        tooltip:AddLine(
          "  |cff" .. GroupClassColorHex(peerInfo.classToken) .. SafeString(peerInfo.name) .. ":|r "
            .. progressText,
          1, 1, 1
        )
      end
    end
  end

  tooltip:Show()
  return true
end

function Addon.ShowGroupHoldTooltip(meta, tooltip)
  local need = meta and Addon.groupHoldNeedByKey and Addon.groupHoldNeedByKey[meta.pfqGroupNeedKey]
  local localName = playerName or UnitName("player") or "Player"
  local _, localClassToken = UnitClass("player")
  local localObjective
  local rows
  local index
  local row

  tooltip = tooltip or GameTooltip
  if not need then
    return
  end

  tooltip:AddLine("|cffffd100" .. SafeString(need.quest.title) .. "|r", 1, 1, 1)
  tooltip:AddLine("|cffffffff- " .. SafeString(need.objective.text) .. "|r", 1, 1, 1)

  localObjective = Addon.GroupHoldLocalObjective(need)
  tooltip:AddLine("  |cff" .. GroupClassColorHex(localClassToken) .. SafeString(localName) .. ":|r " .. Addon.GroupHoldProgressText(localObjective), 1, 1, 1)

  rows = Addon.GetGroupHoldParticipantRows(need)
  for index = 1, table.getn(rows) do
    row = rows[index]
    tooltip:AddLine("  |cff" .. GroupClassColorHex(row.classToken) .. SafeString(row.name) .. ":|r " .. Addon.GroupHoldProgressText(row.objective), 1, 1, 1)
  end

  tooltip:Show()
end

function Addon.InstallGroupHoldMapTooltip()
  if Addon.groupHoldMapTooltipInstalled then
    return true
  end

  if not pfMap or type(pfMap.ShowTooltip) ~= "function" then
    return false
  end

  Addon.originalGroupHoldShowTooltip = pfMap.ShowTooltip
  pfMap.ShowTooltip = function(self, meta, tooltip)
    local result

    if meta and meta.addon == "PFQGROUP" then
      return Addon.ShowGroupHoldTooltip(meta, tooltip)
    end

    result = Addon.originalGroupHoldShowTooltip(self, meta, tooltip)
    if meta and meta.quest then
      Addon.AppendGroupProgressTooltip(meta, tooltip)
    end
    return result
  end

  Addon.groupHoldMapTooltipInstalled = true
  return true
end

function Addon.RefreshGroupHoldPresentation()
  local needs
  local index

  if not Addon.db then
    return
  end

  Addon.SyncGroupHoldSession()
  Addon.MarkGroupHoldLocalState()
  needs = Addon.BuildGroupHoldNeeds()
  Addon.groupHoldNeeds = needs
  Addon.groupHoldNeedByKey = {}

  for index = 1, table.getn(needs) do
    Addon.groupHoldNeedByKey[needs[index].key] = needs[index]
  end

  Addon.RefreshGroupHoldTracker()
  Addon.RefreshGroupHoldNodes()
  RelayoutGroupTracker()
end

function Addon.HandleGroupHoldRemoteSession(sender, remoteSession)
  Addon.UpdateGroupHoldParticipantSession(sender, remoteSession)
  Addon.RefreshGroupHoldPresentation()
end

function Addon.HandleGroupHoldRemoteQuest(sender, remoteState)
  Addon.UpdateGroupHoldParticipantQuest(sender, remoteState)
  Addon.RefreshGroupHoldPresentation()
end

function Addon.HandleGroupHoldLocalState()
  Addon.SyncGroupHoldSession()
  Addon.RefreshGroupHoldPresentation()
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
    npcName = source.npcName,
    flightName = source.flightName
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
  local actionCode = instruction.actionType == "ACCEPT"
    and "A"
    or (instruction.actionType == "TURNIN" and "T" or "F")

  return table.concat({
    "I",
    SafeString(instruction.seq or 0),
    actionCode,
    SafeString(instruction.questID or 0),
    SafeString(instruction.mobID or 0),
    HexEncode(instruction.questTitle),
    HexEncode(instruction.npcName),
    HexEncode(instruction.flightName)
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
  local flightName

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
  elseif fields[3] == "F" then
    actionType = "FLIGHT"
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
  flightName = HexDecode(fields[8] or "")

  if actionType == "FLIGHT" then
    if flightName == "" then
      return nil
    end
    questID = nil
    mobID = nil
    questTitle = ""
    npcName = ""
  elseif not questID and questTitle == "" then
    return nil
  end

  return {
    seq = seq,
    actionType = actionType,
    questID = questID,
    questTitle = questTitle,
    mobID = mobID,
    npcName = npcName,
    flightName = flightName
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

local function EncodeInstructionCompletionWire(kind, guideSessionId, consumed)
  local output = {
    kind .. "." .. HexEncode(guideSessionId or "") .. ".0"
  }
  local keys = {}
  local key
  local seq
  local index

  for key in pairs(consumed or {}) do
    seq = tonumber(key)
    if consumed[key] and seq and seq >= 1 then
      table.insert(keys, math.floor(seq))
    end
  end
  table.sort(keys)

  for index = 1, table.getn(keys) do
    table.insert(output, "K." .. SafeString(keys[index]))
  end

  return table.concat(output, "_")
end

local function DecodeInstructionCompletionWire(payload, expectedKind)
  local records = SplitPlain(payload, "_")
  local header = records[1] and SplitPlain(records[1], ".") or nil
  local decoded = {
    sessionId = nil,
    consumed = {}
  }
  local index
  local fields
  local seq

  if not header or header[1] ~= expectedKind or table.getn(header) < 3 or tonumber(header[3]) ~= 0 then
    return nil
  end

  decoded.sessionId = HexDecode(header[2])
  if decoded.sessionId == "" then
    decoded.sessionId = nil
  end

  for index = 2, table.getn(records) do
    if records[index] ~= "" then
      fields = SplitPlain(records[index], ".")
      seq = fields and tonumber(fields[2]) or nil
      if not fields or fields[1] ~= "K" or table.getn(fields) < 2 or not seq or seq < 1 then
        return nil
      end
      seq = math.floor(seq)
      if decoded.consumed[seq] then
        return nil
      end
      decoded.consumed[seq] = true
    end
  end

  return decoded
end

local function InstructionSnapshot()
  local session = Addon.db and Addon.db.session
  local store = Addon.db and Addon.db.instructions

  if session and session.mode == "GUIDE" and session.guideSessionId and store and store.guideSessionId == session.guideSessionId then
    local pending = {}
    local seq
    local instruction

    for seq, instruction in pairs(store.guideRecords or {}) do
      seq = tonumber(seq)
      if seq
        and not (store.guideCompleted and store.guideCompleted[seq])
        and not (store.guideRemoved and store.guideRemoved[seq]) then
        pending[seq] = instruction
      end
    end

    return EncodeInstructionWire("S", session.guideSessionId, tonumber(session.guideActionSeq) or 0, pending)
  end

  if session and session.mode == "TOURIST" and session.guideSessionId and store and store.touristSessionId == session.guideSessionId then
    return EncodeInstructionCompletionWire("C", session.guideSessionId, store.consumed)
  end

  return EncodeInstructionCompletionWire("C", nil, {})
end

local function InstructionMatchesAction(instruction, actionType, quest, context)
  local actionQuestID
  local actionTitle
  local flightName

  if not instruction or instruction.actionType ~= actionType then
    return false
  end

  if actionType == "FLIGHT" then
    flightName = Trim(SafeString(context and context.flightName))
    return instruction.flightName ~= ""
      and flightName ~= ""
      and instruction.flightName == flightName
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

local function FilterRemoteInstructionCompletions(peer, sessionId, consumed)
  local output = {}
  local localSession = Addon.db and Addon.db.session
  local remoteSession = peer and peer.session
  local store = Addon.db and Addon.db.instructions
  local baseline
  local cursor
  local seq

  if not localSession
    or localSession.mode ~= "GUIDE"
    or not localSession.guideSessionId
    or sessionId ~= localSession.guideSessionId
    or not remoteSession
    or remoteSession.mode ~= "TOURIST"
    or NormalizeName(remoteSession.guideName) ~= NormalizeName(playerName)
    or remoteSession.guideSessionId ~= localSession.guideSessionId
    or remoteSession.joinBaseline == nil
    or not store
    or store.guideSessionId ~= localSession.guideSessionId then
    return nil
  end

  baseline = tonumber(remoteSession.joinBaseline) or 0
  cursor = tonumber(localSession.guideActionSeq) or 0

  for seq in pairs(consumed or {}) do
    seq = tonumber(seq)
    if seq
      and seq > baseline
      and seq <= cursor
      and store.guideRecords
      and store.guideRecords[seq]
      and not (store.guideRemoved and store.guideRemoved[seq]) then
      output[seq] = true
    end
  end

  return output
end

local function ApplyRemoteInstructionCompletionFull(sender, decoded)
  local senderKey = NormalizeName(sender)
  local peer = senderKey and peers[senderKey]
  local filtered
  local seq

  if not peer or not decoded then
    return
  end

  if not decoded.sessionId then
    peer.instructionCompletions = nil
    Emit("REMOTE_INSTRUCTION_COMPLETIONS_CHANGED", sender, nil)
    return
  end

  filtered = FilterRemoteInstructionCompletions(peer, decoded.sessionId, decoded.consumed)
  if not filtered then
    return
  end

  if not peer.instructionCompletions or peer.instructionCompletions.sessionId ~= decoded.sessionId then
    peer.instructionCompletions = {
      sessionId = decoded.sessionId,
      consumed = {}
    }
  end

  for seq in pairs(filtered) do
    peer.instructionCompletions.consumed[seq] = true
  end

  Addon.RecordGuideInstructionCompletions(sender, decoded.sessionId, filtered)
  Emit("REMOTE_INSTRUCTION_COMPLETIONS_CHANGED", sender, peer.instructionCompletions)
end

local function ApplyRemoteInstructionCompletionDelta(sender, payload)
  local decoded = DecodeInstructionCompletionWire(payload, "A")
  local senderKey = NormalizeName(sender)
  local peer = senderKey and peers[senderKey]
  local filtered
  local seq
  local changed = false

  if not decoded or not decoded.sessionId or not peer then
    return
  end

  filtered = FilterRemoteInstructionCompletions(peer, decoded.sessionId, decoded.consumed)
  if not filtered then
    return
  end

  if not peer.instructionCompletions or peer.instructionCompletions.sessionId ~= decoded.sessionId then
    peer.instructionCompletions = {
      sessionId = decoded.sessionId,
      consumed = {}
    }
  end

  for seq in pairs(filtered) do
    if not peer.instructionCompletions.consumed[seq] then
      peer.instructionCompletions.consumed[seq] = true
      changed = true
    end
  end

  Addon.RecordGuideInstructionCompletions(sender, decoded.sessionId, filtered)
  if changed then
    Emit("REMOTE_INSTRUCTION_COMPLETIONS_CHANGED", sender, peer.instructionCompletions)
  end
end

local function ApplyRemoteInstructionFull(sender, payload)
  local decoded = DecodeInstructionWire(payload, "S")
  local completionDecoded
  local senderKey = NormalizeName(sender)
  local peer = senderKey and peers[senderKey]
  local remoteSession

  if not peer then
    return
  end

  if not decoded then
    completionDecoded = DecodeInstructionCompletionWire(payload, "C")
    if completionDecoded then
      ApplyRemoteInstructionCompletionFull(sender, completionDecoded)
    end
    return
  end

  remoteSession = peer.session
  if remoteSession then
    if remoteSession.mode == "GUIDE" and remoteSession.guideSessionId then
      if decoded.sessionId ~= remoteSession.guideSessionId then
        return
      end
    elseif decoded.sessionId then
      return
    end
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

  if not peer then
    return
  end

  if not decoded then
    ApplyRemoteInstructionCompletionDelta(sender, payload)
    return
  end

  if not decoded.sessionId then
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

local function ApplyRemoteSession(sender, payload, checkInstructionSync)
  local values = DecodeMap(payload)
  local mode = values.mode
  local senderKey = NormalizeName(sender)
  local peer = senderKey and peers[senderKey]
  local revision
  local guideName
  local guideSessionId
  local joinBaseline
  local guideActionSeq
  local localSession
  local remoteInstructions
  local remoteInstructionCursor

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
    peer.instructionCompletions = nil
  elseif mode == "GUIDE" then
    guideName = nil
    joinBaseline = nil
    peer.instructionCompletions = nil
    if peer.instructions and peer.instructions.sessionId ~= guideSessionId then
      peer.instructions = nil
    end
  else
    peer.instructions = nil
    guideActionSeq = nil
    if not guideSessionId then
      joinBaseline = nil
    end
    if peer.instructionCompletions and peer.instructionCompletions.sessionId ~= guideSessionId then
      peer.instructionCompletions = nil
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

  Addon.UpdateGuideParticipant(sender, peer.session)
  Emit("REMOTE_SESSION_CHANGED", sender, peer.session)
  ReconcileTouristPairing(sender)
  ReconcileTouristInstructions(sender)

  if checkInstructionSync and mode == "GUIDE" and guideSessionId and guideActionSeq and guideActionSeq > 0 then
    localSession = Addon.db and Addon.db.session
    if localSession
      and localSession.mode == "TOURIST"
      and NormalizeName(localSession.guideName) == senderKey
      and localSession.guideSessionId == guideSessionId
      and localSession.joinBaseline ~= nil
      and guideActionSeq > localSession.joinBaseline then
      remoteInstructions = peer.instructions
      remoteInstructionCursor = remoteInstructions and remoteInstructions.sessionId == guideSessionId and tonumber(remoteInstructions.cursor) or nil
      if not remoteInstructionCursor or remoteInstructionCursor < guideActionSeq then
        Addon.RequestFullSync(sender)
      end
    end
  end
end

local function ApplyRemoteSessionFull(sender, payload)
  ApplyRemoteSession(sender, payload, false)
end

local function ApplyRemoteSessionDelta(sender, payload)
  ApplyRemoteSession(sender, payload, true)
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

function Addon.HasCompatiblePeer(target)
  local normalized
  local peer

  if target then
    normalized = NormalizeName(target)
    peer = normalized and peers[normalized]
    return normalized
      and party[normalized] ~= nil
      and peer
      and peer.compatible
      and true
      or false
  end

  for normalized, peer in pairs(peers) do
    if party[normalized] and peer and peer.compatible then
      return true
    end
  end

  return false
end

function Addon.SendDelta(componentName, payload, target)
  if not components[componentName] or not Addon.HasCompatiblePeer(target) then
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
  local pending = {}
  local seq
  local instruction

  if not session or session.mode ~= "GUIDE" or not store or store.guideSessionId ~= session.guideSessionId then
    return {}
  end

  for seq, instruction in pairs(store.guideRecords or {}) do
    seq = tonumber(seq)
    if seq
      and not (store.guideCompleted and store.guideCompleted[seq])
      and not (store.guideRemoved and store.guideRemoved[seq]) then
      pending[seq] = instruction
    end
  end

  return CopyInstructionList(pending)
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

function Addon.GuideHasActiveTourist(session)
  local guideKey
  local normalized
  local peer
  local remoteSession

  session = session or (Addon.db and Addon.db.session)
  if not session or session.mode ~= "GUIDE" or not session.guideSessionId then
    return false
  end

  guideKey = NormalizeName(playerName)
  for normalized in pairs(party) do
    peer = peers[normalized]
    remoteSession = peer and peer.session
    if peer
      and peer.compatible
      and remoteSession
      and remoteSession.mode == "TOURIST"
      and NormalizeName(remoteSession.guideName) == guideKey
      and remoteSession.guideSessionId == session.guideSessionId
      and remoteSession.joinBaseline ~= nil then
      return true
    end
  end

  return false
end

function Addon.UpdateGuideParticipant(sender, remoteSession)
  local session = Addon.db and Addon.db.session
  local store = Addon.db and Addon.db.instructions
  local senderKey
  local guideKey
  local baseline
  local seq
  local changed = false

  if not session
    or session.mode ~= "GUIDE"
    or not session.guideSessionId
    or not store
    or store.guideSessionId ~= session.guideSessionId then
    return false
  end

  senderKey = NormalizeName(sender)
  if not senderKey then
    return false
  end

  guideKey = NormalizeName(playerName)
  if remoteSession
    and remoteSession.mode == "TOURIST"
    and NormalizeName(remoteSession.guideName) == guideKey
    and remoteSession.guideSessionId == session.guideSessionId
    and remoteSession.joinBaseline ~= nil then
    baseline = math.floor(tonumber(remoteSession.joinBaseline) or 0)
    if store.guideParticipants[senderKey] ~= baseline then
      store.guideParticipants[senderKey] = baseline
      changed = true
    end

    -- Schema-1 sessions have no authoritative historical roster. Recover
    -- provable legacy eligibility from fixed baselines, but leave those
    -- rows non-finalizable because an offline historical Tourist may be
    -- unknowable until it returns.
    for seq in pairs(store.guideRecords or {}) do
      seq = tonumber(seq)
      if seq
        and seq > baseline
        and not (store.guideEligibilityKnown and store.guideEligibilityKnown[seq]) then
        store.guideEligible[seq] = store.guideEligible[seq] or {}
        if not store.guideEligible[seq][senderKey] then
          store.guideEligible[seq][senderKey] = true
          changed = true
        end
      end
    end
  elseif store.guideParticipants[senderKey] ~= nil then
    -- Explicit unpairing affects future instructions only. Existing
    -- per-instruction eligibility snapshots remain immutable.
    store.guideParticipants[senderKey] = nil
    changed = true
  end

  return changed
end

function Addon.CaptureGuideInstructionEligibility(session, seq)
  local store = Addon.db and Addon.db.instructions
  local guideKey
  local normalized
  local peer
  local remoteSession
  local baseline
  local name
  local eligible = {}

  seq = tonumber(seq)
  if not session
    or session.mode ~= "GUIDE"
    or not session.guideSessionId
    or not seq
    or not store
    or store.guideSessionId ~= session.guideSessionId then
    return false
  end
  seq = math.floor(seq)

  guideKey = NormalizeName(playerName)
  for normalized in pairs(party) do
    peer = peers[normalized]
    remoteSession = peer and peer.session
    if peer
      and peer.compatible
      and remoteSession
      and remoteSession.mode == "TOURIST"
      and NormalizeName(remoteSession.guideName) == guideKey
      and remoteSession.guideSessionId == session.guideSessionId
      and remoteSession.joinBaseline ~= nil then
      store.guideParticipants[normalized] = math.floor(tonumber(remoteSession.joinBaseline) or 0)
    end
  end

  for name, baseline in pairs(store.guideParticipants or {}) do
    baseline = tonumber(baseline)
    if baseline and seq > baseline then
      eligible[name] = true
    end
  end

  store.guideEligible[seq] = eligible
  store.guideAcknowledged[seq] = {}
  store.guideCompleted[seq] = nil
  store.guideEligibilityKnown[seq] = true
  return next(eligible) ~= nil
end

function Addon.RecordGuideInstructionCompletions(sender, sessionId, consumed)
  local session = Addon.db and Addon.db.session
  local store = Addon.db and Addon.db.instructions
  local senderKey
  local seq
  local eligible
  local acknowledged
  local name
  local hasEligible
  local allAcknowledged
  local instruction
  local changed = false

  if not session
    or session.mode ~= "GUIDE"
    or not session.guideSessionId
    or sessionId ~= session.guideSessionId
    or not store
    or store.guideSessionId ~= session.guideSessionId then
    return false
  end

  senderKey = NormalizeName(sender)
  if not senderKey then
    return false
  end

  for seq in pairs(consumed or {}) do
    seq = tonumber(seq)
    eligible = seq and store.guideEligible and store.guideEligible[seq]
    if seq
      and eligible
      and eligible[senderKey]
      and not (store.guideRemoved and store.guideRemoved[seq]) then
      acknowledged = store.guideAcknowledged[seq] or {}
      store.guideAcknowledged[seq] = acknowledged
      if not acknowledged[senderKey] then
        acknowledged[senderKey] = true
        changed = true
      end

      if store.guideEligibilityKnown and store.guideEligibilityKnown[seq] and not store.guideCompleted[seq] then
        hasEligible = false
        allAcknowledged = true
        for name in pairs(eligible) do
          hasEligible = true
          if not acknowledged[name] then
            allAcknowledged = false
          end
        end

        if hasEligible and allAcknowledged then
          store.guideCompleted[seq] = true
          instruction = store.guideRecords and store.guideRecords[seq]
          if instruction then
            Emit("GUIDE_INSTRUCTION_COMPLETED", CopyInstruction(instruction))
          end
          changed = true
        end
      end
    end
  end

  if changed then
    Emit("GUIDE_INSTRUCTIONS_CHANGED", Addon.GetGuideInstructions())
  end
  return changed
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

local function CompleteTouristInstruction(seq)
  local session = Addon.db and Addon.db.session
  local instruction
  local store

  seq = tonumber(seq)
  if not session
    or session.mode ~= "TOURIST"
    or not session.guideSessionId
    or session.joinBaseline == nil
    or not seq
    or seq < 1 then
    return false
  end

  seq = math.floor(seq)
  instruction = touristPendingInstructions[seq]
  if not instruction then
    return false
  end

  Addon.db.instructions = NormalizeInstructionStore(Addon.db.instructions, session)
  store = Addon.db.instructions
  store.consumed[seq] = true
  touristPendingInstructions[seq] = nil
  Addon.SendDelta("instructions", EncodeInstructionCompletionWire("A", session.guideSessionId, {
    [seq] = true
  }), session.guideName)
  Emit("TOURIST_INSTRUCTION_COMPLETED", CopyInstruction(instruction))
  Emit("TOURIST_INSTRUCTIONS_CHANGED", Addon.GetTouristInstructions())
  return true
end

function Addon.CreateGuideInstruction(record)
  local session = Addon.db and Addon.db.session
  local store
  local seq
  local instruction

  if not session
    or session.mode ~= "GUIDE"
    or not session.guideSessionId
    or not Addon.GuideHasActiveTourist(session) then
    return false
  end

  seq = (tonumber(session.guideActionSeq) or 0) + 1
  record = record or {}
  record.seq = seq
  instruction = NormalizeInstructionRecord(record, seq)
  if not instruction then
    return false
  end

  session.guideActionSeq = seq
  Addon.db.instructions = NormalizeInstructionStore(Addon.db.instructions, session)
  store = Addon.db.instructions
  store.guideSessionId = session.guideSessionId
  store.guideRecords[seq] = instruction
  store.guideRemoved[seq] = nil
  Addon.CaptureGuideInstructionEligibility(session, seq)
  session.revision = session.revision + 1
  Addon.SendDelta("instructions", EncodeInstructionWire("D", session.guideSessionId, seq, {
    [seq] = instruction
  }))
  BroadcastSessionDelta()
  Emit("SESSION_CHANGED", Addon.GetSession())
  Emit("GUIDE_INSTRUCTION_CREATED", CopyInstruction(instruction))
  Emit("GUIDE_INSTRUCTIONS_CHANGED", Addon.GetGuideInstructions())
  return true
end

function Addon.RemoveGuideInstruction(seq)
  local session = Addon.db and Addon.db.session
  local store = Addon.db and Addon.db.instructions

  seq = tonumber(seq)
  if not session
    or session.mode ~= "GUIDE"
    or not session.guideSessionId
    or not store
    or store.guideSessionId ~= session.guideSessionId
    or not seq then
    return false
  end

  seq = math.floor(seq)
  if not store.guideRecords
    or not store.guideRecords[seq]
    or (store.guideCompleted and store.guideCompleted[seq])
    or (store.guideRemoved and store.guideRemoved[seq]) then
    return false
  end

  store.guideRemoved = store.guideRemoved or {}
  store.guideRemoved[seq] = true
  guideTouristUI.completing[seq] = nil
  guideTouristUI.completed[seq] = nil

  -- Removal changes the authoritative pending instruction set without
  -- advancing the Guide action cursor. A full state snapshot is therefore
  -- the existing protocol-v3 representation of the new set.
  if Addon.HasCompatiblePeer() then
    SendFullState()
  end

  Emit("GUIDE_INSTRUCTIONS_CHANGED", Addon.GetGuideInstructions())
  return true
end

local function HandleInstructionQuestAction(actionType, quest, context)
  local session = Addon.db and Addon.db.session
  local instruction
  local pendingSeq
  local candidateSeq
  local candidate

  if not session or (actionType ~= "ACCEPT" and actionType ~= "TURNIN") then
    return
  end

  if session.mode == "GUIDE" and session.guideSessionId then
    Addon.CreateGuideInstruction({
      actionType = actionType,
      questID = tonumber(context and context.questID) or tonumber(quest and quest.questID),
      questTitle = SafeString((context and context.questTitle) or (quest and quest.title)),
      mobID = tonumber(context and context.mobID),
      npcName = SafeString(context and context.npcName)
    })
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

  CompleteTouristInstruction(pendingSeq)
end

function Addon.HandleFlightAction(flightName)
  local session = Addon.db and Addon.db.session
  local pendingSeq
  local candidateSeq
  local candidate

  flightName = Trim(SafeString(flightName))
  if not session or flightName == "" then
    return false
  end

  if session.mode == "GUIDE" and session.guideSessionId then
    return Addon.CreateGuideInstruction({
      actionType = "FLIGHT",
      flightName = flightName
    })
  end

  if session.mode ~= "TOURIST" or not session.guideSessionId or session.joinBaseline == nil then
    return false
  end

  for candidateSeq, candidate in pairs(touristPendingInstructions) do
    candidateSeq = tonumber(candidateSeq)
    if candidateSeq
      and InstructionMatchesAction(candidate, "FLIGHT", nil, {
        flightName = flightName
      }) then
      if not pendingSeq or candidateSeq < pendingSeq then
        pendingSeq = candidateSeq
      end
    end
  end

  if not pendingSeq then
    return false
  end

  return CompleteTouristInstruction(pendingSeq)
end


local function GuideTouristNpcDisplayName(instruction, npcName)
  local mobID = tonumber(instruction and instruction.mobID)
  local unitData
  local npcLevel
  local color
  local red
  local green
  local colorCode

  if npcName == "" or not mobID then
    return npcName
  end

  if pfDB and pfDB.units and pfDB.units.data then
    unitData = pfDB.units.data[mobID]
  end
  npcLevel = tonumber(unitData and unitData.lvl)
  if not npcLevel then
    return npcName
  end

  if pfQuestCompat and type(pfQuestCompat.GetDifficultyColor) == "function" then
    color = pfQuestCompat.GetDifficultyColor(npcLevel)
  elseif type(GetQuestDifficultyColor) == "function" then
    color = GetQuestDifficultyColor(npcLevel)
  end
  if not color then
    return npcName
  end

  red = tonumber(color.r) or 0
  green = tonumber(color.g) or 0
  if red >= 0.9 then
    if green < 0.3 then
      colorCode = "|cffff3333"
    elseif green < 0.9 then
      colorCode = "|cffff8040"
    else
      colorCode = "|cffffff00"
    end
  else
    -- The requested panel palette has no gray/trivial state, so lower
    -- difficulty NPCs intentionally fold into green.
    colorCode = "|cff40bf40"
  end

  return colorCode .. npcName .. "|r"
end

local function GuideTouristInstructionText(instruction)
  local text
  local fullText
  local markerText
  local markerAt
  local marker = instruction and instruction.actionType == "ACCEPT" and "!" or "?"
  local npcName = Trim(SafeString(instruction and instruction.npcName))

  if instruction and instruction.actionType == "FLIGHT" then
    return string.format(
      L.INSTRUCTION_FLIGHT or "|cffffd100Fly|r to %s",
      SafeString(instruction.flightName)
    )
  end
  local shortNPC = npcName
  local initials = ""
  local startAt
  local spaceAt
  local word
  local lastWord

  if string.len(npcName) > 18 then
    startAt = 1
    while startAt <= string.len(npcName) do
      spaceAt = string.find(npcName, " ", startAt)
      if not spaceAt then
        lastWord = string.sub(npcName, startAt)
        break
      end

      word = string.sub(npcName, startAt, spaceAt - 1)
      if word ~= "" then
        initials = initials .. string.sub(word, 1, 1) .. "."
      end

      startAt = spaceAt + 1
      while startAt <= string.len(npcName) and string.sub(npcName, startAt, startAt) == " " do
        startAt = startAt + 1
      end
    end

    if initials ~= "" and lastWord and lastWord ~= "" then
      shortNPC = initials .. " " .. lastWord
    end
  end

  if instruction and instruction.questTitle and instruction.questTitle ~= "" then
    text = instruction.questTitle
  else
    text = string.format(L.QUEST_ID_FALLBACK or "Quest %d", tonumber(instruction and instruction.questID) or 0)
  end

  if shortNPC ~= "" then
    shortNPC = GuideTouristNpcDisplayName(instruction, shortNPC)
    fullText = string.format(L.INSTRUCTION_WITH_NPC or "%s |cffffd100%s|r %s", shortNPC, marker, text)
  else
    fullText = string.format(L.INSTRUCTION_WITHOUT_NPC or "|cffffd100%s|r %s", marker, text)
  end

  markerText = "|cffffd100" .. marker .. "|r"
  markerAt = string.find(fullText, markerText, 1, true)
  if markerAt then
    return fullText,
      string.sub(fullText, 1, markerAt - 1),
      marker,
      string.sub(fullText, markerAt + string.len(markerText))
  end

  return fullText
end

local function GuideInstructionAllTouristsComplete(session, instruction)
  local seq = tonumber(instruction and instruction.seq)
  local store = Addon.db and Addon.db.instructions
  local guideKey
  local eligible = 0
  local completed = 0
  local partyIndex
  local unit
  local name
  local normalized
  local member
  local peer
  local remoteSession
  local completionState

  if not session
    or session.mode ~= "GUIDE"
    or not session.guideSessionId
    or not seq
    or not store
    or store.guideSessionId ~= session.guideSessionId then
    return false
  end

  if store.guideCompleted and store.guideCompleted[seq] then
    return true
  end

  -- Fresh schema-2+ instructions have a fixed durable eligibility cohort.
  -- Only historical rows whose eligibility could not be reconstructed use
  -- the legacy live-party completion fallback.
  if store.guideEligibilityKnown and store.guideEligibilityKnown[seq] then
    return false
  end

  guideKey = NormalizeName(playerName)
  for partyIndex = 1, 4 do
    unit = "party" .. partyIndex
    if UnitExists(unit) then
      name = UnitName(unit)
      normalized = NormalizeName(name)
      member = normalized and party[normalized]
      peer = normalized and peers[normalized]
      remoteSession = peer and peer.session

      if member
        and peer
        and peer.compatible
        and remoteSession
        and remoteSession.mode == "TOURIST"
        and NormalizeName(remoteSession.guideName) == guideKey
        and remoteSession.guideSessionId == session.guideSessionId
        and remoteSession.joinBaseline ~= nil
        and seq > remoteSession.joinBaseline then
        eligible = eligible + 1
        completionState = peer.instructionCompletions
        if completionState
          and completionState.sessionId == session.guideSessionId
          and completionState.consumed
          and completionState.consumed[seq] then
          completed = completed + 1
        end
      end
    end
  end

  if eligible > 0 and completed == eligible then
    store.guideCompleted = store.guideCompleted or {}
    store.guideCompleted[seq] = true
    return true
  end

  return false
end

local function GuideDisparityKey(peerName, quest)
  local questKey = quest and quest.key

  if not questKey or questKey == "" then
    questKey = QuestKey(quest and quest.questID, quest and quest.title)
  end

  return SafeString(NormalizeName(peerName)) .. "|" .. SafeString(questKey)
end

local function BuildGuideDisparities(session)
  local output = {}
  local hidden
  local guideKey
  local partyIndex
  local unit
  local name
  local normalized
  local member
  local peer
  local remoteSession
  local questKey
  local quest
  local disparityKey

  if not session or session.mode ~= "GUIDE" or not session.guideSessionId or not questState.ready then
    return output
  end

  hidden = Addon.db and Addon.db.session and Addon.db.session.hiddenDisparities or {}
  guideKey = NormalizeName(playerName)

  for partyIndex = 1, 4 do
    unit = "party" .. partyIndex
    if UnitExists(unit) then
      name = UnitName(unit)
      normalized = NormalizeName(name)
      member = normalized and party[normalized]
      peer = normalized and peers[normalized]
      remoteSession = peer and peer.session

      if member
        and peer
        and peer.compatible
        and remoteSession
        and remoteSession.mode == "TOURIST"
        and NormalizeName(remoteSession.guideName) == guideKey
        and remoteSession.guideSessionId == session.guideSessionId
        and remoteSession.joinBaseline ~= nil
        and peer.questState
        and peer.questState.ready then
        for questKey, quest in pairs(questState.quests or {}) do
          if not FindRemoteTrackerQuest(peer.questState, quest) then
            disparityKey = GuideDisparityKey(peer.name or member.name or name, quest)
            table.insert(output, {
              key = disparityKey,
              partyIndex = partyIndex,
              playerName = peer.name or member.name or name,
              quest = quest,
              hidden = hidden[disparityKey] and true or false
            })
          end
        end
      end
    end
  end

  table.sort(output, function(left, right)
    local leftTitle
    local rightTitle

    if left.partyIndex ~= right.partyIndex then
      return left.partyIndex < right.partyIndex
    end

    leftTitle = string.lower(SafeString(left.quest and left.quest.title))
    rightTitle = string.lower(SafeString(right.quest and right.quest.title))
    if leftTitle ~= rightTitle then
      return leftTitle < rightTitle
    end

    return SafeString(left.key) < SafeString(right.key)
  end)

  return output
end

local function SetGuideDisparityHidden(disparityKey, hidden)
  local session = Addon.db and Addon.db.session

  if not session or session.mode ~= "GUIDE" or not disparityKey or disparityKey == "" then
    return
  end

  if type(session.hiddenDisparities) ~= "table" then
    session.hiddenDisparities = {}
  end

  if hidden then
    session.hiddenDisparities[disparityKey] = true
  else
    session.hiddenDisparities[disparityKey] = nil
  end

  if guideTouristUI.refresh then
    guideTouristUI.refresh()
  end
end

local function SingleObjectiveAlertText(quest, objective)
  local text = Trim(SafeString(objective and objective.text))

  if text ~= "" then
    return text
  end

  return SafeString(quest and quest.title)
end

local function BuildGuideSingleObjectiveAlerts(session)
  local output = {}
  local guideKey
  local questKey
  local quest
  local objectiveIndex
  local objective
  local participants
  local allComplete
  local partyIndex
  local unit
  local name
  local normalized
  local member
  local peer
  local remoteSession
  local remoteQuest
  local remoteObjective

  if not session
    or session.mode ~= "GUIDE"
    or not session.guideSessionId
    or not questState.ready then
    return output
  end

  guideKey = NormalizeName(playerName)

  for questKey, quest in pairs(questState.quests or {}) do
    for objectiveIndex = 1, table.getn(quest.objectives or {}) do
      objective = quest.objectives[objectiveIndex]
      if IsSharedSingleObjective(objective) and SingleObjectiveDone(objective) then
        participants = {}
        allComplete = true

        for partyIndex = 1, 4 do
          unit = "party" .. partyIndex
          if UnitExists(unit) then
            name = UnitName(unit)
            normalized = NormalizeName(name)
            member = normalized and party[normalized]
            peer = normalized and peers[normalized]
            remoteSession = peer and peer.session

            if member
              and peer
              and peer.compatible
              and remoteSession
              and remoteSession.mode == "TOURIST"
              and NormalizeName(remoteSession.guideName) == guideKey
              and remoteSession.guideSessionId == session.guideSessionId
              and remoteSession.joinBaseline ~= nil
              and peer.questState
              and peer.questState.ready then
              remoteQuest = FindRemoteTrackerQuest(peer.questState, quest)
              remoteObjective = remoteQuest and FindQuestObjective(remoteQuest, objective.index or objectiveIndex)
              if remoteObjective and IsSharedSingleObjective(remoteObjective) then
                table.insert(participants, {
                  partyIndex = partyIndex,
                  name = peer.name or member.name or name,
                  complete = SingleObjectiveDone(remoteObjective)
                })
                if not SingleObjectiveDone(remoteObjective) then
                  allComplete = false
                end
              end
            end
          end
        end

        if table.getn(participants) > 0 then
          table.insert(output, {
            key = SafeString(quest.key or questKey) .. "#" .. SafeString(objective.index or objectiveIndex),
            quest = quest,
            objective = objective,
            text = SingleObjectiveAlertText(quest, objective),
            participants = participants,
            complete = allComplete
          })
        end
      end
    end
  end

  table.sort(output, function(left, right)
    local leftTitle = string.lower(SafeString(left.quest and left.quest.title))
    local rightTitle = string.lower(SafeString(right.quest and right.quest.title))

    if leftTitle ~= rightTitle then
      return leftTitle < rightTitle
    end

    return SafeString(left.key) < SafeString(right.key)
  end)

  return output
end

local function BuildTouristSingleObjectiveAlerts(session)
  local output = {}
  local guideKey
  local peer
  local remoteSession
  local questKey
  local guideQuest
  local localQuest
  local objectiveIndex
  local guideObjective
  local localObjective

  if not session
    or session.mode ~= "TOURIST"
    or not session.guideName
    or not session.guideSessionId
    or session.joinBaseline == nil
    or not questState.ready then
    return output
  end

  guideKey = NormalizeName(session.guideName)
  peer = guideKey and peers[guideKey]
  remoteSession = peer and peer.session
  if not peer
    or not peer.compatible
    or not remoteSession
    or remoteSession.mode ~= "GUIDE"
    or remoteSession.guideSessionId ~= session.guideSessionId
    or not peer.questState
    or not peer.questState.ready then
    return output
  end

  for questKey, guideQuest in pairs(peer.questState.quests or {}) do
    localQuest = FindRemoteTrackerQuest(questState, guideQuest)
    if localQuest then
      for objectiveIndex = 1, table.getn(guideQuest.objectives or {}) do
        guideObjective = guideQuest.objectives[objectiveIndex]
        localObjective = FindQuestObjective(localQuest, guideObjective and (guideObjective.index or objectiveIndex))
        if guideObjective
          and localObjective
          and IsSharedSingleObjective(guideObjective)
          and IsSharedSingleObjective(localObjective)
          and SingleObjectiveDone(guideObjective) then
          table.insert(output, {
            key = SafeString(guideQuest.key or questKey) .. "#" .. SafeString(guideObjective.index or objectiveIndex),
            quest = guideQuest,
            objective = guideObjective,
            text = SingleObjectiveAlertText(guideQuest, guideObjective),
            participants = nil,
            complete = SingleObjectiveDone(localObjective)
          })
        end
      end
    end
  end

  table.sort(output, function(left, right)
    local leftTitle = string.lower(SafeString(left.quest and left.quest.title))
    local rightTitle = string.lower(SafeString(right.quest and right.quest.title))

    if leftTitle ~= rightTitle then
      return leftTitle < rightTitle
    end

    return SafeString(left.key) < SafeString(right.key)
  end)

  return output
end

local function BuildTouristDisplayRows()
  local instructions = Addon.GetTouristInstructions()
  local display = {}
  local present = {}
  local index
  local seq
  local instruction
  local completion
  local text
  local prefixText
  local markerText
  local suffixText

  for index = 1, table.getn(instructions) do
    instruction = instructions[index]
    seq = tonumber(instruction and instruction.seq) or 0
    text, prefixText, markerText, suffixText = GuideTouristInstructionText(instruction)
    table.insert(display, {
      seq = seq,
      text = text,
      prefixText = prefixText,
      markerText = markerText,
      suffixText = suffixText,
      actionText = L.INSTRUCTION_DONE or "Done",
      targetNpcName = Trim(SafeString(instruction and instruction.npcName)),
      completing = false
    })
    present[seq] = true
  end

  for seq, completion in pairs(guideTouristUI.completing) do
    if not present[seq] then
      text, prefixText, markerText, suffixText = GuideTouristInstructionText(completion.instruction)
      table.insert(display, {
        seq = tonumber(seq) or 0,
        text = text,
        prefixText = prefixText,
        markerText = markerText,
        suffixText = suffixText,
        actionText = nil,
        targetNpcName = Trim(SafeString(completion.instruction and completion.instruction.npcName)),
        completing = true,
        completion = completion
      })
    end
  end

  table.sort(display, function(left, right)
    return (tonumber(left.seq) or 0) < (tonumber(right.seq) or 0)
  end)

  return display
end

local function EnsureTouristRow(index)
  local row = guideTouristUI.touristRows[index]
  local fontPath
  local fontSize
  local fontFlags

  if row then
    return row
  end

  row = {}
  row.frame = CreateFrame("Frame", nil, guideTouristUI.frame)
  row.frame:SetWidth(264)
  row.frame:SetHeight(20)

  row.text = row.frame:CreateFontString(nil, "OVERLAY")
  row.text:SetPoint("LEFT", row.frame, "LEFT", 4, 0)
  row.text:SetWidth(180)
  row.text:SetHeight(20)
  row.text:SetJustifyH("LEFT")
  CopyGroupTrackerFont(guideTouristUI.title, row.text, 12)
  row.text:SetTextColor(1, 1, 1, 1)

  row.inlineMarker = row.frame:CreateFontString(nil, "OVERLAY")
  row.inlineMarker:SetHeight(20)
  row.inlineMarker:SetJustifyH("LEFT")
  row.inlineMarker:SetTextColor(1, 0.82, 0, 1)
  fontPath, fontSize, fontFlags = row.text:GetFont()
  if fontPath then
    if fontFlags then
      row.inlineMarker:SetFont(fontPath, 15, fontFlags)
    else
      row.inlineMarker:SetFont(fontPath, 15)
    end
  end
  row.inlineMarker:Hide()

  row.inlineSuffix = row.frame:CreateFontString(nil, "OVERLAY")
  row.inlineSuffix:SetHeight(20)
  row.inlineSuffix:SetJustifyH("LEFT")
  CopyGroupTrackerFont(row.text, row.inlineSuffix, 12)
  row.inlineSuffix:SetTextColor(1, 1, 1, 1)
  row.inlineSuffix:Hide()

  row.target = CreateFrame("Button", nil, row.frame)
  row.target:SetPoint("LEFT", row.frame, "LEFT", 4, 0)
  row.target:SetWidth(180)
  row.target:SetHeight(20)
  row.target:SetScript("OnClick", function()
    if row.targetNpcName
      and row.targetNpcName ~= ""
      and type(TargetByName) == "function" then
      TargetByName(row.targetNpcName, 1)
    end
  end)
  row.target:Hide()

  row.strike = row.frame:CreateTexture(nil, "OVERLAY")
  row.strike:SetPoint("LEFT", row.text, "LEFT", 0, 0)
  row.strike:SetHeight(1)
  row.strike:SetTexture(1, 0.82, 0)
  row.strike:Hide()

  row.action = CreateFrame("Button", nil, row.frame, "UIPanelButtonTemplate")
  row.action:SetPoint("RIGHT", row.frame, "RIGHT", 0, 0)
  row.action:SetWidth(52)
  row.action:SetHeight(18)
  row.action:SetText("")
  row.action:SetScript("OnClick", function()
    if row.seq then
      CompleteTouristInstruction(row.seq)
    end
  end)
  row.action:Hide()

  row.actionLabel = row.action:CreateFontString(nil, "OVERLAY")
  row.actionLabel:SetPoint("CENTER", row.action, "CENTER", 0, 0)
  CopyGroupTrackerFont(guideTouristUI.title, row.actionLabel, 12)
  row.actionLabel:SetTextColor(1, 0.82, 0, 1)

  guideTouristUI.touristRows[index] = row
  return row
end

local function RenderGuideTouristInstructionText(row, text, prefixText, markerText, suffixText, availableWidth)
  local prefixWidth
  local markerWidth
  local textWidth

  row.text:SetWidth(availableWidth)
  row.text:SetText(prefixText or text or "")
  row.text:Show()
  row.inlineMarker:Hide()
  row.inlineSuffix:Hide()

  textWidth = math.min(row.text:GetStringWidth(), availableWidth)
  if markerText then
    prefixWidth = textWidth
    row.inlineMarker:ClearAllPoints()
    row.inlineMarker:SetPoint("LEFT", row.text, "LEFT", prefixWidth, 0)
    row.inlineMarker:SetWidth(30)
    row.inlineMarker:SetText(markerText)
    markerWidth = math.max(1, row.inlineMarker:GetStringWidth())
    row.inlineMarker:SetWidth(markerWidth)
    row.inlineMarker:Show()

    row.inlineSuffix:ClearAllPoints()
    row.inlineSuffix:SetPoint("LEFT", row.inlineMarker, "RIGHT", 0, 0)
    row.inlineSuffix:SetWidth(math.max(0, availableWidth - prefixWidth - markerWidth))
    row.inlineSuffix:SetText(suffixText or "")
    row.inlineSuffix:Show()
    textWidth = math.min(availableWidth, prefixWidth + markerWidth + row.inlineSuffix:GetStringWidth())
  end

  row.renderedTextWidth = textWidth
end

local function EnsureSingleObjectiveRow(index)
  local row = guideTouristUI.objectiveRows[index]
  local slotIndex
  local xText
  local check

  if row then
    return row
  end

  row = {}
  row.frame = CreateFrame("Frame", nil, guideTouristUI.frame)
  row.frame:SetWidth(264)
  row.frame:SetHeight(20)

  row.icon = row.frame:CreateTexture(nil, "ARTWORK")
  row.icon:SetPoint("LEFT", row.frame, "LEFT", 1, 0)
  row.icon:SetWidth(16)
  row.icon:SetHeight(16)
  row.icon:SetTexture(SINGLE_OBJECTIVE_ICON)

  row.statusX = {}
  row.statusCheck = {}
  for slotIndex = 1, 4 do
    xText = row.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    xText:SetPoint("LEFT", row.frame, "LEFT", 21 + ((slotIndex - 1) * 12), 0)
    xText:SetWidth(10)
    xText:SetHeight(18)
    xText:SetJustifyH("CENTER")
    xText:SetText("X")
    xText:SetTextColor(1, 0.25, 0.2)
    xText:Hide()
    row.statusX[slotIndex] = xText

    check = row.frame:CreateTexture(nil, "OVERLAY")
    check:SetPoint("LEFT", row.frame, "LEFT", 21 + ((slotIndex - 1) * 12), 0)
    check:SetWidth(11)
    check:SetHeight(11)
    check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    check:SetVertexColor(0.25, 1, 0.25)
    check:Hide()
    row.statusCheck[slotIndex] = check
  end

  row.text = row.frame:CreateFontString(nil, "OVERLAY")
  row.text:SetHeight(20)
  row.text:SetJustifyH("LEFT")
  CopyGroupTrackerFont(guideTouristUI.title, row.text, 12)
  row.text:SetTextColor(1, 1, 1, 1)

  row.strike = row.frame:CreateTexture(nil, "OVERLAY")
  row.strike:SetHeight(1)
  row.strike:SetTexture(1, 0.82, 0)
  row.strike:Hide()

  guideTouristUI.objectiveRows[index] = row
  return row
end

local function HideSingleObjectiveRows()
  local index

  for index = 1, table.getn(guideTouristUI.objectiveRows) do
    guideTouristUI.objectiveRows[index].frame:Hide()
  end
end

local function RenderSingleObjectiveRows(alerts, startIndex, guideMode)
  local index
  local row
  local alert
  local slotIndex
  local participant
  local textLeft

  for index = 1, table.getn(alerts) do
    alert = alerts[index]
    row = EnsureSingleObjectiveRow(index)
    row.frame:ClearAllPoints()
    row.frame:SetPoint("TOPLEFT", guideTouristUI.frame, "TOPLEFT", 8, -28 - ((startIndex + index - 1) * 20))
    row.frame:SetAlpha(1)

    for slotIndex = 1, 4 do
      row.statusX[slotIndex]:Hide()
      row.statusCheck[slotIndex]:Hide()
    end

    if guideMode then
      for slotIndex = 1, math.min(4, table.getn(alert.participants or {})) do
        participant = alert.participants[slotIndex]
        if participant.complete then
          row.statusCheck[slotIndex]:Show()
        else
          row.statusX[slotIndex]:Show()
        end
      end
      textLeft = 71
    else
      textLeft = 21
    end

    row.text:ClearAllPoints()
    row.text:SetPoint("LEFT", row.frame, "LEFT", textLeft, 0)
    row.text:SetWidth(258 - textLeft)
    row.text:SetText(alert.text or "")
    row.text:Show()

    row.strike:ClearAllPoints()
    row.strike:SetPoint("LEFT", row.text, "LEFT", 0, 0)
    row.strike:SetWidth(math.min(row.text:GetStringWidth(), 258 - textLeft))
    if alert.complete then
      row.strike:Show()
    else
      row.strike:Hide()
    end

    row.frame:Show()
  end

  for index = table.getn(alerts) + 1, table.getn(guideTouristUI.objectiveRows) do
    guideTouristUI.objectiveRows[index].frame:Hide()
  end

  return table.getn(alerts)
end

local function HideTouristRows()
  local index

  for index = 1, table.getn(guideTouristUI.touristRows) do
    guideTouristUI.touristRows[index].frame:Hide()
  end
end

local function RefreshTouristWindow(session)
  local display = BuildTouristDisplayRows()
  local alerts = BuildTouristSingleObjectiveAlerts(session)
  local index
  local entry
  local row
  local alertCount
  local desiredHeight
  local savedHeight

  guideTouristUI.title:SetText(string.format(
    L.WINDOW_TITLE_TOURIST or "Tourist: %s",
    SafeString(session and session.guideName)
  ))
  guideTouristUI.showHidden = false
  if guideTouristUI.showHiddenButton then
    guideTouristUI.showHiddenButton:Hide()
  end

  for index = 1, table.getn(guideTouristUI.rows) do
    guideTouristUI.rows[index].frame:Hide()
  end

  for index = 1, table.getn(display) do
    entry = display[index]
    row = EnsureTouristRow(index)
    row.frame:ClearAllPoints()
    row.frame:SetPoint("TOPLEFT", guideTouristUI.frame, "TOPLEFT", 8, -28 - ((index - 1) * 20))
    row.frame:SetAlpha(1)
    row.seq = entry.seq
    row.targetNpcName = entry.targetNpcName
    RenderGuideTouristInstructionText(
      row,
      entry.text,
      entry.prefixText,
      entry.markerText,
      entry.suffixText,
      entry.actionText and 180 or 238
    )
    row.strike:Hide()
    row.target:SetWidth(entry.actionText and 180 or 238)
    row.target:Hide()
    row.actionLabel:SetText(entry.actionText or "")
    row.action:Hide()

    if row.targetNpcName
      and row.targetNpcName ~= ""
      and type(TargetByName) == "function" then
      row.target:Show()
    end

    if entry.actionText then
      row.action:Show()
    end

    if entry.completing then
      row.strike:SetWidth(math.min(row.renderedTextWidth or row.text:GetStringWidth(), 238))
      row.strike:Show()
      if entry.completion then
        entry.completion.row = row
      end
    end

    row.frame:Show()
  end

  for index = table.getn(display) + 1, table.getn(guideTouristUI.touristRows) do
    guideTouristUI.touristRows[index].frame:Hide()
  end

  alertCount = RenderSingleObjectiveRows(alerts, table.getn(display), false)
  desiredHeight = 34 + ((table.getn(display) + alertCount) * 20)
  savedHeight = Addon.db
    and Addon.db.ui
    and Addon.db.ui.guideWindow
    and tonumber(Addon.db.ui.guideWindow.height)
  guideTouristUI.frame:SetHeight(math.max(desiredHeight, savedHeight or desiredHeight))
  guideTouristUI.frame:Show()
end

local function EnsureGuideTouristRow(index)
  local row = guideTouristUI.rows[index]
  local fontPath
  local fontSize
  local fontFlags

  if row then
    return row
  end

  row = {}
  row.frame = CreateFrame("Frame", nil, guideTouristUI.frame)
  row.frame:SetWidth(264)
  row.frame:SetHeight(20)

  row.marker = row.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  row.marker:SetPoint("LEFT", row.frame, "LEFT", 0, 0)
  row.marker:SetWidth(18)
  row.marker:SetHeight(20)
  row.marker:SetJustifyH("CENTER")
  row.marker:SetTextColor(1, 0.82, 0)

  row.text = row.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  row.text:SetPoint("LEFT", row.marker, "RIGHT", 4, 0)
  row.text:SetWidth(238)
  row.text:SetHeight(20)
  row.text:SetJustifyH("LEFT")
  row.text:SetTextColor(1, 1, 1)

  row.inlineMarker = row.frame:CreateFontString(nil, "OVERLAY")
  row.inlineMarker:SetHeight(20)
  row.inlineMarker:SetJustifyH("LEFT")
  row.inlineMarker:SetTextColor(1, 0.82, 0, 1)
  fontPath, fontSize, fontFlags = row.text:GetFont()
  if fontPath then
    if fontFlags then
      row.inlineMarker:SetFont(fontPath, 15, fontFlags)
    else
      row.inlineMarker:SetFont(fontPath, 15)
    end
  end
  row.inlineMarker:Hide()

  row.inlineSuffix = row.frame:CreateFontString(nil, "OVERLAY")
  row.inlineSuffix:SetHeight(20)
  row.inlineSuffix:SetJustifyH("LEFT")
  CopyGroupTrackerFont(row.text, row.inlineSuffix, 12)
  row.inlineSuffix:SetTextColor(1, 1, 1, 1)
  row.inlineSuffix:Hide()

  row.target = CreateFrame("Button", nil, row.frame)
  row.target:SetPoint("LEFT", row.frame, "LEFT", 4, 0)
  row.target:SetWidth(238)
  row.target:SetHeight(20)
  row.target:SetScript("OnClick", function()
    if row.targetNpcName
      and row.targetNpcName ~= ""
      and type(TargetByName) == "function" then
      TargetByName(row.targetNpcName, 1)
    end
  end)
  row.target:Hide()

  row.strike = row.frame:CreateTexture(nil, "OVERLAY")
  row.strike:SetPoint("LEFT", row.text, "LEFT", 0, 0)
  row.strike:SetHeight(1)
  row.strike:SetTexture(1, 0.82, 0)
  row.strike:Hide()

  row.action = CreateFrame("Button", nil, row.frame, "UIPanelButtonTemplate")
  row.action:SetPoint("RIGHT", row.frame, "RIGHT", 0, 0)
  row.action:SetWidth(52)
  row.action:SetHeight(18)
  row.action:SetScript("OnClick", function()
    if row.disparityKey then
      SetGuideDisparityHidden(row.disparityKey, not row.disparityHidden)
    elseif row.guideInstructionSeq then
      Addon.RemoveGuideInstruction(row.guideInstructionSeq)
    elseif row.touristInstructionSeq then
      CompleteTouristInstruction(row.touristInstructionSeq)
    end
  end)
  row.action:Hide()

  guideTouristUI.rows[index] = row
  return row
end

local function SaveGuideTouristWindowPosition(saveSize)
  local state
  local point
  local relativeTo
  local relativePoint
  local x
  local y

  if not Addon.db or not guideTouristUI.frame then
    return
  end

  Addon.db.ui = NormalizeUIState(Addon.db.ui)
  state = Addon.db.ui.guideWindow
  point, relativeTo, relativePoint, x, y = guideTouristUI.frame:GetPoint()
  state.point = point or "CENTER"
  state.relativePoint = relativePoint or state.point
  state.x = tonumber(x) or 0
  state.y = tonumber(y) or 0

  if saveSize then
    state.width = math.max(280, tonumber(guideTouristUI.frame:GetWidth()) or 280)
    state.height = math.max(34, tonumber(guideTouristUI.frame:GetHeight()) or 34)
  end
end

local function RefreshGuideTouristWindow()
  local session = Addon.GetSession()
  local instructions
  local disparities = {}
  local display = {}
  local present = {}
  local sessionKey
  local index
  local seq
  local completion
  local allComplete
  local row
  local entry
  local title
  local disparity
  local alerts = {}
  local alertCount = 0
  local hiddenCount = 0
  local instructionText
  local prefixText
  local markerText
  local suffixText
  local desiredHeight
  local savedHeight

  if not guideTouristUI.frame then
    return
  end

  if not session
    or session.mode == "OFF"
    or (session.mode == "GUIDE" and not Addon.GuideHasActiveTourist(session)) then
    guideTouristUI.completing = {}
    guideTouristUI.completed = {}
    guideTouristUI.sessionKey = nil
    guideTouristUI.showHidden = false
    if guideTouristUI.showHiddenButton then
      guideTouristUI.showHiddenButton:Hide()
    end
    for index = 1, table.getn(guideTouristUI.rows) do
      guideTouristUI.rows[index].frame:Hide()
    end
    HideTouristRows()
    HideSingleObjectiveRows()
    guideTouristUI.frame:Hide()
    return
  end

  sessionKey = session.mode .. ":" .. SafeString(session.guideName) .. ":" .. SafeString(session.guideSessionId)
  if guideTouristUI.sessionKey ~= sessionKey then
    guideTouristUI.completing = {}
    guideTouristUI.completed = {}
    guideTouristUI.sessionKey = sessionKey
    guideTouristUI.showHidden = false
  end

  if session.mode == "TOURIST" then
    RefreshTouristWindow(session)
    return
  end

  HideTouristRows()

  if session.mode == "GUIDE" then
    title = L.WINDOW_TITLE_GUIDE or "Guide"
    instructions = Addon.GetGuideInstructions()
    disparities = BuildGuideDisparities(session)
    alerts = BuildGuideSingleObjectiveAlerts(session)
  else
    title = string.format(L.WINDOW_TITLE_TOURIST or "Tourist: %s", SafeString(session.guideName))
    instructions = Addon.GetTouristInstructions()
  end

  guideTouristUI.title:SetText(title)

  for index = 1, table.getn(instructions) do
    seq = tonumber(instructions[index].seq) or 0
    if session.mode == "GUIDE" then
      allComplete = GuideInstructionAllTouristsComplete(session, instructions[index])
      if not allComplete then
        guideTouristUI.completed[seq] = nil
        if guideTouristUI.completing[seq] and guideTouristUI.completing[seq].guide then
          guideTouristUI.completing[seq] = nil
        end
      elseif not guideTouristUI.completed[seq] and not guideTouristUI.completing[seq] then
        guideTouristUI.completing[seq] = {
          instruction = CopyInstruction(instructions[index]),
          started = GetTime(),
          row = nil,
          guide = true
        }
      end

      if not guideTouristUI.completed[seq] then
        completion = guideTouristUI.completing[seq]
        entry = {
          kind = "instruction",
          instruction = instructions[index],
          completing = completion and true or false,
          completion = completion
        }
        table.insert(display, entry)
        present[seq] = true
      end
    else
      entry = {
        kind = "instruction",
        instruction = instructions[index],
        completing = false
      }
      table.insert(display, entry)
      present[seq] = true
    end
  end

  for seq, completion in pairs(guideTouristUI.completing) do
    if not present[seq] then
      table.insert(display, {
        kind = "instruction",
        instruction = completion.instruction,
        completing = true,
        completion = completion
      })
    end
  end

  table.sort(display, function(left, right)
    return (tonumber(left.instruction and left.instruction.seq) or 0) < (tonumber(right.instruction and right.instruction.seq) or 0)
  end)

  if session.mode == "GUIDE" then
    for index = 1, table.getn(disparities) do
      disparity = disparities[index]
      if disparity.hidden then
        hiddenCount = hiddenCount + 1
      end
      if not disparity.hidden or guideTouristUI.showHidden then
        table.insert(display, {
          kind = "disparity",
          disparity = disparity
        })
      end
    end
  end

  if hiddenCount == 0 then
    guideTouristUI.showHidden = false
  end

  for index = 1, table.getn(display) do
    entry = display[index]
    row = EnsureGuideTouristRow(index)
    row.frame:ClearAllPoints()
    row.frame:SetPoint("TOPLEFT", guideTouristUI.frame, "TOPLEFT", 8, -28 - ((index - 1) * 20))
    row.frame:SetAlpha(1)
    row.marker:SetTextColor(1, 0.82, 0)
    row.marker:SetWidth(18)
    row.text:SetTextColor(1, 1, 1)
    row.text:SetWidth(238)
    row.inlineMarker:Hide()
    row.inlineSuffix:Hide()
    row.strike:Hide()
    row.target:Hide()
    row.targetNpcName = nil
    row.action:Hide()
    row.disparityKey = nil
    row.disparityHidden = false
    row.guideInstructionSeq = nil
    row.touristInstructionSeq = nil

    if entry.kind == "disparity" then
      disparity = entry.disparity
      row.seq = nil
      row.disparityKey = disparity.key
      row.disparityHidden = disparity.hidden and true or false
      row.marker:SetText("!")
      row.marker:SetTextColor(1, 0.35, 0.15)
      row.text:SetWidth(180)
      row.text:SetText(string.format(
        L.DISPARITY_MISSING_QUEST or "%s missing: %s",
        SafeString(disparity.playerName),
        SafeString(disparity.quest and disparity.quest.title)
      ))
      row.action:SetText(row.disparityHidden and (L.DISPARITY_UNHIDE or "Unhide") or (L.DISPARITY_HIDE or "Hide"))
      row.action:Show()
      if row.disparityHidden then
        row.frame:SetAlpha(0.55)
      end
    else
      row.seq = tonumber(entry.instruction and entry.instruction.seq) or 0
      row.marker:SetText("")
      row.marker:SetWidth(0)
      instructionText, prefixText, markerText, suffixText = GuideTouristInstructionText(entry.instruction)
      RenderGuideTouristInstructionText(
        row,
        instructionText,
        prefixText,
        markerText,
        suffixText,
        entry.completing and 238 or 180
      )
      row.target:SetWidth(entry.completing and 238 or 180)
      row.targetNpcName = Trim(SafeString(entry.instruction and entry.instruction.npcName))
      if row.targetNpcName ~= "" and type(TargetByName) == "function" then
        row.target:Show()
      end

      if not entry.completing then
        row.guideInstructionSeq = row.seq
        row.action:SetText(L.INSTRUCTION_REMOVE or "Remove")
        row.action:Show()
      end

      if entry.completing then
        row.strike:SetWidth(math.min(row.renderedTextWidth or row.text:GetStringWidth(), 238))
        row.strike:Show()
        entry.completion.row = row
      end
    end

    row.frame:Show()
  end

  for index = table.getn(display) + 1, table.getn(guideTouristUI.rows) do
    guideTouristUI.rows[index].frame:Hide()
  end

  alertCount = RenderSingleObjectiveRows(alerts, table.getn(display), true)

  if session.mode == "GUIDE" and hiddenCount > 0 and guideTouristUI.showHiddenButton then
    if guideTouristUI.showHidden then
      guideTouristUI.showHiddenButton:SetText(L.DISPARITY_HIDE_HIDDEN or "Hide Hidden")
    else
      guideTouristUI.showHiddenButton:SetText(string.format(L.DISPARITY_SHOW_HIDDEN or "Show Hidden (%d)", hiddenCount))
    end
    guideTouristUI.showHiddenButton:Show()
    desiredHeight = 58 + ((table.getn(display) + alertCount) * 20)
  else
    if guideTouristUI.showHiddenButton then
      guideTouristUI.showHiddenButton:Hide()
    end
    desiredHeight = 34 + ((table.getn(display) + alertCount) * 20)
  end

  savedHeight = Addon.db
    and Addon.db.ui
    and Addon.db.ui.guideWindow
    and tonumber(Addon.db.ui.guideWindow.height)
  guideTouristUI.frame:SetHeight(math.max(desiredHeight, savedHeight or desiredHeight))
  guideTouristUI.frame:Show()
end

guideTouristUI.refresh = RefreshGuideTouristWindow
local function HandleGuideInstructionCompleted(instruction)
  local session = Addon.GetSession()
  local seq = tonumber(instruction and instruction.seq)

  if not session or session.mode ~= "GUIDE" or not seq then
    return
  end

  guideTouristUI.completing[seq] = {
    instruction = CopyInstruction(instruction),
    started = GetTime(),
    row = nil,
    guide = true
  }
  RefreshGuideTouristWindow()
end

local function HandleTouristInstructionCompleted(instruction)
  local session = Addon.GetSession()
  local seq = tonumber(instruction and instruction.seq)

  if not session or session.mode ~= "TOURIST" or not seq then
    return
  end

  guideTouristUI.completing[seq] = {
    instruction = CopyInstruction(instruction),
    started = GetTime(),
    row = nil
  }
  RefreshGuideTouristWindow()
end

local function UpdateGuideTouristCompletion()
  local now
  local seq
  local completion
  local elapsed
  local alpha
  local changed = false

  if not guideTouristUI.frame or not next(guideTouristUI.completing) then
    return
  end

  now = GetTime()
  for seq, completion in pairs(guideTouristUI.completing) do
    elapsed = now - (tonumber(completion.started) or now)
    if elapsed >= guideTouristUI.completionDuration then
      if completion.guide then
        guideTouristUI.completed[seq] = true
      end
      guideTouristUI.completing[seq] = nil
      changed = true
    elseif completion.row and completion.row.seq == seq then
      if elapsed <= 0.25 then
        alpha = 1
      else
        alpha = 1 - ((elapsed - 0.25) / (guideTouristUI.completionDuration - 0.25))
        if alpha < 0 then
          alpha = 0
        end
      end
      completion.row.frame:SetAlpha(alpha)
    end
  end

  if changed then
    RefreshGuideTouristWindow()
  end
end

local function InitializeGuideTouristWindow()
  local state

  if guideTouristUI.frame or not Addon.db then
    return
  end

  Addon.db.ui = NormalizeUIState(Addon.db.ui)
  state = Addon.db.ui.guideWindow

  guideTouristUI.frame = CreateFrame("Frame", "pfQuest_GroupGuideTouristFrame", UIParent)
  guideTouristUI.frame:SetWidth(state.width)
  guideTouristUI.frame:SetHeight(state.height)
  guideTouristUI.frame:SetFrameStrata("DIALOG")
  guideTouristUI.frame:SetMovable(true)
  guideTouristUI.frame:SetResizable(true)
  guideTouristUI.frame:SetMinResize(280, 34)
  guideTouristUI.frame:EnableMouse(true)
  guideTouristUI.frame:RegisterForDrag("LeftButton")
  guideTouristUI.frame:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 12,
    insets = {
      left = 3,
      right = 3,
      top = 3,
      bottom = 3
    }
  })
  guideTouristUI.frame:SetBackdropColor(0, 0, 0, 0.9)
  guideTouristUI.frame:SetBackdropBorderColor(0.45, 0.45, 0.45, 1)
  guideTouristUI.frame:SetPoint(state.point, UIParent, state.relativePoint, state.x, state.y)

  guideTouristUI.title = guideTouristUI.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  guideTouristUI.title:SetPoint("TOPLEFT", guideTouristUI.frame, "TOPLEFT", 10, -9)
  guideTouristUI.title:SetPoint("TOPRIGHT", guideTouristUI.frame, "TOPRIGHT", -10, -9)
  guideTouristUI.title:SetHeight(16)
  guideTouristUI.title:SetJustifyH("LEFT")
  guideTouristUI.title:SetTextColor(1, 0.82, 0)

  guideTouristUI.showHiddenButton = CreateFrame("Button", nil, guideTouristUI.frame, "UIPanelButtonTemplate")
  guideTouristUI.showHiddenButton:SetPoint("BOTTOMLEFT", guideTouristUI.frame, "BOTTOMLEFT", 8, 7)
  guideTouristUI.showHiddenButton:SetWidth(112)
  guideTouristUI.showHiddenButton:SetHeight(18)
  guideTouristUI.showHiddenButton:SetScript("OnClick", function()
    guideTouristUI.showHidden = not guideTouristUI.showHidden
    RefreshGuideTouristWindow()
  end)
  guideTouristUI.showHiddenButton:Hide()

  guideTouristUI.resizeGrip = CreateFrame("Button", nil, guideTouristUI.frame)
  guideTouristUI.resizeGrip:SetPoint("BOTTOMRIGHT", guideTouristUI.frame, "BOTTOMRIGHT", -3, 3)
  guideTouristUI.resizeGrip:SetWidth(16)
  guideTouristUI.resizeGrip:SetHeight(16)
  guideTouristUI.resizeGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  guideTouristUI.resizeGrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  guideTouristUI.resizeGrip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  guideTouristUI.resizeGrip:SetScript("OnMouseDown", function()
    guideTouristUI.frame:StartSizing("BOTTOMRIGHT")
  end)
  guideTouristUI.resizeGrip:SetScript("OnMouseUp", function()
    guideTouristUI.frame:StopMovingOrSizing()
    SaveGuideTouristWindowPosition(true)
    RefreshGuideTouristWindow()
  end)

  guideTouristUI.frame:SetScript("OnDragStart", function()
    guideTouristUI.frame:StartMoving()
  end)
  guideTouristUI.frame:SetScript("OnDragStop", function()
    guideTouristUI.frame:StopMovingOrSizing()
    SaveGuideTouristWindowPosition()
  end)
  guideTouristUI.frame:SetScript("OnUpdate", function()
    UpdateGuideTouristCompletion()
  end)

  RefreshGuideTouristWindow()
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

Addon.RegisterStateComponent("session", SessionSnapshot, ApplyRemoteSessionFull, ApplyRemoteSessionDelta)
Addon.RegisterStateComponent("quests", QuestSnapshot, ApplyRemoteQuestFull, ApplyRemoteQuestDelta)
Addon.RegisterStateComponent("instructions", InstructionSnapshot, ApplyRemoteInstructionFull, ApplyRemoteInstructionDelta)

Addon.RegisterListener("REMOTE_SESSION_CHANGED", Addon.HandleGroupHoldRemoteSession)
Addon.RegisterListener("REMOTE_QUEST_STATE_CHANGED", Addon.HandleGroupHoldRemoteQuest)
Addon.RegisterListener("SESSION_CHANGED", Addon.HandleGroupHoldLocalState)
Addon.RegisterListener("LOCAL_QUEST_STATE_CHANGED", Addon.HandleGroupHoldLocalState)
Addon.RegisterListener("PEER_STATUS", Addon.RefreshGroupHoldPresentation)
Addon.RegisterListener("PEER_LEFT", Addon.RefreshGroupHoldPresentation)
Addon.RegisterListener("PARTY_CHANGED", Addon.RefreshGroupHoldPresentation)
Addon.RegisterListener("LOCAL_QUEST_ACTION", HandleInstructionQuestAction)
Addon.RegisterListener("LOCAL_QUEST_STATE_CHANGED", RefreshGroupProgress)
Addon.RegisterListener("REMOTE_QUEST_STATE_CHANGED", RefreshGroupProgress)
Addon.RegisterListener("PEER_STATUS", RefreshGroupProgress)
Addon.RegisterListener("PEER_LEFT", RefreshGroupProgress)
Addon.RegisterListener("PARTY_CHANGED", RefreshGroupProgress)
Addon.RegisterListener("LOCAL_QUEST_STATE_CHANGED", RefreshGuideTouristWindow)
Addon.RegisterListener("REMOTE_QUEST_STATE_CHANGED", RefreshGuideTouristWindow)
Addon.RegisterListener("REMOTE_SESSION_CHANGED", RefreshGuideTouristWindow)
Addon.RegisterListener("PEER_STATUS", RefreshGuideTouristWindow)
Addon.RegisterListener("PEER_LEFT", RefreshGuideTouristWindow)
Addon.RegisterListener("PARTY_CHANGED", RefreshGuideTouristWindow)
Addon.RegisterListener("SESSION_CHANGED", RefreshGuideTouristWindow)
Addon.RegisterListener("GUIDE_INSTRUCTIONS_CHANGED", RefreshGuideTouristWindow)
Addon.RegisterListener("TOURIST_INSTRUCTIONS_CHANGED", RefreshGuideTouristWindow)
Addon.RegisterListener("GUIDE_INSTRUCTION_COMPLETED", HandleGuideInstructionCompleted)
Addon.RegisterListener("TOURIST_INSTRUCTION_COMPLETED", HandleTouristInstructionCompleted)
Addon.RegisterListener("REMOTE_INSTRUCTION_COMPLETIONS_CHANGED", RefreshGuideTouristWindow)


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
    Addon.InstallGroupHoldMapTooltip()
    InitializeGuideTouristWindow()
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
    Addon.InstallGroupHoldMapTooltip()
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

questScanFrame:SetScript("OnUpdate", function()
  if not initialized or not questScanPending then
    questScanFrame:Hide()
    return
  end

  if GetTime() < questScanAt or (not questState.ready and GetTime() < questBaselineAt) then
    return
  end

  ScanQuestState()
end)
