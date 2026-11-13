-- Every locale must translate exactly the keys of enUS.
local LOCALES = { "deDE", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }

local current = "enUS"
function GetLocale() return current end

local function loadLocale(code)
    current = code
    local ns = {}
    harness.load("Locales/enUS.lua", ns)
    local base = {}
    for key, value in pairs(ns.L) do base[key] = value end
    if code ~= "enUS" then harness.load("Locales/" .. code .. ".lua", ns) end
    return ns.L, base
end

test("enUS defines non-empty strings", function()
    local L = loadLocale("enUS")
    local count = 0
    for key, value in pairs(L) do
        count = count + 1
        eq(type(value), "string", key)
        eq(value ~= "", true, key)
    end
    eq(count, 24, "number of keys")
end)

for _, code in ipairs(LOCALES) do
    test(code .. " has exactly the enUS keys", function()
        local L, base = loadLocale(code)
        for key in pairs(L) do
            eq(base[key] ~= nil, true, "unknown key " .. key)
        end
        -- Re-load the locale into an empty table to see which keys it sets itself.
        current = code
        local own = { L = {} }
        harness.load("Locales/" .. code .. ".lua", own)
        for key in pairs(base) do
            eq(type(own.L[key]), "string", "missing key " .. key)
            eq(own.L[key] ~= "", true, "empty key " .. key)
        end
    end)

    test(code .. " is skipped on another client language", function()
        current = "enUS"
        local own = { L = {} }
        harness.load("Locales/" .. code .. ".lua", own)
        eq(next(own.L), nil, "no keys set")
    end)
end
