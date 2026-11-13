local stub = dofile(ADDON_ROOT .. "/tests/wowstub.lua")

-- Loads a fresh addon core. opts: saved (SavedVariables), hour, minute, enter (default true).
local function fresh(opts)
    opts = opts or {}
    stub.reset()
    stub.setTime(opts.hour or 12, opts.minute or 0)
    if opts.cvars then
        for name, value in pairs(opts.cvars) do stub.cvars[name] = value end
    end
    LighterNightsDB = opts.saved
    local ns = {}
    harness.load("Schedule.lua", ns)
    harness.load("Display.lua", ns)
    harness.load("Core.lua", ns)
    stub.fire("ADDON_LOADED", "LighterNights")
    if opts.enter ~= false then stub.fire("PLAYER_ENTERING_WORLD") end
    return ns.Core, ns
end

local function gamma() return stub.cvar("Gamma") end

test("first run: baseline from CVars, default sections, mode auto", function()
    local Core = fresh({ enter = false })
    local db = Core.GetDB()
    eq(LighterNightsDB, db, "saved variable points at the db")
    eq(db.mode, "auto")
    near(db.baseline.gamma, 1.2)
    eq(db.baseline.brightness, 50)
    eq(db.baseline.contrast, 50)
    eq(db.sections.morning.start, 330)
    eq(db.sections.day.start, 480)
    eq(db.sections.evening.start, 1080)
    eq(db.sections.night.start, 1260)
    near(db.sections.morning.gamma, 1.3)
    near(db.sections.day.gamma, 1.2)
    near(db.sections.evening.gamma, 1.3)
    near(db.sections.night.gamma, 1.5)
    eq(db.sections.night.brightness, 50)
    eq(db.sections.night.enabled, true)
    eq(db.minimap.hide, false)
end)

test("default night gamma is clamped to 2.8", function()
    local Core = fresh({ enter = false, cvars = { Gamma = "2.7" } })
    near(Core.GetDB().sections.night.gamma, 2.8)
end)

test("damaged saved settings are repaired", function()
    local Core = fresh({ enter = false, saved = {
        mode = "banana",
        baseline = { gamma = "x", brightness = 500 },
        sections = { night = { enabled = "yes", start = 5000, gamma = 99, brightness = "abc" }, day = 7 },
        minimap = "no",
    } })
    local db = Core.GetDB()
    eq(db.mode, "auto")
    near(db.baseline.gamma, 1.2, "baseline gamma falls back to the CVar")
    eq(db.baseline.brightness, 100, "baseline brightness clamped")
    eq(db.sections.night.enabled, true)
    eq(db.sections.night.start, 1260)
    near(db.sections.night.gamma, 2.8)
    eq(db.sections.night.brightness, 100, "defaults follow the repaired baseline")
    eq(db.sections.day.start, 480)
    eq(db.minimap.hide, false)
end)

test("saved settings survive a reload unchanged", function()
    local Core = fresh({ enter = false, saved = {
        mode = "night",
        baseline = { gamma = 1.1, brightness = 45, contrast = 55 },
        sections = { morning = { enabled = false, start = 400, gamma = 1.25, brightness = 52, contrast = 48 } },
        minimap = { hide = true, minimapPos = 123 },
    } })
    local db = Core.GetDB()
    eq(db.mode, "night")
    near(db.baseline.gamma, 1.1)
    eq(db.sections.morning.enabled, false)
    eq(db.sections.morning.start, 400)
    near(db.sections.morning.gamma, 1.25)
    eq(db.sections.morning.brightness, 52)
    eq(db.minimap.hide, true)
    eq(db.minimap.minimapPos, 123)
end)

test("a non-numeric minimap position is dropped", function()
    local Core = fresh({ enter = false, saved = { minimap = { hide = true, minimapPos = "left" } } })
    eq(Core.GetDB().minimap.minimapPos, nil)
    eq(Core.GetDB().minimap.hide, true)
end)

test("entering the world applies the section for the server time at once", function()
    local Core = fresh({ hour = 22 })
    eq(Core.GetApplied(), "night")
    near(gamma(), 1.5)
    local Core2 = fresh({ hour = 12 })
    eq(Core2.GetApplied(), "day")
    near(gamma(), 1.2)
end)

test("later loading screens do not re-apply", function()
    local Core = fresh({ hour = 22 })
    stub.cvars.Gamma = "0.9"
    stub.fire("PLAYER_ENTERING_WORLD")
    near(gamma(), 0.9)
end)

test("disabled mode touches nothing at login and at logout", function()
    local Core = fresh({ hour = 22, saved = { mode = "disabled", baseline = { gamma = 1.0, brightness = 50, contrast = 50 } } })
    eq(Core.GetApplied(), nil)
    eq(#stub.writes, 0, "no CVar writes at login")
    stub.cvars.Gamma = "1.7"
    stub.fire("PLAYER_LOGOUT")
    near(gamma(), 1.7)
end)

test("the tick fades to the next section when the server time crosses its start", function()
    local Core = fresh({ hour = 20, minute = 59 })
    eq(Core.GetApplied(), "evening")
    near(gamma(), 1.3)
    local notified = 0
    Core.RegisterListener(function() notified = notified + 1 end)
    stub.setTime(21, 0)
    stub.advance(5)
    eq(Core.GetApplied(), "night")
    near(gamma(), 1.3, "fade has only just started")
    eq(notified, 1)
    stub.advance(5)
    near(gamma(), 1.5)
end)

test("a fixed mode ignores the time and the section checkbox", function()
    local Core = fresh({ hour = 12 })
    Core.SetSectionEnabled("night", false)
    Core.SetMode("night")
    eq(Core.GetApplied(), "night")
    stub.advance(5)
    near(gamma(), 1.5)
    stub.setTime(13, 0)
    stub.advance(20)
    eq(Core.GetApplied(), "night")
end)

test("SetMode fades instead of jumping", function()
    local Core = fresh({ hour = 12 })
    Core.SetMode("night")
    near(gamma(), 1.2, "not changed yet")
    stub.advance(2.5)
    near(gamma(), 1.35, "halfway")
    stub.advance(2.5)
    near(gamma(), 1.5)
end)

test("entering disabled restores the baseline", function()
    local Core = fresh({ hour = 22 })
    near(gamma(), 1.5)
    Core.SetMode("disabled")
    eq(Core.GetApplied(), nil)
    stub.advance(5)
    near(gamma(), 1.2)
end)

test("leaving disabled re-reads the baseline from the CVars", function()
    local Core = fresh({ hour = 22 })
    Core.SetMode("disabled")
    stub.advance(5)
    stub.cvars.Gamma = "1.0" -- the user changed it in the system options
    stub.cvars.Brightness = "55"
    Core.SetMode("auto")
    near(Core.GetBaseline().gamma, 1.0)
    eq(Core.GetBaseline().brightness, 55)
    stub.advance(5)
    near(gamma(), 1.5, "night section applied again")
end)

test("leaving disabled during the fade back does not re-read the baseline", function()
    local Core = fresh({ hour = 22 })
    Core.SetMode("disabled")
    stub.advance(2.5) -- gamma is halfway between 1.5 and 1.2
    Core.SetMode("auto")
    near(Core.GetBaseline().gamma, 1.2)
end)

test("RememberBaseline works only in disabled mode after the fade", function()
    local Core = fresh({ hour = 22 })
    eq(Core.RememberBaseline(), false, "not in auto")
    Core.SetMode("disabled")
    eq(Core.CanRememberBaseline(), false, "not while fading")
    eq(Core.RememberBaseline(), false)
    stub.advance(5)
    eq(Core.CanRememberBaseline(), true)
    stub.cvars.Gamma = "0.9"
    eq(Core.RememberBaseline(), true)
    near(Core.GetBaseline().gamma, 0.9)
end)

test("listeners hear the end of a fade", function()
    local Core = fresh({ hour = 22 })
    Core.SetMode("disabled")
    local notified = 0
    Core.RegisterListener(function() notified = notified + 1 end)
    stub.advance(5)
    eq(notified, 1)
end)

test("moving a slider of the applied section applies at once", function()
    local Core = fresh({ hour = 22 })
    Core.SetSectionValue("night", "gamma", 1.83)
    near(Core.GetSection("night").gamma, 1.85, "snapped to the step")
    near(gamma(), 1.85)
    Core.SetSectionValue("night", "brightness", 61)
    eq(stub.cvar("Brightness"), 61)
end)

test("moving a slider of another section changes only the saved value", function()
    local Core = fresh({ hour = 22 })
    Core.SetSectionValue("day", "gamma", 0.8)
    near(Core.GetSection("day").gamma, 0.8)
    near(gamma(), 1.5)
end)

test("a slider move cancels a running fade", function()
    local Core = fresh({ hour = 12 })
    Core.SetMode("night")
    stub.advance(1)
    Core.SetSectionValue("night", "gamma", 2.0)
    near(gamma(), 2.0)
    stub.advance(10)
    near(gamma(), 2.0)
end)

test("disabling the applied section in auto fades to the previous enabled one", function()
    local Core = fresh({ hour = 22 })
    Core.SetSectionEnabled("night", false)
    eq(Core.GetApplied(), "evening")
    stub.advance(5)
    near(gamma(), 1.3)
end)

test("all sections disabled in auto: baseline, icon still follows the time", function()
    local Core = fresh({ hour = 22 })
    for _, key in ipairs({ "morning", "day", "evening", "night" }) do Core.SetSectionEnabled(key, false) end
    eq(Core.GetApplied(), nil)
    eq(Core.GetIconSection(), "night")
    stub.advance(5)
    near(gamma(), 1.2)
end)

test("changing a start time re-resolves the applied section", function()
    local Core = fresh({ hour = 20 })
    eq(Core.GetApplied(), "evening")
    Core.SetSectionStart("night", 1190) -- 19:50
    eq(Core.GetApplied(), "night")
    Core.SetSectionStart("night", 5000)
    eq(Core.GetSection("night").start, 1190, "invalid start ignored")
end)

test("the icon section follows the time in disabled mode and listeners hear it", function()
    local Core = fresh({ hour = 20, minute = 59, saved = { mode = "disabled", baseline = { gamma = 1.2, brightness = 50, contrast = 50 } } })
    eq(Core.GetIconSection(), "evening")
    local notified = 0
    Core.RegisterListener(function() notified = notified + 1 end)
    stub.setTime(21, 0)
    stub.advance(5)
    eq(Core.GetIconSection(), "night")
    eq(notified, 1)
    eq(#stub.writes, 0, "still no CVar writes")
end)

test("ResetSections restores defaults from the baseline and applies at once", function()
    local Core = fresh({ hour = 22 })
    local night = Core.GetSection("night")
    Core.SetSectionValue("night", "gamma", 2.5)
    Core.SetSectionStart("night", 100)
    Core.SetSectionEnabled("night", false)
    Core.ResetSections()
    eq(Core.GetSection("night"), night, "section tables are kept, not replaced")
    eq(night.start, 1260)
    eq(night.enabled, true)
    near(night.gamma, 1.5)
    eq(Core.GetApplied(), "night")
    near(gamma(), 1.5)
    eq(Core.GetMode(), "auto")
end)

test("ResetSections with nothing to change leaves the CVars and a running fade alone", function()
    local Core = fresh({ hour = 12 })
    Core.SetMode("night")
    stub.advance(2.5)
    local writes = #stub.writes
    Core.ResetSections()
    eq(#stub.writes, writes, "no CVar writes")
    near(gamma(), 1.35, "fade still halfway")
    stub.advance(2.5)
    near(gamma(), 1.5, "fade ran to its end")
end)

test("ResetSections leaves the baseline unchanged", function()
    local Core = fresh({ hour = 22 })
    Core.SetSectionValue("night", "gamma", 2.5)
    Core.ResetSections()
    near(Core.GetBaseline().gamma, 1.2)
    eq(Core.GetBaseline().brightness, 50)
    eq(Core.GetBaseline().contrast, 50)
end)

test("logout in disabled mode during the fade back sets the baseline at once", function()
    local Core = fresh({ hour = 22 })
    Core.SetMode("disabled")
    stub.advance(2.5) -- gamma is halfway between 1.5 and 1.2
    stub.fire("PLAYER_LOGOUT")
    near(gamma(), 1.2)
end)

test("logout restores the baseline at once, even in the middle of a fade", function()
    local Core = fresh({ hour = 12 })
    Core.SetMode("night")
    stub.advance(2)
    stub.fire("PLAYER_LOGOUT")
    near(gamma(), 1.2)
    eq(stub.cvar("Brightness"), 50)
end)

test("OnReady runs at once after load and is queued before it", function()
    stub.reset()
    local ns = {}
    harness.load("Schedule.lua", ns)
    harness.load("Display.lua", ns)
    harness.load("Core.lua", ns)
    local calls = 0
    ns.Core.OnReady(function() calls = calls + 1 end)
    eq(calls, 0)
    stub.fire("ADDON_LOADED", "SomeOtherAddon")
    eq(calls, 0)
    stub.fire("ADDON_LOADED", "LighterNights")
    eq(calls, 1)
    ns.Core.OnReady(function() calls = calls + 1 end)
    eq(calls, 2)
end)

test("an error in one listener is reported and does not stop the others", function()
    local Core = fresh()
    local reported, second = {}, 0
    geterrorhandler = function() return function(message) reported[#reported + 1] = message end end
    Core.RegisterListener(function() error("boom") end)
    Core.RegisterListener(function() second = second + 1 end)
    Core.SetMinimapHidden(true)
    geterrorhandler = nil
    eq(second, 1, "second listener ran")
    eq(#reported, 1, "error reported once")
    eq(tostring(reported[1]):find("boom", 1, true) ~= nil, true, "message kept")
end)

test("an error in one ready callback does not stop the others", function()
    stub.reset()
    local ns = {}
    harness.load("Schedule.lua", ns)
    harness.load("Display.lua", ns)
    harness.load("Core.lua", ns)
    local reported, second = {}, 0
    geterrorhandler = function() return function(message) reported[#reported + 1] = message end end
    ns.Core.OnReady(function() error("boom") end)
    ns.Core.OnReady(function() second = second + 1 end)
    stub.fire("ADDON_LOADED", "LighterNights")
    geterrorhandler = nil
    eq(second, 1, "second callback ran")
    eq(#reported, 1, "error reported once")
end)

test("SetMinimapHidden stores the flag and notifies", function()
    local Core = fresh()
    local notified = 0
    Core.RegisterListener(function() notified = notified + 1 end)
    Core.SetMinimapHidden(true)
    eq(Core.GetDB().minimap.hide, true)
    eq(notified, 1)
end)

test("/ln switches modes and opens the options", function()
    local Core = fresh({ hour = 12 })
    local opened = 0
    Core.OpenOptions = function() opened = opened + 1 end
    SlashCmdList["LIGHTERNIGHTS"]("")
    eq(opened, 1)
    SlashCmdList["LIGHTERNIGHTS"](" Night ")
    eq(Core.GetMode(), "night")
    SlashCmdList["LIGHTERNIGHTS"]("off")
    eq(Core.GetMode(), "disabled")
    SlashCmdList["LIGHTERNIGHTS"]("auto")
    eq(Core.GetMode(), "auto")
end)
