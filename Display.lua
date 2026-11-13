-- The only file that reads or writes the Gamma / Brightness / Contrast CVars.
local _, ns = ...

local Display = {}
ns.Display = Display

Display.KEYS = { "gamma", "brightness", "contrast" }
Display.LIMITS = {
    gamma      = { min = 0.3, max = 2.8, step = 0.05 },
    brightness = { min = 0,   max = 100, step = 1 },
    contrast   = { min = 0,   max = 100, step = 1 },
}
Display.FADE_SECONDS = 5
Display.FADE_STEP = 0.1

-- Called (if set) when a fade runs to its end. Not called when a fade is replaced.
Display.OnFadeFinished = nil

local CVARS = { gamma = "Gamma", brightness = "Brightness", contrast = "Contrast" }
local WRITE_FORMAT = { gamma = "%.3f", brightness = "%.1f", contrast = "%.1f" }

local getCVar = (C_CVar and C_CVar.GetCVar) or GetCVar
local setCVar = (C_CVar and C_CVar.SetCVar) or SetCVar

local fade -- the running fade, or nil

local function clamp(key, value)
    local limit = Display.LIMITS[key]
    if value < limit.min then return limit.min end
    if value > limit.max then return limit.max end
    return value
end

-- Clamps a value into the allowed range and snaps it to the slider step.
function Display.Normalize(key, value)
    local limit = Display.LIMITS[key]
    value = math.floor(value / limit.step + 0.5) * limit.step
    value = math.floor(value * 100 + 0.5) / 100
    return clamp(key, value)
end

-- True when the client has the Contrast CVar.
function Display.HasContrast()
    return getCVar(CVARS.contrast) ~= nil
end

-- Returns the current values as { gamma, brightness, contrast }.
-- A key is absent when its CVar does not exist in this client.
function Display.Read()
    local values = {}
    for _, key in ipairs(Display.KEYS) do
        local raw = getCVar(CVARS[key])
        local number = tonumber(raw)
        if number then values[key] = clamp(key, number) end
    end
    return values
end

local function write(values)
    for _, key in ipairs(Display.KEYS) do
        local value = values[key]
        if value ~= nil and getCVar(CVARS[key]) ~= nil then
            setCVar(CVARS[key], string.format(WRITE_FORMAT[key], clamp(key, value)))
        end
    end
end

local function stopFade()
    if fade then
        fade.ticker:Cancel()
        fade = nil
    end
end

function Display.IsFading()
    return fade ~= nil
end

-- Applies { gamma, brightness, contrast }.
-- seconds == nil or 0: at once. Otherwise: linear fade from the current CVar values.
-- Any running fade is replaced.
function Display.Apply(values, seconds)
    stopFade()
    local target = {}
    for _, key in ipairs(Display.KEYS) do target[key] = values[key] end

    local from = Display.Read()
    local differs = false
    for _, key in ipairs(Display.KEYS) do
        if from[key] ~= nil and target[key] ~= nil and math.abs(from[key] - target[key]) > 0.0005 then
            differs = true
        end
    end
    if not seconds or seconds <= 0 or not differs then
        write(target)
        return
    end

    local steps = math.max(1, math.floor(seconds / Display.FADE_STEP + 0.5))
    local state = { step = 0 }
    fade = state
    state.ticker = C_Timer.NewTicker(Display.FADE_STEP, function()
        if fade ~= state then return end
        state.step = state.step + 1
        if state.step >= steps then
            stopFade()
            write(target)
            if Display.OnFadeFinished then Display.OnFadeFinished() end
            return
        end
        local t = state.step / steps
        local mid = {}
        for _, key in ipairs(Display.KEYS) do
            if from[key] ~= nil and target[key] ~= nil then
                mid[key] = from[key] + (target[key] - from[key]) * t
            end
        end
        write(mid)
    end, steps)
end
