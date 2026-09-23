------------------------------------------------------------
-- harness.lua - tiny assertion harness + addon loader.
--
--     local H = dofile("tests/harness.lua")
--     H.loadLibrary()
--     H.eq(actual, expected, "what this proves")
--     H.done("test_thing")
--
-- Run from the repo root so the relative paths resolve.
--
-- Spell helpers and the combat secrecy switch arrive with the slice whose
-- tests need them (the host, slice 3).
------------------------------------------------------------

local H = { run = 0, failures = 0 }

function H.check(cond, msg)
    H.run = H.run + 1
    if not cond then
        H.failures = H.failures + 1
        print("  FAIL: " .. (msg or "assertion failed"))
    end
end

function H.eq(a, b, msg)
    H.check(a == b, (msg or "values differ") ..
        "  (expected " .. tostring(b) .. ", got " .. tostring(a) .. ")")
end

-- A whole file as text with CRLF normalised, or nil if it does not exist.
function H.readFile(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return (s:gsub("\r\n", "\n"))
end

-- The addon's own Lua files, in the order Wildly.toc loads them. Read from
-- the TOC so a new file cannot be missed by the tests that scan every file.
function H.tocFiles()
    local files = {}
    local toc = assert(H.readFile("Wildly.toc"), "Wildly.toc not found - run from the repo root")
    for line in (toc .. "\n"):gmatch("([^\n]*)\n") do
        local file = line:match("^%s*([^#%s][^%s]*%.lua)%s*$")
        if file then files[#files + 1] = file end
    end
    return files
end

-- Where LibGroupBuffs-1.0 is checked out. tests/run.ps1 sets LIBGROUPBUFFS to
-- the path it resolved (and prints it); running a test file by hand falls back
-- to the sibling checkout. There is deliberately no vendored copy to fall back
-- to: a stale one would make the suite pass against code that no longer ships.
function H.libraryRoot()
    return os.getenv("LIBGROUPBUFFS") or "../LibGroupBuffs"
end

-- Load a file or stop the run, naming it. A test that silently skipped a
-- missing file is how a load error in the client can pass a green suite.
local function run(path)
    local chunk, err = loadfile(path)
    if not chunk then error("cannot load " .. path .. ": " .. tostring(err), 3) end
    chunk()
end

-- The library's files as its XML lists them (tests/libfiles.lua, the same
-- reader run.ps1, deploy.ps1 and CI use).
function H.loadLibrary()
    local root = H.libraryRoot()
    local L = dofile("tests/libfiles.lua")
    local ok, load = pcall(L.resolve, root)
    if not ok then
        error(tostring(load) .. ". Check LibGroupBuffs out next to this repository "
            .. "(../LibGroupBuffs) or set LIBGROUPBUFFS to its path.", 2)
    end
    for _, file in ipairs(load) do run(root .. "/" .. file) end
end

-- The TOC's files the port has not reached yet. They are the TBC code, which
-- neither loads under this stub nor keeps the rules test_bridge scans for, so
-- loadAddon skips them and so do the scans. The slice that ports a file
-- removes it here; test_bridge fails while a listed file already uses
-- Wildly.API, so the list cannot outlive the port.
H.NOT_YET_PORTED = {
    ["Wildly.lua"] = "slice 3 (host)",
}

-- Everything the TOC loads that has been ported, in its order: the library,
-- then Wildly's files. Returns the test seams (nil until the file that sets
-- one is ported) and Wildly.API.
function H.loadAddon()
    H.loadLibrary()
    for _, file in ipairs(H.tocFiles()) do
        if not H.NOT_YET_PORTED[file] then run(file) end
    end
    return Wildly._test, Wildly._testConfig, Wildly.API
end

function H.done(name)
    if H.failures > 0 then
        print(string.format("%s: %d/%d FAILED", name, H.failures, H.run))
        os.exit(1)
    end
    print(string.format("%s: %d tests passed", name, H.run))
end

return H
