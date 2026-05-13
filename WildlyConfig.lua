-- ============================================================================
-- WildlyConfig.lua  –  Options panel for Wildly
-- ============================================================================

local ADDON_NAME = "Wildly"
local _, playerClass = UnitClass("player")
if playerClass ~= "DRUID" then
    return
end

local DEFAULTS = {
    trackMark  = true,
    thornsMode = "default", -- "default" | "tanks" | "self" | "everyone" | "disabled"
    showSolo   = false,
    trackPets  = true,
    frameAlpha = 0.96,
}

function Wildly_EnsureDefaults()
    if not WildlyDB then WildlyDB = {} end

    if WildlyDB.trackMark == nil then
        if WildlyDB.trackFort ~= nil then
            WildlyDB.trackMark = (WildlyDB.trackFort ~= false)
        else
            WildlyDB.trackMark = DEFAULTS.trackMark
        end
    end

    if WildlyDB.thornsMode == nil then
        WildlyDB.thornsMode = DEFAULTS.thornsMode
    end

    for k, v in pairs(DEFAULTS) do
        if WildlyDB[k] == nil then
            WildlyDB[k] = v
        end
    end

    -- Remove priest-specific leftovers after migration.
    WildlyDB.trackFort = nil
    WildlyDB.trackSpirit = nil
    WildlyDB.shadowMode = nil
    WildlyDB.shadowInstances = nil
    WildlyDB.shadowBosses = nil
end

function Wildly_TrackPets()
    return WildlyDB and WildlyDB.trackPets ~= false
end

function Wildly_IsBuffEnabled(defId)
    if not WildlyDB then return true end
    if defId == "mark" then return WildlyDB.trackMark ~= false end
    return true
end

function Wildly_GetThornsMode()
    local mode = WildlyDB and WildlyDB.thornsMode or "default"
    if mode == "default" or mode == "tanks" or mode == "self" or mode == "everyone" or mode == "disabled" then
        return mode
    end
    return "default"
end

function Wildly_GetFrameAlpha()
    return WildlyDB and WildlyDB.frameAlpha or 0.96
end

function Wildly_ShowSolo()
    return WildlyDB and WildlyDB.showSolo == true
end

local panel = CreateFrame("Frame", "WildlyOptionsPanel")
panel.name = ADDON_NAME

local function MakeHeader(parent, yRef, text, width)
    yRef.v = yRef.v - 14
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yRef.v)
    fs:SetText(text)
    local textH = fs:GetStringHeight() or 16
    yRef.v = yRef.v - textH - 2
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1.00, 0.49, 0.04, 0.45) -- #ff7c0a accent
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yRef.v)
    line:SetWidth(width or 480)
    yRef.v = yRef.v - 8
end

local function MakeCheckbox(parent, yRef, label, dbKey, onChange)
    yRef.v = yRef.v - 4
    local cb = CreateFrame("CheckButton", "WildlyCB_" .. dbKey, parent, "InterfaceOptionsCheckButtonTemplate")
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yRef.v)
    cb.Text:SetText(label)
    cb:SetChecked(WildlyDB[dbKey] ~= false)
    cb:SetScript("OnClick", function(self)
        WildlyDB[dbKey] = self:GetChecked() and true or false
        if onChange then onChange(self:GetChecked()) end
        if Wildly_ScheduleRefresh then Wildly_ScheduleRefresh() end
        if Wildly_ForceRebuild then Wildly_ForceRebuild() end
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
    yRef.v = yRef.v - (fs:GetStringHeight() + 6)
    return fs
end

local function MakeRadioGroup(parent, yRef, options, currentKey, onSelect)
    local radios = {}
    for _, opt in ipairs(options) do
        yRef.v = yRef.v - 4
        local rb = CreateFrame("CheckButton", "WildlyRB_" .. opt.key, parent, "UIRadioButtonTemplate")
        rb:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, yRef.v)
        local textObj = rb.text or rb.Text or _G[rb:GetName() .. "Text"]
        if textObj then
            textObj:SetText(opt.label)
            textObj:SetFontObject("GameFontHighlight")
        end
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
    for _, rb in ipairs(radios) do
        rb:SetChecked(rb._key == currentKey)
    end
    return radios
end

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
    verFs:SetText("|cff5555770.1|r")

    local settingsScroll = CreateFrame("ScrollFrame", "WildlySettingsScroll", panel, "UIPanelScrollFrameTemplate")
    settingsScroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -44)
    settingsScroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -30, 10)

    local settingsChild = CreateFrame("Frame", "WildlySettingsChild")
    settingsChild:SetSize(PANEL_W, 560)
    settingsScroll:SetScrollChild(settingsChild)

    local y = { v = 0 }

    MakeHeader(settingsChild, y, "General", PANEL_W)
    MakeCheckbox(settingsChild, y,
        "Show when solo (always display, even outside a group)", "showSolo",
        function(enabled)
            if Wildly_OnSoloToggle then Wildly_OnSoloToggle(enabled) end
        end)
    MakeDesc(settingsChild, y,
        "The Wildly frame stays visible without a party or raid. Use /wildly hide to close.")

    MakeHeader(settingsChild, y, "Buff Tracking", PANEL_W)
    MakeCheckbox(settingsChild, y, "Track |cffffffffMark of the Wild|r / Gift of the Wild", "trackMark")

    MakeHeader(settingsChild, y, "Thorns Tracking", PANEL_W)
    local thornsDesc = settingsChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    thornsDesc:SetPoint("TOPLEFT", settingsChild, "TOPLEFT", 0, y.v - 2)
    thornsDesc:SetWidth(PANEL_W)
    thornsDesc:SetJustifyH("LEFT")
    thornsDesc:SetText("|cffccccccChoose which targets should be tracked for Thorns.|r")
    y.v = y.v - (thornsDesc:GetStringHeight() + 8)

    MakeRadioGroup(settingsChild, y, {
        { key = "default",  label = "Default: tanks in group/raid, self while solo" },
        { key = "tanks",    label = "Tanks only" },
        { key = "self",     label = "Self only" },
        { key = "everyone", label = "Everyone" },
        { key = "disabled", label = "Disabled" },
    }, Wildly_GetThornsMode(), function(key)
        WildlyDB.thornsMode = key
        if Wildly_ForceRebuild then Wildly_ForceRebuild() end
    end)

    MakeDesc(settingsChild, y,
        "When no eligible targets exist in tank-scoped modes, the Thorns row is hidden.", 8)

    MakeHeader(settingsChild, y, "Pet Tracking", PANEL_W)
    MakeCheckbox(settingsChild, y, "Track pets in a separate group section", "trackPets")
    MakeDesc(settingsChild, y, "Useful for Mark of the Wild maintenance in party and raid groups.")

    MakeHeader(settingsChild, y, "Appearance", PANEL_W)

    y.v = y.v - 4
    local alphaLabel = settingsChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    alphaLabel:SetPoint("TOPLEFT", settingsChild, "TOPLEFT", 0, y.v)
    alphaLabel:SetText("Frame Opacity")
    y.v = y.v - 18

    local SLIDER_W = 220
    local trackBg = settingsChild:CreateTexture(nil, "BACKGROUND")
    trackBg:SetColorTexture(0.10, 0.10, 0.18, 0.95)
    trackBg:SetSize(SLIDER_W, 10)
    trackBg:SetPoint("TOPLEFT", settingsChild, "TOPLEFT", 8, y.v - 6)

    for _, info in ipairs({
        {"TOPLEFT", "TOPRIGHT", 1},
        {"BOTTOMLEFT", "BOTTOMRIGHT", 1},
    }) do
        local t = settingsChild:CreateTexture(nil, "BORDER")
        t:SetColorTexture(0.35, 0.35, 0.55, 0.80)
        t:SetHeight(info[3])
        t:SetPoint(info[1], trackBg, info[1])
        t:SetPoint(info[2], trackBg, info[2])
    end
    for _, side in ipairs({"LEFT", "RIGHT"}) do
        local t = settingsChild:CreateTexture(nil, "BORDER")
        t:SetColorTexture(0.35, 0.35, 0.55, 0.80)
        t:SetWidth(1)
        t:SetPoint("TOP" .. side, trackBg, "TOP" .. side)
        t:SetPoint("BOTTOM" .. side, trackBg, "BOTTOM" .. side)
    end

    local trackFill = settingsChild:CreateTexture(nil, "ARTWORK")
    trackFill:SetColorTexture(1.00, 0.49, 0.04, 0.75) -- #ff7c0a accent
    trackFill:SetPoint("TOPLEFT", trackBg, "TOPLEFT", 1, -1)
    trackFill:SetHeight(8)

    local alphaSlider = CreateFrame("Slider", "WildlyAlphaSlider", settingsChild, "OptionsSliderTemplate")
    alphaSlider:SetPoint("TOPLEFT", settingsChild, "TOPLEFT", 4, y.v)
    alphaSlider:SetWidth(SLIDER_W + 8)
    alphaSlider:SetMinMaxValues(0.20, 1.00)
    alphaSlider:SetValueStep(0.05)
    alphaSlider:SetObeyStepOnDrag(true)
    alphaSlider:SetValue(WildlyDB.frameAlpha or 0.96)
    alphaSlider.Low:SetText("20%")
    alphaSlider.High:SetText("100%")

    local alphaVal = settingsChild:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
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
        WildlyDB.frameAlpha = value
        alphaVal:SetText(string.format("%d%%", value * 100))
        UpdateFill()
        if Wildly_ApplyAlpha then Wildly_ApplyAlpha() end
    end)

    alphaSlider:HookScript("OnShow", function() C_Timer.After(0.02, UpdateFill) end)
    C_Timer.After(0.1, UpdateFill)

    y.v = y.v - 40
    MakeDesc(settingsChild, y, "Controls the background opacity of the main Wildly frame and popover.", 4)

    settingsChild:SetHeight(math.abs(y.v) + 20)
end

panel:SetScript("OnShow", function(self) BuildPanel(self) end)

local function RegisterPanel()
    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(category)
        panel._category = category
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

local regFrame = CreateFrame("Frame")
regFrame:RegisterEvent("PLAYER_LOGIN")
regFrame:SetScript("OnEvent", function()
    Wildly_EnsureDefaults()
    RegisterPanel()
end)

function Wildly_OpenConfig()
    if Settings and Settings.OpenToCategory and panel._category then
        Settings.OpenToCategory(panel._category:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(panel)
        InterfaceOptionsFrame_OpenToCategory(panel)
    end
end
