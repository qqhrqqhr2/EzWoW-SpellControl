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

-- "value unknown" in the applied-attribute cache: the next assign always sets it
local STALE_ATTR = {}

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

-----------------------------------------------------------------------------
-- Left-Click Cast Sequence (buff cells)
-- Out of combat every scan moves a buff cell's left click on to the next missing
-- buff once the last one has landed. In combat the attributes are frozen and auras
-- cannot be read, so while two or more buffs are still to cast the left click runs
-- a /castsequence macro of the same order: the game moves it on only after a
-- successful cast (a failed one, out of range or mana, stays on the same buff).
-----------------------------------------------------------------------------
local SEQ_MAX_TEXT = 255
-- The game keeps a sequence's place per macro text, not per target, so every built
-- sequence gets its own tag in the reset part. Letters only and no "t": the tag can
-- never read as seconds or as "target", "combat", "shift", "ctrl" or "alt".
local SEQ_TAG_LETTERS = "abcdefghijklmnopqrsuvwxyz"
local seqTagSerial = 0
local seqStepCache = {}   -- cast text -> spell ID the sequence waits for (false = unusable)

local function nextSequenceTag()
    seqTagSerial = seqTagSerial + 1
    local n, tag, base = seqTagSerial, "", #SEQ_TAG_LETTERS
    repeat
        local digit = n % base
        tag = SEQ_TAG_LETTERS:sub(digit + 1, digit + 1) .. tag
        n = math.floor(n / base)
    until n == 0
    return tag
end

-- learned spells changed: a name without a rank may stand for another rank now
function ns:ClearSequenceSpellCache()
    wipe(seqStepCache)
end

local function readSpellID(fn, spellID)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, spellID)
    if ok and not issecretvalue(value) and type(value) == "number" then return value end
    return nil
end

-- the game's own test for "this cast is the step's spell"
function SecureCellController.castMatchesStep(stepSpellID, castID)
    if not stepSpellID or not castID then return false end
    local book = C_SpellBook
    if not book then return stepSpellID == castID end
    return stepSpellID == readSpellID(book.FindSpellOverrideByID, castID)
        or stepSpellID == readSpellID(book.FindBaseSpellByID, castID)
end

-- spell ID the game's sequence keeps for one step (it looks the lower-cased text up
-- again); nil when it would take the text for an item or finds no spell
local function sequenceStepSpellID(text)
    local cached = seqStepCache[text]
    if cached ~= nil then return cached or nil end
    local found = false
    local lower = strlower(strtrim(text))
    local isItem = false
    if C_Item and type(C_Item.GetItemInfo) == "function" then
        local ok, itemName = pcall(C_Item.GetItemInfo, lower)
        isItem = ok and (issecretvalue(itemName) or itemName ~= nil)
    end
    if not isItem and C_Spell and type(C_Spell.GetSpellIDForSpellIdentifier) == "function" then
        local ok, spellID = pcall(C_Spell.GetSpellIDForSpellIdentifier, lower)
        if ok and not issecretvalue(spellID) and type(spellID) == "number" then
            found = spellID
        end
    end
    seqStepCache[text] = found
    return found or nil
end

-- cast text for one step that the game will match after the cast (the cast is the
-- rank the plain spell casts), and the spell ID it waits for; a name without a rank
-- (own highest rank) that the game reads as another rank is given its rank
local function sequenceStepFor(choice)
    local rankObj = choice and choice.rankObj
    local wantID = rankObj and rankObj.id
    if not wantID then return nil end
    local texts = { choice.castSpell, rankObj.fullCastName }
    for index = 1, 2 do
        local text = texts[index]
        -- "," splits the steps; ";" "[" "]" belong to the macro options
        if type(text) == "string" and text ~= "" and not text:find("[,;%[%]\r\n]") then
            local stepID = sequenceStepSpellID(text)
            if stepID and SecureCellController.castMatchesStep(stepID, wantID) then
                return text, stepID
            end
        end
    end
    return nil
end

function SecureCellController.dropLeftClickSequence(cell)
    cell.ezSeqInput, cell.ezSeqText, cell.ezSeqKey, cell.ezSeqSteps = nil, nil, nil, nil
    cell.ezSeqRan, cell.ezSeqStep, cell.ezSeqTargetReset = false, 1, false
    cell.ezSeqOwnCast = nil
end

-- builds (or keeps) the cast sequence of a buff cell's left click; returns the macro
-- text, or nil when the plain spell is used. A changed order always gets a new tag,
-- so a sequence the game still holds half done is never picked up again.
function SecureCellController.prepareLeftClickSequence(cell, unit, state, buff1Spell)
    local order = state and state.leftClickOrder
    local first = type(order) == "table" and order[1]
    if not (unit and buff1Spell and first and order[2] and first.castSpell == buff1Spell) then
        SecureCellController.dropLeftClickSequence(cell)
        return nil
    end
    -- the game restarts it when combat ends; the target cell's one also on a new target
    local resetWords = (unit == "target") and "combat/target" or "combat"
    -- (the name too: after a roster change "party2" may be someone else)
    local inputParts = { unit, tostring(state.name), resetWords }
    for index = 1, #order do
        local rankObj = order[index].rankObj
        inputParts[#inputParts + 1] = tostring(order[index].castSpell) .. "#" .. tostring(rankObj and rankObj.id)
    end
    local input = table.concat(inputParts, "\031")
    if cell.ezSeqInput == input then
        -- same sequence: keep its place, follow the newest scan's entries
        local steps = cell.ezSeqSteps
        if steps then
            for index = 1, #steps do
                steps[index].choice = order[index] or steps[index].choice
            end
        end
        return cell.ezSeqText
    end

    SecureCellController.dropLeftClickSequence(cell)
    cell.ezSeqInput = input
    local steps, texts = {}, {}
    for index = 1, #order do
        local text, stepID = sequenceStepFor(order[index])
        if not text then break end   -- the steps after it could never be reached
        steps[#steps + 1] = { choice = order[index], text = text, spellID = stepID }
        texts[#texts + 1] = text
    end
    if #steps < 2 then return nil end

    local tag = nextSequenceTag()
    local options, macroText
    repeat
        options = "[@" .. unit .. "] reset=" .. resetWords .. "/" .. tag .. " " .. table.concat(texts, ", ")
        macroText = "/castsequence " .. options
        if #macroText <= SEQ_MAX_TEXT then break end
        steps[#steps] = nil
        texts[#texts] = nil
    until #steps < 2
    if #steps < 2 then return nil end

    -- the game keeps the place under the text its option parser hands to /castsequence;
    -- without that text the place is followed from the casts alone (the mirror)
    local key
    if type(SecureCmdOptionParse) == "function" then
        local ok, parsed = pcall(SecureCmdOptionParse, options)
        if ok and not issecretvalue(parsed) and type(parsed) == "string" then
            -- any other text would not read as these steps: keep the plain spell
            if parsed ~= "reset=" .. resetWords .. "/" .. tag .. " " .. table.concat(texts, ", ") then
                return nil
            end
            key = parsed
        end
    end

    cell.ezSeqText, cell.ezSeqKey, cell.ezSeqSteps = macroText, key, steps
    cell.ezSeqTargetReset = (unit == "target")
    return macroText
end

-- step the next left click casts: asked from the game when possible, else the mirror
-- kept from the casts (OnSequenceSpellCast)
local function sequenceStepIndex(cell)
    local steps = cell.ezSeqSteps
    if not steps then return nil end
    local index = 1
    if cell.ezSeqRan then
        index = cell.ezSeqStep or 1
        if cell.ezSeqKey and type(QueryCastSequence) == "function" then
            local ok, asked = pcall(QueryCastSequence, cell.ezSeqKey)
            if ok and not issecretvalue(asked) and type(asked) == "number" then
                index = asked
            end
        end
    end
    if index < 1 or index > #steps then index = 1 end
    return index
end

-- what the next left click on a buff cell casts when it is not just the slot-1 buff:
-- a buff picked with Ctrl + wheel in combat, or the current step of the sequence
function ns:GetCellLeftClickChoice(cell)
    if not cell or cell.sectionRole ~= "BUFF" then return nil end
    if cell.ezPickedLeft then return cell.ezPickedLeft end
    local index = sequenceStepIndex(cell)
    local step = index and cell.ezSeqSteps[index]
    return step and step.choice
end

-- buffs the following left clicks cast after the current step (tooltip), or nil
function ns:GetCellLeftClickNextText(cell)
    if not cell or cell.sectionRole ~= "BUFF" or cell.ezPickedLeft then return nil end
    local index = sequenceStepIndex(cell)
    if not index then return nil end
    local steps, names = cell.ezSeqSteps, {}
    for later = index + 1, #steps do
        local choice = steps[later].choice
        names[#names + 1] = (choice and (choice.displaySpell or choice.castSpell)) or steps[later].text
    end
    if #names == 0 then return nil end
    return table.concat(names, ", ")
end

-- redraw the cells whose sequence may have moved, once the game has handled the
-- same event (a sequence the game is not running cannot move)
local seqRedrawQueued = false
local function redrawSequenceCells()
    seqRedrawQueued = false
    local board = ns.boardFrame
    if not (board and board.buffCells and ns.UpdateSingleUnitCellVisualOnly) then return end
    local present = ns.TacticalUnitBoard and ns.TacticalUnitBoard.presentCellTooltip
    for _, cell in ipairs(board.buffCells) do
        if cell.ezSeqRedraw then
            cell.ezSeqRedraw = nil
            if cell.unit and cell:IsShown() then
                ns:UpdateSingleUnitCellVisualOnly(cell)
                if present and cell._isHovered and cell:IsMouseOver() then
                    present(cell, true)
                end
            end
        end
    end
end

function SecureCellController.queueSequenceRedraw()
    if seqRedrawQueued then return end
    if C_Timer and C_Timer.After then
        seqRedrawQueued = true
        C_Timer.After(0, redrawSequenceCells)
    else
        redrawSequenceCells()
    end
end

-- The game moves on every sequence it holds whose current step is the spell just
-- cast, whatever the target: also one whose last click failed (out of range, on
-- cooldown). So the cast a left click sends is told apart from the same spell cast
-- elsewhere, and out of combat a sequence moved on by another cast starts again under
-- a new tag: the left click keeps the scan's order. In combat that cannot be changed;
-- the cell then shows what the game will cast.
local SEQ_CLICK_WINDOW = 0.5   -- seconds from a click to the cast it sends
local SEQ_CAST_MAX = 10        -- seconds a cell's own cast may stay unanswered
local seqClickCell, seqClickTime

-- out of combat: a fresh sequence (new tag, first step) for the cell's left click
local function restartSequenceNow(cell)
    if InCombatLockdown and InCombatLockdown() then return end
    SecureCellController.dropLeftClickSequence(cell)
    cell.ezSeqRedraw = true
    if cell.unit then
        ns:ApplyBuffCellSecureAttributes(cell, cell.unit, ns.unitStates and ns.unitStates[cell.unit])
    end
end

-- PreClick of every cell: the cell whose click runs its sequence, else nil
function ns:NoteSequenceClick(cell)
    seqClickCell, seqClickTime = cell, GetTime()
end

-- true when spellID is the step the clicked cell's sequence is at
local function isClickedStep(cell, spellID)
    if not (cell and spellID and cell.ezSeqSteps) then return false end
    local index = sequenceStepIndex(cell)
    local step = index and cell.ezSeqSteps[index]
    return step ~= nil and SecureCellController.castMatchesStep(step.spellID, spellID)
end

-- the player's cast was sent: it is the clicked cell's own when it is the step that
-- cell's sequence is at
function ns:OnSequenceCastSent(castGUID, spellID)
    local cell = seqClickCell
    seqClickCell = nil
    if not castGUID or GetTime() - (seqClickTime or 0) > SEQ_CLICK_WINDOW then return end
    if isClickedStep(cell, spellID) then
        cell.ezSeqOwnCast, cell.ezSeqOwnCastAt = castGUID, GetTime()
    end
end

-- the player's cast failed or was interrupted: no longer on its way; a click whose
-- cast failed before it was sent (range, cooldown) sends nothing more
function ns:OnSequenceCastEnded(castGUID, spellID)
    if isClickedStep(seqClickCell, spellID) then
        seqClickCell = nil
    end
    local board = self.boardFrame
    if not (castGUID and board and board.buffCells) then return end
    for _, cell in ipairs(board.buffCells) do
        if cell.ezSeqOwnCast == castGUID then
            cell.ezSeqOwnCast = nil
        end
    end
end

-- a cast of ours went through: move the mirror on the way the game moves its
-- sequences (every running one whose current step is that spell), then redraw;
-- out of combat one that was moved on by a cast not its own starts again
function ns:OnSequenceSpellCast(castID, castGUID)
    local board = self.boardFrame
    if not (board and board.buffCells) then return end
    local canRestart = not (InCombatLockdown and InCombatLockdown())
    local anyRunning = false
    for _, cell in ipairs(board.buffCells) do
        local own = castGUID ~= nil and cell.ezSeqOwnCast == castGUID
        if own then cell.ezSeqOwnCast = nil end
        local steps = cell.ezSeqSteps
        if steps and cell.ezSeqRan then
            cell.ezSeqRedraw = true
            anyRunning = true
            local stepIndex = cell.ezSeqStep or 1
            local step = steps[stepIndex]
            if castID and step and SecureCellController.castMatchesStep(step.spellID, castID) then
                if canRestart and not own then
                    restartSequenceNow(cell)
                elseif stepIndex >= #steps then
                    -- last step done: the game puts the sequence back to its start
                    cell.ezSeqStep, cell.ezSeqRan = 1, false
                else
                    cell.ezSeqStep = stepIndex + 1
                end
            end
        end
    end
    if anyRunning then
        SecureCellController.queueSequenceRedraw()
    end
end

-- combat starts (attributes can still be set): a sequence the game holds at its
-- first step with no cast of its own on the way (its click failed) gets a new tag,
-- so the same spell cast elsewhere in combat cannot move it on
function ns:RestartIdleLeftClickSequences()
    if InCombatLockdown and InCombatLockdown() then return end
    local board = self.boardFrame
    if not (board and board.buffCells) then return end
    local now = GetTime()
    for _, cell in ipairs(board.buffCells) do
        if cell.ezSeqSteps and cell.ezSeqRan and sequenceStepIndex(cell) == 1 then
            local onItsWay = cell.ezSeqOwnCast and (now - (cell.ezSeqOwnCastAt or 0)) < SEQ_CAST_MAX
            if not onItsWay then
                restartSequenceNow(cell)
            end
        end
    end
end

-- the game restarts its sequences when combat ends and on death, and the target
-- cell's one on a new target; true when a running one was restarted
function ns:ResetLeftClickSequences(targetOnly)
    local board = self.boardFrame
    if not (board and board.buffCells) then return false end
    local anyRunning = false
    for _, cell in ipairs(board.buffCells) do
        if cell.ezSeqSteps and (not targetOnly or cell.ezSeqTargetReset) then
            if cell.ezSeqRan then
                cell.ezSeqRedraw = true
                anyRunning = true
            end
            cell.ezSeqRan, cell.ezSeqStep = false, 1
        end
    end
    return anyRunning
end

-- Ctrl + wheel choices kept on the cell for the secure snippet that handles the wheel
-- in combat (UI/MicroBoard.lua): ezw-n count, ezw-1..n cast texts, ezw-i the current one
function SecureCellController.storeWheelChoices(cell, state)
    local list = cell.ezWheelChoices or {}
    cell.ezWheelChoices = list
    wipe(list)
    local current = 1
    local slot1 = state and state.slot1Choice
    local slot1Key = slot1 and slot1.buffDef and slot1.buffDef.key
    if state and type(state.validChoices) == "table" then
        for _, choice in ipairs(state.validChoices) do
            if choice.buffDef and choice.castSpell then
                list[#list + 1] = choice
                if choice.buffDef.key == slot1Key then current = #list end
            end
        end
    end
    local count = (#list >= 2) and #list or 0
    local assign = SecureCellController.assignAttrIfChanged
    for index = 1, math.max(count, cell.ezWheelStored or 0) do
        assign(cell, "ezw-" .. index, (index <= count) and list[index].castSpell or nil)
    end
    cell.ezWheelStored = count
    assign(cell, "ezw-n", count)
    assign(cell, "ezw-i", current)
end

-- the secure snippet has put a buff picked with Ctrl + wheel in combat on the left
-- click: follow it in the display, and keep it after combat like a pick made out of it
local PICK_ATTRS = { "type1", "spell1", "ctrl-type1", "ctrl-spell1", "ezw-i" }
function ns:OnCombatWheelPick(cell, index)
    local choice = cell and cell.ezWheelChoices and cell.ezWheelChoices[tonumber(index) or 0]
    local unit = cell and cell.unit
    if not (choice and choice.buffDef and unit) then return end
    -- changed behind the applied-attribute cache: set them again after combat
    cell._appliedAttrs = cell._appliedAttrs or {}
    for _, attr in ipairs(PICK_ATTRS) do
        cell._appliedAttrs[attr] = STALE_ATTR
    end
    cell.ezPickedLeft = choice
    cell.boundLClickBuff = choice.castSpell
    cell.boundCtrlLClickBuff = choice.castSpell
    self.unitWheelBuffKey[unit] = choice.buffDef.key
    self.unitWheelBuffWasActive[unit] = choice.isActive and true or false
    pcall(self.ScanUnitState, self, unit)
    if self.UpdateSingleUnitCell then
        self:UpdateSingleUnitCell(unit)
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

    -- the bound* fields drive the badge/tooltip; in combat the secure attributes stay frozen,
    -- so keep showing what a click will really cast until they can be re-applied
    -- (a cast sequence's current step is followed in the display, UI/MicroBoard.lua)
    if InCombatLockdown and InCombatLockdown() then
        self.pendingSecureUpdate = true
        return
    end

    local assign = SecureCellController.assignAttrIfChanged
    local seqText = SecureCellController.prepareLeftClickSequence(cell, unit, state, buff1Spell)
    -- a Ctrl + wheel pick made in combat ends here: the scan has taken it over
    cell.ezPickedLeft = nil

    cell.boundLClickBuff = buff1Spell
    cell.boundRClickBuff = buff2Spell
    cell.boundLClickDispel = nil
    cell.boundRClickDispel = nil
    cell.boundCtrlLClickBuff = buff1Spell
    cell.boundCtrlRClickBuff = buff2Spell

    assign(cell, "unit", unit)
    assign(cell, "shift-type1", nil)
    assign(cell, "shift-spell1", nil)
    assign(cell, "alt-type1", "target")

    if seqText then
        -- two or more buffs to cast in turn: the same order in and out of combat
        assign(cell, "type1", "macro")
        assign(cell, "macrotext1", seqText)
        assign(cell, "spell1", nil)
        assign(cell, "ctrl-type1", "macro")
        assign(cell, "ctrl-macrotext1", seqText)
        assign(cell, "ctrl-spell1", nil)
    elseif buff1Spell then
        assign(cell, "type1", "spell")
        assign(cell, "spell1", buff1Spell)
        assign(cell, "ctrl-type1", "spell")
        assign(cell, "ctrl-spell1", buff1Spell)
        assign(cell, "macrotext1", nil)
        assign(cell, "ctrl-macrotext1", nil)
    else
        assign(cell, "type1", "target")
        assign(cell, "spell1", nil)
        assign(cell, "ctrl-type1", nil)
        assign(cell, "ctrl-spell1", nil)
        assign(cell, "macrotext1", nil)
        assign(cell, "ctrl-macrotext1", nil)
    end
    SecureCellController.storeWheelChoices(cell, state)

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
    self.engineInitialized = true
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
    "PLAYER_DEAD",
    "ADDON_RESTRICTION_STATE_CHANGED",
    "BAG_UPDATE_DELAYED",
}
for _, evName in ipairs(EVENTS_TO_REGISTER) do
    pcall(eventFrame.RegisterEvent, eventFrame, evName)
end
-- the player's own casts, for the left-click sequences (ns:OnSequenceCastSent)
for _, evName in ipairs({ "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_FAILED_QUIET", "UNIT_SPELLCAST_INTERRUPTED" }) do
    if not (eventFrame.RegisterUnitEvent and pcall(eventFrame.RegisterUnitEvent, eventFrame, evName, "player")) then
        pcall(eventFrame.RegisterEvent, eventFrame, evName)
    end
end

-- In a raid, aura changes arrive many times a second; they are collected here and
-- each changed unit is scanned once per 0.1 s instead of once per event.
local pendingAuraUnits = {}
local castRescanPending = false
local function boardIsShown()
    return EzWoW_SpellControlDB and EzWoW_SpellControlDB.showBoard and ns.boardFrame and ns.boardFrame:IsShown()
end
local function flushPendingAuraUnits()
    for unitRef in pairs(pendingAuraUnits) do
        pendingAuraUnits[unitRef] = nil
        if ns.unitStates[unitRef] then
            pcall(ns.ScanUnitState, ns, unitRef)
            if ns.UpdateSingleUnitCell then
                ns:UpdateSingleUnitCell(unitRef)
            end
        end
    end
end

local rangeTickerElapsed = 0
local auraFlushElapsed = 0
eventFrame:SetScript("OnUpdate", function(_, elapsed)
    local dtVal = elapsed or 0
    rangeTickerElapsed = rangeTickerElapsed + dtVal
    auraFlushElapsed = auraFlushElapsed + dtVal

    if auraFlushElapsed >= 0.1 then
        auraFlushElapsed = 0
        if next(pendingAuraUnits) then flushPendingAuraUnits() end
    end

    -- full rescan (range, buffs): 0.4 s in a party, 1 s in a raid of up to 40
    local fullScanInterval = (IsInRaid and IsInRaid()) and 1.0 or 0.4
    if rangeTickerElapsed >= fullScanInterval then
        rangeTickerElapsed = 0
        if EzWoW_SpellControlDB and EzWoW_SpellControlDB.showBoard and ns.boardFrame and ns.boardFrame:IsShown() then
            wipe(pendingAuraUnits)
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
        if not ns.engineInitialized then
            ns:InitializeSpellControlEngine()
        else
            -- later loading screens: the board already exists, only refresh the roster and cells
            if InCombatLockdown and InCombatLockdown() then
                ns.pendingSecureUpdate = true
            else
                ns:RebuildActiveUnits()
                if ns.LayoutBoardCells then
                    ns:LayoutBoardCells()
                end
            end
            ns:ScanAllActiveUnits()
        end
    elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then
        ns:UpdateRestrictionState(arg1, arg2)
        ns:ScanAllActiveUnits()
    elseif event == "SPELLS_CHANGED" or event == "LEARNED_SPELL_IN_TAB" or event == "PLAYER_LEVEL_UP" or (event == "UNIT_PET" and arg1 == "player") then
        ns:ClearSequenceSpellCache()
        ns:ScanLearnedSpells()
        if not (InCombatLockdown and InCombatLockdown()) and ns.LayoutBoardCells then
            ns:LayoutBoardCells()
        end
        ns:ScanAllActiveUnits()
        if ns.RefreshSettingsTexts then
            ns:RefreshSettingsTexts()
        end
    elseif event == "GROUP_ROSTER_UPDATE" then
        -- "party2" / "raid5" may be someone else now
        if ns.unitWheelBuffKey then wipe(ns.unitWheelBuffKey) end
        if ns.unitWheelBuffWasActive then wipe(ns.unitWheelBuffWasActive) end
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
    elseif event == "PLAYER_TARGET_CHANGED" then
        ns:ResetLeftClickSequences(true)
        ns:ScanCCTargetState()
        if InCombatLockdown and InCombatLockdown() then
            ns.pendingSecureUpdate = true
            ns:ScanAllActiveUnits()
        else
            -- the cells follow the "target" unit by themselves; only when the target cell
            -- appears or disappears does the cell count change and a relayout is needed
            local hasTargetCell = false
            for _, unitRef in ipairs(ns.activeUnits) do
                if unitRef == "target" then
                    hasTargetCell = true
                    break
                end
            end
            local wantTargetCell = ns:ShouldShowTargetUnit() and true or false
            if wantTargetCell ~= hasTargetCell then
                ns:RebuildActiveUnits()
                if ns.LayoutBoardCells then
                    ns:LayoutBoardCells()
                end
                ns:ScanAllActiveUnits()
            else
                pcall(ns.ScanUnitState, ns, "target")
                if ns.UpdateSingleUnitCell then
                    ns:UpdateSingleUnitCell("target")
                end
            end
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
        if unitRef then
            -- units not on the board (raid groups turned off) are ignored;
            -- the OnUpdate ticker rescans the board regularly anyway
            if ns.unitStates[unitRef] then
                pcall(ns.ScanUnitState, ns, unitRef)
                if ns.UpdateSingleUnitCell then
                    ns:UpdateSingleUnitCell(unitRef)
                end
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
                if event == "UNIT_AURA" and IsInRaid and IsInRaid() then
                    pendingAuraUnits[unitRef] = true
                else
                    pcall(ns.ScanUnitState, ns, unitRef)
                    if ns.UpdateSingleUnitCell then
                        ns:UpdateSingleUnitCell(unitRef)
                    end
                end
            end
        else
            ns:ScanAllActiveUnits()
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- auras changed by the cast arrive through UNIT_AURA; one rescan after a cast is
        -- only needed out of combat (secure cell attributes), and only while the board is shown
        local unitRef = safeVal(arg1)
        if unitRef == "player" or unitRef == "pet" then
            -- left-click cast sequences may have moved on (in combat too)
            ns:OnSequenceSpellCast(safeVal(arg3), safeVal(arg2))
        end
        if (unitRef == "player" or unitRef == "pet") and not castRescanPending
            and not (InCombatLockdown and InCombatLockdown()) and boardIsShown()
            and C_Timer and C_Timer.After then
            castRescanPending = true
            C_Timer.After(0.2, function()
                castRescanPending = false
                if (InCombatLockdown and InCombatLockdown()) or not boardIsShown() then return end
                wipe(pendingAuraUnits)
                ns:ScanAllActiveUnits()
            end)
        end
    elseif event == "UNIT_SPELLCAST_SENT" then
        if safeVal(arg1) == "player" then
            ns:OnSequenceCastSent(safeVal(arg3), safeVal(arg4))
        end
    elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_FAILED_QUIET" or event == "UNIT_SPELLCAST_INTERRUPTED" then
        if safeVal(arg1) == "player" then
            ns:OnSequenceCastEnded(safeVal(arg2), safeVal(arg3))
        end
    elseif event == "BAG_UPDATE_DELAYED" then
        -- reagent count for the group buff (board header warning)
        if ns.RefreshBuffHeaderReagent then
            ns:RefreshBuffHeaderReagent()
        end
    elseif event == "PLAYER_DEAD" then
        if ns:ResetLeftClickSequences(false) then
            SecureCellController.queueSequenceRedraw()
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        ns:RestartIdleLeftClickSequences()
        ns:ScanAllActiveUnits()
    elseif event == "PLAYER_REGEN_ENABLED" then
        ns.pendingSecureUpdate = false
        ns:ResetLeftClickSequences(false)
        if ns.combatWheelPending and ns.InstallCombatWheel then
            ns:InstallCombatWheel()
        end
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
