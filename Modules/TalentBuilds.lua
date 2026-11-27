--===========================================================================
-- EzWoW - Spell Control
-- Modules/TalentBuilds.lua : "Recommended talents" button on the talent
--                            window; spends free points along a build
--===========================================================================
local ADDON_NAME, ns = ...

local TEXT = {
    koKR = {
        button = "추천 특성",
        menuTitle = "추천 특성 (%s)",
        tipTitle = "추천 특성",
        tip1 = "직업별 추천 빌드 순서대로 남은 특성 포인트를 넣습니다.",
        tip2 = "넣은 뒤 적용할지 한 번 더 묻습니다.",
        leveling = "레벨업 빌드는 레벨이 오를 때마다 다시 누르면 이어서 찍습니다. 만렙 빌드는 던전·공격대 등 용도별로 고릅니다.",
        tipOrder = "순서와 다르게 찍어 둔 포인트가 있어도 빌드에 있는 특성이면 이어서 채웁니다.",
        tipFit = "|cff55ff55●|r 표시: 지금 찍힌 특성 그대로 이어 갈 수 있는 빌드",
        combat = "전투 중에는 특성을 바꿀 수 없습니다.",
        noApi = "이 클라이언트에서는 특성을 자동으로 넣을 수 없습니다.",
        noConfig = "특성 정보를 읽지 못했습니다. 특성 창을 한 번 열고 다시 시도해 주세요.",
        noBuilds = "이 직업의 추천 빌드가 없습니다.",
        nothing = "넣을 포인트가 없습니다 (남은 포인트가 없거나 이미 이 빌드대로 찍혀 있습니다).",
        blocked = "남은 포인트 %d개는 넣지 못했습니다. 다음 특성(%s)이 아직 열리지 않았습니다.",
        offBuild = "이 빌드에 없는 특성에 %d포인트가 있습니다. 빌드대로 맞추려면 특성을 초기화한 뒤 다시 누르세요.",
        role_dps = "딜러", role_tank = "탱커", role_healer = "힐러",
        levelRange = "Lv 10~60",
        last = "이어서",
        fitTip = "지금 찍힌 특성 그대로 이어 갈 수 있습니다.",
        offTip = "이 빌드에 없는 특성에 %d포인트가 있습니다.",
        confirm = "|cffffd100%s|r\n\n특성 포인트 %d개를 넣었습니다.\n지금 적용할까요?",
        apply = "적용",
        cancel = "취소",
        applied = "추천 특성을 적용했습니다: %s (%d포인트)",
        failed = "적용하지 못했습니다. 특성 창의 \"변경 사항 적용\"을 직접 눌러 주세요.",
        rolledBack = "넣은 포인트를 되돌렸습니다.",
    },
    enUS = {
        button = "Recommended",
        menuTitle = "Recommended talents (%s)",
        tipTitle = "Recommended talents",
        tip1 = "Spends your free talent points along a recommended build for your class.",
        tip2 = "You are asked once more before the points are applied.",
        leveling = "With the leveling build, click again after each level to continue. Level-60 builds are picked by content (dungeon, raid, ...).",
        tipOrder = "Points you spent out of order are kept when they are part of the build; the rest is filled in.",
        tipFit = "|cff55ff55●|r: builds you can continue from your current talents",
        combat = "Talents cannot be changed in combat.",
        noApi = "Talents cannot be set automatically on this client.",
        noConfig = "Could not read your talents. Open the talent window once and try again.",
        noBuilds = "No recommended builds for this class.",
        nothing = "No points to spend (none left, or already spent along this build).",
        blocked = "%d points were left unspent: the next talent (%s) is not open yet.",
        offBuild = "%d points are in talents this build does not use. Reset your talents and click again to follow it exactly.",
        role_dps = "DPS", role_tank = "Tank", role_healer = "Healer",
        levelRange = "Lv 10-60",
        last = "Continue",
        fitTip = "You can continue it from your current talents.",
        offTip = "%d points are in talents this build does not use.",
        confirm = "|cffffd100%s|r\n\n%d talent points were placed.\nApply them now?",
        apply = "Apply",
        cancel = "Cancel",
        applied = "Recommended talents applied: %s (%d points)",
        failed = "Could not apply. Press the talent window's apply button yourself.",
        rolledBack = "The placed points were taken back.",
    },
}

local function T(key)
    local code = (ns.GetActiveLocaleCode and ns:GetActiveLocaleCode()) or GetLocale()
    local tbl = TEXT[code] or TEXT.enUS
    return tbl[key] or TEXT.enUS[key] or key
end

local function isKorean()
    local code = (ns.GetActiveLocaleCode and ns:GetActiveLocaleCode()) or GetLocale()
    return code == "koKR"
end

local function say(msg)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99EzWoW - Spell Control|r: " .. tostring(msg))
    end
end

local function specName(key)
    local spec = (ns.TalentBuildSpecs or {})[key]
    return spec and (isKorean() and spec.ko or spec.en) or key
end

local function buildName(build)
    local name = isKorean() and build.ko or build.en
    if build.kind == "level" then name = name .. " (" .. T("levelRange") .. ")" end
    return name
end

local function buildLabel(build)
    return specName(build.spec) .. " (" .. (isKorean() and build.ko or build.en) .. ")"
end

-- the same build across sessions (which one the character used last)
local function buildKey(build)
    return tostring(build.spec) .. "|" .. tostring(build.kind) .. "|" .. tostring(build.en)
end

-----------------------------------------------------------------------------
-- Talent data access
-----------------------------------------------------------------------------
local function activeConfigID()
    if C_ClassTalents and C_ClassTalents.GetActiveConfigID then
        local ok, id = pcall(C_ClassTalents.GetActiveConfigID)
        if ok and id then return id end
    end
    return nil
end

local function nodeRank(configID, nodeID)
    local ok, info = pcall(C_Traits.GetNodeInfo, configID, nodeID)
    if not ok or type(info) ~= "table" then return nil end
    local rank = tonumber(info.ranksPurchased) or tonumber(info.currentRank) or 0
    return rank, info
end

-- ranks in every talent of the character's trees right now: { [nodeID] = rank } (ranked nodes only)
local function currentRanks(configID)
    local ranks = {}
    local ok, cfg = pcall(C_Traits.GetConfigInfo, configID)
    if not ok or type(cfg) ~= "table" or type(cfg.treeIDs) ~= "table" then return ranks end
    for _, treeID in ipairs(cfg.treeIDs) do
        local nok, nodes = pcall(C_Traits.GetTreeNodes, treeID)
        if nok and type(nodes) == "table" then
            for _, nodeID in ipairs(nodes) do
                local rank = nodeRank(configID, nodeID)
                if rank and rank > 0 then ranks[nodeID] = rank end
            end
        end
    end
    return ranks
end

local function finalRanksOf(build)
    if build.final then return build.final end
    local final = {}
    for _, nodeID in ipairs(build.order) do final[nodeID] = (final[nodeID] or 0) + 1 end
    build.final = final
    return final
end

-- points sitting in talents the build never uses (or past the build's rank)
local function offBuildCount(ranks, finalRanks)
    local extra = 0
    for nodeID, rank in pairs(ranks) do
        local want = finalRanks[nodeID] or 0
        if rank > want then extra = extra + rank - want end
    end
    return extra
end
ns.TalentOffBuildCount = offBuildCount

local function nodeName(configID, nodeID)
    local _, info = nodeRank(configID, nodeID)
    local entryID = info and ((info.activeEntry and info.activeEntry.entryID) or (type(info.entryIDs) == "table" and info.entryIDs[1]))
    if not (entryID and C_Traits.GetEntryInfo and C_Traits.GetDefinitionInfo) then return nil end
    local eok, entry = pcall(C_Traits.GetEntryInfo, configID, entryID)
    local defID = eok and type(entry) == "table" and entry.definitionID
    if not defID then return nil end
    local dok, def = pcall(C_Traits.GetDefinitionInfo, defID)
    local spellID = dok and type(def) == "table" and def.spellID
    local name = spellID and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
    if type(name) == "string" and not (issecretvalue and issecretvalue(name)) then return name end
    return nil
end

-- unspent talent points (the trees share one pool)
local function remainingPoints(configID)
    if not (C_Traits.GetTreeCurrencyInfo and C_Traits.GetConfigInfo) then return 0 end
    local ok, cfg = pcall(C_Traits.GetConfigInfo, configID)
    if not ok or type(cfg) ~= "table" or type(cfg.treeIDs) ~= "table" then return 0 end
    local most = 0
    for _, treeID in ipairs(cfg.treeIDs) do
        local cok, list = pcall(C_Traits.GetTreeCurrencyInfo, configID, treeID, false)
        if cok and type(list) == "table" then
            for _, c in ipairs(list) do
                local q = tonumber(c.quantity) or 0
                if q > most then most = q end
            end
        end
    end
    return most
end

local function commit(configID)
    local fn = (C_ClassTalents and C_ClassTalents.CommitConfig) or (C_Traits and C_Traits.CommitConfig)
    if not fn then return false end
    local ok, result = pcall(fn, configID)
    return ok and result ~= false
end

local function rollback(configID)
    if C_Traits and C_Traits.RollbackConfig then pcall(C_Traits.RollbackConfig, configID) end
end

-----------------------------------------------------------------------------
-- Apply
-----------------------------------------------------------------------------
local pending   -- { configID, label, count }

local POPUP = "EZWOW_SPELLCONTROL_TALENT_APPLY"

local function acceptPending()
    local p = pending
    pending = nil
    if not p then return end
    if InCombatLockdown and InCombatLockdown() then
        rollback(p.configID)
        say(T("combat"))
        return
    end
    if commit(p.configID) then
        say(T("applied"):format(p.label, p.count))
    else
        say(T("failed"))
    end
end

local function cancelPending()
    local p = pending
    pending = nil
    if p then
        rollback(p.configID)
        say(T("rolledBack"))
    end
end

local function showConfirm(label, count)
    -- with the gamepad UI on, the game's popup opened from addon code breaks the game's
    -- gamepad navigation: the EzWoW question window then (Libs/EzWoWGamePad: Confirm)
    local pad = ns.GamePad
    if pad and pad.Confirm and pad.IsActive and pad.IsActive() then
        local ok, text = pcall(string.format, T("confirm"), label or "", count or 0)
        pad.Confirm((ok and text or "") .. "\n\n|cff8c8c8cEzWoW - Spell Control|r", acceptPending, cancelPending, T("apply"), T("cancel"))
        return
    end
    if not StaticPopupDialogs or not StaticPopup_Show then
        say(T("failed"))
        return
    end
    StaticPopupDialogs[POPUP] = {
        text = T("confirm") .. "\n\n|cff8c8c8cEzWoW - Spell Control|r",
        button1 = T("apply"),
        button2 = T("cancel"),
        OnAccept = acceptPending,
        OnCancel = function(_, _, reason)
            -- reuse: ApplyTalentBuild already rolled back the old build and staged a new one
            if reason == "override" then return end
            cancelPending()
        end,
        timeout = 0,
        noCancelOnReuse = true,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    StaticPopup_Show(POPUP, label, count)
end

-- whether the game takes the next rank of this talent now (a closed tier or arrow says no)
local function purchasable(configID, nodeID)
    local ok, info = pcall(C_Traits.GetNodeInfo, configID, nodeID)
    if not ok or type(info) ~= "table" then return false end
    if C_Traits.CanPurchaseRank then
        local entryID = (info.activeEntry and info.activeEntry.entryID) or (type(info.entryIDs) == "table" and info.entryIDs[1])
        local cok, can = pcall(C_Traits.CanPurchaseRank, configID, nodeID, entryID)
        if cok and type(can) == "boolean" then return can end
    end
    if type(info.canPurchaseRank) == "boolean" then return info.canPurchaseRank end
    return true     -- no way to ask: PurchaseRank itself answers
end

-- Spends free points along `order`, the earliest wanted point first. A point the game does not take yet (its tier
-- or arrow still closed, e.g. because points went into later talents first) waits, and the next ones are tried;
-- after each point the list starts over, so a point that opened up is taken in its turn (2026-11-27 user: picking
-- the build's last talents early stopped the button). Pass 2 is for a client whose purchase check always says no.
-- Returns the points bought and the first wanted talent that stayed closed.
function ns.SpendTalentOrder(configID, order, api)
    api = api or {}
    local rankOf = api.rank or function(n) return nodeRank(configID, n) or 0 end
    local canBuy = api.can or function(n) return purchasable(configID, n) end
    local buy = api.buy or function(n)
        local ok, result = pcall(C_Traits.PurchaseRank, configID, n)
        return ok and result and true or false
    end
    local left = api.left or function() return remainingPoints(configID) end
    local need, count = {}, {}
    for i, nodeID in ipairs(order) do
        count[nodeID] = (count[nodeID] or 0) + 1
        need[i] = count[nodeID]
    end
    local have = {}
    local function rank(n)
        if have[n] == nil then have[n] = rankOf(n) end
        return have[n]
    end
    local bought = 0
    for pass = 1, 2 do
        local progress = true
        while progress and left() > 0 do
            progress = false
            for i, nodeID in ipairs(order) do
                if rank(nodeID) < need[i] and (pass == 2 or canBuy(nodeID)) and buy(nodeID) then
                    have[nodeID] = rank(nodeID) + 1
                    bought = bought + 1
                    progress = true
                    break
                end
            end
        end
        if left() <= 0 then break end
    end
    local stuck
    for i, nodeID in ipairs(order) do
        if rank(nodeID) < need[i] then stuck = nodeID; break end
    end
    return bought, stuck
end

local function lastKeyStore()
    if type(EzWoW_SpellControlDB) ~= "table" then return nil end
    EzWoW_SpellControlDB.talentLast = type(EzWoW_SpellControlDB.talentLast) == "table" and EzWoW_SpellControlDB.talentLast or {}
    return EzWoW_SpellControlDB.talentLast
end

local function charKey()
    local guid = UnitGUID and UnitGUID("player")
    if type(guid) == "string" and not (issecretvalue and issecretvalue(guid)) then return guid end
    return nil
end

function ns:ApplyTalentBuild(build)
    if InCombatLockdown and InCombatLockdown() then say(T("combat")) return end
    if not (C_Traits and C_Traits.PurchaseRank and C_Traits.GetNodeInfo) then say(T("noApi")) return end
    local configID = activeConfigID()
    if not configID then say(T("noConfig")) return end
    if pending then rollback(pending.configID); pending = nil end

    local label = buildLabel(build)
    local store, key = lastKeyStore(), charKey()
    if store and key then store[key] = buildKey(build) end
    local bought, stuck = ns.SpendTalentOrder(configID, build.order)
    local left = remainingPoints(configID)
    if left > 0 and stuck then
        say(T("blocked"):format(left, nodeName(configID, stuck) or "-"))
    end

    if bought == 0 then
        -- a popup left from an earlier pick would still offer its points (rolled back above)
        if StaticPopup_Hide then pcall(StaticPopup_Hide, POPUP) end
        if not (left > 0 and stuck) then say(T("nothing")) end
        local extra = offBuildCount(currentRanks(configID), finalRanksOf(build))
        if extra > 0 then say(T("offBuild"):format(extra)) end
        return
    end
    local extra = offBuildCount(currentRanks(configID), finalRanksOf(build))
    if extra > 0 then say(T("offBuild"):format(extra)) end
    pending = { configID = configID, label = label, count = bought }
    showConfirm(label, bought)
end

-----------------------------------------------------------------------------
-- Menu
-----------------------------------------------------------------------------
local function classBuilds()
    local _, classFile = UnitClass("player")
    return classFile and ns.TalentBuilds and ns.TalentBuilds[classFile], classFile
end

-- the class's builds grouped by spec, in data order: { { spec = key, builds = { ... } }, ... }
function ns.GroupTalentBuilds(builds)
    local groups, byKey = {}, {}
    for _, b in ipairs(builds or {}) do
        local g = byKey[b.spec]
        if not g then
            g = { spec = b.spec, builds = {} }
            byKey[b.spec] = g
            groups[#groups + 1] = g
        end
        g.builds[#g.builds + 1] = b
    end
    return groups
end

local function addTip(desc, text)
    if desc and desc.SetTooltip and text then
        pcall(desc.SetTooltip, desc, function(tooltip) tooltip:SetText(text, 1, 1, 1, 1, true) end)
    end
end

local function openMenu(owner)
    local builds = classBuilds()
    if not builds or #builds == 0 then say(T("noBuilds")) return end
    if not (MenuUtil and MenuUtil.CreateContextMenu) then say(T("noApi")) return end
    local className = UnitClass("player")
    -- the talents as they are now: a green dot on builds that continue from them
    local configID = C_Traits and C_Traits.GetNodeInfo and activeConfigID()
    local ranks = configID and currentRanks(configID) or nil
    local store, key = lastKeyStore(), charKey()
    local lastKey = store and key and store[key]
    local specs = ns.TalentBuildSpecs or {}
    local function line(b)
        local off = ranks and offBuildCount(ranks, finalRanksOf(b)) or nil
        local dot = (off == nil and "") or (off == 0 and "|cff55ff55●|r ") or "|cff555555●|r "
        return dot .. buildName(b) .. "  |cff999999" .. b.split .. "|r", off
    end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(T("menuTitle"):format(className or ""))
        if lastKey then
            for _, b in ipairs(builds) do
                if buildKey(b) == lastKey then
                    local text = line(b)
                    local desc = root:CreateButton("|cffffd100" .. T("last") .. ":|r " .. specName(b.spec) .. " · " .. text,
                        function() ns:ApplyTalentBuild(b) end)
                    addTip(desc, buildLabel(b))
                    root:CreateDivider()
                    break
                end
            end
        end
        -- "Balance · DPS" then one line per build: "● Leveling (Lv 10-60)  38/0/13"
        for _, g in ipairs(ns.GroupTalentBuilds(builds)) do
            local spec = specs[g.spec]
            local role = spec and spec.role and T("role_" .. spec.role)
            root:CreateTitle(specName(g.spec) .. (role and ("  |cff8c8c8c" .. role .. "|r") or ""))
            for _, b in ipairs(g.builds) do
                local text, off = line(b)
                local desc = root:CreateButton(text, function() ns:ApplyTalentBuild(b) end)
                if off then addTip(desc, off == 0 and T("fitTip") or T("offTip"):format(off)) end
            end
        end
        root:CreateDivider()
        root:CreateTitle("|cff8c8c8cEzWoW - Spell Control|r")
    end)
end

-----------------------------------------------------------------------------
-- Button on the talent window
-----------------------------------------------------------------------------
-- whichever of these is open gets the button
local FRAME_NAMES = {
    "PlayerSpellsFrame", "PlayerTalentFrame", "ClassTalentFrame", "TalentFrame",
}
local button

local function bigEnough(f)
    local w, h = f:GetWidth(), f:GetHeight()
    return type(w) == "number" and type(h) == "number" and w > 500 and h > 300
end

-- a known talent window, or else any large open window named like one
local foundName, learnedName
local function shownHost(scan)
    for _, name in ipairs(FRAME_NAMES) do
        local f = _G[name]
        if type(f) == "table" and f.IsShown and f:IsShown() and bigEnough(f) then
            foundName = name
            learnedName = learnedName or name   -- known window: the full scan is never needed again
            return f
        end
    end
    -- the full scan runs only on a panel-open signal, and only until the window's name is known
    if not scan or learnedName or type(EnumerateFrames) ~= "function" then return nil end
    local f = EnumerateFrames()
    local best, bestArea
    -- some frames are off limits to addons: every call on them goes through pcall
    local function probe(frame)
        local name = frame:GetName()
        if type(name) ~= "string" or not name:find("Talent") or name:find("Inspect") or name:find("%.") then
            return nil
        end
        if not frame:IsVisible() or not bigEnough(frame) then return nil end
        return name, frame:GetWidth() * frame:GetHeight()
    end
    while f do
        local ok, name, area = pcall(probe, f)
        if ok and name and (not bestArea or area > bestArea) then
            best, bestArea, foundName = f, area, name
        end
        local nok, nextFrame = pcall(EnumerateFrames, f)
        f = nok and nextFrame or nil
    end
    if best and foundName then
        learnedName = foundName
        table.insert(FRAME_NAMES, 1, foundName)
    end
    return best
end

local function createButton(host)
    -- made without a parent and put in afterwards: a frame made inside the open talent
    -- window breaks the game's gamepad navigation (Libs/EzWoWGamePad: MakeFrame)
    local make = (ns.GamePad and ns.GamePad.MakeFrame) or CreateFrame
    button = make("Button", nil, host, "UIPanelButtonTemplate")
    button:SetSize(96, 22)
    button:SetText(T("button"))
    button:SetScript("OnClick", function(self) openMenu(self) end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(T("tipTitle"), 1, 0.82, 0)
        GameTooltip:AddLine(T("tip1"), 1, 1, 1, true)
        GameTooltip:AddLine(T("leveling"), 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine(T("tipOrder"), 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine(T("tipFit"), 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine(T("tip2"), 0.8, 0.8, 0.8, true)
        GameTooltip:AddDoubleLine(" ", "EzWoW - Spell Control", 0, 0, 0, 0.5, 0.5, 0.5)
        GameTooltip:Show()
        if _G.EzWoWTooltipTagSizer and _G.EzWoWTooltipTagSizer.Refit then
            pcall(_G.EzWoWTooltipTagSizer.Refit, GameTooltip)
        end
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- put the button on the open talent window (left of its search box)
local function attach(scan)
    local host = shownHost(scan)
    if not host then return end
    if not button then createButton(host) end
    if button.host == host then return end
    if InCombatLockdown and InCombatLockdown() then return end
    button.host = host
    -- next to the talent search box when there is one (drawn on the same
    -- layer, so the tree art does not cover the button)
    local talents = host.TalentsFrame or host
    local search = talents.SearchBox
    local parent = (search and search:GetParent()) or talents
    button:SetParent(parent)
    button:ClearAllPoints()
    if search then
        button:SetPoint("RIGHT", search, "LEFT", -10, 0)
    else
        button:SetPoint("TOPRIGHT", host, "TOPRIGHT", -232, -51)
    end
    button:SetFrameStrata(parent:GetFrameStrata() or "HIGH")
    button:SetFrameLevel(math.max(parent:GetFrameLevel() or 1, search and search:GetFrameLevel() or 0) + 10)
    button:Show()
end

local function attachScan() attach(true) end
local function deferScan()
    if C_Timer and C_Timer.After then C_Timer.After(0, attachScan) else attachScan() end
end
if type(hooksecurefunc) == "function" then
    if type(_G.ToggleTalentFrame) == "function" then
        pcall(hooksecurefunc, "ToggleTalentFrame", deferScan)
    end
    -- the window can also open without ToggleTalentFrame (key binding, micro button)
    if type(_G.ShowUIPanel) == "function" then
        pcall(hooksecurefunc, "ShowUIPanel", function()
            if learnedName then return end
            deferScan()
        end)
    end
end
if C_Timer and C_Timer.NewTicker then
    C_Timer.NewTicker(1, function()
        if button and button.host and button.host:IsShown() then return end
        attach(false)   -- known names only, never the full frame walk
    end)
end

ns.OpenTalentBuildMenu = function() openMenu(button or UIParent) end

-- /추천특성, /eztalent : the same menu from anywhere
SLASH_EZWOWTALENTBUILD1 = "/eztalent"
SLASH_EZWOWTALENTBUILD2 = "/추천특성"
SlashCmdList.EZWOWTALENTBUILD = function(msg)
    if msg == "where" then
        local host = shownHost(true)
        say("talent window: " .. tostring(host and foundName or "none")
            .. ", button: " .. tostring(button and button:IsVisible() and "shown" or "hidden"))
        return
    end
    openMenu(button and button:IsVisible() and button or UIParent)
end
