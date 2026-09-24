------------------------------------------------------------
-- test_options.lua - build the options panel and click everything in it.
--
-- The panel is built lazily on OnShow, so without this none of it would run
-- under test: not the construction, not a single checkbox, radio or slider.
-- That would put the whole options UI outside the strict-global net in
-- wow_stubs.lua, which is the one thing protecting against an API that
-- quietly went away.
--
-- The hooks Wildly.lua defines for the config - Wildly_ForceRebuild and
-- friends - are replaced here by spies, and put back at the end. That tests
-- what the panel asks for, which is the panel's whole job; what the host then
-- does with it is test_frames' and test_visibility's.
--
--   & 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_options.lua
------------------------------------------------------------

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")
local _, TC = H.loadAddon()

WoW.reset()
WildlyDB = nil
Wildly_EnsureDefaults()

local calls = {}
local HOOKS = { "Wildly_ForceRebuild", "Wildly_OnSoloToggle", "Wildly_ApplyAlpha" }
local realHooks = {}
for _, name in ipairs(HOOKS) do realHooks[name] = rawget(_G, name) end
local function spy(name)
    _G[name] = function(...) calls[#calls + 1] = { name = name, args = { ... } } end
end
for _, name in ipairs({ "Wildly_ForceRebuild", "Wildly_OnSoloToggle", "Wildly_ApplyAlpha" }) do
    spy(name)
end
local function called(name, since)
    for i = (since or 0) + 1, #calls do
        if calls[i].name == name then return calls[i] end
    end
end

local function click(name, ...)
    local f = _G[name]
    if not f then H.check(false, "no widget named " .. name) return end
    local fn = f._scripts and f._scripts.OnClick
    if not fn then H.check(false, name .. " has no OnClick") return end
    local ok, err = pcall(fn, f, ...)
    H.check(ok, name .. " OnClick ran: " .. tostring(err))
    return f
end

-- Every change goes through the one write path.
local changed = {}
local realHook = Wildly_OnConfigChanged
Wildly_OnConfigChanged = function(key) changed[#changed + 1] = key end
local function reported(key, since)
    for i = (since or 0) + 1, #changed do
        if changed[i] == key then return true end
    end
    return false
end

------------------------------------------------------------
-- The panel builds at all
------------------------------------------------------------

local panel = _G["WildlyOptionsPanel"]
H.check(panel ~= nil, "the options panel frame exists")
local built, err = pcall(panel._scripts.OnShow, panel)
H.check(built, "it builds on first show: " .. tostring(err))
H.check(pcall(panel._scripts.OnShow, panel), "showing it again is a no-op")

------------------------------------------------------------
-- Checkboxes
--
-- The client toggles a checkbox before OnClick fires, so the test does too:
-- firing the handler alone just re-reads whatever state it was in.
------------------------------------------------------------

for _, key in ipairs({ "trackMark", "trackPets", "showSolo", "lockFrame", "showClickHints" }) do
    local box = _G["WildlyCB_" .. key]
    H.check(box ~= nil, key .. " has a checkbox")
    if box then
        -- Flip from whatever it is now, then back: setting the value it already
        -- has is (correctly) not a change, and would not be reported.
        local now = WildlyDB[key] ~= false
        for _, state in ipairs({ not now, now }) do
            local mark, rebuilds = #changed, #calls
            box:SetChecked(state)
            click("WildlyCB_" .. key)
            H.eq(WildlyDB[key], state, key .. " follows its checkbox to " .. tostring(state))
            H.check(reported(key, mark), key .. " is written through Wildly_SetConfig")
            H.check(called("Wildly_ForceRebuild", rebuilds) ~= nil, key .. " asks the window to rebuild")
        end
    end
end

-- Solo also asks for the dedicated show/hide handler, with the new state.
local mark = #calls
_G["WildlyCB_showSolo"]:SetChecked(true)
click("WildlyCB_showSolo")
local solo = called("Wildly_OnSoloToggle", mark)
H.check(solo ~= nil and solo.args[1] == true, "ticking solo tells the window to show")

------------------------------------------------------------
-- Thorns radios
------------------------------------------------------------

local THORNS = { "default", "tanks", "self", "everyone", "disabled" }
for _, mode in ipairs(THORNS) do
    local before, rebuilds = #changed, #calls
    click("WildlyRB_thorns_" .. mode)
    H.eq(WildlyDB.thornsMode, mode, "the " .. mode .. " radio selects that mode")
    H.check(reported("thornsMode", before) or mode == "default",
        "through the setter (the first click may re-select the default, which is no change)")
    H.check(called("Wildly_ForceRebuild", rebuilds) ~= nil, "and rebuilds the window")
end
H.eq(Wildly_IsBuffEnabled("thorns"), false, "'disabled' drops the Thorns row")
for _, mode in ipairs(THORNS) do
    H.eq(_G["WildlyRB_thorns_" .. mode]:GetChecked(), mode == "disabled",
        "only the selected Thorns radio is checked (" .. mode .. ")")
end

-- Built with the saved mode checked, not always the first radio.
WildlyDB.thornsMode = "self"
panel._built = nil
H.check(pcall(panel._scripts.OnShow, panel), "the panel rebuilds")
H.eq(_G["WildlyRB_thorns_self"]:GetChecked(), true, "with the saved Thorns mode checked")
H.eq(_G["WildlyRB_thorns_default"]:GetChecked(), false, "and not the default")

------------------------------------------------------------
-- Popover side radios
--
-- A separate group from Thorns: their names carry the group, so two groups
-- with a matching key could not collide in _G.
------------------------------------------------------------

for _, side in ipairs({ "left", "right", "auto" }) do
    click("WildlyRB_side_" .. side)
    H.eq(WildlyDB.popoverSide, side, "the " .. side .. " radio selects that side")
end
H.eq(_G["WildlyRB_side_auto"]:GetChecked(), true, "auto is the one left checked")
H.eq(_G["WildlyRB_side_left"]:GetChecked(), false, "with the others cleared")
H.eq(WildlyDB.thornsMode, "self", "and choosing a side leaves the Thorns mode alone")

------------------------------------------------------------
-- Opacity slider
------------------------------------------------------------

local slider = _G["WildlyAlphaSlider"]
H.check(slider ~= nil, "the opacity slider was created")
-- Template-free, so nothing else turns the mouse on: without this the thumb
-- cannot be dragged, and a test that calls OnValueChanged directly would never
-- notice.
H.eq(slider and slider._mouseEnabled, true, "and it takes the mouse")
local onValue = slider and slider._scripts.OnValueChanged
H.check(onValue ~= nil, "with a value handler")
mark = #calls
local changedMark = #changed
H.check(pcall(onValue, slider, 0.5), "which runs")
H.eq(WildlyDB.frameAlpha, 0.5, "and stores the opacity")
H.check(reported("frameAlpha", changedMark), "through Wildly_SetConfig")
H.check(called("Wildly_ApplyAlpha", mark) ~= nil, "and applies it to the window")
H.check(pcall(onValue, slider, 0.73), "an in-between value")
H.eq(WildlyDB.frameAlpha, 0.75, "is snapped to the 5% step")
H.check(pcall(onValue, slider, 1.0), "at the top of its range too")
H.eq(WildlyDB.frameAlpha, 1.0, "which is full opacity")

-- Installed with HookScript, so it has to be run on purpose.
H.check(pcall(slider._scripts.OnShow, slider), "the slider's OnShow hook runs")
WoW.flushTimers()

------------------------------------------------------------
-- Without Wildly.lua's hooks at all
--
-- The config must not depend on the host having loaded: if Wildly.lua failed,
-- each hook is looked up guarded, so a missing one is skipped, not an error.
------------------------------------------------------------

for _, name in ipairs({ "Wildly_ForceRebuild", "Wildly_OnSoloToggle", "Wildly_ApplyAlpha" }) do
    _G[name] = nil
end
click("WildlyCB_trackMark")
click("WildlyRB_thorns_tanks")
H.check(pcall(onValue, slider, 0.6), "the slider runs with no host loaded")
H.eq(WildlyDB.thornsMode, "tanks", "and settings still save")
for name, fn in pairs(realHooks) do _G[name] = fn end

------------------------------------------------------------
-- Layout measurement before the text has been laid out
------------------------------------------------------------

local flat = WoW.makeFrame()
flat.GetStringHeight = function() return 0 end
H.eq(TC.TextHeight(flat), 16, "a zero height falls back to a readable default")
H.eq(TC.TextHeight(flat, 32), 32, "callers can pick their own fallback")
local tall = WoW.makeFrame()
tall.GetStringHeight = function() return 24 end
H.eq(TC.TextHeight(tall), 24, "a real height is used as-is")
H.eq(TC.TextHeight(nil), 16, "and a missing FontString does not error")

WoW.zeroHeights = true
panel._built = nil
H.check(pcall(panel._scripts.OnShow, panel), "the panel builds even when no text has been measured yet")
WoW.zeroHeights = false

------------------------------------------------------------
-- Opening the panel
------------------------------------------------------------

local before = #WoW.messages
H.check(pcall(Wildly_OpenConfig), "Wildly_OpenConfig runs before the panel is registered")
H.check(#WoW.messages > before and WoW.messages[#WoW.messages]:find("AddOns", 1, true) ~= nil,
    "and says where to find the options rather than doing nothing")

-- The panel registers itself with the Settings framework on login, which is
-- what OpenToCategory needs.
WoW.dispatch("PLAYER_LOGIN")
WoW.flushTimers()
H.check(pcall(Wildly_OpenConfig), "Wildly_OpenConfig runs")
H.eq(WoW.settingsOpenedTo, 42, "and opens the registered category")

Wildly_OnConfigChanged = realHook

H.done("test_options")
