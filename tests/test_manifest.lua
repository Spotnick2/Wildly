------------------------------------------------------------
-- test_manifest.lua - assertions about Wildly.toc itself.
--
-- The TOC is not Lua and nothing else in the suite can see it, but two of its
-- lines are load-bearing in ways that are invisible until a player notices
-- something missing: which files load and in what order, and where settings
-- are stored.
--
--   & 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_manifest.lua
------------------------------------------------------------

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")

-- One reader for every file this test looks at (H.readFile normalises CRLF),
-- split into lines once.
local function lines(path)
    local text = assert(H.readFile(path), path .. " is missing")
    local out = {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do out[#out + 1] = (line:gsub("%s+$", "")) end
    return out
end

local toc = lines("Wildly.toc")

local function directive(name)
    -- Escape the name: "X-Curse-Project-ID" contains "-", which is a Lua
    -- pattern quantifier, so an unescaped match silently finds nothing.
    local escaped = name:gsub("(%W)", "%%%1")
    for _, line in ipairs(toc) do
        local value = line:match("^##%s*" .. escaped .. ":%s*(.*)$")
        if value then return value end
    end
    return nil
end

------------------------------------------------------------
-- Interface version
------------------------------------------------------------

H.eq(directive("Interface"), "16001",
    "WoW: Forever 1.60.1 is interface 16001 - the %d%02d%02d form, not the transposed 11601 "
    .. "that circulates in the wild")

------------------------------------------------------------
-- Settings storage
--
-- Measured on build 1.60.1.69913: this client writes SavedVariables and never
-- reads them back - account-wide AND per-character - so every session starts
-- from defaults. (An earlier note here said per-character storage loads. It
-- does not; that was concluded from reading the saved file, which always looks
-- populated because EnsureDefaults rewrites every default each session.)
--
-- So this directive does not make settings persist today. It stays because it
-- is no worse than account-wide, and it is where settings will be read from
-- once Blizzard fixes the loader. Wildly follows Priestly here; Priestly's
-- issues #9 and #35 have the history. Read them before changing storage.
------------------------------------------------------------

H.eq(directive("SavedVariablesPerCharacter"), "WildlyDB",
    "WildlyDB is declared per character - no worse than account-wide while neither loads")
-- The only account-wide variable is the load check's marker, so the addon can
-- tell when account-wide storage is fixed.
H.eq(directive("SavedVariables"), "WildlySVCheck",
    "the only account-wide variable is the load-check marker")
H.check(not tostring(directive("SavedVariables")):find("WildlyDB", 1, true),
    "and WildlyDB is not ALSO declared account-wide - one variable cannot live in both")

------------------------------------------------------------
-- Load order
--
-- LibGlass-1.0 first: LibGroupBuffs' lib:New refuses to make an instance
-- while LibGlass is missing or half-loaded. Then LibGroupBuffs-1.0, then
-- WildlyCompat, which asks it for Wildly's instance; both other files take
-- file-local aliases from that at load time. Anything out of order and they
-- get nil.
------------------------------------------------------------

local entries = {}
for _, line in ipairs(toc) do
    -- Any line starting with "#" is a directive or a comment to the client,
    -- never a file to load.
    if line:match("%.[lx][um][al]$") and not line:match("^%s*#") then entries[#entries + 1] = line end
end

local GLASS_XML = "Libs\\LibGlass-1.0\\LibGlass-1.0.xml"
local LIB_XML = "Libs\\LibGroupBuffs-1.0\\LibGroupBuffs-1.0.xml"
H.eq(entries[1], GLASS_XML, "the glass material loads first, through its own XML")
H.eq(entries[2], LIB_XML, "then the shared library that draws with it")
H.eq(entries[3], "WildlyCompat.lua", "then the bridge that asks it for Wildly's instance")
H.eq(entries[4], "WildlyConfig.lua", "then the config, which reads Wildly.API at file scope")
H.eq(entries[5], "Wildly.lua", "then the addon proper")
H.eq(#entries, 5, "and nothing else loads")

------------------------------------------------------------
-- Both libraries are embedded, pinned, and never committed
--
-- The TOC paths, the .pkgmeta externals keys and .gitignore have to agree, or
-- the release zip is missing a library while every local check passes. Each
-- external is read BY PATH (tests/pkgmeta.lua): with two of them, "the first
-- tag: in the file" is LibGlass's.
------------------------------------------------------------

local P = dofile("tests/pkgmeta.lua")
local externals = P.externals() or {}
local function embeds(path, xml, url)
    local ext = externals[path]
    H.check(ext ~= nil, ".pkgmeta embeds " .. path)
    ext = ext or {}
    H.eq(path:gsub("/", "\\") .. "\\" .. xml, entries[path:find("LibGlass", 1, true) and 1 or 2],
        "which is exactly where the TOC loads " .. xml .. " from")
    H.eq(ext.url, url, "from its repository")
    -- A tag, or a full commit SHA while a pin is being piloted. Read as the
    -- packager reads it, the whole rest of the line, so an inline comment -
    -- which the packager keeps in the ref - fails here.
    local pinned = (ext.kind == "tag" and tostring(ext.ref):match("^r%d+$"))
        or (ext.kind == "commit" and tostring(ext.ref):match("^%x+$") and #ext.ref == 40)
    H.check(pinned, path .. " is pinned to an r<N> tag or a full commit, so a release cannot "
        .. "change under its own source: " .. tostring(ext.kind) .. " " .. tostring(ext.ref))
    return ext
end
local glass = embeds("Libs/LibGlass-1.0", "LibGlass-1.0.xml", "https://github.com/Spotnick2/LibGlass")
local gb = embeds("Libs/LibGroupBuffs-1.0", "LibGroupBuffs-1.0.xml",
    "https://github.com/Spotnick2/LibGroupBuffs")
local external = "Libs/LibGroupBuffs-1.0"
local n = 0
for _ in pairs(externals) do n = n + 1 end
H.eq(n, 2, "and nothing else is embedded")
-- LibGlass by tag, never `latest` (newest by creation date, else branch HEAD).
H.eq(glass.kind, "tag", "LibGlass is pinned by tag: " .. tostring(glass.ref))

-- The bridge refuses a library older than the behaviour this build needs, and
-- that floor has to be the library actually shipped: pinning a newer one
-- while the floor stays behind means a player with the older library
-- installed gets an addon that starts and quietly misbehaves, which is what
-- the floor exists to prevent. (The opposite, a floor ahead of the pin,
-- refuses to start at all.)
--
-- A tag names its MINOR. A commit does not, so for a commit pin the MINOR is
-- read from that commit in the library checkout's history (`git show`) - not
-- from its working tree, which may be any branch.
local needs = tonumber((H.readFile("WildlyCompat.lua") or "")
    :match("local NEEDS_MINOR = (%d+)"))
H.check(needs ~= nil, "WildlyCompat declares the oldest library it works against")
local pinnedMinor
if gb.kind == "tag" then
    pinnedMinor = tonumber(tostring(gb.ref):match("^r(%d+)$"))
else
    -- Only a full hex SHA reaches the shell (the pin check above requires one),
    -- so nothing in .pkgmeta can become part of a command.
    local sha = tostring(gb.ref):match("^%x+$")
    local cmd = 'git -C "' .. H.libraryRoot() .. '" show ' .. tostring(sha) .. ":LibGroupBuffs.lua"
    local src = ""
    if sha and #sha == 40 then
        local pipe = io.popen(cmd .. " 2>&1")
        src = pipe and pipe:read("*a") or ""
        if pipe then pipe:close() end
    end
    pinnedMinor = tonumber(src:match('local MAJOR, MINOR = "LibGroupBuffs%-1%.0", (%d+)'))
    H.check(pinnedMinor ~= nil, "the pinned commit's MINOR could be read with `" .. cmd
        .. "` - the library checkout must have that commit: " .. src:sub(1, 200))
end
H.eq(needs, pinnedMinor,
    "and it is the MINOR .pkgmeta pins: " .. tostring(gb.kind) .. " " .. tostring(gb.ref)
    .. " vs NEEDS_MINOR " .. tostring(needs))

-- lib:New arrived in r26, and the bridge has no other way in: below r26 it
-- would read every healthy library as "failed to load completely" and
-- Wildly would refuse to start for everyone. r28 added lib:Refusal, which is
-- how the bridge words a refusal, and r27 the `manual` argument Wildly's
-- onCloseDeferred reads. Rolling the pin back is the way either breaks, and
-- this is what stops it landing quietly.
H.check(needs ~= nil and needs >= 28,
    "the floor is r28 or newer, which is where lib:Refusal came from: " .. tostring(needs))

local libIgnored = false
for line in ((H.readFile(".gitignore") or "") .. "\n"):gmatch("([^\n]*)\n") do
    if line == "Libs/" then libIgnored = true end
end
H.check(libIgnored, "and Libs/ is git-ignored, so no vendored copy can creep back in")

------------------------------------------------------------
-- Packaging
------------------------------------------------------------

H.eq(directive("Version"), "@project-version@",
    "the packager substitutes the version; deploy.ps1 rewrites it only in the deployed copy")

-- ...and it substitutes keywords in EVERY file it ships, Lua included, not
-- only the TOC. A Lua comparison against the whole "@project-version@" became
-- `version == "v1.0.3"` in the released file, and every player's copy took
-- itself for a development copy (#25) - which no offline test could see,
-- because they load the source, where the token is still raw. So no shipped
-- Lua file may hold a packager keyword whole; code that needs one builds it
-- from pieces. Matched by shape, because the packager has a family of them
-- (@project-revision@, @file-date-iso@, @debug@, ...).
for _, file in ipairs(H.tocFiles()) do
    local src = H.readFile(file) or ""
    local n, keyword = 0, nil
    for line in (src .. "\n"):gmatch("([^\n]*)\n") do
        n = n + 1
        keyword = line:match("(@[%w%-]+@)")
        if keyword then break end
    end
    H.check(keyword == nil, file .. " holds no packager keyword the release would rewrite: "
        .. tostring(keyword) .. " at line " .. n)
end
H.check(directive("X-Curse-Project-ID") ~= nil, "the CurseForge project is declared")
H.check(tostring(directive("Title")):find("Wildly", 1, true) ~= nil,
    "the Title directive names the addon: " .. tostring(directive("Title")))
H.eq(directive("X-Curse-Project-ID"), "1542496", "and it is Wildly's CurseForge project")

------------------------------------------------------------
-- The packaged zip must not carry internal documents
------------------------------------------------------------

local pkg = lines(".pkgmeta")

-- Every Lua pattern character escaped, not just the dot: a path like
-- Libs/LibGroupBuffs-1.0/tests carries a `-`, which is a quantifier in a
-- pattern, so a dot-only escape silently matches nothing and the check
-- passes for the wrong reason.
local function ignored(name)
    local literal = name:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%1")
    for _, line in ipairs(pkg) do
        if line:match("^%s*%-%s*" .. literal .. "%s*$") then return true end
    end
    return false
end

for _, name in ipairs({ "AGENTS.md", "CLAUDE.md", "tests", "Tools", "docs", ".github" }) do
    H.check(ignored(name), name .. " stays out of the release zip")
end

------------------------------------------------------------
-- The libraries' dev files are ignored from HERE
--
-- CurseForge's packager, which builds the release from the tag webhook, does
-- not apply an external's own ignore list: Priestly v2.0.6 shipped the
-- library's tests and notes, 46 files instead of 7. Read from each library's
-- own .pkgmeta rather than copied, so a dev file added and ignored there - and
-- so invisible to CI's packager, which does honour it - fails here instead of
-- shipping in the next release. Dot-paths are skipped: both packagers prune
-- those.
------------------------------------------------------------

local function mirror(path, root)
    local libPkgmeta = H.readFile(root .. "/.pkgmeta")
    H.check(libPkgmeta ~= nil, path .. ": the library checkout has a .pkgmeta to mirror")
    local mirrored, inIgnore = 0, false
    for line in (libPkgmeta or ""):gmatch("[^\n]+") do
        if line:match("^ignore:%s*$") then
            inIgnore = true
        -- A top-level comment does not end a YAML list; a later ignore entry
        -- can still follow it and must be mirrored here.
        elseif line:match("^%S") and not line:match("^#") then
            inIgnore = false
        elseif inIgnore then
            local entry = line:match("^%s+%-%s+(%S+)")
            if entry and entry:sub(1, 1) ~= "." then
                mirrored = mirrored + 1
                H.check(ignored(path .. "/" .. entry),
                    path .. "/" .. entry .. " is ignored from here too, not left to the library's own list")
            end
        end
    end
    H.check(mirrored >= 4, path .. ": the library's ignore list was read: " .. mirrored .. " entries")
end
mirror(external, H.libraryRoot())
mirror("Libs/LibGlass-1.0", H.libGlassRoot())

H.done("test_manifest")
