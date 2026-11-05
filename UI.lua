-- Old Friends v2.1 - UI: main frame, top bar, tabs, search/filter row, pooled rows, scrolling, and the
-- two window skins ("enhanced" flat dark look and the "classic" Blizzard panel look).
--
-- Skinning: every piece of frame chrome (frame border/background, title bar, close button, tabs, buttons,
-- scrollbar, row hover/header textures, popup backdrops) is switched in ONE place, MF.ApplySkin(), so the
-- option applies live (no /reload). Widgets are built once and carry both art sets; the skin only shows
-- one set and re-anchors a few things (see SKINS). Layout of the rows themselves is identical in both.
local _, MF = ...
local pcall = MF.PCall -- logs failures to the diagnostics log

MF.rows = {}
MF.items = {}
MF.offset = 0
MF.tab = "friends"
MF.tabButtons = {}
MF.Renderers = MF.Renderers or {}

local ROW_H, VISIBLE, WIDTH = MF.ROW_H, MF.VISIBLE, MF.WIDTH
local FLAT = "Interface\\Buttons\\WHITE8x8"

------------------------------------------------------------------ skins
-- Per-skin metrics. padL/padR/padT inset the content from the frame border, scrollW is the scrollbar width,
-- arrow reserves room for the classic scrollbar's up/down buttons, skinX is the skin button's distance from the
-- right edge (it sits left of the close button), bottomY lifts the bottom button above the border, dlgPad is
-- the inner padding of the popup dialog (Menu.lua).
MF.SKINS = {
  enhanced  = { padL = 0, padR = 0, padT = 0, scrollW = 8,  arrow = 0,  skinX = 26, bottomY = 6,  dlgPad = 12, gripX = 2, gripY = 2 },
  classic = { padL = 8, padR = 8, padT = 2, scrollW = 16, arrow = 16, skinX = 32, bottomY = 12, dlgPad = 20, gripX = 7, gripY = 7 },
}

function MF.SkinName()
  local s = MF.DB and MF.DB.skin
  return (s == "classic") and "classic" or "enhanced"
end

function MF.SkinMetric(key)
  return MF.SKINS[MF.SkinName()][key]
end

local function IsClassic() return MF.SkinName() == "classic" end

local function Font(name) return _G[name] or name end

-- Stock Blizzard art used by the classic skin (all referenced by Blizzard's own XML/Lua):
--   Interface\Buttons\UI-Panel-Button-*            UIPanelButtonTemplate
--   Interface\Buttons\UI-ScrollBar-*               UIPanelScrollBarTemplate / scroll up+down buttons
--   Interface\FriendsFrame\UI-FriendsFrame-HighlightBar(-Blue)   friends / paper doll list highlights
--   UIPanelDialogTemplate                          title bar + gold-grey border + red close button
--   Interface\DialogFrame\UI-DialogBox-*, Interface\Tooltips\UI-Tooltip-*   dialog / tooltip backdrops
--   atlases uiframe-tab-* / uiframe-activetab-*    PanelTabButtonTemplate
local BTN_UP   = "Interface\\Buttons\\UI-Panel-Button-Up"
local BTN_DOWN = "Interface\\Buttons\\UI-Panel-Button-Down"
local BTN_HL   = "Interface\\Buttons\\UI-Panel-Button-Highlight"
local ROW_HL_CLASSIC  = "Interface\\FriendsFrame\\UI-FriendsFrame-HighlightBar-Blue"
local ROW_HDR_CLASSIC = "Interface\\FriendsFrame\\UI-FriendsFrame-HighlightBar"
local KNOB = "Interface\\Buttons\\UI-ScrollBar-Knob"

local BD_FLAT = { bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 }
local BD_DIALOG = {
  bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
  edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
  tile = true, tileSize = 32, edgeSize = 32,
  insets = { left = 11, right = 12, top = 12, bottom = 11 },
}
local BD_TOOLTIP = {
  bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  tile = true, tileSize = 16, edgeSize = 16,
  insets = { left = 4, right = 4, top = 4, bottom = 4 },
}
local ENHANCED_COLORS = { -- bg rgba, border rgba
  main   = { 0.05, 0.05, 0.07, 0.93,  0.20, 0.20, 0.25, 1 },
  dialog = { 0.05, 0.05, 0.08, 0.97,  0.50, 0.50, 0.55, 1 },
  menu   = { 0.05, 0.05, 0.08, 0.97,  0.40, 0.40, 0.45, 1 },
}

-- Backdrop for a frame in the current skin. kind: "main" (only used when the classic chrome frame is
-- unavailable), "dialog", "menu".
local function ApplyPanelBackdrop(frame)
  local kind = frame.mfKind or "dialog"
  if not IsClassic() then
    local c = ENHANCED_COLORS[kind] or ENHANCED_COLORS.dialog
    frame:SetBackdrop(BD_FLAT)
    frame:SetBackdropColor(c[1], c[2], c[3], c[4])
    frame:SetBackdropBorderColor(c[5], c[6], c[7], c[8])
  elseif kind == "menu" then
    frame:SetBackdrop(BD_TOOLTIP)
    frame:SetBackdropColor(0.09, 0.09, 0.19, 1)
    frame:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
  else
    frame:SetBackdrop(BD_DIALOG)
    frame:SetBackdropColor(1, 1, 1, 1)
    frame:SetBackdropBorderColor(1, 1, 1, 1)
  end
end

-- Registers a popup frame (BackdropTemplate) so its chrome follows the skin.
MF.skinPanels = {}
function MF.SkinPanel(frame, kind)
  frame.mfKind = kind
  MF.skinPanels[#MF.skinPanels + 1] = frame
  ApplyPanelBackdrop(frame)
end

------------------------------------------------------------------ small widgets
local DOT_COLORS = {
  online = { 0.2, 0.9, 0.2 }, away = { 1, 0.85, 0.1 }, busy = { 0.9, 0.2, 0.2 }, offline = { 0.5, 0.5, 0.5 },
}

-- Presence dot: Blizzard atlas if known, else a coloured square.
function MF.SetDot(tex, presence)
  if not DOT_COLORS[presence] then presence = "offline" end
  local atlas = "friends-status-" .. presence
  if MF.HasAtlas(atlas) then
    tex:SetAtlas(atlas)
    tex:SetVertexColor(1, 1, 1, 1)
  else
    local c = DOT_COLORS[presence]
    tex:SetTexture(FLAT)
    tex:SetVertexColor(c[1], c[2], c[3], 1)
  end
end

-- Three-slice button art (UIPanelButtonTemplate: 12px caps, stretched middle).
local function SetSlices(t, file)
  for _, k in ipairs({ "l", "m", "r" }) do t[k]:SetTexture(file) end
  t.l:SetTexCoord(0, 0.09375, 0, 0.6875)
  t.m:SetTexCoord(0.09375, 0.53125, 0, 0.6875)
  t.r:SetTexCoord(0.53125, 0.625, 0, 0.6875)
end

local function BuildSlices(b, parentLevelSub)
  local t = {}
  t.l = b:CreateTexture(nil, "BACKGROUND", nil, parentLevelSub)
  t.l:SetPoint("TOPLEFT")
  t.l:SetPoint("BOTTOMLEFT")
  t.l:SetWidth(12)
  t.r = b:CreateTexture(nil, "BACKGROUND", nil, parentLevelSub)
  t.r:SetPoint("TOPRIGHT")
  t.r:SetPoint("BOTTOMRIGHT")
  t.r:SetWidth(12)
  t.m = b:CreateTexture(nil, "BACKGROUND", nil, parentLevelSub)
  t.m:SetPoint("TOPLEFT", t.l, "TOPRIGHT")
  t.m:SetPoint("BOTTOMRIGHT", t.r, "BOTTOMLEFT")
  SetSlices(t, BTN_UP)
  return t
end

local function ShowSlices(t, shown)
  for _, k in ipairs({ "l", "m", "r" }) do t[k]:SetShown(shown) end
end

local function FlipV(tex)
  local ulx, uly, llx, lly, urx, ury, lrx, lry = tex:GetTexCoord()
  if ulx then tex:SetTexCoord(llx, lly, ulx, uly, lrx, lry, urx, ury) end
end

-- Classic folder-tab art (PanelTabButtonTemplate atlases), flipped so the rounded corners are on top.
-- Returns nil when the client lacks any of the atlases (the tab then falls back to the panel-button art).
local TAB_ATLAS = {
  normal = { "uiframe-tab-left", "_uiframe-tab-center", "uiframe-tab-right" },
  active = { "uiframe-activetab-left", "_uiframe-activetab-center", "uiframe-activetab-right" },
}
local function BuildTabArt(b)
  for _, set in pairs(TAB_ATLAS) do
    for _, name in ipairs(set) do
      if not MF.HasAtlas(name) then return nil end
    end
  end
  local art = {}
  for key, set in pairs(TAB_ATLAS) do
    local t = {}
    t.l = b:CreateTexture(nil, "BACKGROUND", nil, 2)
    t.l:SetAtlas(set[1])
    t.l:SetPoint("TOPLEFT")
    t.l:SetPoint("BOTTOMLEFT")
    t.l:SetWidth(12)
    t.r = b:CreateTexture(nil, "BACKGROUND", nil, 2)
    t.r:SetAtlas(set[3])
    t.r:SetPoint("TOPRIGHT")
    t.r:SetPoint("BOTTOMRIGHT")
    t.r:SetWidth(12)
    t.m = b:CreateTexture(nil, "BACKGROUND", nil, 2)
    t.m:SetAtlas(set[2])
    t.m:SetHorizTile(true)
    t.m:SetPoint("TOPLEFT", t.l, "TOPRIGHT")
    t.m:SetPoint("BOTTOMRIGHT", t.r, "BOTTOMLEFT")
    for _, k in ipairs({ "l", "m", "r" }) do FlipV(t[k]) end
    ShowSlices(t, false)
    art[key] = t
  end
  return art
end

-- Enhanced buttons get a thin 1px outline (four edge textures); classic buttons and tabs hide it.
local function AddEdges(b)
  local e = {}
  local function mk()
    local t = b:CreateTexture(nil, "BORDER")
    t:SetColorTexture(1, 1, 1, 0.14)
    t:Hide()
    return t
  end
  e.t = mk(); e.t:SetPoint("TOPLEFT"); e.t:SetPoint("TOPRIGHT"); e.t:SetHeight(1)
  e.b = mk(); e.b:SetPoint("BOTTOMLEFT"); e.b:SetPoint("BOTTOMRIGHT"); e.b:SetHeight(1)
  e.l = mk(); e.l:SetPoint("TOPLEFT"); e.l:SetPoint("BOTTOMLEFT"); e.l:SetWidth(1)
  e.r = mk(); e.r:SetPoint("TOPRIGHT"); e.r:SetPoint("BOTTOMRIGHT"); e.r:SetWidth(1)
  b.edges = e
end

local function ShowEdges(b, shown)
  if not b.edges then return end
  for _, t in pairs(b.edges) do t:SetShown(shown) end
end

-- Tab look for the current skin. selected = whether it is the current tab.
function MF.StyleTab(b, selected)
  if not b.isTab then return end
  b.selected = selected and true or false
  ShowEdges(b, false)
  if not IsClassic() then
    -- Enhanced tabs are flat text: dim when idle, white with a gold underline when selected.
    b.sel:SetShown(b.selected)
    if b.selected then
      b.bg:Show()
      b.bg:SetColorTexture(1, 1, 1, 0.06)
    else
      b.bg:Hide()
    end
    if b.tabArt then
      ShowSlices(b.tabArt.normal, false)
      ShowSlices(b.tabArt.active, false)
    end
    ShowSlices(b.art, false)
    b.hl:Show()
    b.hl:SetColorTexture(1, 1, 1, 0.06)
    b.cHl:Hide()
    b.label:SetFontObject(Font("GameFontHighlightSmall"))
    if b.selected then
      b.label:SetTextColor(1, 1, 1)
    else
      b.label:SetTextColor(0.62, 0.62, 0.68)
    end
    return
  end
  b.sel:Hide()
  b.bg:Hide()
  b.hl:Hide()
  -- Classic tabs use the same rounded red panel-button art as the other buttons (selected = pressed look).
  if b.tabArt then
    ShowSlices(b.tabArt.normal, false)
    ShowSlices(b.tabArt.active, false)
  end
  b.cHl:Show()
  ShowSlices(b.art, true)
  SetSlices(b.art, b.selected and BTN_DOWN or BTN_UP)
  b.label:SetFontObject(Font(b.selected and "GameFontHighlightSmall" or "GameFontNormalSmall"))
end

-- Button look for the current skin (tabs are delegated to StyleTab).
local function SkinButton(b)
  -- Secure buttons are protected frames: their regions are not touched during combat lockdown (re-skinned later).
  if b.isSecure and InCombatLockdown() then
    b.skinPending = true
    return
  end
  if b.isTab then
    MF.StyleTab(b, b.selected)
    return
  end
  local classic = IsClassic()
  local flat = (not classic) and b.flat -- e.g. the close button: no fill, no outline
  b.bg:SetShown(not classic and not flat)
  b.hl:SetShown(not classic)
  ShowEdges(b, not classic and not flat)
  ShowSlices(b.art, classic)
  b.cHl:SetShown(classic)
  if classic then
    SetSlices(b.art, BTN_UP)
  else
    b.bg:SetColorTexture(0.11, 0.11, 0.15, 0.9)
    if flat then
      b.hl:SetColorTexture(0.9, 0.25, 0.25, 0.4)
    else
      b.hl:SetColorTexture(1, 1, 1, 0.10)
    end
  end
  b.label:SetFontObject(Font(classic and "GameFontNormalSmall" or "GameFontHighlightSmall"))
  if flat then b.label:SetTextColor(0.7, 0.7, 0.75) end
end

MF.skinButtons = {}
-- template (optional): e.g. "SecureActionButtonTemplate" for the macro buttons that run a Blizzard slash command.
-- A secure button must be created out of combat; the caller sets b.isSecure = true.
local function MakeTextButton(parent, w, h, text, template)
  local b = CreateFrame("Button", nil, parent, template)
  b.isSecure = (template ~= nil)
  b:SetSize(w, h)
  -- enhanced art
  b.bg = b:CreateTexture(nil, "BACKGROUND")
  b.bg:SetAllPoints()
  b.bg:SetColorTexture(0.18, 0.18, 0.26, 0.95)
  b.hl = b:CreateTexture(nil, "HIGHLIGHT")
  b.hl:SetAllPoints()
  b.hl:SetColorTexture(1, 1, 1, 0.15)
  AddEdges(b)
  -- classic art (UIPanelButtonTemplate textures)
  b.art = BuildSlices(b, 1)
  ShowSlices(b.art, false)
  b.cHl = b:CreateTexture(nil, "HIGHLIGHT")
  b.cHl:SetTexture(BTN_HL)
  b.cHl:SetTexCoord(0, 0.625, 0, 0.6875)
  b.cHl:SetBlendMode("ADD")
  b.cHl:SetAllPoints()
  b.cHl:Hide()
  b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.label:SetPoint("CENTER")
  b.label:SetText(text or "")
  b.SetLabel = function(self, t) self.label:SetText(t) end
  b:SetScript("OnMouseDown", function(self)
    if self.isSecure and InCombatLockdown() then return end
    if IsClassic() and not self.isTab then
      SetSlices(self.art, BTN_DOWN)
      self.label:SetPoint("CENTER", 1, -1)
    end
  end)
  b:SetScript("OnMouseUp", function(self)
    if self.isSecure and InCombatLockdown() then return end
    if IsClassic() and not self.isTab then
      SetSlices(self.art, BTN_UP)
      self.label:SetPoint("CENTER", 0, 0)
    end
  end)
  MF.skinButtons[#MF.skinButtons + 1] = b
  SkinButton(b)
  return b
end
MF.MakeTextButton = MakeTextButton

-- Icon button: shows an atlas when one is known, else a short text glyph.
local function MakeIconButton(parent, size)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(size, size)
  b.tex = b:CreateTexture(nil, "ARTWORK")
  b.tex:SetAllPoints()
  b.txt = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  b.txt:SetPoint("CENTER")
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 1, 1, 0.15)
  return b
end

function MF.SetIcon(b, atlas, fallback, r, g, bl)
  if atlas then
    b.tex:SetAtlas(atlas)
    b.tex:Show()
    b.txt:Hide()
  else
    b.tex:Hide()
    b.txt:SetText(fallback or "")
    b.txt:SetTextColor(r or 1, g or 1, bl or 1)
    b.txt:Show()
  end
end

function MF.StarAlpha(row)
  local s = row.star
  if not s:IsShown() then return end
  if not s.dimmable then
    s:SetAlpha(1)
  elseif s:IsMouseOver() then
    s:SetAlpha(0.9)
  elseif row:IsMouseOver() then
    s:SetAlpha(0.4)
  else
    s:SetAlpha(0)
  end
end

------------------------------------------------------------------ row layout
local function P(region, point, rel, relPoint, x, y)
  region:ClearAllPoints()
  region:SetPoint(point, rel, relPoint, x, y)
end

-- Re-anchors the row widgets for a row "mode" (cached; only changes when the mode changes).
function MF.LayoutRow(row, mode)
  if row.mode == mode then return end
  row.mode = mode
  row.name:SetWidth(0)
  row.char:SetWidth(0)
  row.extra:SetWidth(0)
  row.loc:SetWidth(0)
  row.name:SetJustifyH("LEFT")
  row.char:SetJustifyH("LEFT")
  row.loc:SetJustifyH("LEFT")
  row.extra:SetJustifyH("RIGHT")
  row.loc:ClearAllPoints()
  P(row.dot, "LEFT", row, "LEFT", 4, 0)
  P(row.star, "LEFT", row, "LEFT", 15, 0)
  P(row.party, "RIGHT", row, "RIGHT", -2, 0)
  P(row.extra, "RIGHT", row.party, "LEFT", -3, 0)

  if mode == "friend" then
    P(row.name, "LEFT", row, "LEFT", 30, 0); row.name:SetWidth(84)
    P(row.char, "LEFT", row, "LEFT", 116, 0); row.char:SetWidth(124)
    P(row.kind, "LEFT", row, "LEFT", 244, 0)
    row.loc:SetPoint("LEFT", row, "LEFT", 286, 0)
    row.loc:SetPoint("RIGHT", row.extra, "LEFT", -4, 0)
    row.loc:SetJustifyH("RIGHT")
  elseif mode == "ally" then
    P(row.name, "LEFT", row, "LEFT", 30, 0); row.name:SetWidth(96)
    P(row.char, "LEFT", row, "LEFT", 128, 0); row.char:SetWidth(40)
    row.extra:SetWidth(112)
    row.loc:SetPoint("LEFT", row, "LEFT", 170, 0)
    row.loc:SetPoint("RIGHT", row.extra, "LEFT", -4, 0)
  elseif mode == "header" then
    P(row.sign, "LEFT", row, "LEFT", 6, 0)
    row.name:ClearAllPoints()
    row.name:SetPoint("LEFT", row, "LEFT", 20, 0)
    row.name:SetPoint("RIGHT", row, "RIGHT", -4, 0)
  elseif mode == "request" then
    P(row.char, "LEFT", row, "LEFT", 6, 0); row.char:SetWidth(52)
    P(row.name, "LEFT", row, "LEFT", 62, 0); row.name:SetWidth(160)
    row.loc:SetPoint("LEFT", row, "LEFT", 226, 0); row.loc:SetWidth(70)
    P(row.btnC, "RIGHT", row, "RIGHT", -2, 0)
    P(row.btnB, "RIGHT", row.btnC, "LEFT", -3, 0)
    P(row.btnA, "RIGHT", row.btnB, "LEFT", -3, 0)
  elseif mode == "ignore" then
    P(row.name, "LEFT", row, "LEFT", 8, 0); row.name:SetWidth(300)
    P(row.btnA, "RIGHT", row, "RIGHT", -2, 0)
  else -- message
    row.name:ClearAllPoints()
    row.name:SetPoint("LEFT", row, "LEFT", 8, 0)
    row.name:SetPoint("RIGHT", row, "RIGHT", -8, 0)
  end
end

local function ResetRow(row)
  row.dot:Hide()
  row.star:Hide()
  row.party:Hide()
  row.btnA:Hide()
  row.btnA:SetAlpha(1)
  row.btnB:Hide()
  row.btnC:Hide()
  row.sign:Hide()
  row.bg:Hide()
  row.name:SetText("")
  row.char:SetText("")
  row.loc:SetText("")
  row.extra:SetText("")
  row.kind:SetText("")
  row.entry = nil
end

-- Row header/hover textures for the current skin.
local function SkinRow(row)
  if IsClassic() then
    row.bg:SetTexture(ROW_HDR_CLASSIC)
    row.bg:SetTexCoord(0, 1, 0, 1)
    row.bg:SetVertexColor(1, 1, 1, 1)
    row.bg:SetBlendMode("ADD")
    row.bg:SetAlpha(0.3)
    row.hl:SetTexture(ROW_HL_CLASSIC)
    row.hl:SetTexCoord(0, 1, 0, 1)
    row.hl:SetVertexColor(1, 1, 1, 1)
    row.hl:SetBlendMode("ADD")
    row.hl:SetAlpha(1)
  else
    row.bg:SetColorTexture(1, 1, 1, 0.05)
    row.bg:SetBlendMode("BLEND")
    row.bg:SetAlpha(1)
    row.hl:SetColorTexture(1, 1, 1, 0.08)
    row.hl:SetBlendMode("BLEND")
    row.hl:SetAlpha(1)
  end
end

local function MakeRow(f, i)
  local y = -MF.TOP_H - (i - 1) * ROW_H
  local row = CreateFrame("Button", nil, f)
  row.baseY = y
  row:SetHeight(ROW_H)
  row:SetPoint("TOPLEFT", f, "TOPLEFT", 4, y)   -- re-anchored per skin by MF.ApplyLayout
  row:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, y)
  row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

  row.bg = row:CreateTexture(nil, "BACKGROUND")
  row.bg:SetAllPoints()
  row.hl = row:CreateTexture(nil, "HIGHLIGHT")
  row.hl:SetAllPoints()
  SkinRow(row)

  row.dot = row:CreateTexture(nil, "ARTWORK")
  row.dot:SetSize(9, 9)
  row.sign = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")

  row.star = MakeIconButton(row, 12)
  row.star:SetScript("OnClick", function(self) MF.StarClick(self:GetParent()) end)
  row.star:SetScript("OnEnter", function(self)
    local r = self:GetParent()
    MF.StarAlpha(r)
    MF.StarEnter(r)
  end)
  row.star:SetScript("OnLeave", function(self)
    MF.StarAlpha(self:GetParent())
    GameTooltip:Hide()
  end)

  row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.name:SetJustifyH("LEFT")
  row.name:SetWordWrap(false)
  row.char = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.char:SetJustifyH("LEFT")
  row.char:SetWordWrap(false)
  row.loc = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  row.loc:SetWordWrap(false)
  row.extra = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.extra:SetWordWrap(false)
  row.kind = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") -- realm type icons (friends tab)
  row.kind:SetJustifyH("LEFT")
  row.kind:SetWordWrap(false)
  row.kind:SetWidth(40)

  row.party = MakeIconButton(row, 16)
  row.party:SetScript("OnClick", function(self) MF.PartyClick(self:GetParent()) end)
  row.party:SetScript("OnEnter", function(self) MF.PartyEnter(self:GetParent()) end)
  row.party:SetScript("OnLeave", function() GameTooltip:Hide() end)

  row.btnA = MakeTextButton(row, 46, 14, "Accept")
  row.btnB = MakeTextButton(row, 52, 14, "Decline")
  row.btnC = MakeTextButton(row, 22, 14, "...")
  row.btnA:SetScript("OnClick", function(self) MF.RowButton(self:GetParent(), "A") end)
  row.btnB:SetScript("OnClick", function(self) MF.RowButton(self:GetParent(), "B") end)
  row.btnC:SetScript("OnClick", function(self) MF.RowButton(self:GetParent(), "C") end)
  row.btnA:SetScript("OnEnter", function(self) MF.RowButtonEnter(self:GetParent(), "A", self) end)
  row.btnA:SetScript("OnLeave", function() GameTooltip:Hide() end)

  row:SetScript("OnClick", function(self, btn) MF.RowClick(self, btn) end)
  row:SetScript("OnEnter", function(self)
    MF.StarAlpha(self)
    MF.RowEnter(self)
  end)
  row:SetScript("OnLeave", function(self)
    MF.StarAlpha(self)
    GameTooltip:Hide()
  end)
  row:Hide()
  return row
end

------------------------------------------------------------------ rendering
local function SetScrollChromeShown(shown)
  local f = MF.frame
  if not f then return end
  f.slider:SetShown(shown)
  local arrows = shown and IsClassic()
  f.scrollUp:SetShown(arrows)
  f.scrollDown:SetShown(arrows)
end

function MF.Render()
  local f = MF.frame
  if not f then return end
  local items = MF.items or {}
  local vis = MF.visibleRows or VISIBLE
  local range = math.max(0, #items - vis)
  MF.offset = math.min(math.max(MF.offset or 0, 0), range)
  f.slider.updating = true
  f.slider:SetMinMaxValues(0, math.max(range, 1))
  f.slider:SetValue(MF.offset)
  f.slider.updating = false
  SetScrollChromeShown(range > 0)
  for i = 1, #MF.rows do
    local row = MF.rows[i]
    local item = (i <= vis) and items[MF.offset + i] or nil
    if item then
      ResetRow(row)
      row.item = item
      local fn = MF.Renderers[item.type]
      if fn then
        fn(row, item)
        MF.StarAlpha(row)
        row:Show()
      else
        row:Hide()
      end
    else
      row.item = nil
      row.entry = nil
      row:Hide()
    end
  end
end

------------------------------------------------------------------ frame pieces
local function ApplyPosition()
  local f, DB = MF.frame, MF.DB
  f:ClearAllPoints()
  local p = DB.point
  if p and p[1] then
    f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
  else
    f:SetPoint("CENTER", UIParent, "CENTER", -300, 0)
  end
  f:SetScale(DB.scale or 1)
end
MF.ApplyPosition = ApplyPosition

local SHORT_STATUS = { online = "Online", away = "Away", busy = "Busy", offline = "Hidden" }

local function BuildTopBar(f)
  -- Own Battle.net status: shown (dot + label) but not settable here: that needs C_BattleNet.SetAFK / SetDND /
  -- SetAppearOffline, which are restricted to Blizzard's own UI. Clicking opens a small popup with secure macro
  -- buttons for the IN-GAME /afk and /dnd flags (see MF.ToggleStatusPopup); that is a different thing and says so.
  local s = CreateFrame("Button", nil, f)
  s:SetSize(58, 18)
  s.dot = s:CreateTexture(nil, "OVERLAY")
  s.dot:SetSize(10, 10)
  s.dot:SetPoint("LEFT", 2, 0)
  s.label = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  s.label:SetPoint("LEFT", s.dot, "RIGHT", 4, 0)
  s.label:SetText("Online")
  s:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("Battle.net status: " .. (MF.statusLabel or "Online"), 1, 1, 1)
    GameTooltip:AddLine("Changing it: " .. MF.RESTRICTED_TIP, 1, 0.4, 0.4, true)
    GameTooltip:AddLine(MF.RESTRICTED_ALT, 0.7, 0.7, 0.7, true)
    GameTooltip:AddLine("Click: set in-game Away / Busy (/afk, /dnd).", 0.7, 0.9, 1, true)
    GameTooltip:Show()
  end)
  s:SetScript("OnLeave", function() GameTooltip:Hide() end)
  s:SetScript("OnClick", function(self)
    MF.SetAction("click status")
    MF.ToggleStatusPopup(self)
  end)
  f.status = s

  f.tagText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  f.tagText:SetPoint("LEFT", s, "RIGHT", 8, 0)

  f.copy = MakeTextButton(f, 42, 18, "Copy")
  f.copy:SetPoint("LEFT", f.tagText, "RIGHT", 6, 0)
  f.copy:SetScript("OnClick", function()
    MF.SetAction("click Copy BattleTag")
    MF.CopyOwnTag()
  end)
  f.copy:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("Copy BattleTag", 1, 1, 1)
    GameTooltip:Show()
  end)
  f.copy:SetScript("OnLeave", function() GameTooltip:Hide() end)

  -- Skin switch (left of the close button): shows the skin you would switch TO.
  f.skinBtn = MakeTextButton(f, 58, 18, "Classic")
  f.skinBtn:SetScript("OnClick", function()
    MF.SetAction("click skin toggle")
    MF.SetSkin("toggle")
  end)
  f.skinBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("Window skin: " .. MF.SkinName(), 1, 1, 1)
    GameTooltip:AddLine("Click to switch (also /of skin classic|enhanced|toggle).", 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
  end)
  f.skinBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

  -- Enhanced close button. The classic skin shows the stock red close button of its chrome frame instead.
  local close = MakeTextButton(f, 18, 18, "x")
  close.flat = true
  SkinButton(close)
  close:SetPoint("TOPRIGHT", -4, -4)
  close:SetScript("OnClick", function()
    MF.SetAction("click close")
    f:Hide()
  end)
  f.close = close
end

local TAB_DEFS = {
  { key = "friends",  label = "Friends",        w = 62 },
  { key = "allies",   label = "Recent Allies",  w = 92 },
  { key = "requests", label = "Requests",       w = 70 },
  { key = "ignore",   label = "Ignore",         w = 50 },
}

local function BuildTabs(f)
  for _, d in ipairs(TAB_DEFS) do
    local b = MakeTextButton(f, d.w, 22, d.label)
    b.key = d.key
    b.isTab = true
    b.sel = b:CreateTexture(nil, "ARTWORK")
    b.sel:SetColorTexture(1, 0.82, 0, 1)
    b.sel:SetHeight(2)
    b.sel:SetPoint("BOTTOMLEFT")
    b.sel:SetPoint("BOTTOMRIGHT")
    b:SetScript("OnClick", function(self) MF.SelectTab(self.key) end)
    if d.key == "ignore" then
      b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Ignore list", 1, 1, 1)
        GameTooltip:Show()
      end)
      b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    if d.key == "requests" then
      b.glow = b:CreateTexture(nil, "OVERLAY")
      b.glow:SetAllPoints()
      b.glow:SetColorTexture(1, 0.82, 0, 0.45)
      b.glow:Hide()
      b.glowAnim = b.glow:CreateAnimationGroup()
      b.glowAnim:SetLooping("BOUNCE")
      local a = b.glowAnim:CreateAnimation("Alpha")
      a:SetFromAlpha(0.15)
      a:SetToAlpha(1)
      a:SetDuration(0.5)
      b.badgeBg = b:CreateTexture(nil, "OVERLAY")
      b.badgeBg:SetColorTexture(0.85, 0.1, 0.1, 1)
      b.badgeBg:SetSize(16, 13)
      b.badgeBg:SetPoint("TOPRIGHT", 5, 5)
      b.badgeBg:Hide()
      b.badge = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      b.badge:SetPoint("CENTER", b.badgeBg, "CENTER", 0, 0)
    end
    MF.tabButtons[d.key] = b
  end
end

function MF.LayoutTabs()
  local x = 8 + MF.SkinMetric("padL")
  for _, d in ipairs(TAB_DEFS) do
    local b = MF.tabButtons[d.key]
    local show = true
    if d.key == "allies" then show = MF.AlliesSupported() end
    b:SetShown(show)
    if show then
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", MF.frame, "TOPLEFT", x, -28)
      x = x + d.w + 4
    end
  end
end

local function BuildSearch(f)
  local filter = MakeTextButton(f, 74, 18, "Filter")
  filter:SetPoint("TOPRIGHT", -8, -53) -- re-anchored per skin by MF.ApplyLayout
  filter:SetScript("OnClick", function(self) MF.OpenFilterMenu(self) end)
  f.filter = filter

  local s = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
  s:SetHeight(18)
  s:SetPoint("TOPLEFT", 14, -53)
  s:SetPoint("TOPRIGHT", filter, "TOPLEFT", -6, 0)
  s:SetAutoFocus(false)
  -- Enhanced look: hide the template's art (kept for classic) and use a flat fill with a thin underline.
  s.tplTex = {}
  for _, r in ipairs({ s:GetRegions() }) do
    if r.IsObjectType and r:IsObjectType("Texture") then s.tplTex[#s.tplTex + 1] = r end
  end
  s.flatBg = s:CreateTexture(nil, "BACKGROUND")
  s.flatBg:SetAllPoints()
  s.flatBg:SetColorTexture(0.07, 0.07, 0.1, 0.9)
  s.flatLine = s:CreateTexture(nil, "BORDER")
  s.flatLine:SetPoint("BOTTOMLEFT")
  s.flatLine:SetPoint("BOTTOMRIGHT")
  s.flatLine:SetHeight(1)
  s.flatLine:SetColorTexture(1, 1, 1, 0.2)
  s:SetScript("OnEscapePressed", function(self)
    self:SetText("")
    self:ClearFocus()
  end)
  s:SetScript("OnEnterPressed", s.ClearFocus)
  s:SetScript("OnTextChanged", function()
    MF.offset = 0
    MF.Rebuild()
  end)
  f.search = s
  local ph = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  ph:SetPoint("LEFT", s, "LEFT", 2, 0)
  ph:SetText("Search")
  f.searchHint = ph
  s:HookScript("OnTextChanged", function(self) ph:SetShown(self:GetText() == "") end)
end

local function ScrollArrow(f, kind)
  local b = CreateFrame("Button", nil, f)
  b:SetSize(18, 16)
  local base = "Interface\\Buttons\\UI-ScrollBar-Scroll" .. kind .. "Button-"
  b:SetNormalTexture(base .. "Up")
  b:SetPushedTexture(base .. "Down")
  b:SetDisabledTexture(base .. "Disabled")
  b:SetHighlightTexture(base .. "Highlight", "ADD")
  for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture", "GetHighlightTexture" }) do
    local t = b[getter](b)
    if t then t:SetTexCoord(0.20, 0.80, 0.25, 0.75) end
  end
  b:SetScript("OnClick", function()
    MF.offset = MF.offset + ((kind == "Up") and -3 or 3)
    MF.Render()
  end)
  b:Hide()
  return b
end

local function BuildList(f)
  f:EnableMouseWheel(true)
  f:SetScript("OnMouseWheel", function(_, d)
    MF.offset = MF.offset - d * 3
    MF.Render()
  end)

  local sl = CreateFrame("Slider", nil, f)
  sl:SetOrientation("VERTICAL")
  sl:SetWidth(8)
  sl:SetPoint("TOPRIGHT", -4, -MF.TOP_H) -- re-anchored per skin by MF.ApplyLayout
  sl:SetPoint("BOTTOMRIGHT", -4, MF.BOTTOM_H)
  sl.thumbEnhanced = sl:CreateTexture(nil, "OVERLAY")
  sl.thumbEnhanced:SetColorTexture(0.55, 0.55, 0.6, 0.55)
  sl.thumbEnhanced:SetSize(4, 30)
  sl.thumbClassic = sl:CreateTexture(nil, "OVERLAY")
  sl.thumbClassic:SetTexture(KNOB)
  sl.thumbClassic:SetTexCoord(0.20, 0.80, 0.125, 0.875)
  sl.thumbClassic:SetSize(18, 24)
  sl.thumbClassic:Hide()
  sl:SetThumbTexture(sl.thumbEnhanced)
  if sl.SetObeyStepOnDrag then sl:SetObeyStepOnDrag(true) end
  sl:SetValueStep(1)
  sl:SetScript("OnValueChanged", function(self, v)
    if self.updating then return end
    MF.offset = math.floor(v + 0.5)
    MF.Render()
  end)
  f.slider = sl
  f.scrollUp = ScrollArrow(f, "Up")
  f.scrollDown = ScrollArrow(f, "Down")

  for i = 1, MF.MAX_ROWS do MF.rows[i] = MakeRow(f, i) end
end

local function BuildBottom(f)
  local b = MakeTextButton(f, 150, 22, "Add New Friend")
  b:SetPoint("BOTTOM", 0, 6) -- re-anchored per skin by MF.ApplyLayout
  b:SetScript("OnClick", function(self)
    MF.SetAction("click " .. tostring(self.label:GetText()))
    if self.disabledReason then
      MF.Print(self.disabledReason)
    elseif self.action then
      self.action()
    end
  end)
  b:SetScript("OnEnter", function(self)
    if self.disabledReason then
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:AddLine(self.disabledReason, 1, 0.3, 0.3, true)
      GameTooltip:Show()
    end
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  f.bottomBtn = b
end

------------------------------------------------------------------ skin application
-- Classic frame chrome: Blizzard's UIPanelDialogTemplate (gold-grey border, textured title bar, stock
-- red close button) as a child frame behind the content. Created on first use; if the template is not
-- available the classic skin falls back to the DialogBox backdrop on the main frame.
local function EnsureClassicChrome(f)
  if MF.chrome ~= nil then return MF.chrome or nil end
  local ok, c = pcall(CreateFrame, "Frame", "OldFriendsClassicChrome", f, "UIPanelDialogTemplate")
  if ok and c then
    c:SetAllPoints(f)
    c:SetFrameLevel(f:GetFrameLevel()) -- under the content (children are one level above their parent)
    if c.Title then c.Title:Hide() end -- the top bar (status, BattleTag) sits on the title bar instead
    local close = _G["OldFriendsClassicChromeClose"]
    if close then
      close:SetScript("OnClick", function()
        MF.SetAction("click close")
        f:Hide()
      end)
    end
    MF.chrome = c
    MF.Log("skin", "classic chrome frame created (UIPanelDialogTemplate)")
  else
    MF.chrome = false
    MF.Log("fallback", "UIPanelDialogTemplate unavailable (" .. tostring(c) .. "), using DialogBox backdrop")
  end
  return MF.chrome or nil
end

-- Positions everything whose placement depends on the skin (insets for the border / scrollbar).
function MF.ApplyLayout()
  local f = MF.frame
  if not (f and f.bottomBtn) then return end
  local S = MF.SKINS[MF.SkinName()]
  local top = -(5 + S.padT)
  f.status:ClearAllPoints()
  f.status:SetPoint("TOPLEFT", f, "TOPLEFT", 6 + S.padL, top)
  f.skinBtn:ClearAllPoints()
  f.skinBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -S.skinX, top)
  f.filter:ClearAllPoints()
  f.filter:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(8 + S.padR), -53)
  f.search:ClearAllPoints()
  f.search:SetPoint("TOPLEFT", f, "TOPLEFT", 14 + S.padL, -53)
  f.search:SetPoint("TOPRIGHT", f.filter, "TOPLEFT", -6, 0)
  f.bottomBtn:ClearAllPoints()
  f.bottomBtn:SetPoint("BOTTOM", f, "BOTTOM", 0, S.bottomY)
  if f.grip then
    f.grip:ClearAllPoints()
    f.grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -S.gripX, S.gripY)
  end

  local sr = 4 + S.padR
  f.slider:ClearAllPoints()
  f.slider:SetWidth(S.scrollW)
  f.slider:SetPoint("TOPRIGHT", f, "TOPRIGHT", -sr, -(MF.TOP_H + S.arrow))
  f.slider:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -sr, MF.BOTTOM_H + S.arrow)
  f.scrollUp:ClearAllPoints()
  f.scrollUp:SetPoint("BOTTOM", f.slider, "TOP", 0, 0)
  f.scrollDown:ClearAllPoints()
  f.scrollDown:SetPoint("TOP", f.slider, "BOTTOM", 0, 0)
  for _, row in ipairs(MF.rows) do
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", f, "TOPLEFT", 4 + S.padL, row.baseY)
    row:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(sr + S.scrollW + 2), row.baseY)
  end
  MF.LayoutTabs()
end

-- Switches ALL chrome to the saved skin (OldFriendsDB.skin). Safe to call repeatedly / while shown.
function MF.ApplySkin()
  local f = MF.frame
  if not (f and f.bottomBtn) then return end
  local classic = IsClassic()
  MF.Log("skin", "apply " .. MF.SkinName())

  -- main frame border / background / title bar / close button
  local chrome = classic and EnsureClassicChrome(f) or MF.chrome
  if classic and chrome then
    f:SetBackdrop(nil)
    chrome:Show()
  else
    if chrome then chrome:Hide() end
    f.mfKind = "main"
    ApplyPanelBackdrop(f)
  end
  f.close:SetShown(not (classic and chrome))

  for _, b in ipairs(MF.skinButtons) do SkinButton(b) end
  local sb = f.search
  if sb and sb.tplTex then
    for _, t in ipairs(sb.tplTex) do t:SetShown(classic) end
    sb.flatBg:SetShown(not classic)
    sb.flatLine:SetShown(not classic)
  end
  for _, row in ipairs(MF.rows) do SkinRow(row) end
  for _, p in ipairs(MF.skinPanels) do ApplyPanelBackdrop(p) end

  -- scrollbar art
  local sl = f.slider
  if classic then
    sl.thumbEnhanced:Hide()
    sl.thumbClassic:Show()
    sl:SetThumbTexture(sl.thumbClassic)
  else
    sl.thumbClassic:Hide()
    sl.thumbEnhanced:Show()
    sl:SetThumbTexture(sl.thumbEnhanced)
  end

  f.skinBtn:SetLabel(classic and "Enhanced" or "Classic")
  MF.ApplyLayout()
  MF.UpdateTabs()
  if f:IsShown() then MF.Render() end
end

-- name: "classic" | "enhanced" | "toggle". Returns the skin now in use. Any explicit choice also counts as
-- having picked a look (skinChosen), so the first-run chooser is not shown again.
function MF.SetSkin(name)
  local cur = MF.SkinName()
  if name == "toggle" then name = (cur == "classic") and "enhanced" or "classic" end
  if name ~= "classic" and name ~= "enhanced" then return cur end
  MF.DB.skin = name
  MF.DB.skinChosen = true
  MF.Log("skin", "set " .. name)
  if MF.skinChooser then MF.skinChooser:Hide() end
  MF.ApplySkin()
  return name
end

------------------------------------------------------------------ secure helpers / status popup
-- Text shared with the menus (Views.lua) for everything Blizzard restricts.
MF.RESTRICTED_TIP = "Not available in addons (Blizzard restriction)."
MF.RESTRICTED_ALT = "Alternative: Blizzard's own Social window (type /friends with nothing targeted)."

-- PostClick runs for both the key/mouse down and up of a secure button; true only for the phase that actually
-- performed the action (same rule as SecureActionButton_OnClick: the ActionButtonUseKeyDown CVar decides).
function MF.IsActionPhase(btn, down)
  local useDown
  if SecureActionButton_ShouldUseOnKeyDown then
    useDown = SecureActionButton_ShouldUseOnKeyDown(btn)
  else
    useDown = GetCVarBool("ActionButtonUseKeyDown")
  end
  if useDown then return down and true or false end
  return (not down) and true or false
end

-- Experiment: Away / Busy as secure macro buttons running /afk and /dnd. These toggle the IN-GAME flags
-- (the chat handler is C_ChatInfo.SendChatMessage(msg, "AFK"/"DND")). Blizzard's own Social window sets the
-- Battle.net status with C_BattleNet.SetAFK/SetDND explicitly, and nothing in the Blizzard source links /afk
-- to that, so the tooltips say exactly this and do not promise a Battle.net status change.
local statusPopup
local function EnsureStatusPopup()
  if statusPopup then return statusPopup end
  if InCombatLockdown() then return nil end -- secure frames can only be created and set up out of combat
  local p = CreateFrame("Frame", "OldFriendsStatusPopup", UIParent, "BackdropTemplate")
  p:SetSize(190, 124)
  p:SetFrameStrata("FULLSCREEN_DIALOG")
  p:SetToplevel(true)
  p:EnableMouse(true)
  MF.SkinPanel(p, "menu")
  local catcher = CreateFrame("Button", nil, UIParent) -- click anywhere else closes the popup
  catcher:SetAllPoints(UIParent)
  catcher:SetFrameStrata("FULLSCREEN")
  catcher:RegisterForClicks("AnyUp")
  catcher:SetScript("OnClick", function() p:Hide() end)
  catcher:Hide()
  p:SetScript("OnShow", function() catcher:Show() end)
  p:SetScript("OnHide", function() catcher:Hide() end)

  local title = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  title:SetPoint("TOP", 0, -10)
  title:SetText("In-game status")

  local function SecureButton(label, macro, y, tipLine)
    local b = MakeTextButton(p, 170, 20, label, "SecureActionButtonTemplate")
    b:SetPoint("TOP", p, "TOP", 0, y)
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetAttribute("type", "macro")
    b:SetAttribute("macrotext", macro)
    b:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine(label .. ": runs " .. macro, 1, 1, 1)
      GameTooltip:AddLine(tipLine, 0.7, 0.7, 0.7, true)
      GameTooltip:AddLine("Does not change your Battle.net status (" .. MF.RESTRICTED_TIP .. ")", 1, 0.4, 0.4, true)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("PostClick", function(self, _, down)
      if not MF.IsActionPhase(self, down) then return end
      MF.SetAction("status popup " .. macro)
      MF.Log("secure", "status popup ran " .. macro)
      p:Hide()
    end)
    return b
  end
  SecureButton("Away (/afk)", "/afk", -30, "Toggles your in-game AFK flag.")
  SecureButton("Busy (/dnd)", "/dnd", -54, "Toggles your in-game Do Not Disturb flag.")

  local note = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  note:SetPoint("TOP", p, "TOP", 0, -82)
  note:SetWidth(170)
  note:SetJustifyH("CENTER")
  note:SetText("Battle.net status and Appear Offline: " .. MF.RESTRICTED_TIP)

  tinsert(UISpecialFrames, "OldFriendsStatusPopup")
  p:Hide()
  statusPopup = p
  MF.Log("secure", "status popup created (macro buttons /afk, /dnd)")
  return p
end

------------------------------------------------------------------ Recent Allies loader (secure, experiment)
-- The game loads Recent Allies only when Blizzard's own Recent Allies view is shown: that view calls the
-- restricted C_RecentAllies.TryRequestRecentAlliesData, which an add-on may not call. This button runs a
-- secure macro that does what the user would do by hand:
--   /click QuickJoinToastButton      the Social micro button: opens Blizzard's Social window
--   /click OldFriendsAllyTabClick    a secure "click" proxy aimed at that window's Recent Allies tab
--   /click SocialUIFrameCloseButton  closes the window again
-- The proxy is aimed from a hook on SocialUIFrame's OnShow, because the window's tab buttons are pooled and
-- only exist while it is open. Both buttons are secure, so they are parented to UIParent (a secure child
-- would stop the main window from hiding in combat), and the Load button is hidden and unanchored in combat.
local allyLoader, allyTabProxy, socialHooked

local function FindRecentAlliesTab()
  local sf = _G.SocialUIFrame
  if not (sf and sf.EnumerateTabs and SocialUITabType and SocialUITabType.RecentAllies) then return nil end
  for tab in sf:EnumerateTabs() do
    if tab.tabData and tab.tabData.tabType == SocialUITabType.RecentAllies then return tab end
  end
  return nil
end

function MF.AimAllyTabProxy()
  if not allyTabProxy or InCombatLockdown() then return end
  local ok, tab = pcall(FindRecentAlliesTab)
  allyTabProxy:SetAttribute("clickbutton", (ok and tab) or nil)
  MF.Log("allies", "loader aimed at Blizzard's Recent Allies tab: " .. tostring(ok and tab ~= nil))
end

local function CanLoadAllies()
  return (_G.SocialUIFrame and _G.QuickJoinToastButton and _G.SocialUIFrameCloseButton and SocialUITabType
    and SocialUITabType.RecentAllies) and true or false
end

local function EnsureAllyLoader()
  if allyLoader then return allyLoader end
  if InCombatLockdown() or not CanLoadAllies() then return nil end
  allyTabProxy = CreateFrame("Button", "OldFriendsAllyTabClick", UIParent, "SecureActionButtonTemplate")
  allyTabProxy:RegisterForClicks("AnyUp", "AnyDown")
  allyTabProxy:SetAttribute("type", "click")
  allyTabProxy:SetAttribute("useOnKeyDown", false) -- /click sends an up-click
  allyTabProxy:Hide()
  if not socialHooked then
    SocialUIFrame:HookScript("OnShow", function() MF.AimAllyTabProxy() end)
    socialHooked = true
  end

  local b = MakeTextButton(UIParent, 150, 22, "Load Recent Allies", "SecureActionButtonTemplate")
  b:RegisterForClicks("AnyUp", "AnyDown")
  b:SetAttribute("type", "macro")
  b:SetScript("PreClick", function(self)
    if InCombatLockdown() then return end
    local open = SocialUIFrame:IsShown()
    if open then MF.AimAllyTabProxy() end
    self:SetAttribute("macrotext", open and "/click OldFriendsAllyTabClick"
      or "/click QuickJoinToastButton\n/click OldFriendsAllyTabClick\n/click SocialUIFrameCloseButton")
  end)
  b:SetScript("PostClick", function(self, _, down)
    if not MF.IsActionPhase(self, down) then return end
    MF.SetAction("load recent allies")
    MF.Log("allies", "Load Recent Allies clicked (secure macro)")
    C_Timer.After(3, function()
      if not MF.alliesFull then
        MF.Print("Recent Allies did not load. Open Blizzard's window (Shift+O) and click Recent Allies.")
      end
      MF.UpdateAllyLoadButton()
    end)
  end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Load Recent Allies", 1, 1, 1)
    GameTooltip:AddLine("The game only loads this list when Blizzard's own Recent Allies view opens. "
      .. "This opens it for a moment and closes it again.", 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:Hide()
  MF.frame:HookScript("OnHide", function() MF.UpdateAllyLoadButton() end)
  allyLoader = b
  MF.Log("secure", "Recent Allies loader created")
  return b
end

-- Shows the Load button over the bottom button spot while the Allies tab shows the saved list.
function MF.UpdateAllyLoadButton()
  if InCombatLockdown() then return end -- PLAYER_REGEN_ENABLED calls this again
  local f = MF.frame
  local want = f and f:IsShown() and MF.tab == "allies" and not MF.testMode and MF.AlliesSupported()
    and not MF.alliesFull
  if not want then
    if allyLoader then
      allyLoader:Hide()
      allyLoader:ClearAllPoints()
    end
    return
  end
  local b = EnsureAllyLoader()
  if not b then return end
  b:SetScale(f:GetScale())
  b:SetFrameStrata(f:GetFrameStrata())
  b:SetFrameLevel(f:GetFrameLevel() + 20)
  b:ClearAllPoints()
  b:SetPoint("CENTER", f.bottomBtn, "CENTER")
  b:Show()
end

-- PLAYER_REGEN_DISABLED: secure frames can still be changed during this event, not after it.
function MF.HideAllyLoaderForCombat()
  if allyLoader then
    allyLoader:Hide()
    allyLoader:ClearAllPoints()
  end
end

function MF.ToggleStatusPopup(owner)
  if MF.testMode then
    MF.Print("(test) status popup: Away would run /afk, Busy would run /dnd (in-game flags only)")
    return
  end
  local p = EnsureStatusPopup()
  if not p then
    MF.Print("The status buttons can only be set up out of combat: try again after combat.")
    return
  end
  if p:IsShown() then
    p:Hide()
    return
  end
  p:ClearAllPoints()
  p:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
  p:Show()
  p:Raise()
end

------------------------------------------------------------------ first-run skin chooser
-- Our own small frame (no StaticPopup), shown on the first window open until a look was chosen, and by
-- "skin" with no argument. It is not modal: no keyboard capture, nothing else is blocked while it is up.
-- Closing it (X / Esc) keeps the Enhanced look for now and asks again next time.
local function ChooserPick(skin)
  MF.SetAction("skin chooser: " .. skin)
  MF.SetSkin(skin)
  MF.Print("look set to " .. skin .. ". Change it any time with /of skin classic|enhanced|toggle.")
end

local function EnsureChooser()
  if MF.skinChooser then return MF.skinChooser end
  local d = CreateFrame("Frame", "OldFriendsSkinChooser", UIParent, "BackdropTemplate")
  d:SetSize(400, 170)
  d:SetPoint("CENTER", 0, 80)
  d:SetFrameStrata("FULLSCREEN_DIALOG")
  d:SetToplevel(true)
  d:EnableMouse(true)
  d:SetMovable(true)
  d:RegisterForDrag("LeftButton")
  d:SetScript("OnDragStart", d.StartMoving)
  d:SetScript("OnDragStop", d.StopMovingOrSizing)
  MF.SkinPanel(d, "dialog")

  local title = d:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOP", 0, -22)
  title:SetText("Welcome to Old Friends: pick a look")

  local function Column(x, label, desc, skin)
    local b = MakeTextButton(d, 150, 26, label)
    b:SetPoint("TOP", d, "TOP", x, -56)
    b:SetScript("OnClick", function() ChooserPick(skin) end)
    local t = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t:SetPoint("TOP", b, "BOTTOM", 0, -8)
    t:SetWidth(160)
    t:SetJustifyH("CENTER")
    t:SetText(desc)
    return b
  end
  Column(-90, "Enhanced", "Compact, flat and dark.", "enhanced")
  Column(90, "Classic", "The classic WoW panel look.", "classic")

  local close = MakeTextButton(d, 18, 18, "x")
  close:SetPoint("TOPRIGHT", -10, -10)
  close:SetScript("OnClick", function() d:Hide() end)

  tinsert(UISpecialFrames, "OldFriendsSkinChooser") -- Esc closes it (keeps Enhanced, asks again next time)
  d:Hide()
  MF.skinChooser = d
  return d
end

function MF.ShowSkinChooser()
  local d = EnsureChooser()
  MF.Log("skin", "chooser shown")
  d:Show()
  d:Raise()
end

------------------------------------------------------------------ resizing
-- Size is saved as DB.width (pixels) and DB.rows (visible rows), so the height always fits whole rows.
function MF.ApplySize()
  local f, DB = MF.frame, MF.DB
  local w = math.min(MF.MAX_WIDTH, math.max(WIDTH, tonumber(DB.width) or WIDTH))
  local n = math.min(MF.MAX_ROWS, math.max(MF.MIN_ROWS, math.floor(tonumber(DB.rows) or VISIBLE)))
  MF.visibleRows = n
  f:SetSize(w, MF.TOP_H + n * ROW_H + MF.BOTTOM_H)
end

-- Called while the frame changes size: shows as many rows as fit.
function MF.UpdateVisibleRows()
  local f = MF.frame
  if not (f and f.slider) then return end
  local n = math.floor((f:GetHeight() - MF.TOP_H - MF.BOTTOM_H) / ROW_H + 0.01)
  n = math.max(MF.MIN_ROWS, math.min(MF.MAX_ROWS, n))
  if n ~= MF.visibleRows then
    MF.visibleRows = n
    MF.Render()
  end
end

-- Resize grabber in the bottom-right corner (stock chat-frame grabber art).
local function BuildGrip(f)
  f:SetResizable(true)
  local minW, minH = WIDTH, MF.TOP_H + MF.MIN_ROWS * ROW_H + MF.BOTTOM_H
  local maxW, maxH = MF.MAX_WIDTH, MF.TOP_H + MF.MAX_ROWS * ROW_H + MF.BOTTOM_H
  if f.SetResizeBounds then
    f:SetResizeBounds(minW, minH, maxW, maxH)
  else
    if f.SetMinResize then f:SetMinResize(minW, minH) end
    if f.SetMaxResize then f:SetMaxResize(maxW, maxH) end
  end

  local g = CreateFrame("Button", nil, f)
  g:SetSize(16, 16)
  g:SetFrameLevel(f:GetFrameLevel() + 10)
  local base = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-"
  g:SetNormalTexture(base .. "Up")
  g:SetPushedTexture(base .. "Down")
  g:SetHighlightTexture(base .. "Highlight")
  for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture" }) do
    local t = g[getter](g)
    if t then t:SetTexCoord(0, 1, 0, 1) end -- stock art already points to the bottom-right
  end
  g:SetScript("OnMouseDown", function(_, btn)
    if btn ~= "LeftButton" then return end
    MF.SetAction("resize start")
    GameTooltip:Hide()
    f:StartSizing("BOTTOMRIGHT")
  end)
  g:SetScript("OnMouseUp", function(_, btn)
    if btn == "RightButton" then
      -- Right-click: back to the default size (a double-click would nudge the size on the first click).
      MF.SetAction("resize reset")
      MF.DB.width, MF.DB.rows = nil, nil
      MF.ApplySize()
      MF.Render()
      return
    end
    if btn ~= "LeftButton" then return end
    f:StopMovingOrSizing()
    local n = MF.visibleRows or VISIBLE
    f:SetHeight(MF.TOP_H + n * ROW_H + MF.BOTTOM_H) -- snap to whole rows
    MF.DB.width = math.floor(f:GetWidth() + 0.5)
    MF.DB.rows = n
    local p, _, rp, x, y = f:GetPoint()
    MF.DB.point = { p, rp, x, y }
    MF.Render()
  end)
  g:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Drag to resize", 1, 1, 1)
    GameTooltip:AddLine("Right-click: default size", 0.7, 0.7, 0.7)
    GameTooltip:Show()
  end)
  g:SetScript("OnLeave", function() GameTooltip:Hide() end)
  f.grip = g
  f:SetScript("OnSizeChanged", function() MF.UpdateVisibleRows() end)
end

function MF.CreateMainFrame()
  local f = CreateFrame("Frame", "OldFriendsFrame", UIParent, "BackdropTemplate")
  MF.frame = f
  MF.ApplySize()
  tinsert(UISpecialFrames, "OldFriendsFrame") -- Esc closes the window
  f:SetFrameStrata("MEDIUM")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    MF.DB.point = { p, rp, x, y }
  end)
  f:Hide()

  BuildTopBar(f)
  BuildTabs(f)
  BuildSearch(f)
  BuildList(f)
  BuildBottom(f)
  BuildGrip(f)

  f:SetScript("OnShow", function() MF.OnShow() end)
  f:SetScript("OnHide", function()
    GameTooltip:Hide()
    f.search:SetText("")
  end)

  ApplyPosition()
  MF.ApplySkin() -- backdrop, chrome, buttons, layout (also positions the tabs)
  MF.UpdateTopBar()
  MF.Log("ui", "main frame created, skin " .. MF.SkinName())
end

------------------------------------------------------------------ top bar updates
local function FormatTag(tag)
  local prefix, suffix = tag:match("^(.-)(#.*)$")
  if prefix then
    return "|cffffd200" .. prefix .. "|r|cff8c8c8c" .. suffix .. "|r"
  end
  return "|cffffd200" .. tag .. "|r"
end

function MF.UpdateTopBar()
  local f = MF.frame
  if not f then return end
  local info = MF.GetOwnInfo()
  MF.SetDot(f.status.dot, info.status)
  MF.statusLabel = MF.STATUS_LABELS[info.status] or "Online"
  f.status.label:SetText(SHORT_STATUS[info.status] or "Online")
  if not info.connected then
    f.tagText:SetText("|cff808080Battle.net unavailable|r")
    f.copy:Hide()
  elseif info.tag then
    f.tagText:SetText(FormatTag(info.tag))
    f.copy:Show()
  else
    f.tagText:SetText("|cff808080No BattleTag|r")
    f.copy:Hide()
  end
end

function MF.GetOwnTag()
  return MF.GetOwnInfo().tag
end

-- Called from the Copy button's click handler. (CopyToClipboard is a restricted function, so the tag is
-- shown selected in a small box and the user presses Ctrl+C.)
function MF.CopyOwnTag()
  local tag = MF.GetOwnTag()
  if not tag then return end
  MF.ShowCopy(tag, "BattleTag (Ctrl+C to copy):")
end

------------------------------------------------------------------ tabs, bottom bar, badges
function MF.FriendsDisabled()
  local r = C_SocialRestrictions
  if r and r.IsFriendsDisabled then
    local ok, v = pcall(r.IsFriendsDisabled)
    if ok and v then return true, _G.ADDING_FRIENDS_DISABLED or "Adding friends is currently disabled." end
  end
  return false
end

function MF.UpdateBottom()
  local f = MF.frame
  if not f then return end
  local b = f.bottomBtn
  local tab = MF.tab
  if tab == "friends" or tab == "requests" then
    b:Show()
    b:SetLabel("Add New Friend")
    b.action = MF.AddFriend
    local disabled, reason = MF.FriendsDisabled()
    b.disabledReason = disabled and reason or nil
    b:SetAlpha(disabled and 0.45 or 1)
  elseif tab == "ignore" then
    b:Show()
    b:SetLabel("Block Player")
    b.action = MF.BlockPlayerPrompt
    b.disabledReason = nil
    b:SetAlpha(1)
  else
    b:Hide()
  end
  MF.UpdateAllyLoadButton()
end

function MF.UpdateFilterButton()
  local f = MF.frame
  if not f then return end
  local active
  if MF.tab == "allies" then
    local a = MF.DB.allyFilter
    active = a.online or a.away or a.busy or a.offline
  else
    active = MF.FilterActive()
  end
  f.filter:SetLabel(active and "Filter *" or "Filter")
end

function MF.ReskinPending()
  for _, b in ipairs(MF.skinButtons) do
    if b.skinPending and not InCombatLockdown() then
      b.skinPending = nil
      SkinButton(b)
    end
  end
end

function MF.UpdateTabs()
  for key, b in pairs(MF.tabButtons) do
    MF.StyleTab(b, key == MF.tab)
  end
end

function MF.UpdateBadges()
  local b = MF.tabButtons and MF.tabButtons.requests
  if not b then return end
  local n = MF.RequestCount()
  if n > 0 then
    b.badge:SetText(n > 99 and "99+" or tostring(n))
    b.badgeBg:Show()
    b.badge:Show()
  else
    b.badgeBg:Hide()
    b.badge:Hide()
  end
end

function MF.FlashRequests()
  local b = MF.tabButtons and MF.tabButtons.requests
  if not b or not b.glow then return end
  if MF.tab == "requests" and MF.frame and MF.frame:IsShown() then return end
  b.glow:Show()
  b.glowAnim:Play()
end

local function StopFlash()
  local b = MF.tabButtons.requests
  if b and b.glow then
    b.glowAnim:Stop()
    b.glow:Hide()
  end
end

function MF.SelectTab(key)
  if key == "allies" and not MF.AlliesSupported() then
    MF.Log("fallback", "allies tab unsupported, showing friends")
    key = "friends"
  end
  if not MF.tabButtons[key] then key = "friends" end
  MF.SetAction("open tab " .. key)
  MF.Log("tab", key)
  MF.tab = key
  MF.DB.lastTab = key
  MF.offset = 0
  if key == "requests" then StopFlash() end
  local f = MF.frame
  local showSearch = (key == "friends" or key == "allies")
  f.search:SetShown(showSearch)
  f.filter:SetShown(showSearch)
  f.searchHint:SetShown(showSearch and f.search:GetText() == "")
  MF.UpdateTabs()
  MF.UpdateBottom()
  MF.UpdateFilterButton()
  MF.Refresh()
end

function MF.Toggle()
  if not MF.frame then return end
  MF.SetAction("toggle window")
  if MF.frame:IsShown() then MF.frame:Hide() else MF.frame:Show() end
end
