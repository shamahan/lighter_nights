-- Minimap button: icon for the current time of day, click opens the mode menu.
local _, ns = ...
local Core, Schedule, L, UI = ns.Core, ns.Schedule, ns.L, ns.UI

local NAME = "LighterNights"

local function openMenu(owner)
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(NAME)
        UI.AddModeItems(root)
        root:CreateDivider()
        root:CreateButton(L.SETTINGS, function()
            if Core.OpenOptions then Core.OpenOptions() end
        end)
    end)
end

local function showTooltip(tooltip)
    local applied = Core.GetApplied()
    tooltip:AddLine(NAME)
    tooltip:AddDoubleLine(L.MODE, UI.ModeLabel(Core.GetMode()), 1, 0.82, 0, 1, 1, 1)
    tooltip:AddDoubleLine(L.SERVER_TIME, Schedule.FormatTime(Core.GetServerMinute()), 1, 0.82, 0, 1, 1, 1)
    tooltip:AddDoubleLine(L.APPLIED, applied and UI.ModeLabel(applied) or L.BASELINE, 1, 0.82, 0, 1, 1, 1)
    tooltip:AddLine(UI.FormatValues(Core.GetValues()), 1, 1, 1)
    tooltip:AddLine(L.CLICK_HINT, 0.6, 0.6, 0.6)
end

Core.OnReady(function()
    local LDB = LibStub("LibDataBroker-1.1")
    local DBIcon = LibStub("LibDBIcon-1.0")

    local object = LDB:NewDataObject(NAME, {
        type = "launcher",
        text = NAME,
        icon = UI.ICONS[Core.GetIconSection()],
        OnClick = function(frame) openMenu(frame) end,
        OnTooltipShow = showTooltip,
    })

    DBIcon:Register(NAME, object, Core.GetDB().minimap)

    local hidden = Core.GetDB().minimap.hide

    local function update()
        object.icon = UI.ICONS[Core.GetIconSection()]
        -- Grey icon when no section is applied (disabled mode, or nothing enabled).
        local button = DBIcon:GetMinimapButton(NAME)
        if button and button.icon then
            button.icon:SetDesaturated(Core.GetApplied() == nil)
        end
        -- Show/Hide re-anchor the button, so only act when the flag changes.
        local wantHidden = Core.GetDB().minimap.hide
        if wantHidden ~= hidden then
            hidden = wantHidden
            if hidden then DBIcon:Hide(NAME) else DBIcon:Show(NAME) end
        end
    end

    Core.RegisterListener(update)
    update()
end)
