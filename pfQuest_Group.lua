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
      incoming[senderKey] = nil
    end

    peer.name = sender
    peer.version = hello.version
    peer.protocol = protocolVersion
    peer.bootId = hello.boot
    peer.compatible = protocolVersion == PROTOCOL_VERSION
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

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PARTY_MEMBERS_CHANGED")
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
  elseif event == "CHAT_MSG_ADDON" then
    ReceiveWire(arg1, arg2, arg3, arg4)
  end
end)
