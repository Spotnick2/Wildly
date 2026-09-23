-- ============================================================================
-- WildlyConfig.lua  –  Options panel and settings for Wildly Forever
-- Registers through Retail's Settings framework (WoW: Forever 1.60.1)
-- ============================================================================

local ADDON_NAME = "Wildly"
local API = Wildly.API

-- WildlyCompat.lua has already said in chat why Wildly cannot start if the
-- shared library is missing. Stop here rather than building half an addon and
-- failing further down, far from the cause.
if not API then return end

-- ─── Default configuration ──────────────────────────────────────────────────

local THORNS_MODES = { default = true, tanks = true, self = true, everyone = true, disabled = true }

local DEFAULTS = {
    trackMark       = true,
    thornsMode      = "default",  -- "default" | "tanks" | "self" | "everyone" | "disabled"
    showSolo        = false,
    trackPets       = true,
    frameAlpha      = 0.96,
    popoverSide     = "auto",     -- "auto" | "left" | "right"
    lockFrame       = false,
    showClickHints  = true,
}

-- Deliberately NOT in DEFAULTS:
--   learnedDurations  -- [spellName] = seconds, scoped to a client build
--   visible, pos      -- the window's own state, written by Wildly.lua
--
-- And one that must NEVER be in DEFAULTS, or it stops working:
--   svLoadCheck       -- proof the client read the file; see the load check

-- ─── One write path for WildlyDB ─────────────────────────────────────────────
--
-- Nothing an addon writes survives a real client restart on this build -
-- account-wide and per-character SavedVariables, and CVars too (Priestly's
-- docs/FOREVER-PROBE.md section 11). The fix is Blizzard's. Until it lands,
-- every settings change goes through one setter anyway, so that whatever the
-- fix needs - a migration, a validation pass, a different store - lands in one
-- place instead of in each handler.
--
-- The setter, the check that notices the fix and the check that notices a new
-- client build are shared by every addon on LibGroupBuffs-1.0 (Settings.lua).
-- Wildly supplies what is its own: the saved tables, the builds it was
-- measured on, and how it speaks in chat.
--
-- The contract, enforced by a source scan in tests/test_config_seam.lua: no
-- file writes WildlyDB or WildlySVCheck directly except inside a
-- `config-owner` region - the code that creates the tables, seeds defaults
-- and keeps the learned-duration cache. Everything else calls the setter.

-- Which build the notes Wildly relies on were measured on, and the build where
-- SavedVariables are measured broken - both Priestly's measurements, which
-- this addon shares through the library. In the SOURCE, because it is the one
-- thing that survives a restart here. Bump MEASURED_ON_BUILD after
-- re-measuring (AGENTS.md); the library warns at every real login until then.
local MEASURED_ON_BUILD = "69913"
local SV_BROKEN_ON_BUILD = "69913"

-- config-owner: begin
-- The two saved tables, created on first use. WildlyDB holds the settings
-- (per character); WildlySVCheck is a small account-wide table declared only
-- so the load check can watch that scope too.
local function CharacterStore()
    if not WildlyDB then WildlyDB = {} end
    return WildlyDB
end

local function AccountCheckStore()
    if not WildlySVCheck then WildlySVCheck = {} end
    return WildlySVCheck
end
-- config-owner: end

-- Empty on purpose: the one place the SavedVariables fix, or a migration, will
-- land. The library looks it up at call time, so replacing it works.
function Wildly_OnConfigChanged(key)
end

local settings = Wildly.Settings.New({
    owner = ADDON_NAME,
    scopes = {
        { label = "per-character", get = CharacterStore },
        { label = "account-wide",  get = AccountCheckStore },
    },
    measuredOnBuild = MEASURED_ON_BUILD,
    svBrokenOnBuild = SV_BROKEN_ON_BUILD,
    report = function(text, kind)
        if not DEFAULT_CHAT_FRAME then return end
        if kind == "settingsLoaded" then text = "|cff55ff55" .. text .. "|r" end
        DEFAULT_CHAT_FRAME:AddMessage("|cffff7c0a[Wildly]|r " .. text)
    end,
    -- Looked up at call time, not captured: the hook is Wildly's extension
    -- point, and whatever replaces it later (or a test) must be the one called.
    onChanged = function(key) Wildly_OnConfigChanged(key) end,
})

-- An unchanged value is not a change: the window sets `visible` on every
-- refresh, which would otherwise run the hook on the aura hot path. Tables
-- are always reported.
function Wildly_SetConfig(key, value)
    settings:Set(key, value)
end

-- ─── Ensure defaults ────────────────────────────────────────────────────────

-- Resolved once per session (see Wildly_EnsureDefaults) so that learning a
-- duration does not call GetBuildInfo for every member of every group.
local g_Build

-- config-owner: begin
function Wildly_EnsureDefaults()
    if not WildlyDB then WildlyDB = {} end
    -- A client build can only change across a restart, which means a fresh
    -- login, which means this runs again. Re-resolving here is what keeps the
    -- cached build honest while keeping GetBuildInfo off the aura hot path.
    g_Build = nil
    for k, v in pairs(DEFAULTS) do
        if WildlyDB[k] == nil then
            WildlyDB[k] = v
        end
    end
    -- A mode this build does not know (a typo, or a later build's) would
    -- otherwise be read as "default" by the getter but shown as nothing in
    -- the panel, where no radio would be checked.
    if not THORNS_MODES[WildlyDB.thornsMode] then
        WildlyDB.thornsMode = DEFAULTS.thornsMode
    end
end
-- config-owner: end

-- ─── Learned buff durations ─────────────────────────────────────────────────
--
-- Forever's durations match neither TBC nor Vanilla and are still moving
-- during the beta, so the values in DEFS are only seeds: whatever a live aura
-- reports wins. Replacement goes in BOTH directions - pinning "the longest we
-- ever saw" would survive a duration nerf and quietly mis-colour every bar -
-- and the whole table is discarded when the client build changes. Keyed by
-- spell name: Mark of the Wild and Gift of the Wild share a row and need not
-- share a duration.

-- config-owner: begin
local function DurationStore()
    if not WildlyDB then return nil end
    if not g_Build then g_Build = (API and API.ClientBuild()) or "?" end
    local store = WildlyDB.learnedDurations
    if not store or store.build ~= g_Build then
        store = { build = g_Build }
        WildlyDB.learnedDurations = store
        -- Replaced from inside a getter, so it reports here or not at all.
        settings:Changed("learnedDurations")
    end
    return store
end

function Wildly_LearnDuration(spellName, seconds)
    if not spellName or not seconds or seconds <= 0 then return end
    local store = DurationStore()
    if not store then return end
    -- Almost every call re-learns the value we already have; only write when it
    -- actually changed.
    if store[spellName] == seconds then return end
    store[spellName] = seconds
    -- A write through a local alias, which the source scan cannot see, so it
    -- reports by hand.
    settings:Changed("learnedDurations")
end
-- config-owner: end

function Wildly_GetLearnedDuration(spellName)
    if not spellName then return nil end
    local store = DurationStore()
    return store and store[spellName] or nil
end

-- ─── Accessors ──────────────────────────────────────────────────────────────

function Wildly_TrackPets()
    return WildlyDB and WildlyDB.trackPets ~= false
end

-- "Disabled" Thorns is a buff that is not enabled: the library's way of
-- dropping a row entirely, before any member filter runs.
function Wildly_IsBuffEnabled(defId)
    if not WildlyDB then return true end
    if defId == "mark"   then return WildlyDB.trackMark ~= false end
    if defId == "thorns" then return Wildly_GetThornsMode() ~= "disabled" end
    return true
end

function Wildly_GetThornsMode()
    local mode = WildlyDB and WildlyDB.thornsMode
    if THORNS_MODES[mode] then return mode end
    return DEFAULTS.thornsMode
end

function Wildly_GetFrameAlpha()
    return WildlyDB and WildlyDB.frameAlpha or 0.96
end

-- True when the window must not be dragged. Checked in the drag handler
-- rather than by unregistering the drag, which keeps this clear of the secure
-- frame rules and safe to toggle in combat.
function Wildly_FrameLocked()
    return WildlyDB and WildlyDB.lockFrame == true
end

-- Whether a row explains what its clicks will cast, on hover. Only an
-- explicit false turns them off.
function Wildly_ShowClickHints()
    return not (WildlyDB and WildlyDB.showClickHints == false)
end

-- "auto" | "left" | "right". Auto means "wherever there is room", decided
-- fresh each time the popover opens.
function Wildly_PopoverSide()
    return (WildlyDB and WildlyDB.popoverSide) or "auto"
end

function Wildly_ShowSolo()
    return WildlyDB and WildlyDB.showSolo == true
end

-- ─── Has Blizzard fixed it? Did the client update? ──────────────────────────
--
-- Both checks live in LibGroupBuffs-1.0's Settings.lua. The load check keeps a
-- `svLoadCheck` marker in each scope - written every session, never in
-- DEFAULTS - and says so once when one comes back on a real login on a build
-- other than SV_BROKEN_ON_BUILD. The build check warns at every real login on
-- a build other than MEASURED_ON_BUILD, deliberately unlatched.

function Wildly_CheckClientBuild()
    settings:CheckBuild()
end

-- PLAYER_LOGIN fires on /reload too and cannot tell the two apart.
-- PLAYER_ENTERING_WORLD can: it carries (isInitialLogin, isReloadingUi). It
-- also fires on every zone change with both false, which the library ignores.
function Wildly_HandleEnteringWorld(isInitialLogin, isReloadingUi)
    settings:HandleEnteringWorld(isInitialLogin, isReloadingUi)
end

-- ═════════════════════════════════════════════════════════════════════════════
-- OPTIONS PANEL
-- ═════════════════════════════════════════════════════════════════════════════

local panel = CreateFrame("Frame", "WildlyOptionsPanel")
panel.name = ADDON_NAME

-- Wildly's accent, the #ff7c0a of its title.
local ACCENT = { 1.00, 0.49, 0.04 }

-- ─── Widget helpers ─────────────────────────────────────────────────────────
--
-- The TBC build leaned on InterfaceOptionsCheckButtonTemplate and
-- OptionsSliderTemplate. Neither is guaranteed in the Retail UI this client
-- ships, and a template CreateFrame rejects is a load blocker, not a cosmetic
-- problem. So: ask for a template, accept that it may not be there, and draw
-- our own art when it is not.

local CHECK_ART = {
    normal    = "Interface\\Buttons\\UI-CheckBox-Up",
    pushed    = "Interface\\Buttons\\UI-CheckBox-Down",
    highlight = "Interface\\Buttons\\UI-CheckBox-Highlight",
    checked   = "Interface\\Buttons\\UI-CheckBox-Check",
}

-- Returns frame, templateApplied.
--
-- Never returns nil: callers go straight on to :SetPoint() and a nil here would
-- just move the load-blocking error one line down. If the template is missing
-- we fall back to a bare frame; if even that fails nothing about the UI can
-- work anyway, so let it raise.
local function SafeFrame(frameType, name, parent, template, proof)
    if template then
        local ok, f = pcall(CreateFrame, frameType, name, parent, template)
        if ok and f then
            -- `proof` names a region the template is supposed to bring. Without
            -- it we cannot tell an applied template from a missing one, because
            -- a missing template does not throw - CreateFrame just returns a
            -- bare frame (Priestly's docs/FOREVER-PROBE.md, section 3).
            local applied = true
            if proof then
                applied = f[proof] ~= nil
                    or (f.GetName and f:GetName() and _G[f:GetName() .. proof] ~= nil)
            end
            return f, applied
        end
    end
    return CreateFrame(frameType, name, parent), false
end

-- A check button that looks right whether or not the template exists, with a
-- label we own (template label fields have moved around between UI versions).
local function MakeCheckButton(parent, name, label, labelWidth)
    local cb, templated = SafeFrame("CheckButton", name, parent, "UICheckButtonTemplate", "text")
    cb:SetSize(24, 24)
    if not templated then
        cb:SetNormalTexture(CHECK_ART.normal)
        cb:SetPushedTexture(CHECK_ART.pushed)
        cb:SetHighlightTexture(CHECK_ART.highlight)
        cb:SetCheckedTexture(CHECK_ART.checked)
    end
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    fs:SetJustifyH("LEFT")
    if labelWidth then fs:SetWidth(labelWidth) end
    fs:SetText(label or "")
    cb.label = fs
    return cb
end

-- GetStringHeight returns 0 for a FontString that has not been laid out yet,
-- which is the normal state inside a scroll child built during OnShow. `0 or 16`
-- is 0 in Lua, so every one of these needs a real check or the next control
-- lands on top of the text.
local function TextHeight(fs, fallback)
    local h = fs and fs:GetStringHeight()
    if not h or h <= 0 then return fallback or 16 end
    return h
end

-- One rebuild per change. ForceRebuild already re-runs everything
-- ScheduleRefresh would, so asking for both would queue two complete passes.
local function Rebuild()
    if Wildly_ForceRebuild then Wildly_ForceRebuild() end
end

local function MakeHeader(parent, yRef, text, width)
    yRef.v = yRef.v - 14
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yRef.v)
    fs:SetText(text)
    yRef.v = yRef.v - TextHeight(fs) - 2
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.45)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yRef.v)
    line:SetWidth(width or 480)
    yRef.v = yRef.v - 8
end

local function MakeCheckbox(parent, yRef, label, dbKey, onChange)
    yRef.v = yRef.v - 4
    local cb = MakeCheckButton(parent, "WildlyCB_" .. dbKey, label)
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yRef.v)
    cb:SetChecked(WildlyDB[dbKey] ~= false)
    cb:SetScript("OnClick", function(self)
        Wildly_SetConfig(dbKey, self:GetChecked() and true or false)
        if onChange then onChange(self:GetChecked()) end
        Rebuild()
    end)
    yRef.v = yRef.v - 26
    return cb
end

local function MakeDesc(parent, yRef, text, indent)
    indent = indent or 32
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", indent, yRef.v)
    fs:SetWidth(440)
    fs:SetJustifyH("LEFT")
    fs:SetText("|cff999999" .. text .. "|r")
    yRef.v = yRef.v - (TextHeight(fs) + 6)
    return fs
end

-- `group` prefixes the global names, so two radio groups whose keys happen to
-- match cannot collide in _G.
local function MakeRadioGroup(parent, yRef, group, options, currentKey, onSelect)
    local radios = {}
    for _, opt in ipairs(options) do
        yRef.v = yRef.v - 4
        -- UIRadioButtonTemplate ships on this client, but fall back to the
        -- checkbox art rather than risk a load-blocking CreateFrame throw.
        local rb, templated = SafeFrame("CheckButton", "WildlyRB_" .. group .. "_" .. opt.key,
            parent, "UIRadioButtonTemplate", "text")
        rb:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, yRef.v)
        if not templated then
            rb:SetSize(20, 20)
            rb:SetNormalTexture(CHECK_ART.normal)
            rb:SetHighlightTexture(CHECK_ART.highlight)
            rb:SetCheckedTexture(CHECK_ART.checked)
        end
        local textObj = rb.text or rb.Text or (rb:GetName() and _G[rb:GetName() .. "Text"])
        if not textObj then
            textObj = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            textObj:SetPoint("LEFT", rb, "RIGHT", 4, 0)
            textObj:SetJustifyH("LEFT")
        end
        textObj:SetText(opt.label)
        textObj:SetFontObject("GameFontHighlight")
        rb._key = opt.key
        radios[#radios + 1] = rb
        rb:SetScript("OnClick", function(self)
            for _, other in ipairs(radios) do
                other:SetChecked(other._key == self._key)
            end
            onSelect(self._key)
        end)
        yRef.v = yRef.v - 22
    end
    -- Set initial state AFTER all are built
    for _, rb in ipairs(radios) do
        rb:SetChecked(rb._key == currentKey)
    end
    return radios
end

-- ─── Build the panel ────────────────────────────────────────────────────────

local function BuildPanel(panel)
    if panel._built then return end
    panel._built = true
    Wildly_EnsureDefaults()

    local PANEL_W = 490

    local titleFs = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    titleFs:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -14)
    titleFs:SetText("|cffff7c0aWildly|r")

    local verFs = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    verFs:SetPoint("LEFT", titleFs, "RIGHT", 6, 0)
    verFs:SetText("|cff555577" .. API.AddonVersion(ADDON_NAME) .. "|r")

    local scroll = SafeFrame("ScrollFrame", "WildlySettingsScroll", panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -44)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -30, 10)

    local child = CreateFrame("Frame", "WildlySettingsChild")
    child:SetSize(PANEL_W, 600)
    scroll:SetScrollChild(child)

    local y = { v = 0 }

    -- ── General ──────────────────────────────────────────────────────────────
    MakeHeader(child, y, "General", PANEL_W)
    MakeCheckbox(child, y,
        "Show when solo (always display, even outside a group)", "showSolo",
        function(enabled)
            -- Immediately show or hide via the dedicated handler
            if Wildly_OnSoloToggle then Wildly_OnSoloToggle(enabled) end
        end)
    MakeDesc(child, y,
        "The Wildly frame stays visible without a party or raid. Use /wildly hide to close.")

    -- ── Buff Tracking ────────────────────────────────────────────────────────
    MakeHeader(child, y, "Buff Tracking", PANEL_W)
    MakeCheckbox(child, y, "Track |cffffffffMark of the Wild|r / Gift of the Wild", "trackMark")

    -- ── Thorns ───────────────────────────────────────────────────────────────
    MakeHeader(child, y, "Thorns", PANEL_W)

    y.v = y.v - 2
    local thornsDesc = child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    thornsDesc:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y.v)
    thornsDesc:SetWidth(PANEL_W)
    thornsDesc:SetJustifyH("LEFT")
    thornsDesc:SetText("|cffccccccChoose who the Thorns row covers.|r")
    y.v = y.v - (TextHeight(thornsDesc) + 8)

    MakeRadioGroup(child, y, "thorns", {
        { key = "default",  label = "Tanks in a group, yourself when solo" },
        { key = "tanks",    label = "Tanks only" },
        { key = "self",     label = "Yourself only" },
        { key = "everyone", label = "Everyone (players, not pets)" },
        { key = "disabled", label = "Off - no Thorns row" },
    }, Wildly_GetThornsMode(), function(key)
        Wildly_SetConfig("thornsMode", key)
        Rebuild()
    end)

    MakeDesc(child, y,
        "When nobody in a group qualifies - no tanks, say - that group has no Thorns row.", 8)

    -- ── Pet Tracking ─────────────────────────────────────────────────────────
    MakeHeader(child, y, "Pet Tracking", PANEL_W)
    MakeCheckbox(child, y, "Track pets (Hunter, Warlock and Mage pets)", "trackPets")
    MakeDesc(child, y,
        "Pets appear in a separate group at the bottom of the frame. Thorns never covers them.")

    -- ── Appearance ───────────────────────────────────────────────────────────
    MakeHeader(child, y, "Appearance", PANEL_W)

    y.v = y.v - 4
    local alphaLabel = child:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    alphaLabel:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y.v)
    alphaLabel:SetText("Frame Opacity")
    y.v = y.v - 18

    local SLIDER_W = 220

    local trackBg = child:CreateTexture(nil, "BACKGROUND")
    trackBg:SetColorTexture(0.10, 0.10, 0.18, 0.95)
    trackBg:SetSize(SLIDER_W, 10)
    trackBg:SetPoint("TOPLEFT", child, "TOPLEFT", 8, y.v - 6)

    for _, info in ipairs({
        { "TOPLEFT", "TOPRIGHT" },
        { "BOTTOMLEFT", "BOTTOMRIGHT" },
    }) do
        local t = child:CreateTexture(nil, "BORDER")
        t:SetColorTexture(0.35, 0.35, 0.55, 0.80)
        t:SetHeight(1)
        t:SetPoint(info[1], trackBg, info[1])
        t:SetPoint(info[2], trackBg, info[2])
    end
    for _, side in ipairs({ "LEFT", "RIGHT" }) do
        local t = child:CreateTexture(nil, "BORDER")
        t:SetColorTexture(0.35, 0.35, 0.55, 0.80)
        t:SetWidth(1)
        t:SetPoint("TOP" .. side, trackBg, "TOP" .. side)
        t:SetPoint("BOTTOM" .. side, trackBg, "BOTTOM" .. side)
    end

    local trackFill = child:CreateTexture(nil, "ARTWORK")
    trackFill:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.75)
    trackFill:SetPoint("TOPLEFT", trackBg, "TOPLEFT", 1, -1)
    trackFill:SetHeight(8)

    -- Template-free slider. OptionsSliderTemplate belongs to the Classic
    -- options UI and is not guaranteed here; the track and fill above are
    -- already ours, so all this needs is a thumb and the input handling.
    local alphaSlider = CreateFrame("Slider", "WildlyAlphaSlider", child)
    alphaSlider:SetPoint("TOPLEFT", child, "TOPLEFT", 4, y.v)
    alphaSlider:SetSize(SLIDER_W + 8, 18)
    alphaSlider:SetOrientation("HORIZONTAL")
    alphaSlider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    local thumb = alphaSlider:GetThumbTexture()
    if thumb then thumb:SetSize(16, 18) end
    alphaSlider:SetMinMaxValues(0.20, 1.00)
    alphaSlider:SetValueStep(0.05)
    if alphaSlider.SetObeyStepOnDrag then alphaSlider:SetObeyStepOnDrag(true) end
    alphaSlider:SetValue(WildlyDB.frameAlpha or 0.96)

    local lowTxt = child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lowTxt:SetPoint("TOPLEFT", alphaSlider, "BOTTOMLEFT", 2, 2)
    lowTxt:SetText("20%")
    local highTxt = child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    highTxt:SetPoint("TOPRIGHT", alphaSlider, "BOTTOMRIGHT", -2, 2)
    highTxt:SetText("100%")

    local alphaVal = child:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    alphaVal:SetPoint("LEFT", alphaSlider, "RIGHT", 10, 0)
    alphaVal:SetText(string.format("%d%%", (WildlyDB.frameAlpha or 0.96) * 100))

    local function UpdateFill()
        local min, max = alphaSlider:GetMinMaxValues()
        local val = alphaSlider:GetValue()
        local pct = (val - min) / (max - min)
        trackFill:SetWidth(math.max(1, pct * (SLIDER_W - 2)))
    end

    alphaSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value * 20 + 0.5) / 20
        Wildly_SetConfig("frameAlpha", value)
        alphaVal:SetText(string.format("%d%%", value * 100))
        UpdateFill()
        if Wildly_ApplyAlpha then Wildly_ApplyAlpha() end
    end)

    alphaSlider:HookScript("OnShow", function() C_Timer.After(0.02, UpdateFill) end)
    C_Timer.After(0.1, UpdateFill)

    y.v = y.v - 40
    MakeDesc(child, y,
        "Controls the background opacity of the main Wildly frame and popover.", 4)

    y.v = y.v - 6
    MakeCheckbox(child, y, "Lock frame position", "lockFrame")
    MakeDesc(child, y,
        "Stops the window being dragged by the header. |cff999999/wildly reset|r still recentres "
        .. "it, so a locked window can always be recovered.")
    MakeCheckbox(child, y, "Show click hints on mouseover", "showClickHints")
    MakeDesc(child, y,
        "Hovering a row explains what each mouse button will cast, and on whom. What left-click "
        .. "does depends on whether you know Gift of the Wild, so it is worth reading once.")

    y.v = y.v - 10
    local sideLabel = child:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sideLabel:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y.v)
    sideLabel:SetText("Popover Side")
    -- Reserve the label's own height: MakeRadioGroup anchors a ~20px button by
    -- its TOPLEFT and only subtracts 4 of its own, so a smaller step here puts
    -- the first radio through the label.
    y.v = y.v - 18

    MakeRadioGroup(child, y, "side", {
        { key = "auto",  label = "Automatic - open it wherever there is room" },
        { key = "left",  label = "Always on the left" },
        { key = "right", label = "Always on the right" },
    }, Wildly_PopoverSide(), function(key)
        Wildly_SetConfig("popoverSide", key)
        -- The side is chosen fresh every time the popover opens, so the next
        -- hover would pick this up on its own. The rebuild is for the popover
        -- that is open right now, so the change shows without moving the mouse.
        Rebuild()
    end)

    MakeDesc(child, y,
        "Which side of the frame the per-member popover opens on. Automatic follows the frame: "
        .. "put Wildly on the left of your screen and the popover opens to the right.", 4)

    child:SetHeight(math.abs(y.v) + 20)
end

panel:SetScript("OnShow", function(self) BuildPanel(self) end)

-- ─── Register ───────────────────────────────────────────────────────────────

-- Retail's Settings framework only. InterfaceOptions_AddCategory belongs to
-- the UI this client replaced.
local function RegisterPanel()
    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(category)
        panel._category = category
    end
end

local cfgFrame = CreateFrame("Frame", "WildlyConfigEvents")
Wildly.RegisterEvents(cfgFrame, "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD")
cfgFrame:SetScript("OnEvent", function(self, event, isInitialLogin, isReloadingUi)
    if event == "PLAYER_LOGIN" then
        Wildly_EnsureDefaults()
        RegisterPanel()
    elseif event == "PLAYER_ENTERING_WORLD" then
        Wildly_HandleEnteringWorld(isInitialLogin, isReloadingUi)
    end
end)

function Wildly_OpenConfig()
    if Settings and Settings.OpenToCategory and panel._category then
        Settings.OpenToCategory(panel._category:GetID())
    else
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cffff7c0a[Wildly]|r Options are in Game Menu > Options > AddOns > Wildly.")
    end
end

-- ─── Test seam ───────────────────────────────────────────────────────────────

Wildly._testConfig = {
    TextHeight         = TextHeight,
    DEFAULTS           = DEFAULTS,
    THORNS_MODES       = THORNS_MODES,
    DurationStore      = DurationStore,
    MEASURED_ON_BUILD  = MEASURED_ON_BUILD,
    SV_BROKEN_ON_BUILD = SV_BROKEN_ON_BUILD,
    eventFrame         = function() return cfgFrame end,
}
