--[[
QuickUI - Metadata Editor

Adapted from zen_ui.koplugin / metadata_editor.lua (MIT, Rameez Khan).
UI rewritten for QuickUI's ButtonDialog-based menu system.
]]

local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local InputDialog = require("ui/widget/inputdialog")
local InfoMessage = require("ui/widget/infomessage")
local MultiConfirmBox = require("ui/widget/multiconfirmbox")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local Notification = require("ui/widget/notification")
local Screen = require("device").screen
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local logger = require("logger")

local Service = require("qui_metadata.qm_service")

local M = {}

local EMPTY = _("Not set")

local FIELD_ORDER = {
    "title", "authors", "series", "genres", "language", "publisher", "description",
}

local FIELD_SPECS = {
    title       = { label = _("Title") },
    authors     = { label = _("Authors"), list = true },
    series      = { label = _("Series") },
    genres      = { label = _("Genres"), list = true },
    language    = { label = _("Language") },
    publisher   = { label = _("Publisher") },
    description = { label = _("Description"), long = true },
}

-- ============================================================
-- Pure helpers
-- ============================================================

local function trim(value)
    value = type(value) == "string" and value or tostring(value or "")
    return value:match("^%s*(.-)%s*$")
end

local function valid_number(value)
    local number = tonumber(trim(value))
    return number and number == number and number ~= math.huge and number ~= -math.huge
end

local function copy_value(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, item in pairs(value) do copy[key] = copy_value(item) end
    return copy
end

local function normalize_list(value)
    if type(value) == "string" then
        local values = {}
        value = value:gsub("\r\n", "\n"):gsub("\r", "\n") .. "\n"
        for line in value:gmatch("(.-)\n") do
            line = trim(line)
            if line ~= "" then values[#values + 1] = line end
        end
        return values
    end
    local values = {}
    for _i, item in ipairs(type(value) == "table" and value or {}) do
        item = trim(item)
        if item ~= "" then values[#values + 1] = item end
    end
    return values
end

local function normalize_draft(value)
    value = type(value) == "table" and value or {}
    return {
        title        = trim(value.title),
        authors      = normalize_list(value.authors),
        series_name  = trim(value.series_name or value.series),
        series_index = trim(value.series_index),
        genres       = normalize_list(value.genres or value.keywords),
        language     = trim(value.language),
        publisher    = trim(value.publisher),
        description  = trim(value.description),
        isbn         = trim(value.isbn),
    }
end

local function same_value(left, right)
    if type(left) ~= type(right) then return false end
    if type(left) ~= "table" then return left == right end
    if #left ~= #right then return false end
    for index, value in ipairs(left) do
        if not same_value(value, right[index]) then return false end
    end
    return true
end

local function join_list(value, separator)
    return table.concat(type(value) == "table" and value or {}, separator or ", ")
end

local function series_text(draft)
    if draft.series_name == "" then return "" end
    if draft.series_index == "" then return draft.series_name end
    return draft.series_name .. " #" .. tostring(draft.series_index)
end

local function preview(value)
    value = tostring(value or ""):gsub("%s+", " ")
    return value ~= "" and value or EMPTY
end

local function has_value(key, draft)
    if key == "authors" or key == "genres" then return #draft[key] > 0 end
    if key == "series" then return draft.series_name ~= "" end
    return draft[key] ~= ""
end

local function field_changed(draft, original, key)
    if key == "series" then
        return draft.series_name ~= original.series_name
            or draft.series_index ~= original.series_index
    end
    return not same_value(draft[key], original[key])
end

local function is_metadata_dirty(draft, original, is_epub)
    for _i, key in ipairs(FIELD_ORDER) do
        if (key ~= "publisher" or is_epub) and field_changed(draft, original, key) then
            return true
        end
    end
    return false
end

-- ============================================================
-- Editor state
-- ============================================================

local Editor = {}
Editor.__index = Editor

function Editor:new(state)
    setmetatable(state, self)
    state.dialog = nil
    return state
end

function Editor:close()
    if self.dialog then
        UIManager:close(self.dialog)
        self.dialog = nil
    end
end

function Editor:refresh()
    self:close()
    UIManager:nextTick(function() self:show_menu() end)
end

function Editor:apply_field(key, value)
    if key == "series" then
        self.draft.series_name = trim(value[1])
        local index = trim(value[2])
        self.draft.series_index = self.draft.series_name ~= "" and index or ""
    elseif FIELD_SPECS[key].list then
        self.draft[key] = normalize_list(value)
    else
        self.draft[key] = trim(value)
    end
    self.manual_fields[key] = true
    self.field_sources[key] = "manual"
    logger.dbg("QuickUI metadata: draft field updated key=", key)
    self:refresh()
end

-- ============================================================
-- Field dialogs
-- ============================================================

function Editor:edit_text_field(key)
    local spec = FIELD_SPECS[key]
    local seed = spec.list and join_list(self.draft[key], "\n") or self.draft[key]
    local dialog
    local self_ref = self

    local function apply()
        local value = dialog:getInputText()
        if self_ref.is_epub and (key == "title" or key == "language")
                and trim(value) == "" then
            UIManager:show(InfoMessage:new{
                text = key == "title"
                    and _("An EPUB title is required.")
                    or _("An EPUB language is required."),
                timeout = 2,
            })
            return
        end
        self_ref:apply_field(key, value)
        UIManager:close(dialog)
    end

    local function cancel()
        UIManager:close(dialog)
        UIManager:nextTick(function() self_ref:show_menu() end)
    end

    dialog = InputDialog:new{
        title = spec.label,
        input = seed,
        input_hint = spec.list and _("One per line") or spec.label,
        description = spec.list and _("Enter one value per line.") or nil,
        allow_newline = spec.list or spec.long,
        fullscreen = spec.long,
        condensed = spec.long,
        add_nav_bar = key ~= "description" and spec.long,
        use_available_height = spec.long,
        scroll_by_pan = spec.long,
        text_height = spec.list and Screen:scaleBySize(110) or nil,
        buttons = {{
            {
                text = _("Cancel"),
                id = "close",
                callback = cancel,
            },
            {
                text = _("Save"),
                is_enter_default = true,
                callback = apply,
            },
        }},
    }
    UIManager:close(self.dialog)
    self.dialog = dialog
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function Editor:edit_series()
    local seed = { self.draft.series_name, self.draft.series_index }
    local dialog
    local self_ref = self

    local function apply()
        local values = dialog:getFields()
        local index = trim(values[2])
        if index ~= "" and not valid_number(index) then
            UIManager:show(InfoMessage:new{
                text = _("Series position must be a number."),
                timeout = 2,
            })
            return
        end
        self_ref:apply_field("series", values)
        UIManager:close(dialog)
    end

    local function cancel()
        UIManager:close(dialog)
        UIManager:nextTick(function() self_ref:show_menu() end)
    end

    dialog = MultiInputDialog:new{
        title = _("Series"),
        fields = {
            { description = _("Name"), text = seed[1] },
            { description = _("Position"), text = seed[2] },
        },
        buttons = {{
            {
                text = _("Cancel"),
                id = "close",
                callback = cancel,
            },
            {
                text = _("Save"),
                is_enter_default = true,
                callback = apply,
            },
        }},
    }
    UIManager:close(self.dialog)
    self.dialog = dialog
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

-- ============================================================
-- Save / close
-- ============================================================

function Editor:save(close_all)
    if self.is_epub and self.draft.title == "" then
        UIManager:show(InfoMessage:new{
            text = _("An EPUB title is required."),
            timeout = 2,
        })
        return
    end
    if self.is_epub and self.draft.language == "" then
        UIManager:show(InfoMessage:new{
            text = _("An EPUB language is required."),
            timeout = 2,
        })
        return
    end
    if self.draft.series_index ~= "" and not valid_number(self.draft.series_index) then
        UIManager:show(InfoMessage:new{
            text = _("Series position must be a number."),
            timeout = 2,
        })
        return
    end
    if self.draft.series_name == "" then self.draft.series_index = "" end

    local file = self.file
    local draft = copy_value(self.draft)
    local self_ref = self
    self:close()

    UIManager:show(Notification:new{
        text = _("Saving metadata..."),
        timeout = 1,
    })

    UIManager:scheduleIn(0.1, function()
        local ok, err = Service.save(file, draft)
        if not ok then
            UIManager:show(InfoMessage:new{
                text = err or _("Saving metadata failed."),
                timeout = 3,
            })
            UIManager:nextTick(function() self_ref:show_menu() end)
            return
        end
        self_ref.original = copy_value(self_ref.draft)
        UIManager:show(Notification:new{
            text = _("Metadata saved"),
            timeout = 2,
        })
        if self_ref.on_done then
            self_ref.on_done(close_all == true)
        end
    end)
end

function Editor:request_close(close_all)
    local self_ref = self

    if not is_metadata_dirty(self.draft, self.original, self.is_epub) then
        self:close()
        if self.on_done then self.on_done(close_all == true) end
        return
    end

    UIManager:show(MultiConfirmBox:new{
        text = _("You have unsaved metadata changes."),
        cancel_text = _("Keep editing"),
        choice1_text = _("Discard"),
        choice1_callback = function()
            self_ref:close()
            if self_ref.on_done then self_ref.on_done(close_all == true) end
        end,
        choice2_text = _("Save"),
        choice2_callback = function()
            self_ref:save(close_all == true)
        end,
    })
end

-- ============================================================
-- Main menu
-- ============================================================

function Editor:show_menu()
    local buttons = {}
    local self_ref = self

    if self.is_epub then
        local can_restore = Service.canRestore(self.file)
        if can_restore then
            table.insert(buttons, {{
                text = _("Restore original metadata"),
                callback = function()
                    self_ref:close()
                    UIManager:show(ConfirmBox:new{
                        text = is_metadata_dirty(self_ref.draft, self_ref.original, self_ref.is_epub)
                            and _("Restore the previous metadata and discard your unsaved changes?")
                            or _("Restore the previous metadata for this book?"),
                        cancel_text = _("Cancel"),
                        ok_text = _("Restore"),
                        ok_callback = function()
                            local ok, err = Service.restore(self_ref.file)
                            if not ok then
                                UIManager:show(InfoMessage:new{
                                    text = err or _("Restoring metadata failed."),
                                    timeout = 3,
                                })
                                UIManager:nextTick(function() self_ref:show_menu() end)
                            else
                                UIManager:show(Notification:new{
                                    text = _("Metadata restored"),
                                    timeout = 2,
                                })
                                if self_ref.on_done then self_ref.on_done(false) end
                            end
                        end,
                    })
                end,
            }})
        end
    end

    table.insert(buttons, {})

    for _i, key in ipairs(FIELD_ORDER) do
        if key ~= "publisher" or self.is_epub then
            local spec = FIELD_SPECS[key]
            local value
            if key == "series" then
                value = series_text(self.draft)
            elseif spec.list then
                value = join_list(self.draft[key])
            else
                value = self.draft[key]
            end
            local dirty = field_changed(self.draft, self.original, key)
            local prefix = dirty and "● " or "  "
            local display = prefix .. spec.label .. ": " .. preview(value)
            local _key = key
            table.insert(buttons, {{
                text = display,
                callback = function()
                    self_ref:close()
                    if _key == "series" then
                        self_ref:edit_series()
                    else
                        self_ref:edit_text_field(_key)
                    end
                end,
            }})
        end
    end

    table.insert(buttons, {})

    table.insert(buttons, {{
        text = _("Find metadata online"),
        callback = function()
            self_ref:close()
            require("qui_metadata.qm_provider_picker").show(self_ref)
        end,
    }})

    if is_metadata_dirty(self.draft, self.original, self.is_epub) then
        table.insert(buttons, {{
            text = "✓ " .. _("Save"),
            callback = function() self_ref:save(false) end,
        }})
    end

    local dialog = ButtonDialog:new{
        title = _("Edit Metadata"),
        title_align = "center",
        buttons = buttons,
        width = math.floor(Screen:getWidth() * 0.75),
        max_height = math.floor(Screen:getHeight() * 0.75),
        tap_close_callback = function()
            self_ref:request_close(false)
        end,
    }
    self.dialog = dialog
    UIManager:show(dialog)
end

-- ============================================================
-- Provider metadata merge
-- ============================================================

function Editor:apply_provider(draft, only_key)
    local incoming = normalize_draft(draft)
    only_key = FIELD_SPECS[only_key] and only_key or nil
    local applied, skipped = 0, 0
    for _i, key in ipairs(only_key and { only_key } or FIELD_ORDER) do
        if (key ~= "publisher" or self.is_epub) and has_value(key, incoming) then
            if not only_key
                    and (self.manual_fields[key] or self.field_sources[key] == "manual") then
                skipped = skipped + 1
            elseif key == "series" then
                self.draft.series_name = incoming.series_name
                if only_key or incoming.series_index ~= "" then
                    self.draft.series_index = incoming.series_index
                end
                self.field_sources[key] = "provider"
                applied = applied + 1
            else
                self.draft[key] = copy_value(incoming[key])
                self.field_sources[key] = "provider"
                applied = applied + 1
            end
            if only_key then self.manual_fields[key] = nil end
        end
    end
    return applied, skipped
end

-- ============================================================
-- Public API
-- ============================================================

function M.open(file, options)
    options = options or {}

    local metadata, err = Service.load(file)
    if not metadata then
        UIManager:show(InfoMessage:new{
            text = err or _("Failed to read metadata"),
            timeout = 3,
        })
        return nil
    end

    local state = {
        file          = file,
        is_epub       = Service.isEpub(file),
        original      = normalize_draft(metadata),
        draft         = normalize_draft(metadata),
        manual_fields = {},
        field_sources = {},
        on_done       = options.on_done,
    }

    for _i, key in ipairs(FIELD_ORDER) do
        state.field_sources[key] = "original"
    end

    local editor = Editor:new(state)
    editor:show_menu()
    return editor
end

M._helpers = {
    trim = trim,
    valid_number = valid_number,
    copy_value = copy_value,
    normalize_list = normalize_list,
    normalize_draft = normalize_draft,
    same_value = same_value,
    join_list = join_list,
    series_text = series_text,
    preview = preview,
    has_value = has_value,
    field_changed = field_changed,
    is_metadata_dirty = is_metadata_dirty,
    FIELD_ORDER = FIELD_ORDER,
    FIELD_SPECS = FIELD_SPECS,
}

return M