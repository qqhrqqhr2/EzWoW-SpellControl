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
        leveling = "레벨업 빌드는 레벨이 오를 때마다 다시 누르면 이어서 찍습니다.",
        combat = "전투 중에는 특성을 바꿀 수 없습니다.",
        noApi = "이 클라이언트에서는 특성을 자동으로 넣을 수 없습니다.",
        noConfig = "특성 정보를 읽지 못했습니다. 특성 창을 한 번 열고 다시 시도해 주세요.",
        noBuilds = "이 직업의 추천 빌드가 없습니다.",
        nothing = "넣을 포인트가 없습니다 (남은 포인트가 없거나 이미 이 빌드대로 찍혀 있습니다).",
        blocked = "%s 다음 포인트를 넣지 못했습니다. 이미 다른 특성에 넣은 포인트가 있으면 빌드와 다를 수 있습니다.",
        offBuild = "주의: 이 빌드에 없는 특성에 %d포인트가 들어 있습니다.",
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
        leveling = "With a leveling build, click again after each level to continue.",
        combat = "Talents cannot be changed in combat.",
        noApi = "Talents cannot be set automatically on this client.",
        noConfig = "Could not read your talents. Open the talent window once and try again.",
        noBuilds = "No recommended builds for this class.",
        nothing = "No points to spend (none left, or already spent along this build).",
        blocked = "Could not spend the next point after %s. Points spent on other talents may differ from the build.",
        offBuild = "Note: %d points are in talents that are not part of this build.",
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

local function buildLabel(build)
    local specs = ns.TalentBuildSpecs or {}
    local spec = specs[build.spec]
    local specName = spec and (isKorean() and spec.ko or spec.en) or build.spec
    local name = isKorean() and build.ko or build.en
    return specName .. " (" .. name .. ")"
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

-- points sitting in talents the build never uses
local function pointsOffBuild(configID, finalRanks)
    local ok, cfg = pcall(C_Traits.GetConfigInfo, configID)
    if not ok or type(cfg) ~= "table" or type(cfg.treeIDs) ~= "table" then return 0 end
    local extra = 0
    for _, treeID in ipairs(cfg.treeIDs) do
        local nok, nodes = pcall(C_Traits.GetTreeNodes, treeID)
        if nok and type(nodes) == "table" then
            for _, nodeID in ipairs(nodes) do
                local rank = nodeRank(configID, nodeID)
                if rank and rank > (finalRanks[nodeID] or 0) then
                    extra = extra + rank - (finalRanks[nodeID] or 0)
                end
            end
        end
    end
    return extra
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

local function showConfirm(label, count)
    if not StaticPopupDialogs or not StaticPopup_Show then
        say(T("failed"))
        return
    end
    StaticPopupDialogs[POPUP] = {
        text = T("confirm") .. "\n\n|cff8c8c8cEzWoW - Spell Control|r",
        button1 = T("apply"),
        button2 = T("cancel"),
        OnAccept = function()
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
        end,
        OnCancel = function(_, _, reason)
            -- reuse: ApplyTalentBuild already rolled back the old build and staged a new one
            if reason == "override" then return end
            local p = pending
            pending = nil
            if p then
                rollback(p.configID)
                say(T("rolledBack"))
            end
        end,
        timeout = 0,
        noCancelOnReuse = true,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    StaticPopup_Show(POPUP, label, count)
end

function ns:ApplyTalentBuild(build)
    if InCombatLockdown and InCombatLockdown() then say(T("combat")) return end
    if not (C_Traits and C_Traits.PurchaseRank and C_Traits.GetNodeInfo) then say(T("noApi")) return end
    local configID = activeConfigID()
    if not configID then say(T("noConfig")) return end
    if pending then rollback(pending.configID); pending = nil end

    local label = buildLabel(build)
    local finalRanks = {}
    for _, nodeID in ipairs(build.order) do
        finalRanks[nodeID] = (finalRanks[nodeID] or 0) + 1
    end

    local have, target = {}, {}
    local bought, lastName = 0, nil
    for _, nodeID in ipairs(build.order) do
        target[nodeID] = (target[nodeID] or 0) + 1
        if have[nodeID] == nil then
            have[nodeID] = nodeRank(configID, nodeID) or 0
        end
        if have[nodeID] < target[nodeID] then
            local ok, result = pcall(C_Traits.PurchaseRank, configID, nodeID)
            if not ok or not result then
                -- running out of points is the normal end; anything else is reported
                if remainingPoints(configID) > 0 then
                    say(T("blocked"):format(lastName or "-"))
                end
                break
            end
            have[nodeID] = have[nodeID] + 1
            bought = bought + 1
        end
        local _, info = nodeRank(configID, nodeID)
        local entryID = info and info.activeEntry and info.activeEntry.entryID
        if entryID and C_Traits.GetEntryInfo and C_Traits.GetDefinitionInfo then
            local eok, entry = pcall(C_Traits.GetEntryInfo, configID, entryID)
            local defID = eok and entry and entry.definitionID
            if defID then
                local dok, def = pcall(C_Traits.GetDefinitionInfo, defID)
                local spellID = dok and def and def.spellID
                local name = spellID and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
                if type(name) == "string" then lastName = name end
            end
        end
    end

    if bought == 0 then
        -- a popup left from an earlier pick would still offer its points (rolled back above)
        if StaticPopup_Hide then pcall(StaticPopup_Hide, POPUP) end
        say(T("nothing"))
        return
    end
    local extra = pointsOffBuild(configID, finalRanks)
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

local function openMenu(owner)
    local builds = classBuilds()
    if not builds or #builds == 0 then say(T("noBuilds")) return end
    if not (MenuUtil and MenuUtil.CreateContextMenu) then say(T("noApi")) return end
    local className = UnitClass("player")
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(T("menuTitle"):format(className or ""))
        -- one line per build: "Feral (Tank)  0/34/17"
        for _, b in ipairs(builds) do
            local text = buildLabel(b) .. "  |cff999999" .. b.split .. "|r"
            root:CreateButton(text, function() ns:ApplyTalentBuild(b) end)
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
    button = CreateFrame("Button", nil, host, "UIPanelButtonTemplate")
    button:SetSize(96, 22)
    button:SetText(T("button"))
    button:SetScript("OnClick", function(self) openMenu(self) end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(T("tipTitle"), 1, 0.82, 0)
        GameTooltip:AddLine(T("tip1"), 1, 1, 1, true)
        GameTooltip:AddLine(T("leveling"), 0.8, 0.8, 0.8, true)
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
