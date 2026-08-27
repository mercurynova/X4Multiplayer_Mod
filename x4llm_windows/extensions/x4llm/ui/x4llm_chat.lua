-- x4llm_chat.lua -- standalone "AI Board Computer" chat terminal.
--
-- A descriptor-style menu (the proven debuglog pattern) with:
--   * a multi-ROW display table (one short line per row) so text clips
--     cleanly instead of a single font-string bleeding onto the input,
--   * a text input at the BOTTOM,
--   * a "Drag" button + onUpdate to make the window moveable.
-- The conversation persists across close/open in module state.
--
-- Loaded AFTER the core x4llm.lua (ui.xml load order), and lazily: the
-- descriptor is built on each open so _G.__X4NATIVE_API is guaranteed to
-- exist by then.

local function log(...)
    print("[x4llm chat] " .. table.concat({ ... }, " "))
end

------------------------------------------------------------
-- Conversation buffer (persists while the game runs)
------------------------------------------------------------
local chat_history = ""
local function conv_text() return chat_history end

------------------------------------------------------------
-- Display geometry
------------------------------------------------------------
local CHAT_LINE_W = 38          -- characters per wrapped line
local CHAT_LINES  = 12          -- how many lines the display shows
local ROW_H       = 15          -- approx px per table row
local TITLE_H     = 20
local INPUT_H     = 25
local DISPLAY_H   = 195         -- >= CHAT_LINES * ROW_H so nothing clips
local FRAME_W     = 380
local FRAME_H     = TITLE_H + DISPLAY_H + INPUT_H

local menu -- forward declaration (used by display_lines below)

local function wrap(text, width)
    local lines, cur = {}, ""
    for word in text:gmatch("%S+") do
        if cur == "" then
            cur = word
        elseif #cur + 1 + #word <= width then
            cur = cur .. " " .. word
        else
            lines[#lines + 1] = cur
            cur = word
        end
    end
    if cur ~= "" then lines[#lines + 1] = cur end
    return lines
end

-- Every conversation line, word-wrapped to CHAT_LINE_W.
local function all_wrapped_lines()
    local all = {}
    for msg in conv_text():gmatch("[^\r\n]+") do
        for _, l in ipairs(wrap(msg, CHAT_LINE_W)) do
            all[#all + 1] = l
        end
    end
    return all
end

local function num_pages()
    return math.max(1, math.ceil(#all_wrapped_lines() / CHAT_LINES))
end

-- Each line is short (<= CHAT_LINE_W) so a single table row can never
-- overflow its height -- that keeps text from bleeding onto the input.
-- Return (tail, page, npages): the CHAT_LINES lines of the requested page,
-- the current page number, and the total pages (>= 1). menu.page == nil means
-- "newest" (last page).
local function display_lines()
    local all = all_wrapped_lines()
    local npages = math.max(1, math.ceil(#all / CHAT_LINES))
    local page = menu.page
    if type(page) ~= "number" or page < 1 then page = npages end
    if page > npages then page = npages end
    menu.page = page
    local tail = {}
    for i = (page - 1) * CHAT_LINES + 1, #all do
        tail[#tail + 1] = all[i]
    end
    return tail, page, npages
end

------------------------------------------------------------
-- Menu state
------------------------------------------------------------
menu = {
    texts = {
        title  = "AI Board Computer",
        prompt = "Type a message, press Enter:",
    },
    x = 500, y = 500,          -- current window position
    dragging = false,
    drag_start = nil,          -- mouse pos where the drag began
    drag_from  = nil,          -- frame pos where the drag began
    page       = nil,          -- display page (nil = newest)
}

local function get_api()
    return _G.__X4NATIVE_API
end

-- Forward declarations (used before their definitions below).
local onShowMenu
local buildDescriptors

------------------------------------------------------------
-- LLM round-trip
------------------------------------------------------------
local function onAskReply(reply)
    chat_history = chat_history .. reply .. "\n"
    menu.page = nil -- jump to newest (last page) on rebuild
    log("LLM reply received, chars=" .. #reply)
    -- Rebuild the descriptors so the new reply shows up.
    if menu.view and menu.view.onShowMenu then
        menu.view.onShowMenu(menu, menu.frame, menu.content)
    end
end

local function ask(prompt)
    local api = get_api()
    chat_history = chat_history .. "You: " .. prompt .. "\n"
    if not api then
        chat_history = chat_history .. "AI: [error] native API not ready\n"
        return
    end
    -- The reply arrives later via x4llm.lua's on_response, which calls
    -- append_reply. The conversation is rendered in the MapMenu Info panel.
    api.raise_event("x4llm_ask", prompt)
    -- Show the user's message in the body right away (and clear the input)
    -- instead of waiting for the LLM reply or a menu change.
    if _G.x4llm_chat_refresh then _G.x4llm_chat_refresh() end
end

-- Record an incoming LLM reply into the conversation (called by x4llm.lua).
local function append_reply(text)
    chat_history = chat_history .. "AI: " .. text .. "\n"
end

------------------------------------------------------------
-- Dragging
------------------------------------------------------------
local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function start_drag()
    local mpos = GetLocalMousePosition and GetLocalMousePosition() or nil
    if not mpos then return end
    menu.dragging = true
    menu.drag_start = { x = mpos.x, y = mpos.y }
    menu.drag_from  = { x = menu.x,  y = menu.y }
    log("drag started at", mpos.x, mpos.y)
end

local function stop_drag()
    menu.dragging = false
    menu.drag_start = nil
    menu.drag_from  = nil
end

local function onUpdate()
    if not menu.dragging then return end
    local mpos = GetLocalMousePosition and GetLocalMousePosition() or nil
    if not mpos or not menu.drag_start then return end
    local nx = clamp(menu.drag_from.x + (mpos.x - menu.drag_start.x), 0, 1600 - FRAME_W)
    local ny = clamp(menu.drag_from.y + (mpos.y - menu.drag_start.y), 0,  900 - FRAME_H)
    if nx ~= menu.x or ny ~= menu.y then
        menu.x, menu.y = nx, ny
        if menu.view and menu.view.onShowMenu then
            menu.view.onShowMenu(menu, menu.frame, menu.content)
        end
    end
end

------------------------------------------------------------
-- Build the UI
------------------------------------------------------------
buildDescriptors = function()
    local lines, page, npages = display_lines()
    local rows = {}
    for _, l in ipairs(lines) do
        rows[#rows + 1] = { l }
    end
    -- Guarantee at least one row so the table always renders.
    if #rows == 0 then rows[1] = { menu.texts.prompt } end

    -- Title row: text in col0, then Drag / Prev / Next / Logbook buttons.
    local title = {
        type = "table", id = "title",
        descriptor = {
            "", {{ menu.texts.title .. " " .. page .. "/" .. npages,
                  { "Drag", "dragbtn" }, { "<", "prevbtn" }, { ">", "nextbtn" },
                  { "Log", "logbtn" } }},
            5, true, 1, false, false, 1, 0, 0, TITLE_H,
        },
    }
    -- Display: one short line per row; clips to DISPLAY_H.
    local display = {
        type = "table", id = "chatdisplay",
        descriptor = {
            "chat_display", rows, 1, true, 1, false, false, 1, 0, 0, DISPLAY_H,
        },
    }
    -- Input at the bottom.
    local input = {
        type = "table", id = "chatinput",
        descriptor = {
            "", {{ menu.texts.prompt } },
            1, true, 2, false, false, 1, 0, 0, INPUT_H,
        },
    }

    return {
        title,
        display,
        input,
        {
            type = "frame", id = "frame",
            child = { title, display, input },
            pos = { x = menu.x, y = menu.y },
            size = { w = FRAME_W, h = FRAME_H },
            options = {
                close = true,
                title = menu.texts.title,
                style = "pda_bg",
                closebutton = false,
            },
        },
    }
end

onShowMenu = function()
    local descriptors = buildDescriptors()
    local frame = descriptors[#descriptors]
    local content = {}
    local frames, tables = {}, {}

    for i, d in ipairs(descriptors) do
        if d.type == "frame" then
            frames[i] = CreateFrame(d.child, 0, "pda_bg", d.options, "", nil, d.pos.x, d.pos.y, d.size.w, d.size.h, d.options)
        elseif d.type == "table" then
            tables[i] = CreateTable(d.descriptor[1], d.descriptor[2], d.descriptor[3],
                d.descriptor[4], d.descriptor[5], d.descriptor[6], d.descriptor[7],
                d.descriptor[8], d.descriptor[9], d.descriptor[10], d.descriptor[11])
        end
    end

    content.tables = tables
    content.frames = frames
    menu.frame   = frames[1]
    menu.content = content

    -- Wire the display (no cell actions; read-only).
    local t_title    = tables[1]
    local t_display  = tables[2]
    local t_input    = tables[3]
    local f          = frames[1]

    -- Title-row buttons: col1 Drag, col2 Prev, col3 Next, col4 Logbook.
    SetScript(t_title, "onCellActivated", function(_, row, col)
        if col == 1 then
            if menu.dragging then stop_drag() else start_drag() end
        elseif col == 2 then
            if menu.page and menu.page > 1 then menu.page = menu.page - 1 end
            if menu.view and menu.view.onShowMenu then
                menu.view.onShowMenu(menu, menu.frame, menu.content)
            end
        elseif col == 3 then
            if menu.page and menu.page < num_pages() then menu.page = menu.page + 1 end
            if menu.view and menu.view.onShowMenu then
                menu.view.onShowMenu(menu, menu.frame, menu.content)
            end
        elseif col == 4 then
            local ale = _G.AddLogbookEntry
            if type(ale) == "function" then
                pcall(ale, "tips", "[x4llm chat] " .. conv_text(), nil, nil, nil)
            end
            log("conversation sent to logbook")
        end
    end)

    -- The edit box for input.
    local children = GetChildren(t_input)
    for _, c in ipairs(children) do
        if c and c.type == "editbox" then
            SetScript(c, "onEditBoxDeactivated", function(_, text, _, confirmed)
                if confirmed and text and text ~= "" then
                    ask(text)
                end
            end)
            break
        end
    end

    -- Per-frame update for dragging.
    if SetScript and f then
        SetScript(f, "onUpdate", onUpdate)
    end
end

------------------------------------------------------------
-- View + registration
------------------------------------------------------------
local view = {
    onShowMenu = onShowMenu,
    onViewCreated = function(m, frame, content)
        m.view = view
        local tables = content.tables or {}
        local frames = content.frames or {}
        log("view created (display=" .. tostring(tables[2] ~= nil) ..
            " editbox=" .. tostring((function()
                for _, c in ipairs(GetChildren(tables[3])) do
                    if c and c.type == "editbox" then return true end
                end
                return false
            end)()) ..
            " frame=" .. tostring(frames[1] ~= nil) .. ")")
    end,
}

local x4llm_chat_show -- forward declaration (defined below)

local function x4llm_chat_toggle()
    -- Open (or close) directly. NOTE: an earlier version raised the
    -- "x4llm.chat.show" Lua event but nothing registered a handler for it,
    -- so the window never opened.
    x4llm_chat_show()
    log("toggle: requesting show")
end

x4llm_chat_show = function()
    -- The chat renders inside the game's Information panel (MapMenu) -- the
    -- only proven scrollable surface. RegisterView (used by an earlier draft)
    -- does not exist in the game. Select any ship/station and open its
    -- Information panel to see the AI section.
    log("AI chat lives in the Information panel -- select a ship/station")
end

_G.x4llm_chat_toggle  = x4llm_chat_toggle
_G.x4llm_chat_show    = x4llm_chat_show
_G.x4llm_chat_history = conv_text      -- full conversation string
_G.x4llm_chat_ask     = ask            -- send a prompt (async; updates history)
_G.x4llm_chat_append  = append_reply   -- record an incoming reply

log("initialized")
