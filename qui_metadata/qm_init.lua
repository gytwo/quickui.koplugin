--[[
QuickUI - Metadata Module Entry Point

Entry points:

1. Long-press a book (FileManager / History / Collections / FileSearcher)
   → "Edit metadata" appears in KOReader's own long-press dialog.
   Uses FileManager's official extension point:
       fm:addFileDialogButtons(row_id, row_func)
   Greyed out when the book is currently open in the reader.

2. QuickUI Settings → Metadata Settings → "Edit current book's metadata"
   reads fm.selected_files (same as book_sync.lua).
       - 1 book  → edit directly
       - >1 book → show a picker list
       - 0 books → fall back to the reader's open document
   Books open in the reader are filtered out.

3. Tools menu entry in FileManager.
   Greyed out while the reader UI is alive.
]]

local logger = require("logger")
local _ = require("gettext")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local Notification = require("ui/widget/notification")
local Utils = require("qui_utils")

local M = {}

local plugin = nil

-- ============================================================
-- Config helpers
-- ============================================================

local function getBool(key)
    local config = _G.__QUICKUI_CONFIG
    if config and type(config[key]) == "boolean" then
        return config[key]
    end
    return false
end

local function getString(key)
    local config = _G.__QUICKUI_CONFIG
    if config and type(config[key]) == "string" then
        return config[key]
    end
    return ""
end

-- ============================================================
-- Is this file currently open in the reader?
-- Mirrors qm_service.lua's is_current_reader_file.
-- ============================================================

local function is_current_reader_file(file)
    if type(file) ~= "string" then return false end
    local RUI = require("apps/reader/readerui")
    local reader = RUI and RUI.instance
    if not reader or not reader.document then return false end
    local current = reader.document.file
    if not current then return false end
    if current == file then return true end
    local ffiutil = require("ffi/util")
    local a, b = ffiutil.realpath(current), ffiutil.realpath(file)
    if not a or not b then return false end
    if package.config:sub(1, 1) == "\\" then
        a, b = a:lower(), b:lower()
    end
    return a == b
end

-- ============================================================
-- Selected files (mirrors book_sync.lua's read of fm.selected_files)
-- ============================================================

local function collect_selected_files()
    local lfs = require("libs/libkoreader-lfs")
    local FM = require("apps/filemanager/filemanager")
    local fm = FM and FM.instance
    local result = {}
    if fm and type(fm.selected_files) == "table" then
        for file, selected in pairs(fm.selected_files) do
            if selected and lfs.attributes(file, "mode") == "file" then
                result[#result + 1] = file
            end
        end
    end
    -- pairs order is not deterministic; sort for a stable picker list.
    table.sort(result)
    return result
end

local function current_reader_file()
    local RUI = require("apps/reader/readerui")
    local reader = RUI and RUI.instance
    if reader and reader.document then
        return reader.document.file
    end
    return nil
end

-- ============================================================
-- Refresh helper
-- ============================================================

local function refresh_file_manager()
    local FM = require("apps/filemanager/filemanager")
    local fm = FM and FM.instance
    if fm and fm.file_chooser then
        fm.file_chooser:updateItems()
    end
end

-- ============================================================
-- Entry points
-- ============================================================

function M.edit(file, on_done)
    if not getBool("metadata_enabled") then
        Notification:notify(
            _("Metadata Editor is disabled. Enable it in QuickUI settings."))
        return
    end
    if not file or file == "" then
        UIManager:show(InfoMessage:new{
            text = _("Please select a book first"),
            timeout = 2,
        })
        return
    end
    if is_current_reader_file(file) then
        UIManager:show(InfoMessage:new{
            text = _("This book is currently open in the reader.\n\n"
                .. "Close it first, then edit its metadata."),
            timeout = 4,
        })
        return
    end
    local ok, result = pcall(require("qui_metadata.qm_editor").open, file,
        { on_done = on_done })
    if not ok then
        logger.warn("[QuickUI metadata] editor open failed:", result)
        UIManager:show(InfoMessage:new{
            text = _("Failed to open editor: ") .. tostring(result),
            timeout = 4,
        })
    end
end

-- Multiple books selected → ask which one.
local function pick_one(files, on_done)
    local ButtonDialog = require("ui/widget/buttondialog")
    local Screen = require("device").screen
    local buttons = {}
    local dialog
    for _i, file in ipairs(files) do
        local fname = file:match("([^/]+)$") or file
        local _file = file
        table.insert(buttons, {{
            text = fname,
            callback = function()
                UIManager:close(dialog)
                UIManager:nextTick(function()
                    M.edit(_file, on_done)
                end)
            end,
        }})
    end
    table.insert(buttons, {{
        text = _("Cancel"),
        callback = function() UIManager:close(dialog) end,
    }})
    dialog = ButtonDialog:new{
        title = string.format(_("Edit which book? (%d selected)"), #files),
        title_align = "center",
        buttons = buttons,
        width = math.floor(Screen:getWidth() * 0.8),
        max_height = math.floor(Screen:getHeight() * 0.7),
        rows_per_page = 10,
    }
    UIManager:show(dialog)
end

function M.edit_current(on_done)
    local files = collect_selected_files()

    -- Filter out books currently open in the reader.
    local available = {}
    local skipped_open = 0
    for _i, file in ipairs(files) do
        if is_current_reader_file(file) then
            skipped_open = skipped_open + 1
        else
            available[#available + 1] = file
        end
    end

    if #available == 1 then
        return M.edit(available[1], on_done)
    end
    if #available > 1 then
        return pick_one(available, on_done)
    end

    -- Everything selected is open in the reader.
    if skipped_open > 0 then
        UIManager:show(InfoMessage:new{
            text = _("The selected book(s) are currently open in the reader.\n\n"
                .. "Close them first, then try again."),
            timeout = 4,
        })
        return
    end

    -- No selection at all — fall back to the reader's open book.
    local reader_file = current_reader_file()
    if reader_file then
        UIManager:show(InfoMessage:new{
            text = _("This book is currently open in the reader.\n\n"
                .. "Close it first, then edit its metadata."),
            timeout = 4,
        })
        return
    end

    UIManager:show(InfoMessage:new{
        text = _("No book selected.\n\nLong-press a book and choose "
            .. "\"Edit metadata\", or enable selection mode and check "
            .. "exactly one book first."),
        timeout = 4,
    })
end

-- ============================================================
-- Tools menu injection (FileManager + Reader)
--
-- The item is greyed out in the Reader, because a book that is
-- open in the reader cannot have its metadata edited.
-- ============================================================

local function inject_into_menu(menu_self)
    if not menu_self or not menu_self.tab_item_table then return end
    local target
    for _i, tab in ipairs(menu_self.tab_item_table) do
        if tab.id == "tools" then
            target = tab
            break
        end
    end
    if not target or not target.sub_item_table then return end
    if target._quickui_metadata_injected then return end
    target._quickui_metadata_injected = true

    table.insert(target.sub_item_table, 1, {
        text = _("Edit metadata"),
        enabled_func = function()
            -- Re-read on every call, exactly like qa_settings.lua does
            -- for "Reader Sliders".
            local RUI = require("apps/reader/readerui")
            return not (RUI and RUI.instance)
        end,
        callback = function()
            M.edit_current(refresh_file_manager)
        end,
    })
end
-- ============================================================
-- QuickUI Settings menu items
-- ============================================================

local function edit_key_dialog(title, config_key, after)
    local InputDialog = require("ui/widget/inputdialog")
    local dialog
    dialog = InputDialog:new{
        title = title,
        input = getString(config_key),
        input_hint = _("Paste here"),
        buttons = {{
            {
                text = _("Cancel"),
                callback = function() UIManager:close(dialog) end,
            },
            {
                text = _("Save"),
                is_enter_default = true,
                callback = function()
                    local text = dialog:getInputText() or ""
                    local config = _G.__QUICKUI_CONFIG
                    if config then
                        config[config_key] = text
                        Utils.saveConfig()
                    end
                    UIManager:close(dialog)
                    if after then after() end
                end,
            },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function M.getMenuItems()
    local items = {}

    table.insert(items, {
        text = _("Edit current book's metadata"),
        callback = function()
            M.edit_current(refresh_file_manager)
        end,
    })

    table.insert(items, {
        text = _("Provider API Keys"),
        sub_item_table = {
            {
                text_func = function()
                    local v = getString("metadata_google_books_key")
                    local status = v ~= "" and _("configured") or _("not set")
                    return _("Google Books") .. ": " .. status
                end,
                keep_menu_open = false,
                callback = function()
                    edit_key_dialog(_("Google Books API key"),
                        "metadata_google_books_key")
                end,
            },
            {
                text_func = function()
                    local v = getString("metadata_hardcover_token")
                    local status = v ~= "" and _("configured") or _("not set")
                    return _("Hardcover") .. ": " .. status
                end,
                keep_menu_open = false,
                callback = function()
                    edit_key_dialog(_("Hardcover API token"),
                        "metadata_hardcover_token")
                end,
            },
            {
                text = _("Open Library: no key required"),
                enabled = false,
            },
        },
    })

    local default_items = Utils.buildDefaultMenuItems("metadata", function() end)
    for _i, item in ipairs(default_items) do
        table.insert(items, item)
    end

    return items
end

-- ============================================================
-- Init
-- ============================================================

function M.init(plugin_ref)
    plugin = plugin_ref

    -- ------------------------------------------------------------
    -- 1. Long-press menu via FileManager's official extension point
    --    (fm:addFileDialogButtons). Greyed out when the book is
    --    currently open in the reader.
    -- ------------------------------------------------------------
    local function register_fm_button()
        local FM = require("apps/filemanager/filemanager")
        local fm = FM and FM.instance
        if not fm or type(fm.addFileDialogButtons) ~= "function" then
            return false
        end
        if fm._quickui_metadata_row_registered then
            return true
        end
        fm._quickui_metadata_row_registered = true

        fm:addFileDialogButtons("quickui_metadata_edit",
            function(file, is_file, _book_props)
                if not is_file then return nil end
                if not getBool("metadata_enabled") then return nil end

                local busy = is_current_reader_file(file)

                return {
                    {
                        text = _("Edit metadata"),
                        enabled = not busy,
                        callback = function()
                            if fm.file_chooser and fm.file_chooser.file_dialog then
                                UIManager:close(fm.file_chooser.file_dialog)
                                fm.file_chooser.file_dialog = nil
                            end
                            UIManager:nextTick(function()
                                M.edit(file, refresh_file_manager)
                            end)
                        end,
                    },
                }
            end)

        return true
    end

    if not register_fm_button() then
        local function retry()
            if register_fm_button() then return end
            UIManager:scheduleIn(2, retry)
        end
        UIManager:scheduleIn(2, retry)
    end

    -- ------------------------------------------------------------
    -- 2. Tools menu entry (FileManager + Reader)
    -- ------------------------------------------------------------
    local FileManagerMenu = require("apps/filemanager/filemanagermenu")
    if not FileManagerMenu._quickui_metadata_patched then
        FileManagerMenu._quickui_metadata_patched = true
        local orig = FileManagerMenu.setUpdateItemTable
        FileManagerMenu.setUpdateItemTable = function(self, ...)
            orig(self, ...)
            inject_into_menu(self)
        end
    end

    local ReaderMenu = require("apps/reader/modules/readermenu")
    if not ReaderMenu._quickui_metadata_patched then
        ReaderMenu._quickui_metadata_patched = true
        local orig = ReaderMenu.setUpdateItemTable
        ReaderMenu.setUpdateItemTable = function(self, ...)
            orig(self, ...)
            inject_into_menu(self)
        end
    end
end

return M
