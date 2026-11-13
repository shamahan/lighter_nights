-- Every file listed in the .toc must exist and compile as Lua 5.1.
-- This is the only automated check for the UI files, which need the game to run.

local function tocFiles()
    local files = {}
    for line in io.lines(ADDON_ROOT .. "/LighterNights.toc") do
        line = line:gsub("\r", ""):match("^%s*(.-)%s*$")
        if line ~= "" and line:sub(1, 1) ~= "#" then
            files[#files + 1] = (line:gsub("\\", "/"))
        end
    end
    return files
end

test("the .toc lists files", function()
    eq(#tocFiles() > 0, true)
end)

for _, path in ipairs(tocFiles()) do
    test("compiles: " .. path, function()
        local chunk, err = loadfile(ADDON_ROOT .. "/" .. path)
        if not chunk then error(err, 0) end
    end)
end

test("the .toc declares the saved variable and both clients", function()
    local text = io.open(ADDON_ROOT .. "/LighterNights.toc"):read("*a")
    eq(text:find("## SavedVariables: LighterNightsDB", 1, true) ~= nil, true, "SavedVariables")
    eq(text:find("16001", 1, true) ~= nil, true, "Forever interface")
    eq(text:find("120105", 1, true) ~= nil, true, "retail interface")
end)

test("the four icons exist", function()
    for _, name in ipairs({ "morning", "day", "evening", "night" }) do
        local file = io.open(ADDON_ROOT .. "/Media/" .. name .. ".png", "rb")
        eq(file ~= nil, true, name .. ".png")
        file:close()
    end
end)
