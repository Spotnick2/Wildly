------------------------------------------------------------
-- test_methods.lua - every widget method the addon calls exists on the
-- client, for that widget type (WowTestKit's Kit.checkMethods).
--
-- The stub records each Type:Method the addon calls. After an exercise as
-- wide as is cheap (login, the window with a party, the popover, clicks,
-- dragging, minimize, close, combat, the reagent footer, the options panel,
-- every slash command), each recorded pair must be in the widget methods of
-- the build tests/kit.pin names. The floor at the end keeps the exercise from
-- quietly shrinking: an exercise that stops reaching the window records less.
--
--   & 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_methods.lua
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
    WoW.dispatch("PLAYER_ENTERING_WORLD", true, false)
    WoW.flushTimers()
    T.UpdateUI()
end

-- A handler that throws fails the test, not the run.
local function run(frame, script, ...)
    local fn = frame and frame._scripts and frame._scripts[script]
    if not fn then return end
    local ok, err = pcall(fn, frame, ...)
    H.check(ok, script .. " ran without error: " .. tostring(err))
end

local function firstRow()
    for _, r in ipairs(T.rows()) do
        if r._active then return r end
    end
end

------------------------------------------------------------
-- The window, the popover and the clicks
------------------------------------------------------------

setup()
WoW.SetAura("player", "Mark of the Wild", 3600, 1200)
T.UpdateUI()
local row = firstRow()
H.check(row ~= nil, "the window has a row to exercise")
run(row, "OnEnter")
local pop = T.popFrame()
WoW.mouseOver[pop] = true
run(pop, "OnUpdate", 5.0)
WoW.mouseOver[pop] = nil
run(pop, "OnUpdate", 5.0)
for _, button in ipairs({ "LeftButton", "RightButton" }) do
    run(row, "PreClick", button)
    run(row, "PostClick", button)
end
run(row, "OnEnter")
local pr = T.popRows()[1]
run(pr, "OnEnter")
run(pr, "PreClick", "LeftButton")
run(pr, "PostClick", "LeftButton")
run(pr, "OnLeave")
run(row, "OnLeave")

local main = T.mainFrame()
run(main, "OnUpdate", 1.0)
run(main, "OnUpdate", 5.0)
run(main.dragHandle, "OnDragStart")
run(main.dragHandle, "OnDragStop")
if main.minimizeBtn then
    run(main.minimizeBtn, "OnClick")
    run(main.minimizeBtn, "OnClick")
end
run(main.closeBtn, "OnClick")

------------------------------------------------------------
-- Combat, and the reagent footer
------------------------------------------------------------

setup()
WoW.inCombat = true
WoW.dispatch("PLAYER_REGEN_DISABLED")
T.UpdateUI()
SlashCmdList["WILDLY"]("hide")
WoW.inCombat = false
WoW.dispatch("PLAYER_REGEN_ENABLED")
WoW.flushTimers()

setup({ "MARK_SINGLE", "MARK_GROUP" }, { MARK_GROUP = "Rank 2" })
local thornroot = T.footerButton(17026)
run(thornroot, "OnEnter")
run(thornroot, "OnLeave")
WoW.dispatch("BAG_UPDATE")

------------------------------------------------------------
-- The options panel, every control
------------------------------------------------------------

local panel = _G["WildlyOptionsPanel"]
run(panel, "OnShow")
for _, key in ipairs({ "trackMark", "trackPets", "showSolo", "lockFrame", "showClickHints" }) do
    local box = _G["WildlyCB_" .. key]
    if box then
        box:SetChecked(not box:GetChecked())
        run(box, "OnClick")
    end
end
for _, mode in ipairs({ "default", "tanks", "self", "everyone", "disabled" }) do
    run(_G["WildlyRB_thorns_" .. mode], "OnClick")
end

------------------------------------------------------------
-- Every slash command
------------------------------------------------------------

for _, cmd in ipairs({ "help", "show", "pos", "config", "reset", "hide", "" }) do
    local ok, err = pcall(SlashCmdList["WILDLY"], cmd)
    H.check(ok, "/wildly " .. cmd .. " ran without error: " .. tostring(err))
end
WoW.flushTimers()

------------------------------------------------------------
-- The check
------------------------------------------------------------

local recorded = Kit.checkMethods()
H.check(recorded >= 120, "the exercise reached the window, popover, footer and panel ("
    .. recorded .. " recorded)")

H.done("test_methods")
