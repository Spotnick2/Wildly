-- ============================================================================
-- WildlyCompat.lua  -  the bridge to LibGroupBuffs-1.0.
--
-- Every removed or moved API on WoW: Forever 1.60.1, the buff engine and the
-- buff window live in the shared library (Libs\LibGroupBuffs-1.0, loaded
-- first by the TOC), which Priestly and Magely embed too. This file checks
-- the library loaded completely and exposes it under Wildly's names:
--
--     local API = Wildly.API
--
-- No fallback copy lives here on purpose. If the library is missing or broken,
-- Wildly says so in chat and does not start, instead of running on a stale
-- duplicate.
-- ============================================================================

Wildly = Wildly or {}

-- Is the library here, and did the ACTIVE copy load to the end? Each runtime
-- file (Compat, Settings, Engine, UI) sets a marker on its LAST line, so a
-- file that threw partway leaves its marker unset. The marker must EQUAL the
-- active MINOR, not merely be set: several addons embed the library, and if a
-- newer copy throws partway through UI.lua, the older copy's uiMinor and half
-- its functions are still on the shared table.
--
-- The oldest library this build of Wildly works against. A floor, not a
-- feature check: behaviour changes cannot be feature-detected. r11 lets an
-- addon colour the popover's divider, which Wildly draws orange. Keep this
-- equal to the tag .pkgmeta pins; tests/test_manifest.lua checks that.
local NEEDS_MINOR = 11

local lib, minor
if LibStub then lib, minor = LibStub("LibGroupBuffs-1.0", true) end
local problem
if not lib then
    problem = "the LibGroupBuffs-1.0 library is missing from Wildly's Libs folder"
elseif not (type(minor) == "number" and minor >= NEEDS_MINOR
            and lib.compatMinor == minor and lib.settingsMinor == minor
            and lib.engineMinor == minor and lib.uiMinor == minor
            and type(lib.API) == "table" and type(lib.API.RegisterEventsReported) == "function"
            and type(lib.API.ClickEdges) == "function"
            and type(lib.Settings) == "table" and type(lib.Settings.New) == "function"
            and type(lib.Engine) == "table" and type(lib.Engine.New) == "function"
            and type(lib.UI) == "table" and type(lib.UI.New) == "function") then
    problem = "the LibGroupBuffs-1.0 library failed to load completely"
end

if problem then
    -- Said in chat, not only thrown: Lua errors are hidden by default on this
    -- client, and without this line the addon would just be silently dead.
    -- WildlyConfig.lua and Wildly.lua both check Wildly.API and stop before
    -- building anything, so there is exactly one message.
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff7c0a[Wildly]|r |cffff6666Wildly cannot start:|r "
            .. problem .. ". Reinstalling Wildly should fix it.")
    end
    error("Wildly: " .. problem .. " (Libs\\LibGroupBuffs-1.0). Developers: check out "
        .. "LibGroupBuffs next to the repository and run Tools/deploy.ps1.")
end

Wildly.API = lib.API
-- The settings write path and the client-fix watches; WildlyConfig.lua builds
-- Wildly's settings object from it.
Wildly.Settings = lib.Settings
-- The buff engine; Wildly.lua builds Wildly's engine from it.
Wildly.Engine = lib.Engine
-- The buff window; Wildly.lua builds Wildly's from it.
Wildly.UI = lib.UI

-- Wildly's own record of the events this client rejected, for
-- `/dump Wildly.eventFailures`. The library also keeps it, as
-- API.eventFailuresByOwner.Wildly; this copy is the short name to type.
Wildly.eventFailures = Wildly.eventFailures or {}

-- How Wildly tells the player. The library never prints - it has no business
-- writing to another addon's chat frame - so it calls this with the names the
-- client rejected, whether it threw or returned false.
local function ReportRejected(failed)
    local mine = lib.API.eventFailuresByOwner and lib.API.eventFailuresByOwner.Wildly or {}
    for _, ev in ipairs(failed) do
        Wildly.eventFailures[ev] = mine[ev] or true
    end
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff7c0a[Wildly]|r |cffff6666unsupported events skipped:|r "
            .. table.concat(failed, ", "))
    end
end

-- Event registration, with the failures reported. Wildly code must use this,
-- never the library's registration directly (tests/test_bridge.lua enforces
-- it), so the reporter is never left out.
function Wildly.RegisterEvents(frame, ...)
    return lib.API.RegisterEventsReported(frame, "Wildly", ReportRejected, ...)
end
