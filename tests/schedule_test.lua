local ns = {}
harness.load("Schedule.lua", ns)
local Schedule = ns.Schedule

local function sections(overrides)
    local s = {
        morning = { enabled = true, start = 330 },  -- 05:30
        day     = { enabled = true, start = 480 },  -- 08:00
        evening = { enabled = true, start = 1080 }, -- 18:00
        night   = { enabled = true, start = 1260 }, -- 21:00
    }
    for key, fields in pairs(overrides or {}) do
        for field, value in pairs(fields) do s[key][field] = value end
    end
    return s
end

local OFF = { enabled = false }

test("each section is in effect from its start time", function()
    local s = sections()
    eq(Schedule.Resolve(s, 330), "morning")
    eq(Schedule.Resolve(s, 479), "morning")
    eq(Schedule.Resolve(s, 480), "day")
    eq(Schedule.Resolve(s, 1079), "day")
    eq(Schedule.Resolve(s, 1080), "evening")
    eq(Schedule.Resolve(s, 1259), "evening")
    eq(Schedule.Resolve(s, 1260), "night")
end)

test("night wraps past midnight until morning starts", function()
    local s = sections()
    eq(Schedule.Resolve(s, 1439), "night")
    eq(Schedule.Resolve(s, 0), "night")
    eq(Schedule.Resolve(s, 329), "night")
end)

test("a disabled section gives its time to the previous enabled one", function()
    local s = sections({ evening = OFF })
    eq(Schedule.Resolve(s, 1100), "day")
    eq(Schedule.Resolve(s, 1260), "night")
end)

test("disabled night: evening lasts through midnight", function()
    local s = sections({ night = OFF })
    eq(Schedule.Resolve(s, 1300), "evening")
    eq(Schedule.Resolve(s, 100), "evening")
end)

test("only one section enabled: it is in effect all day", function()
    local s = sections({ morning = OFF, evening = OFF, night = OFF })
    eq(Schedule.Resolve(s, 0), "day")
    eq(Schedule.Resolve(s, 479), "day")
    eq(Schedule.Resolve(s, 480), "day")
    eq(Schedule.Resolve(s, 1439), "day")
end)

test("no section enabled: nil", function()
    local s = sections({ morning = OFF, day = OFF, evening = OFF, night = OFF })
    eq(Schedule.Resolve(s, 600), nil)
end)

test("ignoreEnabled resolves over all four sections", function()
    local s = sections({ morning = OFF, day = OFF, evening = OFF, night = OFF })
    eq(Schedule.Resolve(s, 600, true), "day")
    eq(Schedule.Resolve(s, 100, true), "night")
end)

test("equal start times: the later section in the fixed order wins", function()
    local s = sections({ day = { start = 330 } })
    eq(Schedule.Resolve(s, 400), "day")
    s = sections({ morning = { start = 1260 } })
    eq(Schedule.Resolve(s, 100), "night")
end)

test("start times out of order are simply sorted by time", function()
    local s = sections({ morning = { start = 600 }, day = { start = 300 } })
    eq(Schedule.Resolve(s, 400), "day")
    eq(Schedule.Resolve(s, 700), "morning")
    eq(Schedule.Resolve(s, 100), "night")
end)

test("ParseTime accepts 5:30, 05:30 and 0530", function()
    eq(Schedule.ParseTime("5:30"), 330)
    eq(Schedule.ParseTime("05:30"), 330)
    eq(Schedule.ParseTime("0530"), 330)
    eq(Schedule.ParseTime(" 21:00 "), 1260)
    eq(Schedule.ParseTime("0:00"), 0)
    eq(Schedule.ParseTime("23:59"), 1439)
end)

test("ParseTime rejects invalid input", function()
    eq(Schedule.ParseTime("24:00"), nil)
    eq(Schedule.ParseTime("12:60"), nil)
    eq(Schedule.ParseTime("530"), nil)
    eq(Schedule.ParseTime("5:3"), nil)
    eq(Schedule.ParseTime("abc"), nil)
    eq(Schedule.ParseTime(""), nil)
    eq(Schedule.ParseTime(nil), nil)
end)

test("FormatTime pads to HH:MM", function()
    eq(Schedule.FormatTime(0), "00:00")
    eq(Schedule.FormatTime(330), "05:30")
    eq(Schedule.FormatTime(1439), "23:59")
end)
