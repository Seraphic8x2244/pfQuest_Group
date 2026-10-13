-- Dev-only visual lab. Synthetic examples never touch Guide/Tourist session state.
-- Loaded by pfQuest_Group.toc on the dev branch only.
if not pfQuest_Group then return end

local GROUP_TITLE_MARKUP = "|cff33ffccpf|cffffffffQuest|cff999999 Group|r"
local lab = {
  window = nil, rows = {}, fields = {}, views = {}, builds = 0,
  mode = "GUIDE", skin = "NATIVE", questArt = true, discoveryArt = 1
}
local base = "Interface\\AddOns\\pfQuest_Group\\assets\\"
local sizes = {
  button = 18, remove = 11, hide = 11, unhide = 11, done = 11,
  quest = 12, gossip = 12, flight = 12, item = 14, kill = 14, discovery = 14
}
local defaults = {
  button = 18, remove = 11, hide = 11, unhide = 11, done = 11,
  quest = 12, gossip = 12, flight = 12, item = 14, kill = 14, discovery = 14
}
local discoveryChoices = {
  { "pfQuest misc", "Interface\\AddOns\\pfQuest\\img\\cluster_misc" },
  { "pfQuest object", "Interface\\AddOns\\pfQuest\\img\\icon_object" },
  { "Inventory map", "Interface\\Icons\\INV_Misc_Map_01" }
}
local options = {
  { "Action button", "button", 16, 26 },
  { "Remove (trash)", "remove", 8, 20 },
  { "Hide (eye-off)", "hide", 8, 20 },
  { "Unhide (eye)", "unhide", 8, 20 },
  { "Done (clipboard)", "done", 8, 20 },
  { "Quest ! / ?", "quest", 8, 20 },
  { "Gossip bubble", "gossip", 8, 20 },
  { "Flight (no crop)", "flight", 8, 20 },
  { "Item bag", "item", 8, 20 },
  { "Kill marker", "kill", 8, 20 },
  { "Discovery misc", "discovery", 8, 20 }
}

local guideSamples = {
  { "accept", "remove", "ACCEPT  |cff40bf40Friendly Guide NPC|r - Sample quest" },
  { "turnin", "remove", "TURNIN  |cffffff00Neutral NPC|r - Sample quest" },
  { "gossip", "remove", "GOSSIP  Speak with the quest NPC" },
  { "flight", "remove", "FLIGHT  Fly to Aerie Peak" },
  { "accept", "hide", "MISSING  Tourist needs a quest (visible)" },
  { "accept", "unhide", "HIDDEN  Tourist needs a quest (hidden)", true },
  { "item", nil, "ITEM  Retrieve an item - Tourist: X" },
  { "kill", nil, "KILL  Defeat enemy (reference only)" },
  { "discovery", nil, "DISCOVERY  Search the Altar of Zul - X" },
  { "accept", "remove", "ACCEPT  Quest without NPC (short name)" },
  { "turnin", "remove", "TURNIN  Long quest title for clipping comparison" },
  { "done", nil, "COMPLETE  Tourist acknowledged (check)", false, true },
  { "accept", "remove", "ACCEPT  Another quest to check scrolling" },
  { "gossip", "remove", "GOSSIP  Another conversation" },
  { "item", nil, "ITEM  Second loot objective" },
  { "flight", "remove", "FLIGHT  Second flight destination" }
}
local touristSamples = {
  { "accept", "done", "ACCEPT  Guide NPC - Sample quest" },
  { "turnin", "done", "TURNIN  Guide NPC - Sample quest" },
  { "gossip", "done", "GOSSIP  Speak with the quest NPC" },
  { "flight", "done", "FLIGHT  Fly to Aerie Peak" },
  { "item", nil, "ITEM  Retrieve an item - X" },
  { "kill", nil, "KILL  Defeat enemy (reference only)" },
  { "discovery", nil, "DISCOVERY  Search the Altar of Zul - X" },
  { "accept", "done", "ACCEPT  Quest without NPC" },
  { "turnin", "done", "TURNIN  Long quest title for clipping comparison" },
  { "done", nil, "COMPLETED  Instruction checked off", false, true },
  { "accept", "done", "ACCEPT  Another quest to check scrolling" },
  { "gossip", "done", "GOSSIP  Another conversation" },
  { "item", nil, "ITEM  Second loot objective" },
  { "flight", "done", "FLIGHT  Second flight destination" }
}

local function CanUsePfUI()
  return pfUI and pfUI.api and pfUI_config
    and pfUI_config.appearance and pfUI_config.appearance.border
    and type(pfUI.api.CreateBackdrop) == "function"
    and type(pfUI.api.SkinButton) == "function"
    and type(pfUI.api.SkinScrollbar) == "function"
    and pfUI.font_default
end

local function ApplyBackdrop(frame)
  if lab.skin == "PFUI" and CanUsePfUI() then
    -- Use the installed pfUI border thickness, colors and pixel scaling.
    pfUI.api.CreateBackdrop(frame, nil, true)
    return
  end

  frame:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 }
  })
  frame:SetBackdropColor(0, 0, 0, 0.9)
  frame:SetBackdropBorderColor(0.45, 0.45, 0.45, 1)
end

local function SkinButton(button)
  if lab.skin == "PFUI" and CanUsePfUI() then
    pfUI.api.SkinButton(button)
  end
end

local function MakeButton(parent, width, label, x, y, handler)
  local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  button:SetWidth(width)
  button:SetHeight(20)
  button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  button:SetText(label)
  button:SetScript("OnClick", handler)
  SkinButton(button)
  return button
end

local function CreateRow(index)
  local frame = CreateFrame("Frame", nil, lab.child)
  frame:SetWidth(338)
  frame:SetHeight(25)
  frame:SetPoint("TOPLEFT", lab.child, "TOPLEFT", 3, -((index - 1) * 27))

  local action = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  action:SetPoint("LEFT", frame, "LEFT", 0, 0)
  action:SetWidth(18)
  action:SetHeight(18)
  action:SetText("")
  SkinButton(action)
  action:EnableMouse(false)
  local actionIcon = action:CreateTexture(nil, "ARTWORK")
  actionIcon:SetPoint("CENTER", action, "CENTER", 0, 0)

  local marker = CreateFrame("Frame", nil, frame)
  marker:SetPoint("LEFT", frame, "LEFT", 21, 0)
  marker:SetWidth(18)
  marker:SetHeight(18)
  local icon = marker:CreateTexture(nil, "ARTWORK")
  icon:SetPoint("CENTER", marker, "CENTER", 0, 0)
  local glyph = marker:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  glyph:SetPoint("CENTER", marker, "CENTER", 0, 0)
  glyph:SetTextColor(1, 0.82, 0)

  local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  label:SetPoint("LEFT", frame, "LEFT", 46, 0)
  label:SetHeight(22)
  label:SetWidth(280)
  label:SetJustifyH("LEFT")

  lab.rows[index] = {
    frame = frame, action = action, actionIcon = actionIcon,
    marker = marker, icon = icon, glyph = glyph, label = label
  }
end

local function Render()
  if not lab.window then return end

  local samples = lab.mode == "GUIDE" and guideSamples or touristSamples
  lab.title:SetText(lab.mode == "GUIDE"
    and GROUP_TITLE_MARKUP .. " - Guide Mode"
    or GROUP_TITLE_MARKUP .. " - Tourist of |cff69ccf0GuideName|r")
  lab.modeButton:SetText(lab.mode == "GUIDE" and "View: Guide" or "View: Tourist")
  lab.skinButton:SetText(lab.skin == "PFUI" and "Skin: pfUI actual" or "Skin: Native")
  lab.questButton:SetText(lab.questArt and "Quest: BLP" or "Quest: ! / ?")
  lab.discoveryButton:SetText("Discovery: " .. discoveryChoices[lab.discoveryArt][1])
  ApplyBackdrop(lab.window)
  ApplyBackdrop(lab.preview)

  local fontPath, _, fontFlags = GameFontNormal:GetFont()
  for index = 1, table.getn(samples) do
    if not lab.rows[index] then CreateRow(index) end
    local row = lab.rows[index]
    local sample = samples[index]
    local markerType = sample[1]
    local actionType = sample[2]

    row.frame:Show()
    row.frame:SetAlpha(sample[4] and 0.5 or 1)
    row.label:SetText(sample[3])
    row.action:SetWidth(sizes.button)
    row.action:SetHeight(sizes.button)
    row.action:ClearAllPoints()
    row.action:SetPoint("LEFT", row.frame, "LEFT", 0, 0)
    row.marker:ClearAllPoints()
    row.marker:SetPoint("LEFT", row.frame, "LEFT", sizes.button + 3, 0)
    row.label:ClearAllPoints()
    row.label:SetPoint("LEFT", row.frame, "LEFT", sizes.button + 24, 0)
    row.label:SetWidth(330 - sizes.button - 24)

    if actionType then
      local artName = actionType == "remove" and "trash-2"
        or actionType == "hide" and "eye-off"
        or actionType == "unhide" and "eye" or "clipboard-check"
      row.actionIcon:SetTexture(base .. artName)
      row.actionIcon:SetWidth(sizes[actionType])
      row.actionIcon:SetHeight(sizes[actionType])
      row.actionIcon:Show()
      row.action:Show()
    else
      row.action:Hide()
    end

    row.icon:Hide()
    row.icon:SetVertexColor(1, 1, 1)
    row.glyph:Hide()
    if markerType == "accept" or markerType == "turnin" then
      if lab.questArt then
        row.icon:SetTexture(markerType == "accept"
          and "Interface\\GossipFrame\\AvailableQuestIcon"
          or "Interface\\GossipFrame\\ActiveQuestIcon")
        row.icon:SetTexCoord(0, 1, 0, 1)
        row.icon:SetWidth(sizes.quest)
        row.icon:SetHeight(sizes.quest)
        row.icon:Show()
      else
        if fontPath then
          if fontFlags then
            row.glyph:SetFont(fontPath, sizes.quest, fontFlags)
          else
            row.glyph:SetFont(fontPath, sizes.quest)
          end
        end
        row.glyph:SetText(markerType == "accept" and "!" or "?")
        row.glyph:Show()
      end
    elseif markerType == "gossip" then
      row.icon:SetTexture("Interface\\GossipFrame\\GossipGossipIcon")
      row.icon:SetTexCoord(0, 1, 1, 0)
      row.icon:SetWidth(sizes.gossip)
      row.icon:SetHeight(sizes.gossip)
      row.icon:Show()
    elseif markerType == "flight" then
      row.icon:SetTexture("Interface\\TaxiFrame\\UI-Taxi-Icon-Green")
      row.icon:SetTexCoord(0, 1, 0, 1)
      row.icon:SetWidth(sizes.flight)
      row.icon:SetHeight(sizes.flight)
      row.icon:Show()
    elseif markerType == "item" then
      row.icon:SetTexture("Interface\\AddOns\\pfQuest\\img\\cluster_item")
      row.icon:SetTexCoord(0, 1, 0, 1)
      row.icon:SetWidth(sizes.item)
      row.icon:SetHeight(sizes.item)
      row.icon:Show()
    elseif markerType == "kill" then
      -- Icon reference only; PFQG does not currently generate kill alerts.
      row.icon:SetTexture("Interface\\AddOns\\pfQuest\\img\\cluster_mob")
      row.icon:SetTexCoord(0, 1, 0, 1)
      row.icon:SetWidth(sizes.kill)
      row.icon:SetHeight(sizes.kill)
      row.icon:Show()
    elseif markerType == "discovery" then
      row.icon:SetTexture(discoveryChoices[lab.discoveryArt][2])
      if lab.discoveryArt == 3 then
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      else
        row.icon:SetTexCoord(0, 1, 0, 1)
      end
      row.icon:SetWidth(sizes.discovery)
      row.icon:SetHeight(sizes.discovery)
      row.icon:Show()
    elseif markerType == "done" then
      -- The old X was a placeholder; completed rows should show a check.
      row.icon:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
      row.icon:SetTexCoord(0, 1, 0, 1)
      row.icon:SetVertexColor(0.25, 1, 0.25)
      row.icon:SetWidth(11)
      row.icon:SetHeight(11)
      row.icon:Show()
    end
    if sample[5] then row.label:SetText("|cff40df40" .. sample[3] .. "|r") end
  end
  for index = table.getn(samples) + 1, table.getn(lab.rows) do
    lab.rows[index].frame:Hide()
  end
  lab.child:SetHeight(math.max(1, table.getn(samples) * 27))

  for _, option in ipairs(options) do
    local field = lab.fields[option[2]]
    if field then field:SetText(sizes[option[2]] .. " px") end
  end
end

local function Reset()
  for key, value in pairs(defaults) do sizes[key] = value end
  -- Reset measurements and examples without changing the selected skin.
  lab.questArt = true
  lab.discoveryArt = 1
  Render()
end

local Build

-- Keep one skinned window per theme. pfUI permanently hooks buttons and the
-- scrollbar; theme changes swap complete temporary previews, never undo hooks.
local function ShowSkin(skin)
  if lab.window then lab.window:Hide() end
  lab.skin = skin
  local view = lab.views[skin]
  if view then
    for key, value in pairs(view) do lab[key] = value end
  else
    lab.window = nil
    lab.rows = {}
    lab.fields = {}
    Build()
  end
  Render()
  lab.window:Show()
end

Build = function()
  if lab.window then return end
  lab.builds = lab.builds + 1
  local window = CreateFrame("Frame", "pfQuest_GroupDevUILabFrame" .. lab.builds, UIParent)
  window:SetWidth(765)
  window:SetHeight(545)
  window:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  window:SetFrameStrata("DIALOG")
  window:SetMovable(true)
  window:EnableMouse(true)
  window:RegisterForDrag("LeftButton")
  window:SetScript("OnDragStart", function() window:StartMoving() end)
  window:SetScript("OnDragStop", function() window:StopMovingOrSizing() end)
  lab.window = window
  ApplyBackdrop(window)

  local heading = window:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  heading:SetPoint("TOPLEFT", window, "TOPLEFT", 16, -11)
  heading:SetText(GROUP_TITLE_MARKUP .. " - UI Lab (dev only)")
  MakeButton(window, 52, "Close", 690, -8, function() window:Hide() end)

  lab.modeButton = MakeButton(window, 120, "View: Guide", 14, -36, function()
    lab.mode = lab.mode == "GUIDE" and "TOURIST" or "GUIDE"
    Render()
  end)
  lab.skinButton = MakeButton(window, 130, "Skin: Native", 140, -36, function()
    if lab.skin == "PFUI" then
      ShowSkin("NATIVE")
    elseif CanUsePfUI() then
      ShowSkin("PFUI")
    elseif DEFAULT_CHAT_FRAME then
      DEFAULT_CHAT_FRAME:AddMessage("pfQuest Group UI Lab: pfUI skinning API not available.")
    end
  end)
  lab.questButton = MakeButton(window, 116, "Quest: ! / ?", 276, -36, function()
    lab.questArt = not lab.questArt
    Render()
  end)
  MakeButton(window, 68, "Reset", 399, -36, Reset)
  lab.discoveryButton = MakeButton(window, 192, "Discovery: pfQuest misc", 475, -36, function()
    lab.discoveryArt = math.mod(lab.discoveryArt, table.getn(discoveryChoices)) + 1
    Render()
  end)

  local preview = CreateFrame("Frame", nil, window)
  preview:SetPoint("TOPLEFT", window, "TOPLEFT", 14, -68)
  preview:SetWidth(353)
  preview:SetHeight(436)
  lab.preview = preview
  ApplyBackdrop(preview)

  lab.title = preview:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  lab.title:SetPoint("TOPLEFT", preview, "TOPLEFT", 10, -10)
  lab.title:SetWidth(334)
  lab.title:SetHeight(20)
  lab.title:SetJustifyH("LEFT")
  lab.title:SetTextColor(1, 1, 1)

  local scrollName = "pfQuest_GroupDevUILabScroll" .. lab.builds
  lab.scroll = CreateFrame("ScrollFrame", scrollName, preview, "UIPanelScrollFrameTemplate")
  lab.scroll:SetPoint("TOPLEFT", preview, "TOPLEFT", 7, -37)
  lab.scroll:SetPoint("BOTTOMRIGHT", preview, "BOTTOMRIGHT", -25, 9)
  lab.child = CreateFrame("Frame", nil, lab.scroll)
  lab.child:SetWidth(315)
  lab.child:SetHeight(1)
  lab.scroll:SetScrollChild(lab.child)
  if lab.skin == "PFUI" and CanUsePfUI() then
    local scrollbar = getglobal(scrollName .. "ScrollBar")
    if scrollbar then pfUI.api.SkinScrollbar(scrollbar) end
  end

  local description = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  description:SetPoint("TOPLEFT", window, "TOPLEFT", 392, -73)
  description:SetWidth(342)
  description:SetHeight(34)
  description:SetJustifyH("LEFT")
  description:SetText("Each +/- adjusts this preview only. No quests, sessions, UI settings or network traffic change.")

  for index, option in ipairs(options) do
    local yy = -113 - (index - 1) * 32
    local label = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", window, "TOPLEFT", 392, yy - 2)
    label:SetWidth(166)
    label:SetHeight(20)
    label:SetJustifyH("LEFT")
    label:SetText(option[1])

    local field = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    field:SetPoint("TOPLEFT", window, "TOPLEFT", 560, yy - 2)
    field:SetWidth(48)
    field:SetHeight(20)
    lab.fields[option[2]] = field

    local control = option
    MakeButton(window, 28, "-", 627, yy, function()
      local key = control[2]
      sizes[key] = math.max(control[3], sizes[key] - 1)
      Render()
    end)
    MakeButton(window, 28, "+", 662, yy, function()
      local key = control[2]
      sizes[key] = math.min(control[4], sizes[key] + 1)
      Render()
    end)
  end

  local caption = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  caption:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 16, 14)
  caption:SetWidth(735)
  caption:SetHeight(22)
  caption:SetJustifyH("LEFT")
  caption:SetText("Synthetic list only | Native or installed pfUI skin | Live panels unchanged")

  lab.views[lab.skin] = {
    window = lab.window, rows = lab.rows, fields = lab.fields,
    modeButton = lab.modeButton, skinButton = lab.skinButton,
    questButton = lab.questButton, discoveryButton = lab.discoveryButton,
    preview = lab.preview, title = lab.title, scroll = lab.scroll,
    child = lab.child
  }
  Render()
end

function pfQuest_Group.ToggleDebugUI()
  local wasOpen = lab.window and lab.window:IsShown()
  if not lab.window and CanUsePfUI() then lab.skin = "PFUI" end
  Build()
  if wasOpen then
    lab.window:Hide()
  else
    Render()
    lab.window:Show()
  end
end
