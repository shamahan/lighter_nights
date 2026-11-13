-- Small helpers shared by the settings window and the minimap button.
local _, ns = ...
local Core, Display, Schedule, L = ns.Core, ns.Display, ns.Schedule, ns.L

local UI = {}
ns.UI = UI

UI.ICONS = {
    morning = "Interface\\AddOns\\LighterNights\\Media\\morning.png",
    day     = "Interface\\AddOns\\LighterNights\\Media\\day.png",
    evening = "Interface\\AddOns\\LighterNights\\Media\\evening.png",
    night   = "Interface\\AddOns\\LighterNights\\Media\\night.png",
}

local VALUE_LABEL = { gamma = "GAMMA", brightness = "BRIGHTNESS", contrast = "CONTRAST" }
local VALUE_FORMAT = { gamma = "%.2f", brightness = "%d", contrast = "%d" }

-- Localized name of a mode: "disabled", "auto" or a section key.
function UI.ModeLabel(mode)
    if mode == "disabled" then return L.MODE_DISABLED end
    if mode == "auto" then return L.MODE_AUTO end
    return L["SECTION_" .. mode]
end

-- Localized name of a value: "gamma", "brightness" or "contrast".
function UI.ValueLabel(field)
    return L[VALUE_LABEL[field]]
end

-- One value as text: "1.30" for gamma, "50" for brightness and contrast.
function UI.FormatValue(field, value)
    return string.format(VALUE_FORMAT[field], value)
end

-- "Gamma 1.30, Brightness 50, Contrast 50"; contrast is left out when the
-- client has no Contrast CVar.
function UI.FormatValues(values)
    local parts = {}
    for _, field in ipairs(Display.KEYS) do
        if field ~= "contrast" or Display.HasContrast() then
            parts[#parts + 1] = UI.ValueLabel(field) .. " " .. UI.FormatValue(field, values[field])
        end
    end
    return table.concat(parts, ", ")
end

-- Adds the six mode radio items to a menu (Blizzard Menu API root description).
-- Used by both the settings dropdown and the minimap button menu.
function UI.AddModeItems(root)
    local function isSelected(mode) return Core.GetMode() == mode end
    local function setSelected(mode) Core.SetMode(mode) end
    root:CreateRadio(UI.ModeLabel("disabled"), isSelected, setSelected, "disabled")
    root:CreateRadio(UI.ModeLabel("auto"), isSelected, setSelected, "auto")
    root:CreateDivider()
    for _, key in ipairs(Schedule.ORDER) do
        root:CreateRadio(UI.ModeLabel(key), isSelected, setSelected, key)
    end
end
