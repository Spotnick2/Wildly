-- ============================================================================
-- Wildly Forever  –  Pally Power–style Druid buff manager
-- World of Warcraft: Forever 1.60.1  ·  /wildly [show|hide|help]
--
-- Every removed/moved API goes through Wildly.API (WildlyCompat.lua). The
-- buff engine and the window are LibGroupBuffs-1.0's; this file supplies what
-- is Wildly's own: DEFS, the reagent footer, the spec icon and colours, and
-- when the window opens.
--
-- Main frame rows (per group, per buff):
--   [Icon] [██████████████  2  27:54]   ← left-click = Gift of the Wild, or
--                                          the single buff when Gift is not known
--                                        ← right-click = single on 1st missing
--                                        ← mouseover = popover
--
-- Thorns has no group form, so both clicks cast Thorns.
-- ============================================================================

local addonName = "Wildly"

-- ─── Compat layer (WildlyCompat.lua, loaded first) ───────────────────────────
local API = Wildly.API

-- WildlyCompat.lua has already said in chat why Wildly cannot start if the
-- shared library is missing. Stop here rather than building half an addon and
-- failing further down, far from the cause.
if not API then return end

local VERSION = API.AddonVersion(addonName)

-- ─── Sizes ───────────────────────────────────────────────────────────────────
-- The window is LibGroupBuffs' UI.lua; it sizes its own pools from the worst
-- roster the engine can produce. Wildly decides one number: how many members a
-- popover lists, which is also how many pets share a pet row.
local MAX_MEMBERS = 8

-- Library functions are looked up through API at call time, never copied into
-- a local when the file loads: API is shared with every addon that embeds
-- LibGroupBuffs, and a newer copy loading later upgrades it in place.
-- tests/test_bridge.lua fails on a new capture.
local function ItemIcon(...) return API.ItemIcon(...) end
local function KnowsSpell(...) return API.KnowsSpell(...) end

-- The druid class icon: the spec icon when no spec spell is known, and a
-- popover member whose class the client does not report.
local DRUID_ICON = "Interface\\Icons\\ClassIcon_Druid"

-- ─── Buff definitions ────────────────────────────────────────────────────────
--
-- Spell IDs are the source of truth: names are resolved from them at runtime
-- (locale-proof), with the enUS literals as the fallback when the client does
-- not know the spell at all. The IDs are the rank 1 spells; casting by name
-- casts the highest rank known.
--
-- `duration` is only a seed for the timer gradient. The real value is learned
-- from live auras, per spell name, because Forever's durations differ from
-- both TBC and Vanilla and are still moving during the beta.
local DEFS = {
    {
        id          = "mark",
        snglID      = 1126,
        grpID       = 21849,
        sngl        = "Mark of the Wild",
        grp         = "Gift of the Wild",
        fallbackIcon= "Interface\\Icons\\Spell_Nature_Regeneration",
        duration    = 1800,
    },
    {
        -- No group form: both clicks cast Thorns, which is what the TBC
        -- `leftUsesSingle` flag did by hand.
        id          = "thorns",
        snglID      = 467,
        sngl        = "Thorns",
        fallbackIcon= "Interface\\Icons\\Spell_Nature_Thorns",
        duration    = 600,
    },
}

-- The Mark of the Wild def, which the reagent and the help text ask about.
local MARK = DEFS[1]

-- ─── Who the Thorns row covers ──────────────────────────────────────────────
--
-- Thorns is a single-target buff worth keeping on whoever takes the hits, so
-- its row covers only the members its mode names. The engine calls this once
-- per row and uses the result for the stats, the targets, the popover and
-- the clicks alike, so they cannot disagree; an empty list means no row.
--
-- Two traps the TBC code fell into:
--   * "Is this me?" is UnitIsUnit, never `unit == "player"`: in a raid the
--     roster names you raidN.
--   * Never match a raid member by name. Characters have surnames here and
--     UnitName returns only the first name for anyone but the player, so two
--     raiders can share one. The main-tank role comes from GetRaidRosterInfo
--     by index, and belongs to the unit "raid"..index.

-- Pets carry pet unit tokens (pet, partypetN, raidpetN), which is how the
-- engine names them; Thorns is for players.
local function IsPet(unit)
    return unit == "pet" or unit:find("pet%d+$") ~= nil
end

-- The raid's main tank, by roster index. GetRaidRosterInfo's 10th value is
-- the Retail shape, not yet measured on this client (AGENTS.md).
local function IsMainTank(unit)
    local index = tonumber(unit:match("^raid(%d+)$"))
    if not index or not IsInRaid() then return false end
    local role = select(10, GetRaidRosterInfo(index))
    return role == "MAINTANK"
end

local function IsTank(unit)
    if UnitGroupRolesAssigned(unit) == "TANK" then return true end
    return IsMainTank(unit)
end

local function IsSelf(unit)
    return UnitIsUnit(unit, "player") and true or false
end

local function ThornsMembers(members)
    local mode = Wildly_GetThornsMode and Wildly_GetThornsMode() or "default"
    if mode == "disabled" then return {} end
    if mode == "default" then
        mode = (GetNumGroupMembers() > 0) and "tanks" or "self"
    end
    local out = {}
    for _, m in ipairs(members) do
        local unit = m.unit
        if not IsPet(unit) then
            local include
            if mode == "everyone" then
                include = true
            elseif mode == "self" then
                include = IsSelf(unit)
            else -- "tanks"
                include = IsTank(unit)
            end
            if include then out[#out + 1] = m end
        end
    end
    return out
end

local function MembersFor(def, members)
    if def.id ~= "thorns" then return members end
    return ThornsMembers(members)
end

-- ─── The buff engine (LibGroupBuffs-1.0's Engine.lua) ─────────────────────
--
-- Aura reads and the combat-secrecy cache, durations, the roster, group stats,
-- target picking, click mapping and UNIT_AURA filtering are shared with
-- Priestly and Magely. The config accessors are looked up when called, so
-- WildlyConfig.lua can replace them and tests can install their own.
local engine = Wildly.Engine.New({
    defs       = DEFS,
    bucketSize = MAX_MEMBERS,           -- pets are split into popover-sized buckets
    showSolo      = function() return Wildly_ShowSolo() end,
    trackPets     = function() return Wildly_TrackPets() end,
    isBuffEnabled = function(defId) return Wildly_IsBuffEnabled(defId) end,
    membersFor      = MembersFor,
    learnDuration   = function(spell, secs) Wildly_LearnDuration(spell, secs) end,
    learnedDuration = function(spell) return Wildly_GetLearnedDuration(spell) end,
})

local ST_HAS     = Wildly.Engine.STATES.HAS
local ST_MISSING = Wildly.Engine.STATES.MISSING
local ST_UNKNOWN = Wildly.Engine.STATES.UNKNOWN

-- What RefreshSpellData derives from the spellbook, kept until it next runs:
-- the window asks for the icon and the reagent on every rebuild, and in a
-- raid that is every aura burst, while both only change when spells do.
local g_GiftRank, g_SpecIcon

local RefreshDerived   -- defined below, with the spec icon and the reagent

-- Resolve localized names and what this druid knows. Rerun on SPELLS_CHANGED
-- and talent changes: what a druid knows changes as they level.
local function RefreshSpellData()
    engine:RefreshSpells()
    RefreshDerived()
end

local function ClickSpells(def) return engine:ClickSpells(def) end
local function ActiveDefs(groups, ord) return engine:ActiveDefs(groups, ord) end
local function PickTarget(...) return engine:PickTarget(...) end
local function AuraEventIsRelevant(unit, updateInfo)
    return engine:AuraEventIsRelevant(unit, updateInfo)
end

-- ─── State ───────────────────────────────────────────────────────────────────
local g_IsDruid = false
local g_LastGroupSize = 0
local g_LoginAt = 0

-- The roster can arrive a moment after PLAYER_LOGIN: GetNumGroupMembers() may
-- still read 0 at login inside a group. A 0-to-n change that soon is the
-- client catching up, not the player joining, and must not override a close.
-- Not measured on this client (AGENTS.md, in-game list); five seconds is a
-- guess on the safe side - a real invite that soon after login is rare.
local ROSTER_SETTLE_SECONDS = 5

-- Would the window open by itself right now? In a group, or solo mode - and
-- never over a deliberate close.
local function WantsOpen()
    if not WildlyDB or WildlyDB.visible == false then return false end
    return GetNumGroupMembers() > 0 or Wildly_ShowSolo()
end

-- Settings writes go through WildlyConfig's single write path. Guarded: if
-- WildlyConfig failed to load, a bare call would throw from a drag or a
-- refresh instead of quietly doing nothing.
local function SetConfig(key, value)
    if Wildly_SetConfig then Wildly_SetConfig(key, value) end
end

-- ─── Spec icon ───────────────────────────────────────────────────────────────
--
-- From a spell only that tree's 31-point talent teaches, by ID. The TBC scan
-- of talent tabs is gone - GetNumTalentTabs / GetTalentTabInfo do not exist on
-- this client - and Tree of Life and Mangle are TBC spells.
local SPEC_ICON_SPELLS = {
    { id = 24858, icon = "Interface\\Icons\\Spell_Nature_ForceOfNature" },  -- Moonkin Form
    { id = 18562, icon = "Interface\\Icons\\INV_Relics_IdolofRejuvenation" }, -- Swiftmend
    { id = 17007, icon = "Interface\\Icons\\Spell_Nature_UnyeildingStamina" }, -- Leader of the Pack
}

local function FindSpecIcon()
    for _, s in ipairs(SPEC_ICON_SPELLS) do
        if KnowsSpell(s.id) then return s.icon end
    end
    return DRUID_ICON
end

local function GetSpecIcon() return g_SpecIcon or DRUID_ICON end

-- ─── Colours ─────────────────────────────────────────────────────────────────
-- Wildly's orange, #ff7c0a, where Priestly has its blue. Everything else is
-- the library's default.
local APPEARANCE = {
    border     = { 1.00, 0.49, 0.04, 0.85 },
    header     = { 0.16, 0.08, 0.03, 0.98 },
    headerLine = { 1.00, 0.49, 0.04, 0.55 },
    footerLine = { 0.95, 0.47, 0.06, 0.40 },
    popBorder  = { 0.95, 0.47, 0.06, 1 },
    popDivider = { 0.95, 0.47, 0.06, 0.55 },
}

local function Appearance()
    local look = { icon = GetSpecIcon() }
    for k, v in pairs(APPEARANCE) do look[k] = v end
    return look
end

-- ─── Reagent footer ──────────────────────────────────────────────────────────
--
-- Gift of the Wild's reagent, for the rank the druid knows. Read from the
-- spellbook's rank subtext, not assumed from level. Rank 3 (Wild Quillvine) is
-- TBC's, at level 70, and cannot exist at Forever's cap of 60; a rank this
-- table does not know shows no reagent rather than a guess.
local GIFT_REAGENTS = {
    [1] = 17021,   -- Wild Berries
    [2] = 17026,   -- Wild Thornroot
}

-- Highest rank of Gift of the Wild known, 0 if none. A spellbook walk, so
-- only RefreshDerived calls it.
local function FindGiftRank()
    if not MARK.hasGroup then return 0 end
    return API.GetSpellRank(MARK.grp)
end

local function GetGiftRank() return g_GiftRank or 0 end

RefreshDerived = function()
    g_GiftRank = FindGiftRank()
    g_SpecIcon = FindSpecIcon()
end

local function FooterItems()
    local items = {}
    -- No Mark row, no reason to count its reagent.
    if Wildly_IsBuffEnabled and not Wildly_IsBuffEnabled("mark") then return items end
    local reagent = GIFT_REAGENTS[GetGiftRank()]
    if reagent then
        items[#items + 1] = {
            itemID = reagent, icon = ItemIcon(reagent), usedBy = MARK.grp,
            color = function(count)
                if count >= 50 then return 0.20, 1.00, 0.20 end
                if count >= 25 then return 1.00, 0.88, 0.10 end
                return 1.00, 0.22, 0.10
            end,
        }
    end
    return items
end

-- ─── The window (LibGroupBuffs-1.0's UI.lua) ─────────────────────────────────
--
-- Rows, popover, clicks, dragging, the ticker and what combat defers are shared
-- with Priestly and Magely. Wildly supplies its title, colours, spec icon,
-- reagents and config, and decides when the window opens; the events and
-- slash commands below call the ui's methods.
local ui = Wildly.UI.New({
    engine  = engine,
    owner   = addonName,
    title   = "|cffff7c0aWildly|r",
    version = VERSION,
    appearance = Appearance,
    unknownClassIcon = DRUID_ICON,
    footerItems = FooterItems,
    alpha       = function() return Wildly_GetFrameAlpha and Wildly_GetFrameAlpha() or 0.96 end,
    -- `Wildly_FrameLocked and` is not decoration: if WildlyConfig fails to
    -- load, calling a nil global would throw - silently, errors are off by
    -- default here - and kill the drag. Short-circuiting leaves the window
    -- draggable, which is the safe way to be wrong.
    locked      = function() return Wildly_FrameLocked and Wildly_FrameLocked() or false end,
    popoverSide = function() return Wildly_PopoverSide and Wildly_PopoverSide() or "auto" end,
    showClickHints = function() return not Wildly_ShowClickHints or Wildly_ShowClickHints() end,
    getPos = function()
        if not WildlyDB then return nil, "WildlyDB was nil" end
        if not WildlyDB.pos then return nil, "WildlyDB.pos was nil" end
        return WildlyDB.pos
    end,
    setPos     = function(pos) SetConfig("pos", pos) end,
    setVisible = function(visible) SetConfig("visible", visible) end,
    -- The window parents secure buttons, so in combat the client refuses to
    -- hide it. Every way of closing - the X button, /wildly hide, the toggle -
    -- lands here, so none of them looks ignored.
    onCloseDeferred = function()
        DEFAULT_CHAT_FRAME:AddMessage("|cffff7c0a[Wildly]|r The window closes when you leave combat.")
    end,
})

-- ─── Global hooks for WildlyConfig.lua ──────────────────────────────────────

function Wildly_ScheduleRefresh()
    ui:ScheduleRefresh()
end

-- Force a full rebuild (used when config changes affect layout). Only of a
-- window that is open: ui:Open shows the window and records it as visible, so
-- rebuilding a closed one would undo the player's close for a settings change.
-- In combat the rows cannot change; the library rebuilds a visible window at
-- combat end.
function Wildly_ForceRebuild()
    if InCombatLockdown() or not ui:IsVisible() then return end
    ui:Open(0.1)
end

-- Called when the solo checkbox is toggled in config. Not refused in combat:
-- ui:Open and ui:Close both remember what was asked and carry it out when the
-- fight ends, so ticking the box mid-fight is honoured rather than lost.
function Wildly_OnSoloToggle(enabled)
    if not g_IsDruid then return end
    if enabled then
        if not ui:IsVisible() and g_IsDruid then
            SetConfig("visible", true)
            ui:Open(0.1)
        end
    elseif GetNumGroupMembers() == 0 then
        ui:Close()
    end
end

function Wildly_ApplyAlpha()
    ui:ApplyAppearance()
end

-- ─── Events ──────────────────────────────────────────────────────────────────

-- RegisterEvent throws on an unknown event name on this client, so every
-- registration goes through the bridge, which reports what it skipped rather
-- than leaving a handler silently dead.
local evtFrame = CreateFrame("Frame", "WildlyEvents")
Wildly.RegisterEvents(evtFrame,
    "PLAYER_LOGIN",
    "READY_CHECK",
    "UNIT_AURA",
    "UNIT_PET",
    "RAID_ROSTER_UPDATE",
    "GROUP_ROSTER_UPDATE",
    "PLAYER_TALENT_UPDATE",
    "ACTIVE_TALENT_GROUP_CHANGED",
    "PLAYER_REGEN_ENABLED",
    "BAG_UPDATE",
    "SPELLS_CHANGED")

evtFrame:SetScript("OnEvent", function(self, event, arg1, arg2)
    if event == "PLAYER_LOGIN" then
        local _, cls = UnitClass("player")
        g_IsDruid = (cls == "DRUID")
        -- Class-specific: on anyone else Wildly builds nothing and says nothing.
        if not g_IsDruid then return end

        Wildly_EnsureDefaults()
        if WildlyDB.visible == nil then SetConfig("visible", true) end

        -- Resolve localized spell names and what this druid knows before
        -- anything reads DEFS. Init applies the colours and opacity.
        RefreshSpellData()
        ui:Init()

        -- Auto-open in a group (or solo mode) - unless the window was
        -- deliberately closed, which is a preference that should survive a
        -- reload.
        g_LastGroupSize = GetNumGroupMembers()
        g_LoginAt = GetTime()
        if WantsOpen() then ui:Open(0.6) end

        DEFAULT_CHAT_FRAME:AddMessage(
            "|cffff7c0a[Wildly]|r Loaded. Auto-opens when you join a group. " ..
            "Type |cffffffff/wildly help|r for commands. " ..
            "Type |cffffffff/wildly config|r for options.")
        return
    end

    if not g_IsDruid then return end

    if event == "READY_CHECK" then
        -- A ready check is a good moment to rebuff, but not a reason to
        -- override someone who closed the window.
        if not WildlyDB or WildlyDB.visible ~= false then ui:Open(0.4) end

    elseif event == "UNIT_AURA" then
        if AuraEventIsRelevant(arg1, arg2) then ui:ScheduleRefresh() end

    elseif event == "UNIT_PET" then
        -- Pet summoned or dismissed: rebuild to add/remove pet rows
        ui:ScheduleRefresh()

    elseif event == "RAID_ROSTER_UPDATE" or event == "GROUP_ROSTER_UPDATE" then
        engine:PruneCache()
        local n = GetNumGroupMembers()
        -- Joining a group is the one case that reopens a window the user
        -- closed: that is the addon's advertised behaviour. Any other roster
        -- churn leaves a deliberate close alone.
        local settling = (GetTime() - g_LoginAt) < ROSTER_SETTLE_SECONDS
        local joined = (g_LastGroupSize == 0 and n > 0) and not settling
        g_LastGroupSize = n
        if joined then SetConfig("visible", true) end
        if n > 0 and not ui:IsVisible()
            and (joined or not WildlyDB or WildlyDB.visible ~= false)
        then
            ui:Open(0.5)
        elseif n == 0 and not Wildly_ShowSolo() then
            ui:Close()  -- auto-close, not manual (unless solo mode)
        else
            ui:ScheduleRefresh()
        end

    elseif event == "PLAYER_TALENT_UPDATE" or event == "SPELLS_CHANGED"
        or event == "ACTIVE_TALENT_GROUP_CHANGED"
    then
        -- Newly learned spells change which rows exist, how they cast, the
        -- spec icon and the reagent. In combat only the counts can move; the
        -- rebuild follows the fight.
        -- A window that is not open may have closed itself for want of a
        -- known spell - the spellbook can arrive after PLAYER_LOGIN - so it
        -- opens now if it would have opened then.
        RefreshSpellData()
        ui:ApplyAppearance()
        if ui:IsVisible() and not InCombatLockdown() then
            ui:Open(0.3)
        elseif ui:IsVisible() then
            ui:RefreshFooter()
        elseif WantsOpen() then
            ui:Open(0.3)
        end

    elseif event == "PLAYER_REGEN_ENABLED" then
        -- What combat deferred - a close, a drag, a rebuild, a show.
        ui:OnCombatEnd()

    elseif event == "BAG_UPDATE" then
        if ui:IsVisible() then ui:RefreshFooter() end
    end
end)

-- ─── Slash commands ──────────────────────────────────────────────────────────

local function Say(text) DEFAULT_CHAT_FRAME:AddMessage("|cffff7c0a[Wildly]|r " .. text) end

SLASH_WILDLY1 = "/wildly"
SlashCmdList["WILDLY"] = function(msg)
    local cmd = strtrim(msg or ""):lower()

    -- Class-specific: on anyone else there is no window to show and nothing
    -- to save, so say that once rather than building frames for nothing.
    if not g_IsDruid then
        Say("Wildly manages Druid buffs; it does nothing on this character.")
        return
    end

    if cmd == "help" then
        Say("Commands:")
        DEFAULT_CHAT_FRAME:AddMessage("  |cffffffff/wildly|r            toggle window")
        DEFAULT_CHAT_FRAME:AddMessage("  |cffffffff/wildly show|r       force open")
        DEFAULT_CHAT_FRAME:AddMessage("  |cffffffff/wildly hide|r       close")
        DEFAULT_CHAT_FRAME:AddMessage("  |cffffffff/wildly config|r     open options panel")
        DEFAULT_CHAT_FRAME:AddMessage("  |cffffffff/wildly reset|r      reset window position")
        DEFAULT_CHAT_FRAME:AddMessage("  |cffffffff/wildly pos|r        why the window is where it is")
        DEFAULT_CHAT_FRAME:AddMessage("  |cffffffff/wildly help|r       this message")
        -- Describe the mapping that is actually live: without Gift of the Wild
        -- left-click is single-target.
        Say("Main frame rows:")
        if MARK.hasGroup then
            DEFAULT_CHAT_FRAME:AddMessage("  Left-click   Gift of the Wild (Mark row); Thorns on the Thorns row")
            DEFAULT_CHAT_FRAME:AddMessage("  Right-click  single buff on the first person missing it")
        else
            DEFAULT_CHAT_FRAME:AddMessage("  Left-click   buff the first person missing it")
            DEFAULT_CHAT_FRAME:AddMessage("  Right-click  same (no Gift of the Wild known yet)")
        end
        DEFAULT_CHAT_FRAME:AddMessage("  Mouseover    open per-member popover")
        Say("Popover:")
        DEFAULT_CHAT_FRAME:AddMessage("  Left/Right   buff that person (left casts Gift when known)")
        DEFAULT_CHAT_FRAME:AddMessage("  R = green (in range) / yellow (out of range) / grey (offline)")
        DEFAULT_CHAT_FRAME:AddMessage("  Timer = green >50% / yellow 10-50% / red <10%")
        DEFAULT_CHAT_FRAME:AddMessage("  ? = buff state unreadable right now (combat aura secrecy)")

    elseif cmd == "config" or cmd == "options" or cmd == "settings" or cmd == "opt" then
        if Wildly_OpenConfig then Wildly_OpenConfig() end

    elseif cmd == "reset" then
        if ui:ResetPosition() then
            Say("Window position reset.")
        else
            -- Re-anchoring the window is blocked in combat: it parents secure
            -- buttons, so the move waits.
            Say("Window position reset - it moves when combat ends.")
        end
        -- Reset deliberately ignores the lock, so a locked window dragged
        -- somewhere unreachable can always be recovered. The trap is what
        -- comes next: centred AND still locked reads exactly like "the
        -- position is not saved".
        if Wildly_FrameLocked and Wildly_FrameLocked() then
            Say("|cffffcc00The window is locked|r - untick " ..
                "|cffffffffLock frame position|r in |cffffffff/wildly config|r to move it.")
        end

    elseif cmd == "pos" then
        -- Diagnostic for "the window does not remember where I put it".
        local p = WildlyDB and WildlyDB.pos
        Say("position diagnostic:")
        DEFAULT_CHAT_FRAME:AddMessage("  saved: " .. (p and string.format(
            "%s/%s  %.1f, %.1f", tostring(p.point), tostring(p.relPoint),
            tonumber(p.x) or 0/0, tonumber(p.y) or 0/0) or "|cffff6666nothing saved|r"))
        local restore = ui:RestoreInfo()
        DEFAULT_CHAT_FRAME:AddMessage("  last restore: " .. tostring(restore.log))
        if restore.skips > 0 then
            DEFAULT_CHAT_FRAME:AddMessage(string.format(
                "    (%d refresh%s since, which leave the position alone)",
                restore.skips, restore.skips == 1 and "" or "es"))
        end
        local main = ui:MainFrame()
        if main then
            local pt, rel, relPt, x, y = main:GetPoint()
            DEFAULT_CHAT_FRAME:AddMessage(string.format(
                "  frame now: %s/%s  %.1f, %.1f  (relativeTo %s)",
                tostring(pt), tostring(relPt), tonumber(x) or 0/0, tonumber(y) or 0/0,
                rel and (rel.GetName and rel:GetName() or "unnamed") or "nil"))
        else
            DEFAULT_CHAT_FRAME:AddMessage("  frame now: |cffff6666not built|r")
        end
        DEFAULT_CHAT_FRAME:AddMessage("  locked: " ..
            tostring(Wildly_FrameLocked and Wildly_FrameLocked() or false))

    elseif cmd == "hide" or cmd == "close" then
        ui:Close(true)      -- onCloseDeferred says so if combat refuses it

    elseif cmd == "show" then
        SetConfig("visible", true)
        ui:Update()

    else
        if ui:IsVisible() then
            ui:Close(true)
        else
            SetConfig("visible", true)
            ui:Update()
        end
    end
end

-- ─── Test seam ───────────────────────────────────────────────────────────────
-- Harmless in game; tests/ reaches the file-locals through this.

Wildly._test = {
    DEFS             = DEFS,
    RefreshSpellData = RefreshSpellData,
    ClickSpells      = ClickSpells,
    ActiveDefs       = ActiveDefs,
    PickTarget       = PickTarget,
    MembersFor       = function(def, members) return engine:MembersFor(def, members) end,
    IsTank           = IsTank,
    IsPet            = IsPet,
    AuraEventIsRelevant = AuraEventIsRelevant,
    GetSpecIcon      = GetSpecIcon,
    GetGiftRank      = GetGiftRank,
    FooterItems      = FooterItems,
    Appearance       = Appearance,
    GIFT_REAGENTS    = GIFT_REAGENTS,
    SPEC_ICON_SPELLS = SPEC_ICON_SPELLS,
    DRUID_ICON       = DRUID_ICON,
    states           = { HAS = ST_HAS, MISSING = ST_MISSING, UNKNOWN = ST_UNKNOWN },
    engine           = engine,
    ui               = ui,
    isDruid          = function() return g_IsDruid end,
    UpdateUI         = function() return ui:Update() end,
    UpdatePopover    = function(...) return ui:UpdatePopover(...) end,
    PopoverSide      = function(row) return ui:PopoverSide(row) end,
    ShowClickHint    = function(row) return ui:ShowClickHint(row) end,
    rows             = function() return ui.rows end,
    popRows          = function() return ui.popRows end,
    mainFrame        = function() return ui.main end,
    popFrame         = function() return ui.pop end,
    eventFrame       = function() return evtFrame end,
    CloseUI          = function(...) return ui:Close(...) end,
    RefreshTimers    = function() return ui:RefreshTimers() end,
    RefreshFooter    = function() return ui:RefreshFooter() end,
    -- The footer's buttons are anonymous; find one by the item it shows.
    footerButton     = function(itemID)
        for _, btn in ipairs(ui.footerBtns) do
            if btn._itemID == itemID and btn:IsShown() then return btn end
        end
    end,
}
