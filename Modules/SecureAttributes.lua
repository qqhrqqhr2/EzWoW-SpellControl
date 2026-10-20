--===========================================================================
-- EzWoW - Spell Control
-- Modules/SecureAttributes.lua : SecureUnitButton Attribute Binder & Event Loop Controller
--===========================================================================
local ADDON_NAME, ns = ...
local type, pairs, ipairs, tonumber, tostring, select, pcall = type, pairs, ipairs, tonumber, tostring, select, pcall

local SecureCellController = ns.SecureCellController or {}
ns.SecureCellController = SecureCellController
local issecretvalue = _G.issecretvalue or function() return false end
local safeVal = ns.UnwrapSafeValue

-----------------------------------------------------------------------------
-- Assign Attr If Changed
-----------------------------------------------------------------------------
function SecureCellController.assignAttrIfChanged(cell, key, val)
    cell._appliedAttrs = cell._appliedAttrs or {}
    if cell._appliedAttrs[key] ~= val then
        cell._appliedAttrs[key] = val
        cell:SetAttribute(key, val)
    end
end

function SecureCellController.determineUnitBuffSpells(self, unit, state)
    local buff1Spell = state and state.slot1Choice and state.slot1Choice.castSpell
    local buff2Spell = state and state.slot2Choice and state.slot2Choice.castSpell

    if not buff1Spell then
        local d1Val = self:GetSelectedBuffSlot1Def()
        if d1Val and d1Val.isLearned then
            local c1Val = self:SelectBuffRankForUnit(unit, d1Val, (unit ~= "target") and EzWoW_SpellControlDB and EzWoW_SpellControlDB.preferGroupBuff)
            if c1Val then buff1Spell = c1Val.castSpell end
        end
    end

    if not buff2Spell then
        local d2Val = self:GetSelectedBuffSlot2Def()
        if d2Val and d2Val.isLearned then
            local c2Val = self:SelectBuffRankForUnit(unit, d2Val, false)
            if c2Val then buff2Spell = c2Val.castSpell end
        end
    end

    return buff1Spell, buff2Spell
end

function ns:ApplyBuffCellSecureAttributes(cell, unit, state)
    if not cell then return end
    local buff1Spell, buff2Spell = SecureCellController.determineUnitBuffSpells(self, unit, state)

    cell.sectionRole = "BUFF"
    cell.targetClickIsBuff = true
    cell.targetClickIsCC = false
    cell.boundLClickBuff = buff1Spell
    cell.boundRClickBuff = buff2Spell
    cell.boundLClickDispel = nil
    cell.boundRClickDispel = nil
    cell.boundCtrlLClickBuff = buff1Spell
    cell.boundCtrlRClickBuff = buff2Spell

    if InCombatLockdown and InCombatLockdown() then
        self.pendingSecureUpdate = true
        return
    end

    SecureCellController.assignAttrIfChanged(cell, "unit", unit)
    SecureCellController.assignAttrIfChanged(cell, "shift-type1", nil)
    SecureCellController.assignAttrIfChanged(cell, "shift-spell1", nil)
    SecureCellController.assignAttrIfChanged(cell, "alt-type1", "target")

    if buff1Spell then
        SecureCellController.assignAttrIfChanged(cell, "type1", "spell")
        SecureCellController.assignAttrIfChanged(cell, "spell1", buff1Spell)
        SecureCellController.assignAttrIfChanged(cell, "ctrl-type1", "spell")
        SecureCellController.assignAttrIfChanged(cell, "ctrl-spell1", buff1Spell)
    else
        SecureCellController.assignAttrIfChanged(cell, "type1", "target")
        SecureCellController.assignAttrIfChanged(cell, "spell1", nil)
        SecureCellController.assignAttrIfChanged(cell, "ctrl-type1", nil)
        SecureCellController.assignAttrIfChanged(cell, "ctrl-spell1", nil)
    end

    if buff2Spell then
        SecureCellController.assignAttrIfChanged(cell, "type2", "spell")
        SecureCellController.assignAttrIfChanged(cell, "spell2", buff2Spell)
        SecureCellController.assignAttrIfChanged(cell, "ctrl-type2", "spell")
        SecureCellController.assignAttrIfChanged(cell, "ctrl-spell2", buff2Spell)
    else
        SecureCellController.assignAttrIfChanged(cell, "type2", nil)
        SecureCellController.assignAttrIfChanged(cell, "spell2", nil)
        SecureCellController.assignAttrIfChanged(cell, "ctrl-type2", nil)
        SecureCellController.assignAttrIfChanged(cell, "ctrl-spell2", nil)
    end
end

function ns:ApplyCleanseCellSecureAttributes(cell, unit, state)
    if not cell then return end

    local buff1Spell, buff2Spell = SecureCellController.determineUnitBuffSpells(self, unit, state)
    local pDispel = self.primaryDispelSpell and self.primaryDispelSpell.fullCastName
    local sDispel = self.secondaryDispelSpell and self.secondaryDispelSpell.fullCastName

    local dispel1 = pDispel
    local dispel2 = (sDispel and sDispel ~= dispel1) and sDispel or nil

    cell.sectionRole = "CLEANSE"
    cell.targetClickIsBuff = false
    cell.targetClickIsCC = false

    if InCombatLockdown and InCombatLockdown() then
        self.pendingSecureUpdate = true
        cell.boundLClickDispel = cell.boundLClickDispel or dispel1
        cell.boundRClickDispel = cell.boundRClickDispel or dispel2
        return
    end

    if self.ConfigureCleanseCellAuraContainer then
        self:ConfigureCleanseCellAuraContainer(cell, unit)
    end

    SecureCellController.assignAttrIfChanged(cell, "unit", unit)
    SecureCellController.assignAttrIfChanged(cell, "shift-type1", nil)
    SecureCellController.assignAttrIfChanged(cell, "shift-spell1", nil)
    SecureCellController.assignAttrIfChanged(cell, "alt-type1", "target")

    if dispel1 then
        SecureCellController.assignAttrIfChanged(cell, "type1", "spell")
        SecureCellController.assignAttrIfChanged(cell, "spell1", dispel1)
    else
        SecureCellController.assignAttrIfChanged(cell, "type1", "target")
        SecureCellController.assignAttrIfChanged(cell, "spell1", nil)
    end

    if dispel2 then
        SecureCellController.assignAttrIfChanged(cell, "type2", "spell")
        SecureCellController.assignAttrIfChanged(cell, "spell2", dispel2)
    else
        SecureCellController.assignAttrIfChanged(cell, "type2", nil)
        SecureCellController.assignAttrIfChanged(cell, "spell2", nil)
    end

    if buff1Spell then
        SecureCellController.assignAttrIfChanged(cell, "ctrl-type1", "spell")
        SecureCellController.assignAttrIfChanged(cell, "ctrl-spell1", buff1Spell)
    else
        SecureCellController.assignAttrIfChanged(cell, "ctrl-type1", nil)
        SecureCellController.assignAttrIfChanged(cell, "ctrl-spell1", nil)
    end

    if buff2Spell then
        SecureCellController.assignAttrIfChanged(cell, "ctrl-type2", "spell")
        SecureCellController.assignAttrIfChanged(cell, "ctrl-spell2", buff2Spell)
    else
        SecureCellController.assignAttrIfChanged(cell, "ctrl-type2", nil)
        SecureCellController.assignAttrIfChanged(cell, "ctrl-spell2", nil)
    end

    cell.boundLClickDispel = dispel1
    cell.boundRClickDispel = dispel2
    cell.boundCtrlLClickBuff = buff1Spell
    cell.boundCtrlRClickBuff = buff2Spell
end

function ns:ApplyCCTargetCellSecureAttributes(cell, unitForScan)
    if not cell then return end
    if InCombatLockdown and InCombatLockdown() then
        self.pendingSecureUpdate = true
        return
    end

    cell.sectionRole = "CC"
    cell.unit = "target"
    cell.targetClickIsBuff = false
    cell.targetClickIsCC = true

    SecureCellController.assignAttrIfChanged(cell, "unit", "target")
    SecureCellController.assignAttrIfChanged(cell, "shift-type1", nil)
    SecureCellController.assignAttrIfChanged(cell, "shift-spell1", nil)
    SecureCellController.assignAttrIfChanged(cell, "alt-type1", "target")

    local ccSt = self:ScanCCTargetState(unitForScan)
    local defaultDefs = self:GetDefaultOrderedCCDefs()
    local cc1 = nil
    local cc2 = nil
    if ccSt then
        if ccSt.primaryUsableEntry and ccSt.primaryUsableEntry.ccDef then
            cc1 = ccSt.primaryUsableEntry.ccDef.fullCastName
        end
        if ccSt.secondaryUsableEntry and ccSt.secondaryUsableEntry.ccDef then
            cc2 = ccSt.secondaryUsableEntry.ccDef.fullCastName
        end
    end
    if not cc1 then
        cc1 = defaultDefs[1] and defaultDefs[1].fullCastName
    end
    if not cc2 then
        for _, def in ipairs(defaultDefs) do
            if def.fullCastName and def.fullCastName ~= cc1 then
                cc2 = def.fullCastName
                break
            end
        end
    end

    local cc3 = nil
    for _, def in ipairs(defaultDefs) do
        if def.fullCastName and def.fullCastName ~= cc1 and def.fullCastName ~= cc2 then
            cc3 = def.fullCastName
            break
        end
    end
    local savedCtrl3 = cc3
    cc3 = cc3 or cc1
    local cc4 = (defaultDefs[4] and defaultDefs[4].fullCastName) or cc2

    if cc1 then
        SecureCellController.assignAttrIfChanged(cell, "type1", "spell")
        SecureCellController.assignAttrIfChanged(cell, "spell1", cc1)
    else
        SecureCellController.assignAttrIfChanged(cell, "type1", "target")
        SecureCellController.assignAttrIfChanged(cell, "spell1", nil)
    end

    if cc2 then
        SecureCellController.assignAttrIfChanged(cell, "type2", "spell")
        SecureCellController.assignAttrIfChanged(cell, "spell2", cc2)
    else
        SecureCellController.assignAttrIfChanged(cell, "type2", nil)
        SecureCellController.assignAttrIfChanged(cell, "spell2", nil)
    end

    if cc3 then
        SecureCellController.assignAttrIfChanged(cell, "ctrl-type1", "spell")
        SecureCellController.assignAttrIfChanged(cell, "ctrl-spell1", cc3)
    else
        SecureCellController.assignAttrIfChanged(cell, "ctrl-type1", nil)
        SecureCellController.assignAttrIfChanged(cell, "ctrl-spell1", nil)
    end

    if cc4 then
        SecureCellController.assignAttrIfChanged(cell, "ctrl-type2", "spell")
        SecureCellController.assignAttrIfChanged(cell, "ctrl-spell2", cc4)
    else
        SecureCellController.assignAttrIfChanged(cell, "ctrl-type2", nil)
        SecureCellController.assignAttrIfChanged(cell, "ctrl-spell2", nil)
    end

    cell.boundLClickCC = cc1
    cell.boundRClickCC = cc2
    cell.boundCtrlLClickCC = savedCtrl3

    if unitForScan and unitForScan ~= "target" then
        self:ScanCCTargetState("target")
    end
end

function ns:ApplyCellSecureAttributes(cell, unit, state)
    if not cell then return end
    if cell.sectionRole == "CLEANSE" then
        self:ApplyCleanseCellSecureAttributes(cell, unit, state)
    elseif cell.sectionRole == "CC" then
        self:ApplyCCTargetCellSecureAttributes(cell)
    else
        self:ApplyBuffCellSecureAttributes(cell, unit, state)
    end
end

-----------------------------------------------------------------------------
-- Initialize Spell Control Engine
-----------------------------------------------------------------------------
function ns:InitializeSpellControlEngine()
    self:InitializeDatabase()
    self:ScanLearnedSpells()
    self:RebuildActiveUnits()
    self:ScanAllActiveUnits()
    if self.InitUI then
        self:InitUI()
    end
    self:ScanAllActiveUnits()
    if self.RefreshAllUI then
        self:RefreshAllUI()
    end
end

local eventFrame = CreateFrame("Frame")
local EVENTS_TO_REGISTER = {
    "ADDON_LOADED",
    "PLAYER_LOGIN",
    "PLAYER_ENTERING_WORLD",
    "SPELLS_CHANGED",
    "LEARNED_SPELL_IN_TAB",
    "PLAYER_LEVEL_UP",
    "GROUP_ROSTER_UPDATE",
    "PLAYER_TARGET_CHANGED",
    "UPDATE_MOUSEOVER_UNIT",
    "UNIT_AURA",
    "UNIT_IN_RANGE_UPDATE",
    "UNIT_LEVEL",
    "UNIT_NAME_UPDATE",
    "UNIT_PET",
    "UNIT_SPELLCAST_SUCCEEDED",
    "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED",
    "ADDON_RESTRICTION_STATE_CHANGED",
}
for _, evName in ipairs(EVENTS_TO_REGISTER) do
    pcall(eventFrame.RegisterEvent, eventFrame, evName)
end

local rangeTickerElapsed = 0
eventFrame:SetScript("OnUpdate", function(_, elapsed)
    local dtVal = elapsed or 0
    rangeTickerElapsed = rangeTickerElapsed + dtVal

    if rangeTickerElapsed >= 0.4 then
        rangeTickerElapsed = 0
        if EzWoW_SpellControlDB and EzWoW_SpellControlDB.showBoard and ns.boardFrame and ns.boardFrame:IsShown() then
            ns:ScanAllActiveUnits()
        end
    end
end)

eventFrame:SetScript("OnEvent", function(_, event, arg1, arg2, arg3, arg4)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON_NAME then
            ns:InitializeDatabase()
        end
    elseif event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        ns:InitializeSpellControlEngine()
    elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then
        ns:UpdateRestrictionState(arg1, arg2)
        ns:ScanAllActiveUnits()
    elseif event == "SPELLS_CHANGED" or event == "LEARNED_SPELL_IN_TAB" or event == "PLAYER_LEVEL_UP" or (event == "UNIT_PET" and arg1 == "player") then
        ns:ScanLearnedSpells()
        if not (InCombatLockdown and InCombatLockdown()) and ns.LayoutBoardCells then
            ns:LayoutBoardCells()
        end
        ns:ScanAllActiveUnits()
        if ns.RefreshSettingsTexts then
            ns:RefreshSettingsTexts()
        end
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_TARGET_CHANGED" then
        ns:ScanCCTargetState()
        if InCombatLockdown and InCombatLockdown() then
            ns.pendingSecureUpdate = true
            ns:ScanAllActiveUnits()
        else
            ns:RebuildActiveUnits()
            if ns.LayoutBoardCells then
                ns:LayoutBoardCells()
            end
            ns:ScanAllActiveUnits()
        end
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        if UnitExists and safeVal(UnitExists("mouseover")) then
            ns:GetUnitCreatureTypeInfo("mouseover")
            if not (InCombatLockdown and InCombatLockdown()) then
                local containsEnemyTarget = ns.ccTargetState and ns.ccTargetState.hasEnemyTarget
                if not containsEnemyTarget and UnitCanAttack then
                    local okAtk, canAtk = pcall(UnitCanAttack, "player", "mouseover")
                    if okAtk and safeVal(canAtk) and ns.boardFrame and ns.boardFrame.ccTargetCell then
                        ns:ApplyCCTargetCellSecureAttributes(ns.boardFrame.ccTargetCell, "mouseover")
                    end
                end
            end
        end
    elseif event == "UNIT_IN_RANGE_UPDATE" then
        local unitRef = safeVal(arg1)
        if unitRef and ns.unitStates[unitRef] then
            pcall(ns.ScanUnitState, ns, unitRef)
            if ns.UpdateSingleUnitCell then
                ns:UpdateSingleUnitCell(unitRef)
            end
        else
            ns:ScanAllActiveUnits()
        end
    elseif event == "UNIT_AURA" or event == "UNIT_LEVEL" or event == "UNIT_NAME_UPDATE" then
        local unitRef = safeVal(arg1)
        if unitRef then
            if unitRef == "target" then
                pcall(ns.ScanCCTargetState, ns)
                if ns.boardFrame and ns.boardFrame.ccTargetCell and not (InCombatLockdown and InCombatLockdown()) then
                    ns:ApplyCCTargetCellSecureAttributes(ns.boardFrame.ccTargetCell)
                end
                if ns.UpdateCCTargetCellVisual then
                    ns:UpdateCCTargetCellVisual()
                end
            end
            if ns.unitStates[unitRef] then
                pcall(ns.ScanUnitState, ns, unitRef)
                if ns.UpdateSingleUnitCell then
                    ns:UpdateSingleUnitCell(unitRef)
                end
            end
        else
            ns:ScanAllActiveUnits()
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unitRef = safeVal(arg1)
        if unitRef == "player" or unitRef == "pet" then
            ns:ScanAllActiveUnits()
            if C_Timer and C_Timer.After then
                C_Timer.After(0.15, function()
                    ns:ScanAllActiveUnits()
                end)
            end
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        ns:ScanAllActiveUnits()
    elseif event == "PLAYER_REGEN_ENABLED" then
        ns.pendingSecureUpdate = false
        ns:RebuildActiveUnits()
        if ns.LayoutBoardCells then
            ns:LayoutBoardCells()
        end
        ns:ScanAllActiveUnits()
    end
end)

-----------------------------------------------------------------------------
-- Module Class Exports
-----------------------------------------------------------------------------
SecureCellController.InitializeSpellControlEngine = ns.InitializeSpellControlEngine
