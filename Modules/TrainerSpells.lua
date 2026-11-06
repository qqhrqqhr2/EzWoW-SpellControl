--===========================================================================
-- EzWoW - Spell Control
-- Modules/TrainerSpells.lua : Class Trainer Capture, Spells-by-Level Data,
--                             Level-up Notice & Spell Tooltip Rank Hints
--===========================================================================
local ADDON_NAME, ns = ...
local type, pairs, ipairs, tonumber, tostring, select, pcall = type, pairs, ipairs, tonumber, tostring, select, pcall

local TrainerSpells = ns.TrainerSpells or {}
ns.TrainerSpells = TrainerSpells

local issecretvalue = _G.issecretvalue or function() return false end
local CHAT_PREFIX = "|cff5CE0B8EzWoW - Spell Control:|r "

local function plain(val)
    if val == nil or issecretvalue(val) then return nil end
    return val
end

local function inCombat()
    return InCombatLockdown and InCombatLockdown() and true or false
end

local function rankNumber(rankText)
    if type(rankText) ~= "string" then return nil end
    return tonumber(rankText:match("(%d+)"))
end
TrainerSpells.RankNumber = rankNumber

-----------------------------------------------------------------------------
-- Trainer API access (a C_Trainer namespace wins when the client has one)
-----------------------------------------------------------------------------
local function trainerFn(name)
    local cTrainer = _G.C_Trainer
    if type(cTrainer) == "table" and type(cTrainer[name]) == "function" then
        return cTrainer[name]
    end
    local fn = _G[name]
    if type(fn) == "function" then return fn end
    return nil
end

local function callTrainer(name, ...)
    local fn = trainerFn(name)
    if not fn then return false end
    return pcall(fn, ...)
end

local function readServiceInfo(index)
    local ok, a, b, c, d = callTrainer("GetTrainerServiceInfo", index)
    if not ok then return nil end
    if type(a) == "table" then
        return {
            name = plain(a.name),
            rank = plain(a.rank or a.subText or a.nameSubtext),
            category = plain(a.category or a.serviceType or a.type),
            expanded = plain(a.isExpanded or a.expanded),
            spellID = plain(a.spellID),
        }
    end
    return { name = plain(a), rank = plain(b), category = plain(c), expanded = plain(d) }
end

local function spellNameByID(spellID)
    if C_Spell and type(C_Spell.GetSpellName) == "function" then
        local ok, name = pcall(C_Spell.GetSpellName, spellID)
        if ok then return plain(name) end
    end
    if type(GetSpellInfo) == "function" then
        local ok, name = pcall(GetSpellInfo, spellID)
        if ok then return plain(name) end
    end
    return nil
end

local function spellSubtextByID(spellID)
    if C_Spell and type(C_Spell.GetSpellSubtext) == "function" then
        local ok, sub = pcall(C_Spell.GetSpellSubtext, spellID)
        if ok then return plain(sub) end
    end
    if type(GetSpellSubtext) == "function" then
        local ok, sub = pcall(GetSpellSubtext, spellID)
        if ok then return plain(sub) end
    end
    return nil
end

local function spellIDFromLink(link)
    link = plain(link)
    if type(link) ~= "string" then return nil end
    return tonumber(link:match("|Hspell:(%d+)") or link:match("^spell:(%d+)"))
end

-- The spell a service teaches, when any client call exposes it.
-- An ID is only kept when its spell name matches the service name.
local function resolveServiceSpellID(index, info)
    local candidates = {}
    if type(info.spellID) == "number" then candidates[#candidates + 1] = info.spellID end
    local okId, directID = callTrainer("GetTrainerServiceSpellID", index)
    if okId and type(plain(directID)) == "number" then candidates[#candidates + 1] = directID end
    if C_TooltipInfo and type(C_TooltipInfo.GetTrainerService) == "function" then
        local okTip, data = pcall(C_TooltipInfo.GetTrainerService, index)
        if okTip and type(data) == "table" and not issecretvalue(data) then
            local tipID = plain(data.id)
            if type(tipID) == "number" then candidates[#candidates + 1] = tipID end
        end
    end
    local okLink, link = callTrainer("GetTrainerServiceItemLink", index)
    if okLink then
        local linkID = spellIDFromLink(link)
        if linkID then candidates[#candidates + 1] = linkID end
    end
    for _, spellID in ipairs(candidates) do
        if spellID > 0 and spellNameByID(spellID) == info.name then
            return spellID
        end
    end
    return nil
end

-----------------------------------------------------------------------------
-- Saved data (account-wide, per class file token)
-----------------------------------------------------------------------------
function TrainerSpells.CharacterKey()
    local name, realm = UnitName("player")
    name = plain(name) or "?"
    realm = plain(realm)
    if type(realm) ~= "string" or realm == "" then
        realm = (type(GetRealmName) == "function" and plain(GetRealmName())) or ""
    end
    return name .. "-" .. realm
end

function TrainerSpells.GetClassData(classToken)
    local db = EzWoW_SpellControlDB
    if not db or type(db.trainerSpells) ~= "table" then return nil end
    classToken = classToken or ns.playerClass or select(2, UnitClass("player"))
    local data = classToken and db.trainerSpells[classToken]
    if type(data) == "table" and type(data.spells) == "table" and #data.spells > 0 then
        return data
    end
    return nil
end

-----------------------------------------------------------------------------
-- Trainer capture
-----------------------------------------------------------------------------
local FILTER_TYPES = { "available", "unavailable", "used" }
local trainerOpen = false
local scanning = false
local ignoreUpdatesUntil = 0
local scanQueued = false

local function now()
    return (GetTime and GetTime()) or 0
end

function TrainerSpells.IsClassTrainer()
    local fn = trainerFn("IsTradeskillTrainer")
    if fn then
        local ok, isTrade = pcall(fn)
        isTrade = ok and plain(isTrade)
        if isTrade and isTrade ~= 0 then return false end
    end
    return true
end

local function readFilters()
    local saved = {}
    for _, filterType in ipairs(FILTER_TYPES) do
        local ok, value = callTrainer("GetTrainerServiceTypeFilter", filterType)
        if not ok then return nil end
        value = plain(value)
        saved[filterType] = (value and value ~= 0) and true or false
    end
    return saved
end

local function setFilter(filterType, enabled)
    local ok = callTrainer("SetTrainerServiceTypeFilter", filterType, enabled)
    if not ok then
        -- older clients take 1/0
        callTrainer("SetTrainerServiceTypeFilter", filterType, enabled and 1 or 0)
    end
end

local function collectServices()
    local okNum, numServices = callTrainer("GetNumTrainerServices")
    numServices = (okNum and tonumber(plain(numServices))) or 0
    local list, seen = {}, {}
    local usedCount, realCount = 0, 0
    local currentLine
    for index = 1, numServices do
        local info = readServiceInfo(index)
        if info and type(info.name) == "string" and info.name ~= "" then
            if info.category == "header" then
                currentLine = info.name
            else
                realCount = realCount + 1
                local rankText = (type(info.rank) == "string" and info.rank ~= "") and info.rank or nil
                local key = info.name .. "\001" .. (rankText or "")
                if not seen[key] then
                    seen[key] = true
                    local entry = { name = info.name, rank = rankText }
                    local okLv, levelReq = callTrainer("GetTrainerServiceLevelReq", index)
                    levelReq = okLv and tonumber(plain(levelReq)) or nil
                    entry.level = (levelReq and levelReq > 0) and levelReq or 1
                    local okCost, cost = callTrainer("GetTrainerServiceCost", index)
                    entry.cost = okCost and tonumber(plain(cost)) or 0
                    local okIcon, icon = callTrainer("GetTrainerServiceIcon", index)
                    icon = okIcon and plain(icon) or nil
                    if type(icon) == "number" or type(icon) == "string" then entry.icon = icon end
                    local okLine, skillLine = callTrainer("GetTrainerServiceSkillLine", index)
                    skillLine = okLine and plain(skillLine) or nil
                    entry.skillLine = (type(skillLine) == "string" and skillLine ~= "") and skillLine or currentLine
                    entry.spellID = resolveServiceSpellID(index, info)
                    if info.category == "used" then
                        entry.used = true
                        usedCount = usedCount + 1
                    end
                    list[#list + 1] = entry
                end
            end
        end
    end
    return list, realCount, usedCount
end

-- One synchronous pass: show every service type and expand every header,
-- read the list, then put the trainer window back exactly as it was.
function TrainerSpells.ScanTrainer()
    if scanning or not trainerOpen then return end
    if not TrainerSpells.IsClassTrainer() then return end
    if not trainerFn("GetNumTrainerServices") or not trainerFn("GetTrainerServiceInfo") then return end
    local db = EzWoW_SpellControlDB
    if not db then return end

    scanning = true
    local savedFilters = readFilters()
    local filtersChanged = false
    if savedFilters then
        for _, filterType in ipairs(FILTER_TYPES) do
            if not savedFilters[filterType] then
                setFilter(filterType, true)
                filtersChanged = true
            end
        end
    end

    -- collapsed headers hide their services
    local collapsedHeaders = {}
    local anyCollapsed = false
    local okNum, numServices = callTrainer("GetNumTrainerServices")
    numServices = (okNum and tonumber(plain(numServices))) or 0
    for index = 1, numServices do
        local info = readServiceInfo(index)
        if info and info.category == "header" and info.name and not info.expanded then
            collapsedHeaders[info.name] = true
            anyCollapsed = true
        end
    end
    if anyCollapsed then
        callTrainer("ExpandTrainerSkillLine", 0)
    end

    local okScan, list, realCount, usedCount = pcall(collectServices)

    if anyCollapsed and trainerFn("CollapseTrainerSkillLine") then
        local okAfter, numAfter = callTrainer("GetNumTrainerServices")
        numAfter = (okAfter and tonumber(plain(numAfter))) or 0
        -- from the bottom up so earlier indices stay valid
        for index = numAfter, 1, -1 do
            local info = readServiceInfo(index)
            if info and info.category == "header" and info.name and collapsedHeaders[info.name] then
                callTrainer("CollapseTrainerSkillLine", index)
            end
        end
    end
    if filtersChanged then
        for _, filterType in ipairs(FILTER_TYPES) do
            if not savedFilters[filterType] then
                setFilter(filterType, false)
            end
        end
    end
    scanning = false
    -- trainer updates caused by our own filter changes must not start another scan
    ignoreUpdatesUntil = now() + 0.75

    if not okScan or type(list) ~= "table" or (realCount or 0) < 1 or #list < 1 then return end

    local classToken = select(2, UnitClass("player"))
    if not classToken then return end
    db.trainerSpells = (type(db.trainerSpells) == "table") and db.trainerSpells or {}

    -- A class trainer always lists some spell the player already has. A list
    -- with none of them (e.g. a hunter's pet trainer) must not replace a
    -- class list that is already stored.
    local previous = db.trainerSpells[classToken]
    if type(previous) == "table" and type(previous.spells) == "table" and #previous.spells > 0 then
        TrainerSpells.InvalidateKnown()
        local knownAny = false
        for _, entry in ipairs(list) do
            local okKnown, known = pcall(TrainerSpells.IsEntryLearned, entry, nil)
            if okKnown and known then knownAny = true break end
        end
        if not knownAny then return end
    end

    db.trainerSpells[classToken] = {
        scannedAt = time and time() or 0,
        scannedBy = TrainerSpells.CharacterKey(),
        spells = list,
    }
    TrainerSpells.InvalidateKnown()
    if ns.RequestSpellsByLevelRefresh then ns:RequestSpellsByLevelRefresh() end
end

local function queueScan(delay)
    if scanQueued then return end
    scanQueued = true
    local function run()
        scanQueued = false
        pcall(TrainerSpells.ScanTrainer)
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(delay or 0.2, run)
    else
        run()
    end
end

-----------------------------------------------------------------------------
-- Learned state (computed live for the current character)
-----------------------------------------------------------------------------
local knownIndex
function TrainerSpells.InvalidateKnown()
    knownIndex = nil
end

local function addKnown(index, name, subName, spellID)
    name = plain(name)
    if type(name) ~= "string" or name == "" then return end
    local rec = index[name]
    if not rec then
        rec = { ranks = {}, maxRank = 0 }
        index[name] = rec
    end
    subName = plain(subName)
    if (type(subName) ~= "string" or subName == "") and spellID then
        subName = spellSubtextByID(spellID)
    end
    if type(subName) == "string" and subName ~= "" then
        rec.ranks[subName] = true
        local num = rankNumber(subName)
        if num and num > rec.maxRank then rec.maxRank = num end
    end
end

local function buildKnownIndex()
    local index = {}
    if C_SpellBook and type(C_SpellBook.GetNumSpellBookSkillLines) == "function"
        and type(C_SpellBook.GetSpellBookSkillLineInfo) == "function"
        and type(C_SpellBook.GetSpellBookItemInfo) == "function" then
        local bank = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
        local itemTypes = Enum and Enum.SpellBookItemType
        local okLines, numLines = pcall(C_SpellBook.GetNumSpellBookSkillLines)
        numLines = (okLines and tonumber(plain(numLines))) or 0
        for lineIndex = 1, numLines do
            local okLine, line = pcall(C_SpellBook.GetSpellBookSkillLineInfo, lineIndex)
            if okLine and type(line) == "table" and line.itemIndexOffset and line.numSpellBookItems then
                for slot = line.itemIndexOffset + 1, line.itemIndexOffset + line.numSpellBookItems do
                    local okInfo, info = pcall(C_SpellBook.GetSpellBookItemInfo, slot, bank)
                    if okInfo and type(info) == "table" then
                        local isFuture = itemTypes and itemTypes.FutureSpell and info.itemType == itemTypes.FutureSpell
                        local isFlyout = itemTypes and itemTypes.Flyout and info.itemType == itemTypes.Flyout
                        if not isFuture and not isFlyout then
                            local spellID = plain(info.spellID)
                            local name, subName = plain(info.name), plain(info.subName)
                            if (not name or not subName) and type(C_SpellBook.GetSpellBookItemName) == "function" then
                                local okNm, n1, n2 = pcall(C_SpellBook.GetSpellBookItemName, slot, bank)
                                if okNm then
                                    name = name or plain(n1)
                                    subName = subName or plain(n2)
                                end
                            end
                            addKnown(index, name, subName, spellID)
                        end
                    end
                end
            end
        end
    elseif type(GetNumSpellTabs) == "function" and type(GetSpellTabInfo) == "function" and type(GetSpellBookItemName) == "function" then
        local bookType = BOOKTYPE_SPELL or "spell"
        local okTabs, numTabs = pcall(GetNumSpellTabs)
        numTabs = (okTabs and tonumber(numTabs)) or 0
        for tab = 1, numTabs do
            local okTab, _, _, offset, numSlots = pcall(GetSpellTabInfo, tab)
            if okTab and offset and numSlots then
                for slot = offset + 1, offset + numSlots do
                    local skillType, spellID
                    if type(GetSpellBookItemInfo) == "function" then
                        local okItem, t, id = pcall(GetSpellBookItemInfo, slot, bookType)
                        if okItem then skillType, spellID = t, plain(id) end
                    end
                    if skillType ~= "FUTURESPELL" and skillType ~= "FLYOUT" then
                        local okNm, name, subName = pcall(GetSpellBookItemName, slot, bookType)
                        if okNm then addKnown(index, name, subName, spellID) end
                    end
                end
            end
        end
    end
    return index
end

local function getKnownIndex()
    if not knownIndex then knownIndex = buildKnownIndex() end
    return knownIndex
end

local function isSpellKnownByID(spellID)
    if type(spellID) ~= "number" then return false end
    if C_SpellBook and type(C_SpellBook.IsSpellKnown) == "function" then
        local ok, known = pcall(C_SpellBook.IsSpellKnown, spellID)
        if ok and plain(known) == true then return true end
    end
    if type(IsPlayerSpell) == "function" then
        local ok, known = pcall(IsPlayerSpell, spellID)
        if ok and plain(known) == true then return true end
    end
    if type(IsSpellKnown) == "function" then
        local ok, known = pcall(IsSpellKnown, spellID)
        if ok and plain(known) == true then return true end
    end
    return false
end

function TrainerSpells.IsEntryLearned(entry, data)
    if type(entry) ~= "table" then return false end
    if entry.spellID and isSpellKnownByID(entry.spellID) then return true end
    local rec = getKnownIndex()[entry.name]
    if rec then
        if not entry.rank or rec.ranks[entry.rank] then return true end
        local num = rankNumber(entry.rank)
        if not num then return true end
        -- the spellbook may list only the highest rank
        if rec.maxRank >= num then return true end
        if rec.maxRank == 0 and num <= 1 then return true end
    end
    if entry.used and data and data.scannedBy == TrainerSpells.CharacterKey() then
        return true
    end
    return false
end

-----------------------------------------------------------------------------
-- View model shared by the window and the spellbook panel
-----------------------------------------------------------------------------
function TrainerSpells.GetPlayerLevel()
    local level = tonumber(plain(UnitLevel("player"))) or 1
    if TrainerSpells.levelOverride and TrainerSpells.levelOverride > level then
        level = TrainerSpells.levelOverride
    end
    return level
end

function TrainerSpells.GetMaxLevel()
    local maxLevel
    if type(GetMaxLevelForPlayerExpansion) == "function" then
        local ok, v = pcall(GetMaxLevelForPlayerExpansion)
        maxLevel = ok and tonumber(plain(v)) or nil
    end
    if not maxLevel and type(GetMaxPlayerLevel) == "function" then
        local ok, v = pcall(GetMaxPlayerLevel)
        maxLevel = ok and tonumber(plain(v)) or nil
    end
    if not maxLevel or maxLevel < 1 then maxLevel = 60 end
    return maxLevel
end

local function sortRows(a, b)
    if a.level ~= b.level then return a.level < b.level end
    if a.name ~= b.name then return a.name < b.name end
    return (rankNumber(a.rank) or 0) < (rankNumber(b.rank) or 0)
end

-- Unlearned spells below the player's level (learnable now) plus every spell
-- from the player's level up to the level cap, sorted by required level.
function TrainerSpells.BuildView()
    local view = { rows = {}, availableCount = 0, availableCost = 0 }
    local data = TrainerSpells.GetClassData()
    view.playerLevel = TrainerSpells.GetPlayerLevel()
    view.maxLevel = math.max(TrainerSpells.GetMaxLevel(), view.playerLevel)
    if not data then return view end
    view.hasData = true
    view.scannedAt = data.scannedAt
    for _, entry in ipairs(data.spells) do
        if type(entry) == "table" and type(entry.name) == "string" then
            local level = tonumber(entry.level) or 1
            local learned = TrainerSpells.IsEntryLearned(entry, data)
            local availableNow = (not learned) and level <= view.playerLevel
            if level <= view.maxLevel and (level >= view.playerLevel or not learned) then
                view.rows[#view.rows + 1] = {
                    name = entry.name,
                    rank = entry.rank,
                    level = level,
                    cost = tonumber(entry.cost) or 0,
                    icon = entry.icon,
                    spellID = entry.spellID,
                    learned = learned,
                    availableNow = availableNow,
                }
            end
            if availableNow then
                view.availableCount = view.availableCount + 1
                view.availableCost = view.availableCost + (tonumber(entry.cost) or 0)
            end
        end
    end
    table.sort(view.rows, sortRows)
    return view
end

function TrainerSpells.CountLearnable(atLevel)
    local data = TrainerSpells.GetClassData()
    if not data then return 0 end
    local count = 0
    for _, entry in ipairs(data.spells) do
        if type(entry) == "table" and (tonumber(entry.level) or 1) <= atLevel
            and not TrainerSpells.IsEntryLearned(entry, data) then
            count = count + 1
        end
    end
    return count
end

-----------------------------------------------------------------------------
-- Chat lines are held back until combat ends
-----------------------------------------------------------------------------
local pendingChatLines = {}
local function printLine(msg)
    if inCombat() then
        pendingChatLines[#pendingChatLines + 1] = msg
        return
    end
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. msg) end
end

local function flushChatLines()
    if #pendingChatLines == 0 or inCombat() then return end
    for _, msg in ipairs(pendingChatLines) do
        if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. msg) end
    end
    wipe(pendingChatLines)
end

local function announceLevelUp(newLevel)
    local db = EzWoW_SpellControlDB
    if not db or db.levelUpSpellNotice == false then return end
    newLevel = tonumber(newLevel) or TrainerSpells.GetPlayerLevel()
    TrainerSpells.InvalidateKnown()
    local count = TrainerSpells.CountLearnable(newLevel)
    if count > 0 then
        printLine(string.format(ns:L("SBL_LEVELUP_MSG"), count))
    end
end

-----------------------------------------------------------------------------
-- Spell tooltip: next unlearned rank / level it can be learned at
-----------------------------------------------------------------------------
local TRACKED_TOOLTIPS = { "GameTooltip", "ItemRefTooltip", "EmbeddedItemTooltip" }

-- Post-calls also run for hidden scanning tooltips of other addons; only
-- decorate the game's own tooltips or a tooltip that is really on screen.
local function isDecoratableTooltip(tip)
    if type(tip) ~= "table" then return false end
    if tip.IsForbidden and tip:IsForbidden() then return false end
    for _, globalName in ipairs(TRACKED_TOOLTIPS) do
        if _G[globalName] == tip then return true end
    end
    local frameName = tip.GetName and plain(tip:GetName())
    if type(frameName) == "string" and frameName:lower():find("scan", 1, true) then return false end
    if type(tip.IsVisible) ~= "function" or not tip:IsVisible() then return false end
    if type(tip.GetNumPoints) == "function" and tip:GetNumPoints() == 0 then return false end
    if type(tip.GetLeft) == "function" and not tip:GetLeft() then return false end
    return true
end

local function decorateSpellTooltip(tip, spellID)
    spellID = plain(spellID)
    if type(spellID) ~= "number" or not isDecoratableTooltip(tip) then return end
    local data = TrainerSpells.GetClassData()
    if not data then return end
    local name = spellNameByID(spellID)
    if type(name) ~= "string" then return end
    local hoveredRank = rankNumber(spellSubtextByID(spellID))

    local sameName = {}
    for _, entry in ipairs(data.spells) do
        if type(entry) == "table" and entry.name == name then sameName[#sameName + 1] = entry end
    end
    if #sameName == 0 then return end

    local hoveredKnown = isSpellKnownByID(spellID)
    if not hoveredKnown then
        for _, entry in ipairs(sameName) do
            local matches = (entry.spellID == spellID)
                or (hoveredRank and rankNumber(entry.rank) == hoveredRank)
                or (not hoveredRank and not entry.rank)
            if matches then
                if not TrainerSpells.IsEntryLearned(entry, data) then
                    tip:AddLine(string.format(ns:L("SBL_TIP_LEARN_AT"), tonumber(entry.level) or 1), 0.361, 0.878, 0.722)
                    if tip.Show then tip:Show() end
                end
                return
            end
        end
    end

    -- lowest rank above the hovered one that this character has not learned
    local best
    for _, entry in ipairs(sameName) do
        local num = rankNumber(entry.rank)
        if num and (not hoveredRank or num > hoveredRank) and not TrainerSpells.IsEntryLearned(entry, data) then
            if not best or num < best.num then best = { num = num, level = tonumber(entry.level) or 1 } end
        end
    end
    if best then
        tip:AddLine(string.format(ns:L("SBL_TIP_NEXT"), best.num, best.level), 0.361, 0.878, 0.722)
        if tip.Show then tip:Show() end
    end
end

local tooltipHooked = false
local function hookSpellTooltips()
    if tooltipHooked then return end
    if TooltipDataProcessor and type(TooltipDataProcessor.AddTooltipPostCall) == "function"
        and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Spell then
        local ok = pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Spell, function(tip, tipData)
            if type(tipData) ~= "table" or issecretvalue(tipData) then return end
            pcall(decorateSpellTooltip, tip, tipData.id)
        end)
        tooltipHooked = ok
    end
    if not tooltipHooked and GameTooltip and GameTooltip.HasScript and GameTooltip:HasScript("OnTooltipSetSpell") then
        GameTooltip:HookScript("OnTooltipSetSpell", function(tip)
            if type(tip.GetSpell) ~= "function" then return end
            local okSpell, _, spellID = pcall(tip.GetSpell, tip)
            if okSpell then pcall(decorateSpellTooltip, tip, spellID) end
        end)
        tooltipHooked = true
    end
end

-----------------------------------------------------------------------------
-- Events
-----------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
for _, eventName in ipairs({
    "PLAYER_LOGIN", "TRAINER_SHOW", "TRAINER_UPDATE", "TRAINER_CLOSED",
    "SPELLS_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE", "LEARNED_SPELL_IN_TAB",
    "PLAYER_LEVEL_UP", "PLAYER_REGEN_ENABLED",
}) do
    pcall(eventFrame.RegisterEvent, eventFrame, eventName)
end

eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_LOGIN" then
        hookSpellTooltips()
    elseif event == "TRAINER_SHOW" then
        trainerOpen = true
        queueScan(0.1)
    elseif event == "TRAINER_UPDATE" then
        if scanning or not trainerOpen or now() < ignoreUpdatesUntil then return end
        queueScan(0.3)
    elseif event == "TRAINER_CLOSED" then
        trainerOpen = false
    elseif event == "SPELLS_CHANGED" or event == "LEARNED_SPELL_IN_SKILL_LINE" or event == "LEARNED_SPELL_IN_TAB" then
        TrainerSpells.InvalidateKnown()
        if ns.RequestSpellsByLevelRefresh then ns:RequestSpellsByLevelRefresh() end
    elseif event == "PLAYER_LEVEL_UP" then
        local newLevel = tonumber(plain(arg1))
        TrainerSpells.levelOverride = newLevel
        if C_Timer and C_Timer.After then
            C_Timer.After(0.5, function() announceLevelUp(newLevel) end)
        else
            announceLevelUp(newLevel)
        end
        if ns.RequestSpellsByLevelRefresh then ns:RequestSpellsByLevelRefresh() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        flushChatLines()
    end
end)

if IsLoggedIn and IsLoggedIn() then
    hookSpellTooltips()
end
