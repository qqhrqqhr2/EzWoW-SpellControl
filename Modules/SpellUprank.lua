--===========================================================================
-- EzWoW - Spell Control
-- Modules/SpellUprank.lua : Replace Lower Ranks on Action Bars After Training
--===========================================================================
local addonName, ns = ...
local type, pairs, ipairs, tonumber, tostring, select, pcall = type, pairs, ipairs, tonumber, tostring, select, pcall

local ActionBarRankUpdater = ns.ActionBarRankUpdater or {}
ns.ActionBarRankUpdater = ActionBarRankUpdater

local ACTION_SLOT_COUNT = 180   -- every bar page, including stance/bonus bars
local queuedSpellIds = {}       -- learned while in combat or while the cursor was busy

function ActionBarRankUpdater.isEnabled()
    return not EzWoW_SpellControlDB or EzWoW_SpellControlDB.spellUprank ~= false
end

function ActionBarRankUpdater.spellName(spellID)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(spellID) end
    return GetSpellInfo and (GetSpellInfo(spellID))
end

-- "Rank 3" / "3레벨" / "Rang 3" ... -> 3; nil for spells without ranks
function ActionBarRankUpdater.rankNumber(spellID)
    local subtext
    if C_Spell and C_Spell.GetSpellSubtext then
        subtext = C_Spell.GetSpellSubtext(spellID)
    elseif GetSpellSubtext then
        subtext = GetSpellSubtext(spellID)
    end
    return type(subtext) == "string" and tonumber(subtext:match("(%d+)")) or nil
end

function ActionBarRankUpdater.isKnown(spellID)
    if IsPlayerSpell and IsPlayerSpell(spellID) then return true end
    return IsSpellKnown and IsSpellKnown(spellID) or false
end

function ActionBarRankUpdater.pickupSpell(spellID)
    if C_Spell and C_Spell.PickupSpell then return C_Spell.PickupSpell(spellID) end
    return PickupSpell(spellID)
end

-- Slots holding the same spell at a lower rank than newID
function ActionBarRankUpdater.findLowerRankSlots(newID)
    local name = ActionBarRankUpdater.spellName(newID)
    local newRank = ActionBarRankUpdater.rankNumber(newID)
    if not name or not newRank then return {} end
    local slots = {}
    for slot = 1, ACTION_SLOT_COUNT do
        local actionType, actionID = GetActionInfo(slot)
        if actionType == "spell" and type(actionID) == "number" and actionID ~= newID
            and ActionBarRankUpdater.spellName(actionID) == name then
            local oldRank = ActionBarRankUpdater.rankNumber(actionID)
            if oldRank and oldRank < newRank then slots[#slots + 1] = slot end
        end
    end
    return slots, name, newRank
end

function ActionBarRankUpdater.canEditBars()
    if InCombatLockdown() then return false end
    return not (GetCursorInfo and GetCursorInfo())
end

function ActionBarRankUpdater.applySpell(newID)
    if not ActionBarRankUpdater.isKnown(newID) then return end
    local slots, name, newRank = ActionBarRankUpdater.findLowerRankSlots(newID)
    if #slots == 0 then return end
    for _, slot in ipairs(slots) do
        ActionBarRankUpdater.pickupSpell(newID)
        PlaceAction(slot)
        ClearCursor()   -- PlaceAction leaves the replaced rank on the cursor
    end
    DEFAULT_CHAT_FRAME:AddMessage("|cff5CE0B8EzWoW - Spell Control:|r "
        .. string.format(ns:L("MSG_UPRANK"), name, #slots, newRank))
end

function ActionBarRankUpdater.flushQueue()
    if not ActionBarRankUpdater.isEnabled() then
        queuedSpellIds = {}
        return
    end
    if not ActionBarRankUpdater.canEditBars() then return end
    local pending = queuedSpellIds
    queuedSpellIds = {}
    for spellID in pairs(pending) do
        pcall(ActionBarRankUpdater.applySpell, spellID)
    end
end

function ActionBarRankUpdater.onSpellLearned(spellID)
    if not ActionBarRankUpdater.isEnabled() or type(spellID) ~= "number" then return end
    queuedSpellIds[spellID] = true
    -- the spellbook entry is filled in a moment after the learn event
    C_Timer.After(0.5, ActionBarRankUpdater.flushQueue)
end

local eventFrame = CreateFrame("Frame")
for _, eventName in ipairs({ "LEARNED_SPELL_IN_TAB", "LEARNED_SPELL_IN_SKILL_LINE", "PLAYER_REGEN_ENABLED", "CURSOR_CHANGED" }) do
    pcall(eventFrame.RegisterEvent, eventFrame, eventName)
end
eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "LEARNED_SPELL_IN_TAB" or event == "LEARNED_SPELL_IN_SKILL_LINE" then
        ActionBarRankUpdater.onSpellLearned(arg1)
    elseif next(queuedSpellIds) then
        ActionBarRankUpdater.flushQueue()
    end
end)
