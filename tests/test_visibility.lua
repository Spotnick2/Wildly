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

-- Past the few seconds after login in which a roster arriving is the client
-- catching up rather than the player joining.
local function afterLogin() WoW.time = WoW.time + 30 end

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

-- Typed commands too: one line, and no saved table, no frames.
WildlyDB = nil
local framesBefore = T.mainFrame()
for _, cmd in ipairs({ "", "show", "reset", "hide", "pos", "config" }) do
    before = #WoW.messages
    SlashCmdList["WILDLY"](cmd)
    H.eq(#WoW.messages, before + 1, "/wildly " .. cmd .. " answers once on a mage")
end
H.check(WoW.messages[#WoW.messages]:find("Druid", 1, true) ~= nil,
    "saying what Wildly is for: " .. WoW.messages[#WoW.messages])
settle()
H.eq(WildlyDB, nil, "and creates no saved table")
H.eq(T.mainFrame(), framesBefore, "and builds no window")
H.check(not shown(), "and shows nothing")
Wildly_OnSoloToggle(true)
settle()
H.check(not shown(), "the solo hook does nothing on a mage either")

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

afterLogin()
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
-- The roster arriving just after login is not a join
--
-- Inside a group GetNumGroupMembers() can still read 0 at PLAYER_LOGIN. The
-- first roster update then looks like 0 -> n, and treating that as a join
-- would undo a close on every login.
------------------------------------------------------------

setup(0)
WildlyDB.visible = false
WoW.dispatch("PLAYER_LOGIN")
settle()
WoW.groupMembers = 5
WoW.dispatch("GROUP_ROSTER_UPDATE")
settle()
H.check(not shown(), "a roster that arrives just after login does not undo a close")
H.eq(WildlyDB.visible, false, "and the preference stands")

afterLogin()
WoW.groupMembers = 0
WoW.dispatch("GROUP_ROSTER_UPDATE")
WoW.groupMembers = 2
WoW.dispatch("GROUP_ROSTER_UPDATE")
settle()
H.check(shown(), "a real join later on still reopens it")

------------------------------------------------------------
-- A settings change never reopens a closed window
------------------------------------------------------------

setup(2)
WoW.dispatch("PLAYER_LOGIN")
settle()
T.CloseUI(true)
Wildly_ForceRebuild()
settle()
H.check(not shown(), "a rebuild asked for by the options panel leaves a closed window closed")
H.eq(WildlyDB.visible, false, "and the close is still remembered")
SlashCmdList["WILDLY"]("show")
settle()
Wildly_ForceRebuild()
settle()
H.check(shown(), "an open window is rebuilt and stays open")

------------------------------------------------------------
-- Spells the client reports only after login still open the window
------------------------------------------------------------

setup(2)
WoW.knownSpells = {}                  -- nothing known yet at login
WoW.spellbook = {}
WoW.dispatch("PLAYER_LOGIN")
settle()
H.check(not shown(), "with nothing to cast there is no window")
H.eq(WildlyDB.visible, true, "which is not a close: the preference is untouched")
WoW.Know(H.SPELL.MARK_SINGLE, H.NAME.MARK_SINGLE)
WoW.dispatch("SPELLS_CHANGED")
settle()
H.check(shown(), "the spellbook arriving opens the window it would have opened at login")

T.CloseUI(true)
WoW.dispatch("SPELLS_CHANGED")
settle()
H.check(not shown(), "but spells changing never overrides a close")

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

-- Mid-fight, the tick is honoured when the fight ends rather than lost.
WoW.inCombat = true
Wildly_SetConfig("showSolo", true)
Wildly_OnSoloToggle(true)
settle()
H.check(not shown(), "nothing can be built during the fight")
WoW.inCombat = false
WoW.dispatch("PLAYER_REGEN_ENABLED")
settle()
H.check(shown(), "and the window appears when it ends")

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
