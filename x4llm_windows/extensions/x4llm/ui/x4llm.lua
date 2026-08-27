-- x4llm — in-game LLM assistant (board computer), Phase 0
--
-- Adds two rows to the main menu (OptionsMenu):
--   * "AI — Test"      : sends a hardcoded prompt to the LLM extension and shows
--                        the response (logged + best-effort on-screen).
--   * "AI — Probe UI"  : dumps the game's UI-related Lua globals to the log so
--                        we can discover the right primitive for a real panel.
--
-- The response arrives back on the UI thread via raise_lua_event("x4llm.response")
-- (the C++ worker thread never touches the UI directly).
--
-- This file may run before x4native.lua sets _G.__X4NATIVE_API, so installation
-- retries on UI-init events until the API appears (same as x4mp_menu.lua).

local api = _G.__X4NATIVE_API

local ROW_TEST  = "x4llm_test"
local ROW_PROBE = "x4llm_probe"
local TEXT_TEST  = "AI - Test (ask)"
local TEXT_PROBE = "AI - Probe UI"

local TEST_PROMPT = "Introduce yourself in two short sentences as this ship's board computer."

-- ---------------------------------------------------------------------------
-- Board computer: a custom menu shown via OpenMenu. Frame + text widgets are
-- built inside the menu's lifecycle hooks. Every hook logs so the FIRST open
-- reveals which hooks the framework invokes (the render contract).
-- ---------------------------------------------------------------------------
local ROW_BC = "x4llm_bc"
local TEXT_BC = "AI - Board Computer"

local g_bc = { response = "(no response yet)", busy = false }
local bc_registered = false

local function build_bc_menu()
    local H = _G.Helper
    local menu = {}
    menu.name = ROW_BC

    -- Instrument every lifecycle hook (log-only) so we see exactly which ones
    -- the framework invokes for our menu.
    local function loghook(name)
        return function(...)
            api.log(1, "BC HOOK " .. name .. " (args=" .. select('#', ...) .. ")")
        end
    end

    -- onShowMenu is the confirmed-called entry point. The framework never called
    -- createTopLevel/viewCreated, so my menu has no render surface. Hypothesis:
    -- Helper.createTopLevelConfig sets up the top-level view; probe its shape and
    -- use the first success, then build widgets (which should attach to the view).
    menu.onShowMenu = function(...)
        api.log(1, "BC HOOK onShowMenu (args=" .. select('#', ...) .. ")")
        local function dump(name, tbl)
            if type(tbl) ~= "table" then
                api.log(1, "BC " .. name .. " = " .. tostring(tbl))
                return
            end
            local parts = {}
            for k, v in pairs(tbl) do
                parts[#parts + 1] = tostring(k) .. "=" .. (type(v) == "table" and "<table>" or tostring(v))
            end
            table.sort(parts)
            api.log(1, "BC " .. name .. " (" .. #parts .. "): " .. table.concat(parts, ", "))
        end
        local function methodsOf(obj, label)
            local m = (getmetatable ~= nil) and getmetatable(obj)
            local idx = m and m.__index
            if type(idx) == "table" then
                local ms = {}
                for k, v in pairs(idx) do if type(v) == "function" then ms[#ms + 1] = k end end
                table.sort(ms)
                api.log(1, "BC " .. label .. " methods (" .. #ms .. "): " .. table.concat(ms, ", "))
            else
                api.log(1, "BC " .. label .. " metatable.__index is " .. type(idx))
            end
        end
        local ok, err = pcall(function()
            local f = H.createFrameHandle({ name = "x4llm_bc" })
            api.log(1, "BC frame -> " .. tostring(f))
            -- create a render target inside the frame (the drawable surface)
            local ok1, rt = pcall(f.addRenderTarget, f, { x = 20, y = 40, width = 540, height = 340 })
            api.log(1, "BC addRenderTarget -> " .. (ok1 and tostring(rt) or tostring(rt):gsub("%.lua:%d+: ", ""):sub(1, 120)))
            if type(rt) == "table" then
                dump("renderTarget", rt)
                methodsOf(rt, "renderTarget")
                -- try adding a text widget (method name guessed from the frame's add* pattern)
                for _, meth in ipairs({ "addTextInfo", "addText", "setText", "addLabel", "addInfo" }) do
                    if type(rt[meth]) == "function" then
                        local ok3, e3 = pcall(rt[meth], rt, { text = "BOARD COMPUTER", x = 10, y = 10, width = 500, height = 30 })
                        api.log(1, "BC rt." .. meth .. " -> " .. (ok3 and "OK" or tostring(e3):gsub("%.lua:%d+: ", ""):sub(1, 110)))
                    end
                end
            end
            -- display the frame
            local ok2, e2 = pcall(f.display, f)
            api.log(1, "BC display -> " .. (ok2 and "OK" or tostring(e2):gsub("%.lua:%d+: ", ""):sub(1, 120)))
        end)
        if not ok then api.log(0, "BC onShowMenu ERR: " .. tostring(err):sub(1, 240)) end
    end

    menu.viewCreated       = loghook("viewCreated")
    menu.createTopLevel    = loghook("createTopLevel")
    menu.createMainFrame   = loghook("createMainFrame")
    menu.createLeftBar     = loghook("createLeftBar")
    menu.createSideBar     = loghook("createSideBar")
    menu.createTopLevelTab = loghook("createTopLevelTab")
    menu.display           = loghook("display")
    menu.displayMenu       = loghook("displayMenu")
    menu.cleanup           = loghook("cleanup")
    menu.onCloseElement    = loghook("onCloseElement")
    menu.onSelectElement   = loghook("onSelectElement")
    menu.hotkey            = loghook("hotkey")
    menu.onUpdate          = function() end

    return menu
end

local function ensure_bc_menu()
    if bc_registered then return true end
    local H = _G.Helper
    if not (H and H.registerMenu) then api.log(0, "BC: registerMenu missing"); return false end
    local menu = build_bc_menu()
    local ok, err = pcall(H.registerMenu, menu, ROW_BC)
    if not ok then
        api.log(1, "BC registerMenu(menu,name) failed: " .. tostring(err):sub(1, 110) .. " -> try (name,menu)")
        ok, err = pcall(H.registerMenu, ROW_BC, menu)
    end
    api.log(1, "BC registerMenu -> " .. (ok and "OK" or ("ERR " .. tostring(err):sub(1, 150))))
    if ok then bc_registered = true end
    return ok
end

local function open_bc_menu()
    if not ensure_bc_menu() then return false end
    local ok = pcall(_G.OpenMenu, ROW_BC, nil, nil)
    api.log(1, "BC OpenMenu -> " .. (ok and "OK" or "ERR"))
    return ok
end

-- ---------------------------------------------------------------------------
-- Frame-structure capture. A bare frame lacks 'frameData' (which display() needs);
-- the framework sets it up for proper menus. Capture the frame structure of a
-- WORKING menu via Helper.getMenu() so we can replicate it for the board computer.
-- ---------------------------------------------------------------------------
local frame_capture_seen = {}
local table_capture_seen = {}
local CAPTURE_LIMIT = 8
local TABLE_LIMIT = 3

local function kv(tbl, limit)
    local parts, n = {}, 0
    for k, v in pairs(tbl) do
        parts[#parts + 1] = tostring(k) .. "=" .. (type(v) == "table" and "<t>" or tostring(v))
        n = n + 1
        if limit and n >= limit then break end
    end
    table.sort(parts)
    return table.concat(parts, ", ")
end

local function dump_table_structure(name, tbl)
    api.log(1, "TABLE-CAP menu='" .. name .. "'")
    local cd = tbl.columndata
    if type(cd) == "table" then
        api.log(1, "  columndata: " .. kv(cd, 8))
        local i, cdef = next(cd)
        if type(cdef) == "table" then api.log(1, "    col[" .. tostring(i) .. "]: " .. kv(cdef, 30)) end
    end
    local rw = tbl.rows
    if type(rw) == "table" then
        local rwn = 0; for _ in pairs(rw) do rwn = rwn + 1 end
        api.log(1, "  rows: " .. rwn)
        local shown = 0
        for i, row in pairs(rw) do
            if type(row) == "table" then
                api.log(1, "    row[" .. tostring(i) .. "]: " .. kv(row, 40))
                shown = shown + 1
                if shown >= 3 then break end
            end
        end
        -- dump ONE real option row (rowdata=true): the button cell's properties
        -- (text/icon) and handlers (click callback) — what we replicate for an AI row.
        for i, row in pairs(rw) do
            if type(row) == "table" and row.rowdata == true then
                api.log(1, "    REALROW[" .. tostring(i) .. "] btn:")
                local btn = row[1]
                if type(btn) == "table" then
                    api.log(1, "      btn: " .. kv(btn, 20))
                    local p = btn.properties
                    if type(p) == "table" then
                        api.log(1, "      btn.properties: " .. kv(p, 60))
                        for _, fld in ipairs({ "text", "icon", "hotkey", "mouseOverText" }) do
                            local v = p[fld]
                            if type(v) == "table" then
                                api.log(1, "      btn.properties." .. fld .. ": " .. kv(v, 20))
                            elseif v ~= nil then
                                api.log(1, "      btn.properties." .. fld .. " = " .. tostring(v))
                            end
                        end
                    end
                    if type(btn.handlers) == "table" then
                        local hk = {}
                        for k, v in pairs(btn.handlers) do hk[#hk + 1] = tostring(k) .. "=" .. type(v) end
                        table.sort(hk)
                        api.log(1, "      btn.handlers: " .. table.concat(hk, ", "))
                    end
                end
                break
            end
        end
    end
    local rg = tbl.rowgroups
    if type(rg) == "table" then
        local rgn = 0; for _ in pairs(rg) do rgn = rgn + 1 end
        api.log(1, "  rowgroups: " .. rgn)
    end
end

local function capture_current_frame(label)
    local M = _G.Menus
    if not (M and type(M) == "table") then
        if label then api.log(1, "CAP: Menus missing") end
        return
    end
    local frame_count = 0; for _ in pairs(frame_capture_seen) do frame_count = frame_count + 1 end
    local table_count = 0; for _ in pairs(table_capture_seen) do table_count = table_count + 1 end

    for _, m in ipairs(M) do
        if type(m) == "table" and m.name then
            local name = tostring(m.name)
            for k, v in pairs(m) do
                if type(v) == "table" and v.type == "frame" then
                    if not frame_capture_seen[name] and frame_count < CAPTURE_LIMIT then
                        frame_capture_seen[name] = true
                        frame_count = frame_count + 1
                        api.log(1, "FRAME-CAP menu='" .. name .. "' frame='" .. k .. "'")
                        api.log(1, "  frame: " .. kv(v, 20))
                    end
                    if type(v.content) == "table" then
                        for _, entry in pairs(v.content) do
                            if type(entry) == "table" and entry.type == "table" then
                                local rwn = 0
                                if type(entry.rows) == "table" then for _ in pairs(entry.rows) do rwn = rwn + 1 end end
                                if rwn > 0 and not table_capture_seen[name] and table_count < TABLE_LIMIT then
                                    table_capture_seen[name] = true
                                    table_count = table_count + 1
                                    dump_table_structure(name, entry)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    if label then
        -- dump the InteractMenu's menu-table fields (methods) to find the injection point
        for _, m in ipairs(M) do
            if type(m) == "table" and m.name == "InteractMenu" then
                local mf = {}
                for k, v in pairs(m) do mf[#mf + 1] = tostring(k) .. "=" .. type(v) end
                table.sort(mf)
                api.log(1, "INTERACT-MENU fields:")
                local chunk = {}
                for _, s in ipairs(mf) do
                    chunk[#chunk + 1] = s
                    if #chunk >= 10 then
                        api.log(1, "  " .. table.concat(chunk, ", "))
                        chunk = {}
                    end
                end
                if #chunk > 0 then api.log(1, "  " .. table.concat(chunk, ", ")) end
                break
            end
        end
        api.log(1, "CAP: frames=" .. frame_count .. " tables=" .. table_count)
    end
end

-- Probe which createFrameHandle descriptor fields allocate the native
-- 'descriptor' (userdata) + 'id' that a rendering frame needs.
local function probe_frame_creation()
    local H = _G.Helper
    if not (H and H.createFrameHandle) then return end
    local descriptors = {
        { "name",           { name = "x4llm_bc" } },
        { "id+name",        { id = 1, name = "x4llm_bc" } },
        { "id+name+w+h",    { id = 1, name = "x4llm_bc", width = 400, height = 300 } },
        { "name+w+h+x+y",   { name = "x4llm_bc", width = 400, height = 300, x = 0, y = 0 } },
        { "name+viewW+viewH", { name = "x4llm_bc", viewWidth = 400, viewHeight = 300 } },
        { "name+id+w+h+x+y+layer", { name = "x4llm_bc", id = 1, width = 400, height = 300, x = 0, y = 0, layer = 1 } },
    }
    for _, d in ipairs(descriptors) do
        local ok, f = pcall(H.createFrameHandle, d[2])
        if ok and type(f) == "table" then
            api.log(1, string.format("CFH(%s) -> descriptor=%s id=%s",
                d[1], type(f.descriptor), tostring(f.id)))
        else
            api.log(1, string.format("CFH(%s) -> ERR %s", d[1], tostring(f):gsub("%.lua:%d+: ", ""):sub(1, 100)))
        end
    end
end

-- ---------------------------------------------------------------------------
-- Response display (best-effort; the reliable sink is the log)
-- ---------------------------------------------------------------------------
local responded_once = false

-- Try a handful of plausible in-game text primitives; log whichever exists.
local function try_display(text)
    local tried = {}
    local candidates = { "ShowMessage", "ShowText", "ShowMessageBox",
                         "ShowPopup", "ShowNotification", "AddMessage",
                         "ShowSubtitle", "ShowChatMessage" }
    for _, name in ipairs(candidates) do
        local fn = _G[name]
        if type(fn) == "function" then
            table.insert(tried, name)
            pcall(fn, text)
        end
    end
    -- Helper table functions.
    if type(Helper) == "table" then
        for _, name in ipairs({ "ShowMessage", "showMessage", "ShowText", "showText" }) do
            if type(Helper[name]) == "function" then
                table.insert(tried, "Helper." .. name)
                pcall(Helper[name], text)
            end
        end
    end
    if #tried > 0 and api and api.log then
        api.log(1, "x4llm: displayed response via " .. table.concat(tried, ", "))
    end
end

local AI_CAT = "x4llm_ai"
local mapmenu_ref

-- Rebuild the AI tab if it is the currently active info mode. Used both when
-- a reply arrives and immediately after the user sends a prompt (so their
-- message shows in the body without waiting for the LLM).
local function refresh_ai_tab()
    if mapmenu_ref and mapmenu_ref.infoMode
        and (mapmenu_ref.infoMode.right == AI_CAT or mapmenu_ref.infoMode.left == AI_CAT)
        and type(mapmenu_ref.refreshInfoFrame) == "function" then
        pcall(mapmenu_ref.refreshInfoFrame, mapmenu_ref)
    end
end
_G.x4llm_chat_refresh = refresh_ai_tab

local function on_response(_, text)
    api = _G.__X4NATIVE_API
    text = text or "(empty response)"
    if api and api.log then api.log(1, "x4llm RESPONSE: " .. text) end
    g_bc.response = text
    g_bc.busy = false
    -- Record the reply in the chat conversation (rendered in the Info panel).
    if _G.x4llm_chat_append then _G.x4llm_chat_append(text) end
    -- Live-refresh the AI tab if it is the active info mode.
    refresh_ai_tab()
    -- Reliable in-game display: add the answer to the player's Logbook (News).
    -- 'tips' is the only category confirmed valid (the game's own call uses it);
    -- invalid categories print a native banner that pcall cannot catch.
    -- If the chat terminal is open it shows the reply inline, so skip the
    -- logbook to avoid posting the same answer twice.
    if not _G.__X4LLM_CHAT_OPEN then
        local ale = _G.AddLogbookEntry
        if type(ale) == "function" then
            local ok = pcall(ale, "tips", text, nil, nil, nil)
            api.log(1, "x4llm: AddLogbookEntry('tips') pcall=" .. tostring(ok))
        else
            api.log(0, "x4llm: AddLogbookEntry not available")
        end
    else
        api.log(1, "x4llm: response routed to chat (logbook skipped)")
    end
    try_display(text)
end

-- Invoked when the injected "AI Board Computer" row is clicked in the
-- Ship Interactions menu. Fires the async LLM query; the answer arrives via
-- the x4llm.response handler (on_response) and is posted to the logbook.
local function on_ai_clicked(menu)
    api = _G.__X4NATIVE_API
    if not api then
        print("x4llm: API not ready for AI click")
        return
    end
    local texts = (menu and type(menu.texts) == "table") and menu.texts or {}
    local data  = (menu and type(menu.data)  == "table") and menu.data  or {}
    -- DIAGNOSTIC: reveal what context the game already knows about the target,
    -- so we can enrich the prompt (name, faction, type, cargo, ...).
    local tk = {}
    for k, v in pairs(texts) do
        if type(v) == "string" and v ~= "" then tk[#tk + 1] = k .. '="' .. v .. '"' end
    end
    table.sort(tk)
    api.log(1, "x4llm: menu.texts: " .. table.concat(tk, ", "))
    local dk = {}
    for k, v in pairs(data) do dk[#dk + 1] = k .. "=" .. type(v) end
    table.sort(dk)
    api.log(1, "x4llm: menu.data keys: " .. table.concat(dk, ", "))

    local target = texts.targetShortName or texts.targetBaseName or "the selected vessel"
    api.log(1, "x4llm: AI invoked for '" .. tostring(target) .. "'")
    local prompt = "You are the onboard AI board computer of a spaceship in the X4: Foundations universe. " ..
        "The pilot is interacting with a target named: " .. tostring(target) .. ". " ..
        "Give a brief, helpful, in-character response about this vessel (2-5 sentences)."
    api.raise_event("x4llm_ask", prompt)
end

-- ---------------------------------------------------------------------------
-- UI probe: dump the game's UI-related globals so we can find a display
-- primitive for a real chat panel (Phase 1).
-- ---------------------------------------------------------------------------
function probe_ui()
    if not api or not api.log then return end

    -- 1) Helper: dump EVERY string-named function (it is the main util table).
    local function dump_helper()
        local t = _G.Helper
        if type(t) ~= "table" then return end
        local fns = {}
        for k, v in pairs(t) do
            if type(k) == "string" and type(v) == "function" then table.insert(fns, k) end
        end
        table.sort(fns)
        api.log(1, string.format("x4llm PROBE Helper: %d functions", #fns))
        -- Emit in chunks so a single log line isn't truncated.
        for i = 1, #fns, 40 do
            local chunk = {}
            for j = i, math.min(i + 39, #fns) do chunk[#chunk + 1] = fns[j] end
            api.log(1, "  " .. table.concat(chunk, ", "))
        end
    end
    dump_helper()

    -- 2) Any other global table holding functions: report the UI-ish ones.
    local ui_pat = "Show|Text|Message|Popup|Notify|Toast|Subtitle|Chat|Panel|Box|Label|Overlay|Dialog|Input|Edit|Display|Info|Window|View|Screen|Element|Tooltip|Banner"
    for name, t in pairs(_G) do
        if type(name) == "string" and type(t) == "table" and name ~= "Helper" then
            local ui, total = {}, 0
            for k, v in pairs(t) do
                if type(k) == "string" and type(v) == "function" then
                    total = total + 1
                    if k:find(ui_pat) then ui[#ui + 1] = k end
                end
            end
            if #ui > 0 then
                table.sort(ui)
                api.log(1, string.format("x4llm PROBE table '%s' (%d fns): UI-ish -> %s",
                    name, total, table.concat(ui, ", ")))
            end
        end
    end

    -- 3) Widget-signature introspection. The game's UI widget API is
    --    undocumented (lua is packed), so we probe with guarded calls: the
    --    LuaJIT error text reveals the expected parameter types.
    -- NOTE: X4 nils the `debug` global; recover it via require("debug").
    local dbg
    do local ok, lib = pcall(require, "debug"); dbg = (ok and lib) or nil end
    local unpack_ = (table and table.unpack) or unpack
    local function try_call(name, args)
        local fn = Helper[name]
        if type(fn) ~= "function" then return end
        local ok, ret = pcall(fn, unpack_(args))
        if ok then
            api.log(1, string.format("x4llm WIDGET %s(%s) -> OK ret=%s",
                name, table.concat(args, ","), tostring(ret)))
        else
            api.log(1, string.format("x4llm WIDGET %s(%s) -> ERR %s",
                name, table.concat(args, ","), tostring(ret)))
        end
    end
    -- source chunk for each widget fn (may reveal the packed module name)
    if dbg and dbg.getinfo then
        for _, n in ipairs({ "createTextInfo", "createEditBox", "drawRectangle",
                             "createButton", "createFrameHandle", "registerMenu",
                             "setKeyBinding", "createTopLevelConfig" }) do
            local fn = Helper[n]
            if type(fn) == "function" then
                local ok, info = pcall(dbg.getinfo, fn, "S")
                if ok and info then
                    api.log(1, string.format("x4llm WIDGET %s src='%s' lines=%s-%s",
                        n, tostring(info.source), tostring(info.linedefined), tostring(info.lastlinedefined)))
                end
            end
        end
    else
        api.log(1, "x4llm WIDGET: require('debug') unavailable")
    end
    try_call("drawRectangle", { 0, 0, 50, 50 })
    try_call("drawRectangle", { 0, 0, 50, 50, 1 })
    try_call("createTextInfo", {})
    try_call("createTextInfo", { "hello" })
    try_call("createTextInfo", { 0, 0, 100, 100, "hello" })
    try_call("createTextInfo", { 10, 10, 200, 50, "hello" })
    try_call("createEditBox", { "type here" })
    try_call("createEditBox", { 0, 0, 200, 30, "type here" })
    try_call("createButton", { "btn" })
    try_call("createButton", { 0, 0, 100, 30, "btn" })

    -- 4) The game keeps its globals behind _G's metatable __index, so pairs(_G)
    --    sees nothing. Enumerate the metatable table to list every global.
    local unpack_ = (table and table.unpack) or unpack
    local mt = (getmetatable ~= nil) and getmetatable(_G) or nil
    local idx = (mt and type(mt.__index) == "table") and mt.__index or nil
    if idx then
        local all, uifn = {}, {}
        for name, v in pairs(idx) do
            if type(name) == "string" then
                all[#all + 1] = name
                if type(v) == "function" then
                    local ln = name:lower()
                    if ln:find("menu") or ln:find("show") or ln:find("chat") or ln:find("message")
                       or ln:find("notify") or ln:find("notification") or ln:find("dialog")
                       or ln:find("text") or ln:find("open") or ln:find("info") or ln:find("display")
                       or ln:find("panel") or ln:find("hud") or ln:find("screen") or ln:find("window")
                       or ln:find("popup") or ln:find("toast") or ln:find("banner") or ln:find("subtitle")
                       or ln:find("caption") or ln:find("print") or ln:find("log") or ln:find("sound") then
                        uifn[#uifn + 1] = name
                    end
                end
            end
        end
        table.sort(all)
        table.sort(uifn)
        api.log(1, string.format("x4llm PROBE metatable globals: total=%d ui-ish=%d", #all, #uifn))
        for i = 1, #uifn, 40 do
            local chunk = {}
            for j = i, math.min(i + 39, #uifn) do chunk[#chunk + 1] = uifn[j] end
            api.log(1, "  " .. table.concat(chunk, ", "))
        end
    else
        api.log(1, "x4llm PROBE: _G metatable.__index is not a table (" .. type(idx) .. ")")
    end

    -- 5) Directly test a comprehensive list of candidate display/menu globals by
    --    name (resolves through the metatable even if enumeration missed it).
    local candidates = {
        "openMenu", "OpenMenu", "showMenu", "ShowMenu", "closeMenu", "CloseMenu",
        "showMessage", "ShowMessage", "addMessage", "AddMessage", "printMessage",
        "sendChatMessage", "showChatMessage", "addChatMessage", "postChatMessage",
        "notify", "Notify", "showNotification", "addNotification",
        "showText", "ShowText", "printToScreen", "showOnScreen", "addText",
        "showSubtitle", "addSubtitle", "showInfo", "ShowInfo", "messageBox",
        "showDialog", "openDialog", "toggleChatWindow", "openChatWindow",
        "showChatWindow", "addLogbookEntry", "AddLogbookEntry",
        "showPopup", "addPopup", "showToast", "addToast"
    }
    local found = {}
    for _, c in ipairs(candidates) do
        if type(_G[c]) == "function" then found[#found + 1] = c end
    end
    table.sort(found)
    api.log(1, "x4llm GOTCHA candidate globals: " .. (#found > 0 and table.concat(found, ", ") or "none"))

    -- 6) createFrameHandle signature discovery (the frame is the container that
    --    makes widgets render). Try positional and descriptor-table forms; the
    --    LuaJIT error text names the expected parameter types.
    local cfh = Helper.createFrameHandle
    if type(cfh) == "function" then
        local function cfh_try(args, label)
            local ok, ret = pcall(cfh, unpack_(args))
            api.log(1, string.format("CFH [%s] -> %s", label,
                ok and ("OK ret=" .. tostring(ret)) or
                      tostring(ret):gsub("%.lua:%d+: ", ""):sub(1, 130)))
        end
        cfh_try({ 10, 10, 400, 300 }, "x,y,w,h")
        cfh_try({ 10, 10, 400, 300, "x4llm_frame" }, "x,y,w,h,name")
        cfh_try({ 10, 10, 400, 300, 1 }, "x,y,w,h,int")
        cfh_try({ 400, 300, 10, 10, "x4llm_frame" }, "w,h,x,y,name")
        cfh_try({ { x = 10, y = 10, width = 400, height = 300, name = "x4llm_frame" } }, "descriptor")
    else
        api.log(1, "CFH: createFrameHandle is " .. type(cfh))
    end

    -- 7) AddLogbookEntry: confirm the reliable in-game text sink. Try a couple of
    --    signatures; whichever works adds a visible entry to the player's logbook.
    local ale = _G.AddLogbookEntry
    api.log(1, "AddLogbookEntry type = " .. type(ale))
    if type(ale) == "function" then
        api.log(1, "ALE-1 (category, text)")
        pcall(ale, "Misc", "x4llm: AddLogbookEntry works (category, text)")
        api.log(1, "ALE-2 (text)")
        pcall(ale, "x4llm: AddLogbookEntry works (text)")
        api.log(1, "ALE-3 (int, text)")
        pcall(ale, 0, "x4llm: AddLogbookEntry works (int, text)")
    end

    -- 6) Menus: report how many and each menu's name + its method names.
    if type(Menus) == "table" then
        api.log(1, "x4llm PROBE Menus: " .. tostring(#Menus) .. " entries")
        for _, m in ipairs(Menus) do
            if m and type(m) == "table" then
                local ms = {}
                for k, v in pairs(m) do if type(k) == "string" and type(v) == "function" then ms[#ms + 1] = k end end
                table.sort(ms)
                api.log(1, string.format("  menu '%s': %s", tostring(m.name), table.concat(ms, ", ")))
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Menu injection (OptionsMenu upvalue pattern, mirrors x4mp_menu.lua)
-- ---------------------------------------------------------------------------
local function find_options_menu()
    if type(Menus) ~= "table" then return nil end
    for _, m in ipairs(Menus) do
        if m and m.name == "OptionsMenu" then return m end
    end
    return nil
end

local _debug
local function load_debug()
    if _debug ~= nil then return _debug end
    local ok, lib = pcall(require, "debug")
    _debug = (ok and type(lib) == "table") and lib or false
    return _debug
end

local function get_config_upvalue(fn)
    if type(fn) ~= "function" then return nil end
    local d = load_debug()
    if not d or not d.getupvalue then return nil end
    for i = 1, 100 do
        local name, val = d.getupvalue(fn, i)
        if not name then return nil end
        if name == "config" then return val end
    end
    return nil
end

local installed = false
local interact_menu_installed = false

local function install()
    if installed then return true end
    api = _G.__X4NATIVE_API
    if not api then return false end

    local menu = find_options_menu()
    if not menu then return false end
    local config = get_config_upvalue(menu.displayOptions)
    if not config or type(config) ~= "table" then return false end
    local main_defs = config.optionDefinitions and config.optionDefinitions["main"]
    if type(main_defs) ~= "table" then return false end

    -- Idempotent: remove any prior injected rows.
    for i = #main_defs, 1, -1 do
        local o = main_defs[i]
        if o and (o.id == ROW_TEST or o.id == ROW_PROBE or o.id == ROW_BC) then table.remove(main_defs, i) end
    end
    table.insert(main_defs, { id = ROW_TEST,  name = TEXT_TEST,  submenu = ROW_TEST })
    table.insert(main_defs, { id = ROW_PROBE, name = TEXT_PROBE, submenu = ROW_PROBE })
    table.insert(main_defs, { id = ROW_BC,    name = TEXT_BC,    submenu = ROW_BC })

    local orig_handler = menu.submenuHandler
    if type(orig_handler) == "function" then
        menu.submenuHandler = function(opt)
            if opt == ROW_TEST then
                if type(Helper) == "table" and Helper.addDelayedOneTimeCallbackOnUpdate then
                    Helper.addDelayedOneTimeCallbackOnUpdate(function()
                        api.raise_event("x4llm_ask", TEST_PROMPT)
                    end, true, getElapsedTime() + 0.1)
                else
                    api.raise_event("x4llm_ask", TEST_PROMPT)
                end
                return
            elseif opt == ROW_PROBE then
                probe_ui()
                return
            elseif opt == ROW_BC then
                -- DIAGNOSTIC: probe createFrameHandle descriptors + capture a
                -- working menu's frame structure to replicate the render pipeline.
                probe_frame_creation()
                capture_current_frame("manual")
                return
            end
            return orig_handler(opt)
        end
    end

    installed = true
    api.log(1, "x4llm: main-menu rows installed")
    return true
end

-- Inject an "AI Board Computer" action into the InteractMenu (Ship
-- Interactions). The game's own createContentTable renders every entry in
-- menu.actions[<section>] as a button row (entry.text = label, entry.script =
-- onClick). We hook createContentTable and append our entry to the
-- "interaction" section right before the table is built, so the game renders
-- it with full native fidelity (descriptor, colors, click handling).
local function install_interact_menu()
    if interact_menu_installed then return true end
    api = _G.__X4NATIVE_API
    if not api then return false end
    local M = _G.Menus
    if not (M and type(M) == "table") then return false end
    for _, m in ipairs(M) do
        if type(m) == "table" and m.name == "InteractMenu" then
            local orig = m.createContentTable
            if type(orig) == "function" then
                m.createContentTable = function(frame, position)
                    pcall(function()
                        local sec = m.actions and m.actions["interaction"]
                        if type(sec) == "table" then
                            local function has(t)
                                for _, e in ipairs(sec) do
                                    if type(e) == "table" and e.type == t then return true end
                                end
                                return false
                            end
                            if not has("x4llm_ai") then
                                sec[#sec + 1] = {
                                    type = "x4llm_ai",
                                    text = "AI Board Computer",
                                    script = function() on_ai_clicked(m) end,
                                    active = true,
                                    mouseOverText = "Quick query (answer in the Logbook)",
                                }
                                api.log(1, "x4llm: AI entry injected into InteractMenu 'interaction'")
                            end
                            if not has("x4llm_chat") then
                                sec[#sec + 1] = {
                                    type = "x4llm_chat",
                                    text = "AI Chat",
                                    script = function()
                                        if _G.x4llm_open_ai_chat then
                                            _G.x4llm_open_ai_chat()
                                        else
                                            if api and api.log then api.log(0, "x4llm: _G.x4llm_open_ai_chat NIL (MapMenu not found yet)") end
                                        end
                                    end,
                                    active = true,
                                    mouseOverText = "Open the chat terminal",
                                }
                                api.log(1, "x4llm: AI Chat entry injected into InteractMenu")
                            end
                        end
                    end)
                    return orig(frame, position)
                end
                interact_menu_installed = true
                api.log(1, "x4llm: InteractMenu.createContentTable hooked (AI row ready)")
            end
            break
        end
    end
    return interact_menu_installed
end

-- MapMenu (Information sidebar) integration: append a NATIVE-SCROLLABLE AI
-- section using the game's own widget API (addTable / createText /
-- maxVisibleHeight / setTopRow). We hook createInfoSubmenu and reuse the game's
-- live `inputframe`, so we avoid the ad-hoc createFrameHandle problem entirely.
local mapmenu_chat_installed = false

-- Build the AI info-tab submenu with the SAME structure the game uses for its
-- other tabs (infoborder + content table + createOrdersMenuHeader + nav
-- connections). Omitting the connections is what caused the
-- SetTableNext/PreviousConnectedTable error spam.
local function createAIChatSubmenu(m, inputframe, instance)
    local H = _G.Helper
    if not (H and inputframe and type(inputframe.addTable) == "function") then return end
    local frameheight = inputframe.properties.height
    local fs = H.scaleFont(H.standardFont, H.standardFontSize)
    local rowh = H.scaleY(H.standardTextHeight)

    local infoborder = inputframe:addFrameBorder("ai_chat", {
        offsetBottom = H.standardContainerOffset,
        active = m.panelState[instance .. "menu"],
        color = H.getFrameBorderColor(m, m.panelState[instance .. "menu"], m.panelPins[instance .. "menu"]),
        linewidth = H.getFrameBorderLineWidth(m, m.panelState[instance .. "menu"]),
    })
    H.setFrameBorderIcon(m, infoborder, instance, m.sideBarWidth / 2)

    -- Chat content table (scrollable body + fixed header + fixed input).
    local table_chat = inputframe:addTable(1, {
        tabOrder = 2,
        x = H.standardContainerOffset,
        width = inputframe.properties.width - 2 * H.standardContainerOffset,
        highlightMode = "off",
        backgroundID = "solid",
        backgroundColor = Color["container_subsection_background"],
        backgroundPadding = 0,
        frameborder = infoborder.id,
        reserveScrollBar = true,
    })

    local hrow = table_chat:addRow(false, { fixed = true, bgColor = Color["row_title_background"], borderBelow = false })
    hrow[1]:createText("AI Board Computer", H.headerRowCenteredProperties)

    local hist = _G.x4llm_chat_history and _G.x4llm_chat_history() or ""
    if hist == "" then hist = "Ask the board computer anything." end
    local lines = GetTextLines(hist, H.standardFont, fs, inputframe.properties.width - 6 * H.standardContainerOffset)

    -- Content rows: render EVERY wrapped line (no tail-cap). minRowHeight keeps
    -- row sizing consistent so the scrollbar math is stable (matches the
    -- game's own chatwindow message rows at 08.dat:689690).
    for _, line in ipairs(lines) do
        table_chat:addRow(true, {})[1]:createText(line, {
            scaling = false,
            fontsize = fs,
            minRowHeight = H.scaleY(H.standardTextHeight),
            x = 3 * H.standardContainerOffset,
        })
    end

    -- Input lives in its OWN table, positioned below the scrolling body. A
    -- trailing fixed row inside a scrolling table is not how the game pins
    -- footers; the chatwindow uses a separate table (08.dat:689753).
    local table_input = inputframe:addTable(1, {
        tabOrder = 1,
        x = H.standardContainerOffset,
        width = inputframe.properties.width - 2 * H.standardContainerOffset,
        highlightMode = "off",
        backgroundID = "solid",
        backgroundColor = Color["container_subsection_background"],
        backgroundPadding = 0,
        frameborder = infoborder.id,
    })
    local irow = table_input:addRow(false, { fixed = true })
    -- maxChars lifts the native default 50-char cap (08.dat:820187). The native
    -- editbox is single-line (no multiline/rows param exists), so this is a
    -- tall box holding one long line -- the most the widget system allows.
    -- inputrows controls how tall the field renders; bump it up to taste.
    local inputrows = 2
    local editbox = irow[1]:createEditBox({ height = inputrows * rowh, maxChars = 1000, description = "Ask the AI (Enter to send)" })
    editbox:setText("")
    irow[1].handlers.onEditBoxDeactivated = function(_, text, changed)
        if text and text ~= "" and _G.x4llm_chat_ask then _G.x4llm_chat_ask(text) end
    end

    -- Tab-button header (auto-includes our AI category from config.infoCategories).
    local table_header = m.createOrdersMenuHeader(inputframe, infoborder, instance)

    -- Layout: header on top, scrollable chat in the middle, input pinned at
    -- the bottom. Reserve the input's height so the chat's visible area never
    -- overlaps it.
    table_chat.properties.y = table_header.properties.y + table_header:getFullHeight() + H.borderSize
    local inputheight = table_input:getFullHeight() + H.borderSize
    table_chat.properties.maxVisibleHeight = frameheight - table_chat.properties.y - inputheight
    table_input.properties.y = table_chat.properties.y + table_chat:getVisibleHeight() + H.borderSize

    -- Auto-scroll to the newest lines (content rows start at row index 2).
    local numlines = math.max(1, math.floor(table_chat.properties.maxVisibleHeight / (rowh * 1.5)))
    table_chat:setTopRow(math.max(1, #lines - numlines + 2))

    -- Nav connections -- MUST mirror the game's submenu structure (group 3 right,
    -- group 2 left) or the nav system throws SetTable...ConnectedTable errors.
    local isleft = instance == "left"
    if isleft and m.playerinfotable then m.playerinfotable:addConnection(1, 2, true) end
    table_header:addConnection(isleft and 2 or 1, isleft and 2 or 3, true)
    table_chat:addConnection(isleft and 3 or 2, isleft and 2 or 3)
    table_input:addConnection(isleft and 3 or 2, isleft and 2 or 3)
end

-- Pull the MapMenu's private `config` upvalue. X4 nils the global `debug`, so
-- load it via require (same as the settings menu). Match by CONTENT (a table
-- that has `infoCategories`), not by upvalue name, and try several functions.
local _debug
local function load_debug()
    if _debug ~= nil then return _debug end
    local ok, lib = pcall(require, "debug")
    _debug = (ok and type(lib) == "table") and lib or false
    return _debug
end

local function find_config_in(fn)
    local d = load_debug()
    if not d or not d.getupvalue or type(fn) ~= "function" then return nil end
    for i = 1, 60 do
        local _, val = d.getupvalue(fn, i)
        if type(val) == "table" and type(val.infoCategories) == "table" then return val end
    end
    return nil
end

local function extract_config(m)
    return find_config_in(m.createInfoFrame2)
        or find_config_in(m.createInfoSubmenu)
        or find_config_in(m.isInfoModeValidFor)
end

-- Build the AI-tab info frame ourselves, replicating createInfoFrame / 
-- createInfoFrame2 geometry, then populate it with createAIChatSubmenu.
local function build_ai_frame_own(m, side)
    local H = _G.Helper
    local config = extract_config(m)
    if not (H and config) then return end
    if side == "left" then
        m.refreshed = true
        m.noupdate = false
        if type(H.clearDataForRefresh) == "function" then H.clearDataForRefresh(m, config.infoFrameLayer) end
        m.infoFrame = H.createFrameHandle(m, {
            x = m.infoTableOffsetX, y = m.infoTableOffsetY,
            width = m.infoTableWidth, height = H.viewHeight - m.infoTableOffsetY - m.borderOffset,
            layer = config.infoFrameLayer,
            standardButtons = {}, autoFrameHeight = true,
            helpOverlayID = "map_infoframe",
        })
    else
        if type(H.clearDataForRefresh) == "function" then H.clearDataForRefresh(m, config.infoFrameLayer2) end
        local offsety = m.infoTable2OffsetY - H.standardContainerOffset
        m.infoFrame2 = H.createFrameHandle(m, {
            x = H.viewWidth - m.infoTableOffsetX - m.infoTableWidth, y = offsety,
            width = m.infoTableWidth, height = H.viewHeight - offsety - m.borderOffset,
            layer = config.infoFrameLayer2,
            standardButtons = {}, showBrackets = false, autoFrameHeight = true,
            helpOverlayID = "map_infoframe2",
        })
    end
    local frame = (side == "left" and m.infoFrame) or m.infoFrame2
    if frame then
        frame:setBackground("solid", { color = Color["frame_background_semitransparent"] })
        pcall(createAIChatSubmenu, m, frame, side)
        frame:display()
    end
end

local function install_mapmenu_chat()
    if mapmenu_chat_installed then return true end
    local M = _G.Menus
    if not (M and type(M) == "table") then return false end
    for _, m in ipairs(M) do
        if type(m) == "table" and m.name == "MapMenu" then
            local config = extract_config(m)
            if not (config and type(config.infoCategories) == "table") then break end
            mapmenu_ref = m

            -- 1) Add an "AI" tab to the info category list (idempotent).
            local has = false
            for _, e in ipairs(config.infoCategories) do
                if type(e) == "table" and e.category == AI_CAT then has = true end
            end
            if not has then
                config.infoCategories[#config.infoCategories + 1] = {
                    category = AI_CAT, name = "AI", icon = "pi_message_read_high",
                    helpOverlayID = "x4llm_ai", helpOverlayText = "AI Board Computer",
                }
            end

            -- 2) Allow the AI mode for any selected object.
            if type(m.isInfoModeValidFor) == "function" then
                local orig_valid = m.isInfoModeValidFor
                m.isInfoModeValidFor = function(object, mode)
                    if mode == AI_CAT then return true end
                    return orig_valid(object, mode)
                end
            end

            -- 3) For the AI tab, build the frame ourselves on BOTH sides.
            if type(m.createInfoFrame2) == "function" then
                local orig_frame2 = m.createInfoFrame2
                m.createInfoFrame2 = function(...)
                    if m.infoMode and m.infoMode.right == AI_CAT then
                        pcall(build_ai_frame_own, m, "right")
                        return
                    end
                    return orig_frame2(...)
                end
            end
            if type(m.createInfoFrame) == "function" then
                local orig_frame = m.createInfoFrame
                m.createInfoFrame = function(...)
                    if m.infoMode and m.infoMode.left == AI_CAT then
                        pcall(build_ai_frame_own, m, "left")
                        return
                    end
                    return orig_frame(...)
                end
            end

            -- Expose a way to jump straight to the AI tab from the Interact menu.
            _G.x4llm_open_ai_chat = function()
                if not m.infoMode then m.infoMode = { left = "objectinfo", right = "objectinfo" } end
                if m.searchTableMode ~= "info" then m.searchTableMode = "info" end
                m.infoMode.left = AI_CAT
                m.infoMode.right = AI_CAT
                if type(m.refreshInfoFrame) == "function" then m.refreshInfoFrame() end
            end

            mapmenu_chat_installed = true
            if api and api.log then api.log(1, "x4llm: MapMenu AI tab ready") end
            break
        end
    end
    return mapmenu_chat_installed
end

local function install_all()
    local a = install()
    local b = install_interact_menu()
    local c = install_mapmenu_chat()
    return a and b and c
end

if not install_all() then
    local function retry() install_all() end
    pcall(function()
        RegisterEvent("gfx_ok", retry)
        RegisterEvent("show",   retry)
    end)
end

-- Receive LLM responses pushed from C++ (main/UI thread).
pcall(function()
    RegisterEvent("x4llm.response", on_response)
end)

-- Per-frame poll: auto-capture the frame structure of any working menu we see.
local frame_evt_seen = false
pcall(function()
    RegisterEvent("on_frame_update", function()
        if not frame_evt_seen then
            frame_evt_seen = true
            api.log(1, "x4llm: on_frame_update RECEIVED (first)")
        end
        capture_current_frame(nil)
    end)
end)
