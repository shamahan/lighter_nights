-- Runs the whole addon (toc order, without Libs) against a permissive mock of the
-- game's widget API and drives the normal user actions. It cannot prove real client
-- behaviour; it catches typos, wrong names, nil texts, stray globals and wiring mistakes.
local stub = dofile(ADDON_ROOT .. "/tests/wowstub.lua")

---------------------------------------------------------------------------
-- Widget mock: permissive about unmodelled Set/Get/... methods, strict about
-- SetText(nil) and non-number SetValue.
---------------------------------------------------------------------------
local mock = {}            -- knobs: failSetChecked ("once"), failGenerateMenu
local allWidgets, registered, popupShown, lastMenu, ldbObject
local errors = {}          -- everything the addon reported to the error handler

local PERMISSIVE = { "Set", "Get", "Register", "Clear", "Add", "Lock", "Unlock", "Enable", "Highlight" }

local function newWidget(kind, template)
    local w = { __kind = kind, __template = template, scripts = {}, events = {}, value = 0,
                checked = false, text = "", shown = true, calls = {}, lines = {} }
    allWidgets[#allWidgets + 1] = w
    local specific = {
        RegisterEvent = function(self, e) self.events[e] = true end,
        UnregisterEvent = function(self, e) self.events[e] = nil end,
        SetScript = function(self, n, f) self.scripts[n] = f end,
        GetScript = function(self, n) return self.scripts[n] end,
        IsVisible = function(self) return self.shown end,
        IsShown = function(self) return self.shown end,
        Hide = function(self) self.shown = false end,
        Show = function(self) self.shown = true; if self.scripts.OnShow then self.scripts.OnShow(self) end end,
        SetShown = function(self, s) self.shown = s and true or false end,
        HasFocus = function(self) return self.focus == true end,
        ClearFocus = function(self)
            if self.focus then
                self.focus = false
                if self.scripts.OnEditFocusLost then self.scripts.OnEditFocusLost(self) end
            end
        end,
        SetText = function(self, t) assert(t ~= nil, "SetText(nil)"); self.text = tostring(t) end,
        GetText = function(self) return self.text end,
        SetChecked = function(self, c)
            if mock.failSetChecked then
                mock.failSetChecked = nil
                error("mock SetChecked failure")
            end
            self.checked = c and true or false
        end,
        GetChecked = function(self) return self.checked end,
        SetValue = function(self, v)
            assert(type(v) == "number", "SetValue non-number")
            if v ~= self.value then
                self.value = v
                if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, v, false) end
            end
        end,
        GetValue = function(self) return self.value end,
        SetEnabled = function(self, e) self.enabled = e and true or false end,
        AddLine = function(self, text)
            assert(type(text) == "string", "AddLine text")
            self.lines[#self.lines + 1] = text
        end,
        AddDoubleLine = function(self, left, right)
            assert(type(left) == "string" and type(right) == "string", "AddDoubleLine text")
            self.lines[#self.lines + 1] = left .. " " .. right
        end,
        CreateFontString = function(self, _, _, font) return newWidget("FontString", font) end,
        CreateTexture = function(self) return newWidget("Texture") end,
        SetupMenu = function(self, gen) self.generator = gen; self:GenerateMenu() end,
        GenerateMenu = function(self)
            if mock.failGenerateMenu then error("mock GenerateMenu failure") end
            self.generated = (self.generated or 0) + 1
        end,
        IsMenuOpen = function(self) return self.menuOpen == true end,
        GetID = function() return 42 end,
    }
    return setmetatable(w, { __index = function(t, k)
        if specific[k] then return specific[k] end
        if type(k) == "string" then
            for _, prefix in ipairs(PERMISSIVE) do
                if k:sub(1, #prefix) == prefix then
                    return function() t.calls[#t.calls + 1] = k end
                end
            end
        end
        return nil
    end })
end

local function newRoot()
    local root = { items = {} }
    local function add(item) root.items[#root.items + 1] = item end
    function root:CreateRadio(text, isSel, setSel, data)
        assert(type(text) == "string" and text ~= "", "radio text")
        add({ kind = "radio", text = text, isSel = isSel, setSel = setSel, data = data })
    end
    function root:CreateDivider() add({ kind = "divider" }) end
    function root:CreateTitle(text) assert(type(text) == "string", "title text"); add({ kind = "title", text = text }) end
    function root:CreateButton(text, fn)
        assert(type(text) == "string" and text ~= "", "button text")
        add({ kind = "button", text = text, fn = fn })
    end
    return root
end

local iconButton
local currentLocale = "enUS"

function CreateFrame(kind, _, _, template)
    local w = newWidget(kind, template)
    if template == "OptionsSliderTemplate" then
        w.Low, w.High, w.Text = newWidget("FontString"), newWidget("FontString"), newWidget("FontString")
    end
    stub.frames[#stub.frames + 1] = w
    return w
end

YES, NO = "Yes", "No"
function StaticPopup_Show(name) popupShown = name; return {} end
function GetLocale() return currentLocale end
Settings = {
    RegisterCanvasLayoutCategory = function(panel) registered.panel = panel; return newWidget("Category") end,
    RegisterAddOnCategory = function(cat) registered.category = cat end,
    OpenToCategory = function(id) registered.opened = id end,
}
MenuUtil = { CreateContextMenu = function(owner, gen)
    local root = newRoot(); gen(owner, root); lastMenu = root; return root
end }

local ldb = {}
function ldb:NewDataObject(_, t) ldbObject = t; return t end
local dbicon = { calls = {} }
function dbicon:Register(_, object, db)
    assert(object.icon, "no icon"); assert(type(db) == "table"); self.db = db
end
function dbicon:Show() self.calls[#self.calls + 1] = "Show" end
function dbicon:Hide() self.calls[#self.calls + 1] = "Hide" end
function dbicon:GetMinimapButton() return iconButton end
LibStub = setmetatable({}, { __call = function(_, name)
    if name == "LibDataBroker-1.1" then return ldb end
    return dbicon
end })

---------------------------------------------------------------------------
-- Global-write watcher: only active while addon code runs (see watched()).
---------------------------------------------------------------------------
local ALLOWED = { LighterNightsDB = true, SLASH_LIGHTERNIGHTS1 = true, SLASH_LIGHTERNIGHTS2 = true }
local leaks, watching = {}, false
setmetatable(_G, { __newindex = function(t, k, v)
    if watching and not ALLOWED[k] then leaks[#leaks + 1] = tostring(k) end
    rawset(t, k, v)
end })

local function watched(fn, ...)
    watching = true
    local ok, err = pcall(fn, ...)
    watching = false
    if not ok then error(err, 0) end
end

local function fire(event, ...) watched(stub.fire, event, ...) end

-- Loads the addon in .toc order (skipping Libs) with a fresh mock; fires ADDON_LOADED
-- and, unless opts.enter == false, PLAYER_ENTERING_WORLD.
local function loadAll(opts)
    opts = opts or {}
    stub.reset()
    stub.setTime(opts.hour or 22, opts.minute or 10)
    geterrorhandler = function() return function(message) errors[#errors + 1] = tostring(message) end end
    errors, allWidgets, registered, popupShown, lastMenu, ldbObject = {}, {}, {}, nil, nil, nil
    mock.failSetChecked, mock.failGenerateMenu = nil, nil
    iconButton = newWidget("Button")
    iconButton.icon = newWidget("Texture")
    dbicon.calls = {}
    GameTooltip = newWidget("GameTooltip")
    StaticPopupDialogs = {}
    currentLocale = opts.locale or "enUS"
    if opts.noContrast then stub.cvars.Contrast = nil end
    LighterNightsDB = opts.saved
    local ns = {}
    local files = {}
    for line in io.lines(ADDON_ROOT .. "/LighterNights.toc") do
        line = line:gsub("\r", ""):match("^%s*(.-)%s*$")
        if line ~= "" and line:sub(1, 1) ~= "#" and not line:match("^Libs") then
            files[#files + 1] = (line:gsub("\\", "/"))
        end
    end
    watched(function() for _, f in ipairs(files) do harness.load(f, ns) end end)
    fire("ADDON_LOADED", "LighterNights")
    if opts.enter ~= false then fire("PLAYER_ENTERING_WORLD") end
    return ns
end

local function noErrors()
    assert(#errors == 0, "errors reported to the error handler:\n" .. table.concat(errors, "\n"))
end

local function widgetsOf(template)
    local list = {}
    for _, w in ipairs(allWidgets) do if w.__template == template then list[#list + 1] = w end end
    return list
end

local function openPanel()
    local panel = registered.panel
    panel.shown = true
    panel.scripts.OnShow(panel)
    return panel
end

local function dropdownOf() return widgetsOf("WowStyle1DropdownTemplate")[1] end

-- Sliders are created per box (morning, day, evening, night), three per box.
local function sliderFor(sectionIndex, fieldIndex)
    return widgetsOf("OptionsSliderTemplate")[(sectionIndex - 1) * 3 + fieldIndex]
end

local function countKinds(items)
    local counts = {}
    for _, item in ipairs(items) do counts[item.kind] = (counts[item.kind] or 0) + 1 end
    return counts
end

---------------------------------------------------------------------------
-- Tests
---------------------------------------------------------------------------

test("the settings panel is registered and Core.OpenOptions opens it", function()
    local ns = loadAll()
    assert(registered.panel, "panel registered")
    assert(registered.category, "category registered")
    eq(registered.panel.name, "LighterNights")
    eq(type(ns.Core.OpenOptions), "function")
    ns.Core.OpenOptions()
    eq(registered.opened, 42)
    openPanel()
    registered.panel.scripts.OnUpdate(registered.panel, 1.5)
    noErrors()
end)

test("the dropdown and the minimap menu offer the mode items", function()
    loadAll()
    local root = newRoot()
    dropdownOf().generator(dropdownOf(), root)
    local counts = countKinds(root.items)
    eq(#root.items, 7)
    eq(counts.radio, 6)
    eq(counts.divider, 1)

    ldbObject.OnClick(iconButton, "LeftButton")
    local menu = countKinds(lastMenu.items)
    eq(#lastMenu.items, 10)
    eq(menu.title, 1)
    eq(menu.radio, 6)
    eq(menu.divider, 2)
    eq(menu.button, 1)
    noErrors()
end)

test("picking each radio sets that mode, in both menus", function()
    local ns = loadAll()
    local root = newRoot()
    dropdownOf().generator(dropdownOf(), root)
    ldbObject.OnClick(iconButton, "LeftButton")
    for _, source in ipairs({ root, lastMenu }) do
        for _, item in ipairs(source.items) do
            if item.kind == "radio" then
                item.setSel(item.data)
                eq(ns.Core.GetMode(), item.data)
                eq(item.isSel(item.data), true, "radio reports itself selected")
            end
        end
    end
    -- the minimap menu's settings button opens the window
    for _, item in ipairs(lastMenu.items) do if item.kind == "button" then item.fn() end end
    eq(registered.opened, 42)
    noErrors()
end)

test("the time field accepts 0615, rejects abc, and Escape restores", function()
    local ns = loadAll()
    openPanel()
    local edit = widgetsOf("InputBoxTemplate")[1]
    edit.focus = true; edit.text = "0615"; edit.scripts.OnEnterPressed(edit)
    eq(edit.text, "06:15")
    eq(ns.Core.GetSection("morning").start, 375)
    edit.focus = true; edit.text = "abc"; edit.scripts.OnEnterPressed(edit)
    eq(edit.text, "06:15")
    eq(ns.Core.GetSection("morning").start, 375)
    edit.focus = true; edit.text = "7:00"; edit.scripts.OnEscapePressed(edit)
    eq(edit.text, "06:15")
    eq(ns.Core.GetSection("morning").start, 375)
    noErrors()
end)

test("sliders and checkboxes reach Core", function()
    local ns = loadAll()
    openPanel()
    local gamma, brightness = sliderFor(1, 1), sliderFor(1, 2)
    gamma.scripts.OnValueChanged(gamma, 1.0500000238, true)
    near(ns.Core.GetSection("morning").gamma, 1.05)
    brightness.scripts.OnValueChanged(brightness, 55, true)
    eq(ns.Core.GetSection("morning").brightness, 55)

    local checks = widgetsOf("UICheckButtonTemplate")
    eq(#checks, 5, "four section boxes and the minimap checkbox")
    checks[1].checked = false; checks[1].scripts.OnClick(checks[1])
    eq(ns.Core.GetSection("morning").enabled, false)
    checks[1].checked = true; checks[1].scripts.OnClick(checks[1])
    eq(ns.Core.GetSection("morning").enabled, true)
    checks[5].checked = false; checks[5].scripts.OnClick(checks[5])
    eq(ns.Core.GetDB().minimap.hide, true)
    checks[5].checked = true; checks[5].scripts.OnClick(checks[5])
    eq(ns.Core.GetDB().minimap.hide, false)
    noErrors()
end)

test("both buttons, the reset popup and the tooltip work", function()
    local ns = loadAll()
    openPanel()
    local buttons = widgetsOf("UIPanelButtonTemplate")
    eq(#buttons, 2)
    local remember, reset = buttons[1], buttons[2]
    remember.scripts.OnEnter(remember)
    remember.scripts.OnLeave(remember)
    remember.scripts.OnClick(remember) -- not in disabled mode: nothing happens, no error

    -- remembering the baseline in disabled mode
    ns.Core.SetMode("disabled")
    stub.advance(ns.Display.FADE_SECONDS + 1)
    stub.cvars.Gamma = "1.4"
    remember.scripts.OnClick(remember)
    near(ns.Core.GetBaseline().gamma, 1.4)

    ns.Core.SetMode("auto")
    local gamma = sliderFor(1, 1)
    gamma.scripts.OnValueChanged(gamma, 1.9, true)
    near(ns.Core.GetSection("morning").gamma, 1.9)
    reset.scripts.OnClick(reset)
    eq(popupShown, "LIGHTERNIGHTS_RESET")
    StaticPopupDialogs["LIGHTERNIGHTS_RESET"].OnAccept()
    near(ns.Core.GetSection("morning").gamma, 1.5) -- default: baseline 1.4 + 0.1

    local tooltip = newWidget("GameTooltip")
    ldbObject.OnTooltipShow(tooltip)
    eq(tooltip.lines[1], "LighterNights")
    assert(#tooltip.lines >= 6, "tooltip has its lines")
    noErrors()
end)

test("/ln with no argument, off and a bogus argument", function()
    local ns = loadAll()
    registered.opened = nil
    SlashCmdList["LIGHTERNIGHTS"]("")
    eq(registered.opened, 42)
    SlashCmdList["LIGHTERNIGHTS"]("off")
    eq(ns.Core.GetMode(), "disabled")
    local realPrint, printed = print, {}
    print = function(...) printed[#printed + 1] = table.concat({ ... }, " ") end
    local ok, err = pcall(SlashCmdList["LIGHTERNIGHTS"], "bogus")
    print = realPrint
    assert(ok, err)
    eq(#printed, 1)
    eq(printed[1]:find("/ln", 1, true) ~= nil, true, "usage line")
    eq(ns.Core.GetMode(), "disabled")
    stub.advance(30)
    fire("PLAYER_LOGOUT")
    noErrors()
end)

test("no Contrast CVar, in every locale: the window and tooltip work and Contrast is untouched", function()
    local locales = { "enUS", "deDE", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }
    for _, locale in ipairs(locales) do
        local ns = loadAll({ locale = locale, noContrast = true })
        openPanel()
        registered.panel.scripts.OnUpdate(registered.panel, 1.5)
        local tooltip = newWidget("GameTooltip")
        ldbObject.OnTooltipShow(tooltip)
        eq(tooltip.lines[1], "LighterNights", locale)
        for section = 1, 4 do
            eq(sliderFor(section, 3).shown, false, locale .. " contrast slider hidden")
        end
        ns.Core.SetMode("night")
        stub.advance(30)
        fire("PLAYER_LOGOUT")
        eq(stub.cvars.Contrast, nil, locale)
        for _, write in ipairs(stub.writes) do
            assert(write[1] ~= "Contrast", locale .. ": wrote the Contrast CVar")
        end
        noErrors()
    end
end)

test("F3: the dropdown menu is not regenerated while it is open", function()
    local ns = loadAll({ hour = 12, minute = 0 })
    openPanel()
    local dropdown = dropdownOf()
    dropdown.generated = 0
    dropdown.menuOpen = true
    ns.Core.SetMode("night")
    eq(dropdown.generated, 0, "open menu left alone")
    dropdown.menuOpen = false
    ns.Core.SetMode("auto")
    eq(dropdown.generated, 1, "closed menu refreshed")
    noErrors()
end)

test("F3: an error inside the refresh is reported and sliders keep saving", function()
    local ns = loadAll({ hour = 12, minute = 0 })
    openPanel()
    mock.failSetChecked = true
    ns.Core.SetMode("night")
    eq(#errors, 1, "the failure reached the error handler")
    eq(errors[1]:find("mock SetChecked failure", 1, true) ~= nil, true)
    errors = {}
    local gamma = sliderFor(1, 1)
    gamma.scripts.OnValueChanged(gamma, 1.7, true)
    near(ns.Core.GetSection("morning").gamma, 1.7, "slider still reaches Core")
    noErrors()
end)

test("F1: a failing settings window does not keep the minimap icon from updating", function()
    local ns = loadAll({ hour = 12, minute = 0 })
    openPanel()
    eq(ldbObject.icon, ns.UI.ICONS.day)
    mock.failGenerateMenu = true
    ns.Core.SetMode("night")
    mock.failGenerateMenu = nil
    assert(#errors >= 1, "the window's failure was reported")
    eq(ldbObject.icon, ns.UI.ICONS.night)
end)

test("F7: the minimap button is shown or hidden only when the flag changes", function()
    local ns = loadAll({ hour = 12, minute = 0 })
    openPanel()
    dbicon.calls = {}
    local gamma = sliderFor(1, 1)
    gamma.scripts.OnValueChanged(gamma, 1.6, true)
    ns.Core.SetMode("night")
    ns.Core.SetMode("auto")
    eq(#dbicon.calls, 0, "no Show/Hide for ordinary changes")
    ns.Core.SetMinimapHidden(true)
    eq(table.concat(dbicon.calls, ","), "Hide")
    ns.Core.SetMinimapHidden(true)
    eq(table.concat(dbicon.calls, ","), "Hide", "same flag, no new call")
    ns.Core.SetMinimapHidden(false)
    eq(table.concat(dbicon.calls, ","), "Hide,Show")
    noErrors()
end)

test("no global is written by the addon files except the allowed ones", function()
    -- the watcher itself works
    watched(function() ZZ_PROBE = 1 end)
    eq(leaks[#leaks], "ZZ_PROBE")
    leaks[#leaks] = nil
    rawset(_G, "ZZ_PROBE", nil)
    eq(#leaks, 0, "stray globals: " .. table.concat(leaks, ", "))
end)
