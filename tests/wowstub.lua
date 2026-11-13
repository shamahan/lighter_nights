-- Fake game API for tests: CVars, server clock, timers, event frames.
-- Usage: local stub = dofile(ADDON_ROOT .. "/tests/wowstub.lua"); stub.reset()
local stub = {}

function stub.reset()
    stub.cvars = { Gamma = "1.2000000476837", Brightness = "50", Contrast = "50" }
    stub.writes = {}   -- every SetCVar call, in order: { name, value }
    stub.hour, stub.minute = 12, 0
    stub.now = 0       -- fake clock in seconds, moved by stub.advance
    stub.timers = {}
    stub.frames = {}
    SlashCmdList = {}
    LighterNightsDB = nil
    geterrorhandler = nil
end

function GetCVar(name) return stub.cvars[name] end

function SetCVar(name, value)
    stub.cvars[name] = tostring(value)
    stub.writes[#stub.writes + 1] = { name, tostring(value) }
end

C_CVar = { GetCVar = GetCVar, SetCVar = SetCVar }

function GetGameTime() return stub.hour, stub.minute end

C_Timer = {}

function C_Timer.NewTicker(interval, callback, iterations)
    local timer = { interval = interval, callback = callback, remaining = iterations, nextAt = stub.now + interval }
    function timer:Cancel() self.cancelled = true end
    function timer:IsCancelled() return self.cancelled == true end
    stub.timers[#stub.timers + 1] = timer
    return timer
end

-- Moves the fake clock forward, firing due tickers in time order.
function stub.advance(seconds)
    local target = stub.now + seconds + 1e-6
    while true do
        local due
        for _, timer in ipairs(stub.timers) do
            if not timer.cancelled and timer.nextAt <= target and (not due or timer.nextAt < due.nextAt) then
                due = timer
            end
        end
        if not due then break end
        stub.now = due.nextAt
        due.nextAt = due.nextAt + due.interval
        if due.remaining then
            due.remaining = due.remaining - 1
            if due.remaining <= 0 then due.cancelled = true end
        end
        due.callback(due)
    end
    stub.now = target - 1e-6
end

function CreateFrame()
    local frame = { events = {}, scripts = {} }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:SetScript(name, fn) self.scripts[name] = fn end
    stub.frames[#stub.frames + 1] = frame
    return frame
end

-- Delivers an event to every frame registered for it.
function stub.fire(event, ...)
    for _, frame in ipairs(stub.frames) do
        if frame.events[event] and frame.scripts.OnEvent then
            frame.scripts.OnEvent(frame, event, ...)
        end
    end
end

function stub.setTime(hour, minute) stub.hour, stub.minute = hour, minute end

function stub.cvar(name) return tonumber(stub.cvars[name]) end

stub.reset()
return stub
