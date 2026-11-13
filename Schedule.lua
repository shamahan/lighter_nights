-- Pure schedule logic. No game API calls: this file is unit-tested outside the game.
local _, ns = ...

local Schedule = {}
ns.Schedule = Schedule

-- Fixed order of sections; also the tie-break order for equal start times.
Schedule.ORDER = { "morning", "day", "evening", "night" }

-- Returns the key of the section in effect at `minute` (0..1439), or nil when
-- there is no candidate section.
--   sections      : table key -> { enabled = boolean, start = minutes since midnight }
--   ignoreEnabled : when true, disabled sections are candidates too
function Schedule.Resolve(sections, minute, ignoreEnabled)
    local bestKey, bestStart -- latest start that is <= minute
    local lastKey, lastStart -- latest start of the whole day (wraps past midnight)
    for _, key in ipairs(Schedule.ORDER) do
        local section = sections[key]
        if section and (ignoreEnabled or section.enabled) then
            local start = section.start
            if start <= minute and (not bestStart or start >= bestStart) then
                bestKey, bestStart = key, start
            end
            if not lastStart or start >= lastStart then
                lastKey, lastStart = key, start
            end
        end
    end
    return bestKey or lastKey
end

-- Parses "5:30", "05:30" or "0530" into minutes since midnight; nil when invalid.
function Schedule.ParseTime(text)
    if type(text) ~= "string" then return nil end
    text = text:match("^%s*(.-)%s*$")
    local h, m = text:match("^(%d%d?):(%d%d)$")
    if not h then h, m = text:match("^(%d%d)(%d%d)$") end
    if not h then return nil end
    h, m = tonumber(h), tonumber(m)
    if h > 23 or m > 59 then return nil end
    return h * 60 + m
end

-- Formats minutes since midnight as "HH:MM".
function Schedule.FormatTime(minute)
    return string.format("%02d:%02d", math.floor(minute / 60), minute % 60)
end
