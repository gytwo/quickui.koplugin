--[[
QuickUI - Quick Actions Settings Menu
]]

local logger = require("logger")
local _ = require("gettext")
local Blitbuffer = require("ffi/blitbuffer")
local Screen = require("device").screen
local Device = require("device")
local UIManager = require("ui/uimanager")
local Geom = require("ui/geometry")
local BD = require("ui/bidi")

local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local Notification = require("ui/widget/notification")
local SortWidget = require("ui/widget/sortwidget")
local SpinWidget = require("ui/widget/spinwidget")
local PathChooser = require("ui/widget/pathchooser")

local Utils = require("qui_utils")

local actions = require("qui_actions.qa_actions")
local icon_picker = require("qui_actions.qa_icon_picker")
local plugin_scan = require("qui_actions.qa_plugin_scan")
local menu_recorder = require("qui_actions.qa_menu_recorder")
local uifont = require("qui_actions.qa_uifont")
local settings_icon = icon_picker.nerdIconChar("nerd:E73A") or "⚙️"

local getDefaultViewForActionType = actions.getDefaultViewForActionType

local QA = {}

-- Dialog management variables (module-level)
local _settings_dialog = nil
local _sub_dialog = nil
local _active_dialog = nil
local _choice_dialog = nil
local _coll_picker = nil
local _view_dialog = nil
local _spin_dialog = nil
local _root_items = nil

-- Global storage to avoid module reload issues
local PLUGIN_STORE = _G.__QUICKUI_PLUGIN_STORE or {}
_G.__QUICKUI_PLUGIN_STORE = PLUGIN_STORE

-- ============================================================
-- Initialization
-- ============================================================

function QA.init(plugin)
    PLUGIN_STORE.plugin_ref = plugin
    logger.info("QuickUI QA Settings: initialized")

    -- Register refresh handler for Utils
    Utils.registerRefreshHandler("qa_panel", function()
        QA.refreshQuickPanel()
    end)
end

function QA.setBottombar(bb)
    PLUGIN_STORE.bottombar = bb
    if bb then
        logger.info("QuickUI QA Settings: BottomBar received")
    else
        logger.warn("QuickUI QA Settings: BottomBar not available")
    end
end

-- ============================================================
-- Configuration - Read from _G.__QUICKUI_CONFIG
-- ============================================================

local function getPlugin()
    return PLUGIN_STORE.plugin_ref
end

local function getBool(key, default)
    local config = _G.__QUICKUI_CONFIG
    if config and config[key] ~= nil then
        return config[key]
    end
    return default or false
end

local function setBool(key, value)
    local config = _G.__QUICKUI_CONFIG
    if config then
        config[key] = value
        Utils.saveConfig()
    end
end

local function getString(key, default)
    local config = _G.__QUICKUI_CONFIG
    if config and config[key] ~= nil then
        return config[key]
    end
    return default or ""
end

local function setString(key, value)
    local config = _G.__QUICKUI_CONFIG
    if config then
        config[key] = tostring(value)
        Utils.saveConfig()
    end
end

local function getNumber(key, default)
    local config = _G.__QUICKUI_CONFIG
    if config and type(config[key]) == "number" then
        return config[key]
    end
    return default or 0
end

local function setNumber(key, value)
    local config = _G.__QUICKUI_CONFIG
    if config then
        config[key] = tonumber(value) or 0
        Utils.saveConfig()
    end
end

local function getTable(key)
    local config = _G.__QUICKUI_CONFIG
    if config and config[key] ~= nil then
        return config[key]
    end
    return {}
end

local function setTable(key, value)
    local config = _G.__QUICKUI_CONFIG
    if config then
        config[key] = value
        Utils.saveConfig()
    end
end

local function getQASlots()
    local config = _G.__QUICKUI_CONFIG
    if config and config.qa_panel_slots then
        return config.qa_panel_slots
    end
    return {}
end

local function saveQASlots(slots)
    local config = _G.__QUICKUI_CONFIG
    if config then
        config.qa_panel_slots = slots
        Utils.saveConfig()
    end
end

local function getCustomList()
    local config = _G.__QUICKUI_CONFIG
    if config and config.qa_common_custom_list then
        return config.qa_common_custom_list
    end
    return {}
end

local function setCustomList(value)
    local config = _G.__QUICKUI_CONFIG
    if config then
        config.qa_common_custom_list = value
        Utils.saveConfig()
    end
end

local function getCustom()
    local config = _G.__QUICKUI_CONFIG
    if config and config.qa_common_custom then
        return config.qa_common_custom
    end
    return {}
end

local function setCustom(value)
    local config = _G.__QUICKUI_CONFIG
    if config then
        config.qa_common_custom = value
        Utils.saveConfig()
    end
end

local function getBuiltinOverrides()
    local config = _G.__QUICKUI_CONFIG
    if config and config.qa_common_builtin_overrides then
        return config.qa_common_builtin_overrides
    end
    return {}
end

local function setBuiltinOverrides(value)
    local config = _G.__QUICKUI_CONFIG
    if config then
        config.qa_common_builtin_overrides = value
        Utils.saveConfig()
    end
end

-- ============================================================
-- Forward to actions module
-- ============================================================

local function getAction(id)
    return actions.getAction(id)
end

local function getLabelForAction(id)
    return actions.getLabelForAction(id)
end

local function getActionViewFinal(id)
    return actions.getActionViewFinal(id)
end

local function getAllAvailableActions()
    return actions.getAllAvailableActions()
end

local function getTypePriority(id)
    return actions.getTypePriority(id)
end

local function getActionSymbol(id)
    return actions.getActionSymbol(id)
end

-- ============================================================
-- Dialog Management
-- ============================================================

-- Close all dialogs, with optional exclusions
-- @param exclude: string or table of strings (e.g., "_active_dialog") to skip closing
local function closeSettingsDialog(exclude)
    -- Build exclusion set
    local exclude_set = {}
    if type(exclude) == "string" then
        exclude_set[exclude] = true
    elseif type(exclude) == "table" then
        for __, key in ipairs(exclude) do
            exclude_set[key] = true
        end
    end

    if not exclude_set["_active_dialog"] and _active_dialog then
        UIManager:close(_active_dialog)
        _active_dialog = nil
    end
    if not exclude_set["_settings_dialog"] and _settings_dialog then
        UIManager:close(_settings_dialog)
        _settings_dialog = nil
    end
    if not exclude_set["_sub_dialog"] and _sub_dialog then
        UIManager:close(_sub_dialog)
        _sub_dialog = nil
    end
    if not exclude_set["_choice_dialog"] and _choice_dialog then
        UIManager:close(_choice_dialog)
        _choice_dialog = nil
    end
    if not exclude_set["_coll_picker"] and _coll_picker then
        UIManager:close(_coll_picker)
        _coll_picker = nil
    end
    if not exclude_set["_view_dialog"] and _view_dialog then
        UIManager:close(_view_dialog)
        _view_dialog = nil
    end
end

---@public
function QA.refreshQuickPanel()
    local fm = require("apps/filemanager/filemanager").instance
    if fm and fm.menu and fm.menu.menu_container then
        local menu = fm.menu.menu_container[1]
        if menu and menu.updateItems then
            menu:updateItems()
        end
    end
    local readerui = require("apps/reader/readerui").instance
    if readerui and readerui.menu and readerui.menu.menu_container then
        local menu = readerui.menu.menu_container[1]
        if menu and menu.updateItems then
            menu:updateItems()
        end
    end
end

-- ============================================================
-- Show Menu
-- ============================================================

local function showMenu(items, title, parent_stack, touch_menu, root_items)
    local buttons = {}

    -- Only add QuickUI Settings button when no parent (root menu)
    if parent_stack == nil or #parent_stack == 0 then
        table.insert(buttons, {
            {
                text = "⚙️ " .. _("QuickUI Settings"),
                callback = function()
                    closeSettingsDialog()
                    local plugin = _G.__QUICKUI_PLUGIN_STORE and _G.__QUICKUI_PLUGIN_STORE.plugin_ref
                    if plugin and plugin.quickuisettings then
                        plugin:quickuisettings()
                    end
                end
            }
        })
        table.insert(buttons, {})
    end

    if parent_stack and #parent_stack > 0 then
        if #parent_stack > 1 then
            table.insert(buttons, {
                {
                    text = "◂◂ " .. _("Back to Root"),
                    callback = function()
                        closeSettingsDialog()
                        showMenu(root_items, _("Quick Actions Settings"), nil, touch_menu, root_items)
                    end
                }
            })
        end
        table.insert(buttons, {
            {
                text = "◂ " .. _("Back"),
                callback = function()
                    local parent = parent_stack[#parent_stack]
                    closeSettingsDialog()
                    if parent.items then
                        showMenu(parent.items, parent.title, parent.parent_stack, touch_menu, root_items)
                    else
                        local settings = require("qui_actions/qa_settings")
                        settings.showSettings()
                    end
                end
            }
        })
        table.insert(buttons, {})
    end

    for i = 1, #items do
        local item = items[i]
        local sub_table = item.sub_item_table
        if type(sub_table) == "function" then
            sub_table = sub_table()
        end

        if sub_table and type(sub_table) == "table" and #sub_table > 0 then
            local display_text = item.text_func and item.text_func() or item.text
            if type(display_text) == "function" then
                display_text = display_text()
            end
            table.insert(buttons, {
                {
                    text = display_text .. " ▸",
                    callback = function()
                        closeSettingsDialog()
                        local new_stack = {}
                        if parent_stack then
                            for __, v in ipairs(parent_stack) do
                                table.insert(new_stack, v)
                            end
                        end
                        table.insert(new_stack, {
                            items = items,
                            title = title,
                            parent_stack = parent_stack
                        })
                        showMenu(sub_table, display_text, new_stack, touch_menu, root_items)
                    end
                }
            })
        else
            local checked = item.checked_func and item.checked_func() or false
            local display_text = item.text_func and item.text_func() or item.text
            if type(display_text) == "function" then
                display_text = display_text()
            end
            local prefix = (checked and "✓ " or "  ")
            local enabled = (item.enabled == nil) or (type(item.enabled) == "function" and item.enabled()) or item.enabled

            table.insert(buttons, {
                {
                    text = prefix .. display_text,
                    enabled = enabled,
                    callback = function()
                        -- Execute the callback first
                        if item.callback then
                            item.callback(touch_menu)
                        end

                        -- Handle close_on_click directive
                        if item.close_on_click then
                            -- Determine what to exclude from closing
                            local exclude = {}
                            if type(item.close_on_click) == "table" then
                                exclude = item.close_on_click
                            end
                            -- close_on_click = true  -> close all (exclude = {})
                            -- close_on_click = {"_active_dialog"} -> keep _active_dialog open
                            closeSettingsDialog(exclude)
                        else
                            -- No close instruction: refresh the menu and stay open
                            if touch_menu then
                                touch_menu:updateItems()
                            end
                            QA.refreshQuickPanel()
                            closeSettingsDialog()
                            showMenu(items, title, parent_stack, touch_menu, root_items)
                        end
                    end
                }
            })
        end
    end

    local dialog = ButtonDialog:new{
        title = title or _("Quick Actions Settings"),
        title_align = "center",
        buttons = buttons,
        width = math.floor(Screen:getWidth() * 0.7),
        max_height = math.floor(Screen:getHeight() * 0.7),
    }
    _settings_dialog = dialog
    UIManager:show(dialog)
end

-- ============================================================
-- Edit Built-in Action Dialog
-- ============================================================

function QA.showEditActionDialog(action_id, on_done, source)
    local action = getAction(action_id)
    if not action then return end

    local current_label = action.label
    local current_icon = action.icon
    local current_view = getActionViewFinal(action_id)

    local view_options = { "common", "filemanager", "reader" }
    local view_labels = {
        common = _("Common"),
        filemanager = _("Filemanager"),
        reader = _("Reader"),
    }

    -- Get current position based on source
    local function getCurrentPosition()
        local list
        if source == "bottombar" then
            local bb = PLUGIN_STORE.bottombar
            if not bb then return nil, 0 end
            list = bb.getTabs()
        else
            list = getQASlots()
        end
        for i, id in ipairs(list) do
            if id == action_id then
                return i, #list
            end
        end
        return nil, #list
    end

    -- Remove from current list
    local function removeFromList()
        if source == "bottombar" then
            local tabs = PLUGIN_STORE.bottombar and PLUGIN_STORE.bottombar.getTabs() or {}
            local new_tabs = {}
            for __, id in ipairs(tabs) do
                if id ~= action_id then
                    table.insert(new_tabs, id)
                end
            end
            setTable("qa_bb_tabs", new_tabs)
            if PLUGIN_STORE.bottombar then PLUGIN_STORE.bottombar.refresh() end
        else
            actions.removeFromPanel(action_id, nil)
        end
    end

    -- Move left in current list
    local function moveLeft()
        if source == "bottombar" then
            local tabs = PLUGIN_STORE.bottombar and PLUGIN_STORE.bottombar.getTabs() or {}
            local idx = nil
            for i, id in ipairs(tabs) do
                if id == action_id then
                    idx = i
                    break
                end
            end
            if idx and idx > 1 then
                tabs[idx], tabs[idx-1] = tabs[idx-1], tabs[idx]
                setTable("qa_bb_tabs", tabs)
                if PLUGIN_STORE.bottombar then PLUGIN_STORE.bottombar.refresh() end
            end
        else
            local slots = getQASlots()
            local idx = nil
            for i, id in ipairs(slots) do
                if id == action_id then
                    idx = i
                    break
                end
            end
            if idx and idx > 1 then
                slots[idx], slots[idx-1] = slots[idx-1], slots[idx]
                saveQASlots(slots)
            end
        end
    end

    -- Move right in current list
    local function moveRight()
        if source == "bottombar" then
            local tabs = PLUGIN_STORE.bottombar and PLUGIN_STORE.bottombar.getTabs() or {}
            local idx = nil
            for i, id in ipairs(tabs) do
                if id == action_id then
                    idx = i
                    break
                end
            end
            if idx and idx < #tabs then
                tabs[idx], tabs[idx+1] = tabs[idx+1], tabs[idx]
                setTable("qa_bb_tabs", tabs)
                if PLUGIN_STORE.bottombar then PLUGIN_STORE.bottombar.refresh() end
            end
        else
            local slots = getQASlots()
            local idx = nil
            for i, id in ipairs(slots) do
                if id == action_id then
                    idx = i
                    break
                end
            end
            if idx and idx < #slots then
                slots[idx], slots[idx+1] = slots[idx+1], slots[idx]
                saveQASlots(slots)
            end
        end
    end

    -- Open sort dialog for current list
    local function openSortDialog()
        if source == "bottombar" then
            local tabs = PLUGIN_STORE.bottombar and PLUGIN_STORE.bottombar.getTabs() or {}
            local sort_items = {}
            for i, id in ipairs(tabs) do
                sort_items[#sort_items + 1] = { text = getLabelForAction(id), orig_item = id }
            end
            local sort_dialog = SortWidget:new{
                title = _("Arrange Tabs"),
                item_table = sort_items,
                covers_fullscreen = true,
                callback = function()
                    local new_tabs = {}
                    for j = 1, #sort_items do
                        new_tabs[#new_tabs + 1] = sort_items[j].orig_item
                    end
                    setTable("qa_bb_tabs", new_tabs)
                    if PLUGIN_STORE.bottombar then PLUGIN_STORE.bottombar.refresh() end
                    if on_done then on_done() end
                end,
            }
            UIManager:show(sort_dialog)
        else
            local slots = getQASlots()
            local sort_items = {}
            for i, id in ipairs(slots) do
                sort_items[#sort_items + 1] = { text = getLabelForAction(id), orig_item = id }
            end
            local sort_dialog = SortWidget:new{
                title = _("Arrange Buttons"),
                item_table = sort_items,
                covers_fullscreen = true,
                callback = function()
                    local new_slots = {}
                    for j = 1, #sort_items do
                        new_slots[#new_slots + 1] = sort_items[j].orig_item
                    end
                    saveQASlots(new_slots)
                    QA.refreshQuickPanel()
                    if on_done then on_done() end
                end,
            }
            UIManager:show(sort_dialog)
        end
    end

    local function rebuildDialog()
        if _active_dialog then
            UIManager:close(_active_dialog)
            _active_dialog = nil
        end
        if _view_dialog then
            UIManager:close(_view_dialog)
            _view_dialog = nil
        end

        local function iconButtonText()
            if not current_icon then return _("Icon: Default (tap to change)") end
            local nerd_char = icon_picker.nerdIconChar(current_icon)
            if nerd_char then
                local hex = current_icon:match("nerd:(.+)")
                return _("Icon") .. ": " .. nerd_char .. " (" .. hex .. ")"
            end
            local fname = current_icon:match("([^/]+)$") or current_icon
            local stem = (fname:match("^(.+)%.[^%.]+$") or fname):gsub("_", " ")
            return _("Icon") .. ": " .. stem
        end

        local function viewButtonText()
            return _("View") .. ": " .. view_labels[current_view]
        end

        local fields = {
            { description = _("Name"), text = current_label, hint = _("Action name...") }
        }

        local pos, total = getCurrentPosition()

        local last_row = {
            { text = _("Cancel"), id = "close", callback = function()
                closeSettingsDialog()
            end },
        }

        table.insert(last_row, { text = _("Remove"), callback = function()
            closeSettingsDialog()
            removeFromList()
            if on_done then on_done() end
        end })

        if pos then
            table.insert(last_row, { text = "◀", enabled = (pos > 1), callback = function()
                closeSettingsDialog()
                moveLeft()
                rebuildDialog()
            end })
        end

        if pos then
            table.insert(last_row, { text = pos .. "/" .. total, callback = function()
                closeSettingsDialog()
                openSortDialog()
            end })
        end

        if pos then
            table.insert(last_row, { text = "▶", enabled = (pos < total), callback = function()
                closeSettingsDialog()
                moveRight()
                rebuildDialog()
            end })
        end

        table.insert(last_row, { text = _("Save"), is_enter_default = true, callback = function()
            if not _active_dialog then return end
            local inputs = _active_dialog:getFields()
            local new_label = inputs[1] or ""
            if new_label == "" then
                UIManager:show(InfoMessage:new{ text = _("Please enter a name"), timeout = 2 })
                return
            end
            closeSettingsDialog()

            local overrides = getBuiltinOverrides()
            if not overrides[action_id] then
                overrides[action_id] = {}
            end
            overrides[action_id].label = new_label
            overrides[action_id].icon = current_icon
            overrides[action_id].view = current_view
            setBuiltinOverrides(overrides)
            if PLUGIN_STORE.bottombar then
                 PLUGIN_STORE.bottombar.refresh()
            end
            if on_done then on_done() end
        end })

        local buttons = {
            { { text = iconButtonText(), callback = function()
                closeSettingsDialog()
                icon_picker.showIconPicker(function(new_icon)
                    current_icon = new_icon
                    rebuildDialog()
                end, current_icon)
            end } },
            { { text = viewButtonText(), callback = function()
                closeSettingsDialog()
                local view_buttons = {}
                for __, v in ipairs(view_options) do
                    local _v = v
                    table.insert(view_buttons, {{
                        text = (current_view == _v and "✓ " or "  ") .. view_labels[_v],
                        callback = function()
                            if _view_dialog then
                                UIManager:close(_view_dialog)
                                _view_dialog = nil
                            end
                            current_view = _v
                            rebuildDialog()
                        end,
                    }})
                end
                table.insert(view_buttons, {{
                    text = _("Back"),
                    callback = function()
                        if _view_dialog then
                            UIManager:close(_view_dialog)
                            _view_dialog = nil
                        end
                        rebuildDialog()
                    end,
                }})
                _view_dialog = ButtonDialog:new{
                    title = _("Select View"),
                    title_align = "center",
                    buttons = view_buttons,
                    width = math.floor(Screen:getWidth() * 0.7),
                }
                UIManager:show(_view_dialog)
            end } },
            last_row,
        }

        _active_dialog = MultiInputDialog:new{
            title = source == "bottombar" and _("Edit Bottom Bar Tab") or _("Edit Quick Action"),
            fields = fields,
            tap_close_callback = function()
                closeSettingsDialog()
            end,
            buttons = buttons,
        }
        UIManager:show(_active_dialog)
        pcall(function() _active_dialog:onShowKeyboard() end)
    end

    rebuildDialog()
end

-- ============================================================
-- Custom QA Dialog
-- ============================================================

function QA.showCustomQADialog(qa_id, on_done, source)
    closeSettingsDialog()

    local custom = getCustom()
    local cfg = qa_id and custom[qa_id] or {}
    local chosen_icon = cfg.icon
    local dlg_title = qa_id and _("Edit Quick Action") or _("New Quick Action")
    local existing_label = cfg.label or ""

    local current_action_type = nil
    local current_action_val1 = nil
    local current_action_val2 = nil
    local current_action_title = nil
    local current_view = cfg.view or "common"

    if cfg.action_type == "dispatcher" and cfg.dispatcher_action then
        current_action_type = "dispatcher"
        current_action_val1 = cfg.dispatcher_action
        current_action_val2 = cfg.dispatcher_value or true
        current_action_title = cfg.dispatcher_action
    elseif cfg.action_type == "plugin" and cfg.plugin_key then
        current_action_type = "plugin"
        current_action_val1 = cfg.plugin_key
        current_action_val2 = cfg.plugin_method
        current_action_title = cfg.plugin_key
    elseif cfg.action_type == "collections" and cfg.action_value then
        current_action_type = "collections"
        current_action_val1 = cfg.action_value
        current_action_title = cfg.action_value
    elseif cfg.action_type == "folder" and cfg.action_value then
        current_action_type = "folder"
        current_action_val1 = cfg.action_value
        current_action_title = cfg.action_value:match("([^/]+)$") or cfg.action_value
    elseif cfg.action_type == "menu" and cfg.menu_path then
        current_action_type = "menu"
        current_action_val1 = cfg.menu_path
        current_action_title = cfg.menu_path.display_label or _("Menu Action")
    end

    local view_options = { "common", "filemanager", "reader" }
    local view_labels = {
        common = _("Common"),
        filemanager = _("Filemanager"),
        reader = _("Reader"),
    }

    -- Get current position based on source
    local function getCurrentPosition()
        local list
        if source == "bottombar" then
            local bb = PLUGIN_STORE.bottombar
            if not bb then return nil, 0 end
            list = bb.getTabs()
        else
            list = getQASlots()
        end
        for i, id in ipairs(list) do
            if id == qa_id then
                return i, #list
            end
        end
        return nil, #list
    end

    -- Remove from current list
    local function removeFromList()
        if source == "bottombar" then
            local tabs = PLUGIN_STORE.bottombar and PLUGIN_STORE.bottombar.getTabs() or {}
            local new_tabs = {}
            for __, id in ipairs(tabs) do
                if id ~= qa_id then
                    table.insert(new_tabs, id)
                end
            end
            setTable("qa_bb_tabs", new_tabs)
            if PLUGIN_STORE.bottombar then PLUGIN_STORE.bottombar.refresh() end
        else
            local slots = getQASlots()
            local new_slots = {}
            for __, sid in ipairs(slots) do
                if sid ~= qa_id then
                    table.insert(new_slots, sid)
                end
            end
            saveQASlots(new_slots)
        end
    end

    -- Move left in current list
    local function moveLeft()
        if source == "bottombar" then
            local tabs = PLUGIN_STORE.bottombar and PLUGIN_STORE.bottombar.getTabs() or {}
            local idx = nil
            for i, id in ipairs(tabs) do
                if id == qa_id then
                    idx = i
                    break
                end
            end
            if idx and idx > 1 then
                tabs[idx], tabs[idx-1] = tabs[idx-1], tabs[idx]
                setTable("qa_bb_tabs", tabs)
                if PLUGIN_STORE.bottombar then PLUGIN_STORE.bottombar.refresh() end
            end
        else
            local slots = getQASlots()
            local idx = nil
            for i, id in ipairs(slots) do
                if id == qa_id then
                    idx = i
                    break
                end
            end
            if idx and idx > 1 then
                slots[idx], slots[idx-1] = slots[idx-1], slots[idx]
                saveQASlots(slots)
            end
        end
    end

    -- Move right in current list
    local function moveRight()
        if source == "bottombar" then
            local tabs = PLUGIN_STORE.bottombar and PLUGIN_STORE.bottombar.getTabs() or {}
            local idx = nil
            for i, id in ipairs(tabs) do
                if id == qa_id then
                    idx = i
                    break
                end
            end
            if idx and idx < #tabs then
                tabs[idx], tabs[idx+1] = tabs[idx+1], tabs[idx]
                setTable("qa_bb_tabs", tabs)
                if PLUGIN_STORE.bottombar then PLUGIN_STORE.bottombar.refresh() end
            end
        else
            local slots = getQASlots()
            local idx = nil
            for i, id in ipairs(slots) do
                if id == qa_id then
                    idx = i
                    break
                end
            end
            if idx and idx < #slots then
                slots[idx], slots[idx+1] = slots[idx+1], slots[idx]
                saveQASlots(slots)
            end
        end
    end

    -- Open sort dialog for current list
    local function openSortDialog()
        if source == "bottombar" then
            local tabs = PLUGIN_STORE.bottombar and PLUGIN_STORE.bottombar.getTabs() or {}
            local sort_items = {}
            for i, id in ipairs(tabs) do
                sort_items[#sort_items + 1] = { text = getLabelForAction(id), orig_item = id }
            end
            local sort_dialog = SortWidget:new{
                title = _("Arrange Tabs"),
                item_table = sort_items,
                covers_fullscreen = true,
                callback = function()
                    local new_tabs = {}
                    for j = 1, #sort_items do
                        new_tabs[#new_tabs + 1] = sort_items[j].orig_item
                    end
                    setTable("qa_bb_tabs", new_tabs)
                    if PLUGIN_STORE.bottombar then PLUGIN_STORE.bottombar.refresh() end
                    if on_done then on_done() end
                end,
            }
            UIManager:show(sort_dialog)
        else
            local slots = getQASlots()
            local sort_items = {}
            for i, id in ipairs(slots) do
                sort_items[#sort_items + 1] = { text = getLabelForAction(id), orig_item = id }
            end
            local sort_dialog = SortWidget:new{
                title = _("Arrange Buttons"),
                item_table = sort_items,
                covers_fullscreen = true,
                callback = function()
                    local new_slots = {}
                    for j = 1, #sort_items do
                        new_slots[#new_slots + 1] = sort_items[j].orig_item
                    end
                    saveQASlots(new_slots)
                    QA.refreshQuickPanel()
                    if on_done then on_done() end
                end,
            }
            UIManager:show(sort_dialog)
        end
    end

    local function commitQA(final_label, path, collections, icon, plugin_key, plugin_method, dispatcher_action, dispatcher_value, menu_path, user_view)
        local list = getCustomList()
        local max_n = 0
        for __, id in ipairs(list) do
            local n = tonumber(id:match("^custom_qa_(%d+)$"))
            if n and n > max_n then max_n = n end
        end
        local final_id = qa_id or ("custom_qa_" .. (max_n + 1))

        local custom_tbl = getCustom()
        local custom_list = getCustomList()

        local action_type = nil
        local default_view = "common"

        if path and path ~= "" then
            action_type = "folder"
            default_view = "filemanager"
        elseif collections and collections ~= "" then
            action_type = "collections"
            default_view = "filemanager"
        elseif plugin_key and plugin_key ~= "" then
            action_type = "plugin"
            default_view = "common"
        elseif dispatcher_action and dispatcher_action ~= "" then
            action_type = "dispatcher"
            default_view = "common"
        elseif menu_path and type(menu_path) == "table" then
            action_type = "menu"
            default_view = user_view or "common"
        end

        local final_view
        if action_type == "menu" then
            final_view = default_view
        else
            final_view = user_view or default_view
        end

        local cfg_table = {
            label = final_label,
            icon = icon,
            is_in_place = (dispatcher_action ~= nil or plugin_key ~= nil),
            action_type = action_type,
            view = final_view,
        }

        if path and path ~= "" then
            cfg_table.action_value = path
        elseif collections and collections ~= "" then
            cfg_table.action_value = collections
        elseif plugin_key and plugin_key ~= "" then
            cfg_table.plugin_key = plugin_key
            if plugin_method and type(plugin_method) == "table" and plugin_method.type == "submenu" then
                cfg_table.plugin_method = plugin_method
            else
                if type(plugin_method) == "string" then
                    cfg_table.plugin_method = plugin_method
                else
                    cfg_table.plugin_method = nil
                end
            end
        elseif dispatcher_action and dispatcher_action ~= "" then
            cfg_table.dispatcher_action = dispatcher_action
            cfg_table.dispatcher_value = dispatcher_value
        elseif menu_path and type(menu_path) == "table" then
            cfg_table.menu_path = menu_path
        end

        custom_tbl[final_id] = cfg_table
        setCustom(custom_tbl)
        if PLUGIN_STORE.bottombar then
            PLUGIN_STORE.bottombar.refresh()
        end

        local auto_add = getBool("qa_common_auto_add_to_panel")
        if source ~= "bottombar" and auto_add then
            local slots = getQASlots()
            local already_exists = false
            for __, sid in ipairs(slots) do
                if sid == final_id then
                    already_exists = true
                    break
                end
            end
            if not already_exists then
                if #slots < 66 then
                    slots[#slots + 1] = final_id
                    saveQASlots(slots)
                else
                    UIManager:show(InfoMessage:new{
                        text = string.format(_("Panel is full (max 66 buttons), cannot auto-add.")),
                        timeout = 3,
                    })
                end
            end
        end

        if not qa_id then
            custom_list[#custom_list + 1] = final_id
            setCustomList(custom_list)
        end

        if on_done then on_done() end
    end

    local buildSaveDialog = nil

    local function cancelActionPicker()
        if not current_action_type and not qa_id then
            if on_done then on_done() end
        else
            if _active_dialog then
                UIManager:close(_active_dialog)
                _active_dialog = nil
            end
            if buildSaveDialog then
                buildSaveDialog(false)
            end
        end
    end

    local function openActionPicker()
        if _active_dialog then
            UIManager:close(_active_dialog)
            _active_dialog = nil
        end

        local function getcollectionsList()
            local ok, RC = pcall(require, "readcollection")
            if not ok or not RC then return {} end
            pcall(RC._read, RC)
            local collections = {}
            if RC.coll then
                for name in pairs(RC.coll) do
                    if name ~= RC.default_collections_name then
                        collections[#collections + 1] = name
                    end
                end
            end
            table.sort(collections, function(a, b) return a:lower() < b:lower() end)
            return collections
        end

        local collections = getcollectionsList()

        _choice_dialog = ButtonDialog:new{
            title = _("Action Type"),
            title_align = "center",
            buttons = {
                { { text = _("Folder"), callback = function()
                    closeSettingsDialog()
                    local home_dir = G_reader_settings:readSetting("home_dir") or "/"
                    local pc = PathChooser:new{
                        select_directory = true,
                        select_file = false,
                        path = home_dir,
                        onConfirm = function(path)
                            path = path:gsub("/$", "")
                            current_action_type = "folder"
                            current_action_val1 = path
                            current_action_title = path:match("([^/]+)$") or path
                            current_view = "filemanager"
                            closeSettingsDialog()
                            if buildSaveDialog then
                                buildSaveDialog(true)
                            end
                        end,
                        onCancel = function()
                            closeSettingsDialog()
                            openActionPicker()
                        end,
                    }
                    UIManager:show(pc)
                end } },
                { { text = _("Collections"), enabled = (#collections > 0), callback = function()
                    closeSettingsDialog()
                    local coll_buttons = {}
                    for __, name in ipairs(collections) do
                        local _name = name
                        coll_buttons[#coll_buttons + 1] = {{ text = name, callback = function()
                            closeSettingsDialog()
                            if _coll_picker then UIManager:close(_coll_picker); _coll_picker = nil end
                            if _choice_dialog then UIManager:close(_choice_dialog); _choice_dialog = nil end
                            current_action_type = "collections"
                            current_action_val1 = _name
                            current_action_title = _name
                            current_view = "filemanager"
                            if buildSaveDialog then
                                buildSaveDialog(true)
                            end
                        end }}
                    end
                    coll_buttons[#coll_buttons + 1] = {{ text = _("Back"), callback = function()
                        if _coll_picker then UIManager:close(_coll_picker); _coll_picker = nil end
                        openActionPicker()
                    end }}
                    _coll_picker = ButtonDialog:new{
                        title = _("Select collections"),
                        title_align = "center",
                        buttons = coll_buttons,
                        width = math.floor(Screen:getWidth() * 0.7),
                    }
                    UIManager:show(_coll_picker)
                end } },
                { { text = _("Plugin or Patch"), callback = function()
                    closeSettingsDialog()
                    plugin_scan.showPluginPicker(
                        function(plugin_key, plugin_method, title)
                            current_action_type = "plugin"
                            current_action_val1 = plugin_key
                            current_action_val2 = plugin_method
                            current_action_title = title or plugin_key
                            current_view = "common"
                            if buildSaveDialog then
                                buildSaveDialog(true)
                            end
                        end,
                        function()
                            cancelActionPicker()
                        end,
                        function()
                            buildSaveDialog(false)
                        end,
                        function()
                            openActionPicker()
                        end,
                        function()
                            QA.showSettings()
                        end
                    )
                end } },
                { { text = _("System Action"), callback = function()
                    if _G.__system_dialog then
                        UIManager:close(_G.__system_dialog)
                        _G.__system_dialog = nil
                    end
                    closeSettingsDialog()
                    actions.openDispatcherPicker(
                        function(action_id, value, title)
                            current_action_type = "dispatcher"
                            current_action_val1 = action_id
                            current_action_val2 = value or true
                            current_action_title = title or action_id
                            current_view = getDefaultViewForActionType("dispatcher", action_id)
                            if buildSaveDialog then
                                buildSaveDialog(true)
                            end
                        end,
                        function()
                            cancelActionPicker()
                        end,
                        function()
                            buildSaveDialog(false)
                        end,
                        function()
                            openActionPicker()
                        end,
                        function()
                            QA.showSettings()
                        end
                    )
                end } },
                { { text = _("Record Menu Action"), callback = function()
                    closeSettingsDialog()
                    local FM = require("apps/filemanager/filemanager")
                    local fm = FM and FM.instance
                    local RUI = require("apps/reader/readerui")
                    local rui = RUI and RUI.instance

                    local target_menu = nil
                    local view = "reader"

                    if rui and rui.menu then
                        if not rui.menu.menu_container or not rui.menu.menu_container[1] then
                            rui.menu:onShowMenu()
                        end
                        target_menu = rui.menu.menu_container and rui.menu.menu_container[1]
                        view = "reader"
                    elseif fm and fm.menu then
                        if not fm.menu.menu_container or not fm.menu.menu_container[1] then
                            fm.menu:onShowMenu()
                        end
                        target_menu = fm.menu.menu_container and fm.menu.menu_container[1]
                        view = "filemanager"
                    end

                    if not target_menu then
                        UIManager:show(InfoMessage:new{
                            text = _("Unable to open menu"),
                            timeout = 3
                        })
                        cancelActionPicker()
                        return
                    end

                    menu_recorder.startRecording(target_menu, view, function(path_record)
                        closeSettingsDialog()
                        if _choice_dialog then UIManager:close(_choice_dialog); _choice_dialog = nil end
                        local function cleanString(s)
                            if not s then return "" end
                            return s:gsub("[\n\r]", ""):match("^%s*(.-)%s*$") or ""
                        end
                        local clean_record = {
                            tab_index = path_record.tab_index,
                            display_label = cleanString(path_record.display_label),
                            index_path = path_record.index_path,
                            is_leaf = path_record.is_leaf,
                        }
                        current_action_type = "menu"
                        current_action_val1 = clean_record
                        current_action_title = clean_record.display_label
                        current_view = view
                        buildSaveDialog(true)
                    end, function()
                        cancelActionPicker()
                    end)
                end } },
                { { text = _("Back"), callback = function()
                    if _choice_dialog then
                        UIManager:close(_choice_dialog)
                        _choice_dialog = nil
                    end
                    if buildSaveDialog then
                        buildSaveDialog(false)
                    end
                end } },
            }
        }
        UIManager:show(_choice_dialog)
    end

    buildSaveDialog = function(update_name_with_title)
        if _coll_picker then
            UIManager:close(_coll_picker)
            _coll_picker = nil
        end
        if _choice_dialog then
            UIManager:close(_choice_dialog)
            _choice_dialog = nil
        end
        if _active_dialog then
            UIManager:close(_active_dialog)
            _active_dialog = nil
        end
        if _view_dialog then
            UIManager:close(_view_dialog)
            _view_dialog = nil
        end

        if update_name_with_title then
            if current_action_title then
                existing_label = current_action_title
            end
        end

        local action_label = _("Action") .. ": "
        if current_action_type then
            action_label = action_label .. (current_action_title or "")
        else
            action_label = action_label .. _("Tap to set action")
        end

        local function iconButtonText()
            if not chosen_icon then return _("Icon: Default (tap to change)") end
            local nerd_char = icon_picker.nerdIconChar(chosen_icon)
            if nerd_char then
                local hex = chosen_icon:match("nerd:(.+)")
                return _("Icon") .. ": " .. nerd_char .. " (" .. hex .. ")"
            end
            local fname = chosen_icon:match("([^/]+)$") or chosen_icon
            local stem = (fname:match("^(.+)%.[^%.]+$") or fname):gsub("_", " ")
            return _("Icon") .. ": " .. stem
        end

        local function viewButtonText()
            local is_locked = (current_action_type == "menu")
            if is_locked then
                return _("View") .. ": " .. view_labels[current_view] .. " (" .. _("locked") .. ")"
            else
                return _("View") .. ": " .. view_labels[current_view]
            end
        end

        local fields = {
            { description = _("Name"), text = existing_label, hint = _("Action name...") },
        }

        local pos, total = getCurrentPosition()

        local last_row = {
            { text = _("Cancel"), id = "close", callback = function()
                closeSettingsDialog()
                if not qa_id and not current_action_type then
                    if on_done then on_done() end
                end
            end },
        }

        if qa_id then
            table.insert(last_row, { text = _("Delete"), callback = function()
                closeSettingsDialog()
                UIManager:show(ConfirmBox:new{
                    text = string.format(_("Delete quick action \"%s\"?"), existing_label),
                    ok_text = _("Delete"),
                    cancel_text = _("Cancel"),
                    ok_callback = function()
                        local custom_tbl = getCustom()
                        custom_tbl[qa_id] = nil
                        setCustom(custom_tbl)
                        local list = getCustomList()
                        local new_list = {}
                        for __, id in ipairs(list) do
                            if id ~= qa_id then
                                table.insert(new_list, id)
                            end
                        end
                        setCustomList(new_list)
                        removeFromList()
                        if on_done then on_done() end
                    end,
                })
            end })
        end

        if pos then
            table.insert(last_row, { text = "◀", enabled = (pos > 1), callback = function()
                closeSettingsDialog()
                moveLeft()
                buildSaveDialog(false)
            end })
        end

        if pos then
            table.insert(last_row, { text = pos .. "/" .. total, callback = function()
                closeSettingsDialog()
                openSortDialog()
            end })
        end

        if pos then
            table.insert(last_row, { text = "▶", enabled = (pos < total), callback = function()
                closeSettingsDialog()
                moveRight()
                buildSaveDialog(false)
            end })
        end

        table.insert(last_row, { text = _("Remove"), callback = function()
            closeSettingsDialog()
            removeFromList()
            if on_done then on_done() end
        end })

        table.insert(last_row, { text = _("Save"), is_enter_default = true, callback = function()
            local inputs = _active_dialog:getFields()
            local final_label = inputs[1] or ""
            if final_label == "" then
                UIManager:show(InfoMessage:new{ text = _("Please enter a name"), timeout = 2 })
                return
            end
            if not current_action_type then
                UIManager:show(InfoMessage:new{ text = _("Please select an action type"), timeout = 2 })
                return
            end

            closeSettingsDialog()

            local default_icon = "nerd:F114"
            if current_action_type == "plugin" then
                default_icon = "nerd:F1B2"
            elseif current_action_type == "dispatcher" then
                default_icon = "nerd:E235"
            elseif current_action_type == "menu" then
                default_icon = "nerd:E7FB"
            elseif current_action_type == "collections" then
                default_icon = "nerd:E257"
            end

            local path, collections, plugin_key, plugin_method, dispatcher_action, dispatcher_value, menu_path
            if current_action_type == "folder" then
                path = current_action_val1
            elseif current_action_type == "collections" then
                collections = current_action_val1
            elseif current_action_type == "plugin" then
                plugin_key = current_action_val1
                plugin_method = current_action_val2
            elseif current_action_type == "dispatcher" then
                dispatcher_action = current_action_val1
                dispatcher_value = current_action_val2
            elseif current_action_type == "menu" then
                menu_path = current_action_val1
            end

            commitQA(final_label, path, collections, chosen_icon or default_icon,
                plugin_key, plugin_method, dispatcher_action, dispatcher_value, menu_path, current_view)
        end })

        local buttons = {
            { { text = action_label, callback = function()
                closeSettingsDialog()
                openActionPicker()
            end } },
            { { text = iconButtonText(), callback = function()
                closeSettingsDialog()
                icon_picker.showIconPicker(
                    function(result)
                        if result then
                            chosen_icon = result
                        else
                            chosen_icon = nil
                        end
                        buildSaveDialog(false)
                    end,
                    chosen_icon
                )
            end } },
            { { text = viewButtonText(), enabled = (current_action_type ~= "menu"), callback = function()
                if current_action_type == "menu" then return end
                closeSettingsDialog()
                local view_buttons = {}
                for __, v in ipairs(view_options) do
                    local _v = v
                    table.insert(view_buttons, {{
                        text = (current_view == _v and "✓ " or "  ") .. view_labels[_v],
                        callback = function()
                            if _view_dialog then
                                UIManager:close(_view_dialog)
                                _view_dialog = nil
                            end
                            current_view = _v
                            buildSaveDialog(false)
                        end,
                    }})
                end
                table.insert(view_buttons, {{
                    text = _("Back"),
                    callback = function()
                        if _view_dialog then
                            UIManager:close(_view_dialog)
                            _view_dialog = nil
                        end
                        buildSaveDialog(false)
                    end,
                }})
                _view_dialog = ButtonDialog:new{
                    title = _("Select View"),
                    title_align = "center",
                    buttons = view_buttons,
                    width = math.floor(Screen:getWidth() * 0.7),
                }
                UIManager:show(_view_dialog)
            end } },
            last_row,
        }

        _active_dialog = MultiInputDialog:new{
            title = source == "bottombar" and _("Edit Bottom Bar Tab") or dlg_title,
            fields = fields,
            tap_close_callback = function()
                closeSettingsDialog()
                if not qa_id and not current_action_type then
                    if on_done then on_done() end
                end
            end,
            buttons = buttons,
        }
        UIManager:show(_active_dialog)
        pcall(function() _active_dialog:onShowKeyboard() end)
    end

    buildSaveDialog(false)
end

-- ============================================================
-- Add Button Menu
-- ============================================================

function QA.showAddButtonMenu(touch_menu, on_back, filtered_actions)
    local slots = getQASlots()
    local slot_set = {}
    for __, id in ipairs(slots) do
        slot_set[id] = true
    end
    local available = filtered_actions or getAllAvailableActions()
    table.sort(available, function(a, b)
        local a_checked = slot_set[a.id] or false
        local b_checked = slot_set[b.id] or false
        if a_checked ~= b_checked then
            return a_checked
        end
        local a_prio = getTypePriority(a.id)
        local b_prio = getTypePriority(b.id)
        if a_prio ~= b_prio then
            return a_prio < b_prio
        end
        return a.label:lower() < b.label:lower()
    end)

    local buttons = {}

    -- Search button
    table.insert(buttons, { Utils.createSearchButton(
        function()
            QA.showAddButtonMenu(touch_menu, on_back)
        end,
        function(keyword)
            if _add_button_dialog then
                UIManager:close(_add_button_dialog)
                _add_button_dialog = nil
            end
            local filtered = Utils.filterActionsByKeyword(getAllAvailableActions(), keyword)
            QA.showAddButtonMenu(touch_menu, on_back, filtered)
    end,
        function()
            if _add_button_dialog then
                UIManager:close(_add_button_dialog)
                _add_button_dialog = nil
            end
        end
    ) })
    table.insert(buttons, {})

    if on_back then

        table.insert(buttons, {
            {
                text = "◂◂ " .. _("Back to Root"),
                callback = function()
                    if _add_button_dialog then
                        UIManager:close(_add_button_dialog)
                        _add_button_dialog = nil
                    end
                    closeSettingsDialog()
                    QA.showSettings()
                end
            }
        })

        table.insert(buttons, {
            {
                text = "◂ " .. _("Back"),
                callback = function()
                    if _add_button_dialog then
                        UIManager:close(_add_button_dialog)
                        _add_button_dialog = nil
                    end
                    closeSettingsDialog()
                    on_back()
                end
            }
        })
        table.insert(buttons, {})
    else
        table.insert(buttons, {
            {
                text = settings_icon .. " " .. _("QA Settings"),
                callback = function()
                    if _add_button_dialog then
                        UIManager:close(_add_button_dialog)
                        _add_button_dialog = nil
                    end
                    closeSettingsDialog()
                    QA.showSettings()
                end
            }
        })
        table.insert(buttons, {})
    end

    table.insert(buttons, {
        {
            text = _("Frontlight Slider"),
            checked_func = function()
                return getBool("qa_panel_frontlight")
            end,
            callback = function(touchmenu_instance)
                setBool("qa_panel_frontlight", not getBool("qa_panel_frontlight"))
                if touchmenu_instance then
                    touchmenu_instance:updateItems()
                end
                if touch_menu then
                    touch_menu:updateItems()
                end
                closeSettingsDialog()
                QA.showAddButtonMenu(touch_menu, on_back)
            end,
        }
    })

    if Device:hasNaturalLight() then
        table.insert(buttons, {
            {
                text = _("Warmth Slider"),
                checked_func = function()
                    return getBool("qa_panel_warmth")
                end,
                callback = function(touchmenu_instance)
                    setBool("qa_panel_warmth", not getBool("qa_panel_warmth"))
                    if touchmenu_instance then
                        touchmenu_instance:updateItems()
                    end
                    if touch_menu then
                        touch_menu:updateItems()
                    end
                    closeSettingsDialog()
                    QA.showAddButtonMenu(touch_menu, on_back)
                end,
            }
        })
    end

    table.insert(buttons, {
        {
            text = _("Show Slider Value"),
            checked_func = function()
                return getBool("qa_panel_slider_show_value")
            end,
            callback = function(touchmenu_instance)
                setBool("qa_panel_slider_show_value", not getBool("qa_panel_slider_show_value"))
                if touchmenu_instance then
                    touchmenu_instance:updateItems()
                end
                if touch_menu then
                    touch_menu:updateItems()
                end
                closeSettingsDialog()
                QA.showAddButtonMenu(touch_menu, on_back)
            end,
        }
    })

    local function getAllChecked()
        for __, action in ipairs(available) do
            if not slot_set[action.id] then
                return false
            end
        end
        return true
    end

    local all_checked = getAllChecked()
    table.insert(buttons, {
        {
            text = all_checked and "☑ " .. _("Deselect All") or "☐ " .. _("Select All"),
            callback = function(touchmenu_instance)
                local is_all_checked = getAllChecked()
                local current_slots = getQASlots()
                local new_slots = {}

                if is_all_checked then
                    for __, id in ipairs(current_slots) do
                        local is_available = false
                        for __, action in ipairs(available) do
                            if action.id == id then
                                is_available = true
                                break
                            end
                        end
                        if not is_available then
                            table.insert(new_slots, id)
                        end
                    end
                else
                    for __, id in ipairs(current_slots) do
                        table.insert(new_slots, id)
                    end
                    for __, action in ipairs(available) do
                        if not slot_set[action.id] then
                            if #new_slots >= 66 then
                                UIManager:show(Notification:new{
                                    text = string.format(_("Max %d buttons"), 66),
                                    timeout = 2,
                                })
                                return
                            end
                            table.insert(new_slots, action.id)
                        end
                    end
                end

                saveQASlots(new_slots)
                if touchmenu_instance then
                    touchmenu_instance:updateItems()
                end
                if touch_menu then
                    touch_menu:updateItems()
                end
                closeSettingsDialog()
                QA.showAddButtonMenu(touch_menu, on_back)
            end,
        }
    })

    table.insert(buttons, {})

    for i = 1, #available do
        local action = available[i]
        local is_checked = slot_set[action.id] or false
        local symbol = getActionSymbol(action.id)
        local check_mark = is_checked and "✓ " or "  "
        local view_tag = " [" .. (action.view or "common") .. "]"
        local display_text = check_mark .. symbol .. action.label .. view_tag

        table.insert(buttons, {
            {
                text = display_text,
                callback = function(touchmenu_instance)
                    local current_slots = getQASlots()
                    local found = false
                    for j = 1, #current_slots do
                        if current_slots[j] == action.id then
                            found = true
                            break
                        end
                    end
                    if found then
                        local new_slots = {}
                        for j = 1, #current_slots do
                            if current_slots[j] ~= action.id then
                                new_slots[#new_slots + 1] = current_slots[j]
                            end
                        end
                        saveQASlots(new_slots)
                    else
                        if #current_slots >= 66 then
                            UIManager:show(Notification:new{
                                text = string.format(_("Max %d buttons"), 66),
                                timeout = 2,
                            })
                            return
                        end
                        current_slots[#current_slots + 1] = action.id
                        saveQASlots(current_slots)
                    end
                    if touchmenu_instance then
                        touchmenu_instance:updateItems()
                    end
                    if touch_menu then
                        touch_menu:updateItems()
                    end
                    closeSettingsDialog()
                    QA.showAddButtonMenu(touch_menu, on_back)
                end,
            }
        })
    end

    table.insert(buttons, {})
    table.insert(buttons, {
        { text = _("Close"), callback = function()
            if _add_button_dialog then
                 UIManager:close(_add_button_dialog)
                  _add_button_dialog = nil
            end
            closeSettingsDialog()
        end }
    })

    local dialog = ButtonDialog:new{
        title = _("Add Button"),
        title_align = "center",
        buttons = buttons,
        width = math.floor(Screen:getWidth() * 0.7),
        max_height = math.floor(Screen:getHeight() * 0.7),
    }
    if _add_button_dialog then
        UIManager:close(_add_button_dialog)
        _add_button_dialog = nil
    end
    _add_button_dialog = dialog
    UIManager:show(dialog)
end

-- ============================================================
-- Get Custom Items (Built-in + Custom)
-- ============================================================

local function getCustomItems(touch_menu)
    local items = {}

    if actions.ACTION_ORDER then
        for i = 1, #actions.ACTION_ORDER do
            local id = actions.ACTION_ORDER[i]
            if id then
                local label = getLabelForAction(id)
                local view_tag = " [" .. getActionViewFinal(id) .. "]"
                local symbol = getActionSymbol(id)
                items[#items + 1] = {
                    id = id,
                    text = symbol .. label .. view_tag,
                    is_builtin = true,
                    on_edit = function()
                        QA.showEditActionDialog(id, function()
                            QA.refreshQuickPanel()
                        end)
                    end,
                    on_delete = nil,
                }
            end
        end
    end

    local custom_list = getCustomList()
    for i = 1, #custom_list do
        local id = custom_list[i]
        local cfg = getCustom()[id]
        if cfg then
            local symbol = getActionSymbol(id)
            local view_tag = " [" .. getActionViewFinal(id) .. "]"
            items[#items + 1] = {
                id = id,
                text = symbol .. cfg.label .. view_tag,
                is_builtin = false,
                on_edit = function()
                    QA.showCustomQADialog(id, function()
                        QA.refreshQuickPanel()
                    end)
                end,
                on_delete = function()
                    local custom_tbl = getCustom()
                    custom_tbl[id] = nil
                    setCustom(custom_tbl)
                    local list = getCustomList()
                    local new_list = {}
                    for __, lid in ipairs(list) do
                        if lid ~= id then
                            table.insert(new_list, lid)
                        end
                    end
                    setCustomList(new_list)
                    QA.refreshQuickPanel()
                end,
            }
        end
    end

    return items
end

-- ============================================================
-- Quick Actions Submenu
-- ============================================================

function QA.getQuickActionsSubmenu()
    local items = {}

    local auto_add = getBool("qa_common_auto_add_to_panel")
    items[#items + 1] = {
        text = _("Auto-add to panel on save"),
        checked_func = function()
            return getBool("qa_common_auto_add_to_panel")
        end,
        callback = function(touchmenu_instance)
            setBool("qa_common_auto_add_to_panel", not getBool("qa_common_auto_add_to_panel"))
            if touchmenu_instance then
                touchmenu_instance:updateItems()
            end
            QA.refreshQuickPanel()
        end,
    }

    items[#items + 1] = {
        text = "+ " .. _("New"),
        close_on_click = {"_active_dialog"},
        callback = function()
            QA.showCustomQADialog(nil, function()
                QA.refreshQuickPanel()
            end)
        end,
    }

    local builtin_items = {}
    for __, item in ipairs(getCustomItems()) do
        if item.is_builtin then
            table.insert(builtin_items, {
                text = item.text,
                close_on_click = {"_active_dialog"},
                callback = function()
                    item.on_edit()
                end,
            })
        end
    end
    if #builtin_items > 0 then
        table.insert(items, {
            text = _("Built-in Actions"),
            sub_item_table = builtin_items,
        })
    end

    for __, item in ipairs(getCustomItems()) do
        if not item.is_builtin then
            table.insert(items, {
                text = item.text,
                close_on_click = {"_active_dialog"},
                callback = function()
                    item.on_edit()
                end,
            })
        end
    end

    return items
end

-- ============================================================
-- Panel Menu Items
-- ============================================================

function QA.getPanelMenuItems()
    local items = {}

    items[#items + 1] = {
        text = _("Tab Icon") .. ": " .. getString("qa_common_tab_icon", "star.empty"),
        close_on_click = true,
        callback = function()
            closeSettingsDialog()
            icon_picker.showIconPicker(
                function(file_path)
                    if file_path then
                        local filename_with_ext = file_path:match("([^/]+)$")
                        local filename = filename_with_ext:gsub("%.[^%.]+$", "")
                        setString("qa_common_tab_icon", filename)
                        UIManager:show(ConfirmBox:new{
                            text = _("Restart required.\n\nRestart KOReader now?"),
                            ok_text = _("Restart"),
                            cancel_text = _("Later"),
                            ok_callback = function()
                                UIManager:restartKOReader()
                            end,
                        })
                    end
                end,
                nil,
                "file"
            )
        end,
    }

    items[#items + 1] = {
        text = _("Arrange Buttons"),
        close_on_click = true,
        callback = function()
            local slots = getQASlots()
            local sort_items = {}
            for i, id in ipairs(slots) do
                sort_items[#sort_items + 1] = { text = getLabelForAction(id), orig_item = id }
            end
            local sort_dialog = SortWidget:new{
                title = _("Arrange Buttons"),
                item_table = sort_items,
                covers_fullscreen = true,
                callback = function()
                    local new_slots = {}
                    for j = 1, #sort_items do
                        new_slots[#new_slots + 1] = sort_items[j].orig_item
                    end
                    saveQASlots(new_slots)
                    QA.refreshQuickPanel()
                end,
            }
            UIManager:show(sort_dialog)
        end,
    }

    items[#items + 1] = {
        text = _("Add Button"),
        close_on_click = true, 
        callback = function()
                QA.showAddButtonMenu(nil, function()
                QA.showPanelSettings() 
            end)
        end,
    }

    items[#items + 1] = {
        text = _("Button Shape"),
        sub_item_table = {
            {
                text = _("Round"),
                radio = true,
                checked_func = function()
                    return getString("qa_panel_shape", "round") == "round"
                end,
                callback = function(touchmenu_instance)
                    setString("qa_panel_shape", "round")
                    if touchmenu_instance then
                        touchmenu_instance:updateItems()
                    end
                    QA.refreshQuickPanel()
                end,
            },
            {
                text = _("Rounded Square"),
                radio = true,
                checked_func = function()
                    return getString("qa_panel_shape", "round") == "square_round"
                end,
                callback = function(touchmenu_instance)
                    setString("qa_panel_shape", "square_round")
                    if touchmenu_instance then
                        touchmenu_instance:updateItems()
                    end
                    QA.refreshQuickPanel()
                end,
            },
            {
                text = _("Bare"),
                radio = true,
                checked_func = function()
                    return getString("qa_panel_shape", "round") == "bare"
                end,
                callback = function(touchmenu_instance)
                    setString("qa_panel_shape", "bare")
                    if touchmenu_instance then
                        touchmenu_instance:updateItems()
                    end
                    QA.refreshQuickPanel()
                end,
            },
        },
    }

    items[#items + 1] = {
        text = _("Button Background"),
        enabled = function()
            return getString("qa_panel_shape", "round") ~= "bare"
        end,
        sub_item_table = {
            {
                text = _("Transparent"),
                radio = true,
                checked_func = function()
                    return getString("qa_panel_bg", "flat") == "transparent"
                end,
                callback = function(touchmenu_instance)
                    setString("qa_panel_bg", "transparent")
                    if touchmenu_instance then
                        touchmenu_instance:updateItems()
                    end
                    QA.refreshQuickPanel()
                end,
            },
            {
                text = _("Solid"),
                radio = true,
                checked_func = function()
                    return getString("qa_panel_bg", "flat") == "solid"
                end,
                callback = function(touchmenu_instance)
                    setString("qa_panel_bg", "solid")
                    if touchmenu_instance then
                        touchmenu_instance:updateItems()
                    end
                    QA.refreshQuickPanel()
                end,
            },
            {
                text = _("Light Gray"),
                radio = true,
                checked_func = function()
                    return getString("qa_panel_bg", "flat") == "flat"
                end,
                callback = function(touchmenu_instance)
                    setString("qa_panel_bg", "flat")
                    if touchmenu_instance then
                        touchmenu_instance:updateItems()
                    end
                    QA.refreshQuickPanel()
                end,
            },
        },
    }

    items[#items + 1] = {
        text = _("Show Labels"),
        checked_func = function()
            return getBool("qa_panel_labels", false)
        end,
        callback = function(touchmenu_instance)
            setBool("qa_panel_labels", not getBool("qa_panel_labels", false))
            if touchmenu_instance then
                touchmenu_instance:updateItems()
            end
            QA.refreshQuickPanel()
        end,
    }

    items[#items + 1] = {
        text_func = function()
            return _("Button Size") .. ": " .. getNumber("qa_panel_button_size_pct", 100) .. "%"
        end,
        close_on_click = true,
        callback = function(touchmenu_instance)
            closeSettingsDialog()
            local spin = SpinWidget:new{
                title_text = _("Button Size"),
                value = getNumber("qa_panel_button_size_pct", 100),
                value_min = 60,
                value_max = 150,
                value_step = 5,
                unit = "%",
                callback = function(spin)
                    setNumber("qa_panel_button_size_pct", spin.value)
                    if touchmenu_instance then
                        touchmenu_instance:updateItems()
                    end
                    QA.refreshQuickPanel()
                    QA.showPanelSettings() 
                end,
            }
            _spin_dialog = spin
            UIManager:show(spin)
        end,
    }

    items[#items + 1] = {
        text_func = function()
            return _("Label Size") .. ": " .. getNumber("qa_panel_label_scale_pct", 90) .. "%"
        end,
        close_on_click = true,
        callback = function(touchmenu_instance)
            closeSettingsDialog()
            local spin = SpinWidget:new{
                title_text = _("Label Size"),
                value = getNumber("qa_panel_label_scale_pct", 90),
                value_min = 50,
                value_max = 200,
                value_step = 10,
                unit = "%",
                callback = function(spin)
                    setNumber("qa_panel_label_scale_pct", spin.value)
                    if touchmenu_instance then
                        touchmenu_instance:updateItems()
                    end
                    QA.refreshQuickPanel()
                    QA.showPanelSettings() 
                end,
            }
            _spin_dialog = spin
            UIManager:show(spin)
        end,
    }

    items[#items + 1] = {
        text = _("Long-press button to edit"),
        checked_func = function()
            return getBool("qa_panel_button_hold_edit", true)
        end,
        callback = function(touchmenu_instance)
            setBool("qa_panel_button_hold_edit", not getBool("qa_panel_button_hold_edit", true))
            if touchmenu_instance then
                touchmenu_instance:updateItems()
            end
            QA.refreshQuickPanel()
        end,
    }

    items[#items + 1] = {
        text = _("Long-press tab to open settings"),
        checked_func = function()
            return getBool("qa_panel_settings_on_hold", true)
        end,
        callback = function(touchmenu_instance)
            setBool("qa_panel_settings_on_hold", not getBool("qa_panel_settings_on_hold", true))
            if touchmenu_instance then
                touchmenu_instance:updateItems()
            end
            QA.refreshQuickPanel()
        end,
    }

    return items
end

-- ============================================================
-- Bottom Bar Settings
-- ============================================================

function QA.getBottomBarMenuItems()
    local bb = PLUGIN_STORE.bottombar
    if not bb then
        return {
            {
                text = _("Bottom Bar module not available (enable it first)"),
                enabled = false,
            }
        }
    end

    local items = {}

    -- ============================================================
    -- Top 3 settings
    -- ============================================================

    -- 1. Show in Reader
    items[#items + 1] = {
        text = _("Show in Reader"),
        checked_func = function()
            return getBool("qa_bb_reader_enabled", true)
        end,
        callback = function(touchmenu_instance)
            setBool("qa_bb_reader_enabled", not getBool("qa_bb_reader_enabled", true))
            if touchmenu_instance then
                touchmenu_instance:updateItems()
            end
            bb.refresh()
        end,
    }

    -- 2. Long press to edit
    items[#items + 1] = {
        text = _("Long press to edit"),
        checked_func = function()
            return getBool("qa_bb_button_hold_edit", true)
        end,
        callback = function(touchmenu_instance)
            setBool("qa_bb_button_hold_edit", not getBool("qa_bb_button_hold_edit", true))
            if touchmenu_instance then
                touchmenu_instance:updateItems()
            end
        end,
    }

    -- 3. Long press to open settings
    items[#items + 1] = {
        text = _("Long press to open settings"),
        checked_func = function()
            return getBool("qa_bb_settings_on_hold", true)
        end,
        callback = function(touchmenu_instance)
            setBool("qa_bb_settings_on_hold", not getBool("qa_bb_settings_on_hold", true))
            if touchmenu_instance then
                touchmenu_instance:updateItems()
            end
        end,
    }

    -- ============================================================
    -- Remaining settings
    -- ============================================================

    items[#items + 1] = {
        text = _("Bar Style"),
        sub_item_table = {
            {
                text = _("Default"),
                radio = true,
                checked_func = function()
                    return getString("qa_bb_style", "default") == "default"
                end,
                callback = function(touchmenu_instance)
                    setString("qa_bb_style", "default")
                    if touchmenu_instance then
                        touchmenu_instance:updateItems()
                    end
                    bb.refresh()
                end,
            },
            {
                text = _("Framed"),
                radio = true,
                checked_func = function()
                    return getString("qa_bb_style", "default") == "framed"
                end,
                callback = function(touchmenu_instance)
                    setString("qa_bb_style", "framed")
                    if touchmenu_instance then
                        touchmenu_instance:updateItems()
                    end
                    bb.refresh()
                end,
            },
            {
                text = _("Bare"),
                radio = true,
                checked_func = function()
                    return getString("qa_bb_style", "default") == "bare"
                end,
                callback = function(touchmenu_instance)
                    setString("qa_bb_style", "bare")
                    if touchmenu_instance then
                        touchmenu_instance:updateItems()
                    end
                    bb.refresh()
                end,
            },
        },
    }

    items[#items + 1] = {
        text = _("Bar Background"),
        sub_item_table = {
            {
                text = _("Transparent"),
                radio = true,
                checked_func = function()
                    return getBool("qa_bb_transparent", false) == true
                end,
                callback = function(touchmenu_instance)
                    setBool("qa_bb_transparent", true)
                    if touchmenu_instance then
                        touchmenu_instance:updateItems()
                    end
                    bb.refresh()
                end,
            },
            {
                text = _("Solid"),
                radio = true,
                checked_func = function()
                    return getBool("qa_bb_transparent", false) == false
                end,
                callback = function(touchmenu_instance)
                    setBool("qa_bb_transparent", false)
                    if touchmenu_instance then
                        touchmenu_instance:updateItems()
                    end
                    bb.refresh()
                end,
            },
        },
    }

    items[#items + 1] = {
        text = _("Arrange Tabs"),
        close_on_click = true,
        callback = function()
            if not bb or not bb.getTabs then
                UIManager:show(InfoMessage:new{
                    text = _("Bottom Bar module not fully loaded"),
                    timeout = 2,
                })
                return
            end
            local tabs = bb.getTabs()
            if not tabs or #tabs == 0 then
                UIManager:show(InfoMessage:new{
                    text = _("No tabs configured"),
                    timeout = 2,
                })
                return
            end
            local sort_items = {}
            for i, id in ipairs(tabs) do
                sort_items[#sort_items + 1] = { text = getLabelForAction(id), orig_item = id }
            end
            local sort_dialog = SortWidget:new{
                title = _("Arrange Tabs"),
                item_table = sort_items,
                covers_fullscreen = true,
                callback = function()
                    local new_tabs = {}
                    for j = 1, #sort_items do
                        new_tabs[#new_tabs + 1] = sort_items[j].orig_item
                    end
                    setTable("qa_bb_tabs", new_tabs)
                    if bb then bb.refresh() end
                end,
            }
            UIManager:show(sort_dialog)
        end,
    }

    items[#items + 1] = {
        text = _("Add Tab"),
        close_on_click = true,
        callback = function()
            if not bb or not bb.showAddTabMenu then
                UIManager:show(InfoMessage:new{
                    text = _("Bottom Bar module not fully loaded"),
                    timeout = 2,
                })
                return
            end
            bb.showAddTabMenu(function() 
                QA.showBottombarSettings()
            end)
        end,
    }

    items[#items + 1] = {
        text = _("Show Labels"),
        checked_func = function()
            return getBool("qa_bb_labels", false)
        end,
        callback = function(touchmenu_instance)
            setBool("qa_bb_labels", not getBool("qa_bb_labels", false))
            if touchmenu_instance then
                touchmenu_instance:updateItems()
            end
            bb.refresh()
        end,
    }

    items[#items + 1] = {
        text_func = function()
            return _("Bar Size") .. ": " .. getNumber("qa_bb_size_pct", 100) .. "%"
        end,
        close_on_click = true,
        callback = function(touchmenu_instance)
            closeSettingsDialog()
            local spin = SpinWidget:new{
                title_text = _("Bar Size"),
                value = getNumber("qa_bb_size_pct", 100),
                value_min = 50,
                value_max = 150,
                value_step = 10,
                unit = "%",
                callback = function(spin)
                    setNumber("qa_bb_size_pct", spin.value)
                    if touchmenu_instance then
                        touchmenu_instance:updateItems()
                    end
                    bb.refresh()
                    QA.showBottombarSettings()
                end,
            }
            _spin_dialog = spin
            UIManager:show(spin)
        end,
    }

    items[#items + 1] = {
        text_func = function()
            return _("Icon Size") .. ": " .. getNumber("qa_bb_icon_scale_pct", 100) .. "%"
        end,
        close_on_click = true,
        callback = function(touchmenu_instance)
            closeSettingsDialog()
            local spin = SpinWidget:new{
                title_text = _("Icon Size"),
                value = getNumber("qa_bb_icon_scale_pct", 100),
                value_min = 50,
                value_max = 200,
                value_step = 10,
                unit = "%",
                callback = function(spin)
                    setNumber("qa_bb_icon_scale_pct", spin.value)
                    if touchmenu_instance then
                        touchmenu_instance:updateItems()
                    end
                    bb.refresh()
                    QA.showBottombarSettings()
                end,
            }
            _spin_dialog = spin
            UIManager:show(spin)
        end,
    }

    items[#items + 1] = {
        text_func = function()
            return _("Label Size") .. ": " .. getNumber("qa_bb_label_scale_pct", 100) .. "%"
        end,
        close_on_click = true,
        callback = function(touchmenu_instance)
            closeSettingsDialog()
            local spin = SpinWidget:new{
                title_text = _("Label Size"),
                value = getNumber("qa_bb_label_scale_pct", 100),
                value_min = 50,
                value_max = 200,
                value_step = 10,
                unit = "%",
                callback = function(spin)
                    setNumber("qa_bb_label_scale_pct", spin.value)
                    if touchmenu_instance then
                        touchmenu_instance:updateItems()
                    end
                    bb.refresh()
                    QA.showBottombarSettings()
                end,
            }
            _spin_dialog = spin
            UIManager:show(spin)
        end,
    }

    return items
end

-- ============================================================
-- Interface Filter
-- ============================================================
function QA.getInterfaceFilterMenuItems()
    local function buildDedicatedListItems(mode)
        local target_view = (mode == "fm") and "filemanager" or "reader"
        local items = {}
        local all_actions = actions.getAllAvailableActions()

        table.sort(all_actions, function(a, b)
            local a_checked = (a.view == target_view)
            local b_checked = (b.view == target_view)
            if a_checked ~= b_checked then
                return a_checked
            end
            local a_is_common = (a.view == "common")
            local b_is_common = (b.view == "common")
            if a_is_common ~= b_is_common then
                return a_is_common
            end
            local a_prio = actions.getTypePriority(a.id)
            local b_prio = actions.getTypePriority(b.id)
            if a_prio ~= b_prio then
                return a_prio < b_prio
            end
            return a.label:lower() < b.label:lower()
        end)

        table.insert(items, {
            text = _("Select All Dedicated"),
            checked_func = function()
                local current_actions = actions.getAllAvailableActions()
                for __, action in ipairs(current_actions) do
                    if action.id and not (getCustom()[action.id] and getCustom()[action.id].action_type == "menu") then
                        if action.view ~= target_view then
                            return false
                        end
                    end
                end
                return true
            end,
            enabled = function()
                local current_actions = actions.getAllAvailableActions()
                for __, action in ipairs(current_actions) do
                    if action.id and not (getCustom()[action.id] and getCustom()[action.id].action_type == "menu") then
                        return true
                    end
                end
                return false
            end,
            callback = function(touchmenu_instance)
                local current_actions = actions.getAllAvailableActions()
                local all_checked = true
                for __, action in ipairs(current_actions) do
                    if action.id and not (getCustom()[action.id] and getCustom()[action.id].action_type == "menu") then
                        if action.view ~= target_view then
                            all_checked = false
                            break
                        end
                    end
                end

                for __, action in ipairs(current_actions) do
                    if not action.id then goto continue end
                    if getCustom()[action.id] and getCustom()[action.id].action_type == "menu" then
                        goto continue
                    end
                    local current = actions.getActionViewFinal(action.id)
                    if all_checked then
                        if current == target_view then
                            actions.toggleDedicated(action.id, target_view)
                        end
                    else
                        if current ~= target_view then
                            actions.toggleDedicated(action.id, target_view)
                        end
                    end
                    ::continue::
                end
                if touchmenu_instance then
                    touchmenu_instance:updateItems()
                end
            end,
        })

                for __, action in ipairs(all_actions) do
                    if not action.id then goto continue end
                    local is_locked = (getCustom()[action.id] and getCustom()[action.id].action_type == "menu")
                    local action_id = action.id
                    table.insert(items, {
                        text_func = function()
                            local symbol = actions.getActionSymbol(action_id)
                            local label = actions.getLabelForAction(action_id)
                            local view_tag = " [" .. actions.getActionViewFinal(action_id) .. "]"
                            return symbol .. label .. view_tag
                        end,
                        checked_func = function()
                            return actions.getActionViewFinal(action_id) == target_view
                        end,
                        enabled = not is_locked,
                        close_on_click = false,
                        callback = function(touchmenu_instance)
                            if is_locked then return end
                            actions.toggleDedicated(action_id, target_view)
                            if touchmenu_instance then
                                touchmenu_instance:updateItems()
                            end
                        end,
                    })
                    ::continue::
                end

        return items
    end

    return {
        {
            text = _("Enable Interface Filter"),
            checked_func = function()
                return getBool("qa_common_context_filter")
            end,
            callback = function(touchmenu_instance)
                local p = getPlugin()
                if p then
                    _G.__QUICKUI_CONFIG.qa_common_context_filter = not getBool("qa_common_context_filter")
                    Utils.saveConfig()
                    if touchmenu_instance then
                        touchmenu_instance:updateItems()
                    end
                end
            end,
        },
        {
            text_func = function()
                local actions_list = actions.getAllAvailableActions()
                local fm = 0
                for __, act in ipairs(actions_list) do
                    if act.view == "filemanager" then
                        fm = fm + 1
                    end
                end
                return string.format(_("Filemanager Dedicated (%d)"), fm)
            end,
            sub_item_table = buildDedicatedListItems("fm"),
        },
        {
            text_func = function()
                local actions_list = actions.getAllAvailableActions()
                local rd = 0
                for __, act in ipairs(actions_list) do
                    if act.view == "reader" then
                        rd = rd + 1
                    end
                end
                return string.format(_("Reader Dedicated (%d)"), rd)
            end,
            sub_item_table = buildDedicatedListItems("reader"),
        },
        {
            text = _("Reset to Defaults"),
            callback = function(touchmenu_instance)
                UIManager:show(ConfirmBox:new{
                    text = _("Reset all dedicated view settings to defaults?"),
                    ok_text = _("Reset"),
                    cancel_text = _("Cancel"),
                    ok_callback = function()
                        local p = getPlugin()
                        if p then
                            _G.__QUICKUI_CONFIG.qa_common_builtin_overrides = {}
                            local custom = _G.__QUICKUI_CONFIG.qa_common_custom or {}
                            for id, cfg in pairs(custom) do
                                if cfg.action_type == "menu" then
                                    cfg.view = cfg.menu_path.view or cfg.view
                                else
                                    cfg.view = "common"
                                end
                            end
                            _G.__QUICKUI_CONFIG.qa_common_custom = custom
                            Utils.saveConfig()
                            if touchmenu_instance then
                                touchmenu_instance:updateItems()
                            end
                            UIManager:show(Notification:new{
                                text = _("Reset to defaults"),
                                timeout = 2,
                            })
                        end
                    end,
                })
            end,
        },
    }
end

-- ============================================================
-- Main Settings Menu
-- ============================================================

-- Build the full QA settings menu items (used by showSettings and as parent for sub-settings)
function QA.buildRootMenuItems()
    local items = {}

    table.insert(items, {
        text = _("Enable Panel"),
        checked_func = function()
            return getBool("qa_panel_enabled")
        end,
        callback = function()
            local new_val = not getBool("qa_panel_enabled")
            setBool("qa_panel_enabled", new_val)
            local fm = require("apps/filemanager/filemanager").instance
            if fm and fm.menu and fm.menu.menu_container and fm.menu.menu_container[1] then
                fm.menu.menu_container[1]:updateItems()
            end
            local readerui = require("apps/reader/readerui").instance
            if readerui and readerui.menu and readerui.menu.menu_container and readerui.menu.menu_container[1] then
                readerui.menu.menu_container[1]:updateItems()
            end
            UIManager:show(ConfirmBox:new{
                text = _("Restart required.\n\nRestart KOReader now?"),
                ok_text = _("Restart"),
                cancel_text = _("Later"),
                ok_callback = function()
                    UIManager:restartKOReader()
                end,
            })
        end,
    })

    table.insert(items, {
        text = _("Enable Bottom Bar"),
        checked_func = function()
            return getBool("qa_bb_enabled")
        end,
        callback = function()
            local new_val = not getBool("qa_bb_enabled")
            setBool("qa_bb_enabled", new_val)
            local bb = PLUGIN_STORE.bottombar
            if bb then
                bb.refresh()
            end
            local fm = require("apps/filemanager/filemanager").instance
            if fm and fm.menu and fm.menu.menu_container and fm.menu.menu_container[1] then
                fm.menu.menu_container[1]:updateItems()
            end
            local readerui = require("apps/reader/readerui").instance
            if readerui and readerui.menu and readerui.menu.menu_container and readerui.menu.menu_container[1] then
                readerui.menu.menu_container[1]:updateItems()
            end
            UIManager:show(ConfirmBox:new{
                text = _("Restart required.\n\nRestart KOReader now?"),
                ok_text = _("Restart"),
                cancel_text = _("Later"),
                ok_callback = function()
                    UIManager:restartKOReader()
                end,
            })
        end,
    })

    table.insert(items, {
        text = _("System Icon Override"),
        close_on_click = true,
        callback = function()
            closeSettingsDialog()
            icon_picker.showIconPicker(nil, nil, nil, "system")
        end,
    })

    table.insert(items, {
        text = _("UI Font Switcher"),
        close_on_click = true,
        callback = function()
            closeSettingsDialog()
            uifont.showUIFontSwitcher()
        end,
    })

    table.insert(items, {
        text = _("Quick Actions"),
        sub_item_table = QA.getQuickActionsSubmenu(),
    })

    local filter_items = QA.getInterfaceFilterMenuItems()
    if filter_items and #filter_items > 0 then
        table.insert(items, {
            text = _("Interface Filter"),
            sub_item_table = filter_items,
        })
    end

    table.insert(items, {
        text = _("Panel"),
        sub_item_table = QA.getPanelMenuItems(),
    })

    table.insert(items, {
        text = _("Bottom Bar"),
        sub_item_table = QA.getBottomBarMenuItems(),
    })

    local default_items = Utils.buildDefaultMenuItems({"qa_common", "qa_panel", "qa_bb"}, function()
        QA.refreshQuickPanel()
        local bb = PLUGIN_STORE.bottombar
        if bb then bb.refresh() end
    end)
    for __, item in ipairs(default_items) do
        table.insert(items, item)
    end

    return items
end

-- Show full QA settings
function QA.showSettings()
    closeSettingsDialog()
    local root_items = QA.buildRootMenuItems()
    _root_items = root_items
    showMenu(root_items, _("Quick Actions Settings"), nil, nil, root_items)
end

-- Show only Panel settings, with full QA settings as parent
function QA.showPanelSettings()
    closeSettingsDialog()
    local panel_items = QA.getPanelMenuItems()
    local root_items = QA.buildRootMenuItems()
    _root_items = root_items

    local parent_stack = {{
        items = root_items,
        title = _("Quick Actions Settings"),
        parent_stack = nil,
    }}

    showMenu(panel_items, _("Panel Settings"), parent_stack, nil, root_items)
end

-- Show only Bottom Bar settings, with full QA settings as parent
function QA.showBottombarSettings()
    closeSettingsDialog()
    local bb = PLUGIN_STORE.bottombar
    if not bb then
        UIManager:show(InfoMessage:new{
            text = _("Bottom Bar module not available"),
            timeout = 2,
        })
        return
    end
    local bb_items = QA.getBottomBarMenuItems()
    local root_items = QA.buildRootMenuItems()
    _root_items = root_items

    local parent_stack = {{
        items = root_items,
        title = _("Quick Actions Settings"),
        parent_stack = nil,
    }}

    showMenu(bb_items, _("Bottom Bar Settings"), parent_stack, nil, root_items)
end

function QA.getMenuItems()
    return {}
end

QA.showMenu = showMenu

-- ============================================================
-- Show Interface Filter directly
-- ============================================================
function QA.showInterfaceFilter()
    closeSettingsDialog()
    local root_items = QA.buildRootMenuItems()
    local filter_item = nil
    for __, item in ipairs(root_items) do
        if item.text == _("Interface Filter") then
            filter_item = item
            break
        end
    end
    if filter_item and filter_item.sub_item_table then
        showMenu(filter_item.sub_item_table, _("Interface Filter"), nil, nil, root_items)
    else
        UIManager:show(InfoMessage:new{
            text = _("Interface Filter not available"),
            timeout = 2,
        })
    end
end

return QA
