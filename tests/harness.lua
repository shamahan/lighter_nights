-- Minimal test harness. tests/run.py loads it before each suite.
harness = { ran = 0, failed = 0 }

-- Loads an addon file the way the game does: chunk(addonName, namespace).
function harness.load(relPath, ns)
    local chunk, err = loadfile(ADDON_ROOT .. "/" .. relPath)
    if not chunk then error(err, 0) end
    return chunk("LighterNights", ns)
end

function test(name, fn)
    harness.ran = harness.ran + 1
    local ok, err = xpcall(fn, debug.traceback)
    if ok then
        print("  ok    " .. name)
    else
        harness.failed = harness.failed + 1
        print("  FAIL  " .. name .. "\n        " .. tostring(err))
    end
    io.stdout:flush()
end

function eq(actual, expected, label)
    if actual ~= expected then
        error((label or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

function near(actual, expected, label)
    if type(actual) ~= "number" or math.abs(actual - expected) > 0.0005 then
        error((label or "value") .. ": expected about " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end
