--===========================================================================
-- EzWoW - Spell Control
-- UI/OptionsWindow.lua : EzWoW Style Settings Dialog, Stepper Controls & Slash Commands
--===========================================================================
local ADDON_NAME, ns = ...
local type, pairs, ipairs, tonumber, tostring, select, pcall = type, pairs, ipairs, tonumber, tostring, select, pcall

local SettingsDialog = ns.SettingsDialog or {}
ns.SettingsDialog = SettingsDialog
local STYLE = ns.STYLE
local ACCENT_R, ACCENT_G, ACCENT_B = ns.ACCENT_R, ns.ACCENT_G, ns.ACCENT_B
local DONATE_URL = ns.DONATE_URL
local MEDIA_PATH = ns.MEDIA_PATH
local ICON_PATH = ns.ICON_PATH
local fitFontStringToWidth = ns.fitText
local resolveSectionGroupLabel = ns.GetSectionGroupLabel
local prepareSectionOrder = ns.EnsureSectionOrder

-----------------------------------------------------------------------------
-- Show Donate Popup
-----------------------------------------------------------------------------
function ns:ShowDonatePopup()
    if not self.donateFrame then
        local copyBox = CreateFrame("Frame", "EzWoWSpellControlDonate", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
        copyBox:SetSize(390, 116)
        copyBox:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
        ns.UIKit:ElevateModal(copyBox, 260)
        ns.UIKit:ApplyBackdrop(copyBox)
        copyBox:SetBackdropColor(0.071, 0.094, 0.122, 0.98)
        copyBox:SetBackdropBorderColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)

        local formatLocalizedLabel = copyBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        formatLocalizedLabel:SetPoint("TOP", 0, -14)
        formatLocalizedLabel:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B)
        copyBox.label = formatLocalizedLabel

        local edit = CreateFrame("EditBox", nil, copyBox, BackdropTemplateMixin and "BackdropTemplate" or nil)
        edit:SetSize(346, 27)
        edit:SetFrameLevel(copyBox:GetFrameLevel() + 5)
        edit:SetPoint("TOP", 0, -43)
        ns.UIKit:ApplyBackdrop(edit)
        edit:SetBackdropColor(0.047, 0.067, 0.086, 0.96)
        edit:SetBackdropBorderColor(0.204, 0.298, 0.357, 1)
        edit:SetFontObject(ChatFontNormal)
        edit:SetTextColor(0.929, 0.957, 0.969)
        edit:SetTextInsets(8, 8, 0, 0)
        edit:SetAutoFocus(false)
        edit:SetText(DONATE_URL)
        edit:SetScript("OnEditFocusGained", function(self)
            self:SetBackdropBorderColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
            self:HighlightText()
        end)
        edit:SetScript("OnEditFocusLost", function(self)
            self:SetBackdropBorderColor(0.204, 0.298, 0.357, 1)
        end)
        edit:SetScript("OnEscapePressed", function() copyBox:Hide() end)
        edit:SetScript("OnEnterPressed", function() copyBox:Hide() end)
        copyBox.edit = edit

        local close = CreateFrame("Button", nil, copyBox, BackdropTemplateMixin and "BackdropTemplate" or nil)
        close:SetSize(22, 22)
        close:SetFrameLevel(copyBox:GetFrameLevel() + 5)
        close:SetPoint("TOPRIGHT", -6, -6)
        ns.UIKit:ApplyBackdrop(close)
        close:SetBackdropColor(0.114, 0.157, 0.192, 0.96)
        close:SetBackdropBorderColor(0.204, 0.298, 0.357, 1)
        local dismissTxt = close:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        dismissTxt:SetPoint("CENTER")
        dismissTxt:SetText("X")
        dismissTxt:SetTextColor(0.655, 0.725, 0.773)
        close:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
            dismissTxt:SetTextColor(0.929, 0.957, 0.969)
        end)
        close:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(0.204, 0.298, 0.357, 1)
            dismissTxt:SetTextColor(0.655, 0.725, 0.773)
        end)
        close:SetScript("OnClick", function() copyBox:Hide() end)

        self.donateFrame = copyBox
    end
    ns.UIKit:ElevateModal(self.donateFrame, 260)
    self.donateFrame.label:SetText(self:L("DONATE_TITLE"))
    self.donateFrame:Show()
    if self.donateFrame.Raise then self.donateFrame:Raise() end
    self.donateFrame.edit:SetFocus()
    self.donateFrame.edit:HighlightText()
end

function ns:CycleSelectedBuffSlot(slotNum)
    if not EzWoW_SpellControlDB then return end
    local keys = { "AUTO" }
    for _, buttonWidget in ipairs(self.learnedBuffDefs) do
        if buttonWidget.isLearned then
            table.insert(keys, buttonWidget.key)
        end
    end
    if slotNum == 2 then
        table.insert(keys, "NONE")
    end

    local classToken = self.playerClass
    local targetTable = (slotNum == 2) and EzWoW_SpellControlDB.selectedBuffSlot2ByClass or EzWoW_SpellControlDB.selectedBuffSlot1ByClass
    local lookupKey = targetTable[classToken] or "AUTO"
    local nextIdx = 1
    for index, entryKey in ipairs(keys) do
        if entryKey == lookupKey then
            nextIdx = (index % #keys) + 1
            break
        end
    end
    targetTable[classToken] = keys[nextIdx]
    self:ScanAllActiveUnits()
    self:RefreshSettingsTexts()
end

function ns:CreateSettingsWindow()
    if self.settingsFrame then return self.settingsFrame end

    local config = CreateFrame("Frame", "EzWoWSpellControlSettings", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    config:SetSize(420, 844)
    config:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    config:SetFrameStrata("FULLSCREEN_DIALOG")
    config:SetToplevel(true)
    config:SetClampedToScreen(true)
    config:SetMovable(true)
    config:EnableMouse(true)
    if UISpecialFrames then
        tinsert(UISpecialFrames, "EzWoWSpellControlSettings")
    end
    ns.UIKit:ApplyBackdrop(config, 1, 1)
    config:SetBackdropColor(0.071, 0.094, 0.122, 0.97)
    config:SetBackdropBorderColor(0.204, 0.298, 0.357, 1)
    config:Hide()

    local top = CreateFrame("Frame", nil, config, BackdropTemplateMixin and "BackdropTemplate" or nil)
    top:SetPoint("TOPLEFT", config, "TOPLEFT", 1, -1)
    top:SetPoint("TOPRIGHT", config, "TOPRIGHT", -1, -1)
    top:SetHeight(58)
    top:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    top:SetBackdropColor(0.114, 0.157, 0.192, 0.98)
    top:EnableMouse(true)
    top:RegisterForDrag("LeftButton")
    top:SetScript("OnDragStart", function()
        if not (InCombatLockdown and InCombatLockdown()) then config:StartMoving() end
    end)
    top:SetScript("OnDragStop", function()
        config:StopMovingOrSizing()
    end)

    local accent = top:CreateTexture(nil, "ARTWORK")
    accent:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 1)
    accent:SetPoint("BOTTOMLEFT", top, "BOTTOMLEFT", 0, 0)
    accent:SetPoint("BOTTOMRIGHT", top, "BOTTOMRIGHT", 0, 0)
    accent:SetHeight(2)

    local titleIcon = top:CreateTexture(nil, "ARTWORK")
    titleIcon:SetSize(28, 28)
    titleIcon:SetPoint("TOPLEFT", 14, -14)
    titleIcon:SetTexture(ICON_PATH)

    local headingRegion = top:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    headingRegion:SetPoint("TOPLEFT", 48, -11)
    headingRegion:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B)
    config.heading = headingRegion

    local sub = top:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", headingRegion, "BOTTOMLEFT", 0, -3)
    sub:SetWidth(320)
    sub:SetJustifyH("LEFT")
    sub:SetTextColor(0.655, 0.725, 0.773)
    config.sub = sub

    local close = CreateFrame("Button", nil, top, BackdropTemplateMixin and "BackdropTemplate" or nil)
    close:SetSize(24, 24)
    close:SetPoint("TOPRIGHT", -10, -10)
    close:SetFrameLevel(top:GetFrameLevel() + 3)
    ns.UIKit:ApplyBackdrop(close)
    close:SetBackdropColor(0.114, 0.157, 0.192, 0.96)
    close:SetBackdropBorderColor(0.204, 0.298, 0.357, 1)
    local dismissTxt = close:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    dismissTxt:SetPoint("CENTER")
    dismissTxt:SetText("X")
    dismissTxt:SetTextColor(0.655, 0.725, 0.773)
    close:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
        dismissTxt:SetTextColor(0.929, 0.957, 0.969)
    end)
    close:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.204, 0.298, 0.357, 1)
        dismissTxt:SetTextColor(0.655, 0.725, 0.773)
    end)
    close:SetScript("OnClick", function() config:Hide() end)

    local function section(y)
        local resolvedValue = config:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        resolvedValue:SetPoint("TOPLEFT", 20, y)
        resolvedValue:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B)
        local line = config:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(0.204, 0.298, 0.357, 0.85)
        line:SetPoint("TOPLEFT", config, "TOPLEFT", 20, y - 20)
        line:SetPoint("TOPRIGHT", config, "TOPRIGHT", -20, y - 20)
        line:SetHeight(1)
        return resolvedValue
    end

    local function optionCheck(dbKey, y, labelKey)
        local themeColor = CreateFrame("CheckButton", nil, config, "UICheckButtonTemplate")
        themeColor:SetSize(26, 26)
        themeColor:SetPoint("TOPLEFT", 20, y)
        local resolvedValue = config:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        resolvedValue:SetPoint("LEFT", themeColor, "RIGHT", 5, 0)
        resolvedValue:SetWidth(345)
        resolvedValue:SetJustifyH("LEFT")
        resolvedValue:SetTextColor(0.929, 0.957, 0.969)
        themeColor:SetScript("OnClick", function(self)
            if not EzWoW_SpellControlDB then return end
            EzWoW_SpellControlDB[dbKey] = not not self:GetChecked()
            if dbKey == "unified" or dbKey == "growUp" then
                EzWoW_SpellControlDB.manualHeight = nil
            end
            if InCombatLockdown and InCombatLockdown() then
                -- unit list and cells must change together; PLAYER_REGEN_ENABLED applies both
                ns.pendingSecureUpdate = true
                ns:RefreshSettingsTexts()
                return
            end
            ns:RebuildActiveUnits()
            ns:LayoutBoardCells()
            ns:ScanAllActiveUnits()
            ns:RefreshSettingsTexts()
        end)
        themeColor:SetScript("OnEnter", function(self)
            if GameTooltip and resolvedValue:GetText() then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(resolvedValue:GetText(), ACCENT_R, ACCENT_G, ACCENT_B, 1, true)
                GameTooltip:Show()
            end
        end)
        themeColor:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
        return { check = themeColor, text = resolvedValue, dbKey = dbKey, labelKey = labelKey }
    end

    config:SetSize(420, 844)
    config.secGeneral = section(-66)
    config.checks = {
        optionCheck("smartBuff",       -90,  "OPT_SMART_BUFF"),
        optionCheck("autoDownrank",    -114, "OPT_AUTO_DOWNRANK"),
        optionCheck("trackSecondBuff", -138, "OPT_TRACK_SECOND_BUFF"),
        optionCheck("preferGroupBuff", -162, "OPT_PREFER_GROUP_BUFF"),
        optionCheck("soundAlert",      -186, "OPT_SOUND_ALERT"),
        optionCheck("showSolo",        -210, "OPT_SHOW_SOLO"),
        optionCheck("showTarget",      -234, "OPT_SHOW_TARGET"),
        optionCheck("showCC",          -258, "OPT_SHOW_CC"),
        optionCheck("growUp",          -282, "OPT_GROW_UP"),
        optionCheck("spellUprank",     -306, "OPT_SPELL_UPRANK"),
    }

    config.secSpells = section(-340)

    local function constructSelectBtn(x, y, w, onClick)
        local buttonWidget = CreateFrame("Button", nil, config, BackdropTemplateMixin and "BackdropTemplate" or nil)
        buttonWidget:SetPoint("TOPLEFT", x, y)
        buttonWidget:SetSize(w, 28)
        ns.UIKit:ApplyBackdrop(buttonWidget)
        buttonWidget:SetBackdropColor(0.114, 0.157, 0.192, 0.96)
        buttonWidget:SetBackdropBorderColor(0.204, 0.298, 0.357, 1)
        local displayText = buttonWidget:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        displayText:SetPoint("CENTER")
        displayText:SetWidth(w - 10)
        buttonWidget.label = displayText
        buttonWidget:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(ACCENT_R, ACCENT_G, ACCENT_B, 1) end)
        buttonWidget:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(0.204, 0.298, 0.357, 1) end)
        buttonWidget:SetScript("OnClick", onClick)
        return buttonWidget
    end

    config.slot1Btn = constructSelectBtn(20, -366, 187, function() ns:CycleSelectedBuffSlot(1) end)
    config.slot2Btn = constructSelectBtn(213, -366, 187, function() ns:CycleSelectedBuffSlot(2) end)

    local learnedPanel = CreateFrame("Frame", nil, config, BackdropTemplateMixin and "BackdropTemplate" or nil)
    learnedPanel:SetPoint("TOPLEFT", 20, -399)
    learnedPanel:SetSize(380, 62)
    ns.UIKit:ApplyBackdrop(learnedPanel)
    learnedPanel:SetBackdropColor(0.055, 0.075, 0.098, 0.90)
    learnedPanel:SetBackdropBorderColor(0.204, 0.298, 0.357, 0.85)

    local learnedBox = learnedPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    learnedBox:SetPoint("TOPLEFT", learnedPanel, "TOPLEFT", 8, -6)
    learnedBox:SetPoint("BOTTOMRIGHT", learnedPanel, "BOTTOMRIGHT", -8, 6)
    learnedBox:SetJustifyH("LEFT")
    learnedBox:SetJustifyV("TOP")
    if learnedBox.SetSpacing then
        learnedBox:SetSpacing(2)
    end
    learnedBox:SetTextColor(0.655, 0.725, 0.773)
    config.learnedBox = learnedBox

    config.langBtn = constructSelectBtn(20, -469, 380, nil)
    -- click the box, then pick a language from the list
    local langItems = {}
    for index, entryValue in ipairs(ns.SUPPORTED_LANGS) do langItems[index] = { value = entryValue.code, text = entryValue.label } end
    ns.LanguageDropdown.Attach(config.langBtn, {
        items = langItems,
        width = 200,
        colors = { accent = { ACCENT_R, ACCENT_G, ACCENT_B, 1 } },
        get = function() return EzWoW_SpellControlDB and EzWoW_SpellControlDB.lang or "Auto" end,
        set = function(code)
            if not EzWoW_SpellControlDB then return end
            EzWoW_SpellControlDB.lang = code
            ns:RefreshAllUI()
        end,
    })

    config.secControls = section(-508)

    local function stepper(x, y, getVal, setVal, minVal, maxVal, step)
        local formatLocalizedLabel = config:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        formatLocalizedLabel:SetPoint("TOPLEFT", x, y - 8)
        formatLocalizedLabel:SetWidth(90)
        formatLocalizedLabel:SetJustifyH("LEFT")

        local function createStepButton(symbol, bx, delta)
            local actionBtn2 = CreateFrame("Button", nil, config, BackdropTemplateMixin and "BackdropTemplate" or nil)
            actionBtn2:SetSize(27, 29)
            actionBtn2:SetPoint("TOPLEFT", bx, y)
            ns.UIKit:ApplyBackdrop(actionBtn2)
            actionBtn2:SetBackdropColor(0.114, 0.157, 0.192, 0.96)
            actionBtn2:SetBackdropBorderColor(0.204, 0.298, 0.357, 1)
            local displayText = actionBtn2:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
            displayText:SetPoint("CENTER", 0, 0)
            displayText:SetText(symbol)
            actionBtn2:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(ACCENT_R, ACCENT_G, ACCENT_B, 1) end)
            actionBtn2:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(0.204, 0.298, 0.357, 1) end)
            actionBtn2:SetScript("OnClick", function()
                setVal(math.max(minVal, math.min(maxVal, getVal() + delta)))
                ns:RefreshSettingsTexts()
            end)
            return actionBtn2
        end

        local minus = createStepButton("-", x + 94, -step)
        local plus  = createStepButton("+", x + 160, step)
        local value = config:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        value:SetPoint("CENTER", minus, "CENTER", 33, 0)
        value:SetWidth(40)
        value:SetJustifyH("CENTER")
        return formatLocalizedLabel, value
    end

    config.sizeLabel, config.sizeValue = stepper(
        20, -536,
        function() return (EzWoW_SpellControlDB and EzWoW_SpellControlDB.cellSize) or 30 end,
        function(entryValue)
            if not EzWoW_SpellControlDB then return end
            EzWoW_SpellControlDB.cellSize = entryValue
            EzWoW_SpellControlDB.manualWidth = nil
            EzWoW_SpellControlDB.manualHeight = nil
            ns:LayoutBoardCells()
            ns:UpdateBoardVisuals()
        end,
        20, 64, 2
    )

    config.raidSizeLabel, config.raidSizeValue = stepper(
        210, -536,
        function() return (EzWoW_SpellControlDB and EzWoW_SpellControlDB.raidCellSize) or 24 end,
        function(entryValue)
            if not EzWoW_SpellControlDB then return end
            EzWoW_SpellControlDB.raidCellSize = entryValue
            EzWoW_SpellControlDB.manualWidth = nil
            EzWoW_SpellControlDB.manualHeight = nil
            ns:LayoutBoardCells()
            ns:UpdateBoardVisuals()
        end,
        20, 64, 2
    )

    config.colsLabel, config.colsValue = stepper(
        20, -570,
        function() return (EzWoW_SpellControlDB and EzWoW_SpellControlDB.columns) or 5 end,
        function(entryValue)
            if not EzWoW_SpellControlDB then return end
            EzWoW_SpellControlDB.columns = entryValue
            EzWoW_SpellControlDB.manualWidth = nil
            EzWoW_SpellControlDB.manualHeight = nil
            ns:LayoutBoardCells()
            ns:UpdateBoardVisuals()
        end,
        1, 10, 1
    )

    local function opacityPct()
        return math.floor(((EzWoW_SpellControlDB and EzWoW_SpellControlDB.opacity) or 1) * 100 + 0.5)
    end
    config.alphaLabel, config.alphaValue = stepper(
        210, -570,
        opacityPct,
        function(entryValue)
            if EzWoW_SpellControlDB then EzWoW_SpellControlDB.opacity = entryValue / 100 end
        end,
        30, 100, 10
    )

    local fadeCheck = CreateFrame("CheckButton", nil, config, "UICheckButtonTemplate")
    fadeCheck:SetSize(26, 26)
    fadeCheck:SetPoint("TOPLEFT", 20, -605)
    local fadeText = config:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fadeText:SetPoint("LEFT", fadeCheck, "RIGHT", 4, 0)
    fadeText:SetWidth(160)
    fadeText:SetJustifyH("LEFT")
    fadeText:SetTextColor(0.929, 0.957, 0.969)
    fadeCheck:SetScript("OnClick", function(self)
        if EzWoW_SpellControlDB then EzWoW_SpellControlDB.fade = not not self:GetChecked() end
    end)
    fadeCheck:SetScript("OnEnter", function(self)
        if GameTooltip and fadeText:GetText() then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(fadeText:GetText(), ACCENT_R, ACCENT_G, ACCENT_B, 1, true)
            GameTooltip:Show()
        end
    end)
    fadeCheck:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    config.fadeCheck = fadeCheck
    config.fadeText = fadeText

    local function actionBtn(x, y, fn)
        local buttonWidget = CreateFrame("Button", nil, config, BackdropTemplateMixin and "BackdropTemplate" or nil)
        buttonWidget:SetSize(181, 31)
        buttonWidget:SetPoint("TOPLEFT", x, y)
        ns.UIKit:ApplyBackdrop(buttonWidget)
        buttonWidget:SetBackdropColor(0.114, 0.157, 0.192, 0.96)
        buttonWidget:SetBackdropBorderColor(0.204, 0.298, 0.357, 1)
        local formatLocalizedLabel = buttonWidget:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        formatLocalizedLabel:SetPoint("CENTER")
        formatLocalizedLabel:SetWidth(173)
        formatLocalizedLabel:SetWordWrap(false)
        formatLocalizedLabel:SetTextColor(0.929, 0.957, 0.969)
        buttonWidget.label = formatLocalizedLabel
        buttonWidget:SetScript("OnEnter", function(self)
            self:SetBackdropColor(0.16, 0.21, 0.26, 1)
            self:SetBackdropBorderColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
        end)
        buttonWidget:SetScript("OnLeave", function(self)
            self:SetBackdropColor(0.114, 0.157, 0.192, 0.96)
            self:SetBackdropBorderColor(0.204, 0.298, 0.357, 1)
        end)
        buttonWidget:SetScript("OnClick", fn)
        return buttonWidget
    end

    config.lockBtn = actionBtn(20, -638, function()
        if not EzWoW_SpellControlDB then return end
        EzWoW_SpellControlDB.lockBoard = not EzWoW_SpellControlDB.lockBoard
        ns:LayoutBoardCells()
        ns:RefreshSettingsTexts()
    end)

    config.visBtn = actionBtn(219, -638, function()
        if not EzWoW_SpellControlDB then return end
        EzWoW_SpellControlDB.showBoard = not EzWoW_SpellControlDB.showBoard
        ns:LayoutBoardCells()
        ns:RefreshSettingsTexts()
    end)

    config.expandBtn = actionBtn(20, -673, function()
        if not EzWoW_SpellControlDB then return end
        EzWoW_SpellControlDB.collapsed = false
        EzWoW_SpellControlDB.collapsedGroups = { buff = false, cleanse = false, cc = false }
        ns:LayoutBoardCells()
        ns:RefreshSettingsTexts()
    end)

    config.collapseBtn = actionBtn(219, -673, function()
        if not EzWoW_SpellControlDB then return end
        EzWoW_SpellControlDB.collapsed = true
        EzWoW_SpellControlDB.collapsedGroups = { buff = true, cleanse = true, cc = true }
        ns:LayoutBoardCells()
        ns:RefreshSettingsTexts()
    end)

    config.refreshBtn = actionBtn(20, -708, function()
        ns:ScanLearnedSpells()
        ns:RebuildActiveUnits()
        ns:LayoutBoardCells()
        ns:ScanAllActiveUnits()
        ns:RefreshSettingsTexts()
    end)

    config.resetPosBtn = actionBtn(219, -708, function()
        if InCombatLockdown and InCombatLockdown() then return end
        if EzWoW_SpellControlDB then
            EzWoW_SpellControlDB.boardPoint = nil
            EzWoW_SpellControlDB.manualWidth = nil
            EzWoW_SpellControlDB.manualHeight = nil
            EzWoW_SpellControlDB.sectionOrder = { "buff", "cleanse", "cc" }
        end
        if ns.boardFrame then
            ns.boardFrame:ClearAllPoints()
            ns.boardFrame:SetPoint("CENTER", UIParent, "CENTER", -260, 60)
        end
        ns:LayoutBoardCells()
        DEFAULT_CHAT_FRAME:AddMessage("|cff5CE0B8EzWoW - Spell Control:|r " .. ns:L("MSG_POS_RESET"))
    end)

    local donate = CreateFrame("Button", nil, config, BackdropTemplateMixin and "BackdropTemplate" or nil)
    donate:SetPoint("BOTTOMLEFT", config, "BOTTOMLEFT", 20, 38)
    donate:SetPoint("BOTTOMRIGHT", config, "BOTTOMRIGHT", -20, 38)
    donate:SetHeight(32)
    ns.UIKit:ApplyBackdrop(donate)
    donate:SetBackdropColor(0.11, 0.20, 0.22, 0.96)
    donate:SetBackdropBorderColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.95)
    local donateText = donate:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    donateText:SetPoint("CENTER")
    donateText:SetWidth(365)
    donateText:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B)
    donate.label = donateText
    donate:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.15, 0.26, 0.28, 1)
        self:SetBackdropBorderColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
    end)
    donate:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.11, 0.20, 0.22, 0.96)
        self:SetBackdropBorderColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.95)
    end)
    donate:SetScript("OnClick", function() ns:ShowDonatePopup() end)
    config.donateBtn = donate

    local hint = config:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT", 20, 78)
    hint:SetWidth(380)
    hint:SetJustifyH("LEFT")
    config.hint = hint

    local foot = config:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    foot:SetPoint("BOTTOM", 0, 12)
    -- version comes from the toc, so it never goes stale
    local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local version = getMeta and getMeta("EzWoW-SpellControl", "Version")
    foot:SetText("EzWoW - Spell Control" .. (version and (" v" .. version) or "") .. "  ·  /ezsc")

    config:SetScript("OnShow", function() ns:RefreshSettingsTexts() end)

    self.settingsFrame = config
    self:RefreshSettingsTexts()
    return config
end

function ns:RefreshSettingsTexts()
    local themeColor = self.settingsFrame
    if not themeColor or not EzWoW_SpellControlDB then return end

    themeColor.heading:SetText(self:L("SETTINGS_TITLE"))
    fitFontStringToWidth(themeColor.sub, self:L("SETTINGS_SUBTITLE"), 345, 10, 8)
    fitFontStringToWidth(themeColor.secGeneral, self:L("SECTION_GENERAL"), 375, 13, 10)
    fitFontStringToWidth(themeColor.secSpells, self:L("SECTION_SPELLS"), 375, 13, 10)
    fitFontStringToWidth(themeColor.secControls, self:L("SECTION_CONTROLS"), 375, 13, 10)

    for _, item in ipairs(themeColor.checks) do
        item.check:SetChecked(EzWoW_SpellControlDB[item.dbKey] and true or false)
        fitFontStringToWidth(item.text, self:L(item.labelKey), 340, 12, 9)
    end

    local classToken = self.playerClass
    local s1Def = self:GetSelectedBuffSlot1Def()
    local s2Def = self:GetSelectedBuffSlot2Def()

    local rawSlot1 = (EzWoW_SpellControlDB.selectedBuffSlot1ByClass and EzWoW_SpellControlDB.selectedBuffSlot1ByClass[classToken]) or "AUTO"
    local slot1Name = (rawSlot1 == "AUTO") and self:L("OPT_AUTO")
        or ((s1Def and s1Def.displayName) or self:L("SPELL_NOT_LEARNED"))
    fitFontStringToWidth(themeColor.slot1Btn.label, self:L("OPT_PRIMARY_BUFF") .. " " .. slot1Name .. " ▼", 177, 12, 9)

    local rawSlot2 = (EzWoW_SpellControlDB.selectedBuffSlot2ByClass and EzWoW_SpellControlDB.selectedBuffSlot2ByClass[classToken]) or "AUTO"
    local slot2Name
    if rawSlot2 == "NONE" then
        slot2Name = self:L("OPT_NONE")
    elseif rawSlot2 == "AUTO" then
        slot2Name = self:L("OPT_AUTO")
    else
        slot2Name = (s2Def and s2Def.displayName) or self:L("OPT_NONE")
    end
    fitFontStringToWidth(themeColor.slot2Btn.label, self:L("OPT_SECOND_BUFF") .. " " .. slot2Name .. " ▼", 177, 12, 9)

    local lTag = "[" .. self:L("SHORT_CLICK_L") .. "] "
    local rTag = "[" .. self:L("SHORT_CLICK_R") .. "] "

    local buffParts = {}
    for _, buttonWidget in ipairs(self.learnedBuffDefs) do
        if buttonWidget.isLearned and buttonWidget.highestSingle then
            local prefix = ""
            if s1Def and buttonWidget.key == s1Def.key then
                prefix = lTag
            elseif s2Def and buttonWidget.key == s2Def.key then
                prefix = rTag
            end
            table.insert(buffParts, prefix .. buttonWidget.highestSingle.name)
        end
    end
    local buffStr = (#buffParts > 0) and table.concat(buffParts, ", ") or self:L("SPELL_NOT_LEARNED")

    local dispelParts = {}
    for _, dataEntry in ipairs(self.learnedDispelList) do
        local prefix = (dataEntry.buttonSlot == 2) and rTag or lTag
        table.insert(dispelParts, prefix .. (dataEntry.fullCastName or dataEntry.name))
    end
    local dispelStr = (#dispelParts > 0) and table.concat(dispelParts, ", ") or self:L("SPELL_NOT_LEARNED")

    local ccParts = {}
    for entryIndex, ccEntry in ipairs(self.learnedCCDefs) do
        local prefix = (entryIndex == 1) and lTag or ((entryIndex == 2) and rTag or "")
        local typeNote = ccEntry.allowedTypeKeys and (" (" .. self:FormatAllowedTypesText(ccEntry) .. ")") or ""
        table.insert(ccParts, prefix .. ccEntry.name .. typeNote)
    end
    local ccStr = (#ccParts > 0) and table.concat(ccParts, ", ") or self:L("SPELL_NOT_LEARNED")

    themeColor.learnedBox:SetText(
        "|cffF1BD57" .. self:L("OPT_LEARNED_BUFFS") .. "|r " .. buffStr .. "\n" ..
        "|cff5CE0B8" .. self:L("OPT_LEARNED_DISPELS") .. "|r " .. dispelStr .. "\n" ..
        "|cffE77C70" .. self:L("OPT_LEARNED_CCS") .. "|r " .. ccStr
    )

    local lang = EzWoW_SpellControlDB.lang or "Auto"
    local langLabel = "Auto"
    for _, entryValue in ipairs(ns.SUPPORTED_LANGS) do
        if entryValue.code == lang then langLabel = entryValue.label; break end
    end
    fitFontStringToWidth(themeColor.langBtn.label, self:L("OPT_LANGUAGE") .. ": " .. langLabel .. " ▼", 365, 12, 9)

    fitFontStringToWidth(themeColor.sizeLabel, self:L("OPT_SIZE"), 88, 12, 9)
    themeColor.sizeValue:SetText(tostring(EzWoW_SpellControlDB.cellSize or 30))

    fitFontStringToWidth(themeColor.raidSizeLabel, self:L("OPT_RAID_SIZE"), 88, 12, 9)
    themeColor.raidSizeValue:SetText(tostring(EzWoW_SpellControlDB.raidCellSize or 24))

    fitFontStringToWidth(themeColor.colsLabel, self:L("OPT_COLUMNS"), 88, 12, 9)
    themeColor.colsValue:SetText(tostring(EzWoW_SpellControlDB.columns or 5))

    local pct = math.floor(((EzWoW_SpellControlDB.opacity) or 1) * 100 + 0.5)
    fitFontStringToWidth(themeColor.alphaLabel, self:L("OPT_OPACITY"), 88, 12, 9)
    themeColor.alphaValue:SetText(pct .. "%")

    themeColor.fadeCheck:SetChecked(EzWoW_SpellControlDB.fade and true or false)
    fitFontStringToWidth(themeColor.fadeText, self:L("OPT_FADE"), 160, 12, 9)

    fitFontStringToWidth(themeColor.lockBtn.label, self:L(EzWoW_SpellControlDB.lockBoard and "BTN_UNLOCK" or "BTN_LOCK"), 171, 12, 9)
    fitFontStringToWidth(themeColor.visBtn.label, self:L(EzWoW_SpellControlDB.showBoard and "BTN_HIDE_BAR" or "BTN_SHOW_BAR"), 171, 12, 9)
    fitFontStringToWidth(themeColor.expandBtn.label, self:L("BTN_EXPAND"), 171, 12, 9)
    fitFontStringToWidth(themeColor.collapseBtn.label, self:L("BTN_COLLAPSE"), 171, 12, 9)
    fitFontStringToWidth(themeColor.refreshBtn.label, self:L("BTN_REFRESH"), 171, 12, 9)
    fitFontStringToWidth(themeColor.resetPosBtn.label, self:L("BTN_RESET_POS"), 171, 12, 9)
    fitFontStringToWidth(themeColor.donateBtn.label, self:L("BTN_DONATE"), 365, 12, 10)
    fitFontStringToWidth(themeColor.hint, self:L("HINT_MOVE_RESIZE"), 375, 10, 8)
end

function ns:ToggleSettingsWindow()
    local windowFrame = self:CreateSettingsWindow()
    if windowFrame:IsShown() then
        windowFrame:Hide()
    else
        self:ScanLearnedSpells()
        self:RefreshSettingsTexts()
        windowFrame:Show()
        windowFrame:Raise()
    end
end

-----------------------------------------------------------------------------
-- Register Blizzard Canvas Launcher
-----------------------------------------------------------------------------
function ns:RegisterBlizzardCanvasLauncher()
    if self.canvasPanel then return end

    local panelFrameEntry = CreateFrame("Frame", "EzWoWSpellControlCanvasPanel", UIParent)
    panelFrameEntry.name = "EzWoW - Spell Control"

    local iconTex = panelFrameEntry:CreateTexture(nil, "ARTWORK")
    iconTex:SetSize(32, 32)
    iconTex:SetPoint("TOPLEFT", 18, -18)
    iconTex:SetTexture(ICON_PATH)

    local headingRegion = panelFrameEntry:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    headingRegion:SetPoint("LEFT", iconTex, "RIGHT", 10, 0)
    headingRegion:SetText("EzWoW - Spell Control")
    headingRegion:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B)
    panelFrameEntry.title = headingRegion

    local desc = panelFrameEntry:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    desc:SetPoint("TOPLEFT", iconTex, "BOTTOMLEFT", 0, -14)
    desc:SetWidth(520)
    desc:SetJustifyH("LEFT")
    desc:SetText(self:L("CANVAS_DESC"))
    panelFrameEntry.desc = desc

    local open = CreateFrame("Button", nil, panelFrameEntry, BackdropTemplateMixin and "BackdropTemplate" or nil)
    open:SetSize(220, 28)
    open:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -18)
    ns.UIKit:ApplyBackdrop(open)
    open:SetBackdropColor(0.11, 0.20, 0.22, 0.96)
    open:SetBackdropBorderColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
    open.label = open:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    open.label:SetPoint("CENTER")
    open.label:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B)
    open.label:SetText(self:L("CANVAS_OPEN_BTN"))
    ns.UIKit:FitFontString(open.label, 212, 1)
    open:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.15, 0.26, 0.28, 1)
        self:SetBackdropBorderColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
    end)
    open:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.11, 0.20, 0.22, 0.96)
        self:SetBackdropBorderColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
    end)
    open:SetScript("OnClick", function() ns:ToggleSettingsWindow() end)
    panelFrameEntry.openBtn = open

    local slashInfo = panelFrameEntry:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    slashInfo:SetPoint("TOPLEFT", open, "BOTTOMLEFT", 0, -14)
    slashInfo:SetTextColor(0.655, 0.725, 0.773)
    slashInfo:SetText(self:L("CANVAS_SLASH_INFO"))
    panelFrameEntry.slashInfo = slashInfo

    panelFrameEntry:SetScript("OnShow", function()
        desc:SetText(ns:L("CANVAS_DESC"))
        open.label:SetText(ns:L("CANVAS_OPEN_BTN"))
        ns.UIKit:FitFontString(open.label, 212, 1)
        slashInfo:SetText(ns:L("CANVAS_SLASH_INFO"))
    end)

    if Settings and type(Settings.RegisterCanvasLayoutCategory) == "function" and type(Settings.RegisterAddOnCategory) == "function" then
        local isCallOk, category = pcall(Settings.RegisterCanvasLayoutCategory, panelFrameEntry, panelFrameEntry.name)
        if isCallOk and category then
            pcall(Settings.RegisterAddOnCategory, category)
        end
    elseif type(InterfaceOptions_AddCategory) == "function" then
        pcall(InterfaceOptions_AddCategory, panelFrameEntry)
    end

    self.canvasPanel = panelFrameEntry
end

-----------------------------------------------------------------------------
-- Refresh All Ui
-----------------------------------------------------------------------------
function ns:RefreshAllUI()
    if self.boardFrame then
        self.boardFrame.title:SetText(self:L("BOARD_TITLE"))
        self:LayoutBoardCells()
    end

    if self.canvasPanel then
        self.canvasPanel.desc:SetText(self:L("CANVAS_DESC"))
        self.canvasPanel.openBtn.label:SetText(self:L("CANVAS_OPEN_BTN"))
        ns.UIKit:FitFontString(self.canvasPanel.openBtn.label, 212, 1)
        self.canvasPanel.slashInfo:SetText(self:L("CANVAS_SLASH_INFO"))
    end

    self:RefreshSettingsTexts()
    self:UpdateBoardVisuals()
end

function ns:InitUI()
    self:BuildTacticalUnitBoard()
    self:CreateSettingsWindow()
    self:RegisterBlizzardCanvasLauncher()
    self:RefreshAllUI()
end

SLASH_EZWOWSPELLCONTROL1 = "/ezsc"
SLASH_EZWOWSPELLCONTROL2 = "/spellcontrol"
SLASH_EZWOWSPELLCONTROL3 = "/스펠컨트롤"
SLASH_EZWOWSPELLCONTROL4 = "/ezbc"
SLASH_EZWOWSPELLCONTROL5 = "/버프해제"
SlashCmdList["EZWOWSPELLCONTROL"] = function(msg)
    local cmd = string.lower(strtrim(msg or ""))
    if cmd == "board" or cmd == "toggle" then
        if EzWoW_SpellControlDB then
            EzWoW_SpellControlDB.showBoard = not EzWoW_SpellControlDB.showBoard
            ns:RefreshAllUI()
        end
    elseif cmd == "lock" then
        if EzWoW_SpellControlDB then
            EzWoW_SpellControlDB.lockBoard = not EzWoW_SpellControlDB.lockBoard
            ns:RefreshAllUI()
            DEFAULT_CHAT_FRAME:AddMessage("|cff5CE0B8EzWoW - Spell Control:|r " .. ns:L(EzWoW_SpellControlDB.lockBoard and "MSG_LOCKED" or "MSG_UNLOCKED"))
        end
    elseif cmd == "reset" then
        if InCombatLockdown and InCombatLockdown() then return end
        if EzWoW_SpellControlDB then
            EzWoW_SpellControlDB.boardPoint = nil
            EzWoW_SpellControlDB.manualWidth = nil
            EzWoW_SpellControlDB.manualHeight = nil
            EzWoW_SpellControlDB.sectionOrder = { "buff", "cleanse", "cc" }
        end
        if ns.boardFrame then
            ns.boardFrame:ClearAllPoints()
            ns.boardFrame:SetPoint("CENTER", UIParent, "CENTER", -260, 60)
        end
        ns:RefreshAllUI()
        DEFAULT_CHAT_FRAME:AddMessage("|cff5CE0B8EzWoW - Spell Control:|r " .. ns:L("MSG_POS_RESET"))
    else
        ns:ToggleSettingsWindow()
    end
end

if IsLoggedIn and IsLoggedIn() and ns.InitializeSpellControlEngine then
    ns:InitializeSpellControlEngine()
end
