-- Owns the saved settings and decides what to apply and when.
-- UI files (Options, Minimap) only read state here and call the setters.
local ADDON, ns = ...
local Schedule, Display = ns.Schedule, ns.Display

local Core = {}
ns.Core = Core

Core.MODES = { "disabled", "auto", "morning", "day", "evening", "night" }
Core.TICK_SECONDS = 5

-- Set by Options.lua: opens the settings window.
Core.OpenOptions = nil

local DEFAULT_START = { morning = 330, day = 480, evening = 1080, night = 1260 }
local DEFAULT_GAMMA_OFFSET = { morning = 0.1, day = 0, evening = 0.1, night = 0.3 }
local FALLBACK = { gamma = 1.0, brightness = 50, contrast = 50 }

local db                    -- LighterNightsDB after validation
local applied               -- key of the section whose values are in effect, or nil (baseline)
local lastIcon              -- icon section seen by the last tick
local entered = false       -- first PLAYER_ENTERING_WORLD handled
local listeners = {}
local readyCallbacks = {}

local function isMode(mode)
    for _, known in ipairs(Core.MODES) do
        if known == mode then return true end
    end
    return false
end

-- An error in one UI module is reported to the game's error handler but does
-- not stop the other listeners. (The test stub has no error handler, so tests
-- still see raw errors.)
local function safeCall(fn)
    if geterrorhandler then
        xpcall(fn, geterrorhandler())
    else
        fn()
    end
end

local function notify()
    for _, listener in ipairs(listeners) do safeCall(listener) end
end

local function serverMinute()
    local hour, minute = GetGameTime()
    return (hour or 0) * 60 + (minute or 0)
end

local function defaultSection(key, baseline)
    return {
        enabled = true,
        start = DEFAULT_START[key],
        gamma = Display.Normalize("gamma", baseline.gamma + DEFAULT_GAMMA_OFFSET[key]),
        brightness = Display.Normalize("brightness", baseline.brightness),
        contrast = Display.Normalize("contrast", baseline.contrast),
    }
end

-- Builds a valid settings table from whatever was saved (possibly nil or damaged).
--   saved   : the SavedVariables value
--   current : Display.Read() result, used as the baseline on first run
function Core.BuildDB(saved, current)
    saved = type(saved) == "table" and saved or {}
    local savedBaseline = type(saved.baseline) == "table" and saved.baseline or {}
    local savedSections = type(saved.sections) == "table" and saved.sections or {}

    local out = { version = 1 }

    out.baseline = {}
    for _, key in ipairs(Display.KEYS) do
        local value = tonumber(savedBaseline[key]) or current[key] or FALLBACK[key]
        local limit = Display.LIMITS[key]
        out.baseline[key] = math.max(limit.min, math.min(limit.max, value))
    end

    out.mode = isMode(saved.mode) and saved.mode or "auto"

    out.sections = {}
    for _, key in ipairs(Schedule.ORDER) do
        local section = defaultSection(key, out.baseline)
        local savedSection = type(savedSections[key]) == "table" and savedSections[key] or {}
        if type(savedSection.enabled) == "boolean" then section.enabled = savedSection.enabled end
        local start = tonumber(savedSection.start)
        if start and start >= 0 and start <= 1439 then section.start = math.floor(start) end
        for _, field in ipairs(Display.KEYS) do
            local value = tonumber(savedSection[field])
            if value then section[field] = Display.Normalize(field, value) end
        end
        out.sections[key] = section
    end

    out.minimap = type(saved.minimap) == "table" and saved.minimap or {}
    if type(out.minimap.hide) ~= "boolean" then out.minimap.hide = false end
    if type(out.minimap.minimapPos) ~= "number" then out.minimap.minimapPos = nil end

    return out
end

local function computeApplied()
    if db.mode == "disabled" then return nil end
    if db.mode == "auto" then return Schedule.Resolve(db.sections, serverMinute(), false) end
    return db.mode
end

-- Values of a section, or the baseline when key is nil.
local function valuesFor(key)
    local source = key and db.sections[key] or db.baseline
    return { gamma = source.gamma, brightness = source.brightness, contrast = source.contrast }
end

local function captureBaseline()
    local current = Display.Read()
    for _, key in ipairs(Display.KEYS) do
        if current[key] ~= nil then db.baseline[key] = current[key] end
    end
end

-- Re-resolves the applied section after a schedule edit; fades when it changed.
local function reevaluate()
    local now = computeApplied()
    if now ~= applied then
        applied = now
        if entered then Display.Apply(valuesFor(applied), Display.FADE_SECONDS) end
    end
    notify()
end

local function tick()
    local changed = false
    if db.mode == "auto" then
        local now = computeApplied()
        if now ~= applied then
            applied = now
            Display.Apply(valuesFor(applied), Display.FADE_SECONDS)
            changed = true
        end
    end
    local icon = Core.GetIconSection()
    if icon ~= lastIcon then
        lastIcon = icon
        changed = true
    end
    if changed then notify() end
end

---------------------------------------------------------------------------
-- Reading state
---------------------------------------------------------------------------

function Core.GetDB() return db end
function Core.GetMode() return db.mode end
function Core.GetSection(key) return db.sections[key] end
function Core.GetBaseline() return db.baseline end
function Core.GetServerMinute() return serverMinute() end

-- Key of the section whose values are in effect, or nil when the baseline is.
function Core.GetApplied() return applied end

-- Section to show on the icon: the applied one, or the time of day over all
-- four sections (checkboxes ignored) when nothing is applied.
function Core.GetIconSection()
    return applied or Schedule.Resolve(db.sections, serverMinute(), true)
end

-- Values in effect right now: the applied section's, or the baseline.
function Core.GetValues() return valuesFor(applied) end

function Core.CanRememberBaseline()
    return db.mode == "disabled" and not Display.IsFading()
end

---------------------------------------------------------------------------
-- Changing state
---------------------------------------------------------------------------

-- fn() is called after every state change.
function Core.RegisterListener(fn)
    listeners[#listeners + 1] = fn
end

-- fn() is called once the saved settings are loaded (at once if they already are).
function Core.OnReady(fn)
    if db then fn() else readyCallbacks[#readyCallbacks + 1] = fn end
end

function Core.SetMode(mode)
    if not isMode(mode) or mode == db.mode then return end
    -- Leaving "disabled": keep what the user set in the system options meanwhile,
    -- unless the fade back to the baseline is still running.
    if db.mode == "disabled" and not Display.IsFading() then captureBaseline() end
    db.mode = mode
    applied = computeApplied()
    if entered then Display.Apply(valuesFor(applied), Display.FADE_SECONDS) end
    notify()
end

function Core.SetSectionEnabled(key, enabled)
    local section = db.sections[key]
    if not section then return end
    section.enabled = enabled and true or false
    reevaluate()
end

function Core.SetSectionStart(key, minute)
    local section = db.sections[key]
    minute = tonumber(minute)
    if not section or not minute or minute < 0 or minute > 1439 then return end
    section.start = math.floor(minute)
    reevaluate()
end

-- field: "gamma", "brightness" or "contrast".
function Core.SetSectionValue(key, field, value)
    local section = db.sections[key]
    value = tonumber(value)
    if not section or not Display.LIMITS[field] or not value then return end
    value = Display.Normalize(field, value)
    if section[field] == value then return end
    section[field] = value
    if entered and key == applied then Display.Apply(valuesFor(applied), 0) end
    notify()
end

-- Restores the default times and values of all sections. Applies at once, but
-- only when the applied section or its values actually changed.
function Core.ResetSections()
    local appliedBefore, valuesBefore = applied, valuesFor(applied)
    for _, key in ipairs(Schedule.ORDER) do
        local section, default = db.sections[key], defaultSection(key, db.baseline)
        for field, value in pairs(default) do section[field] = value end
    end
    applied = computeApplied()
    if entered and db.mode ~= "disabled" then
        local valuesAfter = valuesFor(applied)
        local changed = applied ~= appliedBefore
        for _, field in ipairs(Display.KEYS) do
            if valuesAfter[field] ~= valuesBefore[field] then changed = true end
        end
        if changed then Display.Apply(valuesAfter, 0) end
    end
    notify()
end

-- Saves the current CVars as the baseline. Only in "disabled" mode, after the fade.
function Core.RememberBaseline()
    if not Core.CanRememberBaseline() then return false end
    captureBaseline()
    notify()
    return true
end

function Core.SetMinimapHidden(hidden)
    db.minimap.hide = hidden and true or false
    notify()
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

Display.OnFadeFinished = notify

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        self:UnregisterEvent("ADDON_LOADED")
        db = Core.BuildDB(LighterNightsDB, Display.Read())
        LighterNightsDB = db
        local callbacks = readyCallbacks
        readyCallbacks = {}
        for _, fn in ipairs(callbacks) do safeCall(fn) end
    elseif event == "PLAYER_ENTERING_WORLD" then
        if entered or not db then return end
        entered = true
        applied = computeApplied()
        lastIcon = Core.GetIconSection()
        if db.mode ~= "disabled" then Display.Apply(valuesFor(applied), 0) end
        C_Timer.NewTicker(Core.TICK_SECONDS, tick)
        notify()
    elseif event == "PLAYER_LOGOUT" then
        -- Leave the user's own values behind. In "disabled" mode the CVars are
        -- already theirs, unless the fade back to the baseline is still running.
        if db and (db.mode ~= "disabled" or Display.IsFading()) then
            Display.Apply(valuesFor(nil), 0)
        end
    end
end)

---------------------------------------------------------------------------
-- /ln
---------------------------------------------------------------------------

SLASH_LIGHTERNIGHTS1 = "/ln"
SLASH_LIGHTERNIGHTS2 = "/lighternights"
SlashCmdList["LIGHTERNIGHTS"] = function(message)
    local command = (message or ""):lower():match("^%s*(.-)%s*$")
    if command == "" then
        if Core.OpenOptions then Core.OpenOptions() end
        return
    end
    if command == "off" then command = "disabled" end
    if isMode(command) then
        Core.SetMode(command)
        return
    end
    print("|cffffd36bLighterNights:|r /ln [auto | off | morning | day | evening | night]")
end
