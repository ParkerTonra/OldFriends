-- Old Friends v2 - Core: shared namespace, constants, small helpers.
-- Clean-room addon; uses only public Blizzard API. No libraries.
local ADDON, MF = ...
MF.ADDON = ADDON

MF.ROW_H = 16        -- one line per entry
MF.VISIBLE = 22      -- default number of visible rows
MF.MIN_ROWS = 8      -- resize limits (rows)
MF.MAX_ROWS = 50     -- size of the row pool
MF.WIDTH = 440       -- default and minimum width
MF.MAX_WIDTH = 720
MF.TOP_H = 78        -- top bar + tabs + search row (rows start below this)
MF.BOTTOM_H = 34
MF.testMode = false

local format, floor = string.format, math.floor

------------------------------------------------------------------ diagnostics log
-- Ring buffer of the last LOG_MAX lines. Once the saved variables exist (MF.AttachLog, called from
-- InitDB) the buffer IS OldFriendsDB.log, so it survives /reload and can be read from
-- WTF\Account\<acct>\SavedVariables\OldFriends.lua.
MF.LOG_MAX = 300
MF.logBuf = {}
MF.lastAction = "load"   -- label of the last user action / refresh, shown in BLOCKED entries
MF.blockedOther = 0      -- blocked/forbidden events caused by other addons (counted, not logged)

function MF.SetAction(label)
  MF.lastAction = tostring(label or "?")
end

local function PushLine(line)
  local buf = MF.logBuf
  buf[#buf + 1] = line
  while #buf > MF.LOG_MAX do table.remove(buf, 1) end
end

function MF.Log(tag, msg)
  local line = format("%s [%s] %s", date("%H:%M:%S"), tostring(tag), tostring(msg))
  PushLine(line)
  if MF.DB and MF.DB.debug then print("|cff888888MF " .. line .. "|r") end
end

-- Makes OldFriendsDB.log the live buffer (lines logged before the DB existed are kept).
function MF.AttachLog(DB)
  local old = (type(DB.log) == "table") and DB.log or {}
  local pre = MF.logBuf
  MF.logBuf = old
  DB.log = old
  PushLine("---- session start " .. date("%Y-%m-%d %H:%M:%S") .. " ----")
  for _, l in ipairs(pre) do PushLine(l) end
end

function MF.LogLines(n)
  local buf = MF.logBuf
  local out = {}
  for i = math.max(1, #buf - (n or #buf) + 1), #buf do out[#out + 1] = buf[i] end
  return out
end

function MF.LogClear()
  wipe(MF.logBuf)
end

-- pcall that records failures (the error string) in the log; same return values as pcall.
local rawpcall = pcall
local function PCallDone(ok, ...)
  if not ok then MF.Log("pcall-fail", tostring((...)) .. " (action: " .. tostring(MF.lastAction) .. ")") end
  return ok, ...
end
function MF.PCall(fn, ...)
  return PCallDone(rawpcall(fn, ...))
end
local pcall = MF.PCall

-- ADDON_ACTION_BLOCKED / ADDON_ACTION_FORBIDDEN. Only entries for this addon are logged.
local function CompactStackLine(s)
  s = s:gsub("Interface\\AddOns\\", "")
  s = s:gsub('%[string "@?', "")
  s = s:gsub('"%]', "")
  s = s:gsub("%s+", " ")
  return s
end

local blockedLast = { key = nil, base = nil, line = nil, count = 0 }
local blockedWarned = {}

function MF.OnBlocked(event, addonName, funcName)
  -- Only blocked-action events caused by this addon are ours; count the rest.
  if addonName ~= MF.ADDON and addonName ~= "OldFriends" then
    MF.blockedOther = (MF.blockedOther or 0) + 1
    return
  end
  funcName = tostring(funcName or "?")
  if funcName:find("TryRequestRecentAlliesData", 1, true) and MF.DB then MF.DB.noAllyRequest = true end
  local lines = {}
  local okStack, stack = rawpcall(debugstack, 2)
  if okStack and type(stack) == "string" then
    for l in stack:gmatch("[^\n]+") do
      lines[#lines + 1] = CompactStackLine(l)
      if #lines >= 6 then break end
    end
  end
  local stackText = (#lines > 0) and table.concat(lines, " | ") or "(no stack)"
  local tab, action = tostring(MF.tab or "?"), tostring(MF.lastAction)
  local key = table.concat({ event, funcName, tab, action, stackText }, "\1")
  local buf = MF.logBuf
  if blockedLast.key == key and blockedLast.line and buf[#buf] == blockedLast.line then
    blockedLast.count = blockedLast.count + 1
    blockedLast.line = blockedLast.base .. format(" (x%d)", blockedLast.count)
    buf[#buf] = blockedLast.line
  else
    local base = format("%s [BLOCKED] %s fn=%s tab=%s action=%s stack: %s",
      date("%H:%M:%S"), tostring(event), funcName, tab, action, stackText)
    PushLine(base)
    blockedLast.key, blockedLast.base, blockedLast.line, blockedLast.count = key, base, base, 1
  end
  if not blockedWarned[funcName] then
    blockedWarned[funcName] = true
    MF.PrintRaw("OldFriends blocked: " .. funcName .. " (see /of log)")
  end
end

------------------------------------------------------------------ strings
function MF.Trim(s)
  s = tostring(s or "")
  s = s:gsub("^%s+", "")
  s = s:gsub("%s+$", "")
  return s
end

function MF.NotNil(v)
  if v == nil or v == "" then return nil end
  return v
end

function MF.StripTag(tag) -- "Name#1234" -> "Name"
  if type(tag) ~= "string" or tag == "" then return nil end
  return (tag:gsub("#.*$", ""))
end

-- Chat line without the "Old Friends:" prefix.
function MF.PrintRaw(msg)
  msg = tostring(msg)
  local ok = false
  if ChatFrameUtil and ChatFrameUtil.AddSystemMessage then
    ok = pcall(ChatFrameUtil.AddSystemMessage, msg)
  end
  if not ok then print(msg) end
end

function MF.Print(msg)
  MF.PrintRaw("|cff66ccffOld Friends:|r " .. tostring(msg))
end

-- Shows a game system message (used for ERR_GROUP_FULL like the stock UI).
function MF.SystemMessage(text)
  text = tostring(text or "")
  local ok = false
  if ChatFrameUtil and ChatFrameUtil.DisplaySystemMessageInPrimary then
    ok = pcall(ChatFrameUtil.DisplaySystemMessageInPrimary, text)
  end
  if not ok then MF.Print(text) end
end

------------------------------------------------------------------ atlases
local atlasCache = {}
function MF.HasAtlas(name)
  if not name then return false end
  local v = atlasCache[name]
  if v == nil then
    v = false
    if C_Texture and C_Texture.GetAtlasInfo then
      local ok, info = pcall(C_Texture.GetAtlasInfo, name)
      v = (ok and info) and true or false
    end
    if not v then MF.Log("fallback", "atlas missing: " .. tostring(name)) end
    atlasCache[name] = v
  end
  return v
end

-- Returns the first atlas name the client knows, or nil.
function MF.PickAtlas(...)
  for i = 1, select("#", ...) do
    local name = select(i, ...)
    if name and MF.HasAtlas(name) then return name end
  end
  return nil
end

------------------------------------------------------------------ classes
local classFileByName = {}
function MF.BuildClassMap()
  local male, female = _G.LOCALIZED_CLASS_NAMES_MALE, _G.LOCALIZED_CLASS_NAMES_FEMALE
  for _, tbl in ipairs({ male or {}, female or {} }) do
    for file, name in pairs(tbl) do classFileByName[name] = file end
  end
  if GetClassInfo then
    for i = 1, 40 do
      local name, file = GetClassInfo(i)
      if name and file then classFileByName[name] = file end
    end
  end
end

function MF.ClassFileFromName(name)
  return name and classFileByName[name] or nil
end

function MF.ClassHex(classFile)
  local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
  if c then
    return format("%02x%02x%02x", floor(c.r * 255 + 0.5), floor(c.g * 255 + 0.5), floor(c.b * 255 + 0.5))
  end
  return "ffffff"
end

------------------------------------------------------------------ time
local MIN, HOUR, DAY = 60, 3600, 86400

-- ts is normally an absolute time() stamp; small values are treated as "seconds ago".
function MF.RelativeTime(ts)
  if type(ts) ~= "number" or ts <= 0 then return nil end
  local d
  if ts < 1000000000 then d = ts else d = time() - ts end
  if d < 0 then d = 0 end
  if d < MIN then return "now" end
  if d < HOUR then return format("%dm ago", floor(d / MIN)) end
  if d < DAY then return format("%dh ago", floor(d / HOUR)) end
  if d < 30 * DAY then return format("%dd ago", floor(d / DAY)) end
  if d < 365 * DAY then return format("%dmo ago", floor(d / (30 * DAY))) end
  return format("%dy ago", floor(d / (365 * DAY)))
end

function MF.LastOnlineText(ts)
  if type(ts) ~= "number" or ts <= 0 then return "Offline" end
  if ts >= 1000000000 and time() - ts > 365 * DAY then return "Offline" end
  return MF.RelativeTime(ts) or "Offline"
end

------------------------------------------------------------------ friend tags
-- Enum.BattleNetFriendTag (forever branch): Professions, PvP, Raiding, Dungeons, Delves,
-- Questing, Roleplaying, DamagerRole, HealerRole, TankRole (values 0..9).
MF.TAG_DEFS = {
  { key = "Professions", short = "Prof", label = "Professions", group = "interests", hex = "e6cc80" },
  { key = "PvP",         short = "PvP",  label = "PvP",         group = "interests", hex = "ff6060" },
  { key = "Raiding",     short = "Raid", label = "Raiding",     group = "interests", hex = "ff9a3c" },
  { key = "Dungeons",    short = "Dng",  label = "Dungeons",    group = "interests", hex = "5fb4ff" },
  { key = "Delves",      short = "Dlv",  label = "Delves",      group = "interests", hex = "c79cff" },
  { key = "Questing",    short = "Q",    label = "Questing",    group = "interests", hex = "ffd100" },
  { key = "Roleplaying", short = "RP",   label = "Roleplaying", group = "interests", hex = "ff8ad8" },
  { key = "DamagerRole", short = "D",    label = "Damage",      group = "roles",     hex = "ff5555" },
  { key = "HealerRole",  short = "H",    label = "Healer",      group = "roles",     hex = "55ff77" },
  { key = "TankRole",    short = "T",    label = "Tank",        group = "roles",     hex = "6fa8ff" },
}

local tagByValue
local function ResolveTags()
  if tagByValue then return end
  tagByValue = {}
  local enum = Enum and Enum.BattleNetFriendTag
  for _, def in ipairs(MF.TAG_DEFS) do
    def.value = enum and enum[def.key] or nil
    if def.value ~= nil then tagByValue[def.value] = def end
  end
end

function MF.TagDef(value)
  ResolveTags()
  return tagByValue[value]
end

function MF.TagValue(key) -- enum value for a key like "Raiding" (nil if unknown)
  ResolveTags()
  for _, def in ipairs(MF.TAG_DEFS) do
    if def.key == key then return def.value end
  end
  return nil
end

function MF.TagsEnabled()
  local c = C_BattleNet
  if not (c and c.AreFriendTagsEnabled) then return false end
  local ok, v = pcall(c.AreFriendTagsEnabled)
  return (ok and v) and true or false
end

function MF.TagSupported(def)
  ResolveTags()
  if def.value == nil then return false end
  local c = C_BattleNet
  if c and c.IsFriendTagSupportedForCurrentGameType then
    local ok, v = pcall(c.IsFriendTagSupportedForCurrentGameType, def.value)
    if ok then return v and true or false end
  end
  return true
end
