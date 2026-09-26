--[[
QuickUI - Metadata Provider Picker

Flow:
    Find metadata online → search dialog (input + provider buttons)
    → tap a provider:
        * no key needed, or key already set → search now
        * key needed but missing → prompt for it, then search
    → result list → detail preview → Apply

API key management (multi-provider view/edit):
    QuickUI Settings → Metadata Settings → Provider API Keys
    → qm_provider_picker.show_key_settings(editor)
]]

local ButtonDialog = require("ui/widget/buttondialog")
local ButtonTable = require("ui/widget/buttontable")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Notification = require("ui/widget/notification")
local TextViewer = require("ui/widget/textviewer")
local TextBoxWidget = require("ui/widget/textboxwidget")
local Screen = require("device").screen
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local logger = require("logger")

local Utils = require("qui_utils")

local M = {}

local PROVIDERS = {
    {
        id = "douban",
        name = _("Douban"),
        key_config = nil,
        require_key = false,
    },
    {
        id = "google_books",
        name = _("Google Books"),
        key_config = "metadata_google_books_key",
        require_key = true,
    },
    {
        id = "hardcover",
        name = _("Hardcover"),
        key_config = "metadata_hardcover_token",
        require_key = true,
    },
    {
        id = "open_library",
        name = _("Open Library"),
        key_config = nil,
        require_key = false,
    },
}

local function get_config()
    return _G.__QUICKUI_CONFIG or {}
end

local function provider_key(provider)
    if not provider.key_config then return true end
    local key = get_config()[provider.key_config]
    if type(key) ~= "string" or key == "" then return nil end
    return key
end

local function provider_module(provider)
    return require("qui_metadata.qm_" .. provider.id)
end

-- ============================================================
-- Search entry: input + provider buttons, one dialog
-- ============================================================

function M.show(editor)
    -- Initial query: draft title, else ISBN, else filename stem.
    local seed = editor.draft.title
    if not seed or seed == "" then seed = editor.draft.isbn end
    if not seed or seed == "" then
        seed = editor.file:match("([^/]+)%.[^/]+$")
            or editor.file:match("([^/]+)$") or ""
    end

    local dialog
    dialog = InputDialog:new{
        title = _("Search metadata"),
        input = seed,
        input_hint = _("Title or ISBN"),
        buttons = {{
            {
                text = "◂ " .. _("Back"),
                id = "close",
                callback = function()
                    UIManager:close(dialog)
                    UIManager:nextTick(function() editor:show_menu() end)
                end,
            },
        }},
    }

    local provider_buttons = {}
    for _i, p in ipairs(PROVIDERS) do
        local _p = p
        local has_key_field = p.key_config ~= nil
        local has_key = (provider_key(p) ~= nil)
        local missing_key = has_key_field and not has_key

        local display_text
        if missing_key then
            display_text = p.name .. "  (" .. _("API key required") .. ")"
        else
            display_text = p.name
        end

        provider_buttons[#provider_buttons + 1] = {{
            text = display_text,
            callback = function()
                local query = dialog:getInputText()
                if not query or query:gsub("%s+", "") == "" then
                    return
                end
                local stripped = query:gsub("[^%dXx]", "")
                if #stripped >= 10 then
                    editor.draft.isbn = query
                    editor.draft.title = ""
                else
                    editor.draft.title = query
                end

                if missing_key then
                    -- Key required but not set: prompt, then search.
                    UIManager:close(dialog)
                    UIManager:nextTick(function()
                        M.prompt_key_then_search(editor, _p)
                    end)
                else
                    -- Ready to go.
                    UIManager:close(dialog)
                    UIManager:nextTick(function()
                        M.do_search(editor, _p)
                    end)
                end
            end,
        }}
    end

    local width
    if dialog.getAddedWidgetAvailableWidth then
        width = dialog:getAddedWidgetAvailableWidth()
    else
        width = math.floor(Screen:getWidth() * 0.6)
    end

    local provider_table = ButtonTable:new{
        width = width,
        buttons = provider_buttons,
        zero_sep = true,
        show_parent = dialog,
    }

    dialog:addWidget(provider_table)

    editor.dialog = dialog
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

-- ============================================================
-- Key prompt → save → search
-- ============================================================

function M.prompt_key_then_search(editor, provider)
    local config = get_config()
    local current = provider.key_config and config[provider.key_config] or ""
    local dialog
    dialog = InputDialog:new{
        title = provider.name .. " " .. _("API key"),
        input = type(current) == "string" and current or "",
        input_hint = _("Paste the key/token here"),
        buttons = {{
            {
                text = "◂ " .. _("Back"),
                id = "close",
                callback = function()
                    UIManager:close(dialog)
                    UIManager:nextTick(function()
                        -- Return to the search dialog.
                        M.show(editor)
                    end)
                end,
            },
            {
                text = _("Save & Search"),
                is_enter_default = true,
                callback = function()
                    local text = dialog:getInputText() or ""
                    if text == "" then
                        UIManager:show(InfoMessage:new{
                            text = _("Please enter the API key first."),
                            timeout = 2,
                        })
                        return
                    end
                    _G.__QUICKUI_CONFIG[provider.key_config] = text
                    Utils.saveConfig()
                    UIManager:close(dialog)
                    UIManager:nextTick(function()
                        M.do_search(editor, provider)
                    end)
                end,
            },
        }},
    }
    editor.dialog = dialog
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

-- ============================================================
-- Search
-- ============================================================

function M.do_search(editor, provider)
    local key = provider_key(provider)
    if not key then
        UIManager:show(InfoMessage:new{
            text = _("This provider requires an API key."),
            timeout = 3,
        })
        return
    end

    local Mod = provider_module(provider)
    local input = {
        title = editor.draft.title,
        authors = editor.draft.authors,
        author = editor.draft.authors[1],
        isbn = editor.draft.isbn,
        limit = 10,
    }
    if (not input.title or input.title == "")
            and (not input.isbn or input.isbn == "") then
        UIManager:show(InfoMessage:new{
            text = _("Enter a title or ISBN first."),
            timeout = 3,
        })
        return
    end

    UIManager:show(Notification:new{
        text = _("Searching ") .. provider.name .. "...",
        timeout = 1,
    })

    UIManager:scheduleIn(0.1, function()
        local ok, works, err = pcall(Mod.search, key, input)
        if not ok then
            logger.warn("QuickUI metadata search crashed:", works)
            UIManager:show(InfoMessage:new{ text = _("Search failed"), timeout = 3 })
            return
        end
        if not works or #works == 0 then
            local msg = _("No match found")
            if err and err.kind then msg = msg .. " (" .. tostring(err.kind) .. ")" end
            UIManager:show(InfoMessage:new{ text = msg, timeout = 3 })
            return
        end
        M.show_results(editor, provider, works)
    end)
end

-- ============================================================
-- Result list
-- ============================================================

local function result_label(work, edition)
    local title = (edition and edition.title ~= "" and edition.title) or work.title or ""
    local authors = ""
    if type(work.authors) == "table" and #work.authors > 0 then
        authors = table.concat(work.authors, ", ")
    end
    local year = (edition and edition.release_year) or work.release_year
    local parts = {}
    if authors ~= "" then parts[#parts + 1] = authors end
    if year then parts[#parts + 1] = tostring(year) end
    if #parts > 0 then return title .. " — " .. table.concat(parts, " · ") end
    return title
end

local function pick_edition(provider, key, work)
    if type(work.exact_edition) == "table" then return work.exact_edition end
    local Mod = provider_module(provider)
    local ok, editions = pcall(Mod.editions, key, work)
    if ok and type(editions) == "table" and #editions > 0 then
        return editions[1]
    end
    return nil
end

-- session: { editor, provider, works, index, cache }
local function show_result_list(session)
    local editor = session.editor
    local provider = session.provider
    local works = session.works

    local buttons = {}
    table.insert(buttons, {{
        text = "◂ " .. _("Back"),
        callback = function()
            UIManager:close(editor.dialog)
            UIManager:nextTick(function()
                editor._provider_session = nil
                M.show(editor)
            end)
        end,
    }})
    table.insert(buttons, {})

    local key = provider_key(provider)
    local Mod = provider_module(provider)

    for i, work in ipairs(works) do
        local edition
        local ok, editions = pcall(Mod.editions, key, work)
        if ok and type(editions) == "table" and #editions > 0 then
            edition = editions[1]
        end
        local label = result_label(work, edition)
        local _i = i
        table.insert(buttons, {{
            text = label,
            callback = function()
                UIManager:close(editor.dialog)
                session.index = _i
                UIManager:nextTick(function()
                    M.show_detail(session)
                end)
            end,
        }})
    end

    editor.dialog = ButtonDialog:new{
        title = _("Select a match"),
        title_align = "center",
        buttons = buttons,
        width = math.floor(Screen:getWidth() * 0.8),
        max_height = math.floor(Screen:getHeight() * 0.75),
        rows_per_page = 10,
    }
    UIManager:show(editor.dialog)
end

function M.show_results(editor, provider, works)
    local session = {
        editor = editor,
        provider = provider,
        works = works,
        index = 1,
        cache = {},
    }
    editor._provider_session = session
    show_result_list(session)
end

-- ============================================================
-- Detail preview
-- ============================================================

local function value_text(value)
    if type(value) == "table" then
        return table.concat(value, ", ")
    end
    return value
end

local function format_meta_text(meta)
    local lines = {}
    local function add(label, value)
        local text = value_text(value)
        if text and tostring(text) ~= "" then
            table.insert(lines,
                TextBoxWidget.PTF_BOLD_START .. label
                .. TextBoxWidget.PTF_BOLD_END .. ": " .. tostring(text))
        end
    end

    add(_("Title"), meta.title)
    add(_("Authors"), meta.authors)
    add(_("Series"), meta.series)
    add(_("Publisher"), meta.publisher)
    add(_("Published"), meta.pubdate)
    if meta.rating then
        add(_("Rating"), string.format("%.1f / 10", meta.rating))
    end
    add(_("Tags"), meta.keywords)
    if meta.identifiers and meta.identifiers.isbn then
        add("ISBN", meta.identifiers.isbn)
    end

    if meta.description and #meta.description > 0 then
        table.insert(lines, "")
        table.insert(lines, "─── " .. _("Description") .. " ───")
        table.insert(lines, "")
        table.insert(lines, meta.description)
    end

    return table.concat(lines, "\n")
end

local function fetch_detail_for(session, index)
    if session.cache[index] then
        return session.cache[index]
    end
    local Mod = provider_module(session.provider)
    local work = session.works[index]
    if type(Mod.fetch_work_detail) == "function" then
        local enriched, _ = Mod.fetch_work_detail(work)
        if enriched then work = enriched end
    end
    session.cache[index] = work
    return work
end

function M.show_detail(session)
    local index = session.index
    local total = #session.works
    local work = fetch_detail_for(session, index)
    local meta = work._detail or work

    local prev_btn = {
        text = _("Previous"),
        enabled = index > 1,
        callback = function()
            UIManager:close(session.viewer)
            session.index = index - 1
            M.show_detail(session)
        end,
    }

    local apply_btn = {
        text = "✓ " .. _("Apply"),
        callback = function()
            UIManager:close(session.viewer)
            M.apply_work(session, work)
        end,
    }

    local next_btn = {
        text = _("Next"),
        enabled = index < total,
        callback = function()
            UIManager:close(session.viewer)
            session.index = index + 1
            M.show_detail(session)
        end,
    }

    local base_title = meta.title or _("Book Details")
    local title = string.format("%s (%d/%d)", base_title, index, total)

    local viewer = TextViewer:new{
        title = title,
        text = format_meta_text(meta),
        text_type = "lookup",
        show_menu = false,
        buttons_table = {
            { prev_btn, apply_btn, next_btn },
        },
        close_callback = function()
            UIManager:nextTick(function()
                session.viewer = nil
                show_result_list(session)
            end)
        end,
    }
    session.viewer = viewer
    UIManager:show(viewer)
end

function M.apply_work(session, work)
    local editor = session.editor
    local provider = session.provider
    local key = provider_key(provider)
    local Mod = provider_module(provider)

    local edition = pick_edition(provider, key, work)
    local draft = Mod.draft(work, edition)
    if not draft then
        UIManager:show(InfoMessage:new{
            text = _("This result has no usable metadata."),
            timeout = 3,
        })
        return
    end
    local applied, skipped = editor:apply_provider(draft)
    local msg
    if skipped > 0 then
        msg = string.format(_("Applied %d fields, kept %d manual edits"), applied, skipped)
    else
        msg = string.format(_("Applied %d fields"), applied)
    end
    UIManager:show(Notification:new{ text = msg, timeout = 2 })
    session.viewer = nil
    editor._provider_session = nil
    editor:refresh()
end

-- ============================================================
-- API key settings (multi-provider view/edit)
-- ============================================================

local function edit_key(editor, provider, on_back)
    local config = get_config()
    local current = provider.key_config and config[provider.key_config] or ""
    local dialog
    dialog = InputDialog:new{
        title = provider.name .. " " .. _("API key"),
        input = type(current) == "string" and current or "",
        input_hint = _("Paste the key/token here"),
        buttons = {{
            {
                text = "◂ " .. _("Back"),
                callback = function()
                    UIManager:close(dialog)
                    UIManager:nextTick(on_back)
                end,
            },
            {
                text = _("Save"),
                is_enter_default = true,
                callback = function()
                    local text = dialog:getInputText()
                    UIManager:close(dialog)
                    if provider.key_config then
                        _G.__QUICKUI_CONFIG[provider.key_config] = text or ""
                        Utils.saveConfig()
                    end
                    UIManager:nextTick(on_back)
                end,
            },
        }},
    }
    editor.dialog = dialog
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function M.show_key_settings(editor, target_id)
    local function show_keys()
        local buttons = {}
        table.insert(buttons, {{
            text = "◂ " .. _("Back"),
            callback = function()
                UIManager:close(editor.dialog)
                UIManager:nextTick(function() editor:show_menu() end)
            end,
        }})
        table.insert(buttons, {})

        for _i, provider in ipairs(PROVIDERS) do
            if provider.key_config then
                local _provider = provider
                local key = get_config()[provider.key_config]
                local status = (type(key) == "string" and key ~= "")
                    and _("configured") or _("not set")
                table.insert(buttons, {{
                    text = provider.name .. ": " .. status,
                    callback = function()
                        UIManager:close(editor.dialog)
                        edit_key(editor, _provider, show_keys)
                    end,
                }})
            end
        end

        table.insert(buttons, {})
        table.insert(buttons, {{
            text = "◂ " .. _("Back"),
            callback = function()
                UIManager:close(editor.dialog)
                UIManager:nextTick(function() editor:show_menu() end)
            end,
        }})

        editor.dialog = ButtonDialog:new{
            title = _("Provider API Keys"),
            title_align = "center",
            buttons = buttons,
            width = math.floor(Screen:getWidth() * 0.75),
            max_height = math.floor(Screen:getHeight() * 0.75),
        }
        UIManager:show(editor.dialog)
    end

    if target_id then
        for _i, provider in ipairs(PROVIDERS) do
            if provider.id == target_id and provider.key_config then
                edit_key(editor, provider, function()
                    UIManager:nextTick(function() M.show(editor) end)
                end)
                return
            end
        end
    end

    show_keys()
end

return M