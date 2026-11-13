-- Settings window: one canvas panel in the game's Options -> AddOns list.
local _, ns = ...
local Core, Display, Schedule, L, UI = ns.Core, ns.Display, ns.Schedule, ns.L, ns.UI

local MARGIN = 16
local BOX_WIDTH, BOX_HEIGHT, BOX_GAP = 296, 150, 8
local GRID_TOP = -118
local GRID_RIGHT = MARGIN + 2 * BOX_WIDTH + BOX_GAP -- x of the grid's right edge

local BOX_BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local panel, statusText, modeDropdown, baselineText, rememberButton, minimapCheck
local boxes = {}        -- section key -> widgets of that section
local refreshing = false

local function label(parent, font, text)
    local fontString = parent:CreateFontString(nil, "ARTWORK", font)
    if text then fontString:SetText(text) end
    return fontString
end

local function createSlider(box, key, field, y)
    local name = label(box, "GameFontHighlightSmall", UI.ValueLabel(field))
    name:SetPoint("TOPLEFT", 12, y)
    name:SetWidth(84)
    name:SetJustifyH("LEFT")

    local slider = CreateFrame("Slider", nil, box, "OptionsSliderTemplate")
    slider:SetPoint("LEFT", name, "RIGHT", 6, 0)
    slider:SetSize(140, 16)
    local limit = Display.LIMITS[field]
    slider:SetMinMaxValues(limit.min, limit.max)
    slider:SetValueStep(limit.step)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    -- The template brings its own "Low" / "High" / title texts; we draw our own.
    if slider.Low then slider.Low:SetText("") end
    if slider.High then slider.High:SetText("") end
    if slider.Text then slider.Text:SetText("") end

    local value = label(box, "GameFontHighlightSmall")
    value:SetPoint("LEFT", slider, "RIGHT", 8, 0)

    slider:SetScript("OnValueChanged", function(_, raw)
        if refreshing then return end
        Core.SetSectionValue(key, field, raw)
        value:SetText(UI.FormatValue(field, Core.GetSection(key)[field]))
    end)

    return { name = name, slider = slider, value = value }
end

local function createBox(key, column, row)
    local box = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    box:SetSize(BOX_WIDTH, BOX_HEIGHT)
    box:SetPoint("TOPLEFT", MARGIN + column * (BOX_WIDTH + BOX_GAP), GRID_TOP - row * (BOX_HEIGHT + BOX_GAP))
    box:SetBackdrop(BOX_BACKDROP)
    box:SetBackdropColor(0, 0, 0, 0.35)

    local icon = box:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetPoint("TOPLEFT", 10, -8)
    icon:SetTexture(UI.ICONS[key])

    local title = label(box, "GameFontNormal")
    title:SetPoint("LEFT", icon, "RIGHT", 6, 0)

    local check = CreateFrame("CheckButton", nil, box, "UICheckButtonTemplate")
    check:SetSize(24, 24)
    check:SetPoint("TOPLEFT", 8, -30)
    check:SetScript("OnClick", function(self)
        Core.SetSectionEnabled(key, self:GetChecked() and true or false)
    end)
    local checkLabel = label(box, "GameFontHighlightSmall", L.ENABLED)
    checkLabel:SetPoint("LEFT", check, "RIGHT", 2, 0)

    local edit = CreateFrame("EditBox", nil, box, "InputBoxTemplate")
    edit:SetSize(48, 20)
    edit:SetPoint("TOPRIGHT", -14, -32)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(5)
    edit:SetJustifyH("CENTER")
    local function showSavedStart()
        edit:SetText(Schedule.FormatTime(Core.GetSection(key).start))
    end
    edit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    edit:SetScript("OnEscapePressed", function(self)
        showSavedStart()
        self:ClearFocus()
    end)
    edit:SetScript("OnEditFocusLost", function(self)
        self:HighlightText(0, 0)
        local minute = Schedule.ParseTime(self:GetText())
        if minute then Core.SetSectionStart(key, minute) end
        showSavedStart() -- an invalid entry falls back to the saved time
    end)
    local editLabel = label(box, "GameFontHighlightSmall", L.STARTS_AT)
    editLabel:SetPoint("RIGHT", edit, "LEFT", -10, 0)

    return {
        box = box, title = title, check = check, edit = edit,
        gamma = createSlider(box, key, "gamma", -66),
        brightness = createSlider(box, key, "brightness", -92),
        contrast = createSlider(box, key, "contrast", -118),
    }
end

local function refreshStatus()
    statusText:SetText(string.format("%s: %s    %s: %s",
        L.SERVER_TIME, Schedule.FormatTime(Core.GetServerMinute()),
        L.NOW, UI.ModeLabel(Core.GetIconSection())))
end

local function refreshWidgets()
    refreshStatus()

    local applied = Core.GetApplied()
    local hasContrast = Display.HasContrast()
    for _, key in ipairs(Schedule.ORDER) do
        local widgets, section = boxes[key], Core.GetSection(key)
        if key == applied then
            widgets.box:SetBackdropBorderColor(1, 0.82, 0)
            widgets.title:SetText(UI.ModeLabel(key) .. "  |cff40ff40(" .. L.APPLIED .. ")|r")
        else
            widgets.box:SetBackdropBorderColor(0.5, 0.5, 0.5)
            widgets.title:SetText(UI.ModeLabel(key))
        end
        widgets.check:SetChecked(section.enabled)
        if not widgets.edit:HasFocus() then
            widgets.edit:SetText(Schedule.FormatTime(section.start))
        end
        for _, field in ipairs(Display.KEYS) do
            local row = widgets[field]
            row.slider:SetValue(section[field])
            row.value:SetText(UI.FormatValue(field, section[field]))
        end
        widgets.contrast.name:SetShown(hasContrast)
        widgets.contrast.slider:SetShown(hasContrast)
        widgets.contrast.value:SetShown(hasContrast)
    end

    baselineText:SetText(L.BASELINE .. ": " .. UI.FormatValues(Core.GetBaseline()))
    rememberButton:SetEnabled(Core.CanRememberBaseline())
    minimapCheck:SetChecked(not Core.GetDB().minimap.hide)
end

local function refresh()
    if not panel:IsVisible() then return end
    refreshing = true
    xpcall(refreshWidgets, geterrorhandler())
    refreshing = false
    -- Picking an entry refreshes from inside its own click; regenerating then would
    -- replace the menu being clicked. The pick updates the button text by itself.
    if not modeDropdown:IsMenuOpen() then modeDropdown:GenerateMenu() end
end

local function build()
    panel = CreateFrame("Frame")
    panel.name = "LighterNights"
    panel:Hide()

    local heading = label(panel, "GameFontNormalLarge", "LighterNights")
    heading:SetPoint("TOPLEFT", MARGIN, -16)

    statusText = label(panel, "GameFontHighlight")
    statusText:SetPoint("TOPRIGHT", panel, "TOPLEFT", GRID_RIGHT, -20)

    local modeLabel = label(panel, "GameFontNormal", L.MODE)
    modeLabel:SetPoint("TOPLEFT", MARGIN, -54)

    modeDropdown = CreateFrame("DropdownButton", nil, panel, "WowStyle1DropdownTemplate")
    modeDropdown:SetPoint("LEFT", modeLabel, "RIGHT", 10, 0)
    modeDropdown:SetWidth(170)
    modeDropdown:SetupMenu(function(_, root) UI.AddModeItems(root) end)

    local hint = label(panel, "GameFontDisableSmall", L.TUNE_HINT)
    hint:SetPoint("TOPLEFT", MARGIN, -82)
    hint:SetWidth(2 * BOX_WIDTH + BOX_GAP)
    hint:SetJustifyH("LEFT")

    boxes.morning = createBox("morning", 0, 0)
    boxes.day = createBox("day", 1, 0)
    boxes.evening = createBox("evening", 0, 1)
    boxes.night = createBox("night", 1, 1)

    local bottom = GRID_TOP - 2 * (BOX_HEIGHT + BOX_GAP) - 8

    rememberButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    rememberButton:SetSize(190, 22)
    rememberButton:SetPoint("TOPRIGHT", panel, "TOPLEFT", GRID_RIGHT, bottom)
    rememberButton:SetText(L.REMEMBER_CURRENT)
    rememberButton:SetMotionScriptsWhileDisabled(true)
    rememberButton:SetScript("OnClick", function() Core.RememberBaseline() end)
    rememberButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L.REMEMBER_TOOLTIP, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    rememberButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    baselineText = label(panel, "GameFontHighlight")
    baselineText:SetPoint("LEFT", panel, "TOPLEFT", MARGIN, bottom - 11)
    baselineText:SetPoint("RIGHT", rememberButton, "LEFT", -10, 0)
    baselineText:SetJustifyH("LEFT")

    minimapCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    minimapCheck:SetSize(24, 24)
    minimapCheck:SetPoint("TOPLEFT", MARGIN - 4, bottom - 32)
    minimapCheck:SetScript("OnClick", function(self)
        Core.SetMinimapHidden(not self:GetChecked())
    end)
    local minimapLabel = label(panel, "GameFontHighlight", L.SHOW_MINIMAP)
    minimapLabel:SetPoint("LEFT", minimapCheck, "RIGHT", 2, 0)

    StaticPopupDialogs["LIGHTERNIGHTS_RESET"] = {
        text = L.RESET_CONFIRM,
        button1 = YES,
        button2 = NO,
        OnAccept = function() Core.ResetSections() end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    local resetButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    resetButton:SetSize(190, 22)
    resetButton:SetPoint("TOPRIGHT", panel, "TOPLEFT", GRID_RIGHT, bottom - 32)
    resetButton:SetText(L.RESET_ALL)
    resetButton:SetScript("OnClick", function() StaticPopup_Show("LIGHTERNIGHTS_RESET") end)

    panel:SetScript("OnShow", refresh)
    local sinceClock = 0
    panel:SetScript("OnUpdate", function(_, elapsed)
        sinceClock = sinceClock + elapsed
        if sinceClock >= 1 then
            sinceClock = 0
            refreshStatus()
        end
    end)

    Core.RegisterListener(refresh)

    local category = Settings.RegisterCanvasLayoutCategory(panel, "LighterNights")
    Settings.RegisterAddOnCategory(category)
    Core.OpenOptions = function() Settings.OpenToCategory(category:GetID()) end
end

Core.OnReady(build)
