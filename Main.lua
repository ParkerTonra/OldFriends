-- Old Friends v2.1 - Main: saved variables, O-key override, events, slash commands.
local ADDON, MF = ...
local pcall = MF.PCall -- logs failures to the diagnostics log

local format = string.format
local bindOwner = CreateFrame("Frame")
local bindDirty = false

------------------------------------------------------------------ saved variables
local function InitDB()
  OldFriendsDB = OldFriendsDB or {}
  local DB = OldFriendsDB
  MF.DB = DB
  if DB.showOffline == nil then DB.showOffline = false end
  if type(DB.collapsed) ~= "table" then DB.collapsed = {} end -- v1 stored a boolean here
  if type(DB.filter) ~= "table" then DB.filter = {} end
  for _, k in ipairs({ "online", "away", "busy", "offline", "inQueue", "availableForQueue" }) do
    if DB.filter[k] == nil then DB.filter[k] = false end
  end
  if type(DB.filter.tags) ~= "table" then DB.filter.tags = {} end
  if type(DB.allyFilter) ~= "table" then DB.allyFilter = {} end
  for _, k in ipairs({ "online", "away", "busy", "offline" }) do
    if DB.allyFilter[k] == nil then DB.allyFilter[k] = false end
  end
  if type(DB.lastTab) ~= "string" then DB.lastTab = "friends" end
  if type(DB.scale) ~= "number" then DB.scale = 1 end
  if DB.skin ~= "enhanced" and DB.skin ~= "classic" then DB.skin = "enhanced" end -- window look, see MF.ApplySkin
  if type(DB.debug) ~= "boolean" then DB.debug = false end -- echo log lines to chat (/of debug on|off)
  MF.AttachLog(DB) -- OldFriendsDB.log is the persistent diagnostics log
  MF.Log("db", format("init: skin=%s scale=%s lastTab=%s debug=%s", DB.skin, tostring(DB.scale), DB.lastTab,
    tostring(DB.debug)))
end

------------------------------------------------------------------ O key override
-- Binding overrides on the keys of TOGGLESOCIAL (O) and TOGGLEFRIENDSTAB. No Blizzard function is hooked.
-- SHIFT + the taken key goes back to Blizzard's own window (the same binding command), in case it is needed.
-- Skipped when the key already has SHIFT, or when SHIFT + key is bound to something else.
local function BindShiftFallback(key, action, keys)
  local mods, rest = "", key
  while true do
    local m, r = rest:match("^(%u+%-)(.+)$")
    if not m then break end
    mods, rest = mods .. m, r
  end
  if mods:find("SHIFT%-") then return end
  local shiftKey = mods .. "SHIFT-" .. rest
  local existing = GetBindingAction(shiftKey)
  if existing and existing ~= "" and existing ~= action then
    MF.Log("binding", shiftKey .. " already bound to " .. existing .. ", left alone")
    return
  end
  SetOverrideBinding(bindOwner, false, shiftKey, action)
  keys[#keys + 1] = shiftKey .. "->" .. action
end

local function ApplyBindings()
  if InCombatLockdown() then
    bindDirty = true
    MF.Log("binding", "in combat, binding setup deferred")
    return
  end
  bindDirty = false
  ClearOverrideBindings(bindOwner)
  local bound, keys = false, {}
  for _, action in ipairs({ "TOGGLESOCIAL", "TOGGLEFRIENDSTAB" }) do
    local k1, k2 = GetBindingKey(action)
    for _, key in ipairs({ k1 or false, k2 or false }) do
      if key then
        SetOverrideBindingClick(bindOwner, false, key, "OldFriendsToggle")
        bound = true
        keys[#keys + 1] = action .. "=" .. key
        BindShiftFallback(key, action, keys)
      end
    end
  end
  if not bound then
    SetOverrideBindingClick(bindOwner, false, "O", "OldFriendsToggle")
    keys[1] = "default O"
    BindShiftFallback("O", "TOGGLESOCIAL", keys)
  end
  MF.Log("binding", "override bindings -> OldFriendsToggle: " .. table.concat(keys, ", "))
end

local toggleBtn = CreateFrame("Button", "OldFriendsToggle", UIParent)
toggleBtn:SetScript("OnClick", function() MF.Toggle() end)

------------------------------------------------------------------ events
local ev = CreateFrame("Frame")
local EVENTS = {
  "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "UPDATE_BINDINGS", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
  -- friends / battle.net
  "FRIENDLIST_UPDATE", "BN_FRIEND_LIST_SIZE_CHANGED", "BN_FRIEND_INFO_CHANGED", "BN_FRIEND_ACCOUNT_ONLINE",
  "BN_FRIEND_ACCOUNT_OFFLINE", "BATTLE_NET_FRIEND_TAG_ENABLED_STATUS_UPDATED", "BN_CUSTOM_MESSAGE_CHANGED",
  -- own status
  "BN_INFO_CHANGED", "PLAYER_FLAGS_CHANGED", "BN_CONNECTED", "BN_DISCONNECTED",
  -- requests
  "BN_FRIEND_INVITE_ADDED", "BN_FRIEND_INVITE_REMOVED", "BN_FRIEND_INVITE_LIST_INITIALIZED",
  -- activity
  "SOCIAL_QUEUE_UPDATE", "GROUP_ROSTER_UPDATE",
  -- recent allies
  "RECENT_ALLIES_DATA_READY", "RECENT_ALLIES_CACHE_UPDATE", "RECENT_ALLY_DATA_UPDATED",
  "RECENT_ALLIES_SYSTEM_STATUS_UPDATED",
  -- ignore list
  "IGNORELIST_UPDATE", "BN_BLOCK_LIST_UPDATED",
  -- diagnostics: which call was blocked (see MF.OnBlocked in Core.lua)
  "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN",
  -- outcome of a secure /friend send (logged for a few seconds after the click, see MF.OnSystemMessage)
  "CHAT_MSG_SYSTEM",
}
-- RegisterEvent raises an error for an event name the client does not know, so each one is protected.
for _, name in ipairs(EVENTS) do
  if not pcall(ev.RegisterEvent, ev, name) then MF.Log("fallback", "event not registered: " .. name) end
end

local TOP_ONLY = { BN_INFO_CHANGED = true, PLAYER_FLAGS_CHANGED = true }
local TOP_EVENTS = { BN_INFO_CHANGED = true, PLAYER_FLAGS_CHANGED = true, BN_CONNECTED = true, BN_DISCONNECTED = true }
local INVITE_EVENTS = {
  BN_FRIEND_INVITE_ADDED = true, BN_FRIEND_INVITE_REMOVED = true, BN_FRIEND_INVITE_LIST_INITIALIZED = true,
}

ev:SetScript("OnEvent", function(_, event, arg1, arg2)
  if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
    MF.OnBlocked(event, arg1, arg2)
    return
  end
  if event == "CHAT_MSG_SYSTEM" then
    MF.OnSystemMessage(arg1)
    return
  end
  if event == "ADDON_LOADED" then
    if arg1 ~= ADDON then return end
    MF.Log("load", "ADDON_LOADED " .. ADDON)
    InitDB()
    MF.BuildClassMap()
    MF.CreateMainFrame()
    MF.Log("load", "ready")
    return
  end
  if event == "PLAYER_ENTERING_WORLD" or event == "UPDATE_BINDINGS" then
    MF.HookBlizzardAllies()
    ApplyBindings()
    if MF.frame then
      MF.LayoutTabs()
      MF.UpdateBadges()
    end
    return
  end
  if event == "PLAYER_REGEN_DISABLED" then
    MF.HideAllyLoaderForCombat() -- last moment a secure frame may be hidden / unanchored
    return
  end
  if event == "PLAYER_REGEN_ENABLED" then
    if bindDirty then ApplyBindings() end
    if MF.frame then
      MF.ReskinPending() -- secure buttons skipped during combat
      MF.UpdateAllyLoadButton()
    end
    return
  end
  if not MF.frame then return end

  if TOP_EVENTS[event] then MF.UpdateTopBar() end
  if INVITE_EVENTS[event] then
    MF.UpdateBadges()
    if event ~= "BN_FRIEND_INVITE_REMOVED" then MF.FlashRequests() end
  end
  if event == "RECENT_ALLIES_SYSTEM_STATUS_UPDATED" then MF.LayoutTabs() end
  if TOP_ONLY[event] then return end
  MF.RequestRefresh()
end)

------------------------------------------------------------------ slash commands
local USAGE = {
  "/of  (or /oldfriends)  - show or hide the window",
  "/of skin  - choose a look;  /of skin classic|enhanced|toggle  - set it directly (Classic = WoW panel, Enhanced = compact flat)",
  "/of scale <0.5-2>  - window scale",
  "/of reset  - reset position, scale and filters",
  "/of test  - toggle test mode (fake friends, allies, requests)",
  "/of log  - print the last 20 diagnostics lines;  /of log all  - full log window;  /of log clear",
  "/of debug on|off  - echo every log line to chat (blocked actions always print a warning)",
  "Add New Friend: BattleTags/emails are sent directly; character names go through Blizzard's own Add Friend window",
  "  (or a secure /friend button on the legacy friend system). Items marked \"Not available in addons\" are Blizzard restrictions.",
  "Click your status in the top bar for in-game Away/Busy (/afk, /dnd; does not change the Battle.net status).",
}

local function PrintUsage()
  MF.Print("commands:")
  for _, l in ipairs(USAGE) do MF.PrintRaw("  " .. l) end
end

local function LogCommand(rest)
  rest = (rest or ""):lower()
  if rest == "all" then
    MF.ShowLogWindow()
  elseif rest == "clear" then
    MF.LogClear()
    MF.Print("log cleared")
  else
    local lines = MF.LogLines(20)
    MF.Print(format("last %d of %d log lines (/of log all for everything, blocked by other addons: %d):",
      #lines, #MF.logBuf, MF.blockedOther or 0))
    for _, l in ipairs(lines) do MF.PrintRaw("  " .. l) end
  end
end

SLASH_OLDFRIENDS1, SLASH_OLDFRIENDS2 = "/of", "/oldfriends"
SlashCmdList["OLDFRIENDS"] = function(msg)
  local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
  cmd = (cmd or ""):lower()
  MF.SetAction("slash /of " .. cmd)
  if cmd == "log" then
    LogCommand(rest)
    return
  elseif cmd == "debug" then
    rest = (rest or ""):lower()
    if rest == "on" or rest == "off" then
      MF.DB.debug = (rest == "on")
      MF.Print("debug echo " .. rest)
    else
      MF.Print("debug echo is " .. (MF.DB.debug and "on" or "off") .. " (use /of debug on|off)")
    end
    return
  elseif cmd == "help" or cmd == "?" then
    PrintUsage()
    return
  end
  if not MF.frame then return end
  if cmd == "" then
    MF.Toggle()
  elseif cmd == "skin" then
    rest = (rest or ""):lower()
    if rest == "classic" or rest == "enhanced" or rest == "toggle" then
      MF.Print("skin: " .. MF.SetSkin(rest))
    else
      MF.Print("skin is " .. MF.SkinName() .. " (/of skin classic|enhanced|toggle sets it directly)")
      MF.ShowSkinChooser()
    end
  elseif cmd == "test" then
    MF.testMode = not MF.testMode
    MF.offset = 0
    MF.Log("test", "test mode " .. (MF.testMode and "on" or "off"))
    MF.Print("test mode " .. (MF.testMode and "on (fake friends, allies, requests)" or "off"))
    if MF.frame:IsShown() then
      MF.UpdateTopBar()
      MF.UpdateBadges()
      MF.Refresh()
    else
      MF.frame:Show()
    end
  elseif cmd == "reset" then
    local DB = MF.DB
    DB.point, DB.scale = nil, 1
    DB.width, DB.rows = nil, nil
    MF.ApplySize()
    wipe(DB.collapsed)
    MF.ClearFilters()
    DB.showOffline = false
    DB.lastTab = "friends"
    MF.ApplyPosition()
    MF.UpdateFilterButton()
    MF.Rebuild()
    MF.Print("position, scale and filters reset")
  elseif cmd == "scale" and tonumber(rest) then
    MF.DB.scale = math.min(2, math.max(0.5, tonumber(rest)))
    MF.frame:SetScale(MF.DB.scale)
  else
    PrintUsage()
  end
end
