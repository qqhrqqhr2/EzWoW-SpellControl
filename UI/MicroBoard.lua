--===========================================================================
-- EzWoW - Spell Control
-- UI/MicroBoard.lua : Tactical Micro Unit Board, Secure Slot Buttons & Section Headers
--===========================================================================
local ADDON_NAME, ns = ...

local TacticalUnitBoard = ns.TacticalUnitBoard or {}
ns.TacticalUnitBoard = TacticalUnitBoard

local issecretvalue = _G.issecretvalue or function() return false end

function TacticalUnitBoard.commitFrameBoolAlpha(frame, rawBool, trueAlpha, falseAlpha)
    if not frame then return end
    if issecretvalue(rawBool) then
        if frame.SetAlphaFromBoolean then
            pcall(frame.SetAlphaFromBoolean, frame, rawBool, trueAlpha, falseAlpha)
        else
            frame:SetAlpha(trueAlpha)
        end
    else
        frame:SetAlpha(rawBool and trueAlpha or falseAlpha)
    end
end

function TacticalUnitBoard.determineSlotRange(priRaw, priSec, fbRaw, fbSec)
    if priSec then
        return priRaw, true
    end
    if priRaw ~= nil then
        return priRaw, false
    end
    if fbSec then
        return fbRaw, true
    end
    if fbRaw ~= nil then
        return fbRaw, false
    end
    return true, false
end

local ACCENT_R, ACCENT_G, ACCENT_B = 0.361, 0.878, 0.722 
local STYLE = {
    bgMain     = { 0.071, 0.094, 0.122, 0.97 }, 
    bgSub      = { 0.114, 0.157, 0.192, 0.96 }, 
    bgCell     = { 0.090, 0.125, 0.155, 0.92 },
    border     = { 0.204, 0.298, 0.357, 1.00 }, 
    accent     = { ACCENT_R, ACCENT_G, ACCENT_B, 1.00 },
    textMain   = { 0.929, 0.957, 0.969, 1.00 }, 
    textSub    = { 0.655, 0.725, 0.773, 1.00 }, 
    textMuted  = { 0.388, 0.447, 0.482, 1.00 }, 
    warn       = { 0.906, 0.486, 0.439, 1.00 }, 
    gold       = { 0.950, 0.760, 0.330, 1.00 }, 
}

local DONATE_URL = "https://buymeacoffee.com/qqhrqqhr2"
local MEDIA_PATH = "Interface\\AddOns\\EzWoW-SpellControl\\Media\\"
local ICON_PATH  = MEDIA_PATH .. "Icon"
local DEFAULT_SLOT_ICON = "Interface\\Icons\\Spell_Holy_MagicalSentry"

local MAX_CELLS = 40
local hoverUI = false
local hoverUIActive = false
local hoverExitElapsed = 0
local draggingTitle = false

function TacticalUnitBoard.fitFontStringToWidth(fs, text, maxWidth, baseSize, minSize)
    if not fs then return end
    text = text or ""
    if fs._lastFitText == text and fs._lastFitWidth == maxWidth and fs._lastFitBase == baseSize then
        return
    end
    fs._lastFitText = text
    fs._lastFitWidth = maxWidth
    fs._lastFitBase = baseSize
    fs:SetWordWrap(false)
    local font, _, flags = fs:GetFont()
    if not font then
        fs:SetText(text)
        return
    end
    fs:SetFont(font, baseSize, flags)
    fs:SetText(text)
    local size = baseSize
    local resolveW = fs.GetUnboundedStringWidth or fs.GetStringWidth
    while (resolveW(fs) or 0) > maxWidth and size > minSize do
        size = size - 0.5
        fs:SetFont(font, size, flags)
    end
end

function TacticalUnitBoard.shortenUnitName(name, maxChars)
    if not name or name == "" then return "?" end
    maxChars = maxChars or 4
    local bytes = #name
    local coordPos = 1
    local charCount = 0
    while coordPos <= bytes and charCount < maxChars do
        local themeColor = string.byte(name, coordPos)
        if themeColor >= 240 then
            coordPos = coordPos + 4
        elseif themeColor >= 224 then
            coordPos = coordPos + 3
        elseif themeColor >= 192 then
            coordPos = coordPos + 2
        else
            coordPos = coordPos + 1
        end
        charCount = charCount + 1
    end
    return string.sub(name, 1, coordPos - 1)
end

-----------------------------------------------------------------------------
-- Assemble Cell Tooltip Signature
-----------------------------------------------------------------------------
function TacticalUnitBoard.assembleCellTooltipSignature(cell, unit, state)
    if cell.sectionRole == "CC" then
        local ccSt = ns.ccTargetState or ns:ScanCCTargetState()
        local parts = {
            "ROLE:CC",
            tostring(ccSt.hasEnemyTarget),
            tostring(ccSt.name or ""),
            tostring(ccSt.level or 0),
            tostring(ccSt.isDead),
            tostring(ccSt.creatureTypeKey or ""),
            tostring(cell.boundLClickCC or ""),
            tostring(cell.boundRClickCC or ""),
            tostring(cell.boundCtrlLClickCC or ""),
        }
        if ccSt.ccEntries then
            for _, recordEntry in ipairs(ccSt.ccEntries) do
                parts[#parts + 1] = string.format("%d:%s:%s:%s", recordEntry.slotIndex or 0, tostring(recordEntry.ccDef and recordEntry.ccDef.key or ""), tostring(recordEntry.eligible), tostring(recordEntry.inRange))
            end
        end
        return table.concat(parts, "|")
    end

    local parts = {
        tostring(cell.sectionRole or "BUFF"),
        tostring(unit),
        tostring(state.name or ""),
        tostring(state.level or 0),
        tostring(state.classFile or ""),
        tostring(state.isConnected),
        tostring(state.isDead),
        tostring(state.inRange),
        tostring(state.buffInRange),
        tostring(state.dispelInRange),
        tostring(cell.boundLClickBuff or ""),
        tostring(cell.boundRClickBuff or ""),
        tostring(cell.boundLClickDispel or ""),
        tostring(cell.boundRClickDispel or ""),
    }
    for _, dataEntry in ipairs(state.debuffs) do
        parts[#parts + 1] = string.format("D:%s:%s:%s", tostring(dataEntry.name), tostring(dataEntry.count or 0), tostring(dataEntry.dispelType or ""))
    end
    for _, mbVal in ipairs(state.missingBuffs) do
        parts[#parts + 1] = string.format("B:%s:%s", tostring(mbVal.displaySpell or mbVal.castSpell or ""), tostring(mbVal.isDownranked))
    end
    if state.validChoices then
        for _, chVal in ipairs(state.validChoices) do
            parts[#parts + 1] = string.format("C:%s:%s", tostring(chVal.displaySpell or chVal.castSpell or ""), tostring(chVal.isMissing))
        end
    end
    if state.tooLowBuffs then
        for _, tlVal in ipairs(state.tooLowBuffs) do
            parts[#parts + 1] = string.format("L:%s:%s", tostring(tlVal.buffDef and tlVal.buffDef.key or ""), tostring(tlVal.targetLevel or 0))
        end
    end
    return table.concat(parts, "|")
end

function TacticalUnitBoard.resolveBoundCCButtonOrder(cell, ccDef, fallbackOrder)
    local fullCastName = ccDef and ccDef.fullCastName
    if cell and fullCastName then
        if cell.boundLClickCC == fullCastName then
            return 1
        elseif cell.boundRClickCC == fullCastName then
            return 2
        elseif cell.boundCtrlLClickCC == fullCastName then
            return 3
        end
    end
    return fallbackOrder or 1
end

function TacticalUnitBoard.resolveBoundDispelButtonOrder(cell, debuffInfo)
    local fullCastName = debuffInfo and debuffInfo.cureSpell and debuffInfo.cureSpell.fullCastName
    if cell and fullCastName then
        if cell.boundLClickDispel == fullCastName then
            return 1
        elseif cell.boundRClickDispel == fullCastName then
            return 2
        end
    end
    return 1
end

function TacticalUnitBoard.resolveCCSlotBadgeText(findSequenceMatchIndex)
    if findSequenceMatchIndex == 1 then
        return ns:L("BADGE_CC_L")
    elseif findSequenceMatchIndex == 2 then
        return ns:L("BADGE_CC_R")
    else
        return ns:L("BADGE_CC_CTRL_L")
    end
end

function TacticalUnitBoard.resolveCCSlotActionTipKey(findSequenceMatchIndex)
    if findSequenceMatchIndex == 1 then
        return "TIP_ACTION_LCLICK_CC"
    elseif findSequenceMatchIndex == 2 then
        return "TIP_ACTION_RCLICK_CC"
    else
        return "TIP_ACTION_CTRL_LCLICK_CC"
    end
end

function TacticalUnitBoard.presentCellTooltip(cell, forceRebuild)
    if not cell then return end

    if cell.sectionRole == "CC" then
        local ccSt = ns.ccTargetState or ns:ScanCCTargetState()
        if not ccSt.hasEnemyTarget or ccSt.isDead then
            if GameTooltip and GameTooltip:IsOwned(cell) then
                GameTooltip:Hide()
            end
            return
        end

        local sig = TacticalUnitBoard.assembleCellTooltipSignature(cell, "target", ccSt)
        if not forceRebuild and cell._lastTipSig == sig and GameTooltip:IsOwned(cell) and GameTooltip:IsShown() then
            return
        end
        cell._lastTipSig = sig

        GameTooltip:SetOwner(cell, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()

        local cTypeLabel = ccSt.creatureTypeLocale or ns:L("CTYPE_UNKNOWN")
        if ccSt.rawNameSecret then
            pcall(GameTooltip.AddDoubleLine, GameTooltip,
                ccSt.rawName,
                string.format("|cffE77C70%s|r", ns:L("TIP_ENEMY_TARGET_TAG")),
                0.96, 0.56, 0.36, 0.96, 0.56, 0.36
            )
        else
            local dispTypeInHeader = ccSt.rawCreatureTypeSecret and "" or cTypeLabel
            GameTooltip:AddLine(
                string.format("%s (%s) |cffE77C70%s|r", ccSt.name or "target", string.format(ns:L("TIP_UNIT_LEVEL"), ccSt.level or 0, dispTypeInHeader), ns:L("TIP_ENEMY_TARGET_TAG")),
                0.96, 0.56, 0.36
            )
        end
        if ccSt.rawCreatureTypeSecret then
            local typePrefix = (ns:L("TIP_CREATURE_TYPE"):match("^(.-)%%s") or "대상 종족/유형: ")
            pcall(GameTooltip.AddDoubleLine, GameTooltip,
                typePrefix,
                ccSt.rawCreatureType,
                STYLE.textSub[1], STYLE.textSub[2], STYLE.textSub[3],
                1.00, 0.82, 0.48
            )
        else
            GameTooltip:AddLine(string.format(ns:L("TIP_CREATURE_TYPE"), cTypeLabel), unpack(STYLE.textSub))
        end

        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(ns:L("TIP_CC_USABLE_HEADER"), unpack(STYLE.gold))

        local anyEligible = false
        if ccSt.ccEntries then
            for _, entry in ipairs(ccSt.ccEntries) do
                local btnOrder = TacticalUnitBoard.resolveBoundCCButtonOrder(cell, entry.ccDef, entry.usableOrder or entry.slotIndex)
                local slotBadge = TacticalUnitBoard.resolveCCSlotBadgeText(btnOrder)
                if entry.eligible then
                    anyEligible = true
                    local rangeTag = (not entry.inRange)
                        and (" |cffE77C70(" .. ns:L("TIP_SPELL_OUT_OF_RANGE") .. ")|r")
                        or ""
                    GameTooltip:AddLine(
                        string.format(" • [%s] %s%s", slotBadge, entry.ccDef.name, rangeTag),
                        unpack(STYLE.textMain)
                    )
                else
                    local allowedStr = ns:FormatAllowedTypesText(entry.ccDef)
                    GameTooltip:AddLine(
                        " • " .. string.format(ns:L("TIP_CC_INELIGIBLE_NOTE"), slotBadge, entry.ccDef.name, allowedStr),
                        unpack(STYLE.textMuted)
                    )
                end
            end
        end

        if not anyEligible then
            GameTooltip:AddLine(
                " • " .. string.format(ns:L("TIP_CC_NONE_FOR_TYPE"), cTypeLabel),
                unpack(STYLE.warn)
            )
        else
            GameTooltip:AddLine(" ")
            for _, entry in ipairs(ccSt.ccEntries) do
                if entry.eligible then
                    local btnOrder = TacticalUnitBoard.resolveBoundCCButtonOrder(cell, entry.ccDef, entry.usableOrder or entry.slotIndex)
                    local tipKey = TacticalUnitBoard.resolveCCSlotActionTipKey(btnOrder)
                    GameTooltip:AddLine(
                        string.format(ns:L(tipKey), entry.ccDef.name),
                        ACCENT_R, ACCENT_G, ACCENT_B
                    )
                end
            end
        end

        GameTooltip:Show()
        return
    end

    local unit = cell.unit
    if not unit or not UnitExists(unit) then return end
    local state = ns.unitStates[unit] or ns:ScanUnitState(unit)
    local role = cell.sectionRole or "BUFF"
    local aurasRestricted = ns.IsAuraDataRestricted and ns:IsAuraDataRestricted() or false

    if role == "CLEANSE" and (not state.isConnected or state.isDead or (not aurasRestricted and not state.topDebuff and not state.abolishingDebuff)) then
        if GameTooltip and GameTooltip:IsOwned(cell) then
            GameTooltip:Hide()
        end
        return
    end

    local sig = TacticalUnitBoard.assembleCellTooltipSignature(cell, unit, state)
    if not forceRebuild and cell._lastTipSig == sig and GameTooltip:IsOwned(cell) and GameTooltip:IsShown() then
        return
    end
    cell._lastTipSig = sig

    GameTooltip:SetOwner(cell, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()

    local classColor = (RAID_CLASS_COLORS and state.classFile and RAID_CLASS_COLORS[state.classFile])
        or { r = ACCENT_R, g = ACCENT_G, b = ACCENT_B }
    local targetSuffix = (unit == "target") and (" |cff5CE0B8" .. ns:L("TIP_TARGET_TAG") .. "|r") or ""
    GameTooltip:AddLine(
        string.format("%s (%s)%s", state.name or unit, string.format(ns:L("TIP_UNIT_LEVEL"), state.level or 0, state.classLocale or ""), targetSuffix),
        classColor.r, classColor.g, classColor.b
    )

    local roleInRange = (role == "CLEANSE")
        and ((state.dispelInRange ~= nil) and state.dispelInRange or state.inRange)
        or ((state.buffInRange ~= nil) and state.buffInRange or state.inRange)

    if not state.isConnected then
        GameTooltip:AddLine(ns:L("STATUS_OFFLINE"), unpack(STYLE.textMuted))
    elseif state.isDead then
        GameTooltip:AddLine(ns:L("STATUS_DEAD"), unpack(STYLE.warn))
    else
        if not roleInRange then
            GameTooltip:AddLine(ns:L("STATUS_OUT_OF_RANGE"), unpack(STYLE.warn))
        end

        if role == "CLEANSE" then
            if #state.debuffs > 0 then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(ns:L("TIP_DEBUFF_HEADER"), unpack(STYLE.warn))
                for _, dataEntry in ipairs(state.debuffs) do
                    local dtVal = ns.DEBUFF_TYPES[dataEntry.dispelType]
                    local typeLabel = ns:L("DEBUFF_" .. tostring(dataEntry.dispelType))
                    local stackStr = (dataEntry.count and dataEntry.count > 1) and (" x" .. dataEntry.count) or ""
                    local btnOrder = TacticalUnitBoard.resolveBoundDispelButtonOrder(cell, dataEntry)
                    local btnBadge = (btnOrder == 2)
                        and string.format(ns:L("BADGE_DISPEL_R"), ns:L("SHORT_" .. tostring(dataEntry.dispelType)))
                        or string.format(ns:L("BADGE_DISPEL_L"), ns:L("SHORT_" .. tostring(dataEntry.dispelType)))
                    GameTooltip:AddLine(
                        string.format(" • [%s] %s%s (%s)", btnBadge, dataEntry.name, stackStr, typeLabel),
                        dtVal and dtVal.r or 1, dtVal and dtVal.g or 0.4, dtVal and dtVal.b or 0.4
                    )
                end
                if state.topDebuff and state.cureSpell then
                    GameTooltip:AddLine(
                        string.format(ns:L("TIP_CAST_DISPEL"), state.cureSpell.fullCastName or state.cureSpell.name),
                        ACCENT_R, ACCENT_G, ACCENT_B
                    )
                elseif state.abolishingDebuff then
                    GameTooltip:AddLine(ns:L("TIP_ABOLISH_ACTIVE"), ACCENT_R, ACCENT_G, ACCENT_B)
                end
            end
        else
            
            local choices = state.validChoices or {}
            if #choices > 0 then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(ns:L("TIP_BUFF_LIST_HEADER"), unpack(STYLE.gold))
                local bLVal = ns:L("BADGE_TARGET_BUFF_L")
                local bRVal = ns:L("BADGE_TARGET_BUFF_R")
                for _, chVal in ipairs(choices) do
                    local hasL = (cell.boundLClickBuff and chVal.castSpell == cell.boundLClickBuff)
                    local hasR = (cell.boundRClickBuff and chVal.castSpell == cell.boundRClickBuff)
                    local slotTag = hasL and ("|cffF1BD57[" .. bLVal .. "]|r")
                        or (hasR and ("|cffA7B9C5[" .. bRVal .. "]|r") or " • ")
                    local stateStr = chVal.isMissing
                        and ("|cffF1BD57(" .. ns:L("TIP_BUFF_STATE_MISSING") .. ")|r")
                        or ("|cff5CE0B8(" .. ns:L("TIP_BUFF_STATE_ACTIVE") .. ")|r")
                    GameTooltip:AddLine(
                        string.format(" %s %s %s", slotTag, chVal.displaySpell or chVal.castSpell, stateStr),
                        unpack(STYLE.textMain)
                    )
                    if chVal.isDownranked and chVal.rankObj then
                        GameTooltip:AddLine(
                            string.format("   " .. ns:L("TIP_DOWNRANK_NOTE"), chVal.targetLevel or state.level or 1, chVal.rankObj.minTargetLvl or 1),
                            ACCENT_R, ACCENT_G, ACCENT_B
                        )
                    end
                end
            end

            if #state.missingBuffs == 0 then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(ns:L("STATUS_CLEAN"), ACCENT_R, ACCENT_G, ACCENT_B)
            end

            if state.tooLowBuffs and #state.tooLowBuffs > 0 then
                for _, tlVal in ipairs(state.tooLowBuffs) do
                    GameTooltip:AddLine(
                        string.format(ns:L("TIP_TOO_LOW_FOR_BUFF"), tlVal.targetLevel or 1, tlVal.buffDef.displayName, tlVal.minRankObj.minTargetLvl or 1),
                        unpack(STYLE.textMuted)
                    )
                end
            end
        end
    end

    GameTooltip:AddLine(" ")
    if role == "BUFF" then
        if cell.boundLClickBuff then
            GameTooltip:AddLine(string.format(ns:L("TIP_ACTION_LCLICK_BUFF"), cell.boundLClickBuff), ACCENT_R, ACCENT_G, ACCENT_B)
        end
        if cell.boundRClickBuff then
            GameTooltip:AddLine(string.format(ns:L("TIP_ACTION_RCLICK_BUFF"), cell.boundRClickBuff), unpack(STYLE.textSub))
        end
        if state.validChoices and #state.validChoices > 1 then
            GameTooltip:AddLine(ns:L("TIP_ACTION_CTRL_WHEEL_BUFF"), 0.95, 0.76, 0.33)
        end
        GameTooltip:AddLine(ns:L("TIP_ACTION_ALT_LCLICK_TARGET"), unpack(STYLE.textMuted))
    else
        if cell.boundLClickDispel then
            GameTooltip:AddLine(string.format(ns:L("TIP_ACTION_LCLICK_DISPEL"), cell.boundLClickDispel), ACCENT_R, ACCENT_G, ACCENT_B)
        end
        if cell.boundRClickDispel then
            GameTooltip:AddLine(string.format(ns:L("TIP_ACTION_RCLICK_DISPEL"), cell.boundRClickDispel), unpack(STYLE.textSub))
        end
        GameTooltip:AddLine(ns:L("TIP_ACTION_ALT_LCLICK_TARGET"), unpack(STYLE.textMuted))
    end

    GameTooltip:Show()
end

-----------------------------------------------------------------------------
-- Assign Cell Active Edges
-----------------------------------------------------------------------------
function TacticalUnitBoard.assignCellActiveEdges(cell, show, r, g, b)
    if not cell or not cell.activeEdges then return end
    for _, edge in ipairs(cell.activeEdges) do
        if show then
            edge:SetVertexColor(r or STYLE.gold[1], g or STYLE.gold[2], b or STYLE.gold[3], 1)
            edge:Show()
        else
            edge:Hide()
        end
    end
end

local DEFAULT_SECTION_ORDER = { "buff", "cleanse", "cc" }
local sectionOrder = { "buff", "cleanse", "cc" }
local draggingCategory = nil
local dragBadge = nil

function TacticalUnitBoard.resolveSectionGroupLabel(groupKey)
    if groupKey == "cleanse" then
        return ns:L("GROUP_CLEANSE")
    elseif groupKey == "cc" then
        return ns:L("GROUP_CC")
    else
        return ns:L("GROUP_BUFF")
    end
end

function TacticalUnitBoard.prepareSectionOrder()
    if not EzWoW_SpellControlDB then return sectionOrder end
    local isValid = { buff = true, cleanse = true, cc = true }
    local newOrder, visitedMap = {}, {}
    if type(EzWoW_SpellControlDB.sectionOrder) == "table" then
        for _, entryKey in ipairs(EzWoW_SpellControlDB.sectionOrder) do
            if isValid[entryKey] and not visitedMap[entryKey] then
                newOrder[#newOrder + 1] = entryKey
                visitedMap[entryKey] = true
            end
        end
    end
    for _, entryKey in ipairs(DEFAULT_SECTION_ORDER) do
        if not visitedMap[entryKey] then
            newOrder[#newOrder + 1] = entryKey
            visitedMap[entryKey] = true
        end
    end
    sectionOrder = newOrder
    EzWoW_SpellControlDB.sectionOrder = sectionOrder
    return sectionOrder
end

function ns:ShowHoverUI(show)
    hoverUI = show
    hoverUIActive = show
    hoverExitElapsed = 0
    local unitBoardFrame = self.boardFrame
    if not unitBoardFrame or not EzWoW_SpellControlDB then return end

    local locked = EzWoW_SpellControlDB.lockBoard
    local canClickHeader = show or not locked
    if unitBoardFrame.sectionHeaders then
        for _, headerBar in pairs(unitBoardFrame.sectionHeaders) do
            headerBar:EnableMouse(canClickHeader)
            if headerBar.bg then headerBar.bg:SetAlpha((locked and not show) and 0 or 1) end
            if headerBar.accent then headerBar.accent:SetAlpha((locked and not show) and 0 or 1) end
            if headerBar.grip then headerBar.grip:SetShown(not locked) end
        end
    end

    if unitBoardFrame.foldBtn then unitBoardFrame.foldBtn:SetShown(show) end
    if unitBoardFrame.gearBtn then unitBoardFrame.gearBtn:SetShown(show) end
    if unitBoardFrame.lockBtn then unitBoardFrame.lockBtn:SetShown(show) end
    if unitBoardFrame.resizeGrip then
        unitBoardFrame.resizeGrip:SetShown(show and not locked)
    end
    if unitBoardFrame.titleHover and unitBoardFrame.titleHover.SetBackdropBorderColor then
        unitBoardFrame.titleHover:SetBackdropBorderColor(ACCENT_R, ACCENT_G, ACCENT_B, show and 0.90 or 0)
    end

    if show then
        unitBoardFrame:SetBackdropColor(0.071, 0.094, 0.122, 0.88)
        unitBoardFrame:SetBackdropBorderColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.90)
    else
        unitBoardFrame:SetBackdropColor(0.071, 0.094, 0.122, locked and 0 or 0.93)
        unitBoardFrame:SetBackdropBorderColor(0.204, 0.298, 0.357, locked and 0 or 0.90)
    end
end

function TacticalUnitBoard.persistBoardPosition(unitBoardFrame)
    if not EzWoW_SpellControlDB or not unitBoardFrame then return end
    local point, _, relPoint, coordX, coordY = unitBoardFrame:GetPoint(1)
    EzWoW_SpellControlDB.boardPoint = { point or "CENTER", relPoint or "CENTER", math.floor((coordX or 0) + 0.5), math.floor((coordY or 0) + 0.5) }
end

function TacticalUnitBoard.prepareDragBadge()
    if dragBadge then return dragBadge end
    dragBadge = CreateFrame("Frame", nil, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    dragBadge:SetSize(140, 22)
    dragBadge:SetFrameStrata("TOOLTIP")
    dragBadge:Hide()
    ns.UIKit:ApplyBackdrop(dragBadge)
    dragBadge:SetBackdropColor(0.11, 0.20, 0.22, 0.96)
    dragBadge:SetBackdropBorderColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
    dragBadge.text = dragBadge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    dragBadge.text:SetPoint("CENTER", 0, 0)
    dragBadge.text:SetTextColor(0.929, 0.957, 0.969)
    return dragBadge
end

function TacticalUnitBoard.buildSectionHeaderBar(unitBoardFrame, groupKey)
    local groupHeader = CreateFrame("Button", nil, unitBoardFrame)
    groupHeader:SetHeight(20)
    groupHeader:EnableMouse(hoverUIActive or (EzWoW_SpellControlDB and not EzWoW_SpellControlDB.lockBoard))
    groupHeader:RegisterForClicks("AnyUp")
    groupHeader:RegisterForDrag("LeftButton")
    groupHeader.bg = groupHeader:CreateTexture(nil, "BACKGROUND")
    groupHeader.bg:SetAllPoints()
    groupHeader.bg:SetColorTexture(0.114, 0.157, 0.192, 0.92)
    groupHeader.label = groupHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    groupHeader.label:SetPoint("LEFT", 12, 0)
    groupHeader.label:SetJustifyH("LEFT")
    groupHeader.label:SetTextColor(0.929, 0.957, 0.969)
    groupHeader.grip = groupHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    groupHeader.grip:SetPoint("RIGHT", -8, 0)
    groupHeader.grip:SetText("↕")
    groupHeader.grip:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.85)
    groupHeader.accent = groupHeader:CreateTexture(nil, "ARTWORK")
    groupHeader.accent:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 0.95)
    groupHeader.accent:SetPoint("TOPLEFT", groupHeader, "TOPLEFT", 0, 0)
    groupHeader.accent:SetPoint("BOTTOMLEFT", groupHeader, "BOTTOMLEFT", 0, 0)
    groupHeader.accent:SetWidth(2)
    groupHeader:SetScript("OnClick", function(self)
        if self.justDragged then
            self.justDragged = nil
            return
        end
        if not hoverUIActive and (not EzWoW_SpellControlDB or EzWoW_SpellControlDB.lockBoard) then return end
        if InCombatLockdown and InCombatLockdown() then return end
        EzWoW_SpellControlDB.collapsedGroups = EzWoW_SpellControlDB.collapsedGroups or {}
        EzWoW_SpellControlDB.collapsedGroups[groupKey] = not EzWoW_SpellControlDB.collapsedGroups[groupKey]
        ns:LayoutBoardCells()
        ns:RefreshSettingsTexts()
    end)
    groupHeader:SetScript("OnDragStart", function(self)
        if not EzWoW_SpellControlDB or EzWoW_SpellControlDB.lockBoard or (InCombatLockdown and InCombatLockdown()) then return end
        self.justDragged = true
        draggingCategory = groupKey
        self.bg:SetColorTexture(0.16, 0.25, 0.28, 0.98)
        local badge = TacticalUnitBoard.prepareDragBadge()
        badge.text:SetText("↕  " .. TacticalUnitBoard.resolveSectionGroupLabel(groupKey))
        badge:SetWidth(math.max(110, badge.text:GetStringWidth() + 24))
        badge:Show()
    end)
    groupHeader:SetScript("OnDragStop", function(self)
        if draggingCategory ~= groupKey then return end
        draggingCategory = nil
        if dragBadge then dragBadge:Hide() end
        self.bg:SetColorTexture(0.114, 0.157, 0.192, 0.92)
        ns:LayoutBoardCells()
        ns:RefreshSettingsTexts()
    end)
    groupHeader:SetScript("OnEnter", function(self)
        local hasDragging = (draggingCategory == groupKey)
        self.bg:SetColorTexture(hasDragging and 0.16 or 0.16, hasDragging and 0.25 or 0.22, hasDragging and 0.28 or 0.27, 0.98)
    end)
    groupHeader:SetScript("OnLeave", function(self)
        local hasDragging = (draggingCategory == groupKey)
        self.bg:SetColorTexture(hasDragging and 0.16 or 0.114, hasDragging and 0.25 or 0.157, hasDragging and 0.28 or 0.192, hasDragging and 0.98 or 0.92)
    end)
    return groupHeader
end

local auraContainerLoaded = false
function TacticalUnitBoard.prepareAuraContainerLoaded()
    if auraContainerLoaded then return end
    auraContainerLoaded = true
    if C_AddOns and C_AddOns.LoadAddOn then
        pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
    elseif UIParentLoadAddOn then
        pcall(UIParentLoadAddOn, "Blizzard_AuraContainer")
    end
end

function TacticalUnitBoard.buildSlotVisualHostsOnFrame(parentFrame, anchorTarget)
    anchorTarget = anchorTarget or parentFrame

    local shadeHost = CreateFrame("Frame", nil, parentFrame)
    shadeHost:EnableMouse(false)
    shadeHost:SetAllPoints(anchorTarget)
    shadeHost:SetAlpha(0)
    local shade = shadeHost:CreateTexture(nil, "OVERLAY")
    shade:SetPoint("TOPLEFT", anchorTarget, "TOPLEFT", 2, -2)
    shade:SetPoint("BOTTOMRIGHT", anchorTarget, "BOTTOMRIGHT", -2, 2)
    shade:SetColorTexture(0, 0, 0, 0.55)
    parentFrame.shadeHost = shadeHost
    parentFrame.shade = shade

    local activeEdgeHost = CreateFrame("Frame", nil, parentFrame)
    activeEdgeHost:EnableMouse(false)
    activeEdgeHost:SetAllPoints(anchorTarget)
    activeEdgeHost:SetAlpha(0)
    parentFrame.activeEdgeHost = activeEdgeHost
    parentFrame.activeEdges = {}
    for edge = 1, 4 do
        local resolvedValue = activeEdgeHost:CreateTexture(nil, "OVERLAY")
        resolvedValue:SetTexture("Interface\\Buttons\\WHITE8X8")
        resolvedValue:SetVertexColor(0.95, 0.76, 0.33, 1)
        if edge == 1 then
            resolvedValue:SetPoint("TOPLEFT", anchorTarget, "TOPLEFT", 0, 0)
            resolvedValue:SetPoint("TOPRIGHT", anchorTarget, "TOPRIGHT", 0, 0)
            resolvedValue:SetHeight(2)
        elseif edge == 2 then
            resolvedValue:SetPoint("BOTTOMLEFT", anchorTarget, "BOTTOMLEFT", 0, 0)
            resolvedValue:SetPoint("BOTTOMRIGHT", anchorTarget, "BOTTOMRIGHT", 0, 0)
            resolvedValue:SetHeight(2)
        elseif edge == 3 then
            resolvedValue:SetPoint("TOPLEFT", anchorTarget, "TOPLEFT", 0, 0)
            resolvedValue:SetPoint("BOTTOMLEFT", anchorTarget, "BOTTOMLEFT", 0, 0)
            resolvedValue:SetWidth(2)
        else
            resolvedValue:SetPoint("TOPRIGHT", anchorTarget, "TOPRIGHT", 0, 0)
            resolvedValue:SetPoint("BOTTOMRIGHT", anchorTarget, "BOTTOMRIGHT", 0, 0)
            resolvedValue:SetWidth(2)
        end
        resolvedValue:Hide()
        parentFrame.activeEdges[edge] = resolvedValue
    end

    parentFrame.nameText = parentFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    parentFrame.nameText:SetPoint("TOPLEFT", anchorTarget, "TOPLEFT", 2, -5)
    parentFrame.nameText:SetPoint("TOPRIGHT", anchorTarget, "TOPRIGHT", -2, -5)
    parentFrame.nameText:SetJustifyH("CENTER")
    parentFrame.nameText:SetDrawLayer("OVERLAY", 5)

    local inRangeBadgeHost = CreateFrame("Frame", nil, parentFrame)
    inRangeBadgeHost:EnableMouse(false)
    inRangeBadgeHost:SetAllPoints(anchorTarget)
    inRangeBadgeHost:SetAlpha(1)
    parentFrame.inRangeBadgeHost = inRangeBadgeHost
    parentFrame.badgeText = inRangeBadgeHost:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    parentFrame.badgeText:SetPoint("BOTTOMLEFT", anchorTarget, "BOTTOMLEFT", 1, 2)
    parentFrame.badgeText:SetPoint("BOTTOMRIGHT", anchorTarget, "BOTTOMRIGHT", -1, 2)
    parentFrame.badgeText:SetJustifyH("CENTER")
    parentFrame.badgeText:SetDrawLayer("OVERLAY", 6)

    local oorBadgeHost = CreateFrame("Frame", nil, parentFrame)
    oorBadgeHost:EnableMouse(false)
    oorBadgeHost:SetAllPoints(anchorTarget)
    oorBadgeHost:SetAlpha(0)
    parentFrame.oorBadgeHost = oorBadgeHost
    parentFrame.oorBadgeText = oorBadgeHost:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    parentFrame.oorBadgeText:SetPoint("BOTTOMLEFT", anchorTarget, "BOTTOMLEFT", 1, 2)
    parentFrame.oorBadgeText:SetPoint("BOTTOMRIGHT", anchorTarget, "BOTTOMRIGHT", -1, 2)
    parentFrame.oorBadgeText:SetJustifyH("CENTER")
    parentFrame.oorBadgeText:SetDrawLayer("OVERLAY", 6)
end

local CLEANSE_SLOT_TYPES = { "Poison", "Disease", "Curse", "Magic" }

function TacticalUnitBoard.safeUnitStr(val)
    if val == nil or issecretvalue(val) then return nil end
    return val
end

function ns:ConfigureCleanseCellAuraContainer(cell, unit)
    if not cell or not unit then return end
    if InCombatLockdown and InCombatLockdown() then return end

    if not self.dsCurve and self.UpdateDispelColorCurve then
        self:UpdateDispelColorCurve()
    end

    local state = self.unitStates and self.unitStates[unit]
    local rawName = UnitName and select(1, pcall(UnitName, unit)) and UnitName(unit) or nil
    local uName = TacticalUnitBoard.safeUnitStr(rawName) or (state and state.name) or unit
    local shortName = (unit == "target")
        and ("▶" .. TacticalUnitBoard.shortenUnitName(uName, 3))
        or TacticalUnitBoard.shortenUnitName(uName, 4)

    local classFile = (state and state.classFile) or nil
    if not classFile and UnitClass then
        local okC, _, cFile = pcall(UnitClass, unit)
        if okC then classFile = TacticalUnitBoard.safeUnitStr(cFile) end
    end
    classFile = classFile or "PRIEST"
    local classColor = (RAID_CLASS_COLORS and classFile and RAID_CLASS_COLORS[classFile])
        or { r = ACCENT_R, g = ACCENT_G, b = ACCENT_B }

    local size = (EzWoW_SpellControlDB and EzWoW_SpellControlDB.cellSize) or 36
    local filtersByType = {}
    local badgeByType = {}
    local filterParts = { tostring(unit) }
    local visualParts = { tostring(shortName), tostring(classFile), tostring(size) }

    for _, dType in ipairs(CLEANSE_SLOT_TYPES) do
        local cureEntry = self.activeDispelTypes and self.activeDispelTypes[dType]
        if cureEntry then
            filtersByType[dType] = {
                includeDispelTypes = { [dType] = true },
                excludeSpellIDs = {},
            }
            local hasRightClick = (cureEntry.buttonSlot == 2)
            local badgeFmt = hasRightClick and self:L("BADGE_DISPEL_R") or self:L("BADGE_DISPEL_L")
            badgeByType[dType] = string.format(badgeFmt, self:L("SHORT_" .. dType))
            filterParts[#filterParts + 1] = dType .. ":1"
        else
            filtersByType[dType] = {
                includeDispelTypes = {},
                excludeSpellIDs = {},
            }
            badgeByType[dType] = ""
            filterParts[#filterParts + 1] = dType .. ":0"
        end
        visualParts[#visualParts + 1] = dType .. "=" .. badgeByType[dType]
    end

    local visualSig = table.concat(visualParts, "|")
    local filterSig = table.concat(filterParts, "|")
    local restricted = self.IsAuraDataRestricted and self:IsAuraDataRestricted() or false

    if not cell.auraContainer or (cell._ezscVisualSig ~= visualSig and not restricted) then
        if cell.auraContainer then
            pcall(cell.auraContainer.SetEnabled, cell.auraContainer, false)
            pcall(cell.auraContainer.SetShown, cell.auraContainer, false)
            cell.auraContainer:ClearAllPoints()
            cell.auraContainer = nil
        end

        TacticalUnitBoard.prepareAuraContainerLoaded()
        local okAC, acVal = pcall(CreateFrame, "AuraContainer", nil, cell, "CustomAuraContainerTemplate")
        if not okAC or not acVal or type(acVal.AddAuraSlot) ~= "function" then
            return
        end
        acVal:EnableMouse(false)
        acVal:SetAllPoints(cell)

        local preserveStyle = (Enum and Enum.CustomAuraButtonDispelTypeTextureStyle and Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset) or 0

        for entryIndex, dType in ipairs(CLEANSE_SLOT_TYPES) do
            local slotKey = "EZBC_DISPEL_" .. dType
            local dtVal = ns.DEBUFF_TYPES[dType] or { r = 0.24, g = 0.82, b = 0.42 }
            local slotBadge = badgeByType[dType] or ""
            local cureEntry = self.activeDispelTypes and self.activeDispelTypes[dType]
            local hasPrimarySlot = cureEntry and (cureEntry.buttonSlot == 1)
            local slotLevelOffset = (hasPrimarySlot and 10 or 2) + (5 - entryIndex)
            local slotFilter = filtersByType[dType] or { includeDispelTypes = {} }

            pcall(
                acVal.AddAuraSlot,
                acVal,
                slotKey,
                "HARMFUL",
                {
                    sortMethod = 0,
                    sortDirection = 0,
                    candidateFilters = slotFilter,
                    initializeFrame = function(ab)
                        ab:EnableMouse(false)
                        ab:ClearAllPoints()
                        ab:SetPoint("CENTER", cell, "CENTER", 0, 0)
                        ab:SetSize(size, size)
                        ab:SetFrameLevel(cell:GetFrameLevel() + slotLevelOffset)

                        local border = ab:CreateTexture(nil, "BACKGROUND")
                        border:ClearAllPoints()
                        border:SetAllPoints(ab)
                        border:SetColorTexture(1, 1, 1, 1)
                        border:Show()

                        if ab.ClearDispelTypeTextures and ab.AddDispelTypeTexture and ns.dsCurve then
                            ab:ClearDispelTypeTextures()
                            ab:AddDispelTypeTexture(border, {
                                showIcon = false,
                                showWhenHarmful = true,
                                showWhenHelpful = false,
                                showWithoutDispelType = false,
                                style = preserveStyle,
                                customDispelColorCurve = ns.dsCurve,
                            })
                        else
                            border:SetColorTexture(dtVal.r, dtVal.g, dtVal.b, 1)
                        end

                        local bg = ab:CreateTexture(nil, "BORDER")
                        bg:SetPoint("TOPLEFT", ab, "TOPLEFT", 2, -2)
                        bg:SetPoint("BOTTOMRIGHT", ab, "BOTTOMRIGHT", -2, 2)
                        bg:SetColorTexture(0.06, 0.09, 0.12, 0.90)

                        local icon = ab:CreateTexture(nil, "ARTWORK")
                        icon:SetPoint("TOPLEFT", ab, "TOPLEFT", 2, -2)
                        icon:SetPoint("BOTTOMRIGHT", ab, "BOTTOMRIGHT", -2, 2)
                        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                        if ab.SetIcon then
                            ab:SetIcon(icon)
                        end

                        local classBar = ab:CreateTexture(nil, "OVERLAY")
                        classBar:SetPoint("TOPLEFT", ab, "TOPLEFT", 2, -2)
                        classBar:SetPoint("TOPRIGHT", ab, "TOPRIGHT", -2, -2)
                        classBar:SetHeight(3)
                        classBar:SetColorTexture(classColor.r, classColor.g, classColor.b, 1)

                        local nameText = ab:CreateFontString(nil, "OVERLAY")
                        nameText:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE")
                        nameText:SetPoint("TOPLEFT", ab, "TOPLEFT", 1, -5)
                        nameText:SetPoint("TOPRIGHT", ab, "TOPRIGHT", -1, -5)
                        nameText:SetJustifyH("CENTER")
                        nameText:SetWordWrap(false)
                        nameText:SetTextColor(unpack(STYLE.textMain))
                        nameText:SetText(shortName)

                        local badgeText = ab:CreateFontString(nil, "OVERLAY")
                        badgeText:SetFont(STANDARD_TEXT_FONT, 8, "OUTLINE")
                        badgeText:SetPoint("BOTTOMLEFT", ab, "BOTTOMLEFT", 1, 2)
                        badgeText:SetPoint("BOTTOMRIGHT", ab, "BOTTOMRIGHT", -1, 2)
                        badgeText:SetJustifyH("CENTER")
                        badgeText:SetWordWrap(false)
                        badgeText:SetTextColor(1, 0.95, 0.85)
                        badgeText:SetText(slotBadge)
                    end,
                }
            )
        end

        pcall(acVal.SetUnit, acVal, unit)
        pcall(acVal.SetShown, acVal, true)
        pcall(acVal.SetEnabled, acVal, true)

        cell.auraContainer = acVal
        cell.auraContainerConfiguredUnit = unit
        cell._ezscVisualSig = visualSig
        cell._ezscFilterSig = filterSig
        return
    end

    if cell._ezscFilterSig ~= filterSig then
        local acVal = cell.auraContainer
        if acVal.SetAuraSlotCandidateFilters then
            for _, dType in ipairs(CLEANSE_SLOT_TYPES) do
                local slotKey = "EZBC_DISPEL_" .. dType
                pcall(acVal.SetAuraSlotCandidateFilters, acVal, slotKey, filtersByType[dType] or { includeDispelTypes = {} })
            end
        end
        if acVal.SetUnit then
            pcall(acVal.SetUnit, acVal, unit)
        end
        if acVal.SetShown then
            pcall(acVal.SetShown, acVal, true)
        end
        if acVal.SetEnabled then
            pcall(acVal.SetEnabled, acVal, true)
        end
        cell.auraContainerConfiguredUnit = unit
        cell._ezscFilterSig = filterSig
    end
end

function TacticalUnitBoard.buildSecureSlotButton(unitBoardFrame, frameName, sectionRole)
    local b = CreateFrame("Button", frameName, unitBoardFrame, "SecureUnitButtonTemplate")
    b:SetSize(36, 36)
    b:RegisterForClicks("AnyUp")
    b:EnableMouseWheel(true)
    b.sectionRole = sectionRole

    b.border = b:CreateTexture(nil, "BACKGROUND")
    b.border:SetAllPoints()
    b.border:SetTexture("Interface\\Buttons\\WHITE8X8")
    b.border:SetVertexColor(0.17, 0.22, 0.26, 0.90)
    b.border:SetDrawLayer("BACKGROUND", 0)

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 2, -2)
    b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.icon:SetTexture(DEFAULT_SLOT_ICON)

    b.innerBg = b:CreateTexture(nil, "ARTWORK")
    b.innerBg:SetPoint("TOPLEFT", 2, -2)
    b.innerBg:SetPoint("BOTTOMRIGHT", -2, 2)
    b.innerBg:SetColorTexture(0.06, 0.09, 0.12, 0.55)

    b.classBar = b:CreateTexture(nil, "OVERLAY")
    b.classBar:SetPoint("TOPLEFT", 2, -2)
    b.classBar:SetPoint("TOPRIGHT", -2, -2)
    b.classBar:SetHeight(3)
    b.classBar:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 1)

    TacticalUnitBoard.buildSlotVisualHostsOnFrame(b, b)

    local glow = b:CreateTexture(nil, "HIGHLIGHT")
    glow:SetAllPoints(b.icon)
    glow:SetColorTexture(1, 0.86, 0.52, 0.16)
    b.glow = glow

    local pushed = b:CreateTexture(nil, "OVERLAY")
    pushed:SetAllPoints(b.icon)
    pushed:SetColorTexture(0, 0, 0, 0.30)
    if b.SetPushedTexture then b:SetPushedTexture(pushed) else pushed:Hide() end
    b.pushed = pushed

    b:SetScript("OnMouseWheel", function(self, delta)
        if not IsControlKeyDown() then return end
        if self.sectionRole == "BUFF" and self.unit then
            if ns:CycleUnitLeftClickBuff(self.unit, delta) then
                TacticalUnitBoard.presentCellTooltip(self, true)
            end
        end
    end)

    b:SetScript("PostClick", function(self)
        local unit = self.unit
        local role = self.sectionRole
        local function syncAfterClick()
            if role == "CC" then
                ns:ScanCCTargetState()
                if not (InCombatLockdown and InCombatLockdown()) then
                    ns:ApplyCCTargetCellSecureAttributes(self)
                end
                ns:UpdateCCTargetCellVisual()
            elseif unit and UnitExists(unit) then
                ns:ScanUnitState(unit)
                ns:UpdateSingleUnitCell(unit)
            end
            if self._isHovered and self:IsMouseOver() then
                TacticalUnitBoard.presentCellTooltip(self, true)
            end
        end
        if C_Timer and C_Timer.After then
            C_Timer.After(0.05, syncAfterClick)
            C_Timer.After(0.20, syncAfterClick)
        else
            syncAfterClick()
        end
    end)

    b:SetScript("OnEnter", function(self)
        self._isHovered = true
        if self.sectionRole == "CC" then
            ns:ScanCCTargetState()
            if not (InCombatLockdown and InCombatLockdown()) then
                ns:ApplyCCTargetCellSecureAttributes(self)
            end
            ns:UpdateCCTargetCellVisual()
        elseif self.unit and not (InCombatLockdown and InCombatLockdown()) then
            local stateEntry = ns:ScanUnitState(self.unit)
            if self.sectionRole == "CLEANSE" then
                ns:ApplyCleanseCellSecureAttributes(self, self.unit, stateEntry)
            else
                ns:ApplyBuffCellSecureAttributes(self, self.unit, stateEntry)
            end
            ns:UpdateSingleUnitCellVisualOnly(self)
        end
        TacticalUnitBoard.presentCellTooltip(self, true)
    end)
    b:SetScript("OnLeave", function(self)
        self._isHovered = false
        self._lastTipSig = nil
        if GameTooltip and GameTooltip:IsOwned(self) then
            GameTooltip:Hide()
        end
    end)

    b:Hide()
    return b
end

function ns:BuildTacticalUnitBoard()
    if self.boardFrame then return self.boardFrame end

    local unitBoardFrame = CreateFrame("Frame", "EzWoWSpellControlBoard", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    unitBoardFrame:SetSize(216, 84)
    unitBoardFrame:SetClampedToScreen(true)
    unitBoardFrame:SetMovable(true)
    unitBoardFrame:EnableMouse(false)
    ns.UIKit:ApplyBackdrop(unitBoardFrame, 1, 1)
    unitBoardFrame:SetBackdropBorderColor(0.204, 0.298, 0.357, 0.90)
    unitBoardFrame:SetBackdropColor(0.071, 0.094, 0.122, 0.93)

    if EzWoW_SpellControlDB and EzWoW_SpellControlDB.boardPoint then
        local anchorTargetEntry = EzWoW_SpellControlDB.boardPoint
        unitBoardFrame:ClearAllPoints()
        unitBoardFrame:SetPoint(anchorTargetEntry[1] or "CENTER", UIParent, anchorTargetEntry[2] or "CENTER", anchorTargetEntry[3] or -260, anchorTargetEntry[4] or 60)
    else
        unitBoardFrame:SetPoint("CENTER", UIParent, "CENTER", -260, 60)
    end

    local titleStr = unitBoardFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    titleStr:SetPoint("TOPLEFT", 12, -8)
    titleStr:SetDrawLayer("OVERLAY", 2)
    titleStr:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B)
    titleStr:SetText(self:L("BOARD_TITLE"))
    unitBoardFrame.title = titleStr

    local titleHover = CreateFrame("Frame", nil, unitBoardFrame, BackdropTemplateMixin and "BackdropTemplate" or nil)
    titleHover:SetPoint("TOPLEFT", unitBoardFrame, "TOPLEFT", 5, -3)
    titleHover:SetPoint("TOPRIGHT", unitBoardFrame, "TOPRIGHT", -80, -3)
    titleHover:SetHeight(23)
    titleHover:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    titleHover:SetBackdropBorderColor(ACCENT_R, ACCENT_G, ACCENT_B, 0)
    titleHover:EnableMouse(true)
    titleHover:RegisterForDrag("LeftButton")
    titleHover:SetScript("OnDragStart", function()
        if InCombatLockdown and InCombatLockdown() then return end
        if not IsControlKeyDown() and (EzWoW_SpellControlDB and EzWoW_SpellControlDB.lockBoard) then return end
        draggingTitle = true
        unitBoardFrame:StartMoving()
    end)
    titleHover:SetScript("OnDragStop", function()
        if not draggingTitle then return end
        draggingTitle = false
        unitBoardFrame:StopMovingOrSizing()
        TacticalUnitBoard.persistBoardPosition(unitBoardFrame)
    end)
    titleHover:SetScript("OnEnter", function(self)
        ns:ShowHoverUI(true)
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:SetText(ns:L("ADDON_TITLE"), ACCENT_R, ACCENT_G, ACCENT_B)
        GameTooltip:AddLine(ns:L("TITLE_HELP_1"), 0.929, 0.957, 0.969, true)
        GameTooltip:AddLine(ns:L("TITLE_HELP_2"), 0.655, 0.725, 0.773, true)
        GameTooltip:AddLine(ns:L("TITLE_HELP_3"), 0.655, 0.725, 0.773, true)
        GameTooltip:Show()
    end)
    titleHover:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    unitBoardFrame.titleHover = titleHover

    local function buildToolbarControl(name, iconName, offset, tipKey, onClick)
        local b = CreateFrame("Button", name, unitBoardFrame, BackdropTemplateMixin and "BackdropTemplate" or nil)
        b:SetSize(23, 23)
        b:SetPoint("TOPRIGHT", unitBoardFrame, "TOPRIGHT", offset, -3)
        ns.UIKit:ApplyBackdrop(b)
        b:SetBackdropColor(0.114, 0.157, 0.192, 0.92)
        b:SetBackdropBorderColor(0.204, 0.298, 0.357, 0.95)

        local icon = b:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", 3, -3)
        icon:SetPoint("BOTTOMRIGHT", -3, 3)
        icon:SetTexture(MEDIA_PATH .. iconName .. ".tga")
        b.icon = icon

        b:SetScript("OnEnter", function(self)
            self:SetBackdropColor(0.16, 0.24, 0.26, 0.98)
            self:SetBackdropBorderColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(ns:L("ADDON_TITLE"), ACCENT_R, ACCENT_G, ACCENT_B)
            GameTooltip:AddLine(ns:L(tipKey), 0.929, 0.957, 0.969, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function(self)
            self:SetBackdropColor(0.114, 0.157, 0.192, 0.92)
            self:SetBackdropBorderColor(0.204, 0.298, 0.357, 0.95)
            GameTooltip:Hide()
        end)
        b:SetScript("OnClick", onClick)
        b:Hide()
        return b
    end

    unitBoardFrame.foldBtn = buildToolbarControl("EzBCFoldButton", "fold", -57, "FOLD_TIP", function()
        if not EzWoW_SpellControlDB or (InCombatLockdown and InCombatLockdown()) then return end
        EzWoW_SpellControlDB.collapsedGroups = EzWoW_SpellControlDB.collapsedGroups or {}
        local collapsedGroups = EzWoW_SpellControlDB.collapsedGroups
        local allCollapsed = collapsedGroups.buff and collapsedGroups.cleanse and collapsedGroups.cc
        local nextState = not allCollapsed
        collapsedGroups.buff = nextState
        collapsedGroups.cleanse = nextState
        collapsedGroups.cc = nextState
        EzWoW_SpellControlDB.collapsed = nextState
        ns:LayoutBoardCells()
        ns:RefreshSettingsTexts()
    end)

    unitBoardFrame.lockBtn = buildToolbarControl("EzBCLockButton", "unlock", -32, "LOCK_TIP", function()
        if not EzWoW_SpellControlDB or (InCombatLockdown and InCombatLockdown()) then return end
        EzWoW_SpellControlDB.lockBoard = not EzWoW_SpellControlDB.lockBoard
        ns:LayoutBoardCells()
        ns:RefreshSettingsTexts()
    end)

    unitBoardFrame.gearBtn = buildToolbarControl("EzBCSettingsButton", "gear", -6, "GEAR_TIP", function()
        ns:ToggleSettingsWindow()
    end)

    local resize = CreateFrame("Button", "EzWoWSpellControlResizeHandle", unitBoardFrame)
    resize:SetSize(19, 19)
    resize:SetPoint("BOTTOMRIGHT", unitBoardFrame, "BOTTOMRIGHT", -1, 1)
    resize:SetFrameLevel(unitBoardFrame:GetFrameLevel() + 10)
    local resizeIcon = resize:CreateTexture(nil, "ARTWORK")
    resizeIcon:SetAllPoints()
    resizeIcon:SetTexture(MEDIA_PATH .. "resize.tga")
    unitBoardFrame:SetResizable(true)
    if unitBoardFrame.SetResizeBounds then
        unitBoardFrame:SetResizeBounds(165, 52, 900, 900)
    elseif unitBoardFrame.SetMinResize then
        unitBoardFrame:SetMinResize(165, 52)
        unitBoardFrame:SetMaxResize(900, 900)
    end
    resize:RegisterForDrag("LeftButton")
    resize:SetScript("OnDragStart", function()
        if EzWoW_SpellControlDB and not EzWoW_SpellControlDB.lockBoard and not (InCombatLockdown and InCombatLockdown()) then
            unitBoardFrame:StartSizing("BOTTOMRIGHT")
        end
    end)
    resize:SetScript("OnDragStop", function()
        unitBoardFrame:StopMovingOrSizing()
        if not EzWoW_SpellControlDB then return end
        local size = EzWoW_SpellControlDB.cellSize or 36
        EzWoW_SpellControlDB.manualWidth = math.floor(unitBoardFrame:GetWidth() + 0.5)
        EzWoW_SpellControlDB.manualHeight = math.floor(unitBoardFrame:GetHeight() + 0.5)
        EzWoW_SpellControlDB.columns = math.max(1, math.min(10, math.floor((EzWoW_SpellControlDB.manualWidth - 16) / (size + 4))))
        TacticalUnitBoard.persistBoardPosition(unitBoardFrame)
        ns:LayoutBoardCells()
        ns:RefreshSettingsTexts()
    end)
    resize:Hide()
    unitBoardFrame.resizeGrip = resize

    unitBoardFrame.buffHeader = TacticalUnitBoard.buildSectionHeaderBar(unitBoardFrame, "buff")
    unitBoardFrame.cleanseHeader = TacticalUnitBoard.buildSectionHeaderBar(unitBoardFrame, "cleanse")
    unitBoardFrame.ccGroupHeader = TacticalUnitBoard.buildSectionHeaderBar(unitBoardFrame, "cc")
    unitBoardFrame.sectionHeaders = {
        buff = unitBoardFrame.buffHeader,
        cleanse = unitBoardFrame.cleanseHeader,
        cc = unitBoardFrame.ccGroupHeader,
    }
    unitBoardFrame.groupHeader = unitBoardFrame.buffHeader

    unitBoardFrame.buffCells = {}
    unitBoardFrame.cleanseCells = {}
    for index = 1, MAX_CELLS do
        unitBoardFrame.buffCells[index] = TacticalUnitBoard.buildSecureSlotButton(unitBoardFrame, "EzWoWSpellControlCell" .. index, "BUFF")
        unitBoardFrame.cleanseCells[index] = TacticalUnitBoard.buildSecureSlotButton(unitBoardFrame, "EzWoWCleanseSlotCell" .. index, "CLEANSE")
    end
    unitBoardFrame.cells = unitBoardFrame.buffCells
    unitBoardFrame.ccTargetCell = TacticalUnitBoard.buildSecureSlotButton(unitBoardFrame, "EzWoWCCTargetSlotCell", "CC")

    unitBoardFrame:HookScript("OnUpdate", function(_, elapsed)
        elapsed = elapsed or 0
        if hoverUI then
            if draggingTitle or draggingCategory or unitBoardFrame:IsMouseOver() or (unitBoardFrame.resizeGrip and unitBoardFrame.resizeGrip:IsMouseOver()) then
                hoverExitElapsed = 0
            else
                hoverExitElapsed = hoverExitElapsed + elapsed
                if hoverExitElapsed >= 0.15 then
                    ns:ShowHoverUI(false)
                end
            end
        end

        if draggingCategory and not (InCombatLockdown and InCombatLockdown()) then
            local rawX, rawY = GetCursorPosition()
            local boardScale = unitBoardFrame:GetEffectiveScale() or 1
            local cxVal, cyVal = rawX / boardScale, rawY / boardScale
            if dragBadge and dragBadge:IsShown() then
                local badgeScale = dragBadge:GetEffectiveScale() or 1
                dragBadge:ClearAllPoints()
                dragBadge:SetPoint("CENTER", UIParent, "BOTTOMLEFT", rawX / badgeScale, rawY / badgeScale + 16)
            end
            TacticalUnitBoard.prepareSectionOrder()
            for entryIndex, entryKey in ipairs(sectionOrder) do
                local headerBar = unitBoardFrame.sectionHeaders and unitBoardFrame.sectionHeaders[entryKey]
                if headerBar and headerBar:IsShown() and entryKey ~= draggingCategory then
                    local top, bottom = headerBar:GetTop(), headerBar:GetBottom()
                    if top and bottom and cyVal <= top + 6 and cyVal >= bottom - 6 then
                        local fromIdx
                        for index, lookupKey in ipairs(sectionOrder) do
                            if lookupKey == draggingCategory then
                                fromIdx = index
                                break
                            end
                        end
                        if fromIdx and fromIdx ~= entryIndex then
                            table.remove(sectionOrder, fromIdx)
                            table.insert(sectionOrder, entryIndex, draggingCategory)
                            EzWoW_SpellControlDB.sectionOrder = sectionOrder
                            ns:LayoutBoardCells()
                        end
                        break
                    end
                end
            end
        end

        if not EzWoW_SpellControlDB then return end
        local targetAlpha = EzWoW_SpellControlDB.opacity or 1
        if EzWoW_SpellControlDB.fade and not (hoverUI or draggingTitle or draggingCategory or unitBoardFrame:IsMouseOver() or (ns.settingsFrame and ns.settingsFrame:IsShown())) then
            targetAlpha = 0
        end
        local alpha = unitBoardFrame:GetAlpha()
        if math.abs(alpha - targetAlpha) > 0.005 then
            local step = elapsed * 5
            if alpha < targetAlpha then
                alpha = math.min(targetAlpha, alpha + step)
            else
                alpha = math.max(targetAlpha, alpha - step)
            end
            unitBoardFrame:SetAlpha(alpha)
        end
    end)

    self.boardFrame = unitBoardFrame
    self:LayoutBoardCells()
    return unitBoardFrame
end

function ns:LayoutBoardCells()
    local unitBoardFrame = self.boardFrame
    if not unitBoardFrame or not EzWoW_SpellControlDB then return end
    if InCombatLockdown and InCombatLockdown() then
        self.pendingSecureUpdate = true
        return
    end

    EzWoW_SpellControlDB.collapsedGroups = EzWoW_SpellControlDB.collapsedGroups or {
        buff = false,
        cleanse = false,
        cc = false,
    }
    local collapsedGroups = EzWoW_SpellControlDB.collapsedGroups

    local size = EzWoW_SpellControlDB.cellSize or 36
    local cols = math.max(1, EzWoW_SpellControlDB.columns or 5)
    local numUnits = #self.activeUnits
    local frameWidth = math.max(165, EzWoW_SpellControlDB.manualWidth or (16 + cols * (size + 4)))
    cols = math.max(1, math.floor((frameWidth - 16) / (size + 4)))

    local coordY = 32
    local containsBuffSection = (#self.learnedBuffDefs > 0) or (#self.learnedDispelList == 0)
    local containsCleanseSection = (#self.learnedDispelList > 0)
    local containsCCSection = (EzWoW_SpellControlDB.showCC ~= false) and (#self.learnedCCDefs > 0)
    local locked = EzWoW_SpellControlDB.lockBoard

    local function layoutUnitCellArray(cellArray, showCells)
        for index = 1, MAX_CELLS do
            local cell = cellArray[index]
            local unit = showCells and self.activeUnits[index] or nil
            if unit then
                local rowWidget = math.floor((index - 1) / cols)
                local columnIndex = (index - 1) % cols
                cell:ClearAllPoints()
                cell:SetSize(size, size)
                cell:SetPoint("TOPLEFT", unitBoardFrame, "TOPLEFT", 8 + columnIndex * (size + 4), -coordY - rowWidget * (size + 4))
                cell.unit = unit
                cell._appliedAttrs = cell._appliedAttrs or {}
                if cell._appliedAttrs.unit ~= unit then
                    cell._appliedAttrs.unit = unit
                    cell:SetAttribute("unit", unit)
                end
                if cell.sectionRole == "CLEANSE" then
                    self:ConfigureCleanseCellAuraContainer(cell, unit)
                end
                cell:Show()
            else
                if cell._isHovered or (GameTooltip and GameTooltip:IsOwned(cell)) then
                    GameTooltip:Hide()
                end
                cell._isHovered = false
                cell._lastTipSig = nil
                cell.unit = nil
                cell:Hide()
            end
        end
        if showCells and numUnits > 0 then
            coordY = coordY + math.ceil(numUnits / cols) * (size + 4) + 5
        end
    end

    local function configureHeaderBar(groupHeader, collapsed, titleText, countNum)
        groupHeader:ClearAllPoints()
        groupHeader:SetPoint("TOPLEFT", unitBoardFrame, "TOPLEFT", 8, -coordY)
        groupHeader:SetWidth(frameWidth - 16)
        groupHeader.label:SetText((collapsed and ">  " or "v  ") .. titleText .. "  |  " .. countNum)
        groupHeader.bg:SetAlpha((locked and not hoverUI) and 0 or 1)
        groupHeader.accent:SetAlpha((locked and not hoverUI) and 0 or 1)
        if groupHeader.grip then groupHeader.grip:SetShown(not locked) end
        groupHeader:Show()
        coordY = coordY + 25
    end

    TacticalUnitBoard.prepareSectionOrder()
    for _, secKey in ipairs(sectionOrder) do
        if secKey == "buff" then
            if containsBuffSection then
                local buffCollapsed = collapsedGroups.buff and true or false
                configureHeaderBar(unitBoardFrame.buffHeader, buffCollapsed, self:L("GROUP_BUFF"), numUnits)
                layoutUnitCellArray(unitBoardFrame.buffCells, not buffCollapsed)
            else
                unitBoardFrame.buffHeader:Hide()
                layoutUnitCellArray(unitBoardFrame.buffCells, false)
            end
        elseif secKey == "cleanse" then
            if containsCleanseSection then
                local cleanseCollapsed = collapsedGroups.cleanse and true or false
                configureHeaderBar(unitBoardFrame.cleanseHeader, cleanseCollapsed, self:L("GROUP_CLEANSE"), numUnits)
                layoutUnitCellArray(unitBoardFrame.cleanseCells, not cleanseCollapsed)
            else
                unitBoardFrame.cleanseHeader:Hide()
                layoutUnitCellArray(unitBoardFrame.cleanseCells, false)
            end
        elseif secKey == "cc" then
            local ccCell = unitBoardFrame.ccTargetCell
            if containsCCSection then
                local ccCollapsed = collapsedGroups.cc and true or false
                configureHeaderBar(unitBoardFrame.ccGroupHeader, ccCollapsed, self:L("GROUP_CC"), 1)
                if not ccCollapsed then
                    ccCell:ClearAllPoints()
                    ccCell:SetSize(size, size)
                    ccCell:SetPoint("TOPLEFT", unitBoardFrame, "TOPLEFT", 8, -coordY)
                    ccCell.unit = "target"
                    self:ApplyCCTargetCellSecureAttributes(ccCell)
                    ccCell:Show()
                    self:UpdateCCTargetCellVisual()
                    coordY = coordY + (size + 4) + 5
                else
                    if ccCell._isHovered or (GameTooltip and GameTooltip:IsOwned(ccCell)) then
                        GameTooltip:Hide()
                    end
                    ccCell._isHovered = false
                    ccCell._lastTipSig = nil
                    ccCell:Hide()
                end
            else
                unitBoardFrame.ccGroupHeader:Hide()
                if ccCell then
                    ccCell:Hide()
                end
            end
        end
    end

    local left, top, bottom = unitBoardFrame:GetLeft(), unitBoardFrame:GetTop(), unitBoardFrame:GetBottom()
    if not draggingTitle and left and top and bottom then
        unitBoardFrame:ClearAllPoints()
        if EzWoW_SpellControlDB.growUp then
            unitBoardFrame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
            EzWoW_SpellControlDB.boardPoint = { "BOTTOMLEFT", "BOTTOMLEFT", math.floor(left + 0.5), math.floor(bottom + 0.5) }
        else
            unitBoardFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
            EzWoW_SpellControlDB.boardPoint = { "TOPLEFT", "BOTTOMLEFT", math.floor(left + 0.5), math.floor(top + 0.5) }
        end
    end

    unitBoardFrame:SetSize(frameWidth, math.max(48, coordY + 6, EzWoW_SpellControlDB.manualHeight or 0))

    if unitBoardFrame.lockBtn and unitBoardFrame.lockBtn.icon then
        unitBoardFrame.lockBtn.icon:SetTexture(MEDIA_PATH .. (EzWoW_SpellControlDB.lockBoard and "lock" or "unlock") .. ".tga")
    end

    self:ShowHoverUI(hoverUI)
    local shouldShow = EzWoW_SpellControlDB.showBoard and (numUnits > 0 or containsCCSection)
    unitBoardFrame:SetShown(shouldShow and true or false)
end

function TacticalUnitBoard.assignSlotEmptyState(cell)
    if not cell then return end
    cell._isEmptySlot = true
    cell:SetAlpha(1.0)
    cell.border:Hide()
    cell.innerBg:Hide()
    cell.icon:Hide()
    cell.classBar:Hide()
    if cell.shadeHost then cell.shadeHost:SetAlpha(0) end
    if cell.activeEdgeHost then cell.activeEdgeHost:SetAlpha(0) end
    if cell.inRangeBadgeHost then cell.inRangeBadgeHost:SetAlpha(0) end
    if cell.oorBadgeHost then cell.oorBadgeHost:SetAlpha(0) end
    if cell.glow then cell.glow:SetAlpha(0) end
    if cell.pushed then cell.pushed:SetAlpha(0) end
    TacticalUnitBoard.assignCellActiveEdges(cell, false)
    cell.nameText:SetText("")
    cell.nameText._lastFitText = ""
    cell.badgeText:SetText("")
    cell.badgeText._lastFitText = ""
end

function TacticalUnitBoard.restoreSlotVisibleState(cell)
    if not cell then return end
    cell._isEmptySlot = false
    cell:SetAlpha(1.0)
    cell.border:Show()
    cell.border:SetVertexColor(0.17, 0.22, 0.26, 0.90)
    cell.innerBg:Show()
    cell.icon:Show()
    cell.classBar:Show()
    if cell.shadeHost then cell.shadeHost:SetAlpha(0) end
    if cell.activeEdgeHost then cell.activeEdgeHost:SetAlpha(1) end
    if cell.inRangeBadgeHost then cell.inRangeBadgeHost:SetAlpha(1) end
    if cell.oorBadgeHost then cell.oorBadgeHost:SetAlpha(0) end
    if cell.glow then cell.glow:SetAlpha(1) end
    if cell.pushed then cell.pushed:SetAlpha(1) end
end

function TacticalUnitBoard.commitSlotRangeVisual(host, inRangeRaw, inRangeSecret, showActiveEdgeWhenInRange, size, oorText)
    if not inRangeSecret and inRangeRaw == nil then
        inRangeRaw = true
    end
    if host.oorBadgeText and oorText then
        TacticalUnitBoard.fitFontStringToWidth(host.oorBadgeText, oorText, size - 4, 9, 7)
        host.oorBadgeText:SetTextColor(unpack(STYLE.warn))
    end
    TacticalUnitBoard.commitFrameBoolAlpha(host, inRangeRaw, 1.0, 0.42)
    TacticalUnitBoard.commitFrameBoolAlpha(host.shadeHost, inRangeRaw, 0.0, 1.0)
    TacticalUnitBoard.commitFrameBoolAlpha(host.inRangeBadgeHost, inRangeRaw, 1.0, 0.0)
    TacticalUnitBoard.commitFrameBoolAlpha(host.oorBadgeHost, inRangeRaw, 0.0, 1.0)
    if showActiveEdgeWhenInRange then
        TacticalUnitBoard.commitFrameBoolAlpha(host.activeEdgeHost, inRangeRaw, 1.0, 0.0)
    elseif host.activeEdgeHost then
        host.activeEdgeHost:SetAlpha(0.0)
    end
    if not inRangeSecret and host.icon then
        host.icon:SetDesaturated(not inRangeRaw)
    elseif host.icon then
        host.icon:SetDesaturated(false)
    end
end

function ns:UpdateCCTargetCellVisual()
    local unitBoardFrame = self.boardFrame
    if not unitBoardFrame or not unitBoardFrame.ccTargetCell then return end
    local cell = unitBoardFrame.ccTargetCell
    if not cell:IsShown() then return end

    local size = (EzWoW_SpellControlDB and EzWoW_SpellControlDB.cellSize) or 36
    local ccSt = self.ccTargetState or self:ScanCCTargetState()

    if not ccSt.hasEnemyTarget or ccSt.isDead then
        TacticalUnitBoard.assignSlotEmptyState(cell)
        return
    end

    TacticalUnitBoard.restoreSlotVisibleState(cell)
    cell.classBar:SetColorTexture(0.92, 0.38, 0.36, 1)
    if ccSt.name then
        local enemyShortName = "⚔" .. TacticalUnitBoard.shortenUnitName(ccSt.name, 3)
        TacticalUnitBoard.fitFontStringToWidth(cell.nameText, enemyShortName, size - 4, 10, 7)
    elseif ccSt.rawNameSecret then
        cell.nameText:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE")
        cell.nameText:SetWordWrap(false)
        pcall(cell.nameText.SetText, cell.nameText, ccSt.rawName)
    else
        TacticalUnitBoard.fitFontStringToWidth(cell.nameText, "⚔", size - 4, 10, 7)
    end
    cell.nameText:SetTextColor(unpack(STYLE.textMain))

    local entry = ccSt.primaryUsableEntry
    if entry and entry.ccDef then
        cell.icon:SetTexture(entry.ccDef.icon or DEFAULT_SLOT_ICON)
        cell.innerBg:SetColorTexture(0.22, 0.11, 0.06, 0.56)
        TacticalUnitBoard.assignCellActiveEdges(cell, true, 0.95, 0.55, 0.34)
        local btnOrder = TacticalUnitBoard.resolveBoundCCButtonOrder(cell, entry.ccDef, 1)
        local badgeText = TacticalUnitBoard.resolveCCSlotBadgeText(btnOrder)
        TacticalUnitBoard.fitFontStringToWidth(cell.badgeText, badgeText, size - 4, 9, 7)
        cell.badgeText:SetTextColor(1.00, 0.82, 0.48)

        local inRangeRaw, inRangeSecret = TacticalUnitBoard.determineSlotRange(entry.inRangeRaw, entry.inRangeSecret, entry.inRange, false)
        TacticalUnitBoard.commitSlotRangeVisual(cell, inRangeRaw, inRangeSecret, true, size, self:L("BADGE_OUT_OF_RANGE"))
    else
        local fallbackIcon = (self.learnedCCDefs[1] and self.learnedCCDefs[1].icon) or DEFAULT_SLOT_ICON
        cell.icon:SetTexture(fallbackIcon)
        cell.icon:SetDesaturated(true)
        if cell.shadeHost then cell.shadeHost:SetAlpha(1) end
        cell.innerBg:SetColorTexture(0.08, 0.08, 0.10, 0.82)
        cell.border:SetVertexColor(0.24, 0.28, 0.32, 0.90)
        TacticalUnitBoard.assignCellActiveEdges(cell, false)
        TacticalUnitBoard.fitFontStringToWidth(cell.badgeText, self:L("BADGE_CC_NONE"), size - 4, 9, 7)
        cell.badgeText:SetTextColor(unpack(STYLE.textMuted))
    end
end

function ns:UpdateSingleUnitCellVisualOnly(cell)
    if not cell then return end
    if cell.sectionRole == "CC" then
        self:UpdateCCTargetCellVisual()
        return
    end
    if not cell.unit then return end

    local state = self.unitStates[cell.unit]
    local size = (EzWoW_SpellControlDB and EzWoW_SpellControlDB.cellSize) or 36

    if not state or not state.exists then
        if cell.auraContainer then cell.auraContainer:SetAlpha(0) end
        TacticalUnitBoard.assignSlotEmptyState(cell)
        return
    end

    local role = cell.sectionRole or "BUFF"
    local oorText = self:L("BADGE_OUT_OF_RANGE")

    if role == "CLEANSE" then
        if not (InCombatLockdown and InCombatLockdown()) then
            self:ConfigureCleanseCellAuraContainer(cell, cell.unit)
        end

        if not state.isConnected or state.isDead then
            if cell.auraContainer then cell.auraContainer:SetAlpha(0) end
            TacticalUnitBoard.assignSlotEmptyState(cell)
            return
        end

        local inRangeRaw, inRangeSecret = TacticalUnitBoard.determineSlotRange(
            state.dispelInRangeRaw, state.dispelInRangeSecret,
            state.inRangeRaw, state.inRangeSecret
        )

        if state.topDebuff or state.abolishingDebuff then
            if cell.auraContainer then cell.auraContainer:SetAlpha(0) end
        else
            TacticalUnitBoard.assignSlotEmptyState(cell)
            if cell.auraContainer then
                if not inRangeSecret and inRangeRaw == nil then
                    inRangeRaw = true
                end
                TacticalUnitBoard.commitFrameBoolAlpha(cell.auraContainer, inRangeRaw, 1.0, 0.42)
            end
            return
        end

        TacticalUnitBoard.restoreSlotVisibleState(cell)
        local classColor = (RAID_CLASS_COLORS and state.classFile and RAID_CLASS_COLORS[state.classFile])
            or { r = ACCENT_R, g = ACCENT_G, b = ACCENT_B }
        cell.classBar:SetColorTexture(classColor.r, classColor.g, classColor.b, 1)

        local shortName = (cell.unit == "target")
            and ("▶" .. TacticalUnitBoard.shortenUnitName(state.name, 3))
            or TacticalUnitBoard.shortenUnitName(state.name, 4)
        TacticalUnitBoard.fitFontStringToWidth(cell.nameText, shortName, size - 4, 10, 7)
        cell.nameText:SetTextColor(unpack(STYLE.textMain))

        if state.topDebuff then
            local dtVal = ns.DEBUFF_TYPES[state.topDebuff.dispelType] or { r = 0.9, g = 0.3, b = 0.3 }
            if state.topDebuff.rawIconSecret then
                pcall(cell.icon.SetTexture, cell.icon, state.topDebuff.rawIcon)
            else
                cell.icon:SetTexture(state.topDebuff.icon or DEFAULT_SLOT_ICON)
            end
            cell.innerBg:SetColorTexture(dtVal.r * 0.28, dtVal.g * 0.28, dtVal.b * 0.28, 0.62)
            TacticalUnitBoard.assignCellActiveEdges(cell, true, dtVal.r, dtVal.g, dtVal.b)

            local shortType = self:L("SHORT_" .. tostring(state.topDebuff.dispelType))
            local btnOrder = TacticalUnitBoard.resolveBoundDispelButtonOrder(cell, state.topDebuff)
            local badgeFmt = (btnOrder == 2) and self:L("BADGE_DISPEL_R") or self:L("BADGE_DISPEL_L")
            TacticalUnitBoard.fitFontStringToWidth(cell.badgeText, string.format(badgeFmt, shortType), size - 4, 9, 7)
            cell.badgeText:SetTextColor(1, 0.95, 0.85)
            TacticalUnitBoard.commitSlotRangeVisual(cell, inRangeRaw, inRangeSecret, true, size, oorText)
        elseif state.abolishingDebuff then
            local dtVal = ns.DEBUFF_TYPES[state.abolishingDebuff.dispelType] or { r = 0.3, g = 0.8, b = 0.5 }
            if state.abolishingDebuff.rawIconSecret then
                pcall(cell.icon.SetTexture, cell.icon, state.abolishingDebuff.rawIcon)
            else
                cell.icon:SetTexture(state.abolishingDebuff.icon or DEFAULT_SLOT_ICON)
            end
            cell.innerBg:SetColorTexture(dtVal.r * 0.15, dtVal.g * 0.15, dtVal.b * 0.15, 0.72)
            TacticalUnitBoard.assignCellActiveEdges(cell, false)
            TacticalUnitBoard.fitFontStringToWidth(cell.badgeText, self:L("BADGE_ABOLISHING"), size - 4, 9, 7)
            cell.badgeText:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B)
            TacticalUnitBoard.commitSlotRangeVisual(cell, inRangeRaw, inRangeSecret, false, size, oorText)
        end
        return
    end

    TacticalUnitBoard.restoreSlotVisibleState(cell)
    local classColor = (RAID_CLASS_COLORS and state.classFile and RAID_CLASS_COLORS[state.classFile])
        or { r = ACCENT_R, g = ACCENT_G, b = ACCENT_B }
    cell.classBar:SetColorTexture(classColor.r, classColor.g, classColor.b, 1)
    local shortName
    if cell.unit == "target" then
        shortName = "▶" .. TacticalUnitBoard.shortenUnitName(state.name, 3)
    else
        shortName = TacticalUnitBoard.shortenUnitName(state.name, 4)
    end
    TacticalUnitBoard.fitFontStringToWidth(cell.nameText, shortName, size - 4, 10, 7)

    if not state.isConnected then
        cell.icon:SetTexture(DEFAULT_SLOT_ICON)
        cell.icon:SetDesaturated(true)
        cell.innerBg:SetColorTexture(0.05, 0.06, 0.08, 0.78)
        if cell.shadeHost then cell.shadeHost:SetAlpha(1) end
        TacticalUnitBoard.assignCellActiveEdges(cell, false)
        cell.nameText:SetTextColor(unpack(STYLE.textMuted))
        TacticalUnitBoard.fitFontStringToWidth(cell.badgeText, self:L("BADGE_OFFLINE"), size - 4, 9, 7)
        cell.badgeText:SetTextColor(unpack(STYLE.textMuted))
        return
    elseif state.isDead then
        cell.icon:SetTexture(DEFAULT_SLOT_ICON)
        cell.icon:SetDesaturated(true)
        cell.innerBg:SetColorTexture(0.18, 0.05, 0.05, 0.82)
        if cell.shadeHost then cell.shadeHost:SetAlpha(1) end
        TacticalUnitBoard.assignCellActiveEdges(cell, false)
        cell.nameText:SetTextColor(unpack(STYLE.warn))
        TacticalUnitBoard.fitFontStringToWidth(cell.badgeText, self:L("BADGE_DEAD"), size - 4, 9, 7)
        cell.badgeText:SetTextColor(unpack(STYLE.warn))
        return
    end

    cell.nameText:SetTextColor(unpack(STYLE.textMain))
    local inRangeRaw, inRangeSecret = TacticalUnitBoard.determineSlotRange(
        state.buffInRangeRaw, state.buffInRangeSecret,
        state.inRangeRaw, state.inRangeSecret
    )

    if state.primaryMissingBuff then
        local mbVal = state.primaryMissingBuff
        cell.icon:SetTexture((mbVal.buffDef and mbVal.buffDef.icon) or DEFAULT_SLOT_ICON)
        cell.innerBg:SetColorTexture(0.18, 0.14, 0.04, 0.58)
        TacticalUnitBoard.assignCellActiveEdges(cell, true, STYLE.gold[1], STYLE.gold[2], STYLE.gold[3])

        local useRightClick = (cell.boundLClickBuff ~= mbVal.castSpell) and (cell.boundRClickBuff == mbVal.castSpell)
        local badgeKey = useRightClick and "BADGE_TARGET_BUFF_R" or "BADGE_TARGET_BUFF_L"
        TacticalUnitBoard.fitFontStringToWidth(cell.badgeText, self:L(badgeKey), size - 4, 9, 7)
        if mbVal.isDownranked then
            cell.badgeText:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B)
        else
            cell.badgeText:SetTextColor(unpack(STYLE.gold))
        end
        TacticalUnitBoard.commitSlotRangeVisual(cell, inRangeRaw, inRangeSecret, true, size, oorText)
    else
        local okIcon = (state.slot1Choice and state.slot1Choice.buffDef and state.slot1Choice.buffDef.icon)
            or (self.learnedBuffDefs[1] and self.learnedBuffDefs[1].icon)
            or (self.primaryDispelSpell and self.primaryDispelSpell.icon)
            or DEFAULT_SLOT_ICON
        cell.icon:SetTexture(okIcon)
        cell.innerBg:SetColorTexture(0.06, 0.09, 0.12, 0.78)
        TacticalUnitBoard.assignCellActiveEdges(cell, false)
        TacticalUnitBoard.fitFontStringToWidth(cell.badgeText, self:L("BADGE_BUFF_OK"), size - 4, 9, 7)
        cell.badgeText:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B)
        TacticalUnitBoard.commitSlotRangeVisual(cell, inRangeRaw, inRangeSecret, false, size, oorText)
    end
end

function ns:UpdateSingleUnitCell(unit)
    if not self.boardFrame then return end
    local state = self.unitStates[unit]

    for index = 1, #self.activeUnits do
        local bCell = self.boardFrame.buffCells and self.boardFrame.buffCells[index]
        if bCell and bCell.unit == unit then
            self:ApplyBuffCellSecureAttributes(bCell, unit, state)
            self:UpdateSingleUnitCellVisualOnly(bCell)
            if bCell._isHovered and bCell:IsMouseOver() then
                TacticalUnitBoard.presentCellTooltip(bCell, true)
            end
        end

        local cCell = self.boardFrame.cleanseCells and self.boardFrame.cleanseCells[index]
        if cCell and cCell.unit == unit then
            self:ApplyCleanseCellSecureAttributes(cCell, unit, state)
            self:UpdateSingleUnitCellVisualOnly(cCell)
            if cCell._isHovered and cCell:IsMouseOver() then
                TacticalUnitBoard.presentCellTooltip(cCell, true)
            end
        end
    end

    if unit == "target" and self.boardFrame.ccTargetCell then
        local ccCell = self.boardFrame.ccTargetCell
        if not (InCombatLockdown and InCombatLockdown()) then
            self:ApplyCCTargetCellSecureAttributes(ccCell)
        end
        self:UpdateCCTargetCellVisual()
        if ccCell._isHovered and ccCell:IsMouseOver() then
            TacticalUnitBoard.presentCellTooltip(ccCell, true)
        end
    end
end

function ns:UpdateBoardVisuals()
    if not self.boardFrame then return end
    local inCombat = InCombatLockdown and InCombatLockdown()

    for index = 1, #self.activeUnits do
        local bCell = self.boardFrame.buffCells and self.boardFrame.buffCells[index]
        if bCell and bCell.unit then
            local state = self.unitStates[bCell.unit]
            if not inCombat then
                self:ApplyBuffCellSecureAttributes(bCell, bCell.unit, state)
            end
            self:UpdateSingleUnitCellVisualOnly(bCell)
            if bCell._isHovered and bCell:IsMouseOver() then
                TacticalUnitBoard.presentCellTooltip(bCell, false)
            end
        end

        local cCell = self.boardFrame.cleanseCells and self.boardFrame.cleanseCells[index]
        if cCell and cCell.unit then
            local state = self.unitStates[cCell.unit]
            if not inCombat then
                self:ApplyCleanseCellSecureAttributes(cCell, cCell.unit, state)
            end
            self:UpdateSingleUnitCellVisualOnly(cCell)
            if cCell._isHovered and cCell:IsMouseOver() then
                TacticalUnitBoard.presentCellTooltip(cCell, false)
            end
        end
    end

    if self.boardFrame.ccTargetCell then
        local ccCell = self.boardFrame.ccTargetCell
        if not inCombat then
            self:ApplyCCTargetCellSecureAttributes(ccCell)
        end
        self:UpdateCCTargetCellVisual()
        if ccCell._isHovered and ccCell:IsMouseOver() then
            TacticalUnitBoard.presentCellTooltip(ccCell, false)
        end
    end
end

ns.STYLE = STYLE
ns.ACCENT_R, ns.ACCENT_G, ns.ACCENT_B = ACCENT_R, ACCENT_G, ACCENT_B
ns.DONATE_URL = DONATE_URL
ns.MEDIA_PATH = MEDIA_PATH
ns.ICON_PATH = ICON_PATH
ns.fitText = TacticalUnitBoard.fitFontStringToWidth
ns.GetSectionGroupLabel = TacticalUnitBoard.resolveSectionGroupLabel
ns.EnsureSectionOrder = TacticalUnitBoard.prepareSectionOrder

-----------------------------------------------------------------------------
-- Module Class Exports
-----------------------------------------------------------------------------
TacticalUnitBoard.BuildTacticalUnitBoard = ns.BuildTacticalUnitBoard
