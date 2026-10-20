--===========================================================================
-- EzWoW - Spell Control
-- Modules/SpellScanner.lua : Learned Buff, Dispel & Crowd-Control Unit State Scanner
--===========================================================================
local ADDON_NAME, ns = ...

local TacticalSpellScanner = ns.TacticalSpellScanner or {}
ns.TacticalSpellScanner = TacticalSpellScanner
local issecretvalue = _G.issecretvalue or function() return false end
local canaccessvalue = _G.canaccessvalue or function() return true end
local canaccesstable = _G.canaccesstable or function() return true end
local safeVal = ns.UnwrapSafeValue
local safeField = ns.ReadSafeTableField
local hasValuePresent = ns.HasAccessibleReturnValue
local pickRangeRaw = ns.SelectAvailableRangeFlag

-----------------------------------------------------------------------------
-- Has Spell Passive Check
-----------------------------------------------------------------------------
function TacticalSpellScanner.hasSpellPassiveCheck(spellID)
    if not spellID then return false end
    if C_Spell and type(C_Spell.IsSpellPassive) == "function" then
        local isCallOk, passive = pcall(C_Spell.IsSpellPassive, spellID)
        if isCallOk and safeVal(passive) == true then
            return true
        end
    end
    if type(IsPassiveSpell) == "function" then
        local isCallOk, passive = pcall(IsPassiveSpell, spellID)
        if isCallOk and safeVal(passive) == true then
            return true
        end
    end
    return false
end

local spellNameCache, spellRankCache, spellIconCache = {}, {}, {}
local spellSubtextCache = {}

function TacticalSpellScanner.resolveSafeSpellInfo(spellID)
    if not spellID then return nil end
    local cachedName = spellNameCache[spellID]
    if cachedName ~= nil then
        return cachedName, spellRankCache[spellID], spellIconCache[spellID]
    end
    if C_Spell and C_Spell.GetSpellInfo then
        local isCallOk, apiInfo = pcall(C_Spell.GetSpellInfo, spellID)
        if isCallOk and apiInfo and apiInfo.name then
            local nVal, iVal = safeVal(apiInfo.name), safeVal(apiInfo.iconID)
            if nVal then spellNameCache[spellID], spellIconCache[spellID] = nVal, iVal end
            return nVal, nil, iVal
        end
    end
    if C_Spell and C_Spell.GetSpellName then
        local okN, displayName2 = pcall(C_Spell.GetSpellName, spellID)
        local okT, iconTex = pcall(C_Spell.GetSpellTexture, spellID)
        if okN and displayName2 then
            local nVal, iVal = safeVal(displayName2), okT and safeVal(iconTex) or nil
            if nVal then spellNameCache[spellID], spellIconCache[spellID] = nVal, iVal end
            return nVal, nil, iVal
        end
    end
    if GetSpellInfo then
        local isCallOk, displayName2, rank, iconTex = pcall(GetSpellInfo, spellID)
        if isCallOk and displayName2 then
            local nVal, rVal, iVal = safeVal(displayName2), safeVal(rank), safeVal(iconTex)
            if nVal then
                spellNameCache[spellID], spellRankCache[spellID], spellIconCache[spellID] = nVal, rVal, iVal
            end
            return nVal, rVal, iVal
        end
    end
    return nil
end

function TacticalSpellScanner.resolveSafeSpellSubtext(spellID)
    if not spellID then return nil end
    local cachedSub = spellSubtextCache[spellID]
    if cachedSub ~= nil then
        return cachedSub ~= false and cachedSub or nil
    end
    if C_Spell and C_Spell.GetSpellSubtext then
        local isCallOk, sub = pcall(C_Spell.GetSpellSubtext, spellID)
        if isCallOk and sub and not issecretvalue(sub) and sub ~= "" then
            return sub
        end
    end
    if GetSpellSubtext then
        local isCallOk, sub = pcall(GetSpellSubtext, spellID)
        if isCallOk and sub and not issecretvalue(sub) and sub ~= "" then
            return sub
        end
    end
    if GetSpellInfo then
        local isCallOk, _, rank = pcall(GetSpellInfo, spellID)
        if isCallOk and rank and not issecretvalue(rank) and rank ~= "" then
            spellSubtextCache[spellID] = rank
            return rank
        end
    end
    spellSubtextCache[spellID] = false
    return nil
end

function TacticalSpellScanner.hasSpellActuallyLearned(spellID, isPetSpell)
    if not spellID then return false end
    
    if TacticalSpellScanner.hasSpellPassiveCheck(spellID) then
        return false
    end
    if ns.learnedSpellMap[spellID] then
        return true
    end
    if isPetSpell then
        if C_SpellBook and C_SpellBook.IsSpellKnown and Enum and Enum.SpellBookSpellBank then
            local isCallOk, evalResult = pcall(C_SpellBook.IsSpellKnown, spellID, Enum.SpellBookSpellBank.Pet)
            if isCallOk and safeVal(evalResult) == true then return true end
        end
        if IsSpellKnown then
            local isCallOk, evalResult = pcall(IsSpellKnown, spellID, true)
            if isCallOk and safeVal(evalResult) == true then return true end
        end
        return false
    end
    if C_SpellBook and C_SpellBook.IsSpellKnown then
        local isCallOk, evalResult = pcall(C_SpellBook.IsSpellKnown, spellID)
        if isCallOk and safeVal(evalResult) ~= nil then
            return safeVal(evalResult) == true
        end
    end
    if IsSpellKnown then
        local isCallOk, evalResult = pcall(IsSpellKnown, spellID)
        if isCallOk and safeVal(evalResult) == true then return true end
    end
    if IsPlayerSpell then
        local isCallOk, evalResult = pcall(IsPlayerSpell, spellID)
        if isCallOk and safeVal(evalResult) == true then return true end
    end
    return false
end

-----------------------------------------------------------------------------
-- Scan Learned Spells
-----------------------------------------------------------------------------
function ns:ScanLearnedSpells()
    wipe(self.learnedSpellMap)
    wipe(self.activeDispelTypes)
    wipe(self.learnedDispelList)
    wipe(self.learnedBuffDefs)
    wipe(self.learnedCCDefs)
    wipe(self.ccSpellIdMap)
    wipe(self.ccSpellNameMap)
    self.primaryDispelSpell = nil
    self.secondaryDispelSpell = nil

    local _, classToken = UnitClass("player")
    if classToken then self.playerClass = classToken end

    local playerLevel = safeVal(UnitLevel("player")) or 1
    if playerLevel <= 0 then playerLevel = 1 end

    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookSkillLineInfo and C_SpellBook.GetSpellBookItemInfo then
        local bank = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
        local spellKind = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell
        local okLines, numLines = pcall(C_SpellBook.GetNumSpellBookSkillLines)
        numLines = (okLines and tonumber(numLines)) or 0
        for tabWidget = 1, numLines do
            local okLine, line = pcall(C_SpellBook.GetSpellBookSkillLineInfo, tabWidget)
            if okLine and line and line.itemIndexOffset and line.numSpellBookItems then
                for slot = line.itemIndexOffset + 1, line.itemIndexOffset + line.numSpellBookItems do
                    local okInfo, siVal = pcall(C_SpellBook.GetSpellBookItemInfo, slot, bank)
                    if okInfo and siVal and siVal.spellID and not issecretvalue(siVal.spellID) and not siVal.isPassive then
                        local itemTypeOk = (not spellKind) or (siVal.itemType == spellKind)
                        local spellID = siVal.spellID
                        if itemTypeOk and not TacticalSpellScanner.hasSpellPassiveCheck(spellID) then
                            local spellName = safeVal(siVal.name)
                            local subName = safeVal(siVal.subName)
                            if (not spellName or not subName) and C_SpellBook.GetSpellBookItemName then
                                local okNm, n1Val, n2Val = pcall(C_SpellBook.GetSpellBookItemName, slot, bank)
                                if okNm then
                                    spellName = spellName or safeVal(n1Val)
                                    subName = subName or safeVal(n2Val)
                                end
                            end
                            local sName, _, sIcon = TacticalSpellScanner.resolveSafeSpellInfo(spellID)
                            spellName = spellName or sName
                            subName = subName or TacticalSpellScanner.resolveSafeSpellSubtext(spellID)
                            local iconTex = safeVal(siVal.iconID) or sIcon
                            if spellName and spellName ~= "" then
                                local fullCast = spellName
                                if subName and subName ~= "" then
                                    fullCast = spellName .. "(" .. subName .. ")"
                                end
                                self.learnedSpellMap[spellID] = {
                                    id = spellID,
                                    name = spellName,
                                    subName = subName,
                                    fullCastName = fullCast,
                                    icon = iconTex,
                                }
                            end
                        end
                    end
                end
            end
        end
    end

    if GetNumSpellTabs and GetSpellTabInfo and GetSpellBookItemInfo and GetSpellBookItemName then
        local okTabs, numTabs = pcall(GetNumSpellTabs)
        numTabs = (okTabs and tonumber(numTabs)) or 0
        for tabWidget = 1, numTabs do
            local okTab, _, _, offset, numSlots = pcall(GetSpellTabInfo, tabWidget)
            if okTab and offset and numSlots then
                for slot = offset + 1, offset + numSlots do
                    local okItem, skillType, spellID = pcall(GetSpellBookItemInfo, slot, BOOKTYPE_SPELL or "spell")
                    if okItem and skillType == "SPELL" and spellID and not issecretvalue(spellID) and not self.learnedSpellMap[spellID] and not TacticalSpellScanner.hasSpellPassiveCheck(spellID) then
                        local okNm, spellName, subName = pcall(GetSpellBookItemName, slot, BOOKTYPE_SPELL or "spell")
                        spellName = okNm and safeVal(spellName) or nil
                        subName = okNm and safeVal(subName) or nil
                        local sName, _, iconTex = TacticalSpellScanner.resolveSafeSpellInfo(spellID)
                        spellName = spellName or sName
                        if spellName and spellName ~= "" then
                            local fullCast = spellName
                            if subName and subName ~= "" then
                                fullCast = spellName .. "(" .. subName .. ")"
                            end
                            self.learnedSpellMap[spellID] = {
                                id = spellID,
                                name = spellName,
                                subName = subName,
                                fullCastName = fullCast,
                                icon = iconTex,
                            }
                        end
                    end
                end
            end
        end
    end

    local function determineRankList(ranks, isPetSpell)
        local learned = {}
        local allSpellIDs = {}
        local allSpellNames = {}
        if not ranks then return learned, allSpellIDs, allSpellNames end

        for _, rowEntry in ipairs(ranks) do
            allSpellIDs[rowEntry.id] = true
            local sName, sRank, sIcon = TacticalSpellScanner.resolveSafeSpellInfo(rowEntry.id)
            if sName then
                allSpellNames[sName] = true
            end
            if playerLevel >= (rowEntry.learnedLvl or 1) and TacticalSpellScanner.hasSpellActuallyLearned(rowEntry.id, isPetSpell) then
                local bookEntry = self.learnedSpellMap[rowEntry.id]
                local displayName2 = (bookEntry and bookEntry.name) or sName
                local subName = (bookEntry and bookEntry.subName) or TacticalSpellScanner.resolveSafeSpellSubtext(rowEntry.id) or sRank
                local iconTex = (bookEntry and bookEntry.icon) or sIcon
                if displayName2 and displayName2 ~= "" then
                    local fullCastName = displayName2
                    if subName and subName ~= "" then
                        fullCastName = displayName2 .. "(" .. subName .. ")"
                    end
                    table.insert(learned, {
                        id = rowEntry.id,
                        rank = rowEntry.rank,
                        learnedLvl = rowEntry.learnedLvl or 1,
                        minTargetLvl = rowEntry.minTargetLvl or math.max(1, (rowEntry.learnedLvl or 1) - 10),
                        duration = rowEntry.duration,
                        name = displayName2,
                        subName = subName,
                        fullCastName = fullCastName,
                        icon = iconTex,
                    })
                end
            end
        end
        return learned, allSpellIDs, allSpellNames
    end

    local classDispels = ns.CLASS_DISPELS[self.playerClass]
    if classDispels then
        for _, dispelDef in ipairs(classDispels) do
            local learnedRanks = determineRankList(dispelDef.ranks, dispelDef.isPetSpell)
            if #learnedRanks > 0 then
                local highest = learnedRanks[#learnedRanks]
                local abolishName = dispelDef.abolishAuraID and TacticalSpellScanner.resolveSafeSpellInfo(dispelDef.abolishAuraID) or nil

                local addsNewType = false
                for debuffType, canCure in pairs(dispelDef.cures) do
                    if canCure and not self.activeDispelTypes[debuffType] then
                        addsNewType = true
                        break
                    end
                end

                local entry = {
                    key = dispelDef.key,
                    cures = dispelDef.cures,
                    abolishAuraID = dispelDef.abolishAuraID,
                    abolishAuraName = abolishName,
                    priority = dispelDef.priority,
                    isPetSpell = dispelDef.isPetSpell,
                    id = highest.id,
                    name = highest.name,
                    subName = highest.subName,
                    fullCastName = highest.name,
                    icon = highest.icon,
                    ranks = learnedRanks,
                    buttonSlot = nil, 
                }

                if addsNewType then
                    if not self.primaryDispelSpell then
                        entry.buttonSlot = 1
                        self.primaryDispelSpell = entry
                        table.insert(self.learnedDispelList, entry)
                    elseif not self.secondaryDispelSpell then
                        entry.buttonSlot = 2
                        self.secondaryDispelSpell = entry
                        table.insert(self.learnedDispelList, entry)
                    end

                    for debuffType, canCure in pairs(dispelDef.cures) do
                        if canCure and not self.activeDispelTypes[debuffType] then
                            self.activeDispelTypes[debuffType] = entry
                        end
                    end
                end
            end
        end
    end

    local classBuffs = ns.CLASS_BUFFS[self.playerClass]
    if classBuffs then
        for _, buffDef in ipairs(classBuffs) do
            local learnedRanks, idSet, nameSet = determineRankList(buffDef.ranks, false)
            local learnedGroupRanks, grpIdSet, grpNameSet = determineRankList(buffDef.groupRanks, false)

            for entityID in pairs(grpIdSet) do idSet[entityID] = true end
            for nmVal in pairs(grpNameSet) do nameSet[nmVal] = true end

            if buffDef.alsoSatisfiedBy then
                for _, extraID in ipairs(buffDef.alsoSatisfiedBy) do
                    idSet[extraID] = true
                    local extraName = TacticalSpellScanner.resolveSafeSpellInfo(extraID)
                    if extraName then
                        nameSet[extraName] = true
                    end
                end
            end

            local repSpellID = buffDef.ranks[1] and buffDef.ranks[1].id
            local repName, _, repIcon = TacticalSpellScanner.resolveSafeSpellInfo(repSpellID)
            local highestSingle = learnedRanks[#learnedRanks]
            local highestGroup = learnedGroupRanks[#learnedGroupRanks]

            local apiInfo = {
                key = buffDef.key,
                defaultSlot = buffDef.defaultSlot or 1,
                smartOrder = buffDef.smartOrder or 99,
                isSelfOnly = buffDef.isSelfOnly,
                manaUsersOnly = buffDef.manaUsersOnly,
                isOptionalBuff = buffDef.isOptionalBuff,
                isMainBlessing = buffDef.isMainBlessing,
                preferPhysicalClass = buffDef.preferPhysicalClass,
                preferManaClass = buffDef.preferManaClass,
                displayName = (highestSingle and highestSingle.name) or repName or buffDef.key,
                icon = (highestSingle and highestSingle.icon) or repIcon or "Interface\\Icons\\INV_Misc_QuestionMark",
                learnedRanks = learnedRanks,
                learnedGroupRanks = learnedGroupRanks,
                highestSingle = highestSingle,
                highestGroup = highestGroup,
                isLearned = (#learnedRanks > 0),
                satisfiedByIDs = idSet,
                satisfiedByNames = nameSet,
                minPossibleTargetLvl = (learnedRanks[1] and learnedRanks[1].minTargetLvl) or 1,
                minLearnedLvl = (buffDef.ranks[1] and buffDef.ranks[1].learnedLvl) or 1,
            }
            table.insert(self.learnedBuffDefs, apiInfo)
        end
    end

    local classCCs = ns.CLASS_CCS and ns.CLASS_CCS[self.playerClass]
    if classCCs then
        for _, ccDef in ipairs(classCCs) do
            local learnedRanks, idSet, nameSet = determineRankList(ccDef.ranks, ccDef.isPetSpell)
            if #learnedRanks > 0 then
                local highest = learnedRanks[#learnedRanks]
                if ccDef.alsoAuraIDs then
                    for _, extraID in ipairs(ccDef.alsoAuraIDs) do
                        idSet[extraID] = true
                        local extraName = TacticalSpellScanner.resolveSafeSpellInfo(extraID)
                        if extraName then
                            nameSet[extraName] = true
                        end
                    end
                end
                local ccEntry = {
                    key = ccDef.key,
                    priority = ccDef.priority or 99,
                    allowedTypes = ccDef.allowedTypes,
                    blockedTypes = ccDef.blockedTypes,
                    allowedTypeKeys = ccDef.allowedTypeKeys,
                    isPetSpell = ccDef.isPetSpell,
                    id = highest.id,
                    name = highest.name,
                    subName = highest.subName,
                    fullCastName = highest.name,
                    icon = highest.icon or "Interface\\Icons\\INV_Misc_QuestionMark",
                    duration = highest.duration or 20,
                    ranks = learnedRanks,
                    satisfiedByIDs = idSet,
                    satisfiedByNames = nameSet,
                    slotIdx = #self.learnedCCDefs + 1,
                }
                table.insert(self.learnedCCDefs, ccEntry)

                for _, rowEntry in ipairs(learnedRanks) do
                    self.ccSpellIdMap[rowEntry.id] = { ccDef = ccEntry, rankObj = rowEntry }
                end
                for entityID in pairs(idSet) do
                    if not self.ccSpellIdMap[entityID] then
                        self.ccSpellIdMap[entityID] = { ccDef = ccEntry, rankObj = highest }
                    end
                end
                for nmVal in pairs(nameSet) do
                    self.ccSpellNameMap[nmVal] = { ccDef = ccEntry, rankObj = highest }
                end
                if highest.name then
                    self.ccSpellNameMap[highest.name] = { ccDef = ccEntry, rankObj = highest }
                end
            end
        end
    end

    self:UpdateDispelColorCurve()
    self:EnsureSelectedBuffDefaults()
end

local restrictionStates = {}
if C_RestrictedActions and C_RestrictedActions.GetAddOnRestrictionState and Enum and Enum.AddOnRestrictionType then
    for _, fieldValue in pairs(Enum.AddOnRestrictionType) do
        local isCallOk, stateEntry = pcall(C_RestrictedActions.GetAddOnRestrictionState, fieldValue)
        if isCallOk and stateEntry ~= nil then
            restrictionStates[fieldValue] = stateEntry
        end
    end
end

function ns:UpdateRestrictionState(restrictionType, restrictionState)
    if restrictionType ~= nil and restrictionState ~= nil then
        restrictionStates[restrictionType] = restrictionState
    end
end

function ns:IsAuraDataRestricted()
    if InCombatLockdown and InCombatLockdown() then
        return true
    end
    if Enum and Enum.AddOnRestrictionType then
        local resolvedValue = Enum.AddOnRestrictionType
        if (resolvedValue.Combat and (restrictionStates[resolvedValue.Combat] or 0) ~= 0)
            or (resolvedValue.Encounter and (restrictionStates[resolvedValue.Encounter] or 0) ~= 0)
            or (resolvedValue.ChallengeMode and (restrictionStates[resolvedValue.ChallengeMode] or 0) ~= 0)
            or (resolvedValue.PvPMatch and (restrictionStates[resolvedValue.PvPMatch] or 0) ~= 0) then
            return true
        end
    end
    return false
end

local DISPEL_TYPE_TO_CURVE_ID = {
    Magic   = 1,
    Curse   = 2,
    Disease = 3,
    Poison  = 4,
}

function ns:UpdateDispelColorCurve()
    if not C_CurveUtil or type(C_CurveUtil.CreateColorCurve) ~= "function" or type(CreateColor) ~= "function" then
        return
    end
    if not self.dsCurve then
        local isCallOk, curve = pcall(C_CurveUtil.CreateColorCurve)
        if not isCallOk or not curve then return end
        if Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step and curve.SetType then
            pcall(curve.SetType, curve, Enum.LuaCurveType.Step)
        end
        self.dsCurve = curve
    end

    local dsc = self.dsCurve
    pcall(dsc.ClearPoints, dsc)
    pcall(dsc.AddPoint, dsc, 0, CreateColor(0, 0, 0, 0))
    for dType, curveId in pairs(DISPEL_TYPE_TO_CURVE_ID) do
        local dtVal = ns.DEBUFF_TYPES[dType]
        if self.activeDispelTypes and self.activeDispelTypes[dType] and dtVal then
            pcall(dsc.AddPoint, dsc, curveId, CreateColor(dtVal.r, dtVal.g, dtVal.b, 1))
        else
            pcall(dsc.AddPoint, dsc, curveId, CreateColor(1, 1, 1, 0))
        end
    end
    pcall(dsc.AddPoint, dsc, 11, CreateColor(1, 1, 1, 0))
end

function ns:EnsureSelectedBuffDefaults()
    if not EzWoW_SpellControlDB then return end
    EzWoW_SpellControlDB.selectedBuffSlot1ByClass = EzWoW_SpellControlDB.selectedBuffSlot1ByClass or {}
    EzWoW_SpellControlDB.selectedBuffSlot2ByClass = EzWoW_SpellControlDB.selectedBuffSlot2ByClass or {}

    local classToken = self.playerClass
    local cur1 = EzWoW_SpellControlDB.selectedBuffSlot1ByClass[classToken]
    local cur2 = EzWoW_SpellControlDB.selectedBuffSlot2ByClass[classToken]

    local valid1 = (cur1 == "AUTO")
    local valid2 = (cur2 == "AUTO" or cur2 == "NONE")

    for _, buttonWidget in ipairs(self.learnedBuffDefs) do
        if buttonWidget.isLearned then
            if buttonWidget.key == cur1 then valid1 = true end
            if buttonWidget.key == cur2 then valid2 = true end
        end
    end

    if not valid1 then
        EzWoW_SpellControlDB.selectedBuffSlot1ByClass[classToken] = "AUTO"
    end
    if not valid2 then
        EzWoW_SpellControlDB.selectedBuffSlot2ByClass[classToken] = "AUTO"
    end
end

function ns:GetBuffDefByKey(key)
    if not key or key == "AUTO" or key == "NONE" then return nil end
    for _, buttonWidget in ipairs(self.learnedBuffDefs) do
        if buttonWidget.isLearned and buttonWidget.key == key then
            return buttonWidget
        end
    end
    return nil
end

function ns:GetSelectedBuffSlot1Def()
    local classToken = self.playerClass
    local key = EzWoW_SpellControlDB and EzWoW_SpellControlDB.selectedBuffSlot1ByClass and EzWoW_SpellControlDB.selectedBuffSlot1ByClass[classToken]
    if key and key ~= "AUTO" and key ~= "NONE" then
        local found = self:GetBuffDefByKey(key)
        if found then return found end
    end
    for _, buttonWidget in ipairs(self.learnedBuffDefs) do
        if buttonWidget.isLearned and buttonWidget.defaultSlot == 1 then
            return buttonWidget
        end
    end
    for _, buttonWidget in ipairs(self.learnedBuffDefs) do
        if buttonWidget.isLearned then
            return buttonWidget
        end
    end
    return nil
end

function ns:GetSelectedBuffSlot2Def()
    local classToken = self.playerClass
    local key = EzWoW_SpellControlDB and EzWoW_SpellControlDB.selectedBuffSlot2ByClass and EzWoW_SpellControlDB.selectedBuffSlot2ByClass[classToken]
    if key == "NONE" then return nil end
    if key and key ~= "AUTO" then
        local found = self:GetBuffDefByKey(key)
        if found then return found end
    end
    local slot1 = self:GetSelectedBuffSlot1Def()
    for _, buttonWidget in ipairs(self.learnedBuffDefs) do
        if buttonWidget.isLearned and buttonWidget.defaultSlot == 2 and (not slot1 or buttonWidget.key ~= slot1.key) then
            return buttonWidget
        end
    end
    for _, buttonWidget in ipairs(self.learnedBuffDefs) do
        if buttonWidget.isLearned and (not slot1 or buttonWidget.key ~= slot1.key) then
            return buttonWidget
        end
    end
    return nil
end

-----------------------------------------------------------------------------
-- Select Buff Rank For Unit
-----------------------------------------------------------------------------
function ns:SelectBuffRankForUnit(unit, buffDef, useGroup)
    if not buffDef or not buffDef.isLearned then
        return nil, "NOT_LEARNED"
    end

    if buffDef.isSelfOnly and unit ~= "player" then
        return nil, "SELF_ONLY"
    end

    local ranks = (useGroup and buffDef.learnedGroupRanks and #buffDef.learnedGroupRanks > 0)
        and buffDef.learnedGroupRanks
        or buffDef.learnedRanks

    if not ranks or #ranks == 0 then
        return nil, "NOT_LEARNED"
    end

    local maxRank = ranks[#ranks]
    if unit == "player" or buffDef.isSelfOnly then
        return {
            castSpell = maxRank.name,
            displaySpell = maxRank.fullCastName,
            rankObj = maxRank,
            isDownranked = false,
            isGroup = (useGroup and ranks == buffDef.learnedGroupRanks) or false,
        }
    end

    local targetLevel = safeVal(UnitLevel(unit)) or 0
    if targetLevel <= 0 then
        targetLevel = safeVal(UnitLevel("player")) or 60
    end

    local autoDownrank = not EzWoW_SpellControlDB or (EzWoW_SpellControlDB.autoDownrank ~= false)
    if not autoDownrank then
        return {
            castSpell = maxRank.name,
            displaySpell = maxRank.fullCastName,
            rankObj = maxRank,
            isDownranked = false,
            isGroup = (useGroup and ranks == buffDef.learnedGroupRanks) or false,
        }
    end

    local chosen = nil
    for index = #ranks, 1, -1 do
        local rowEntry = ranks[index]
        if targetLevel >= (rowEntry.minTargetLvl or 1) then
            chosen = rowEntry
            break
        end
    end

    if not chosen then
        return nil, "TOO_LOW", ranks[1]
    end

    local hasDownranked = (chosen.rank < maxRank.rank)
    return {
        castSpell = chosen.fullCastName,
        displaySpell = chosen.fullCastName,
        rankObj = chosen,
        isDownranked = hasDownranked,
        targetLevel = targetLevel,
        isGroup = (useGroup and ranks == buffDef.learnedGroupRanks) or false,
    }
end

function ns:GetCandidateBuffDefsForUnit(unit, classFile)
    local hasSelfUnit = (unit == "player")
    local hasNonMana = ns.NON_MANA_CLASSES[classFile] and true or false
    local hasPhysical = ns.PHYSICAL_CLASSES[classFile] and true or false

    local candidates = {}

    if self.playerClass == "PALADIN" then
        local visitedMap = {}
        local function addPaladinCandidate(def, isAltMain)
            if def and def.isLearned and not visitedMap[def.key] then
                local allowSelf = (not def.isSelfOnly) or hasSelfUnit
                local allowMana = (not def.manaUsersOnly) or (not hasNonMana) or hasSelfUnit
                if allowSelf and allowMana then
                    visitedMap[def.key] = true
                    table.insert(candidates, def)
                end
            end
        end

        local bestMain = nil
        local mightDef = self:GetBuffDefByKey("BLESS_MIGHT")
        local wisdomDef = self:GetBuffDefByKey("BLESS_WISDOM")
        local kingsDef = self:GetBuffDefByKey("BLESS_KINGS")

        local manualKey1 = EzWoW_SpellControlDB and EzWoW_SpellControlDB.selectedBuffSlot1ByClass and EzWoW_SpellControlDB.selectedBuffSlot1ByClass["PALADIN"]
        local manualDef1 = self:GetBuffDefByKey(manualKey1)

        if manualDef1 and manualDef1.isMainBlessing then
            if not (manualDef1.manaUsersOnly and hasNonMana) then
                bestMain = manualDef1
            end
        end

        if not bestMain then
            if hasPhysical then
                bestMain = mightDef or kingsDef
            else
                bestMain = wisdomDef or kingsDef or mightDef
            end
        end

        addPaladinCandidate(bestMain)

        addPaladinCandidate(self:GetBuffDefByKey("BLESS_SALVATION"))
        if hasSelfUnit then
            addPaladinCandidate(self:GetBuffDefByKey("RIGHTEOUS_FURY"))
        end

        for _, buttonWidget in ipairs(self.learnedBuffDefs) do
            addPaladinCandidate(buttonWidget, true)
        end
        return candidates
    end

    for _, buttonWidget in ipairs(self.learnedBuffDefs) do
        if buttonWidget.isLearned then
            local allowSelf = (not buttonWidget.isSelfOnly) or hasSelfUnit
            local allowMana = (not buttonWidget.manaUsersOnly) or (not hasNonMana) or hasSelfUnit
            if allowSelf and allowMana then
                table.insert(candidates, buttonWidget)
            end
        end
    end

    return candidates
end

-----------------------------------------------------------------------------
-- Clean Creature Type String
-----------------------------------------------------------------------------
function TacticalSpellScanner.cleanCreatureTypeString(str)
    if not str or str == "" then return nil end
    local stateFlag = tostring(str):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    stateFlag = stateFlag:match("^%s*(.-)%s*$")
    if stateFlag == "" then return nil end
    return stateFlag
end

function TacticalSpellScanner.matchLocalizedCreatureType(str)
    if not str or not ns.CREATURE_TYPE_LOCALE_MAP then return nil, nil end
    local exact = ns.CREATURE_TYPE_LOCALE_MAP[str]
    if exact then
        return exact, str
    end
    
    local bestKey, bestLoc, bestLen = nil, nil, 0
    for locStr, mappedKey in pairs(ns.CREATURE_TYPE_LOCALE_MAP) do
        local strLength = #locStr
        if strLength > bestLen and string.find(str, locStr, 1, true) then
            bestKey = mappedKey
            bestLoc = locStr
            bestLen = strLength
        end
    end
    return bestKey, bestLoc
end

function ns:GetUnitCreatureTypeInfo(unit)
    if not unit or not safeVal(UnitExists(unit)) then
        return "UNKNOWN", self:L("CTYPE_UNKNOWN"), nil, false
    end

    local rawUnitName = nil
    if UnitName then
        local okN, uName = pcall(UnitName, unit)
        if okN then rawUnitName = uName end
    end
    local unitName = safeVal(rawUnitName)
    if not unitName and UnitNameUnmodified then
        local okU, uName = pcall(UnitNameUnmodified, unit)
        if okU then unitName = safeVal(uName) end
    end
    if not unitName and C_NamePlate and C_NamePlate.GetNamePlateForUnit then
        local okP, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
        if hasValuePresent(okP, plate) then
            local ufVal = safeField(plate, "UnitFrame")
            local lbl = ufVal and (safeField(ufVal, "name") or safeField(ufVal, "nameText"))
            if lbl and lbl.GetText then
                local okT, displayText = pcall(lbl.GetText, lbl)
                if okT then unitName = TacticalSpellScanner.cleanCreatureTypeString(safeVal(displayText)) end
            end
        end
    end

    local rawTypeName = nil
    local rawTypeSecret = false
    local locType, typeID = nil, nil
    if UnitCreatureType then
        local isCallOk, tName, tID = pcall(UnitCreatureType, unit)
        if isCallOk then
            rawTypeName = tName
            rawTypeSecret = issecretvalue(tName)
            locType = TacticalSpellScanner.cleanCreatureTypeString(safeVal(tName))
            typeID = safeVal(tID)
        end
    end

    local typeKey, matchedLoc = TacticalSpellScanner.matchLocalizedCreatureType(locType)
    if not typeKey and typeID and ns.CREATURE_TYPE_ID_MAP then
        typeKey = ns.CREATURE_TYPE_ID_MAP[typeID]
    end

    if not typeKey and C_TooltipInfo and C_TooltipInfo.GetUnit and ns.CREATURE_TYPE_LOCALE_MAP then
        local okTip, tipData = pcall(C_TooltipInfo.GetUnit, unit)
        if hasValuePresent(okTip, tipData) then
            local lineList = safeField(tipData, "lines")
            if type(lineList) == "table" then
                for lIdx = 2, math.min(5, #lineList) do
                    local lineObj = safeField(lineList, lIdx)
                    local lineTxt = TacticalSpellScanner.cleanCreatureTypeString(safeField(lineObj, "leftText"))
                    if lineTxt then
                        local mKey, mLoc = TacticalSpellScanner.matchLocalizedCreatureType(lineTxt)
                        if mKey then
                            typeKey = mKey
                            locType = locType or mLoc
                            break
                        end
                    end
                end
            end
        end
    end

    if not typeKey and GameTooltip and GameTooltip.GetUnit and GameTooltip:IsShown() then
        local okU, _, tipUnit = pcall(GameTooltip.GetUnit, GameTooltip)
        tipUnit = okU and safeVal(tipUnit) or nil
        if tipUnit and UnitIsUnit then
            local okSame, hasSame = pcall(UnitIsUnit, tipUnit, unit)
            if okSame and safeVal(hasSame) then
                local numLines = GameTooltip:NumLines() or 0
                for lIdx = 2, math.min(5, numLines) do
                    local labelRegion = _G["GameTooltipTextLeft" .. lIdx]
                    local lineTxt = labelRegion and labelRegion.GetText and TacticalSpellScanner.cleanCreatureTypeString(safeVal(labelRegion:GetText())) or nil
                    if lineTxt then
                        local mKey, mLoc = TacticalSpellScanner.matchLocalizedCreatureType(lineTxt)
                        if mKey then
                            typeKey = mKey
                            locType = locType or mLoc
                            break
                        end
                    end
                end
            end
        end
    end

    local hasPl = false
    if UnitIsPlayer then
        local okPl, plVal = pcall(UnitIsPlayer, unit)
        if okPl and safeVal(plVal) then
            hasPl = true
            if not typeKey then
                typeKey = "HUMANOID"
            end
        end
    end

    if not typeKey and not hasPl and UnitCreatureFamily then
        local okFam, famName, famID = pcall(UnitCreatureFamily, unit)
        if okFam and (safeVal(famName) ~= nil or safeVal(famID) ~= nil) then
            local hasPlayerPet = (UnitPlayerControlled and safeVal(UnitPlayerControlled(unit)))
                or (UnitIsOtherPlayersPet and safeVal(UnitIsOtherPlayersPet(unit)))
            if not hasPlayerPet then
                typeKey = "BEAST"
            end
        end
    end

    if not typeKey and not hasPl then
        local uLvl = safeVal(UnitLevel(unit)) or 0
        local reaction = UnitReaction and safeVal(UnitReaction(unit, "player")) or nil
        if uLvl == 1 and (reaction == 4 or rawTypeSecret) then
            typeKey = "CRITTER"
        end
    end

    if not typeKey and unitName and self.creatureTypeCacheByName and self.creatureTypeCacheByName[unitName] then
        local cached = self.creatureTypeCacheByName[unitName]
        typeKey = cached.key
        locType = locType or cached.loc
    end

    typeKey = typeKey or "UNKNOWN"
    local locDisplay = (locType and locType ~= "" and locType) or matchedLoc or self:L("CTYPE_" .. typeKey)

    if typeKey ~= "UNKNOWN" and unitName and unitName ~= "" then
        self.creatureTypeCacheByName = self.creatureTypeCacheByName or {}
        self.creatureTypeCacheByName[unitName] = {
            key = typeKey,
            loc = locDisplay,
        }
    end

    return typeKey, locDisplay, rawTypeName, rawTypeSecret
end

function ns:IsCCDefEligibleForType(ccDef, creatureTypeKey)
    if not ccDef then return false end
    if creatureTypeKey == "CRITTER" then
        return false
    end
    if not creatureTypeKey or creatureTypeKey == "UNKNOWN" then
        return true
    end
    if ccDef.blockedTypes and ccDef.blockedTypes[creatureTypeKey] then
        return false
    end
    if ccDef.allowedTypes and not ccDef.allowedTypes[creatureTypeKey] then
        return false
    end
    return true
end

function ns:FormatAllowedTypesText(ccDef)
    if not ccDef or not ccDef.allowedTypeKeys then return "" end
    local parts = {}
    for _, lKey in ipairs(ccDef.allowedTypeKeys) do
        table.insert(parts, self:L(lKey))
    end
    return table.concat(parts, "·")
end

-----------------------------------------------------------------------------
-- Get Unit Range Boolean
-----------------------------------------------------------------------------
function ns:GetUnitRangeBoolean(spellName, spellID, unit)
    if unit == "player" then
        return true, false
    end
    if not unit or not safeVal(UnitExists(unit)) then
        return false, false
    end
    if UnitIsUnit then
        local okMe, hasMe = pcall(UnitIsUnit, unit, "player")
        if okMe and safeVal(hasMe) == true then
            return true, false
        end
    end
    local okConn, hasConn = pcall(UnitIsConnected, unit)
    if okConn and safeVal(hasConn) == false then
        return false, false
    end
    local okDead, hasDead = pcall(UnitIsDeadOrGhost, unit)
    if okDead and safeVal(hasDead) == true then
        return false, false
    end
    if UnitPhaseReason then
        local okPhase, phaseReason = pcall(UnitPhaseReason, unit)
        if okPhase and safeVal(phaseReason) ~= nil then
            return false, false
        end
    end
    if UnitIsVisible then
        local okVis, hasVis = pcall(UnitIsVisible, unit)
        if okVis and safeVal(hasVis) == false then
            return false, false
        end
    end

    if spellID and C_Spell and C_Spell.IsSpellInRange then
        local isCallOk, inRange = pcall(C_Spell.IsSpellInRange, spellID, unit)
        if isCallOk then
            if issecretvalue(inRange) then
                return inRange, true
            end
            if inRange == true or inRange == 1 then return true, false end
            if inRange == false or inRange == 0 then return false, false end
        end
    end

    if spellName and C_Spell and C_Spell.IsSpellInRange then
        local isCallOk, inRange = pcall(C_Spell.IsSpellInRange, spellName, unit)
        if isCallOk then
            if issecretvalue(inRange) then
                return inRange, true
            end
            if inRange == true or inRange == 1 then return true, false end
            if inRange == false or inRange == 0 then return false, false end
        end
    end

    if spellName and IsSpellInRange then
        local isCallOk, inRange = pcall(IsSpellInRange, spellName, unit)
        if isCallOk then
            if issecretvalue(inRange) then
                return inRange, true
            end
            if inRange == 1 or inRange == true then return true, false end
            if inRange == 0 or inRange == false then return false, false end
        end
    end

    local inGroupUnit = (UnitInParty and safeVal(UnitInParty(unit))) or (UnitInRaid and safeVal(UnitInRaid(unit)))
    if inGroupUnit and UnitInRange then
        local isCallOk, inRange, checked = pcall(UnitInRange, unit)
        if isCallOk then
            if issecretvalue(inRange) then
                return inRange, true
            end
            if inRange ~= nil then
                if safeVal(checked) == false then
                    
                else
                    return (inRange == true or inRange == 1), false
                end
            end
        end
    end

    if CheckInteractDistance then
        local okInt, inDist = pcall(CheckInteractDistance, unit, 4)
        if okInt then
            if issecretvalue(inDist) then
                return inDist, true
            end
            if inDist == true or inDist == 1 then
                return true, false
            end
        end
    end

    return (UnitIsVisible and safeVal(UnitIsVisible(unit))) and true or false, false
end

function ns:IsSpellInRangeForUnit(spellName, spellID, unit)
    local rawBool, hasSecret = self:GetUnitRangeBoolean(spellName, spellID, unit)
    if hasSecret then
        return true, rawBool, true
    end
    local cleanBool = (rawBool == true or rawBool == 1)
    return cleanBool, cleanBool, false
end

function ns:GetDefaultOrderedCCDefs()
    return self.learnedCCDefs
end

function ns:ScanCCTargetState(unitOverride)
    local verifyUnit = unitOverride or "target"
    local stateEntry
    if verifyUnit == "target" then
        stateEntry = self.ccTargetState
        if not stateEntry then
            stateEntry = { ccEntries = {}, ineligibleCCs = {} }
            self.ccTargetState = stateEntry
        else
            wipe(stateEntry.ccEntries)
            wipe(stateEntry.ineligibleCCs)
        end
    else
        stateEntry = { ccEntries = {}, ineligibleCCs = {} }
    end

    stateEntry.hasEnemyTarget = false
    stateEntry.name = nil
    stateEntry.rawName = nil
    stateEntry.rawNameSecret = false
    stateEntry.level = 0
    stateEntry.isDead = false
    stateEntry.creatureTypeKey = nil
    stateEntry.creatureTypeLocale = nil
    stateEntry.rawCreatureType = nil
    stateEntry.rawCreatureTypeSecret = false
    stateEntry.primaryUsableEntry = nil
    stateEntry.secondaryUsableEntry = nil
    stateEntry.anyInRange = false

    local containsTarget = UnitExists and safeVal(UnitExists(verifyUnit)) and true or false
    local hasEnemy = false
    if containsTarget and UnitCanAttack then
        local okAtk, canAtk = pcall(UnitCanAttack, "player", verifyUnit)
        if okAtk and safeVal(canAtk) then
            hasEnemy = true
        end
    end

    if hasEnemy then
        local cKey, cLoc, rawCType, rawCSec = self:GetUnitCreatureTypeInfo(verifyUnit)
        stateEntry.creatureTypeKey = cKey
        stateEntry.creatureTypeLocale = cLoc
        stateEntry.rawCreatureType = rawCType
        stateEntry.rawCreatureTypeSecret = rawCSec
        
        if cKey == "CRITTER" then
            hasEnemy = false
        end
    end

    if not hasEnemy then
        local defaultDefs = self:GetDefaultOrderedCCDefs()
        for entryIndex, ccDef in ipairs(defaultDefs) do
            table.insert(stateEntry.ccEntries, {
                ccDef = ccDef,
                slotIndex = entryIndex,
                slotIdx = entryIndex,
                usableOrder = entryIndex,
                eligible = true,
                inRange = true,
                rangeRaw = true,
                rangeSecret = false,
                inRangeRaw = true,
                inRangeSecret = false,
            })
        end
        stateEntry.primaryUsableEntry = stateEntry.ccEntries[1]
        stateEntry.secondaryUsableEntry = stateEntry.ccEntries[2]
        return stateEntry
    end

    stateEntry.hasEnemyTarget = (verifyUnit == "target")
    local rawUName = nil
    if UnitName then
        local okN, uName = pcall(UnitName, verifyUnit)
        if okN then rawUName = uName end
    end
    stateEntry.rawName = rawUName
    stateEntry.rawNameSecret = issecretvalue(rawUName)
    local cleanUName = safeVal(rawUName)
    if not cleanUName and C_NamePlate and C_NamePlate.GetNamePlateForUnit then
        local okP, plate = pcall(C_NamePlate.GetNamePlateForUnit, verifyUnit)
        if hasValuePresent(okP, plate) then
            local ufVal = safeField(plate, "UnitFrame")
            local lbl = ufVal and (safeField(ufVal, "name") or safeField(ufVal, "nameText"))
            if lbl and lbl.GetText then
                local okT, displayText = pcall(lbl.GetText, lbl)
                if okT then cleanUName = TacticalSpellScanner.cleanCreatureTypeString(safeVal(displayText)) end
            end
        end
    end
    stateEntry.name = cleanUName
    stateEntry.level = safeVal(UnitLevel(verifyUnit)) or 0
    stateEntry.isDead = safeVal(UnitIsDeadOrGhost(verifyUnit)) and true or false

    local usableList = {}
    for entryIndex, ccDef in ipairs(self.learnedCCDefs) do
        local eligible = self:IsCCDefEligibleForType(ccDef, stateEntry.creatureTypeKey)
        local inRange, rangeRaw, rangeSecret = false, false, false
        if not stateEntry.isDead then
            inRange, rangeRaw, rangeSecret = self:IsSpellInRangeForUnit(ccDef.name, ccDef.id, verifyUnit)
        end
        local entry = {
            ccDef = ccDef,
            slotIndex = entryIndex,
            slotIdx = entryIndex,
            usableOrder = nil,
            eligible = eligible,
            inRange = inRange,
            rangeRaw = rangeRaw,
            rangeSecret = rangeSecret,
            inRangeRaw = rangeRaw,
            inRangeSecret = rangeSecret,
        }
        table.insert(stateEntry.ccEntries, entry)
        if eligible then
            table.insert(usableList, entry)
            if inRange then
                stateEntry.anyInRange = true
            end
        else
            table.insert(stateEntry.ineligibleCCs, entry)
        end
    end

    
    local inCombat = InCombatLockdown and InCombatLockdown()
    local ccCell = self.boardFrame and self.boardFrame.ccTargetCell
    if inCombat and ccCell and ccCell.boundLClickCC and #usableList > 1 then
        for index, entry in ipairs(usableList) do
            if entry.ccDef and entry.ccDef.fullCastName == ccCell.boundLClickCC then
                if index > 1 then
                    table.remove(usableList, index)
                    table.insert(usableList, 1, entry)
                end
                break
            end
        end
    end

    for index, entry in ipairs(usableList) do
        entry.usableOrder = index
    end
    stateEntry.primaryUsableEntry = usableList[1]
    stateEntry.secondaryUsableEntry = usableList[2]

    return stateEntry
end

function ns:GetPrimaryDispelTypeForSpell(dispelEntry)
    if not dispelEntry or not dispelEntry.cures then return "Poison" end
    local bestType = nil
    local bestOrder = 999
    for dType, canCure in pairs(dispelEntry.cures) do
        if canCure then
            local ord = (ns.DEBUFF_TYPES[dType] and ns.DEBUFF_TYPES[dType].order) or 99
            if ord < bestOrder then
                bestOrder = ord
                bestType = dType
            end
        end
    end
    return bestType or "Poison"
end

function ns:ScanUnitState(unit)
    local unitState = self.unitStates[unit]
    if not unitState then
        unitState = {
            unit = unit,
            debuffs = {},
            missingBuffs = {},
            tooLowBuffs = {},
            validChoices = {},
            lastKnownActiveBuffKeys = {},
        }
        self.unitStates[unit] = unitState
    else
        wipe(unitState.debuffs)
        wipe(unitState.missingBuffs)
        wipe(unitState.tooLowBuffs)
        unitState.validChoices = unitState.validChoices or {}
        wipe(unitState.validChoices)
        unitState.lastKnownActiveBuffKeys = unitState.lastKnownActiveBuffKeys or {}
    end

    unitState.isEnemy = false
    if not safeVal(UnitExists(unit)) or (unit == "target" and not self:ShouldShowTargetUnit()) then
        unitState.exists = false
        return unitState
    end

    unitState.exists = true
    local rawUName = nil
    if UnitName then
        local okN, uName = pcall(UnitName, unit)
        if okN then rawUName = uName end
    end
    unitState.rawName = rawUName
    unitState.rawNameSecret = issecretvalue(rawUName)
    unitState.name = safeVal(rawUName) or unitState.name or unit
    local classLocale, classFile = UnitClass(unit)
    unitState.classLocale = safeVal(classLocale) or unitState.classLocale or ""
    unitState.classFile = safeVal(classFile) or unitState.classFile or "PRIEST"
    local uLvl = safeVal(UnitLevel(unit))
    if uLvl and uLvl > 0 then
        unitState.level = uLvl
    else
        unitState.level = unitState.level or 0
    end
    unitState.isConnected = safeVal(UnitIsConnected(unit)) ~= false
    unitState.isDead = safeVal(UnitIsDeadOrGhost(unit)) and true or false

    unitState.topDebuff = nil
    unitState.abolishingDebuff = nil
    unitState.cureSpell = nil
    unitState.secondaryCureSpell = nil
    unitState.primaryMissingBuff = nil
    unitState.slot1Choice = nil
    unitState.slot2Choice = nil
    unitState.wheelSelectedChoice = nil

    local bDef1 = self:GetSelectedBuffSlot1Def()
    local buffRefName = bDef1 and bDef1.displayName
    local buffRefID = bDef1 and bDef1.highestSingle and bDef1.highestSingle.id
    local dispelRefName = self.primaryDispelSpell and self.primaryDispelSpell.name
    local dispelRefID = self.primaryDispelSpell and self.primaryDispelSpell.id

    unitState.buffInRange, unitState.buffRangeRaw, unitState.buffRangeSecret = self:IsSpellInRangeForUnit(buffRefName or dispelRefName, buffRefID or dispelRefID, unit)
    unitState.buffInRangeRaw = unitState.buffRangeRaw
    unitState.buffInRangeSecret = unitState.buffRangeSecret
    unitState.dispelInRange, unitState.dispelRangeRaw, unitState.dispelRangeSecret = self:IsSpellInRangeForUnit(dispelRefName or buffRefName, dispelRefID or buffRefID, unit)
    unitState.dispelInRangeRaw = unitState.dispelRangeRaw
    unitState.dispelInRangeSecret = unitState.dispelRangeSecret
    unitState.inRange = unitState.buffInRange or unitState.dispelInRange
    unitState.inRangeRaw, unitState.inRangeSecret = pickRangeRaw(unitState.buffRangeRaw, unitState.buffRangeSecret, unitState.dispelRangeRaw, unitState.dispelRangeSecret)

    if not unitState.isConnected or unitState.isDead then
        return unitState
    end

    local activeBuffIDs = {}
    local activeBuffNames = {}
    local anyHelpfulRestricted = false
    for index = 1, 40 do
        local displayName2, spellId
        local nameSec, idSec = false, false
        if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
            local isCallOk, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, index, "HELPFUL")
            if not hasValuePresent(isCallOk, aura) then break end
            displayName2, nameSec = safeField(aura, "name")
            spellId, idSec = safeField(aura, "spellId")
        elseif UnitBuff then
            local isCallOk, bName, _, _, _, _, _, _, _, _, bSpellId = pcall(UnitBuff, unit, index)
            if not hasValuePresent(isCallOk, bName) then break end
            nameSec = issecretvalue(bName)
            idSec = issecretvalue(bSpellId)
            displayName2 = safeVal(bName)
            spellId = safeVal(bSpellId)
        else
            break
        end
        if nameSec or idSec then
            anyHelpfulRestricted = true
        end
        if spellId then activeBuffIDs[spellId] = true end
        if displayName2 then activeBuffNames[displayName2] = true end
    end

    local function hasAuraActiveByIDOrName(entityID, nmVal)
        if entityID and activeBuffIDs[entityID] then return true end
        if nmVal and activeBuffNames[nmVal] then return true end
        if entityID and unit == "player" and C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
            local isCallOk, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, entityID)
            if isCallOk and safeVal(aura) ~= nil then
                return true
            end
        end
        if entityID and C_UnitAuras and C_UnitAuras.GetUnitAuraBySpellID then
            local isCallOk, aura = pcall(C_UnitAuras.GetUnitAuraBySpellID, unit, entityID)
            if isCallOk and safeVal(aura) ~= nil then
                return true
            end
        end
        if nmVal and C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
            local isCallOk, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, unit, nmVal, "HELPFUL")
            if isCallOk and safeVal(aura) ~= nil then
                return true
            end
        end
        return false
    end

    if not self:IsAuraDataRestricted() then
        for index = 1, 40 do
            local displayName2, iconTex, totalCount, dispelType, duration, expirationTime, spellId, auraInstanceID
            local rawDispelSecret, rawIconSecret = false, false
            local rawIconVal = nil
            local resolveDebuff = C_UnitAuras and (C_UnitAuras.GetDebuffDataByIndex or C_UnitAuras.GetAuraDataByIndex)
            if resolveDebuff then
                local isCallOk, aura = pcall(resolveDebuff, unit, index, "HARMFUL")
                if not hasValuePresent(isCallOk, aura) then break end
                displayName2 = safeField(aura, "name")
                dispelType, rawDispelSecret = safeField(aura, "dispelName")
                iconTex, rawIconSecret, rawIconVal = safeField(aura, "icon")
                totalCount = safeField(aura, "applications")
                duration = safeField(aura, "duration")
                expirationTime = safeField(aura, "expirationTime")
                spellId = safeField(aura, "spellId")
                auraInstanceID = safeField(aura, "auraInstanceID")
            elseif UnitDebuff then
                local isCallOk, dName, dIcon, dCount, dType, dDur, dExp, _, _, _, dSpellId = pcall(UnitDebuff, unit, index)
                if not hasValuePresent(isCallOk, dName) then break end
                rawDispelSecret = issecretvalue(dType)
                rawIconSecret = issecretvalue(dIcon)
                rawIconVal = dIcon
                displayName2 = safeVal(dName)
                iconTex = safeVal(dIcon)
                totalCount = safeVal(dCount)
                dispelType = safeVal(dType)
                duration = safeVal(dDur)
                expirationTime = safeVal(dExp)
                spellId = safeVal(dSpellId)
            else
                break
            end

            if not dispelType and rawDispelSecret and auraInstanceID and self.dsCurve and C_UnitAuras and C_UnitAuras.GetAuraDispelTypeColor then
                local okCol, sCol = pcall(C_UnitAuras.GetAuraDispelTypeColor, unit, auraInstanceID, self.dsCurve)
                if hasValuePresent(okCol, sCol) and self.primaryDispelSpell then
                    dispelType = self:GetPrimaryDispelTypeForSpell(self.primaryDispelSpell)
                end
            end

            if dispelType and self.activeDispelTypes[dispelType] then
                local cureEntry = self.activeDispelTypes[dispelType]
                local hasAbolishing = false
                if cureEntry.abolishAuraID and hasAuraActiveByIDOrName(cureEntry.abolishAuraID, cureEntry.abolishAuraName) then
                    hasAbolishing = true
                end

                local baseOrder = (ns.DEBUFF_TYPES[dispelType] and ns.DEBUFF_TYPES[dispelType].order) or 99
                local btnOrder = (cureEntry.buttonSlot == 1) and 0 or 10
                local resolvedName = (displayName2 and displayName2 ~= "" and displayName2) or self:L("DEBUFF_" .. tostring(dispelType))

                local debuffInfo = {
                    name = resolvedName,
                    icon = iconTex or cureEntry.icon,
                    rawIcon = rawIconVal,
                    rawIconSecret = rawIconSecret,
                    count = totalCount or 0,
                    dispelType = dispelType,
                    duration = duration or 0,
                    expirationTime = expirationTime or 0,
                    spellId = spellId,
                    auraInstanceID = auraInstanceID,
                    cureSpell = cureEntry,
                    cureButton = cureEntry.buttonSlot or 1,
                    isAbolishing = hasAbolishing,
                    priority = baseOrder + btnOrder,
                }
                table.insert(unitState.debuffs, debuffInfo)

                if hasAbolishing then
                    if not unitState.abolishingDebuff then
                        unitState.abolishingDebuff = debuffInfo
                    end
                else
                    if not unitState.topDebuff or debuffInfo.priority < unitState.topDebuff.priority then
                        unitState.topDebuff = debuffInfo
                        unitState.cureSpell = cureEntry
                    end
                end
            end
        end
    end

    local function hasBuffActiveOnUnit(buffDef)
        for entityID in pairs(buffDef.satisfiedByIDs) do
            if hasAuraActiveByIDOrName(entityID, nil) then return true end
        end
        for nmVal in pairs(buffDef.satisfiedByNames) do
            if hasAuraActiveByIDOrName(nil, nmVal) then
                return true
            end
        end
        if anyHelpfulRestricted and unitState.lastKnownActiveBuffKeys and unitState.lastKnownActiveBuffKeys[buffDef.key] ~= nil then
            return unitState.lastKnownActiveBuffKeys[buffDef.key]
        end
        return false
    end

    local useGroup = (unit ~= "target") and EzWoW_SpellControlDB and EzWoW_SpellControlDB.preferGroupBuff and true or false
    local smartBuff = not EzWoW_SpellControlDB or (EzWoW_SpellControlDB.smartBuff ~= false)
    local trackSecond = not EzWoW_SpellControlDB or (EzWoW_SpellControlDB.trackSecondBuff ~= false)
    local classToken = self.playerClass
    local manualKey1 = EzWoW_SpellControlDB and EzWoW_SpellControlDB.selectedBuffSlot1ByClass and EzWoW_SpellControlDB.selectedBuffSlot1ByClass[classToken]
    local manualKey2 = EzWoW_SpellControlDB and EzWoW_SpellControlDB.selectedBuffSlot2ByClass and EzWoW_SpellControlDB.selectedBuffSlot2ByClass[classToken]

    local candidates = self:GetCandidateBuffDefsForUnit(unit, unitState.classFile)
    local validChoices = unitState.validChoices
    local mainBlessingChecked = false

    for entryIndex, buffDef in ipairs(candidates) do
        local allowGroup = useGroup and (entryIndex == 1)
        local rankChoice, errReason, minRankObj = self:SelectBuffRankForUnit(unit, buffDef, allowGroup)
        if rankChoice then
            rankChoice.buffDef = buffDef
            rankChoice.isActive = hasBuffActiveOnUnit(buffDef)
            rankChoice.isMissing = not rankChoice.isActive
            if not anyHelpfulRestricted then
                unitState.lastKnownActiveBuffKeys[buffDef.key] = rankChoice.isActive
            end
            table.insert(validChoices, rankChoice)

            local hasSecondaryMainBlessing = false
            if self.playerClass == "PALADIN" and buffDef.isMainBlessing then
                if mainBlessingChecked then
                    hasSecondaryMainBlessing = true
                else
                    mainBlessingChecked = true
                end
            end

            local shouldWarnMissing = (not buffDef.isOptionalBuff) and (not hasSecondaryMainBlessing) and (entryIndex == 1 or trackSecond)
            if shouldWarnMissing and not rankChoice.isActive then
                table.insert(unitState.missingBuffs, rankChoice)
            end
        elseif errReason == "TOO_LOW" and minRankObj then
            table.insert(unitState.tooLowBuffs, {
                buffDef = buffDef,
                minRankObj = minRankObj,
                targetLevel = unitState.level,
            })
        end
    end

    if smartBuff and (not manualKey1 or manualKey1 == "AUTO") then
        if #unitState.missingBuffs > 0 then
            unitState.slot1Choice = unitState.missingBuffs[1]
            unitState.slot1Choice.slotIndex = 1
            unitState.primaryMissingBuff = unitState.slot1Choice

            if manualKey2 == "NONE" then
                unitState.slot2Choice = nil
            elseif manualKey2 and manualKey2 ~= "AUTO" then
                local m2Def = self:GetBuffDefByKey(manualKey2)
                if m2Def then
                    local c2Val = self:SelectBuffRankForUnit(unit, m2Def, false)
                    if c2Val then
                        c2Val.buffDef = m2Def
                        c2Val.slotIndex = 2
                        unitState.slot2Choice = c2Val
                    end
                end
            elseif #unitState.missingBuffs >= 2 then
                unitState.slot2Choice = unitState.missingBuffs[2]
                unitState.slot2Choice.slotIndex = 2
            else
                for _, vcVal in ipairs(validChoices) do
                    if vcVal.buffDef.key ~= unitState.slot1Choice.buffDef.key then
                        unitState.slot2Choice = vcVal
                        unitState.slot2Choice.slotIndex = 2
                        break
                    end
                end
            end
        else
            if validChoices[1] then
                unitState.slot1Choice = validChoices[1]
                unitState.slot1Choice.slotIndex = 1
            end
            if manualKey2 ~= "NONE" and validChoices[2] then
                unitState.slot2Choice = validChoices[2]
                unitState.slot2Choice.slotIndex = 2
            end
        end
    else
        local d1Val = self:GetSelectedBuffSlot1Def()
        if d1Val then
            local c1Val = self:SelectBuffRankForUnit(unit, d1Val, useGroup)
            if c1Val then
                c1Val.buffDef = d1Val
                c1Val.slotIndex = 1
                unitState.slot1Choice = c1Val
                if not hasBuffActiveOnUnit(d1Val) then
                    unitState.primaryMissingBuff = c1Val
                end
            end
        end

        local d2Val = self:GetSelectedBuffSlot2Def()
        if d2Val then
            local c2Val = self:SelectBuffRankForUnit(unit, d2Val, false)
            if c2Val then
                c2Val.buffDef = d2Val
                c2Val.slotIndex = 2
                unitState.slot2Choice = c2Val
                if trackSecond and not hasBuffActiveOnUnit(d2Val) and not unitState.primaryMissingBuff then
                    unitState.primaryMissingBuff = c2Val
                    if smartBuff then
                        unitState.slot2Choice = unitState.slot1Choice
                        if unitState.slot2Choice then
                            unitState.slot2Choice.slotIndex = 2
                        end
                        c2Val.slotIndex = 1
                        unitState.slot1Choice = c2Val
                    end
                end
            end
        end
    end

    local wheelKey = self.unitWheelBuffKey and self.unitWheelBuffKey[unit]
    if wheelKey then
        local wheelChoice = nil
        for _, vcVal in ipairs(validChoices) do
            if vcVal.buffDef and vcVal.buffDef.key == wheelKey then
                wheelChoice = vcVal
                break
            end
        end
        if wheelChoice then
            if self.unitWheelBuffWasActive[unit] == false and wheelChoice.isActive and #unitState.missingBuffs > 0 then
                self.unitWheelBuffKey[unit] = nil
                self.unitWheelBuffWasActive[unit] = nil
            else
                unitState.slot1Choice = wheelChoice
                unitState.slot1Choice.slotIndex = 1
                unitState.wheelSelectedChoice = wheelChoice
                if not wheelChoice.isActive then
                    unitState.primaryMissingBuff = wheelChoice
                end
                unitState.slot2Choice = nil
                for _, mbVal in ipairs(unitState.missingBuffs) do
                    if mbVal.buffDef.key ~= wheelChoice.buffDef.key then
                        unitState.slot2Choice = mbVal
                        unitState.slot2Choice.slotIndex = 2
                        break
                    end
                end
                if not unitState.slot2Choice then
                    for _, vcVal in ipairs(validChoices) do
                        if vcVal.buffDef.key ~= wheelChoice.buffDef.key then
                            unitState.slot2Choice = vcVal
                            unitState.slot2Choice.slotIndex = 2
                            break
                        end
                    end
                end
            end
        else
            self.unitWheelBuffKey[unit] = nil
            self.unitWheelBuffWasActive[unit] = nil
        end
    end

    local chosenBuff = unitState.primaryMissingBuff or unitState.slot1Choice or unitState.slot2Choice
    if chosenBuff and chosenBuff.rankObj then
        unitState.buffInRange, unitState.buffRangeRaw, unitState.buffRangeSecret = self:IsSpellInRangeForUnit(chosenBuff.rankObj.name, chosenBuff.rankObj.id, unit)
        unitState.buffInRangeRaw = unitState.buffRangeRaw
        unitState.buffInRangeSecret = unitState.buffRangeSecret
    end
    local chosenDispel = unitState.cureSpell or self.primaryDispelSpell or self.secondaryDispelSpell
    if chosenDispel then
        unitState.dispelInRange, unitState.dispelRangeRaw, unitState.dispelRangeSecret = self:IsSpellInRangeForUnit(chosenDispel.name, chosenDispel.id, unit)
        unitState.dispelInRangeRaw = unitState.dispelRangeRaw
        unitState.dispelInRangeSecret = unitState.dispelRangeSecret
    end
    unitState.inRange = unitState.buffInRange and unitState.dispelInRange
    unitState.inRangeRaw, unitState.inRangeSecret = pickRangeRaw(unitState.buffRangeRaw, unitState.buffRangeSecret, unitState.dispelRangeRaw, unitState.dispelRangeSecret)

    return unitState
end

function ns:CycleUnitLeftClickBuff(unit, delta)
    if not unit or not UnitExists(unit) then return false end
    local unitState = self:ScanUnitState(unit)
    local choices = unitState and unitState.validChoices
    if not choices or #choices <= 1 then return false end

    local lookupKey = unitState.slot1Choice and unitState.slot1Choice.buffDef and unitState.slot1Choice.buffDef.key
    local currentIndex = 1
    for index, vcVal in ipairs(choices) do
        if vcVal.buffDef and vcVal.buffDef.key == lookupKey then
            currentIndex = index
            break
        end
    end

    local nextIdx
    if (delta or -1) < 0 then
        nextIdx = (currentIndex % #choices) + 1
    else
        nextIdx = ((currentIndex - 2) % #choices) + 1
    end

    local nextChoice = choices[nextIdx]
    if not nextChoice or not nextChoice.buffDef then return false end

    self.unitWheelBuffKey[unit] = nextChoice.buffDef.key
    self.unitWheelBuffWasActive[unit] = nextChoice.isActive and true or false

    self:ScanUnitState(unit)
    if self.UpdateSingleUnitCell then
        self:UpdateSingleUnitCell(unit)
    end
    return true
end

-----------------------------------------------------------------------------
-- Should Show Target Unit
-----------------------------------------------------------------------------
function ns:ShouldShowTargetUnit()
    if EzWoW_SpellControlDB and EzWoW_SpellControlDB.showTarget == false then
        return false
    end
    local okEx, exists = pcall(UnitExists, "target")
    if not okEx or not safeVal(exists) then
        return false
    end
    if UnitIsUnit then
        local okMe, hasMe = pcall(UnitIsUnit, "target", "player")
        if okMe and safeVal(hasMe) then
            return false
        end
    end
    if UnitCanAttack then
        local okAtk, canAtk = pcall(UnitCanAttack, "player", "target")
        if okAtk and safeVal(canAtk) then
            return false
        end
    end
    if UnitIsPlayer then
        local okPl, hasPl = pcall(UnitIsPlayer, "target")
        if not okPl or not safeVal(hasPl) then
            return false
        end
    end
    if UnitIsFriend then
        local okFr, hasFr = pcall(UnitIsFriend, "player", "target")
        if not okFr or not safeVal(hasFr) then
            return false
        end
    end
    if UnitInParty then
        local okPty, inPty = pcall(UnitInParty, "target")
        if okPty and safeVal(inPty) then
            return false
        end
    end
    if UnitInRaid then
        local okRd, inRd = pcall(UnitInRaid, "target")
        if okRd and safeVal(inRd) then
            return false
        end
    end
    return true
end

function ns:RebuildActiveUnits()
    wipe(self.activeUnits)
    if IsInRaid and IsInRaid() then
        local numericVal = GetNumGroupMembers and GetNumGroupMembers() or 40
        for index = 1, math.min(numericVal, 40) do
            local unitRef = "raid" .. index
            if UnitExists(unitRef) then
                table.insert(self.activeUnits, unitRef)
            end
        end
        if #self.activeUnits == 0 then
            table.insert(self.activeUnits, "player")
        end
    elseif IsInGroup and IsInGroup() then
        table.insert(self.activeUnits, "player")
        for index = 1, 4 do
            local unitRef = "party" .. index
            if UnitExists(unitRef) then
                table.insert(self.activeUnits, unitRef)
            end
        end
    else
        if not EzWoW_SpellControlDB or EzWoW_SpellControlDB.showSolo ~= false then
            table.insert(self.activeUnits, "player")
        end
    end

    if self:ShouldShowTargetUnit() then
        table.insert(self.activeUnits, "target")
    end
end

function ns:ScanAllActiveUnits()
    local hadDebuffBefore = false
    for _, unitRef in ipairs(self.activeUnits) do
        local previousVal = self.unitStates[unitRef]
        if previousVal and previousVal.topDebuff then
            hadDebuffBefore = true
            break
        end
    end

    local containsDebuffNow = false
    for _, unitRef in ipairs(self.activeUnits) do
        local okSt, stateEntry = pcall(self.ScanUnitState, self, unitRef)
        if okSt and stateEntry and stateEntry.topDebuff and stateEntry.dispelInRange then
            containsDebuffNow = true
        end
    end

    pcall(self.ScanCCTargetState, self)

    if containsDebuffNow and not hadDebuffBefore and EzWoW_SpellControlDB and EzWoW_SpellControlDB.soundAlert then
        local currentTime = GetTime and GetTime() or 0
        if currentTime - self.lastAlertTime > 3.0 then
            self.lastAlertTime = currentTime
            if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then
                pcall(PlaySound, SOUNDKIT.RAID_WARNING, "Master")
            elseif PlaySound then
                pcall(PlaySound, 8959)
            end
        end
    end

    if self.UpdateBoardVisuals then
        self:UpdateBoardVisuals()
    end
end

-----------------------------------------------------------------------------
-- Module Class Exports
-----------------------------------------------------------------------------
TacticalSpellScanner.IsAuraDataRestricted = ns.IsAuraDataRestricted
