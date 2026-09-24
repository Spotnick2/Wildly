------------------------------------------------------------
-- test_visibility.lua - when the window opens itself, and when it must not.
--
-- Closing the window is a preference, and the addon also opens itself when you
-- join a group. Those two rules meet in a few places where the wrong one can
-- win: a deliberate close overwritten on the next login or roster update, and
-- a show asked for during combat dropped entirely. Wildly decides these; the
-- library only carries them out.
--
--   & 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_visibility.lua
------------------------------------------------------------

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")
local T = H.loadAddon()

local function setup(groupSize, class)
    WoW.reset()
    -- The addon's own module state survives between sections of this file,
    -- where a real login always starts with nothing on screen. Close first so
    -- each section is testing the open, not inheriting one.
    WoW.inCombat = false
    T.CloseUI(false)
    WildlyDB = nil
    Wildly_EnsureDefaults()
    H.TeachSpells({ "MARK_SINGLE" })
    T.RefreshSpellData()
    WoW.SetUnit("player", { name = "Karuzo Elegia", guid = "P0", class = class or "DRUID" })
    WoW.SetUnit("party1", { name = "Zoruka Mortalis", guid = "P1", class = "WARRIOR" })
    WoW.groupMembers = groupSize or 2
end

-- Logically open, which is what the addon's policy is about. In combat the
-- frame can still be on screen after a close, because the client refuses to
-- hide a frame that parents secure buttons.
local function shown()
    local main = T.mainFrame()
    return main ~= nil and main:IsShown() and T.ui:IsVisible()
end

local function settle()
    WoW.flushTimers()
    WoW.flushTimers()   -- a deferred rebuild can queue another
end

------------------------------------------------------------
-- Login opens the window for a druid in a group
------------------------------------------------------------

setup(2)
WoW.dispatch("PLAYER_LOGIN")
settle()
H.check(shown(), "a druid logging in inside a group gets the window")

setup(0)
WoW.dispatch("PLAYER_LOGIN")
settle()
H.check(not shown(), "a druid logging in alone does not")

setup(0)
WildlyDB.showSolo = true
WoW.dispatch("PLAYER_LOGIN")
settle()
H.check(shown(), "unless solo display is on")

------------------------------------------------------------
-- ...and nothing at all for any other class
------------------------------------------------------------

setup(2, "MAGE")
local before = #WoW.messages
WoW.dispatch("PLAYER_LOGIN")
settle()
H.check(not shown(), "a mage in a group gets no window")
H.eq(#WoW.messages, before, "and no Wildly chat line")
WoW.dispatch("GROUP_ROSTER_UPDATE")
WoW.dispatch("READY_CHECK")
settle()
H.check(not shown(), "nor does a roster change or a ready check open one")
H.check(not T.isDruid(), "Wildly knows it is on another class")

------------------------------------------------------------
-- A deliberate close survives a reload
------------------------------------------------------------

setup(2)
WildlyDB.visible = false
WoW.dispatch("PLAYER_LOGIN")
settle()
H.check(not shown(), "a window closed on purpose stays closed across a reload")
H.eq(WildlyDB.visible, false, "and the preference is not overwritten")

------------------------------------------------------------
-- Roster churn does not reopen a closed window...
------------------------------------------------------------

setup(2)
WoW.dispatch("PLAYER_LOGIN")
settle()
H.check(shown(), "open to start with")
T.CloseUI(true)                     -- /wildly hide
H.check(not shown(), "closed by hand")
H.eq(WildlyDB.visible, false, "which is remembered")

WoW.groupMembers = 3
WoW.SetUnit("party2", { name = "Sten Thornbeard", guid = "P2" })
WoW.dispatch("GROUP_ROSTER_UPDATE")
settle()
H.check(not shown(), "a third member joining does not reopen it")
H.eq(WildlyDB.visible, false, "and does not overwrite the preference")

WoW.dispatch("READY_CHECK")
settle()
H.check(not shown(), "nor does a ready check")

------------------------------------------------------------
-- ...but joining a group does, because that is the advertised behaviour
------------------------------------------------------------

WoW.groupMembers = 0
WoW.dispatch("GROUP_ROSTER_UPDATE")
settle()
H.check(not shown(), "leaving the group leaves it closed")

WoW.groupMembers = 2
WoW.dispatch("GROUP_ROSTER_UPDATE")
settle()
H.check(shown(), "joining a group reopens it - that is what the addon promises")
H.eq(WildlyDB.visible, true, "and the preference follows")

WoW.groupMembers = 0
WoW.dispatch("GROUP_ROSTER_UPDATE")
settle()
H.check(not shown(), "leaving the group closes it again, with solo display off")

------------------------------------------------------------
-- A show asked for during combat happens when combat ends
------------------------------------------------------------

setup(2)
WoW.dispatch("PLAYER_LOGIN")
settle()
T.CloseUI(true)
WoW.inCombat = true
SlashCmdList["WILDLY"]("show")
settle()
H.check(not shown(), "the window cannot be built during combat lockdown")
WoW.inCombat = false
WoW.dispatch("PLAYER_REGEN_ENABLED")
settle()
H.check(shown(), "so the request is honoured the moment combat ends, not dropped")

------------------------------------------------------------
-- The solo checkbox
------------------------------------------------------------

setup(0)
WoW.dispatch("PLAYER_LOGIN")
settle()
-- In the checkbox's order: the setting is saved, then the hook is called.
Wildly_SetConfig("showSolo", true)
Wildly_OnSoloToggle(true)
settle()
H.check(shown(), "ticking solo opens the window alone")
Wildly_SetConfig("showSolo", false)
Wildly_OnSoloToggle(false)
settle()
H.check(not shown(), "and unticking it alone closes it")

------------------------------------------------------------
-- Toggling
------------------------------------------------------------

setup(2)
WoW.dispatch("PLAYER_LOGIN")
settle()
H.check(shown(), "open")
SlashCmdList["WILDLY"]("")          -- bare /wildly toggles
settle()
H.check(not shown(), "toggles closed")
SlashCmdList["WILDLY"]("")
settle()
H.check(shown(), "and back open")

H.done("test_visibility")
