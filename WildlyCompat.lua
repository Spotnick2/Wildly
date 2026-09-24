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

-- The oldest library this build of Wildly works against. A floor, not a
-- feature check: behaviour changes cannot be feature-detected. r11 lets an
-- addon colour the popover's divider, which Wildly draws orange; r12 answers
-- for itself whether a copy is usable, which is what lib.Status below is.
-- Keep this equal to the tag .pkgmeta pins; tests/test_manifest.lua checks that.
local NEEDS_MINOR = 12

-- Is this copy usable? The library answers, from its own list of files, so
-- the marker names and entry points are no longer Wildly's business - this
-- file used to carry them, as Priestly's did (Spotnick2/priestly#52). A copy
-- older than r12 has no Status to ask, which is itself an answer: either it
-- is too old for this build, or its last file threw before installing it.
-- Called under pcall: it is library code on a shared table another copy may
-- have left half-built, and a throw here would skip the chat message below.
local lib, minor
if LibStub then lib, minor = LibStub("LibGroupBuffs-1.0", true) end
local status
if lib and type(lib.Status) == "function" then
    local asked, answer = pcall(lib.Status, NEEDS_MINOR)
    status = asked and answer or "incomplete"
end
if lib and not status then
    status = (type(minor) == "number" and minor < NEEDS_MINOR) and "too-old" or "incomplete"
end

local problem
if not lib then
    problem = "the LibGroupBuffs-1.0 library is missing from Wildly's Libs folder"
elseif status == "too-old" then
    -- Behind the floor. Said separately from a failed load: the TOC loads
    -- Wildly's own copy before this file and LibStub upgrades anything older,
    -- so an older one being active means Wildly's own copy is missing or
    -- stale - whatever state the other addon's copy is in. That is what the
    -- player can fix, so it is what they are told.
    problem = "the LibGroupBuffs-1.0 library in use is r" .. tostring(minor)
        .. ", older than the r" .. NEEDS_MINOR .. " this Wildly needs"
elseif status ~= "ok" then
    problem = "the LibGroupBuffs-1.0 library failed to load completely"
end

if problem then
    -- Said in chat, not only thrown: Lua errors are hidden by default on this
    -- client, and without this line the addon would just be silently dead.
    -- Once they are ported (AGENTS.md, Port status), WildlyConfig.lua and
    -- Wildly.lua check Wildly.API and stop before building anything, so this
    -- is the only message. Until then they are the TBC code, which does not
    -- run on this client with or without the library.
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
