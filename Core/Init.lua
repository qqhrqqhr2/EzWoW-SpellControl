--===========================================================================
-- EzWoW - Spell Control
-- Core/Init.lua : Secret-Value Guards, EzWoW Style Palette & SavedVariables Bootstrap
--===========================================================================
local ADDON_NAME, ns = ...
local type, pairs, ipairs, tonumber, tostring, select, pcall = type, pairs, ipairs, tonumber, tostring, select, pcall

local CoreBootstrap = ns.CoreBootstrap or {}
ns.CoreBootstrap = CoreBootstrap

local issecretvalue = _G.issecretvalue or function() return false end
local canaccessvalue = _G.canaccessvalue or function() return true end
local canaccesstable = _G.canaccesstable or function() return true end

function CoreBootstrap.safeVal(val)
    if issecretvalue(val) then
        return nil
    end
    local isCallOk, accessible = pcall(canaccessvalue, val)
    if isCallOk and not accessible then
        return nil
    end
    if val == nil then
        return nil
    end
    return val
end

function CoreBootstrap.rawReadTableField(t, k)
    return t[k]
end

function CoreBootstrap.safeField(tbl, key)
    if tbl == nil then
        return nil, false, nil
    end
    if issecretvalue(tbl) then
        return nil, true, nil
    end
    local okTbl, canTbl = pcall(canaccesstable, tbl)
    if okTbl and not canTbl then
        return nil, true, nil
    end
    local isCallOk, val = pcall(CoreBootstrap.rawReadTableField, tbl, key)
    if not isCallOk then
        return nil, true, nil
    end
    if issecretvalue(val) then
        return nil, true, val
    end
    local okVal, canVal = pcall(canaccessvalue, val)
    if okVal and not canVal then
        return nil, true, val
    end
    if val == nil then
        return nil, false, nil
    end
    return val, false, val
end

function CoreBootstrap.hasValuePresent(isCallOk, val)
    if not isCallOk then
        return false
    end
    if issecretvalue(val) then
        return true
    end
    local okAcc, canAcc = pcall(canaccessvalue, val)
    if okAcc and not canAcc then
        return true
    end
    return val ~= nil
end

function CoreBootstrap.pickRangeRaw(priRaw, priSec, fbRaw, fbSec)
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

ns.DEFAULTS = {
    lang = "Auto",
    showBoard = true,
    lockBoard = false,
    showSolo = true,
    showTarget = true,
    showCC = true,
    soundAlert = true,
    smartBuff = true,
    trackSecondBuff = true,
    autoDownrank = true,
    spellUprank = true,
    preferGroupBuff = false,
    unified = false,
    growUp = false,
    fade = false,
    collapsed = false,
    collapsedGroups = {
        buff = false,
        cleanse = false,
        cc = false,
    },
    cellSize = 36,
    columns = 5,
    opacity = 1.0,
    manualWidth = nil,
    manualHeight = nil,
    selectedBuffSlot1ByClass = {},
    selectedBuffSlot2ByClass = {},
    boardPoint = nil,
}

ns.playerClass = select(2, UnitClass("player"))
ns.learnedSpellMap = {}
ns.activeDispelTypes = {}
ns.learnedDispelList = {}
ns.primaryDispelSpell = nil
ns.secondaryDispelSpell = nil
ns.learnedBuffDefs = {}
ns.learnedCCDefs = {}
ns.ccSpellIdMap = {}
ns.ccSpellNameMap = {}
ns.activeCCList = {}
ns.unitStates = {}
ns.unitWheelBuffKey = {}
ns.unitWheelBuffWasActive = {}
ns.creatureTypeCacheByName = {}
ns.ccTargetState = {
    hasEnemyTarget = false,
    ccEntries = {},
    ineligibleCCs = {},
}
ns.activeUnits = { "player" }
ns.pendingSecureUpdate = false
ns.lastAlertTime = 0

function ns:InitializeDatabase()
    EzWoW_SpellControlDB = EzWoW_SpellControlDB or {}
    for entryKey, entryValue in pairs(ns.DEFAULTS) do
        if EzWoW_SpellControlDB[entryKey] == nil then
            if type(entryValue) == "table" then
                local copy = {}
                for subK, subV in pairs(entryValue) do
                    copy[subK] = subV
                end
                EzWoW_SpellControlDB[entryKey] = copy
            else
                EzWoW_SpellControlDB[entryKey] = entryValue
            end
        end
    end
    EzWoW_SpellControlDB.unified = false
    if not EzWoW_SpellControlDB.cellSizeMigrated36 then
        EzWoW_SpellControlDB.cellSizeMigrated36 = true
        if EzWoW_SpellControlDB.cellSize == 44 then
            EzWoW_SpellControlDB.cellSize = 36
            EzWoW_SpellControlDB.manualWidth = nil
            EzWoW_SpellControlDB.manualHeight = nil
        end
    end
    EzWoW_SpellControlDB.collapsedGroups = EzWoW_SpellControlDB.collapsedGroups or {}
    if EzWoW_SpellControlDB.collapsedGroups.buff == nil then
        EzWoW_SpellControlDB.collapsedGroups.buff = false
    end
    if EzWoW_SpellControlDB.collapsedGroups.cleanse == nil then
        EzWoW_SpellControlDB.collapsedGroups.cleanse = false
    end
    if EzWoW_SpellControlDB.collapsedGroups.cc == nil then
        EzWoW_SpellControlDB.collapsedGroups.cc = false
    end
end

ns.UnwrapSafeValue = CoreBootstrap.safeVal
ns.ReadSafeTableField = CoreBootstrap.safeField
ns.HasAccessibleReturnValue = CoreBootstrap.hasValuePresent
ns.SelectAvailableRangeFlag = CoreBootstrap.pickRangeRaw

-----------------------------------------------------------------------------
-- Module Class Exports
-----------------------------------------------------------------------------
CoreBootstrap.InitializeDatabase = ns.InitializeDatabase
CoreBootstrap.HasAccessibleReturnValue = ns.HasAccessibleReturnValue
CoreBootstrap.SelectAvailableRangeFlag = ns.SelectAvailableRangeFlag
CoreBootstrap.ReadSafeTableField = ns.ReadSafeTableField
CoreBootstrap.UnwrapSafeValue = ns.UnwrapSafeValue
