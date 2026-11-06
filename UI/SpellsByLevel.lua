--===========================================================================
-- EzWoW - Spell Control
-- UI/SpellsByLevel.lua : Spells-by-Level Window & Spellbook Side Panel
--===========================================================================
local ADDON_NAME, ns = ...
local type, pairs, ipairs, tonumber, tostring, select, pcall = type, pairs, ipairs, tonumber, tostring, select, pcall

local SpellsByLevelUI = ns.SpellsByLevelUI or {}
ns.SpellsByLevelUI = SpellsByLevelUI

local ACCENT_R, ACCENT_G, ACCENT_B = ns.ACCENT_R or 0.361, ns.ACCENT_G or 0.878, ns.ACCENT_B or 0.722
local ICON_PATH = ns.ICON_PATH
local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil
local CHECK_TEXTURE = "Interface\\RaidFrame\\ReadyCheck-Ready"
local QUESTION_ICON = 134400

local HEADER_H = 22
local ROW_H = 24
local COMPACT_ROW_H = 22

-----------------------------------------------------------------------------
-- Helpers
-----------------------------------------------------------------------------
function SpellsByLevelUI.FormatMoney(copper)
    copper = tonumber(copper) or 0
    if copper <= 0 then return ns:L("SBL_FREE") end
    local fn = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or _G.GetCoinTextureString
    if type(fn) == "function" then
        local ok, text = pcall(fn, copper)
        if ok and type(text) == "string" then return text end
    end
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local rest = copper % 100
    local parts = {}
    if gold > 0 then parts[#parts + 1] = "|cffffd700" .. gold .. "g|r" end
    if silver > 0 then parts[#parts + 1] = "|cffc7c7cf" .. silver .. "s|r" end
    if rest > 0 then parts[#parts + 1] = "|cffeda55f" .. rest .. "c|r" end
    return table.concat(parts, " ")
end

local function spellLabel(row)
    if row.rank and row.rank ~= "" then
        return row.name .. " |cffA7B9C5(" .. row.rank .. ")|r"
    end
    return row.name
end

local function makeCloseButton(parent, onClick)
    local close = CreateFrame("Button", nil, parent, BACKDROP_TEMPLATE)
    close:SetSize(22, 22)
    close:SetFrameLevel(parent:GetFrameLevel() + 3)
    ns.UIKit:ApplyBackdrop(close)
    close:SetBackdropColor(0.114, 0.157, 0.192, 0.96)
    close:SetBackdropBorderColor(0.204, 0.298, 0.357, 1)
    local txt = close:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    txt:SetPoint("CENTER")
    txt:SetTextColor(0.655, 0.725, 0.773)
    close.label = txt
    close:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
        txt:SetTextColor(0.929, 0.957, 0.969)
        if self.tipKey and GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(ns:L(self.tipKey), ACCENT_R, ACCENT_G, ACCENT_B, 1, true)
            GameTooltip:Show()
        end
    end)
    close:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.204, 0.298, 0.357, 1)
        txt:SetTextColor(0.655, 0.725, 0.773)
        if self.tipKey and GameTooltip then GameTooltip:Hide() end
    end)
    close:SetScript("OnClick", onClick)
    return close
end

-----------------------------------------------------------------------------
-- Shared scrolling list (used by the window and the spellbook panel)
-----------------------------------------------------------------------------
local function rowOnEnter(row)
    local data = row.data
    if not data or not GameTooltip then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    local shown = false
    if data.spellID and type(GameTooltip.SetSpellByID) == "function" then
        shown = pcall(GameTooltip.SetSpellByID, GameTooltip, data.spellID)
    end
    if not shown then
        GameTooltip:SetText(data.name, 1, 1, 1)
        if data.rank then GameTooltip:AddLine(data.rank, 0.655, 0.725, 0.773) end
        GameTooltip:AddLine(string.format(ns:L("SBL_REQ_LEVEL"), data.level), 0.929, 0.957, 0.969)
    end
    GameTooltip:AddLine(ns:L("SBL_COST") .. ": " .. SpellsByLevelUI.FormatMoney(data.cost), 0.929, 0.957, 0.969)
    if data.learned then
        GameTooltip:AddLine(ns:L("SBL_LEARNED"), 0.45, 0.50, 0.54)
    elseif data.availableNow then
        GameTooltip:AddLine(ns:L("SBL_AVAILABLE"), ACCENT_R, ACCENT_G, ACCENT_B)
    end
    GameTooltip:Show()
end

local function rowOnLeave()
    if GameTooltip then GameTooltip:Hide() end
end

local function createRow(list)
    local row = CreateFrame("Button", nil, list.content)
    row:SetHeight(ROW_H)

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 0.14)

    row.hover = row:CreateTexture(nil, "HIGHLIGHT")
    row.hover:SetAllPoints()
    row.hover:SetColorTexture(1, 1, 1, 0.06)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetPoint("LEFT", 4, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.check = row:CreateTexture(nil, "OVERLAY")
    row.check:SetSize(14, 14)
    row.check:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", 4, -3)
    row.check:SetTexture(CHECK_TEXTURE)

    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)

    row.cost = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.cost:SetPoint("RIGHT", -6, 0)
    row.cost:SetJustifyH("RIGHT")
    row.cost:SetWordWrap(false)

    row.header = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.header:SetPoint("BOTTOMLEFT", 4, 5)
    row.header:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B)

    row.line = row:CreateTexture(nil, "ARTWORK")
    row.line:SetColorTexture(0.204, 0.298, 0.357, 0.85)
    row.line:SetPoint("BOTTOMLEFT", 0, 2)
    row.line:SetPoint("BOTTOMRIGHT", 0, 2)
    row.line:SetHeight(1)

    row:SetScript("OnEnter", rowOnEnter)
    row:SetScript("OnLeave", rowOnLeave)
    return row
end

local function setupHeaderRow(row, text)
    row.data = nil
    row:EnableMouse(false)
    row:SetHeight(HEADER_H)
    row.bg:Hide()
    row.icon:Hide()
    row.check:Hide()
    row.text:Hide()
    row.cost:Hide()
    row.header:Show()
    row.line:Show()
    row.header:SetText(text)
    row:SetAlpha(1)
end

local function setupSpellRow(list, row, data)
    row.data = data
    row:EnableMouse(true)
    local height = list.compact and COMPACT_ROW_H or ROW_H
    row:SetHeight(height)
    row.header:Hide()
    row.line:Hide()
    row.icon:Show()
    row.text:Show()
    row.cost:Show()

    local iconSize = height - 4
    row.icon:SetSize(iconSize, iconSize)
    row.icon:SetTexture(data.icon or QUESTION_ICON)

    local costWidth = list.compact and 74 or 96
    row.cost:SetWidth(costWidth)
    row.cost:SetText(SpellsByLevelUI.FormatMoney(data.cost))

    row.text:ClearAllPoints()
    row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.text:SetPoint("RIGHT", row.cost, "LEFT", -6, 0)
    if list.compact then
        row.text:SetText("Lv " .. data.level .. " · " .. spellLabel(data))
    else
        row.text:SetText(spellLabel(data))
    end

    row.check:SetShown(data.learned and true or false)
    row.bg:SetShown(data.availableNow and true or false)
    if data.learned then
        row:SetAlpha(0.45)
        row.text:SetTextColor(0.655, 0.725, 0.773)
        row.icon:SetDesaturated(true)
    elseif data.availableNow then
        row:SetAlpha(1)
        row.text:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B)
        row.icon:SetDesaturated(false)
    else
        row:SetAlpha(1)
        row.text:SetTextColor(0.929, 0.957, 0.969)
        row.icon:SetDesaturated(false)
    end
end

-- opts: compact (rows carry "Lv N" instead of level headers)
function SpellsByLevelUI.CreateList(parent, opts)
    local list = { rows = {}, compact = opts and opts.compact or false }

    local okScroll, scroll = pcall(CreateFrame, "ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    if not okScroll or not scroll then
        scroll = CreateFrame("ScrollFrame", nil, parent)
        scroll:EnableMouseWheel(true)
        scroll:SetScript("OnMouseWheel", function(self, delta)
            local maxScroll = self:GetVerticalScrollRange() or 0
            local nextScroll = math.max(0, math.min(maxScroll, self:GetVerticalScroll() - delta * 40))
            self:SetVerticalScroll(nextScroll)
        end)
    end
    list.scroll = scroll

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(10, 10)
    scroll:SetScrollChild(content)
    list.content = content

    scroll:SetScript("OnSizeChanged", function(self, width)
        if width and width > 0 then content:SetWidth(width) end
    end)

    local empty = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    empty:SetPoint("TOPLEFT", scroll, "TOPLEFT", 8, -24)
    empty:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", -8, -24)
    empty:SetJustifyH("CENTER")
    empty:SetTextColor(0.655, 0.725, 0.773)
    empty:Hide()
    list.empty = empty
    return list
end

function SpellsByLevelUI.RenderList(list, view)
    local width = list.scroll:GetWidth()
    if width and width > 0 then list.content:SetWidth(width) end

    local used, y = 0, 0
    local function nextRow()
        used = used + 1
        local row = list.rows[used]
        if not row then
            row = createRow(list)
            list.rows[used] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", list.content, "TOPLEFT", 0, -y)
        row:SetPoint("TOPRIGHT", list.content, "TOPRIGHT", 0, -y)
        row:Show()
        return row
    end

    if not view.hasData then
        list.empty:SetText(ns:L("SBL_EMPTY"))
        list.empty:Show()
    elseif #view.rows == 0 then
        list.empty:SetText(ns:L("SBL_ALL_LEARNED"))
        list.empty:Show()
    else
        list.empty:Hide()
        local lastLevel
        for _, data in ipairs(view.rows) do
            if not list.compact and data.level ~= lastLevel then
                lastLevel = data.level
                local header = nextRow()
                setupHeaderRow(header, string.format(ns:L("SBL_LEVEL"), data.level))
                y = y + HEADER_H
            end
            local row = nextRow()
            setupSpellRow(list, row, data)
            y = y + row:GetHeight()
        end
    end
    for index = used + 1, #list.rows do
        list.rows[index]:Hide()
        list.rows[index].data = nil
    end
    list.content:SetHeight(math.max(y, 1))
    if list.scroll.UpdateScrollChildRect then list.scroll:UpdateScrollChildRect() end
end

local function summaryText(view)
    if not view.hasData then return "" end
    if view.availableCount > 0 then
        return string.format(ns:L("SBL_SUMMARY"), view.availableCount, SpellsByLevelUI.FormatMoney(view.availableCost))
    end
    return ns:L("SBL_SUMMARY_NONE")
end

-----------------------------------------------------------------------------
-- Window
-----------------------------------------------------------------------------
function ns:CreateSpellsByLevelWindow()
    if self.spellsByLevelFrame then return self.spellsByLevelFrame end

    local win = CreateFrame("Frame", "EzWoWSpellControlSpellsByLevel", UIParent, BACKDROP_TEMPLATE)
    win:SetSize(440, 540)
    win:SetPoint("CENTER", UIParent, "CENTER", 120, 0)
    win:SetFrameStrata("FULLSCREEN_DIALOG")
    win:SetToplevel(true)
    win:SetClampedToScreen(true)
    win:SetMovable(true)
    win:EnableMouse(true)
    ns.UIKit:ApplyBackdrop(win, 1, 1)
    win:SetBackdropColor(0.071, 0.094, 0.122, 0.97)
    win:SetBackdropBorderColor(0.204, 0.298, 0.357, 1)
    win:Hide()
    if UISpecialFrames then
        tinsert(UISpecialFrames, "EzWoWSpellControlSpellsByLevel")
    end

    local top = CreateFrame("Frame", nil, win, BACKDROP_TEMPLATE)
    top:SetPoint("TOPLEFT", win, "TOPLEFT", 1, -1)
    top:SetPoint("TOPRIGHT", win, "TOPRIGHT", -1, -1)
    top:SetHeight(52)
    top:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    top:SetBackdropColor(0.114, 0.157, 0.192, 0.98)
    top:EnableMouse(true)
    top:RegisterForDrag("LeftButton")
    top:SetScript("OnDragStart", function() win:StartMoving() end)
    top:SetScript("OnDragStop", function() win:StopMovingOrSizing() end)

    local accent = top:CreateTexture(nil, "ARTWORK")
    accent:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 1)
    accent:SetPoint("BOTTOMLEFT", top, "BOTTOMLEFT", 0, 0)
    accent:SetPoint("BOTTOMRIGHT", top, "BOTTOMRIGHT", 0, 0)
    accent:SetHeight(2)

    local titleIcon = top:CreateTexture(nil, "ARTWORK")
    titleIcon:SetSize(26, 26)
    titleIcon:SetPoint("TOPLEFT", 12, -12)
    titleIcon:SetTexture(ICON_PATH)

    local heading = top:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    heading:SetPoint("TOPLEFT", 46, -9)
    heading:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B)
    win.heading = heading

    local sub = top:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -3)
    sub:SetWidth(340)
    sub:SetJustifyH("LEFT")
    sub:SetTextColor(0.655, 0.725, 0.773)
    win.sub = sub

    local close = makeCloseButton(top, function() win:Hide() end)
    close:SetPoint("TOPRIGHT", -10, -10)
    close.label:SetText("X")

    local summary = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    summary:SetPoint("TOPLEFT", 16, -64)
    summary:SetPoint("TOPRIGHT", -16, -64)
    summary:SetJustifyH("LEFT")
    summary:SetWordWrap(false)
    summary:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B)
    win.summary = summary

    local list = SpellsByLevelUI.CreateList(win, { compact = false })
    list.scroll:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -88)
    list.scroll:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -32, 12)
    win.list = list

    win:SetScript("OnShow", function() ns:RefreshSpellsByLevel() end)

    self.spellsByLevelFrame = win
    return win
end

function ns:ToggleSpellsByLevel()
    local win = self:CreateSpellsByLevelWindow()
    if win:IsShown() then
        win:Hide()
    else
        win:Show()
        win:Raise()
    end
end

-----------------------------------------------------------------------------
-- Spellbook side panel
-----------------------------------------------------------------------------
local SPELLBOOK_ADDONS = { Blizzard_PlayerSpells = true, Blizzard_SpellBook = true }
local hookedBookFrames = {}
local dock

local function dockEnabled()
    local db = EzWoW_SpellControlDB
    return not db or db.spellbookDock ~= false
end

-- The frame our panel follows and the frame whose visibility means "spellbook open"
local function findSpellbook()
    local outer = _G.PlayerSpellsFrame
    if type(outer) == "table" and outer.GetObjectType then
        local inner = outer.SpellBookFrame
        if type(inner) ~= "table" or not inner.HookScript then inner = outer end
        return outer, inner
    end
    local classic = _G.SpellBookFrame
    if type(classic) == "table" and classic.GetObjectType then
        return classic, classic
    end
    return nil, nil
end

local function createDock()
    if dock then return dock end
    local panel = CreateFrame("Frame", "EzWoWSpellControlSpellbookPanel", UIParent, BACKDROP_TEMPLATE)
    panel:SetSize(280, 420)
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    ns.UIKit:ApplyBackdrop(panel, 1, 1)
    panel:SetBackdropColor(0.071, 0.094, 0.122, 0.96)
    panel:SetBackdropBorderColor(0.204, 0.298, 0.357, 1)
    panel:Hide()

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 10, -9)
    title:SetPoint("TOPRIGHT", -36, -9)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    title:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B)
    panel.title = title

    local toggle = makeCloseButton(panel, function()
        local db = EzWoW_SpellControlDB
        if db then db.spellbookDockCollapsed = not db.spellbookDockCollapsed end
        ns:UpdateSpellbookPanel()
    end)
    toggle:SetPoint("TOPRIGHT", -6, -5)
    toggle.tipKey = "SBL_TOGGLE_TIP"
    panel.toggle = toggle

    local summary = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    summary:SetPoint("TOPLEFT", 10, -32)
    summary:SetPoint("TOPRIGHT", -10, -32)
    summary:SetJustifyH("LEFT")
    summary:SetWordWrap(false)
    summary:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B)
    panel.summary = summary

    local list = SpellsByLevelUI.CreateList(panel, { compact = true })
    list.scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 6, -50)
    list.scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -28, 8)
    panel.list = list

    dock = panel
    ns.spellbookPanel = panel
    return panel
end

function ns:UpdateSpellbookPanel()
    local outer, inner = findSpellbook()
    local bookOpen = outer and inner and inner:IsVisible()
    if not (bookOpen and dockEnabled()) then
        if dock then dock:Hide() end
        return
    end
    local panel = createDock()
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", outer, "TOPRIGHT", 4, -2)
    local okStrata, strata = pcall(outer.GetFrameStrata, outer)
    panel:SetFrameStrata((okStrata and type(strata) == "string") and strata or "HIGH")

    local collapsed = EzWoW_SpellControlDB and EzWoW_SpellControlDB.spellbookDockCollapsed
    if collapsed then
        panel:SetSize(34, 34)
        panel.title:Hide()
        panel.summary:Hide()
        panel.list.scroll:Hide()
        panel.list.empty:Hide()
        panel.toggle.label:SetText(">")
        panel:Show()
        return
    end
    local okHeight, bookHeight = pcall(outer.GetHeight, outer)
    bookHeight = (okHeight and tonumber(bookHeight)) or 420
    panel:SetSize(280, math.max(240, math.min(bookHeight - 4, 620)))
    panel.title:Show()
    panel.summary:Show()
    panel.list.scroll:Show()
    panel.toggle.label:SetText("<")
    panel:Show()
    ns:RefreshSpellsByLevel()
end

local function hookSpellbook()
    local outer, inner = findSpellbook()
    if not inner then return end
    for _, frame in ipairs({ outer, inner }) do
        if not hookedBookFrames[frame] and frame.HookScript then
            hookedBookFrames[frame] = true
            frame:HookScript("OnShow", function() ns:UpdateSpellbookPanel() end)
            frame:HookScript("OnHide", function() ns:UpdateSpellbookPanel() end)
        end
    end
    ns:UpdateSpellbookPanel()
end

local loaderFrame = CreateFrame("Frame")
pcall(loaderFrame.RegisterEvent, loaderFrame, "ADDON_LOADED")
pcall(loaderFrame.RegisterEvent, loaderFrame, "PLAYER_LOGIN")
loaderFrame:SetScript("OnEvent", function(_, event, addonName)
    if event == "PLAYER_LOGIN" or SPELLBOOK_ADDONS[addonName] then
        hookSpellbook()
    end
end)

-----------------------------------------------------------------------------
-- Refresh
-----------------------------------------------------------------------------
function ns:RefreshSpellsByLevel()
    local win = self.spellsByLevelFrame
    local winShown = win and win:IsShown()
    local dockShown = dock and dock:IsShown() and dock.list.scroll:IsShown()
    if not winShown and not dockShown then return end

    local view = ns.TrainerSpells.BuildView()
    local summary = summaryText(view)

    if winShown then
        win.heading:SetText(self:L("SBL_TITLE"))
        local className = UnitClass("player")
        local sub = (type(className) == "string" and className or "")
        if view.scannedAt and view.scannedAt > 0 and type(date) == "function" then
            sub = sub .. " · " .. string.format(self:L("SBL_SCANNED"), date("%Y-%m-%d %H:%M", view.scannedAt))
        end
        win.sub:SetText(sub)
        ns.UIKit:FitFontString(win.sub, 340, 1)
        win.summary:SetText(summary)
        ns.UIKit:FitFontString(win.summary, 400, 1)
        SpellsByLevelUI.RenderList(win.list, view)
    end
    if dockShown then
        dock.title:SetText(self:L("SBL_TITLE"))
        dock.summary:SetText(summary)
        ns.UIKit:FitFontString(dock.summary, 256, 1)
        SpellsByLevelUI.RenderList(dock.list, view)
    end
end

local refreshQueued = false
function ns:RequestSpellsByLevelRefresh()
    if refreshQueued then return end
    refreshQueued = true
    local function run()
        refreshQueued = false
        ns:RefreshSpellsByLevel()
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0.2, run)
    else
        run()
    end
end
