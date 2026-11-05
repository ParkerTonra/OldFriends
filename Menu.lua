-- Old Friends v2 - Menu: data-driven context menus (MenuUtil, with a tiny fallback) and dialogs.
--
-- Menu item spec (plain tables, built by the views):
--   { title = "text" }                       non-clickable title
--   { divider = true }
--   { text = "x", func = fn }                button
--   { text = "x", sub = { ...items } }       submenu
--   { text = "x", checkbox = true, checked = fn, func = fn, keepOpen = true }
--   { text = "x", radio = true,    checked = fn, func = fn }
--   any item: disabled = true, tooltip = "reason text"
-- Panel chrome (backdrop) comes from MF.SkinPanel (UI.lua) so the enhanced/classic skin option applies here too.
local _, MF = ...
local pcall = MF.PCall -- logs failures to the diagnostics log

-- label = the menu text, for the diagnostics log / "last action" shown in blocked-action entries.
local function RunSafe(fn, label)
  if type(fn) ~= "function" then return end
  MF.SetAction("menu: " .. tostring(label or "?"))
  MF.Log("menu", tostring(label or "?"))
  local ok, err = pcall(fn)
  if not ok then MF.Print("error: " .. tostring(err)) end
end

------------------------------------------------------------------ MenuUtil path
local function ApplyCommon(desc, it)
  if it.disabled and desc.SetEnabled then desc:SetEnabled(false) end
  if it.tooltip and desc.SetTooltip then
    local text = it.tooltip
    desc:SetTooltip(function(tooltip)
      if GameTooltip_SetTitle then
        GameTooltip_SetTitle(tooltip, text, nil, true)
      else
        tooltip:AddLine(text, 1, 0.3, 0.3, true)
      end
    end)
  end
end

local function BuildDescription(desc, items)
  local keep = _G.MenuResponse and _G.MenuResponse.Refresh
  for _, it in ipairs(items) do
    pcall(function()
      local d
      if it.title then
        desc:CreateTitle(it.title)
      elseif it.divider then
        desc:CreateDivider()
      elseif it.sub then
        d = desc:CreateButton(it.text)
        BuildDescription(d, it.sub)
      elseif it.checkbox or it.radio then
        local isSel = function() return (it.checked and it.checked()) and true or false end
        local setSel = function()
          RunSafe(it.func, it.text)
          if it.keepOpen then return keep end
        end
        if it.radio then
          d = desc:CreateRadio(it.text, isSel, setSel)
        else
          d = desc:CreateCheckbox(it.text, isSel, setSel)
        end
      else
        d = desc:CreateButton(it.text, function() RunSafe(it.func, it.text) end)
      end
      if d then ApplyCommon(d, it) end
    end)
  end
end

------------------------------------------------------------------ fallback menu (no MenuUtil)
local fb

-- Submenus are drawn inline: a title line, then their items indented.
local function Flatten(items, out, depth)
  depth = depth or 0
  for _, it in ipairs(items) do
    if it.sub then
      out[#out + 1] = { title = it.text, depth = depth }
      Flatten(it.sub, out, depth + 1)
    else
      local copy = setmetatable({ depth = depth }, { __index = it })
      out[#out + 1] = copy
    end
  end
  return out
end

local function FallbackLabel(it)
  if it.title then return "|cffffd100" .. tostring(it.title) .. "|r" end
  if it.divider then return "|cff555555--------|r" end
  local text = tostring(it.text or "")
  if it.checkbox or it.radio then
    local on = it.checked and it.checked()
    text = (on and "[x] " or "[ ] ") .. text
  end
  if it.disabled then text = "|cff777777" .. text .. "|r" end
  return string.rep("   ", it.depth or 0) .. text
end

local function FallbackLayout()
  local list = fb.list
  local n = #list
  local w = 150
  for i = 1, math.max(n, #fb.buttons) do
    local b = fb.buttons[i]
    if i <= n then
      if not b then
        b = CreateFrame("Button", nil, fb.panel)
        b:SetHeight(16)
        b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.label:SetPoint("LEFT", 4, 0)
        b.label:SetPoint("RIGHT", -4, 0)
        b.label:SetJustifyH("LEFT")
        b.label:SetWordWrap(false)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.12)
        b:SetScript("OnClick", function(self)
          local it = self.item
          if not it or it.title or it.divider or it.disabled then return end
          RunSafe(it.func, it.text)
          if it.keepOpen then FallbackLayout() else fb:Hide() end
        end)
        b:SetScript("OnEnter", function(self)
          local it = self.item
          if it and it.tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(it.tooltip, 1, 0.3, 0.3, true)
            GameTooltip:Show()
          end
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        fb.buttons[i] = b
      end
      b.item = list[i]
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", fb.panel, "TOPLEFT", 5, -5 - (i - 1) * 16)
      b:SetPoint("TOPRIGHT", fb.panel, "TOPRIGHT", -5, -5 - (i - 1) * 16)
      b.label:SetText(FallbackLabel(list[i]))
      local fs = b.label
      local sw = fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth() or fs:GetStringWidth()
      w = math.max(w, (sw or 0) + 18)
      b:Show()
    elseif b then
      b:Hide()
    end
  end
  fb.panel:SetSize(math.min(w, 320), n * 16 + 10)
end

local function EnsureFallback()
  if fb then return fb end
  fb = CreateFrame("Button", "OldFriendsFallbackMenu", UIParent)
  fb:SetAllPoints(UIParent)
  fb:SetFrameStrata("FULLSCREEN_DIALOG")
  fb:RegisterForClicks("AnyUp")
  fb:SetScript("OnClick", function(self) self:Hide() end)
  fb:Hide()
  fb.panel = CreateFrame("Frame", nil, fb, "BackdropTemplate")
  MF.SkinPanel(fb.panel, "menu")
  fb.panel:EnableMouse(true)
  fb.panel:SetClampedToScreen(true)
  fb.buttons = {}
  fb.list = {}
  tinsert(UISpecialFrames, "OldFriendsFallbackMenu")
  return fb
end

local function OpenFallback(items)
  EnsureFallback()
  fb.list = Flatten(items, {})
  local x, y = GetCursorPosition()
  local s = UIParent:GetEffectiveScale()
  fb.panel:ClearAllPoints()
  fb.panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / s, y / s)
  FallbackLayout()
  fb:Show()
end

------------------------------------------------------------------ public: menu
-- Always our own menu frames. Blizzard's MenuUtil pools its menu frames; if an addon opens the first
-- menu of a session, those pooled frames carry addon taint, and Blizzard's own right-click menus
-- (raid markers on the target frame -> SetRaidTarget) then get blocked and blamed on this addon.
-- Set MF.useBlizzardMenu = true only to compare behaviour while debugging.
function MF.OpenMenu(owner, items)
  if not items or #items == 0 then return end
  if MF.useBlizzardMenu and MenuUtil and MenuUtil.CreateContextMenu then
    local ok = pcall(MenuUtil.CreateContextMenu, owner, function(_, root)
      BuildDescription(root, items)
    end)
    if ok then return end
  end
  OpenFallback(items)
end

------------------------------------------------------------------ dialog (prompt / confirm / copy)
local dlg
local RefreshMode -- defined below (forward declared: the dialog's scripts call it)

local function DialogAccept()
  if not dlg then return end
  local fn, text = dlg.onAccept, dlg.eb:GetText()
  local edit = dlg.hasEdit
  dlg:Hide()
  MF.SetAction("dialog accept")
  MF.Log("dialog", "accept (" .. tostring(dlg.msg:GetText()) .. ")")
  if fn then
    local ok, err
    if edit then ok, err = pcall(fn, text) else ok, err = pcall(fn) end
    if not ok then MF.Print("error: " .. tostring(err)) end
  end
end

local function EnsureDialog()
  if dlg then return dlg end
  dlg = CreateFrame("Frame", "OldFriendsDialog", UIParent, "BackdropTemplate")
  dlg:SetSize(310, 110)
  dlg:SetPoint("CENTER", 0, 120)
  dlg:SetFrameStrata("FULLSCREEN_DIALOG")
  dlg:SetToplevel(true)
  dlg:EnableMouse(true)
  dlg:SetMovable(true)
  dlg:RegisterForDrag("LeftButton")
  dlg:SetScript("OnDragStart", dlg.StartMoving)
  dlg:SetScript("OnDragStop", dlg.StopMovingOrSizing)
  MF.SkinPanel(dlg, "dialog")

  dlg.msg = dlg:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  dlg.msg:SetPoint("TOPLEFT", 12, -12) -- re-anchored per skin in MF.Dialog
  dlg.msg:SetWidth(286)
  dlg.msg:SetJustifyH("LEFT")
  dlg.msg:SetWordWrap(true)

  dlg.eb = CreateFrame("EditBox", nil, dlg, "InputBoxTemplate")
  dlg.eb:SetSize(280, 20)
  dlg.eb:SetAutoFocus(false)
  dlg.eb:SetScript("OnEscapePressed", function() dlg:Hide() end)
  dlg.eb:SetScript("OnEnterPressed", function()
    if dlg.readOnly then
      dlg:Hide()
    elseif dlg.mode == "secure" then
      MF.Print("This action needs a real click on the button (Enter cannot trigger it).")
    elseif dlg.mode == "blocked" then
      return
    else
      DialogAccept()
    end
  end)
  dlg.eb:SetScript("OnTextChanged", function(self, userInput)
    if userInput and dlg.readOnly then
      self:SetText(dlg.origText or "")
      self:HighlightText()
      return
    end
    if dlg.resolve then RefreshMode() end -- keep the secure macro in step with what is typed
  end)

  local function MakeBtn(label)
    return MF.MakeTextButton(dlg, 84, 20, label)
  end
  dlg.note = dlg:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  dlg.note:SetJustifyH("CENTER")
  dlg.ok = MakeBtn("OK")
  dlg.ok:SetPoint("BOTTOMRIGHT", dlg, "BOTTOM", -4, 10)
  dlg.ok:SetScript("OnClick", function()
    if dlg.readOnly then dlg:Hide() else DialogAccept() end
  end)
  dlg.cancel = MakeBtn("Cancel")
  dlg.cancel:SetPoint("BOTTOMLEFT", dlg, "BOTTOM", 4, 10)
  dlg.cancel:SetScript("OnClick", function() dlg:Hide() end)

  -- combat starts/ends: the secure button must not stay armed in combat, and re-arms afterwards
  dlg:RegisterEvent("PLAYER_REGEN_DISABLED")
  dlg:RegisterEvent("PLAYER_REGEN_ENABLED")
  dlg:SetScript("OnEvent", function() RefreshMode() end)
  dlg:SetScript("OnHide", function()
    if dlg.sec then dlg.sec:SetAlpha(0) end
  end)

  tinsert(UISpecialFrames, "OldFriendsDialog")
  dlg:Hide()
  return dlg
end

-- Secure mode ------------------------------------------------------------------------------------------
-- Some actions (adding a character friend) only work from a Blizzard slash command that an add-on may not call
-- directly. The dialog can therefore swap its OK button for a SecureActionButtonTemplate button that runs a macro
-- ("/friend Name"): the real click must land on that secure button, so it is a second button sitting exactly
-- behind OK. Rules that make this safe:
--   * the secure button is created and its attributes (type / macrotext) are set only OUT of combat;
--   * it is never shown/hidden/disabled by us (protected frame): we only change its alpha, and the normal OK
--     button (created above it) covers it whenever the secure one must not be clickable (combat, bad input);
--   * the macro text is rebuilt from the edit box on every keystroke, so it always matches what is typed.
-- opts.resolve(text) -> { mode = "secure", macro = "/cmd ..." } | { mode = "insecure" } | { mode = "blocked" },
--   all with an optional note shown under the text box. opts.onSent(text, macro) runs after the secure click.
local function EnsureSecure()
  if dlg.sec then return true end
  if InCombatLockdown() then return false end
  local b = MF.MakeTextButton(dlg, 84, 20, "OK", "SecureActionButtonTemplate")
  b:RegisterForClicks("AnyUp", "AnyDown")
  b:SetAllPoints(dlg.ok)
  b:SetFrameLevel(math.max(1, dlg.ok:GetFrameLevel() - 1))
  b:SetAlpha(0)
  b:SetScript("PostClick", function(self, _, down)
    if not MF.IsActionPhase(self, down) then return end
    local text = dlg.hasEdit and dlg.eb:GetText() or ""
    local macro, fn = dlg.secMacro, dlg.onSent
    MF.SetAction("secure send")
    MF.Log("secure", "clicked: " .. tostring(macro))
    dlg:Hide()
    if fn then
      local ok, err = pcall(fn, text, macro)
      if not ok then MF.Print("error: " .. tostring(err)) end
    end
  end)
  dlg.sec = b
  MF.Log("secure", "dialog secure button created")
  return true
end

RefreshMode = function()
  if not (dlg and dlg:IsShown()) then return end
  local r
  if dlg.resolve then
    local text = dlg.hasEdit and dlg.eb:GetText() or ""
    local okR, res = pcall(dlg.resolve, text)
    r = okR and res or { mode = "blocked", note = "Internal error: see /of log" }
  else
    r = { mode = "insecure" }
  end
  local mode, note = r.mode or "insecure", r.note
  if mode == "secure" then
    if InCombatLockdown() then
      mode, note = "blocked", "In combat: try again after combat."
    elseif not EnsureSecure() then
      mode, note = "blocked", "Secure button unavailable."
    end
  end
  dlg.mode = mode
  dlg.note:SetText(note or "")
  if mode == "secure" then
    dlg.sec:SetAttribute("type", "macro")
    dlg.sec:SetAttribute("macrotext", r.macro)
    dlg.secMacro = r.macro
    dlg.sec:SetLabel(dlg.okText or "OK")
    dlg.sec:SetAlpha(1)
    dlg.ok:Hide()
  else
    if dlg.sec then dlg.sec:SetAlpha(0) end
    dlg.ok:Show()
    dlg.ok:SetEnabled(mode ~= "blocked")
    dlg.ok:SetAlpha(mode == "blocked" and 0.45 or 1)
  end
end

-- opts: message, edit (bool), text, readOnly, okText, onAccept(fn(text) or fn()), resolve, onSent
function MF.Dialog(opts)
  EnsureDialog()
  dlg.onAccept = opts.onAccept
  dlg.resolve = opts.resolve
  dlg.onSent = opts.onSent
  dlg.okText = opts.okText or "OK"
  dlg.hasEdit = opts.edit and true or false
  dlg.readOnly = opts.readOnly and true or false
  dlg.origText = opts.text or ""
  dlg.msg:SetText(opts.message or "")
  dlg.ok:SetLabel(opts.okText or "OK")
  dlg.cancel:SetShown(not dlg.readOnly)
  local pad = MF.SkinMetric("dlgPad") -- 12 enhanced, larger for the classic border
  local padB = 10 + (pad - 12)
  dlg.msg:ClearAllPoints()
  dlg.msg:SetPoint("TOPLEFT", pad, -pad)
  dlg.msg:SetWidth(310 - 2 * pad)
  dlg.msg:SetText(opts.message or "")
  dlg.ok:ClearAllPoints()
  dlg.cancel:ClearAllPoints()
  if dlg.readOnly then
    dlg.ok:SetPoint("BOTTOM", dlg, "BOTTOM", 0, padB)
  else
    dlg.ok:SetPoint("BOTTOMRIGHT", dlg, "BOTTOM", -4, padB)
    dlg.cancel:SetPoint("BOTTOMLEFT", dlg, "BOTTOM", 4, padB)
  end
  local h = pad + math.max(14, dlg.msg:GetStringHeight()) + 10 + 24 + padB
  dlg.note:ClearAllPoints()
  dlg.note:SetPoint("BOTTOM", dlg, "BOTTOM", 0, padB + 28)
  dlg.note:SetWidth(310 - 2 * pad)
  if opts.resolve then h = h + 18 end
  dlg.eb:ClearAllPoints()
  if dlg.hasEdit then
    dlg.eb:SetPoint("TOPLEFT", dlg.msg, "BOTTOMLEFT", 4, -8)
    dlg.eb:SetWidth(280 - 2 * (pad - 12))
    dlg.eb:Show()
    dlg.eb:SetText(dlg.origText)
    h = h + 30
  else
    dlg.eb:Hide()
    dlg.eb:SetText("")
  end
  dlg:SetHeight(h)
  dlg:Show()
  dlg:Raise()
  RefreshMode() -- OK button vs secure button, note text
  if dlg.hasEdit then
    dlg.eb:SetFocus()
    dlg.eb:HighlightText()
  end
end

function MF.Prompt(message, text, onAccept, okText)
  MF.Dialog({ message = message, edit = true, text = text or "", onAccept = onAccept, okText = okText })
end

function MF.Confirm(message, onYes, okText)
  MF.Dialog({ message = message, edit = false, onAccept = onYes, okText = okText or "Yes" })
end

function MF.ShowCopy(text, label)
  MF.Dialog({ message = label or "Press Ctrl+C to copy:", edit = true, text = tostring(text or ""),
    readOnly = true, okText = "Close" })
end

------------------------------------------------------------------ log window (/of log all)
-- Read-only, scrollable, select-all copyable view of the whole diagnostics buffer (the one-line copy box
-- above cannot show long text).
local logWin

local function EnsureLogWindow()
  if logWin ~= nil then return logWin or nil end
  local ok, w = pcall(CreateFrame, "Frame", "OldFriendsLogWindow", UIParent, "BackdropTemplate")
  if not (ok and w) then logWin = false return nil end
  w:SetSize(560, 340)
  w:SetPoint("CENTER")
  w:SetFrameStrata("FULLSCREEN_DIALOG")
  w:SetToplevel(true)
  w:EnableMouse(true)
  w:SetMovable(true)
  w:RegisterForDrag("LeftButton")
  w:SetScript("OnDragStart", w.StartMoving)
  w:SetScript("OnDragStop", w.StopMovingOrSizing)
  MF.SkinPanel(w, "dialog")

  local title = w:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", 18, -14)
  title:SetText("Old Friends log (read-only: Select All, then Ctrl+C)")

  local ok2, sf = pcall(CreateFrame, "ScrollFrame", "OldFriendsLogScroll", w, "UIPanelScrollFrameTemplate")
  if not (ok2 and sf) then
    MF.Log("fallback", "UIPanelScrollFrameTemplate unavailable, /of log all prints to chat instead")
    w:Hide()
    logWin = false
    return nil
  end
  sf:SetPoint("TOPLEFT", 18, -36)
  sf:SetPoint("BOTTOMRIGHT", -36, 46)
  local eb = CreateFrame("EditBox", nil, sf)
  eb:SetMultiLine(true)
  eb:SetAutoFocus(false)
  eb:SetFontObject(_G.ChatFontNormal or "GameFontHighlightSmall")
  eb:SetWidth(500)
  eb:SetMaxLetters(0) -- 0 = unlimited
  sf:SetScrollChild(eb)
  eb:SetScript("OnEscapePressed", function() w:Hide() end)
  eb:SetScript("OnTextChanged", function(self, userInput)
    if userInput and w.text then self:SetText(w.text) end
  end)
  w.eb, w.sf = eb, sf

  local sel = MF.MakeTextButton(w, 90, 22, "Select All")
  sel:SetPoint("BOTTOMLEFT", 18, 14)
  sel:SetScript("OnClick", function()
    eb:SetFocus()
    eb:HighlightText()
  end)
  local close = MF.MakeTextButton(w, 90, 22, "Close")
  close:SetPoint("BOTTOMRIGHT", -18, 14)
  close:SetScript("OnClick", function() w:Hide() end)

  tinsert(UISpecialFrames, "OldFriendsLogWindow")
  w:Hide()
  logWin = w
  return w
end

function MF.ShowLogWindow()
  local w = EnsureLogWindow()
  if not w then
    for _, l in ipairs(MF.LogLines(40)) do MF.PrintRaw("  " .. l) end
    return
  end
  local text = table.concat(MF.logBuf, "\n")
  if text == "" then text = "(log is empty)" end
  w.text = text
  w.eb:SetText(text)
  w:Show()
  w:Raise()
  w.eb:SetFocus()
  w.eb:HighlightText()
  C_Timer.After(0.1, function()
    if w:IsShown() then w.sf:SetVerticalScroll(w.sf:GetVerticalScrollRange()) end
  end)
end
