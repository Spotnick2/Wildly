------------------------------------------------------------
-- test_frames.lua - run every script handler, event and slash command the
-- addon installs.
--
-- The other test files assert behaviour; this one exists to *execute* code,
-- because tests/wow_stubs.lua fails on the read of any global it does not
-- stub, and a global that quietly went away in the move to the Retail
-- codebase only shows up when the handler that uses it actually runs. That is
-- how Priestly shipped a call to MouseIsOver: nothing ran the popover's hover
-- poll, and the first sign was a Lua error on mouseover in game.
--
--   & 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_frames.lua
------------------------------------------------------------

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")
local T = H.loadAddon()

local function setup(known, ranks)
    WoW.reset()
    WildlyDB = nil
    Wildly_EnsureDefaults()
    H.TeachSpells(known or { "MARK_SINGLE", "THORNS" }, ranks)
    T.RefreshSpellData()
    WoW.SetUnit("player", { name = "Karuzo Elegia", guid = "P0", class = "DRUID" })
    WoW.SetUnit("party1", { name = "Zoruka Mortalis", guid = "P1", class = "WARRIOR" })
    WoW.groupMembers = 2
    WoW.dispatch("PLAYER_LOGIN")
    WoW.flushTimers()
    T.UpdateUI()
end

-- Call a frame's script handler, failing the test rather than the run if it
-- throws - including on an unstubbed global.
local function runScript(frame, script, ...)
    if not frame then H.check(false, "no frame for " .. script) return end
    local fn = frame._scripts and frame._scripts[script]
    if not fn then H.check(false, "no " .. script .. " handler installed") return end
    local ok, err = pcall(fn, frame, ...)
    H.check(ok, script .. " ran without error: " .. tostring(err))
    return ok
end

local function said(from)
    return table.concat(WoW.messages, " ", from + 1, #WoW.messages)
end

local function firstRow()
    for _, r in ipairs(T.rows()) do
        if r._active then return r end
    end
end

setup()

------------------------------------------------------------
-- Login
------------------------------------------------------------

H.check(T.isDruid(), "a druid is recognised at login")
H.check(said(0):find("Loaded", 1, true) ~= nil, "and told Wildly loaded: " .. said(0))
H.eq(WildlyDB.visible, true, "the window starts visible by preference")

------------------------------------------------------------
-- The popover hover poll
------------------------------------------------------------

local row = firstRow()
H.check(row ~= nil, "there is a row to hover")
runScript(row, "OnEnter")
local pop = T.popFrame()
H.check(pop and pop:IsShown(), "mousing over a row opens the popover")
WoW.mouseOver[pop] = true
runScript(pop, "OnUpdate", 5.0)
H.check(pop:IsShown(), "the popover stays open while the mouse is over it")
WoW.mouseOver[pop] = nil
runScript(pop, "OnUpdate", 5.0)
H.check(not pop:IsShown(), "and closes once the mouse leaves")

------------------------------------------------------------
-- Row and popover-row handlers
------------------------------------------------------------

for _, button in ipairs({ "LeftButton", "RightButton" }) do
    runScript(row, "PreClick", button)
    runScript(row, "PostClick", button)
end
runScript(row, "OnEnter")
runScript(row, "OnLeave")
local pr = T.popRows()[1]
runScript(pr, "OnEnter")
runScript(pr, "OnLeave")
runScript(pr, "PreClick", "LeftButton")
runScript(pr, "PostClick", "LeftButton")

-- An offline member takes the tooltip branch in the popover's OnEnter.
WoW.units.party1.connected = false
T.UpdateUI()
runScript(firstRow(), "OnEnter")
runScript(T.popRows()[2], "OnEnter")
WoW.units.party1.connected = true

------------------------------------------------------------
-- Main frame: ticker, drag, close
------------------------------------------------------------

local main = T.mainFrame()
runScript(main, "OnUpdate", 1.0)
runScript(main, "OnUpdate", 5.0)
H.check(pcall(T.RefreshTimers), "RefreshTimers runs")
H.check(pcall(T.RefreshFooter), "RefreshFooter runs")

local drag = main.dragHandle
runScript(drag, "OnDragStart")
WildlyDB.pos = nil
runScript(drag, "OnDragStop")
H.check(WildlyDB.pos ~= nil and WildlyDB.pos.point ~= nil, "dragging the frame saves its position")

WildlyDB.lockFrame = true
main._moving = false
runScript(drag, "OnDragStart")
H.check(not main._moving, "locked, dragging the header does nothing")
WildlyDB.lockFrame = false

runScript(main.closeBtn, "OnClick")
H.check(not main:IsShown(), "the close button closes the window")
H.eq(WildlyDB.visible, false, "and records that as deliberate")

------------------------------------------------------------
-- Closing in combat is answered, whichever way it is asked
------------------------------------------------------------

setup()
main = T.mainFrame()
WoW.inCombat = true
local at = #WoW.messages
SlashCmdList["WILDLY"]("hide")
H.check(main:IsShown(), "the window is still up during the fight")
H.check(said(at):find("leave combat", 1, true) ~= nil, "and the player is told when it goes: " .. said(at))
H.eq(WildlyDB.visible, false, "the preference is saved straight away")
WoW.inCombat = false
WoW.dispatch("PLAYER_REGEN_ENABLED")
H.check(not main:IsShown(), "and combat's end hides it")
WoW.flushTimers()

T.UpdateUI()
WoW.inCombat = true
at = #WoW.messages
runScript(main.closeBtn, "OnClick")
H.check(said(at):find("leave combat", 1, true) ~= nil, "the X button says the same: " .. said(at))
WoW.inCombat = false
WoW.dispatch("PLAYER_REGEN_ENABLED")
WoW.flushTimers()

------------------------------------------------------------
-- Events
------------------------------------------------------------

setup()
local events = {
    { "PLAYER_LOGIN" },
    { "READY_CHECK" },
    { "UNIT_AURA", "player", { isFullUpdate = true } },
    { "UNIT_AURA", "party1", { addedAuras = { { name = "Mark of the Wild" } } } },
    { "UNIT_AURA", "nameplate1", { isFullUpdate = true } },
    { "UNIT_AURA", "player", WoW.SecretUpdateInfo() },
    { "UNIT_PET" },
    { "GROUP_ROSTER_UPDATE" },
    { "RAID_ROSTER_UPDATE" },
    { "PLAYER_TALENT_UPDATE" },
    { "SPELLS_CHANGED" },
    { "ACTIVE_TALENT_GROUP_CHANGED" },
    { "PLAYER_REGEN_ENABLED" },
    { "BAG_UPDATE" },
    { "PLAYER_ENTERING_WORLD", true, false },
    { "PLAYER_ENTERING_WORLD", false, false },
}
for _, e in ipairs(events) do
    -- To every frame registered for it, as the game does: the host's and the
    -- config's frames both listen for PLAYER_LOGIN.
    local ok, err = pcall(WoW.dispatch, e[1], e[2], e[3])
    H.check(ok, e[1] .. " handler ran: " .. tostring(err))
end
-- In combat, spells changing refreshes only what can change.
WoW.inCombat = true
H.check(pcall(WoW.dispatch, "SPELLS_CHANGED"), "SPELLS_CHANGED in combat")
WoW.inCombat = false
H.check(pcall(WoW.flushTimers), "and everything they queued runs clean")

-- A secret UNIT_AURA payload refreshes rather than being dropped.
H.eq(T.AuraEventIsRelevant("player", WoW.SecretUpdateInfo()), true,
    "an unreadable payload counts as relevant")

------------------------------------------------------------
-- Slash commands
------------------------------------------------------------

local slash = SlashCmdList["WILDLY"]
H.check(slash ~= nil and SLASH_WILDLY1 == "/wildly", "/wildly is registered")
for _, cmd in ipairs({ "", "help", "show", "hide", "close", "reset", "config",
                       "options", "settings", "opt", "pos", "garbage" }) do
    local ok, err = pcall(slash, cmd)
    H.check(ok, "/wildly " .. (cmd == "" and "<no args>" or cmd) .. ": " .. tostring(err))
end
WoW.flushTimers()

-- Help describes the mapping that is actually live.
at = #WoW.messages
slash("help")
H.check(said(at):find("no Gift of the Wild known yet", 1, true) ~= nil,
    "without Gift, help says left-click is single-target: " .. said(at))
setup({ "MARK_SINGLE", "MARK_GROUP" })
at = #WoW.messages
slash("help")
H.check(said(at):find("Left-click   Gift of the Wild", 1, true) ~= nil,
    "with Gift, left-click is the group cast: " .. said(at))

-- Reset works while locked, and says the window is still locked.
WildlyDB.lockFrame = true
WildlyDB.pos = { point = "CENTER", relPoint = "CENTER", x = 9999, y = 9999 }
at = #WoW.messages
slash("reset")
H.eq(WildlyDB.pos, nil, "/wildly reset works while locked")
H.check(said(at):find("locked", 1, true) ~= nil, "and says the window is still locked: " .. said(at))
WildlyDB.lockFrame = false
at = #WoW.messages
slash("reset")
H.check(not said(at):find("is locked", 1, true), "unlocked, it does not nag: " .. said(at))

-- The position diagnostic survives a missing position and an unbuilt frame.
WildlyDB.pos = nil
at = #WoW.messages
H.check(pcall(slash, "pos"), "/wildly pos with no saved position")
H.check(said(at):find("nothing saved", 1, true) ~= nil, "says so plainly: " .. said(at))

------------------------------------------------------------
-- Config hooks
------------------------------------------------------------

H.check(pcall(Wildly_ApplyAlpha), "Wildly_ApplyAlpha runs")
H.check(pcall(Wildly_ForceRebuild), "Wildly_ForceRebuild runs")
H.check(pcall(Wildly_ScheduleRefresh), "Wildly_ScheduleRefresh runs")
H.check(pcall(Wildly_OnSoloToggle, true), "Wildly_OnSoloToggle(true) runs")
H.check(pcall(Wildly_OnSoloToggle, false), "Wildly_OnSoloToggle(false) runs")
WoW.inCombat = true
H.check(pcall(Wildly_ForceRebuild), "Wildly_ForceRebuild in combat does nothing, quietly")
H.check(pcall(Wildly_OnSoloToggle, true), "and so does the solo toggle")
WoW.inCombat = false
H.check(pcall(WoW.flushTimers), "queued timers run")

------------------------------------------------------------
-- The reagent footer tooltips
--
-- Built only when there is a reagent to show - here, Gift of the Wild at
-- rank 2 - and they are where a GameTooltip method this client lacks would
-- hide: the stub's catch-all makes an unknown METHOD a silent no-op. So they
-- are run, and what they produce is asserted.
------------------------------------------------------------

setup({ "MARK_SINGLE", "MARK_GROUP" }, { MARK_GROUP = "Rank 2" })
local thornroot = T.footerButton(17026)
H.check(thornroot ~= nil, "the Wild Thornroot button exists for rank 2 Gift")
WoW.clearTooltip()
runScript(thornroot, "OnEnter")
local tip = WoW.tooltipText()
H.check(tip:find("Item 17026", 1, true), "its tooltip names the item: " .. tip)
H.check(tip:find("in your bags", 1, true), "and how many you have: " .. tip)
H.check(tip:find("Gift of the Wild", 1, true), "and what consumes it: " .. tip)
runScript(thornroot, "OnLeave")

WoW.clearTooltip()
WoW.itemsUncached[17026] = true
runScript(thornroot, "OnEnter")
tip = WoW.tooltipText()
H.check(tip:find("Loading", 1, true), "an uncached item shows a placeholder: " .. tip)
H.check(WoW.itemsRequested[17026], "and the data is requested for next time")
WoW.itemsUncached[17026] = nil

-- Bags changing updates the count.
WoW.itemCounts[17026] = 12
H.check(pcall(WoW.dispatch, "BAG_UPDATE"), "BAG_UPDATE with the footer up")
H.eq(thornroot.countTxt._text, 12, "and the count follows the bags")

H.done("test_frames")
