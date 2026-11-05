-- Old Friends v2 - Data: reads Battle.net friends (the Social UI data model), recent allies,
-- requests, ignores; invite logic; filtering and test data.
--
-- NOTE: Blizzard marks many functions HasRestrictions = true (callable only from Blizzard's own secure
-- code). Calling one from an add-on raises the "blocked from an action only available to the Blizzard UI"
-- popup (pcall does not suppress it). This file therefore never calls: C_BattleNet.SearchFriends,
-- SetAFK / SetDND / SetAppearOffline, C_RecentAllies.TryRequestRecentAlliesData, C_FriendList.AddFriend.
--
-- Data model: on this client EVERY friend is a Battle.net friend. A "WoW friend" is a BNet friend
-- whose accountInfo.friendLevel == Enum.BattleNetFriendLevel.Title.
local _, MF = ...
local NotNil, StripTag = MF.NotNil, MF.StripTag
local format = string.format
local pcall = MF.PCall -- logs failures to the diagnostics log

------------------------------------------------------------------ own status / battletag
local STATUS_LABELS = { online = "Online", away = "Away", busy = "Busy", offline = "Appear Offline" }
MF.STATUS_LABELS = STATUS_LABELS

-- Returns { connected, tag, status } where status is online|away|busy|offline (offline = Appear Offline).
-- Read-only: the own status can only be changed from Blizzard's own Social window (the setters are restricted).
function MF.GetOwnInfo()
  local r = { connected = true, status = "online" }
  if MF.testMode then
    r.tag = "TestUser#1234"
    return r
  end
  if BNConnected then
    local ok, v = pcall(BNConnected)
    if ok then r.connected = v and true or false end
  end
  if BNGetInfo then
    local ok, _, tag, _, _, afk, busy, _, off = pcall(BNGetInfo)
    if ok then
      r.tag = NotNil(tag)
      if off then r.status = "offline"
      elseif afk then r.status = "away"
      elseif busy then r.status = "busy" end
    end
  end
  return r
end

------------------------------------------------------------------ friend helpers
local CLIENT_LABELS = {
  WoW = "WoW", App = "App", BSAp = "Mob", CLNT = "App", D3 = "D3", Fen = "D4", WTCG = "HS", Hero = "HotS",
  S1 = "SC", S2 = "SC2", Pro = "OW", OSI = "D2R", W3 = "WC3", GRY = "Rum",
}
function MF.ClientLabel(client)
  if type(client) ~= "string" or client == "" then return nil end
  return CLIENT_LABELS[client] or client
end

function MF.PresenceOf(account, ga)
  if not (ga and ga.isOnline) then return "offline" end
  if account.isAFK or ga.isGameAFK then return "away" end
  if account.isDND or ga.isGameBusy then return "busy" end
  return "online"
end

-- Live social-queue activity for a character guid. Returns nil or
-- { inGroup = true, kind = "PvE"|"PvP"|nil, names = { ... } }.
function MF.GetQueueInfo(guid)
  if not guid then return nil end
  local sq = C_SocialQueue
  if not (sq and sq.GetGroupForPlayer) then return nil end
  local ok, group = pcall(sq.GetGroupForPlayer, guid)
  if not ok or not group then return nil end
  local info = { inGroup = true, names = {} }
  if sq.GetGroupQueues then
    local ok2, queues = pcall(sq.GetGroupQueues, group)
    if ok2 and type(queues) == "table" then
      for _, q in ipairs(queues) do
        local qd = q and q.queueData
        if qd then
          local t = qd.queueType
          local kind
          if t == "pvp" then kind = "PvP"
          elseif t == "lfg" or t == "lfglist" then kind = "PvE" end
          if kind and not info.kind then info.kind = kind end
          local name
          if SocialQueueUtil_GetQueueName then
            local ok3, n = pcall(SocialQueueUtil_GetQueueName, qd)
            if ok3 and type(n) == "string" and n ~= "" then name = n end
          end
          info.names[#info.names + 1] = name or (kind or tostring(t or "queue"))
        end
      end
    end
  end
  return info
end

local function BuildSearch(e)
  local parts = {}
  local function add(v)
    if type(v) == "string" and v ~= "" then parts[#parts + 1] = v end
  end
  add(e.name)
  add(e.accountName)
  add(e.battleTag)
  add(e.charName)
  add(e.area)
  add(e.rich)
  add(e.note)
  add(e.className)
  add(e.customMessage)
  for _, t in ipairs(e.tags or {}) do
    local d = MF.TagDef(t)
    if d then
      add(d.label)
      add(d.short)
    end
  end
  e.search = table.concat(parts, "\n"):lower()
end

function MF.NormalizeFriend(account, index)
  local ga = account.gameAccountInfo or {}
  local e = {
    kind = "bnet", index = index, id = account.bnetAccountID, account = account, ga = ga,
    fake = account._fake and true or false,
    accountName = NotNil(account.accountName), battleTag = NotNil(account.battleTag),
    isFavorite = account.isFavorite and true or false,
    online = ga.isOnline and true or false,
    note = NotNil(account.note), tags = account.friendTags or {},
    customMessage = NotNil(account.customMessage), customMessageTime = account.customMessageTime,
    lastOnlineTime = account.lastOnlineTime or 0,
    client = NotNil(ga.clientProgram),
  }
  local levels = Enum and Enum.BattleNetFriendLevel
  e.friendLevel = account.friendLevel
  e.isTitle = (levels and levels.Title ~= nil and account.friendLevel == levels.Title) and true or false
  e.presence = MF.PresenceOf(account, ga)

  local custom
  if e.isTitle and C_BattleNet and C_BattleNet.GetCustomTitleFriendName and e.id then
    local ok, n = pcall(C_BattleNet.GetCustomTitleFriendName, e.id)
    if ok then custom = NotNil(n) end
  end
  e.customName = custom
  e.name = custom or e.accountName or StripTag(e.battleTag) or "?"

  e.isWoW = (ga.clientProgram == "WoW")
  e.charName = e.online and NotNil(ga.characterName) or nil
  -- Some servers send "Name-Realm" as the character name (the part after the dash is the realm, not a guild).
  -- Split it so rows show just the name and the tooltip can show a short realm.
  e.realmText = nil
  if e.charName and not NotNil(ga.realmDisplayName) and not NotNil(ga.realmName) then
    local n, r = e.charName:match("^(.-)%-(.+)$")
    if n and n ~= "" then e.charName, e.realmText = n, r end
  end
  e.level = (type(ga.characterLevel) == "number" and ga.characterLevel > 0) and ga.characterLevel or nil
  e.classFile = NotNil(ga.classFilename)
  e.className = NotNil(ga.className)
  e.area = NotNil(ga.areaName)
  e.rich = NotNil(ga.richPresence)
  e.differentProject = (e.isWoW and WOW_PROJECT_ID ~= nil and ga.wowProjectID ~= WOW_PROJECT_ID) and true or false
  e.richOnly = e.online and (not e.isWoW or e.differentProject or e.area == nil)

  if e.online then
    if e.richOnly then
      e.loc = e.rich or (not e.isWoW and MF.ClientLabel(e.client)) or ""
    else
      e.loc = e.area or ""
    end
  else
    e.loc = MF.LastOnlineText(e.lastOnlineTime)
  end

  if e.online and e.isWoW and ga.playerGuid then
    if account._fakeQueue then
      e.queue = account._fakeQueue
    else
      e.queue = MF.GetQueueInfo(ga.playerGuid)
    end
  end
  BuildSearch(e)
  if e.online then e.invite = MF.EvaluateInvite(e) end
  return e
end

------------------------------------------------------------------ invite logic
function MF.GetInviteType(guid)
  if guid and GetDisplayedInviteType then
    local ok, t = pcall(GetDisplayedInviteType, guid)
    if ok and type(t) == "string" then return t end
  end
  return "INVITE"
end

function MF.InviteMode(t)
  if type(t) == "string" then
    if t:find("^REQUEST_INVITE") then return "REQUEST" end
    if t:find("^SUGGEST_INVITE") then return "SUGGEST" end
  end
  return "INVITE"
end

local MODE_LABELS = { REQUEST = "Request Invite", SUGGEST = "Suggest Invite", INVITE = "Invite" }
function MF.InviteLabel(mode) return MODE_LABELS[mode] or "Invite" end

function MF.GetGameAccounts(e)
  if e.gaList then return e.gaList end
  local list, seen = {}, {}
  local function add(g)
    if g and g.gameAccountID and not seen[g.gameAccountID] then
      seen[g.gameAccountID] = true
      list[#list + 1] = g
    end
  end
  add(e.ga)
  if not e.fake and e.index and C_BattleNet and C_BattleNet.GetFriendNumGameAccounts
      and C_BattleNet.GetFriendGameAccountInfo then
    local ok, n = pcall(C_BattleNet.GetFriendNumGameAccounts, e.index)
    if ok and type(n) == "number" then
      for k = 1, n do
        local ok2, g = pcall(C_BattleNet.GetFriendGameAccountInfo, e.index, k)
        if ok2 then add(g) end
      end
    end
  end
  e.gaList = list
  return list
end

-- Realm ruleset (PvE / PvP / RP / RP-PvP), read from the realm name by MF.ParseRealm (Views.lua).
-- Returns the ruleset key, or nil when the realm name does not say.
function MF.RealmRuleset(realm)
  if not (MF.ParseRealm and type(realm) == "string" and realm ~= "") then return nil end
  local ok, _, _, key = pcall(MF.ParseRealm, realm)
  if ok then return key end
  return nil
end

-- True plus a reason when the other player's realm ruleset differs from this character's.
-- When either ruleset cannot be read, the invite is allowed (nothing to compare).
function MF.RulesetMismatch(otherRealm)
  local mine = GetRealmName and MF.RealmRuleset(GetRealmName())
  local theirs = MF.RealmRuleset(otherRealm)
  if mine and theirs and mine ~= theirs then
    return true, format("Different realm ruleset (you: %s, them: %s)", mine, theirs)
  end
  return false
end

-- First failing check wins; returns true or false, reason.
-- fallbackRealm: realm text split from a "Name-Realm" character name, when the account has no realm fields.
local function EvalGameAccount(ga, fallbackRealm)
  if not ga or not ga.isOnline then return false, "Friend is offline" end
  if ga.clientProgram ~= "WoW" then return false, "Not playing World of Warcraft" end
  if WOW_PROJECT_ID ~= nil and ga.wowProjectID ~= WOW_PROJECT_ID then
    return false, "Playing a different version of World of Warcraft"
  end
  if not ga.playerGuid then return false, "Character information unavailable" end
  if ga.realmID ~= nil and ga.realmID == 0 then return false, "Realm information unavailable" end
  if ga.isInCurrentRegion == false then return false, "Playing in a different region" end
  local mine = UnitFactionGroup and UnitFactionGroup("player")
  if mine and ga.factionName and ga.factionName ~= mine then
    if C_QuestSession and C_QuestSession.Exists and C_QuestSession.Exists() then
      return false, "Cannot invite the opposite faction during a quest session"
    end
    local canCross = C_PartyInfo and C_PartyInfo.CanFormCrossFactionParties and C_PartyInfo.CanFormCrossFactionParties()
    if not canCross then return false, "Friend is on the opposite faction" end
  end
  local mismatch, why = MF.RulesetMismatch(NotNil(ga.realmDisplayName) or NotNil(ga.realmName) or fallbackRealm)
  if mismatch then return false, why end
  if WOW_PROJECT_CLASSIC ~= nil and WOW_PROJECT_ID == WOW_PROJECT_CLASSIC and GetRealmID
      and ga.realmID and ga.realmID ~= GetRealmID() then
    return false, "Friend is on a different realm"
  end
  return true
end

local function EvaluateInviteRaw(e)
  local inv = { enabled = false, targets = {}, mode = "INVITE", label = "Invite" }
  if not e.online then
    inv.reason = "Friend is offline"
    return inv
  end
  local firstReason, wowReason
  for _, ga in ipairs(MF.GetGameAccounts(e)) do
    local ok, why = EvalGameAccount(ga, (ga == e.ga) and e.realmText or nil)
    if ok then
      inv.targets[#inv.targets + 1] = ga
    else
      firstReason = firstReason or why
      if ga.clientProgram == "WoW" then wowReason = wowReason or why end
    end
  end
  if #inv.targets > 0 then
    inv.enabled = true
    inv.mode = MF.InviteMode(MF.GetInviteType(inv.targets[1].playerGuid))
    inv.label = MF.InviteLabel(inv.mode)
  else
    inv.reason = wowReason or firstReason or "No game account available"
  end
  return inv
end

function MF.EvaluateInvite(e)
  local ok, res = pcall(EvaluateInviteRaw, e)
  if ok and res then return res end
  return { enabled = false, targets = {}, mode = "INVITE", label = "Invite", reason = "Invite status unavailable" }
end

-- Click path for a Battle.net game account: re-read it fresh, then Invite / Suggest / Request.
function MF.InviteGameAccount(gameAccountID, fallbackGuid)
  if not gameAccountID then return end
  local ga
  if C_BattleNet and C_BattleNet.GetGameAccountInfoByID then
    local ok, g = pcall(C_BattleNet.GetGameAccountInfoByID, gameAccountID)
    if ok then ga = g end
  end
  local guid = (ga and ga.playerGuid) or fallbackGuid
  if not guid then
    MF.Log("invite", "gameAccount " .. tostring(gameAccountID) .. ": no guid, aborted")
    MF.Print("Cannot invite: character information unavailable.")
    return
  end
  local mode = MF.InviteMode(MF.GetInviteType(guid))
  if mode == "REQUEST" then
    if BNRequestInviteFriend then
      MF.Log("invite", "gameAccount " .. tostring(gameAccountID) .. ": BNRequestInviteFriend")
      BNRequestInviteFriend(gameAccountID)
      MF.Log("invite", "BNRequestInviteFriend returned")
    else
      MF.Log("invite", "BNRequestInviteFriend missing")
      MF.Print("Request Invite is unavailable.")
    end
    return
  end
  if mode == "SUGGEST" and C_PartyInfo and C_PartyInfo.IsPartyFull and C_PartyInfo.IsPartyFull() then
    MF.Log("invite", "gameAccount " .. tostring(gameAccountID) .. ": suggest blocked, party full")
    MF.SystemMessage(ERR_GROUP_FULL or "Your party is full.")
    return
  end
  if C_BattleNet and C_BattleNet.InviteFriend then
    MF.Log("invite", "gameAccount " .. tostring(gameAccountID) .. ": C_BattleNet.InviteFriend (mode " .. mode .. ")")
    C_BattleNet.InviteFriend(gameAccountID)
    MF.Log("invite", "C_BattleNet.InviteFriend returned")
  else
    MF.Log("invite", "C_BattleNet.InviteFriend missing")
    MF.Print("Invite is unavailable.")
  end
end

-- Legacy character friends and recent allies invite by character name.
function MF.InviteByName(name, guid)
  local P = C_PartyInfo
  if not name or name == "" then return end
  local mode = MF.InviteMode(MF.GetInviteType(guid))
  if mode == "REQUEST" and P and P.RequestInviteFromUnit then
    MF.Log("invite", "by name " .. name .. ": C_PartyInfo.RequestInviteFromUnit")
    P.RequestInviteFromUnit(name)
    MF.Log("invite", "RequestInviteFromUnit returned")
    return
  end
  if mode == "SUGGEST" and P and P.IsPartyFull and P.IsPartyFull() then
    MF.Log("invite", "by name " .. name .. ": suggest blocked, party full")
    MF.SystemMessage(ERR_GROUP_FULL or "Your party is full.")
    return
  end
  if P and P.InviteUnit then
    MF.Log("invite", "by name " .. name .. ": C_PartyInfo.InviteUnit (mode " .. mode .. ")")
    P.InviteUnit(name)
    MF.Log("invite", "C_PartyInfo.InviteUnit returned")
  elseif InviteUnit then
    MF.Log("fallback", "C_PartyInfo.InviteUnit missing, using global InviteUnit")
    InviteUnit(name)
  else
    MF.Log("invite", "no invite API available")
    MF.Print("Invite is unavailable.")
  end
end

------------------------------------------------------------------ test data
local function FakeAccount(i, o)
  local mine = (UnitFactionGroup and UnitFactionGroup("player")) or "Alliance"
  local levels = (Enum and Enum.BattleNetFriendLevel) or { BattleTag = 1, RealID = 2, Title = 3 }
  local classNames = _G.LOCALIZED_CLASS_NAMES_MALE or {}
  local online = o.online ~= false
  -- Test friends share your own realm (so the invite stays enabled) unless o.ruleset names another one;
  -- o.alt puts the friend on the opposite faction.
  local myRealm = GetRealmName and GetRealmName() or ""
  if not MF.RealmRuleset(myRealm) then myRealm = "US1 Realm 3 PvE" end
  local realm = o.ruleset and ("US2 Realm 8 " .. o.ruleset) or myRealm
  local faction = mine
  if o.alt then faction = (mine == "Horde") and "Alliance" or "Horde" end
  local ga = {
    gameAccountID = 9000 + i, clientProgram = o.client or "WoW", isOnline = online,
    isGameBusy = o.busy and true or false, isGameAFK = o.away and true or false,
    wowProjectID = WOW_PROJECT_ID, characterName = o.char, realmName = realm, realmDisplayName = realm,
    realmID = 1, factionName = faction, raceName = "Human", classFilename = o.class,
    className = o.class and classNames[o.class] or nil, areaName = o.area, characterLevel = o.level,
    richPresence = o.rich, playerGuid = (o.char and online) and ("Player-1-FAKE" .. i) or nil,
    isInCurrentRegion = true,
  }
  local tags = {}
  for _, key in ipairs(o.tags or {}) do
    local v = MF.TagValue(key)
    if v ~= nil then tags[#tags + 1] = v end
  end
  return {
    _fake = true, _fakeQueue = o.queue,
    bnetAccountID = 8000 + i, accountName = o.name, battleTag = (o.name:gsub("[^%w]", "")) .. "#" .. (1000 + i),
    friendLevel = o.title and levels.Title or levels.BattleTag,
    lastOnlineTime = o.lastOnline or 0, isAFK = false, isDND = false, isFavorite = o.fav and true or false,
    friendTags = tags, customMessage = o.msg or "", customMessageTime = o.msg and (time() - 7200) or 0,
    note = o.note or "", gameAccountInfo = ga,
  }
end

-- TEST DATA ONLY (/of test): fictional, silly placeholder names. Never real people or accounts.
-- The names deliberately include a few too long for the row (e.g. "Mage Against the Machine") to check truncation.
local function FakeFriendAccounts()
  local DAY = 86400
  local list = {
    { name = "50dkp Minus", title = true, fav = true, char = "Fiftydkp", class = "WARLOCK", level = 80, area = "Orgrimmar",
      tags = { "Raiding", "DamagerRole" }, msg = "dkp minus 50 for standing in fire", note = "Owes me a flask" },
    { name = "Bobbard Kotick", title = true, fav = true, alt = true, char = "Bobbard", class = "PALADIN", level = 80, area = "Stormwind City",
      queue = { inGroup = true, kind = "PvE", names = { "Heroic Dungeon: The Stonevault" } }, note = "Wallet is always open" },
    { name = "Dix Enormous", title = true, char = "Dixxy", class = "ROGUE", level = 74, area = "Hallowfall",
      away = true, tags = { "HealerRole" }, msg = "rogue healer, trust me" },
    { name = "Yuri Nader", title = true, char = "Yurinator", class = "DEATHKNIGHT", level = 80, area = "Orgrimmar",
      busy = true, note = "Guild officer" },
    { name = "Ben Dover", char = "Bendover", class = "WARRIOR", level = 61, area = "Isle of Dorn", tags = { "Questing" } },
    { name = "Leeroy Jenkinz", ruleset = "PvP", char = "Leeroyjenkinz", class = "SHAMAN", level = 80, area = "Silvermoon City",
      queue = { inGroup = true, kind = "PvP", names = { "Rated Battleground" } }, tags = { "PvP" },
      msg = "At least I have chicken" },
    { name = "Tankenstein", char = "Tankenstein", class = "WARRIOR", level = 80, area = "The Ringing Deeps",
      tags = { "TankRole", "Dungeons" } },
    { name = "Healz McGee", title = true, char = "Healzmcgee", class = "PRIEST", level = 80, area = "Dornogal",
      away = true, tags = { "HealerRole", "Raiding" } },
    { name = "Sir Pulls-A-Lot", char = "Pullsalot", class = "DRUID", level = 80, area = "Dornogal", busy = true,
      queue = { inGroup = true, kind = "PvE", names = { "Mythic Keystone: Cinderbrew Meadery" } },
      tags = { "TankRole", "Dungeons", "Delves" } },
    { name = "Gnomeo Juliet", ruleset = "RP", char = "Gnomeo", class = "MAGE", level = 70, area = "Dornogal", tags = { "Roleplaying" },
      msg = "Wherefore art thou, Dalaran?" },
    { name = "Legolasagna", char = "Legolasagna", class = "HUNTER", level = 80, area = "Isle of Dorn",
      tags = { "Professions", "Delves" } },
    { name = "Shaman Fan", client = "App", rich = "Online" },
    { name = "Mage Against the Machine", client = "Fen", rich = "In Nightmare Dungeon" },
    { name = "Ctrl Alt Dalaran", alt = true, ruleset = "RP-PvP", char = "Ctrlaltdalaran", class = "MAGE", level = 80, area = "Dalaran", tags = { "Roleplaying", "Questing" } },
    { name = "AFK Gary", title = true, char = "Garyafk", class = "MONK", level = 80, area = "Valdrakken", away = true,
      msg = "brb 5 min" },
    { name = "Wipe Right", title = true, online = false, lastOnline = time() - 3 * DAY },
    { name = "Nerf Herder", online = false, lastOnline = time() - 40 * DAY, fav = true },
    { name = "Noob Saibot", title = true, online = false, lastOnline = 0 },
  }
  local out = {}
  for i, o in ipairs(list) do out[i] = FakeAccount(i, o) end
  return out
end

local function FakeAllies()
  local now = time()
  local names = {
    { "Pallydin", "PALADIN", 80, "Completed a dungeon together", "Stormwind City", true, true },
    { "Sheepnado", "MAGE", 79, "Party member", "Dornogal", true, true },
    { "Hunterhoney", "HUNTER", 80, "Completed a delve together", "Isle of Dorn", true, false },
    { "Shamwow", "SHAMAN", 72, "Traded", nil, false, false },
    { "Dotsworth", "WARLOCK", 80, "Raid member", "Hallowfall", true, false },
    { "Rogueish", "ROGUE", 65, "Dueled", "Orgrimmar", true, false },
    { "Deathknightmare", "DEATHKNIGHT", 80, "Completed an arena match", nil, false, false },
    { "Feraldo", "DRUID", 77, "Crafting order", "Silvermoon City", true, false },
    { "Evokerlord", "EVOKER", 80, "Whispered", nil, false, false },
    { "Monkey Business", "MONK", 80, "Party member", "The Ringing Deeps", true, false },
  }
  local out = {}
  for i, n in ipairs(names) do
    out[i] = {
      _fake = true,
      characterData = { guid = "Player-1-ALLY" .. i, name = n[1], fullName = n[1] .. "-TestRealm", realmName = "TestRealm",
        level = n[3], classID = 0, raceID = 1, sex = 2, _classFile = n[2] },
      stateData = { isOnline = n[6], isDND = (i == 6), isAFK = (i == 3), isConvertedLegacyFriend = (i == 1),
        pinExpirationDate = n[7] and (now + 20 * 86400) or nil, friendRequestSentThisSession = false, currentLocation = n[5] },
      interactionData = { note = (i == 2) and "Polymorphs everything, even allies" or nil, interactions = {
        { type = 0, description = n[4], timestamp = now - i * 3600 * 5, contextData = {} },
        { type = 0, description = "Party member", timestamp = now - i * 86400, contextData = {} },
      } },
    }
  end
  return out
end

local function FakeRequests()
  local levels = (Enum and Enum.BattleNetFriendLevel) or { BattleTag = 1, RealID = 2, Title = 3 }
  local now = time()
  return {
    { inviteID = -1, accountName = "Pugs McPugface", creationTimestamp = now - 1800, friendLevel = levels.RealID },
    { inviteID = -2, accountName = "Lootgoblin#4242", creationTimestamp = now - 86400 * 2, friendLevel = levels.BattleTag },
    { inviteID = -3, accountName = "Nerf This", creationTimestamp = now - 3600 * 9, friendLevel = levels.Title },
  }
end

------------------------------------------------------------------ fetch: friends
MF.friends = {}
MF.legacy = {}

local function LegacyEnabled()
  if not (C_FriendList and C_FriendList.IsLegacyFriendSystemEnabled and C_FriendList.GetNumFriends) then return false end
  local ok, v = pcall(C_FriendList.IsLegacyFriendSystemEnabled)
  if not (ok and v) then return false end
  local ok2, n = pcall(C_FriendList.GetNumFriends)
  return (ok2 and type(n) == "number" and n > 0) and true or false
end

local function NormalizeLegacy(f, index)
  local e = {
    kind = "legacy", index = index, name = f.name, charName = f.name, id = nil, isFavorite = false,
    online = f.connected and true or false, level = (type(f.level) == "number" and f.level > 0) and f.level or nil,
    className = NotNil(f.className), area = NotNil(f.area), note = NotNil(f.notes), tags = {},
    guid = f.guid, isWoW = true,
  }
  e.classFile = MF.ClassFileFromName(e.className)
  e.presence = (not e.online) and "offline" or (f.afk and "away") or (f.dnd and "busy") or "online"
  e.loc = e.online and (e.area or "") or "Offline"
  e.client = "WoW"
  e.richOnly = false
  e.invite = { enabled = e.online, targets = {}, mode = "INVITE", label = "Invite",
    reason = (not e.online) and "Friend is offline" or nil }
  e.search = ((e.name or "") .. "\n" .. (e.area or "") .. "\n" .. (e.note or "") .. "\n" .. (e.className or "")):lower()
  return e
end

function MF.FetchFriends()
  local list, legacy = {}, {}
  if MF.testMode then
    for i, acc in ipairs(FakeFriendAccounts()) do
      local ok, e = pcall(MF.NormalizeFriend, acc, i)
      if ok and e then list[#list + 1] = e end
    end
  else
    if BNGetNumFriends and C_BattleNet and C_BattleNet.GetFriendAccountInfo then
      local n = (BNGetNumFriends()) or 0
      for i = 1, n do
        local ok, acc = pcall(C_BattleNet.GetFriendAccountInfo, i)
        if ok and acc then
          local ok2, e = pcall(MF.NormalizeFriend, acc, i)
          if ok2 and e then list[#list + 1] = e end
        end
      end
    end
    if LegacyEnabled() then
      for i = 1, (C_FriendList.GetNumFriends() or 0) do
        local f = C_FriendList.GetFriendInfoByIndex and C_FriendList.GetFriendInfoByIndex(i)
        if f and f.name then legacy[#legacy + 1] = NormalizeLegacy(f, i) end
      end
    end
  end
  MF.friends, MF.legacy = list, legacy
  MF.Log("fetch", format("friends: %d bnet, %d legacy%s", #list, #legacy, MF.testMode and " (test mode)" or ""))
end

------------------------------------------------------------------ friends: filter state
local function FilterState()
  return MF.DB.filter
end

function MF.AnyTagFilter()
  for _, v in pairs(FilterState().tags) do
    if v then return true end
  end
  return false
end

function MF.FilterActive()
  local f = FilterState()
  if f.online or f.away or f.busy or f.offline or f.inQueue or f.availableForQueue then return true end
  if MF.AnyTagFilter() then return true end
  if MF.DB.showOffline then return true end
  return false
end

function MF.ClearFilters()
  local f = FilterState()
  f.online, f.away, f.busy, f.offline, f.inQueue, f.availableForQueue = false, false, false, false, false, false
  wipe(f.tags)
  MF.DB.showOffline = false
  wipe(MF.DB.allyFilter)
end

-- Queue filters are computed client-side from data we already read (C_BattleNet.SearchFriends is a
-- restricted function and cannot be called from an add-on).
--   In Queue            = the friend's character is in a social-queue group (e.queue, see MF.GetQueueInfo).
--   Available for Queue = online, playing this version of WoW, and not in such a group.
function MF.IsAvailableForQueue(e)
  return (e.online and e.isWoW and not e.differentProject and e.queue == nil) and true or false
end

function MF.FriendPasses(e, q)
  local f = FilterState()
  if f.online or f.away or f.busy or f.offline then
    if not f[e.presence] then return false end
  elseif not e.online and not MF.DB.showOffline then
    return false
  end
  if MF.tagsOn and MF.AnyTagFilter() then
    local hit = false
    for _, t in ipairs(e.tags or {}) do
      if f.tags[t] then hit = true end
    end
    if not hit then return false end
  end
  if (f.inQueue or f.availableForQueue) and e.kind == "bnet" then
    local ok = (f.inQueue and e.queue ~= nil) or (f.availableForQueue and MF.IsAvailableForQueue(e))
    if not ok then return false end
  end
  if q and q ~= "" and not (e.search and e.search:find(q, 1, true)) then return false end
  return true
end

------------------------------------------------------------------ fetch: recent allies
MF.allies = {}

function MF.AlliesSupported()
  local r = C_RecentAllies
  if not (r and r.IsSystemSupported and r.IsSystemEnabled) then return false end
  local ok1, a = pcall(r.IsSystemSupported)
  local ok2, b = pcall(r.IsSystemEnabled)
  return (ok1 and a and ok2 and b) and true or false
end

-- C_RecentAllies.TryRequestRecentAlliesData is HasRestrictions: calling it from an addon raises the
-- "blocked from an action only available to the Blizzard UI" popup (pcall cannot suppress it). So this
-- addon never calls it. The data loads when Blizzard's own Recent Allies list is shown; we only read it.
function MF.RequestAlliesData()
end

function MF.AlliesReady()
  if MF.testMode then return true end
  local r = C_RecentAllies
  if not (r and r.IsRecentAllyDataReady) then return false end
  local ok, v = pcall(r.IsRecentAllyDataReady)
  return (ok and v) and true or false
end

local function NormalizeAlly(d, order)
  local c, s, i = d.characterData or {}, d.stateData or {}, d.interactionData or {}
  local classFile = c._classFile
  if not classFile and c.classID and GetClassInfo then
    local ok, _, file = pcall(GetClassInfo, c.classID)
    if ok then classFile = file end
  end
  local useFull = RegionalUniqueNamesEnabled and RegionalUniqueNamesEnabled()
  local interactions = i.interactions or {}
  local first = interactions[1]
  local e = {
    kind = "ally", data = d, order = order, fake = d._fake and true or false,
    guid = c.guid, fullName = NotNil(c.fullName) or c.name, level = (type(c.level) == "number" and c.level > 0) and c.level or nil,
    classFile = classFile, online = s.isOnline and true or false,
    pinned = s.pinExpirationDate ~= nil, legacy = s.isConvertedLegacyFriend and true or false,
    location = NotNil(s.currentLocation), interactions = interactions,
    interaction = first and NotNil(first.description) or nil,
    lastStamp = first and first.timestamp or 0, note = NotNil(i.note),
  }
  e.name = (useFull and NotNil(c.fullName)) or c.name or "?"
  -- Same-ruleset rule: an ally on a realm with a different ruleset cannot be invited.
  local allyRealm = NotNil(c.realmName) or (e.fullName and e.fullName:match("^.-%-(.+)$")) or nil
  e.realm = allyRealm
  e.inviteBlocked, e.inviteReason = MF.RulesetMismatch(allyRealm)
  e.presence = (not e.online) and "offline" or (s.isAFK and "away") or (s.isDND and "busy") or "online"
  e.search = table.concat({ e.name or "", e.fullName or "", e.location or "", e.interaction or "", e.note or "" }, "\n"):lower()
  return e
end

-- Saved copy of the last live list (OldFriendsDB.allyCache). The game only loads Recent Allies when
-- Blizzard's own Recent Allies view is shown, so until then the tab shows this copy, marked "saved".
local CACHE_FIELDS = { "name", "fullName", "guid", "level", "classFile", "pinned", "legacy", "interaction",
  "lastStamp", "note", "realm" }

local function SaveAllyCache(list)
  if not MF.DB then return end
  local out = {}
  for i, e in ipairs(list) do
    local c = {}
    for _, k in ipairs(CACHE_FIELDS) do c[k] = e[k] end
    out[i] = c
  end
  MF.DB.allyCache = { at = time(), list = out }
end

local function CachedAllies()
  local cache = MF.DB and MF.DB.allyCache
  local list = {}
  if type(cache) ~= "table" or type(cache.list) ~= "table" then return list end
  for i, c in ipairs(cache.list) do
    if type(c) == "table" and c.name then
      local e = { kind = "ally", cached = true, order = i, online = false, presence = "offline", interactions = {} }
      for _, k in ipairs(CACHE_FIELDS) do e[k] = c[k] end
      e.lastStamp = e.lastStamp or 0
      e.inviteBlocked, e.inviteReason = MF.RulesetMismatch(e.realm)
      e.search = table.concat({ e.name or "", e.fullName or "", e.interaction or "", e.note or "" }, "\n"):lower()
      list[#list + 1] = e
    end
  end
  return list
end

function MF.FetchAllies()
  local list = {}
  local raw
  MF.alliesCached = false
  if MF.testMode then
    raw = FakeAllies()
  elseif MF.AlliesReady() and MF.AlliesSupported() and C_RecentAllies.GetRecentAllies then
    local ok, res = pcall(C_RecentAllies.GetRecentAllies)
    if ok and type(res) == "table" then raw = res end
  end
  if raw then
    for idx, d in ipairs(raw) do
      local ok, e = pcall(NormalizeAlly, d, idx)
      if ok and e then list[#list + 1] = e end
    end
    if not MF.testMode then SaveAllyCache(list) end
  else
    list = CachedAllies()
    MF.alliesCached = true
  end
  table.sort(list, function(a, b)
    if a.online ~= b.online then return a.online end
    if a.lastStamp ~= b.lastStamp then return (a.lastStamp or 0) > (b.lastStamp or 0) end
    return a.order < b.order
  end)
  MF.allies = list
  MF.Log("fetch", format("allies: %d%s", #list, MF.testMode and " (test mode)" or (MF.alliesCached and " (saved list)" or "")))
end

function MF.AllyPasses(e, q)
  local f = MF.DB.allyFilter
  if f.online or f.away or f.busy or f.offline then
    if not f[e.presence] then return false end
  end
  if q and q ~= "" and not e.search:find(q, 1, true) then return false end
  return true
end

------------------------------------------------------------------ fetch: requests, ignore
MF.requests = {}

function MF.FetchRequests()
  local list = {}
  if MF.testMode then
    list = FakeRequests()
  elseif BNGetNumFriendInvites and C_BattleNet and C_BattleNet.GetFriendInviteInfo then
    for i = 1, (BNGetNumFriendInvites() or 0) do
      local ok, inv = pcall(C_BattleNet.GetFriendInviteInfo, i)
      if ok and inv then list[#list + 1] = inv end
    end
  end
  MF.requests = list
  MF.Log("fetch", format("requests: %d", #list))
end

function MF.RequestCount()
  if MF.testMode then return 3 end
  if not BNGetNumFriendInvites then return 0 end
  local ok, n = pcall(BNGetNumFriendInvites)
  return (ok and type(n) == "number") and n or 0
end

MF.ignores, MF.blocks = {}, {}

function MF.FetchIgnores()
  local ig, bl = {}, {}
  if MF.testMode then
    ig = { { index = 1, name = "Goldseller9000-TestRealm" }, { index = 2, name = "Gankalot-TestRealm" },
      { index = 3, name = "Ninjalooter-TestRealm" } }
    bl = { { id = -11, name = "Royal Prince#0001" }, { id = -12, name = "Gold4Sale#1337" } }
  else
    if C_FriendList and C_FriendList.GetNumIgnores and C_FriendList.GetIgnoreName then
      for i = 1, (C_FriendList.GetNumIgnores() or 0) do
        local name = C_FriendList.GetIgnoreName(i)
        if name then ig[#ig + 1] = { index = i, name = name } end
      end
    end
    if BNGetNumBlocked and BNGetBlockedInfo then
      for i = 1, (BNGetNumBlocked() or 0) do
        local id, name = BNGetBlockedInfo(i)
        if id then bl[#bl + 1] = { id = id, name = name or "?" } end
      end
    end
  end
  MF.ignores, MF.blocks = ig, bl
  MF.Log("fetch", format("ignores: %d, blocks: %d", #ig, #bl))
end
