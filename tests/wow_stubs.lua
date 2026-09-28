------------------------------------------------------------
-- wow_stubs.lua - Wildly's layer over the SHARED stub.
--
-- The client surface itself lives in LibGroupBuffs (tests/wow_stubs.lua), the
-- same way tests/config_scan.lua does: every absence and refusal measured on
-- this client is measured once, for three addons. Wildly kept its own copy,
-- marking each change "Wildly:" so a library fix could be carried over by
-- hand - until the glass material arrived needing mask, slice and status-bar
-- methods in all three at once, which is the drift that copy was always going
-- to cause (LibGroupBuffs#21).
--
-- What stays here is Wildly's alone: a druid rather than a priest, and the
-- globals this addon owns.
--
--     dofile("tests/wow_stubs.lua")     -- FIRST, in every test file
--     WoW.reset()
------------------------------------------------------------

-- Same rule as tests/harness.lua, which is not loaded yet when this runs.
local LIBRARY = os.getenv("LIBGROUPBUFFS") or "../LibGroupBuffs"
local shared = LIBRARY .. "/tests/wow_stubs.lua"
local chunk = loadfile(shared)
if not chunk then
    error("Wildly's tests need LibGroupBuffs checked out next to this repository "
        .. "(../LibGroupBuffs) or LIBGROUPBUFFS set to its path: " .. shared .. " not found", 0)
end
chunk()

-- A druid, at the level cap of this beta. The shared stub defaults to the
-- priest its first consumer needed; a unit no test describes takes this class
-- rather than that one.
WoW.SetPlayerDefaults({ name = "Wildly Testcase", class = "DRUID", level = 20 })

------------------------------------------------------------
-- Globals that legitimately start out nil
--
-- Reading one is an error unless it is named here: the stub is the list of
-- APIs confirmed to exist on this client, and an unstubbed read is either a
-- typo or an API that quietly went away. These are Wildly's own.
------------------------------------------------------------

WoW.allowGlobal(
    -- The addon and its saved tables.
    "Wildly", "WildlyDB", "WildlySVCheck",
    -- The hooks Wildly.lua defines for the config, which the config looks up
    -- guarded (`if Wildly_ForceRebuild then`), so a test that loads the config
    -- on its own must be able to read them as nil.
    "Wildly_ForceRebuild", "Wildly_ApplyAlpha", "Wildly_OnSoloToggle"
)
