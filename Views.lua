-- Old Friends v2 - Views: row renderers, tooltips, context menus, per-tab item lists, actions.
local _, MF = ...
local R = MF.Renderers
local format = string.format
local pcall = MF.PCall -- logs failures to the diagnostics log

-- Restricted-function policy: Blizzard marks some functions HasRestrictions = true in its API docs; add-ons
-- cannot call them (the client shows "Old Friends has been blocked from an action only available to the
-- Blizzard UI", and pcall does not hide it). Features that need one are either disabled with RESTRICTED_TIP
-- (C_BattleNet.SetBlocked: Unblock / Block Invites; Battle.net status) or routed through Blizzard's own secure code:
--   * adding a character friend: the stock Add Friend window (AddFriendFrame_Show, which then calls
--     C_BattleNet.SendTitleFriendInviteByName / C_FriendList.AddFriend itself from a real click), or, with the legacy
--     friend system, a SecureActionButtonTemplate macro button running "/friend Name" (see MF.Dialog, Menu.lua);
--   * /afk and /dnd macro buttons for the in-game flags (UI.lua).
local RESTRICTED_TIP = MF.RESTRICTED_TIP
local RESTRICTED_FULL = MF.RESTRICTED_TIP .. "\n" .. MF.RESTRICTED_ALT

local BNET_HEX = "82c4ff"
local GREY_HEX = "8a8a8a"

------------------------------------------------------------------ helpers
local function ColorName(text, hex) return "|cff" .. hex .. tostring(text) .. "|r" end

-- Shortens a verbose realm name such as "US2 Realm 8 PvP" to "US - PvP" (region + realm type).
-- Any name that does not match both parts is returned unchanged.
local REGIONS = { US = true, EU = true, KR = true, TW = true, CN = true }
-- Small inline icons (stock icon files, present in every client): sword = PvP, book = roleplay.
-- Realm type icons (stock icon files): crossed swords = PvP, mask = roleplay, shield = PvE.
local ICON_FILES = {
  sword = "Interface\\Icons\\Ability_DualWield",
  mask = "Interface\\Icons\\INV_Misc_Book_09", -- INV_Misc_Mask_01 renders blank on Forever
  shield = "Interface\\Icons\\INV_Shield_05",
}
local KIND_ICONS = { PvP = { "sword" }, PvE = { "shield" }, RP = { "mask" }, ["RP-PvP"] = { "mask", "sword" } }
local function KindIcons(key, size)
  local out = ""
  for _, k in ipairs(KIND_ICONS[key] or {}) do
    out = out .. "|T" .. ICON_FILES[k] .. ":" .. size .. ":" .. size .. ":0:0|t"
  end
  return out
end
local KINDS = { pvp = "PvP", pve = "PvE", rp = "RP", ["rp-pvp"] = "RP-PvP", rppvp = "RP-PvP" }
-- Region = any word that is a region code plus optional digits ("US2", "EU1"), anywhere in the name, so
-- prefixed names like "CAMWOW US1 Realm 3 PvE" work too. Type = the last word (PvP, PvE, RP, RP-PvP).
-- Returns region, kind label with its icon (both nil when the name is not in that shape).
local function ParseRealm(realm)
  if type(realm) ~= "string" then return nil end
  local region, last
  for word in realm:gmatch("%S+") do
    local code = word:match("^(%a%a)%d*$")
    if code and REGIONS[code:upper()] and not region then region = code:upper() end
    last = word
  end
  local kind = last and KINDS[last:lower()]
  if not (region and kind) then return nil end
  return region, KindIcons(kind, 14) .. " " .. kind, kind
end
MF.ParseRealm = ParseRealm

local function ShortRealm(realm)
  local region, kind = ParseRealm(realm)
  if region then return region .. " - " .. kind end
  return realm
end
MF.ShortRealm = ShortRealm

-- Small Horde / Alliance emblem (stock TargetingFrame textures, cropped to the emblem) for a faction name.
local function FactionIcon(name, size)
  local file
  if name == "Horde" or name == FACTION_HORDE then file = "UI-PVP-Horde"
  elseif name == "Alliance" or name == FACTION_ALLIANCE then file = "UI-PVP-Alliance" end
  if not file then return "" end
  size = size or 16
  return "|TInterface\\TargetingFrame\\" .. file .. ":" .. size .. ":" .. size .. ":0:0:64:64:5:36:2:39|t "
end
MF.FactionIcon = FactionIcon

local function SearchText()
  local f = MF.frame
  if not f then return "" end
  return MF.Trim(f.search:GetText()):lower()
end

local function ReportAvailable()
  return (ReportFrame and ReportFrame.InitiateReport and ReportInfo and ReportInfo.CreateReportInfoFromType
    and PlayerLocation and Enum and Enum.ReportType) and true or false
end

local function AfterAction()
  C_Timer.After(0.4, function() MF.RequestRefresh() end)
end

------------------------------------------------------------------ actions: friends
function MF.Whisper(e)
  MF.SetAction("whisper " .. tostring(e.name))
  MF.Log("action", "whisper " .. tostring(e.name) .. " (" .. tostring(e.kind) .. ")")
  if e.fake then MF.Print("(test) whisper " .. tostring(e.name)) return end
  if e.kind == "ally" then
    if ChatFrameUtil and ChatFrameUtil.SendTell then ChatFrameUtil.SendTell(e.fullName) end
    return
  end
  if e.kind == "legacy" then
    if ChatFrameUtil and ChatFrameUtil.SendTell then ChatFrameUtil.SendTell(e.name) end
    return
  end
  local name = (BNet_GetBNetAccountName and e.account and BNet_GetBNetAccountName(e.account)) or e.accountName or e.name
  if ChatFrameUtil and ChatFrameUtil.SendBNetTell then
    ChatFrameUtil.SendBNetTell(name)
  elseif ChatFrame_SendBNetTell then
    ChatFrame_SendBNetTell(name)
  end
end

function MF.ToggleFavorite(e)
  MF.SetAction("toggle favorite")
  MF.Log("action", "BNSetFriendFavoriteFlag " .. tostring(e.name) .. " -> " .. tostring(not e.isFavorite))
  if e.fake then MF.Print("(test) favorite toggled for " .. tostring(e.name)) return end
  if BNSetFriendFavoriteFlag and e.id then
    BNSetFriendFavoriteFlag(e.id, not e.isFavorite)
    AfterAction()
  else
    MF.Print("Favorites are unavailable.")
  end
end

function MF.SetNote(e)
  MF.SetAction("set note")
  if e.fake then MF.Print("(test) set note for " .. tostring(e.name)) return end
  if e.kind == "legacy" then
    MF.Prompt("Note for " .. tostring(e.name) .. ":", e.note or "", function(text)
      if C_FriendList and C_FriendList.SetFriendNotes then C_FriendList.SetFriendNotes(e.name, text) end
      AfterAction()
    end, "Save")
    return
  end
  if not BNSetFriendNote then MF.Print("Setting notes is unavailable in this client.") return end
  MF.Prompt("Note for " .. tostring(e.name) .. ":", e.note or "", function(text)
    BNSetFriendNote(e.id, text)
    AfterAction()
  end, "Save")
end

local function CustomNamesEnabled()
  local c = C_BattleNet
  if not (c and c.AreTitleFriendCustomNamesEnabled and c.SetCustomTitleFriendName) then return false end
  local ok, v = pcall(c.AreTitleFriendCustomNamesEnabled)
  return (ok and v) and true or false
end

function MF.SetCustomName(e)
  MF.SetAction("set custom name")
  if e.fake then MF.Print("(test) set custom name for " .. tostring(e.name)) return end
  MF.Prompt("Custom name for " .. tostring(e.accountName or e.name) .. ":", e.customName or "", function(text)
    C_BattleNet.SetCustomTitleFriendName(e.id, text)
    AfterAction()
  end, "Save")
end

function MF.ToggleTag(e, value)
  MF.SetAction("toggle tag")
  MF.Log("action", "C_BattleNet.SetFriendTags " .. tostring(e.name) .. " tag " .. tostring(value))
  local new, found = {}, false
  for _, t in ipairs(e.tags or {}) do
    if t == value then found = true else new[#new + 1] = t end
  end
  if not found then new[#new + 1] = value end
  if e.fake then
    e.tags = new
    MF.Rebuild()
    return
  end
  if C_BattleNet and C_BattleNet.SetFriendTags and e.id then
    local ok, err = pcall(C_BattleNet.SetFriendTags, e.id, new)
    if ok then
      e.tags = new
      MF.Rebuild()
      AfterAction()
    else
      MF.Print("Could not set tags: " .. tostring(err))
    end
  end
end

function MF.RemoveFriend(e)
  MF.SetAction("remove friend")
  if e.fake then MF.Print("(test) remove " .. tostring(e.name)) return end
  if e.kind == "legacy" then
    MF.Confirm(format("Remove %s from your friends list?", tostring(e.name)), function()
      if C_FriendList and C_FriendList.RemoveFriend then C_FriendList.RemoveFriend(e.name) end
      AfterAction()
    end, "Remove")
    return
  end
  local msg = format("Remove %s from your Battle.net friends?", tostring(e.name))
  if BNRemoveFriend then
    -- Own confirm dialog + BNRemoveFriend. (Blizzard's CONFIRM_REMOVE_BN_FRIEND popup is not used: its
    -- accept handler would read data we passed in from add-on code and run tainted.)
    MF.Confirm(msg, function()
      MF.Log("action", "BNRemoveFriend " .. tostring(e.name))
      BNRemoveFriend(e.id)
      AfterAction()
    end, "Remove")
  else
    MF.Log("fallback", "BNRemoveFriend missing")
    MF.Print("Removing Battle.net friends is unavailable in this client.")
  end
end

function MF.ReportFriend(e)
  MF.SetAction("report friend")
  if not ReportAvailable() then return end
  local ok, err = pcall(function()
    local loc = PlayerLocation:CreateFromBattleNetID(e.id)
    local info = ReportInfo:CreateReportInfoFromType(Enum.ReportType.Friend)
    ReportFrame:InitiateReport(info, e.name, loc, true)
  end)
  if not ok then MF.Print("Report failed: " .. tostring(err)) end
end

------------------------------------------------------------------ actions: party / star
function MF.DoParty(e, anchor)
  if not e then return end
  MF.SetAction("invite " .. tostring(e.name))
  if e.kind == "ally" then
    if not e.online and not e.cached then MF.Print("Player is offline.") return end
    if e.inviteBlocked then MF.Print(e.inviteReason or "Cannot invite: different realm ruleset.") return end
    if e.fake then MF.Print("(test) would invite " .. tostring(e.name)) return end
    MF.InviteByName(e.fullName, e.guid)
    return
  end
  local inv = e.invite
  if not inv or not inv.enabled then
    MF.Print((inv and inv.reason) or "Cannot invite right now.")
    return
  end
  if e.fake then MF.Print("(test) would " .. inv.label:lower() .. " " .. tostring(e.name)) return end
  if e.kind == "legacy" then
    MF.InviteByName(e.name, e.guid)
    return
  end
  local targets = inv.targets
  if #targets == 1 then
    MF.InviteGameAccount(targets[1].gameAccountID, targets[1].playerGuid)
    return
  end
  local items = { { title = inv.label .. " " .. tostring(e.name) } }
  for _, ga in ipairs(targets) do
    local label = ColorName(ga.characterName or "?", MF.ClassHex(ga.classFilename))
    local realm = ga.realmDisplayName or ga.realmName
    if realm and realm ~= "" then label = label .. "-" .. ShortRealm(realm) end
    if ga.characterLevel and ga.characterLevel > 0 then label = label .. "  " .. ga.characterLevel end
    items[#items + 1] = { text = label, func = function() MF.InviteGameAccount(ga.gameAccountID, ga.playerGuid) end }
  end
  MF.OpenMenu(anchor, items)
end

function MF.PartyClick(row)
  MF.SetAction("click party btn")
  MF.DoParty(row.entry, row.party)
end

function MF.PartyEnter(row)
  local e = row.entry
  if not e then return end
  local tt = GameTooltip
  tt:SetOwner(row.party, "ANCHOR_LEFT")
  if e.kind == "ally" then
    if (e.online or e.cached) and e.inviteBlocked then
      tt:AddLine("Invite to party", 1, 1, 1)
      tt:AddLine(e.inviteReason or "Different realm ruleset", 1, 0.25, 0.25, true)
    elseif e.online then
      tt:AddLine("Invite to party", 1, 1, 1)
    elseif e.cached then
      tt:AddLine("Invite to party", 1, 1, 1)
      tt:AddLine("Saved list: online status unknown until Recent Allies is loaded.", 0.7, 0.7, 0.7, true)
    else
      tt:AddLine("Invite to party", 1, 1, 1)
      tt:AddLine("Player is offline", 1, 0.25, 0.25)
    end
  else
    local inv = e.invite
    if inv and inv.enabled then
      tt:AddLine(inv.label, 1, 1, 1)
      if #inv.targets > 1 then tt:AddLine(format("%d characters: pick one", #inv.targets), 0.7, 0.7, 0.7) end
      if inv.mode == "REQUEST" and e.queue then
        for _, n in ipairs(e.queue.names or {}) do tt:AddLine(n, 1, 0.7, 0.3) end
      end
    else
      tt:AddLine("Invite", 1, 1, 1)
      tt:AddLine((inv and inv.reason) or "Unavailable", 1, 0.25, 0.25, true)
    end
  end
  tt:Show()
end

function MF.TogglePin(e)
  MF.SetAction("toggle pin")
  MF.Log("action", "C_RecentAllies.SetRecentAllyPinned " .. tostring(e.name) .. " -> " .. tostring(not e.pinned))
  if e.fake then MF.Print("(test) pin toggled for " .. tostring(e.name)) return end
  if e.cached then MF.Print("Load Recent Allies first (saved list).") return end
  if C_RecentAllies and C_RecentAllies.SetRecentAllyPinned and e.guid then
    C_RecentAllies.SetRecentAllyPinned(e.guid, not e.pinned)
  else
    MF.Print("Pinning is unavailable.")
  end
end

function MF.StarClick(row)
  local item = row.item
  if not item then return end
  MF.SetAction("click star")
  if item.type == "friend" and item.e.kind == "bnet" then
    MF.ToggleFavorite(item.e)
  elseif item.type == "ally" then
    MF.TogglePin(item.e)
  end
end

function MF.StarEnter(row)
  local item = row.item
  if not item then return end
  local tt = GameTooltip
  tt:SetOwner(row.star, "ANCHOR_RIGHT")
  if item.type == "ally" then
    tt:AddLine(item.e.pinned and "Pinned (click to unpin)" or "Click to pin", 1, 1, 1)
  else
    tt:AddLine(item.e.isFavorite and "Favorite (click to remove)" or "Click to add to favorites", 1, 1, 1)
  end
  tt:Show()
end

------------------------------------------------------------------ actions: requests / ignore
function MF.RequestMenuItems(inv)
  local items = { { title = tostring(inv.accountName or "?") } }
  local levels = Enum and Enum.BattleNetFriendLevel
  if ReportAvailable() then
    items[#items + 1] = { text = "Report", func = function()
      if MF.testMode then MF.Print("(test) report") return end
      local ok, err = pcall(function()
        local loc = PlayerLocation:CreateFromBattleNetID(inv.inviteID)
        local info = ReportInfo:CreateReportInfoFromType(Enum.ReportType.Friend)
        ReportFrame:InitiateReport(info, inv.accountName, loc, true)
      end)
      if not ok then MF.Print("Report failed: " .. tostring(err)) end
    end }
  end
  local isTitle = levels and levels.Title ~= nil and inv.friendLevel == levels.Title
  if inv.friendLevel ~= nil and not isTitle then
    -- Blocking the sender needs C_BattleNet.SetBlocked (restricted), so this entry is shown disabled.
    items[#items + 1] = { text = "Block Invites", disabled = true, tooltip = RESTRICTED_FULL, func = function() end }
  end
  return items
end

function MF.RowButton(row, which)
  local item = row.item
  if not item then return end
  MF.SetAction("row button " .. which .. " (" .. tostring(item.type) .. ")")
  MF.Log("action", "row button " .. which .. " on " .. tostring(item.type))
  if item.type == "request" then
    local inv = item.inv
    if which == "C" then
      MF.OpenMenu(row.btnC, MF.RequestMenuItems(inv))
      return
    end
    if MF.testMode then MF.Print("(test) " .. (which == "A" and "accept " or "decline ") .. tostring(inv.accountName)) return end
    if which == "A" then
      if BNAcceptFriendInvite then BNAcceptFriendInvite(inv.inviteID) else MF.Print("Accepting is unavailable.") end
    else
      if BNDeclineFriendInvite then BNDeclineFriendInvite(inv.inviteID) else MF.Print("Declining is unavailable.") end
    end
    AfterAction()
  elseif item.type == "ignore" then
    if MF.testMode then MF.Print("(test) unblock " .. tostring(item.name)) return end
    local C = C_FriendList
    if C and C.DelIgnore then
      C.DelIgnore(item.name)
    elseif C and C.DelIgnoreByIndex then
      C.DelIgnoreByIndex(item.index)
    end
    AfterAction()
  elseif item.type == "block" then
    -- Unblocking a Battle.net account needs C_BattleNet.SetBlocked, which is restricted: never called.
    MF.Print("Unblock: " .. RESTRICTED_TIP .. " " .. MF.RESTRICTED_ALT)
  end
end

-- Tooltip for the first row button (explains the disabled Unblock on blocked Battle.net accounts).
function MF.RowButtonEnter(row, which, btn)
  local item = row.item
  if which == "A" and item and item.type == "block" then
    GameTooltip:SetOwner(btn, "ANCHOR_TOP")
    GameTooltip:AddLine(RESTRICTED_TIP, 1, 0.3, 0.3, true)
    GameTooltip:AddLine(MF.RESTRICTED_ALT, 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
  end
end

function MF.BlockPlayerPrompt()
  MF.SetAction("block player prompt")
  MF.Prompt("Block player (character name):", "", function(text)
    text = MF.Trim(text)
    if text == "" then return end
    if MF.testMode then MF.Print("(test) block " .. text) return end
    if C_FriendList and C_FriendList.AddIgnore then
      C_FriendList.AddIgnore(text)
      AfterAction()
    else
      MF.Print("Blocking is unavailable.")
    end
  end, "Block")
end

------------------------------------------------------------------ Add New Friend
-- Friend requests sent from an add-on can only be BattleTag / email invites (BNSendFriendInvite, which the
-- stock Add Friend window also calls). Character names go through Blizzard's own code, see MF.AddFriend.
function MF.SendFriendInvite(text)
  text = MF.Trim(text)
  if text == "" then return end
  if text:find("[@#]") and BNSendFriendInvite then
    MF.Log("action", "BNSendFriendInvite " .. text)
    BNSendFriendInvite(text, "")
    return
  end
  MF.Log("action", "add friend by name has no add-on route here: " .. text)
  MF.Print("Adding a friend by character name: " .. RESTRICTED_TIP .. " Use Blizzard's Add Friend window.")
end

local function LegacyFriendsOn()
  local L = C_FriendList
  if not (L and L.IsLegacyFriendSystemEnabled) then return false end
  local ok, v = pcall(L.IsLegacyFriendSystemEnabled)
  return (ok and v) and true or false
end

local function TitleFriendsOn()
  local c = C_BattleNet
  if not (c and c.AreTitleFriendsEnabled) then return false end
  local ok, v = pcall(c.AreTitleFriendsEnabled)
  return (ok and v) and true or false
end
MF.TitleFriendsOn, MF.LegacyFriendsOn = TitleFriendsOn, LegacyFriendsOn

-- Result watcher: after a secure send we cannot know the outcome, so for a few seconds system messages that
-- mention the name (or "friend") are written to the log; Blizzard's own chat line already shows them to the user.
local pendingSend
local function WatchResult(label, name)
  pendingSend = { label = label, name = ((tostring(name or ""):match("^[^-]+")) or ""):lower(), expires = GetTime() + 8 }
end

function MF.OnSystemMessage(text)
  local p = pendingSend
  if not p or type(text) ~= "string" then return end
  if GetTime() > p.expires then
    pendingSend = nil
    return
  end
  local low = text:lower()
  if (p.name ~= "" and low:find(p.name, 1, true)) or low:find("friend", 1, true) then
    MF.Log("result", p.label .. " -> system message: " .. text)
    AfterAction()
  end
end

-- Dialog resolver for "add a friend by name": decides per keystroke whether the OK button is the normal
-- button (BattleTag / email through BNSendFriendInvite) or the secure macro button (character name).
local function ResolveAddByName(text)
  text = MF.Trim(text)
  if text == "" then return { mode = "blocked" } end
  if text:find("[@#]") then
    return { mode = "insecure", note = "Sent as a Battle.net friend request." }
  end
  if text:find("[%s/|;]") then
    return { mode = "blocked", note = "Enter one character name (Name or Name-Realm)." }
  end
  if MF.testMode then
    return { mode = "insecure", note = "(test) a secure /friend button is used here." }
  end
  if not LegacyFriendsOn() then
    return { mode = "blocked", note = "By name: use Blizzard's Add Friend window. " .. RESTRICTED_TIP }
  end
  local L = C_FriendList
  if L and L.GetFriendInfo and L.GetFriendInfo(text) then
    -- /friend toggles (C_FriendList.AddOrRemoveFriend): never arm it for someone already on the list
    return { mode = "blocked", note = "Already on your friend list (/friend would remove them)." }
  end
  return { mode = "secure", macro = "/friend " .. text, note = "Runs /friend " .. text }
end

local function AddDialogAccept(text)
  text = MF.Trim(text or "")
  if text == "" then return end
  if MF.testMode then
    MF.Print("(test) would run: " .. (text:find("[@#]") and "BNSendFriendInvite " or "/friend ") .. text)
    return
  end
  MF.SendFriendInvite(text)
end

local function AddDialogSent(text, macro)
  MF.Log("action", "secure macro sent: " .. tostring(macro))
  MF.Print("Sent: " .. tostring(macro) .. " (the result is shown in chat)")
  WatchResult(tostring(macro), text)
end

-- Add New Friend (bottom button) and, with prefill = "Name-Realm", Add WoW Friend for a recent ally.
-- Routes (investigated in the Blizzard source):
--   * Blizzard's "/friend" slash command only does C_FriendList.AddOrRemoveFriend and only when the LEGACY friend
--     system is enabled; there is NO slash command that sends a Battle.net WoW-friend (title friend) request.
--   * So with title friends enabled the request has to come from Blizzard's own Add Friend window
--     (AddFriendFrame_Accept -> C_BattleNet.SendTitleFriendInviteByName) from a real click: we open that window,
--     optionally pre-filled, and the user presses Send Request there.
--   * AddFriendFrame_Show itself calls C_FriendList.AddFriend when you target another player and legacy friends
--     are on; from add-on code that would be blocked, so that case uses the secure /friend dialog instead.
--   * Legacy friend system only: our dialog with a secure "/friend Name" macro button.
function MF.AddFriend(prefill)
  MF.SetAction("add friend")
  local disabled, reason = MF.FriendsDisabled()
  if disabled then MF.Print(reason) return end
  local legacy, title = LegacyFriendsOn(), TitleFriendsOn()
  local human = (UnitIsHumanPlayer and UnitIsHumanPlayer("target")) and true or false
  local useStock = (title or not legacy) and not (legacy and human) and not MF.testMode
  MF.Log("action", format("add friend: legacy=%s title=%s humanTarget=%s -> %s", tostring(legacy), tostring(title),
    tostring(human), MF.testMode and "test dialog" or (useStock and "stock Add Friend window" or "secure /friend dialog")))
  if useStock then
    if not _G.AddFriendFrame_Show and C_AddOns and C_AddOns.LoadAddOn then
      MF.Log("fallback", "loading Blizzard_AddFriend")
      pcall(C_AddOns.LoadAddOn, "Blizzard_AddFriend")
    end
    if type(_G.AddFriendFrame_Show) == "function" then
      local ok = pcall(_G.AddFriendFrame_Show)
      MF.Log("action", "AddFriendFrame_Show " .. (ok and "ok" or "failed"))
      if ok then
        if prefill and _G.AddFriendNameEditBox then
          pcall(_G.AddFriendNameEditBox.SetText, _G.AddFriendNameEditBox, prefill)
          MF.Print("Add Friend window opened for " .. prefill .. ": press Send Request there.")
        end
        return
      end
    else
      MF.Log("fallback", "AddFriendFrame_Show missing")
    end
  end
  MF.Dialog({
    message = (legacy or MF.testMode) and "Add a friend (character name, or BattleTag#1234 / email):"
      or "Add a friend (BattleTag#1234 or email):",
    edit = true, text = prefill or "", okText = "Add",
    resolve = ResolveAddByName, onAccept = AddDialogAccept, onSent = AddDialogSent,
  })
end

-- Legacy-only clients: "Add Friend" for a recent ally = confirm dialog with a secure "/friend Name" button.
function MF.AllyAddLegacyFriend(e)
  MF.SetAction("ally add friend")
  local name = e.fullName or e.name
  MF.Log("action", "ally add (legacy /friend dialog) " .. tostring(name))
  MF.Dialog({
    message = format("Add %s as a friend?", tostring(name)), edit = false, okText = "Add",
    resolve = function() return ResolveAddByName(name) end,
    onAccept = function() AddDialogAccept(name) end,
    onSent = function(_, macro) AddDialogSent(name, macro) end,
  })
end

------------------------------------------------------------------ tooltips
local function TagLabels(e)
  local out = {}
  for _, t in ipairs(e.tags or {}) do
    local d = MF.TagDef(t)
    if d then out[#out + 1] = d.label end
  end
  return table.concat(out, ", ")
end

function MF.FriendTooltip(row, e)
  local tt = GameTooltip
  tt:SetOwner(row, "ANCHOR_RIGHT")
  local title = tostring(e.name or "?")
  if e.isFavorite then title = title .. " |cffffd100*|r" end
  tt:AddLine(title, 1, 1, 1)
  if e.battleTag then tt:AddLine(e.battleTag, 0.51, 0.77, 1) end

  if e.kind == "legacy" then
    if e.level or e.className then
      tt:AddLine(format("Level %s %s", e.level or "?", e.className or ""), 1, 1, 1)
    end
    if e.area then tt:AddLine(e.area, 0.8, 0.8, 0.8) end
  elseif e.online then
    local ga = e.ga or {}
    if e.richOnly then
      if e.charName then tt:AddLine(e.charName, 1, 1, 1) end
      if e.rich then tt:AddLine(e.rich, 0.8, 0.8, 0.8, true) end
    else
      local realm = MF.NotNil(ga.realmDisplayName) or MF.NotNil(ga.realmName) or e.realmText
      local full = tostring(e.charName or "?")
      -- A verbose server name ("CAMWOW US2 Realm 5 PvE") is dropped from the name line and its type is shown
      -- on the faction line instead ("Alliance - PvE"). Normal realm names stay as Name-Realm.
      local _, realmKind = ParseRealm(realm)
      if not realmKind and realm and realm ~= "" then full = full .. "-" .. realm end
      tt:AddLine(full, 1, 1, 1)
      tt:AddLine(format("Level %s %s", e.level or "?", e.className or ""), 1, 1, 1)
      if ga.raceName then tt:AddLine(ga.raceName, 0.8, 0.8, 0.8) end
      if e.area then tt:AddLine(e.area, 0.8, 0.8, 0.8) end
      if ga.factionName or realmKind then
        local line = ga.factionName and (FactionIcon(ga.factionName) .. ga.factionName) or ""
        if realmKind then line = line .. (line ~= "" and " - " or "") .. realmKind end
        if ga.isInCurrentRegion == false then line = line .. " (other region)" end
        tt:AddLine(line, 0.8, 0.8, 0.8)
      end
    end
    if e.differentProject then
      tt:AddLine("Playing a different version of World of Warcraft", 1, 0.6, 0.2, true)
    end
    if e.queue then
      tt:AddLine("Friend is in a group", 0.5, 0.7, 1)
      for _, n in ipairs(e.queue.names or {}) do tt:AddLine("Queue: " .. tostring(n), 1, 0.7, 0.3, true) end
    end
  end

  if e.note then tt:AddLine("Note: " .. e.note, 1, 0.82, 0, true) end
  if MF.tagsOn then
    local labels = TagLabels(e)
    if labels ~= "" then tt:AddLine("Tags: " .. labels, 0.8, 0.9, 1, true) end
  end
  if e.customMessage then
    local age = MF.RelativeTime(e.customMessageTime)
    tt:AddLine(e.customMessage .. (age and (" (" .. age .. ")") or ""), 0.51, 0.77, 1, true)
  end
  if e.kind == "bnet" and not e.online then
    tt:AddLine("Last online: " .. MF.LastOnlineText(e.lastOnlineTime), 0.6, 0.6, 0.6)
  end

  if e.kind == "bnet" and e.online and not e.fake then
    local list = MF.GetGameAccounts(e)
    local shown, extra = 0, 0
    for i = 2, #list do
      local g = list[i]
      if g.clientProgram ~= "App" and g.clientProgram ~= "CLNT" and g.clientProgram ~= "BSAp" then
        if shown < 4 then
          local label = MF.ClientLabel(g.clientProgram) or "?"
          local text = g.characterName or g.richPresence or ""
          tt:AddLine(label .. ": " .. tostring(text), 0.7, 0.7, 0.7)
          shown = shown + 1
        else
          extra = extra + 1
        end
      end
    end
    if extra > 0 then tt:AddLine(format("and %d more", extra), 0.6, 0.6, 0.6) end
  end

  tt:AddLine("Click: whisper   Right-click: menu", 0.4, 0.4, 0.4)
  tt:Show()
end

function MF.AllyTooltip(row, e)
  local tt = GameTooltip
  tt:SetOwner(row, "ANCHOR_RIGHT")
  tt:AddLine(ColorName(e.fullName or e.name, MF.ClassHex(e.classFile)), 1, 1, 1)
  if e.level then tt:AddLine("Level " .. e.level, 1, 1, 1) end
  if e.location then tt:AddLine(e.location, 0.8, 0.8, 0.8) end
  if e.pinned then tt:AddLine("Pinned", 1, 0.82, 0) end
  if e.note then tt:AddLine("Note: " .. e.note, 1, 0.82, 0, true) end
  if #e.interactions > 0 then
    tt:AddLine(" ")
    tt:AddLine("Recent interactions", 0.6, 0.8, 1)
    for i = 1, math.min(#e.interactions, 6) do
      local it = e.interactions[i]
      local age = MF.RelativeTime(it.timestamp)
      tt:AddLine(tostring(it.description or "?") .. (age and ("  " .. age) or ""), 0.85, 0.85, 0.85, true)
    end
  end
  tt:AddLine("Click: whisper   Right-click: menu", 0.4, 0.4, 0.4)
  tt:Show()
end

function MF.RowEnter(row)
  local item = row.item
  if not item then return end
  if item.type == "friend" then
    MF.FriendTooltip(row, item.e)
  elseif item.type == "ally" then
    MF.AllyTooltip(row, item.e)
  end
end

------------------------------------------------------------------ context menus
function MF.FriendMenu(row, e)
  local items = { { title = tostring(e.name or "?") } }
  local function add(it) items[#items + 1] = it end

  if e.online and e.invite then
    local inv = e.invite
    add({ text = inv.label, disabled = not inv.enabled, tooltip = (not inv.enabled) and inv.reason or nil,
      func = function() MF.DoParty(e, row) end })
  end
  add({ text = "Whisper", func = function() MF.Whisper(e) end })
  add({ text = "Set Note", func = function() MF.SetNote(e) end })

  if e.kind == "bnet" then
    add({ text = e.isFavorite and "Remove from Favorites" or "Add to Favorites", func = function() MF.ToggleFavorite(e) end })
    if MF.tagsOn then
      local sub = {}
      local lastGroup
      for _, def in ipairs(MF.TAG_DEFS) do
        if MF.TagSupported(def) then
          if def.group ~= lastGroup then
            if lastGroup then sub[#sub + 1] = { divider = true } end
            sub[#sub + 1] = { title = (def.group == "interests") and "Interests" or "Roles" }
            lastGroup = def.group
          end
          local value = def.value
          sub[#sub + 1] = {
            text = def.label, checkbox = true, keepOpen = true,
            checked = function()
              for _, t in ipairs(e.tags or {}) do
                if t == value then return true end
              end
              return false
            end,
            func = function() MF.ToggleTag(e, value) end,
          }
        end
      end
      if #sub > 0 then add({ text = "Tags", sub = sub }) end
    end
    if e.isTitle and (MF.testMode or CustomNamesEnabled()) then
      add({ text = "Set Custom Name", func = function() MF.SetCustomName(e) end })
    end
    if e.battleTag then
      add({ text = "Copy BattleTag", func = function() MF.ShowCopy(e.battleTag, "BattleTag (Ctrl+C to copy):") end })
    end
  end

  add({ divider = true })
  add({ text = "Remove Friend", func = function() MF.RemoveFriend(e) end })
  if e.kind == "bnet" and ReportAvailable() then
    add({ text = "Report", func = function() MF.ReportFriend(e) end })
  end
  MF.OpenMenu(row, items)
end

function MF.AllyMenu(row, e)
  local items = { { title = tostring(e.name or "?") } }
  local function add(it) items[#items + 1] = it end
  add({ text = "Whisper", func = function() MF.Whisper(e) end })
  local canInvite = e.online or e.cached
  add({ text = "Invite", disabled = not canInvite, tooltip = (not canInvite) and "Player is offline" or nil,
    func = function() MF.DoParty(e, row) end })
  -- Add WoW Friend: the add-on cannot call C_BattleNet.SendTitleFriendInviteByName (restricted), so this opens
  -- Blizzard's Add Friend window pre-filled with the character; its Send Request button does the real work.
  if TitleFriendsOn() or MF.testMode then
    add({ text = "Add WoW Friend", func = function()
      MF.SetAction("ally add WoW friend")
      MF.AddFriend(e.fullName or e.name)
    end })
  elseif LegacyFriendsOn() then
    add({ text = "Add Friend", func = function() MF.AllyAddLegacyFriend(e) end })
  end
  local canNote = MF.testMode
  if not canNote and not e.cached and C_RecentAllies and C_RecentAllies.CanSetRecentAllyNote and C_RecentAllies.SetRecentAllyNote and e.guid then
    local ok, v = pcall(C_RecentAllies.CanSetRecentAllyNote, e.guid)
    canNote = ok and v and true or false
  end
  if canNote then
    add({ text = "Set Note", func = function()
      MF.Prompt("Note for " .. tostring(e.name) .. ":", e.note or "", function(text)
        if e.fake then MF.Print("(test) note saved") return end
        C_RecentAllies.SetRecentAllyNote(e.guid, text)
      end, "Save")
    end })
  end
  add({ text = e.pinned and "Unpin" or "Pin", func = function() MF.TogglePin(e) end })
  add({ text = "Ignore", func = function()
    MF.Log("action", "C_FriendList.AddOrDelIgnore " .. tostring(e.fullName))
    if e.fake then MF.Print("(test) ignore " .. tostring(e.name)) return end
    if C_FriendList and C_FriendList.AddOrDelIgnore then C_FriendList.AddOrDelIgnore(e.fullName) end
  end })
  add({ text = "Copy Character Name", func = function() MF.ShowCopy(e.fullName, "Character name (Ctrl+C to copy):") end })
  if ReportAvailable() then
    add({ text = "Report", func = function()
      if e.fake then MF.Print("(test) report") return end
      local ok, err = pcall(function()
        local loc = PlayerLocation:CreateFromGUID(e.guid)
        local info = ReportInfo:CreateReportInfoFromType(Enum.ReportType.RecentAlly)
        ReportFrame:InitiateReport(info, e.fullName, loc)
      end)
      if not ok then MF.Print("Report failed: " .. tostring(err)) end
    end })
  end
  MF.OpenMenu(row, items)
end

------------------------------------------------------------------ filter menu
local function StatusCheck(label, key)
  return {
    text = label, checkbox = true, keepOpen = true,
    checked = function() return MF.DB.filter[key] end,
    func = function()
      MF.DB.filter[key] = not MF.DB.filter[key]
      MF.offset = 0
      MF.UpdateFilterButton()
      MF.Rebuild()
    end,
  }
end

local function AllyStatusCheck(label, key)
  return {
    text = label, checkbox = true, keepOpen = true,
    checked = function() return MF.DB.allyFilter[key] end,
    func = function()
      MF.DB.allyFilter[key] = not MF.DB.allyFilter[key]
      MF.offset = 0
      MF.UpdateFilterButton()
      MF.Rebuild()
    end,
  }
end

function MF.OpenFilterMenu(owner)
  MF.SetAction("open filter menu")
  local items = {}
  if MF.tab == "allies" then
    items[#items + 1] = { title = "Status" }
    items[#items + 1] = AllyStatusCheck("Online", "online")
    items[#items + 1] = AllyStatusCheck("Away", "away")
    items[#items + 1] = AllyStatusCheck("Busy", "busy")
    items[#items + 1] = AllyStatusCheck("Offline", "offline")
    items[#items + 1] = { divider = true }
    items[#items + 1] = { text = "Clear filters", func = function()
      MF.ClearFilters()
      MF.UpdateFilterButton()
      MF.Rebuild()
    end }
    MF.OpenMenu(owner, items)
    return
  end
  items[#items + 1] = { text = "Status", sub = {
    StatusCheck("Online", "online"), StatusCheck("Away", "away"), StatusCheck("Busy", "busy"),
    StatusCheck("Offline", "offline"),
    StatusCheck("In Queue", "inQueue"), StatusCheck("Available for Queue", "availableForQueue"),
  } }
  if MF.tagsOn then
    local sub, lastGroup = {}, nil
    for _, def in ipairs(MF.TAG_DEFS) do
      if MF.TagSupported(def) then
        if def.group ~= lastGroup then
          if lastGroup then sub[#sub + 1] = { divider = true } end
          sub[#sub + 1] = { title = (def.group == "interests") and "Interests" or "Roles" }
          lastGroup = def.group
        end
        local value = def.value
        sub[#sub + 1] = {
          text = def.label, checkbox = true, keepOpen = true,
          checked = function() return MF.DB.filter.tags[value] end,
          func = function()
            MF.DB.filter.tags[value] = (not MF.DB.filter.tags[value]) or nil
            MF.offset = 0
            MF.UpdateFilterButton()
            MF.Rebuild()
          end,
        }
      end
    end
    if #sub > 0 then items[#items + 1] = { text = "Tags", sub = sub } end
  end
  items[#items + 1] = { divider = true }
  items[#items + 1] = {
    text = "Show offline", checkbox = true, keepOpen = true,
    checked = function() return MF.DB.showOffline end,
    func = function()
      MF.DB.showOffline = not MF.DB.showOffline
      MF.offset = 0
      MF.UpdateFilterButton()
      MF.Rebuild()
    end,
  }
  items[#items + 1] = { text = "Clear filters", func = function()
    MF.ClearFilters()
    MF.UpdateFilterButton()
    MF.Rebuild()
  end }
  MF.OpenMenu(owner, items)
end

------------------------------------------------------------------ row renderers
local function ExtraText(e)
  local parts = {}
  local q = e.queue
  if q then
    if q.kind == "PvE" then parts[#parts + 1] = "|cffff9a3c[PvE]|r"
    elseif q.kind == "PvP" then parts[#parts + 1] = "|cffff5555[PvP]|r"
    else parts[#parts + 1] = "|cff7fa8ff[Grp]|r" end
  end
  if MF.tagsOn then
    local shown = 0
    for _, t in ipairs(e.tags or {}) do
      local d = MF.TagDef(t)
      if d then
        if shown < 3 then parts[#parts + 1] = "|cff" .. d.hex .. d.short .. "|r" end
        shown = shown + 1
      end
    end
    if shown > 3 then parts[#parts + 1] = "|cff9a9a9a+" .. (shown - 3) .. "|r" end
  end
  return table.concat(parts, " ")
end

local function StyleParty(btn, enabled, mode, inGroup)
  local base = inGroup and "friends-icon-friendsInGroup" or "friends-icon-friendsAvailable"
  local atlas
  if enabled then atlas = MF.PickAtlas(base) else atlas = MF.PickAtlas(base .. "-dis", base) end
  local txt, r, g, b = "+", 0.3, 1, 0.3
  if mode == "REQUEST" then txt, r, g, b = "R", 1, 0.6, 0.2
  elseif mode == "SUGGEST" then txt, r, g, b = "?", 1, 0.9, 0.3 end
  if not enabled then r, g, b = 0.45, 0.45, 0.45 end
  MF.SetIcon(btn, atlas, txt, r, g, b)
  btn:SetAlpha(enabled and 1 or 0.6)
end

local function CharText(e)
  if not e.online then return "" end
  if e.isWoW and e.charName then
    local s = ColorName(e.charName, MF.ClassHex(e.classFile))
    if e.level then s = s .. " |cffaaaaaaLvl " .. e.level .. "|r" end
    return s
  end
  return ColorName(MF.ClientLabel(e.client) or "?", "8899aa")
end

R.header = function(row, item)
  MF.LayoutRow(row, "header")
  row.bg:Show()
  if item.plain then
    row.name:SetText("|cffffd100" .. item.plain .. "|r")
  else
    row.sign:Show()
    row.sign:SetText(item.collapsed and "+" or "-")
    row.name:SetText(format("|cffffd100%s|r |cff9a9a9a(%d/%d)|r", item.text, item.online, item.total))
  end
end

R.message = function(row, item)
  MF.LayoutRow(row, "message")
  row.name:SetText("|cff9a9a9a" .. tostring(item.text) .. "|r")
end

R.friend = function(row, item)
  local e = item.e
  MF.LayoutRow(row, "friend")
  row.entry = e
  row.dot:Show()
  MF.SetDot(row.dot, e.presence)

  if e.kind == "bnet" then
    row.star:Show()
    local atlas = MF.PickAtlas(e.online and "friends-icon-favorites" or "friends-icon-favorites-dis", "friends-icon-favorites")
    MF.SetIcon(row.star, atlas, "*", 1, 0.82, 0)
    row.star.dimmable = not e.isFavorite
  end

  local hex
  if not e.online then hex = GREY_HEX
  elseif e.isTitle then hex = "ffffff"
  else hex = BNET_HEX end
  row.name:SetText(ColorName(e.name or "?", hex))
  row.char:SetText(CharText(e))
  row.loc:SetText(e.loc or "")
  row.extra:SetText(e.online and ExtraText(e) or "")
  -- Faction emblem, then realm type icons (swords = PvP, mask = RP, both = RP-PvP, shield = PvE), in their own column.
  row.kind:SetText("")
  if e.online and e.kind == "bnet" and e.ga then
    local realm = MF.NotNil(e.ga.realmDisplayName) or MF.NotNil(e.ga.realmName) or e.realmText
    local _, _, key = MF.ParseRealm(realm)
    local txt = FactionIcon(e.ga.factionName, 12) .. (key and KindIcons(key, 12) or "")
    if txt ~= "" then row.kind:SetText(txt) end
  end

  if e.online and e.invite then
    row.party:Show()
    StyleParty(row.party, e.invite.enabled, e.invite.mode, e.queue ~= nil)
  end
end

R.ally = function(row, item)
  local e = item.e
  MF.LayoutRow(row, "ally")
  row.entry = e
  row.dot:Show()
  MF.SetDot(row.dot, e.presence)
  row.star:Show()
  local atlas = MF.PickAtlas(e.online and "friends-icon-pinned" or "friends-icon-pinned-dis", "friends-icon-pinned")
  MF.SetIcon(row.star, atlas, "P", 1, 0.82, 0)
  row.star.dimmable = not e.pinned

  row.name:SetText(ColorName(e.name or "?", (e.online or e.cached) and MF.ClassHex(e.classFile) or GREY_HEX))
  row.char:SetText(e.level and ("|cffaaaaaa" .. e.level .. "|r") or "")
  row.loc:SetText(e.interaction or "")
  row.extra:SetText(e.location and ("|cff9a9a9a" .. e.location .. "|r") or "")
  row.party:Show()
  StyleParty(row.party, (e.online or e.cached) and not e.inviteBlocked, "INVITE", false)
end

local function RequestTypeLabel(inv)
  local lv = Enum and Enum.BattleNetFriendLevel
  if lv then
    if inv.friendLevel == lv.RealID then return "Real ID" end
    if inv.friendLevel == lv.BattleTag then return "Battle.net" end
    if inv.friendLevel == lv.Title then return "WoW friend" end
  end
  return ""
end

R.request = function(row, item)
  local inv = item.inv
  MF.LayoutRow(row, "request")
  row.char:SetText("|cff9a9a9a" .. (MF.RelativeTime(inv.creationTimestamp) or "") .. "|r")
  local lv = Enum and Enum.BattleNetFriendLevel
  local isTitle = lv and lv.Title ~= nil and inv.friendLevel == lv.Title
  row.name:SetText(ColorName(inv.accountName or "?", isTitle and "ffd100" or BNET_HEX))
  row.loc:SetText(RequestTypeLabel(inv))
  row.btnA:Show()
  row.btnA:SetLabel("Accept")
  row.btnB:Show()
  row.btnB:SetLabel("Decline")
  if #MF.RequestMenuItems(inv) > 1 then row.btnC:Show() end
end

R.ignore = function(row, item)
  MF.LayoutRow(row, "ignore")
  row.name:SetText(tostring(item.name or "?"))
  row.btnA:Show()
  row.btnA:SetLabel("Unblock")
end
R.block = function(row, item)
  R.ignore(row, item)
  row.btnA:SetAlpha(0.45) -- unblocking a Battle.net account is restricted, see MF.RowButton
end

------------------------------------------------------------------ row interaction
function MF.RowClick(row, btn)
  local item = row.item
  if not item then return end
  MF.SetAction("click row " .. tostring(item.type) .. " (" .. tostring(btn) .. ")")
  if item.type == "header" then
    if btn == "LeftButton" and not item.plain and item.key then
      MF.DB.collapsed[item.key] = not MF.DB.collapsed[item.key] or nil
      MF.Rebuild()
    end
  elseif item.type == "friend" then
    if btn == "RightButton" then MF.FriendMenu(row, item.e) else MF.Whisper(item.e) end
  elseif item.type == "ally" then
    if btn == "RightButton" then MF.AllyMenu(row, item.e) else MF.Whisper(item.e) end
  end
end

------------------------------------------------------------------ item lists per tab
local function AddSection(items, itemType, key, label, list)
  if #list == 0 then return end
  local collapsed = MF.DB.collapsed[key] and true or false
  local online = 0
  for _, e in ipairs(list) do
    if e.online then online = online + 1 end
  end
  items[#items + 1] = { type = "header", key = key, text = label, online = online, total = #list, collapsed = collapsed }
  if not collapsed then
    for _, e in ipairs(list) do items[#items + 1] = { type = itemType, e = e } end
  end
end

function MF.BuildFriendItems()
  local items = {}
  local q = SearchText()
  local fav, forever, rest, legacy = {}, {}, {}, {}
  for _, e in ipairs(MF.friends) do
    if MF.FriendPasses(e, q) then
      if e.isFavorite then
        fav[#fav + 1] = e
      elseif e.online and e.isWoW and not e.differentProject then
        forever[#forever + 1] = e -- online in this same WoW version (WoW Forever)
      else
        rest[#rest + 1] = e
      end
    end
  end
  for _, e in ipairs(MF.legacy) do
    if MF.FriendPasses(e, q) then legacy[#legacy + 1] = e end
  end
  AddSection(items, "friend", "favorites", "Favorites", fav)
  AddSection(items, "friend", "forever", "WoW Forever", forever)
  AddSection(items, "friend", "friends", (#forever > 0) and "Other" or "Friends", rest)
  AddSection(items, "friend", "legacy", "Legacy Friends", legacy)
  if #items == 0 then
    local text
    if not MF.GetOwnInfo().connected then
      text = "Battle.net unavailable"
    elseif #MF.friends == 0 and #MF.legacy == 0 then
      text = "No friends yet. Use Add New Friend below."
    else
      text = "No friends match the current search or filter."
    end
    items[1] = { type = "message", text = text }
  end
  return items
end

function MF.BuildAllyItems()
  if not MF.AlliesSupported() and not MF.testMode then
    return { { type = "message", text = "Recent Allies is unavailable." } }
  end
  local items = {}
  if MF.alliesCached then
    if #MF.allies == 0 then
      return { { type = "message", text = "Recent Allies is not loaded yet. Click Load Recent Allies below, or open Blizzard's window (Shift+O) on Recent Allies." } }
    end
    local at = MF.DB.allyCache and MF.DB.allyCache.at
    items[1] = { type = "header", plain = "Saved list" .. (at and (" from " .. date("%b %d %H:%M", at)) or "") .. " (not live)" }
  end
  local first = #items
  local q = SearchText()
  local legacy, pinned, unpinned = {}, {}, {}
  for _, e in ipairs(MF.allies) do
    if MF.AllyPasses(e, q) then
      if e.pinned and e.legacy then legacy[#legacy + 1] = e
      elseif e.pinned then pinned[#pinned + 1] = e
      else unpinned[#unpinned + 1] = e end
    end
  end
  AddSection(items, "ally", "a_legacy", "Legacy Friends", legacy)
  AddSection(items, "ally", "a_pinned", "Pinned", pinned)
  AddSection(items, "ally", "a_unpinned", "Unpinned", unpinned)
  if #items == first then
    items[#items + 1] = { type = "message", text = (#MF.allies == 0) and "No recent allies yet." or "No allies match the current search or filter." }
  end
  return items
end

function MF.BuildRequestItems()
  local items = {}
  items[1] = { type = "header", plain = format("Received (%d)", #MF.requests) }
  if #MF.requests == 0 then
    items[2] = { type = "message", text = "No pending friend requests." }
  else
    for _, inv in ipairs(MF.requests) do items[#items + 1] = { type = "request", inv = inv } end
  end
  return items
end

function MF.BuildIgnoreItems()
  local items = {}
  items[#items + 1] = { type = "header", plain = format("Ignored (%d)", #MF.ignores) }
  if #MF.ignores == 0 then
    items[#items + 1] = { type = "message", text = "Nobody is ignored." }
  else
    for _, ig in ipairs(MF.ignores) do
      items[#items + 1] = { type = "ignore", name = ig.name, index = ig.index }
    end
  end
  items[#items + 1] = { type = "header", plain = format("Blocked Battle.net invites (%d)", #MF.blocks) }
  if #MF.blocks == 0 then
    items[#items + 1] = { type = "message", text = "No blocked invites." }
  else
    for _, b in ipairs(MF.blocks) do
      items[#items + 1] = { type = "block", name = b.name, id = b.id }
    end
  end
  return items
end

------------------------------------------------------------------ rebuild / refresh
-- Re-filters already fetched data (cheap; used for search/filter/collapse changes).
function MF.Rebuild()
  if not (MF.frame and MF.frame:IsShown()) then return end
  local tab = MF.tab
  local items
  if tab == "friends" then items = MF.BuildFriendItems()
  elseif tab == "allies" then items = MF.BuildAllyItems()
  elseif tab == "requests" then items = MF.BuildRequestItems()
  else items = MF.BuildIgnoreItems() end
  MF.items = items or {}
  MF.Render()
end

-- Re-reads game data for the current tab, then rebuilds.
function MF.Refresh()
  MF.pending = false
  MF.lastRefresh = GetTime()
  if not (MF.frame and MF.frame:IsShown()) then return end
  MF.SetAction("refresh")
  MF.tagsOn = MF.testMode or MF.TagsEnabled()
  local tab = MF.tab
  if tab == "friends" then MF.FetchFriends()
  elseif tab == "allies" then MF.FetchAllies()
  elseif tab == "requests" then MF.FetchRequests()
  else MF.FetchIgnores() end
  MF.UpdateBadges()
  MF.Rebuild()
  MF.UpdateAllyLoadButton()
  MF.Log("refresh", format("tab %s: %d items", tab, #(MF.items or {})))
end

function MF.RequestRefresh()
  if not (MF.frame and MF.frame:IsShown()) or MF.pending then return end
  local wait = 1 - (GetTime() - (MF.lastRefresh or 0))
  if wait <= 0 then
    MF.Refresh()
  else
    MF.pending = true
    C_Timer.After(wait, MF.Refresh)
  end
end

function MF.OnShow()
  MF.SetAction("show window")
  MF.Log("ui", "window shown")
  if C_FriendList and C_FriendList.ShowFriends then pcall(C_FriendList.ShowFriends) end
  MF.LayoutTabs()
  MF.UpdateTopBar()
  MF.SelectTab(MF.DB.lastTab or "friends")
  MF.UpdateBadges()
  -- first run: offer the two looks until one was chosen (closing the chooser asks again next time)
  if not MF.DB.skinChosen then MF.ShowSkinChooser() end
end
