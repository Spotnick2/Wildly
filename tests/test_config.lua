------------------------------------------------------------
-- test_config.lua - saved variables: defaults, the Thorns mode, the learned
-- durations, and the accessors the engine and window read.
--
--   & 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_config.lua
------------------------------------------------------------

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")
local _, TC = H.loadAddon()

------------------------------------------------------------
-- Defaults on a fresh install
------------------------------------------------------------

WoW.reset()
WildlyDB = nil
Wildly_EnsureDefaults()

H.check(WildlyDB ~= nil, "a missing WildlyDB is created")
H.eq(WildlyDB.trackMark, true, "Mark of the Wild tracked by default")
H.eq(WildlyDB.thornsMode, "default", "Thorns covers tanks (or you, solo) by default")
H.eq(WildlyDB.showSolo, false, "solo display off by default")
H.eq(WildlyDB.trackPets, true, "pets tracked by default")
H.eq(WildlyDB.frameAlpha, 0.96, "near-opaque by default")
H.eq(WildlyDB.popoverSide, "auto", "the popover picks its side by default")
H.eq(WildlyDB.lockFrame, false, "unlocked by default")
H.eq(WildlyDB.showClickHints, true, "hints are on by default - they exist to be discovered")
H.eq(WildlyDB.visible, nil, "the window's own state is not a setting to default")
H.eq(WildlyDB.pos, nil, "nor is its position: nil means 'never placed'")
H.eq(TC.DEFAULTS.svLoadCheck, nil, "and the load check's marker is never a default")

-- The user's own settings survive a second run.
WildlyDB.trackMark = false
WildlyDB.frameAlpha = 0.5
WildlyDB.thornsMode = "everyone"
Wildly_EnsureDefaults()
H.eq(WildlyDB.trackMark, false, "a changed setting is not reset")
H.eq(WildlyDB.frameAlpha, 0.5, "...including the slider")
H.eq(WildlyDB.thornsMode, "everyone", "...and the Thorns mode")

------------------------------------------------------------
-- The Thorns mode
------------------------------------------------------------

for mode in pairs(TC.THORNS_MODES) do
    WildlyDB.thornsMode = mode
    H.eq(Wildly_GetThornsMode(), mode, "the '" .. mode .. "' mode reads back")
end
local count = 0
for _ in pairs(TC.THORNS_MODES) do count = count + 1 end
H.eq(count, 5, "five modes: default, tanks, self, everyone, disabled")

-- A value this build does not know reads as the default, and EnsureDefaults
-- repairs it, so the panel always has a radio to check.
WildlyDB.thornsMode = "raid leaders"
H.eq(Wildly_GetThornsMode(), "default", "an unknown mode reads as the default")
Wildly_EnsureDefaults()
H.eq(WildlyDB.thornsMode, "default", "and EnsureDefaults repairs the saved value")
WildlyDB = nil
H.eq(Wildly_GetThornsMode(), "default", "with no saved table at all, too")

------------------------------------------------------------
-- Buff toggles
--
-- "Disabled" Thorns is a buff that is not enabled: the library drops the row
-- before any member filter runs.
------------------------------------------------------------

WildlyDB = nil
Wildly_EnsureDefaults()
H.eq(Wildly_IsBuffEnabled("mark"), true, "Mark enabled by default")
WildlyDB.trackMark = false
H.eq(Wildly_IsBuffEnabled("mark"), false, "and disabled by its checkbox")
H.eq(Wildly_IsBuffEnabled("thorns"), true, "Thorns enabled in the default mode")
for _, mode in ipairs({ "tanks", "self", "everyone" }) do
    WildlyDB.thornsMode = mode
    H.eq(Wildly_IsBuffEnabled("thorns"), true, "Thorns enabled in '" .. mode .. "'")
end
WildlyDB.thornsMode = "disabled"
H.eq(Wildly_IsBuffEnabled("thorns"), false, "and not in 'disabled'")
H.eq(Wildly_IsBuffEnabled("something else"), true, "an unknown buff is not hidden by accident")
WildlyDB = nil
H.eq(Wildly_IsBuffEnabled("mark"), true, "with no saved table, everything is enabled")

------------------------------------------------------------
-- Duration store is per client build, keyed by spell name
------------------------------------------------------------

WoW.reset()
WildlyDB = nil
Wildly_EnsureDefaults()

H.check(Wildly_GetLearnedDuration("Mark of the Wild") == nil, "nothing learned yet")
Wildly_LearnDuration("Mark of the Wild", 1800)
H.eq(Wildly_GetLearnedDuration("Mark of the Wild"), 1800, "a learned duration is stored")
Wildly_LearnDuration("Mark of the Wild", 900)
H.eq(Wildly_GetLearnedDuration("Mark of the Wild"), 900, "and replaced downward on a nerf")
Wildly_LearnDuration("Mark of the Wild", 0)
H.eq(Wildly_GetLearnedDuration("Mark of the Wild"), 900, "a nonsense value is ignored")
Wildly_LearnDuration("Gift of the Wild", 3600)
H.eq(Wildly_GetLearnedDuration("Gift of the Wild"), 3600,
    "the group form of the same buff is stored separately")
H.eq(Wildly_GetLearnedDuration("Mark of the Wild"), 900, "...without overwriting the single form")
H.check(pcall(Wildly_LearnDuration, nil, 600), "a nil spell name is ignored rather than erroring")
H.eq(Wildly_GetLearnedDuration(nil), nil, "and reads as nothing")

WoW.build = "70000"
Wildly_EnsureDefaults()       -- a build change means a restart means a login
H.check(Wildly_GetLearnedDuration("Mark of the Wild") == nil, "a new build resets the table")
Wildly_LearnDuration("Mark of the Wild", 1200)
H.eq(Wildly_GetLearnedDuration("Mark of the Wild"), 1200, "and starts learning again")

------------------------------------------------------------
-- The window's settings
------------------------------------------------------------

WildlyDB = nil
Wildly_EnsureDefaults()
H.eq(Wildly_PopoverSide(), "auto", "the popover side reads back")
WildlyDB.popoverSide = "right"
H.eq(Wildly_PopoverSide(), "right", "an explicit side is reported back")
WildlyDB.popoverSide = nil
H.eq(Wildly_PopoverSide(), "auto", "a missing key falls back to auto")

H.eq(Wildly_FrameLocked(), false, "unlocked")
WildlyDB.lockFrame = true
H.eq(Wildly_FrameLocked(), true, "locking is reported")
WildlyDB.lockFrame = nil
H.eq(Wildly_FrameLocked(), false, "a missing key is unlocked, not a window nobody can move")

H.eq(Wildly_ShowClickHints(), true, "hints on")
WildlyDB.showClickHints = false
H.eq(Wildly_ShowClickHints(), false, "turning them off is respected")
WildlyDB.showClickHints = nil
H.eq(Wildly_ShowClickHints(), true, "only an explicit false turns them off")

H.eq(Wildly_GetFrameAlpha(), 0.96, "the default opacity")
WildlyDB.frameAlpha = 0.4
H.eq(Wildly_GetFrameAlpha(), 0.4, "a chosen opacity")

H.eq(Wildly_ShowSolo(), false, "solo off")
WildlyDB.showSolo = true
H.eq(Wildly_ShowSolo(), true, "solo on")
H.eq(Wildly_TrackPets(), true, "pets on")
WildlyDB.trackPets = false
H.eq(Wildly_TrackPets(), false, "pets off")

WildlyDB = nil
H.eq(Wildly_GetFrameAlpha(), 0.96, "no saved table: default opacity")
H.check(not Wildly_FrameLocked(), "no saved table: unlocked")
H.check(Wildly_ShowClickHints(), "no saved table: hints on")
H.check(not Wildly_ShowSolo(), "no saved table: not solo")

H.done("test_config")
