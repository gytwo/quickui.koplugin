--[[
QuickUI - Quick Actions Registry

Registers all built-in actions (WiFi, night mode, screenshot, etc.)
and provides action execution, lookup, and management functions.

Original: 2-quickactions.lua (action registration and execution)
]]

local logger = require("logger")
local _ = require("gettext")
local Blitbuffer = require("ffi/blitbuffer")
local Screen = require("device").screen
local Device = require("device")
local UIManager = require("ui/uimanager")
local Event = require("ui/event")
local Dispatcher = require("dispatcher")
local BD = require("ui/bidi")
local T = require("ffi/util").template
local util = require("util")

local InfoMessage = require("ui/widget/infomessage")
local Notification = require("ui/widget/notification")
local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local InputDialog = require("ui/widget/inputdialog")
local SpinWidget = require("ui/widget/spinwidget")
local SortWidget = require("ui/widget/sortwidget")

local Utils = require("qui_utils")
local icon_picker = require("qui_actions/qa_icon_picker")
local settings_icon = icon_picker.nerdIconChar("nerd:E73A") or "⚙️"

local QA = {}
QA._registered = false

QA.nerdIconChar = icon_picker.nerdIconChar

-- ============================================================
-- Constants
-- ============================================================

local MAX_SLOTS = 66
local EXCLUDED_PLUGINS = { zen_ui = true }

-- ============================================================
-- Action Registry
-- ============================================================

local ACTION_REGISTRY = {}
local ACTION_ORDER = {}
local _wifi_optimistic = nil

-- ============================================================
-- Configuration - Read from _G.__QUICKUI_CONFIG
-- ============================================================

local function getBool(key)
    local config = _G.__QUICKUI_CONFIG
    if config and config[key] ~= nil then
        return config[key] == true
    end
    return false
end

local function getString(key)
    local config = _G.__QUICKUI_CONFIG
    if config and config[key] ~= nil then
        return config[key]
    end
    return ""
end

local function getTable(key)
    local config = _G.__QUICKUI_CONFIG
    if config and config[key] ~= nil then
        return config[key]
    end
    return {}
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

-- ============================================================
-- Network Manager Helper
-- ============================================================

local function getNetworkMgr()
    local ok, nm = pcall(require, "ui/network/manager")
    return ok and nm or nil
end

-- ============================================================
-- Action Registration
-- ============================================================

function QA.registerAction(id, label, icon, is_in_place, view, execute_fn)
    ACTION_REGISTRY[id] = {
        label = label,
        icon = icon,
        is_in_place = is_in_place,
        view = view or "common",
        execute = execute_fn,
    }
    ACTION_ORDER[#ACTION_ORDER + 1] = id
end

-- ============================================================
-- Get Default View for Action Type
-- ============================================================

local function getDefaultViewForActionType(action_type, action_value)
    if action_type == "folder" or action_type == "collections" then
        return "filemanager"
    elseif action_type == "plugin" then
        return "common"
    elseif action_type == "dispatcher" then
        if not action_value then return "common" end
        local ok, DispatcherMod = pcall(require, "dispatcher")
        if ok and DispatcherMod then
            local settingsList
            local fn_idx = 1
            while true do
                local name, val = debug.getupvalue(DispatcherMod.registerAction, fn_idx)
                if not name then break end
                if name == "settingsList" then settingsList = val end
                fn_idx = fn_idx + 1
            end
            local def = settingsList and settingsList[action_value]
            if def then
                if def.filemanager then return "filemanager" end
                if def.reader or def.rolling or def.paging then return "reader" end
            end
        end
        return "common"
    elseif action_type == "menu" then
        if not action_value or type(action_value) ~= "table" then return "common" end
        return action_value.view or "common"
    end
    return "common"
end

QA.getDefaultViewForActionType = getDefaultViewForActionType

-- ============================================================
-- Get Action
-- ============================================================

function QA.getAction(id)
    local builtin_overrides = getBuiltinOverrides()
    if builtin_overrides[id] then
        return {
            label = builtin_overrides[id].label or (ACTION_REGISTRY[id] and ACTION_REGISTRY[id].label) or id,
            icon = builtin_overrides[id].icon or (ACTION_REGISTRY[id] and ACTION_REGISTRY[id].icon),
            is_in_place = ACTION_REGISTRY[id] and ACTION_REGISTRY[id].is_in_place or false,
            view = builtin_overrides[id].view or (ACTION_REGISTRY[id] and ACTION_REGISTRY[id].view) or "common",
            execute = ACTION_REGISTRY[id] and ACTION_REGISTRY[id].execute,
        }
    end

    if ACTION_REGISTRY[id] then
        local action = ACTION_REGISTRY[id]
        return {
            label = action.label,
            icon = action.icon,
            is_in_place = action.is_in_place,
            view = action.view or "common",
            execute = action.execute,
        }
    end

    local custom = getCustom()
    local cfg = custom[id]
    if type(cfg) == "table" and cfg.label then
        local view = cfg.view
        if not view then
            if cfg.action_type == "menu" and cfg.menu_path and cfg.menu_path.view then
                view = cfg.menu_path.view
            else
                view = getDefaultViewForActionType(cfg.action_type, cfg.action_value or cfg.dispatcher_action)
            end
        end
        return {
            label = cfg.label,
            icon = cfg.icon,
            is_in_place = cfg.is_in_place or false,
            view = view,
            execute = function(ctx)
                if cfg.action_type == "folder" and cfg.action_value then
                    QA.executeFolderAction(cfg.action_value, ctx)
                elseif cfg.action_type == "collections" and cfg.action_value then
                    QA.executeCollectionsAction(cfg.action_value)
                elseif cfg.action_type == "plugin" and cfg.plugin_key then
                    local PluginScan = require("qui_actions/qa_plugin_scan")
                    PluginScan.executePlugin(cfg.plugin_key, cfg.plugin_method, ctx)
                elseif cfg.action_type == "dispatcher" and cfg.dispatcher_action then
                    QA.executeDispatcherAction(cfg.dispatcher_action, cfg.dispatcher_value or true, ctx)
                elseif cfg.action_type == "menu" and cfg.menu_path then
                    QA.executeMenuAction(cfg.menu_path, ctx)
                end
            end,
        }
    end

    return nil
end

-- ============================================================
-- Action Execution
-- ============================================================

function QA.executeAction(id, ctx)
    local action = QA.getAction(id)
    if not action or not action.execute then
        return false
    end

    local action_view = action.view or "common"
    if action_view ~= "common" then
        local current_view = "common"
        local RUI = require("apps/reader/readerui")
        local FM = require("apps/filemanager/filemanager")
        if RUI and RUI.instance and not RUI.instance.tearing_down then
            current_view = "reader"
        elseif FM and FM.instance then
            current_view = "filemanager"
        end

        if action_view ~= current_view then
            local msg
            if action_view == "reader" then
                msg = _("This action can only be executed in the reader. Please open a book first.")
            elseif action_view == "filemanager" then
                msg = _("This action can only be executed in the filemanager.")
            else
                msg = _("This action cannot be executed in the current view.")
            end
            UIManager:show(InfoMessage:new{ text = msg, timeout = 2 })
            return false
        end
    end

    action.execute(ctx or {})
    return true
end

function QA.executeDispatcherAction(action_id, action_value, ctx)
    if ctx and ctx.touch_menu and ctx.touch_menu.onClose then
        ctx.touch_menu:onClose()
    end
    local ok_disp, DispatcherMod = pcall(require, "dispatcher")
    if ok_disp and DispatcherMod then
        DispatcherMod:execute({ [action_id] = action_value })
    end
end

function QA.executeFolderAction(folder_path, ctx)
    local FM = require("apps/filemanager/filemanager")
    local fm = FM and FM.instance
    local RUI = require("apps/reader/readerui")
    local rui = RUI and RUI.instance

    if ctx and ctx.touch_menu and ctx.touch_menu.onClose then
        ctx.touch_menu:onClose()
    end

    if fm and fm.file_chooser then
        fm.file_chooser:changeToPath(folder_path)
    elseif rui then
        rui:onClose()
        FM:showFiles()
        local fm2 = FM.instance
        if fm2 and fm2.file_chooser then
            fm2.file_chooser:changeToPath(folder_path)
        end
    end
end

function QA.executeCollectionsAction(collections_name)
    local FM = require("apps/filemanager/filemanager")
    local fm = FM and FM.instance
    local RUI = require("apps/reader/readerui")
    local rui = RUI and RUI.instance

    if fm and fm.collections then
        pcall(fm.collections.onShowColl, fm.collections, collections_name)
    elseif rui then
        rui.tearing_down = true
        rui:onClose()
        FM:showFiles()
        local fm2 = FM.instance
        if fm2 and fm2.collections then
            pcall(fm2.collections.onShowColl, fm2.collections, collections_name)
        end
    end
end

function QA.executeMenuAction(menu_path, ctx)
    local FM = require("apps/filemanager/filemanager")
    local fm = FM and FM.instance
    local RUI = require("apps/reader/readerui")
    local rui = RUI and RUI.instance

    local recorded_view = menu_path.view or "common"
    local current_view = nil

    if rui and rui.instance and not rui.instance.tearing_down then
        current_view = "reader"
    elseif fm and fm.instance then
        current_view = "filemanager"
    end

    if recorded_view == "common" or recorded_view == current_view then
        local target_menu = nil
        if recorded_view == "reader" or current_view == "reader" then
            if rui and rui.menu then
                if not rui.menu.menu_container or not rui.menu.menu_container[1] then
                    rui.menu:onShowMenu()
                end
                local mc = rui.menu.menu_container
                if mc and mc[1] then
                    target_menu = mc[1]
                else
                    target_menu = rui.menu
                end
            end
        else
            if fm and fm.menu then
                if not fm.menu.menu_container or not fm.menu.menu_container[1] then
                    fm.menu:onShowMenu(menu_path.tab_index or 1)
                end
                local mc = fm.menu.menu_container
                if mc and mc[1] then
                    target_menu = mc[1]
                else
                    target_menu = fm.menu
                end
            end
        end

        if target_menu then
            local MenuRecorder = require("qui_actions/qa_menu_recorder")
            MenuRecorder.replayPath(target_menu, menu_path)
        else
            UIManager:show(InfoMessage:new{
                text = _("Unable to open menu"),
                timeout = 2,
            })
        end
    else
        local msg = (recorded_view == "reader")
            and _("This action can only be executed in the reader. Please open a book first.")
            or _("This action can only be executed in the file manager.")
        UIManager:show(InfoMessage:new{ text = msg, timeout = 3 })
    end
end

-- ============================================================
-- Action Info Lookups
-- ============================================================

function QA.isInPlace(id)
    local action = QA.getAction(id)
    return action and action.is_in_place or false
end

function QA.getLabelForAction(id)
    local builtin_overrides = getBuiltinOverrides()
    if builtin_overrides[id] and builtin_overrides[id].label then
        return builtin_overrides[id].label
    end
    local action = QA.getAction(id)
    if action then return action.label end
    return id
end

function QA.getIconForAction(id)
    if id == "wifi" then
        if _wifi_optimistic ~= nil then
            return _wifi_optimistic and "nerd:ECA8" or "nerd:ECA9"
        end
        local NetworkMgr = getNetworkMgr()
        if NetworkMgr then
            local ok, is_on = pcall(function() return NetworkMgr:isWifiOn() end)
            if ok and is_on then
                return "nerd:ECA8"
            else
                return "nerd:ECA9"
            end
        end
        return "nerd:ECA8"
    end

    if id == "toggle_cloze_mode" then
        local RUI = require("apps/reader/readerui")
        local reader = RUI and RUI.instance
        if reader and reader.highlight then
            local has_covered = false
            local annotations = reader.highlight.ui.annotation.annotations
            if annotations then
                for idx, item in ipairs(annotations) do
                    if item.drawer and reader.highlight._temp_covered and reader.highlight._temp_covered[idx] then
                        has_covered = true
                        break
                    end
                end
            end
            if has_covered then
                return "nerd:F070"
            else
                return "nerd:F06E"
            end
        end
        return "nerd:F06E"
    end

    local action = QA.getAction(id)
    if action then return action.icon end
    return nil
end

function QA.isBuiltinAction(id)
    return ACTION_REGISTRY[id] ~= nil
end

function QA.getActionViewFinal(id)
    if not id then return "common" end
    local overrides = getBuiltinOverrides()
    if overrides and overrides[id] and overrides[id].view then
        return overrides[id].view
    end
    local custom = getCustom()
    local cfg = custom and custom[id]
    if cfg then
        if cfg.action_type == "menu" and cfg.menu_path and cfg.menu_path.view then
            return cfg.menu_path.view
        end
        if cfg.view then
            return cfg.view
        end
    end
    if ACTION_REGISTRY and ACTION_REGISTRY[id] then
        return ACTION_REGISTRY[id].view or "common"
    end
    return "common"
end

function QA.getTypePriority(id)
    local cfg = getCustom()[id]
    if cfg then
        if cfg.action_type == "menu" then
            return 1
        elseif cfg.action_type == "dispatcher" then
            return 2
        elseif cfg.action_type == "plugin" then
            return 3
        elseif cfg.action_type == "folder" then
            return 4
        elseif cfg.action_type == "collections" then
            return 5
        else
            return 6
        end
    end
    if ACTION_ORDER then
        for __, builtin_id in ipairs(ACTION_ORDER) do
            if builtin_id == id then
                return 7
            end
        end
    end
    return 8
end

function QA.getActionSymbol(id)
    local is_builtin = false
    if ACTION_ORDER then
        for __, builtin_id in ipairs(ACTION_ORDER) do
            if builtin_id == id then
                is_builtin = true
                break
            end
        end
    end

    if is_builtin then
        local circle_char = QA.nerdIconChar("nerd:E002") or "○"
        return circle_char .. " "
    end

    local cfg = getCustom()[id]
    if cfg then
        if cfg.action_type == "dispatcher" then
            return "⊕ "
        elseif cfg.action_type == "plugin" then
            return "⬡ "
        elseif cfg.action_type == "collections" then
            return "⊞ "
        elseif cfg.action_type == "menu" then
            return "⊚ "
        elseif cfg.action_type == "folder" then
            return "◇ "
        else
            return "● "
        end
    end
    return "● "
end

-- ============================================================
-- View / Filter Helpers
-- ============================================================

function QA.getAllAvailableActions()
    local available = {}
    if ACTION_ORDER then
        for i = 1, #ACTION_ORDER do
            local id = ACTION_ORDER[i]
            if id then
                available[#available + 1] = {
                    id = id,
                    label = QA.getLabelForAction(id),
                    is_builtin = true,
                    view = QA.getActionViewFinal(id),
                }
            end
        end
    end
    local custom_list = getCustomList()
    if type(custom_list) == "table" then
        for i = 1, #custom_list do
            local id = custom_list[i]
            local cfg = getCustom()[id]
            if cfg then
                local view = cfg.view
                if not view then
                    if cfg.action_type == "menu" and cfg.menu_path and cfg.menu_path.view then
                        view = cfg.menu_path.view
                    else
                        view = getDefaultViewForActionType(cfg.action_type, cfg.action_value or cfg.dispatcher_action)
                    end
                end
                available[#available + 1] = {
                    id = id,
                    label = cfg.label,
                    is_builtin = false,
                    view = view,
                }
            end
        end
    end
    return available
end

function QA.isActionVisible(action_id, current_view)
    if not getBool("qa_common_context_filter") then return true end
    local view = QA.getActionViewFinal(action_id)
    if current_view == "filemanager" then
        return view == "filemanager" or view == "common"
    elseif current_view == "reader" then
        return view == "reader" or view == "common"
    end
    return true
end

function QA.toggleDedicated(action_id, target_view)
    local is_builtin = ACTION_REGISTRY and ACTION_REGISTRY[action_id] ~= nil
    local current_view = QA.getActionViewFinal(action_id)

    if current_view == target_view then
        if is_builtin then
            if not _G.__QUICKUI_CONFIG.qa_common_builtin_overrides then
                _G.__QUICKUI_CONFIG.qa_common_builtin_overrides = {}
            end
            if not _G.__QUICKUI_CONFIG.qa_common_builtin_overrides[action_id] then
                _G.__QUICKUI_CONFIG.qa_common_builtin_overrides[action_id] = {}
            end
            _G.__QUICKUI_CONFIG.qa_common_builtin_overrides[action_id].view = "common"
            setBuiltinOverrides(_G.__QUICKUI_CONFIG.qa_common_builtin_overrides)
        else
            if not _G.__QUICKUI_CONFIG.qa_common_custom then
                _G.__QUICKUI_CONFIG.qa_common_custom = {}
            end
            if _G.__QUICKUI_CONFIG.qa_common_custom[action_id] then
                _G.__QUICKUI_CONFIG.qa_common_custom[action_id].view = "common"
                setCustom(_G.__QUICKUI_CONFIG.qa_common_custom)
            end
        end
    else
        if is_builtin then
            if not _G.__QUICKUI_CONFIG.qa_common_builtin_overrides then
                _G.__QUICKUI_CONFIG.qa_common_builtin_overrides = {}
            end
            if not _G.__QUICKUI_CONFIG.qa_common_builtin_overrides[action_id] then
                _G.__QUICKUI_CONFIG.qa_common_builtin_overrides[action_id] = {}
            end
            _G.__QUICKUI_CONFIG.qa_common_builtin_overrides[action_id].view = target_view
            setBuiltinOverrides(_G.__QUICKUI_CONFIG.qa_common_builtin_overrides)
        else
            if not _G.__QUICKUI_CONFIG.qa_common_custom then
                _G.__QUICKUI_CONFIG.qa_common_custom = {}
            end
            if _G.__QUICKUI_CONFIG.qa_common_custom[action_id] then
                _G.__QUICKUI_CONFIG.qa_common_custom[action_id].view = target_view
                setCustom(_G.__QUICKUI_CONFIG.qa_common_custom)
            end
        end
    end

    Utils.saveConfig()
end

-- ============================================================
-- Interface Filter Menu
-- ============================================================

function QA.getInterfaceFilterMenuItems()
    local function buildDedicatedListItems(mode)
        local target_view = (mode == "fm") and "filemanager" or "reader"
        local items = {}
        local all_actions = QA.getAllAvailableActions()

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
            local a_prio = QA.getTypePriority(a.id)
            local b_prio = QA.getTypePriority(b.id)
            if a_prio ~= b_prio then
                return a_prio < b_prio
            end
            return a.label:lower() < b.label:lower()
        end)

        table.insert(items, {
            text_func = function()
                local current_actions = QA.getAllAvailableActions()
                local all_checked = true
                local has_unlocked = false
                for __, action in ipairs(current_actions) do
                    if action.id and not (getCustom()[action.id] and getCustom()[action.id].action_type == "menu") then
                        has_unlocked = true
                        if action.view ~= target_view then
                            all_checked = false
                            break
                        end
                    end
                end
                if not has_unlocked then
                    all_checked = true
                end
                return all_checked and "☑ " .. _("Deselect All") or "☐ " .. _("Select All Dedicated")
            end,
            enabled = function()
                local current_actions = QA.getAllAvailableActions()
                for __, action in ipairs(current_actions) do
                    if action.id and not (getCustom()[action.id] and getCustom()[action.id].action_type == "menu") then
                        return true
                    end
                end
                return false
            end,
            close_on_click = false,
            callback = function()
                local current_actions = QA.getAllAvailableActions()
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
                    local current = QA.getActionViewFinal(action.id)
                    if all_checked then
                        if current == target_view then
                            QA.toggleDedicated(action.id, target_view)
                        end
                    else
                        if current ~= target_view then
                            QA.toggleDedicated(action.id, target_view)
                        end
                    end
                    ::continue::
                end
            end,
        })

        for __action, action in ipairs(all_actions) do
            if not action.id then goto continue2 end
            local is_locked = (getCustom()[action.id] and getCustom()[action.id].action_type == "menu")
            local action_id = action.id
            table.insert(items, {
                text_func = function()
                    local is_checked = (QA.getActionViewFinal(action_id) == target_view)
                    local prefix = is_checked and "✓ " or "  "
                    local symbol = QA.getActionSymbol(action_id)
                    local view_tag = " [" .. QA.getActionViewFinal(action_id) .. "]"
                    local label = QA.getLabelForAction(action_id)
                    local display_text = prefix .. symbol .. label .. view_tag
                    if is_locked then
                        display_text = display_text .. " (" .. _("locked") .. ")"
                    end
                    return display_text
                end,
                enabled = not is_locked,
                close_on_click = false,
                callback = function()
                    if is_locked then return end
                    QA.toggleDedicated(action_id, target_view)
                end,
            })
            ::continue2::
        end

        return items
    end

    return {
        {
            text_func = function()
                local enabled = getBool("qa_common_context_filter")
                return (enabled and "✓ " or "  ") .. _("Enable Interface Filter")
            end,
            close_on_click = false,
            callback = function()
                _G.__QUICKUI_CONFIG.qa_common_context_filter = not getBool("qa_common_context_filter")
                Utils.saveConfig()
            end,
        },
        {
            text_func = function()
                local actions_list = QA.getAllAvailableActions()
                local fm = 0
                for __, act in ipairs(actions_list) do
                    if act.view == "filemanager" then
                        fm = fm + 1
                    end
                end
                return string.format(_("File Manager Dedicated (%d)"), fm)
            end,
            close_on_click = true,
            sub_item_table = buildDedicatedListItems("fm"),
        },
        {
            text_func = function()
                local actions_list = QA.getAllAvailableActions()
                local rd = 0
                for __, act in ipairs(actions_list) do
                    if act.view == "reader" then
                        rd = rd + 1
                    end
                end
                return string.format(_("Reader Dedicated (%d)"), rd)
            end,
            close_on_click = true,
            sub_item_table = buildDedicatedListItems("reader"),
        },
        {
            text = _("Reset to Defaults"),
            close_on_click = true,
            callback = function()
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
                            setCustom(_G.__QUICKUI_CONFIG.qa_common_custom)
                            setBuiltinOverrides(_G.__QUICKUI_CONFIG.qa_common_builtin_overrides)
                            Utils.saveConfig()
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
-- Panel Management
-- ============================================================

function QA.removeFromPanel(action_id, touch_menu)
    local slots = getQASlots()
    local found = false
    local new_slots = {}
    for __, sid in ipairs(slots) do
        if sid == action_id then
            found = true
        else
            new_slots[#new_slots + 1] = sid
        end
    end

    if not found then
        UIManager:show(Notification:new{
            text = _("Button not found in panel"),
            timeout = 2,
        })
        return false
    end

    _G.__QUICKUI_CONFIG.qa_panel_slots = new_slots
    Utils.saveConfig()

    if touch_menu then
        touch_menu:updateItems()
    end
    return true
end

-- ============================================================
-- Reset All Settings (QA Common)
-- ============================================================

function QA.resetAllSettings()
    local defaults = _G.__QUICKUI_DEFAULTS
    if not defaults then
        logger.warn("QuickUI: Cannot find default_settings for reset")
        return
    end

    for key, default_val in pairs(defaults) do
        _G.__QUICKUI_CONFIG[key] = default_val
    end

    Utils.saveConfig()

    -- Force refresh panel and bottom bar
    local QA_settings = require("qui_actions/qa_settings")
    QA_settings.refreshQuickPanel()
    
    local bb = require("qui_actions/qa_bottombar")
    if bb and bb.refresh then
        bb.refresh()
    end

    UIManager:show(Notification:new{
        text = _("All settings reset to defaults"),
        timeout = 2,
    })
end

-- ============================================================
-- Dispatcher Picker (for System Actions)
-- ============================================================

function QA.openDispatcherPicker(on_select, on_cancel, on_back_to_edit, on_back, on_open_main_menu)
     local actions = QA.getDispatcherActions()
    if #actions == 0 then
        UIManager:show(InfoMessage:new{ text = _("No system actions available"), timeout = 3 })
        if on_cancel then on_cancel() end
        return
    end

    local sections = {
        { key = "general",     title = _("General") },
        { key = "device",      title = _("Device") },
        { key = "screen",      title = _("Screen and lights") },
        { key = "filemanager", title = _("File browser") },
        { key = "reader",      title = _("Reader") },
        { key = "rolling",     title = _("Reflowable documents (epub, fb2, txt…)") },
        { key = "paging",      title = _("Fixed layout documents (pdf, djvu, pics…)") },
    }

    local sections_map = {}
    for __, sec in ipairs(sections) do
        sections_map[sec.key] = { title = sec.title, items = {} }
    end

    for __, action in ipairs(actions) do
        local ok, DispatcherMod = pcall(require, "dispatcher")
        if ok and DispatcherMod then
            local settingsList
            local fn_idx = 1
            while true do
                local name, val = debug.getupvalue(DispatcherMod.registerAction, fn_idx)
                if not name then break end
                if name == "settingsList" then settingsList = val end
                fn_idx = fn_idx + 1
            end
            local def = settingsList and settingsList[action.id]
            if def and def.category then
                local section_key = "general"
                for __, sec in ipairs(sections) do
                    if def[sec.key] == true then
                        section_key = sec.key
                        break
                    end
                end
                table.insert(sections_map[section_key].items, {
                    id = action.id,
                    title = action.title,
                    category = def.category,
                    def = def,
                })
            end
        end
    end

    local function showMainPicker()
        local final_buttons = {}
        local system_dialog = nil

        table.insert(final_buttons, {{
            text = settings_icon .. " " .. _("QA Settings"),
            callback = function()
                if system_dialog then
                    UIManager:close(system_dialog)
                    system_dialog = nil
                end
                if on_open_main_menu then on_open_main_menu() end
                return true
            end
        }})

        table.insert(final_buttons, {{
            text = "◂◂ " .. _("Back to Edit"),
            callback = function()
                if system_dialog then
                    UIManager:close(system_dialog)
                    system_dialog = nil
                end
                if on_back_to_edit then on_back_to_edit() end
                return true
            end
        }})

        table.insert(final_buttons, {{
            text = "◂ " .. _("Back"),
            callback = function()
                if system_dialog then
                    UIManager:close(system_dialog)
                    system_dialog = nil
                end
                if on_back then on_back() end
                return true
            end
        }})

        table.insert(final_buttons, {})

        for __, sec in ipairs(sections) do
            local items = sections_map[sec.key].items
            if #items > 0 then
                table.sort(items, function(a, b) return a.title:lower() < b.title:lower() end)

                table.insert(final_buttons, {
                    {
                        text = sec.title .. " ▸",
                        callback = function()
                            if system_dialog then
                                UIManager:close(system_dialog)
                                system_dialog = nil
                            end
                            local sub_buttons = {}
                            local sub_dialog = nil

                            table.insert(sub_buttons, {{
                                text = settings_icon .. " " .. _("QA Settings"),
                                callback = function()
                                    if sub_dialog then
                                        UIManager:close(sub_dialog)
                                        sub_dialog = nil
                                    end
                                    if on_open_main_menu then on_open_main_menu() end
                                    return true
                                end
                            }})

                            table.insert(sub_buttons, {{
                                text = "◂◂ " .. _("Back to Edit"),
                                callback = function()
                                    if sub_dialog then
                                        UIManager:close(sub_dialog)
                                        sub_dialog = nil
                                    end
                                    if on_back_to_edit then on_back_to_edit() end
                                    return true
                                end
                            }})

                            table.insert(sub_buttons, {{
                                text = "◂ " .. _("Back"),
                                callback = function()
                                    if sub_dialog then
                                        UIManager:close(sub_dialog)
                                        sub_dialog = nil
                                    end
                                    showMainPicker()
                                    return true
                                end
                            }})

                            table.insert(sub_buttons, {})

                            for __, item in ipairs(items) do
                                local _item = item
                                local def = item.def
                                local category = item.category

                                if category == "none" or category == "arg" then
                                    table.insert(sub_buttons, {
                                        {
                                            text = item.title,
                                            callback = function()
                                                if sub_dialog then
                                                    UIManager:close(sub_dialog)
                                                    sub_dialog = nil
                                                end
                                                if on_select then
                                                    on_select(_item.id, true, _item.title)
                                                end
                                                return true
                                            end
                                        }
                                    })
                                elseif category == "absolutenumber" or category == "incrementalnumber" then
                                    table.insert(sub_buttons, {
                                        {
                                            text = item.title,
                                            callback = function()
                                                if sub_dialog then
                                                    UIManager:close(sub_dialog)
                                                    sub_dialog = nil
                                                end
                                                local spin = SpinWidget:new{
                                                    title_text = _item.title,
                                                    value = def.default or def.min or 0,
                                                    value_min = def.min or 0,
                                                    value_max = def.max or 100,
                                                    value_step = def.step or 1,
                                                    unit = def.unit,
                                                    callback = function(spin)
                                                        if on_select then
                                                            on_select(_item.id, spin.value, _item.title .. ": " .. tostring(spin.value))
                                                        end
                                                    end,
                                                }
                                                UIManager:show(spin)
                                                return true
                                            end
                                        }
                                    })
                                elseif category == "string" or category == "configurable" then
                                    table.insert(sub_buttons, {
                                        {
                                            text = item.title,
                                            callback = function()
                                                if sub_dialog then
                                                    UIManager:close(sub_dialog)
                                                    sub_dialog = nil
                                                end
                                                local sub_buttons2 = {}
                                                local args = def.args
                                                local toggle = def.toggle
                                                local sub_dialog2 = nil

                                                if def.args_func then
                                                    local ok, a, t = pcall(def.args_func)
                                                    if ok then
                                                        args = a
                                                        toggle = t
                                                    end
                                                end

                                                -- Top navigation buttons
                                                table.insert(sub_buttons2, {{
                                                    text = settings_icon .. " " .. _("QA Settings"),
                                                    callback = function()
                                                        if sub_dialog2 then
                                                            UIManager:close(sub_dialog2)
                                                            sub_dialog2 = nil
                                                        end
                                                        if on_open_main_menu then on_open_main_menu() end
                                                        return true
                                                    end
                                                }})

                                                table.insert(sub_buttons2, {{
                                                    text = "◂◂ " .. _("Back to Edit"),
                                                    callback = function()
                                                        if sub_dialog2 then
                                                            UIManager:close(sub_dialog2)
                                                            sub_dialog2 = nil
                                                        end
                                                        if on_back_to_edit then on_back_to_edit() end
                                                        return true
                                                    end
                                                }})

                                                table.insert(sub_buttons2, {{
                                                    text = "◂ " .. _("Back"),
                                                    callback = function()
                                                        if sub_dialog2 then
                                                            UIManager:close(sub_dialog2)
                                                            sub_dialog2 = nil
                                                        end
                                                        -- Recreate and show the parent submenu
                                                        sub_dialog = ButtonDialog:new{
                                                            title = sec.title,
                                                            title_align = "center",
                                                            buttons = sub_buttons,
                                                            width = math.floor(Screen:getWidth() * 0.7),
                                                            max_height = math.floor(Screen:getHeight() * 0.7),
                                                        }
                                                        UIManager:show(sub_dialog)
                                                        return true
                                                    end
                                                }})

                                                table.insert(sub_buttons2, {})

                                                if args and #args > 0 then
                                                    for index, value in ipairs(args) do
                                                        local display = toggle and toggle[index] or tostring(value)
                                                        table.insert(sub_buttons2, {
                                                            {
                                                                text = display,
                                                                callback = function()
                                                                    if on_select then
                                                                        on_select(_item.id, value, _item.title .. ": " .. display)
                                                                    end
                                                                    if sub_dialog2 then
                                                                        UIManager:close(sub_dialog2)
                                                                        sub_dialog2 = nil
                                                                    end
                                                                    return true
                                                                end
                                                            }
                                                        })
                                                    end
                                                else
                                                    local dialog
                                                    dialog = InputDialog:new{
                                                        title = _item.title,
                                                        input_hint = _("Enter value..."),
                                                        buttons = {
                                                            {
                                                                {
                                                                    text = _("Cancel"),
                                                                    callback = function()
                                                                        UIManager:close(dialog)
                                                                    end,
                                                                },
                                                                {
                                                                    text = _("OK"),
                                                                    is_enter_default = true,
                                                                    callback = function()
                                                                        local val = dialog:getInputText()
                                                                        if on_select then
                                                                            on_select(_item.id, val, _item.title .. ": " .. val)
                                                                        end
                                                                        UIManager:close(dialog)
                                                                    end,
                                                                },
                                                            },
                                                        },
                                                    }
                                                    UIManager:show(dialog)
                                                end

                                                sub_dialog2 = ButtonDialog:new{
                                                    title = _item.title,
                                                    title_align = "center",
                                                    buttons = sub_buttons2,
                                                    width = math.floor(Screen:getWidth() * 0.7),
                                                }
                                                UIManager:show(sub_dialog2)
                                                return true
                                            end
                                        }
                                    })
                                end
                            end

                            if #sub_buttons == 4 then
                                table.insert(sub_buttons, {{
                                    text = _("No actions available"),
                                    enabled = false,
                                }})
                            end

                            sub_dialog = ButtonDialog:new{
                                title = sec.title,
                                title_align = "center",
                                buttons = sub_buttons,
                                width = math.floor(Screen:getWidth() * 0.7),
                                max_height = math.floor(Screen:getHeight() * 0.7),
                            }
                            UIManager:show(sub_dialog)
                        end
                    }
                })
            end
        end

        system_dialog = ButtonDialog:new{
            title = _("System Actions"),
            title_align = "center",
            buttons = final_buttons,
            width = math.floor(Screen:getWidth() * 0.7),
            max_height = math.floor(Screen:getHeight() * 0.7),
        }
        UIManager:show(system_dialog)
    end

    showMainPicker()
end

function QA.getDispatcherActions()
    local ok, DispatcherMod = pcall(require, "dispatcher")
    if not ok or not DispatcherMod then return {} end
    pcall(DispatcherMod.init, DispatcherMod)

    local settingsList, dispatcher_menu_order
    local fn_idx = 1
    while true do
        local name, val = debug.getupvalue(DispatcherMod.registerAction, fn_idx)
        if not name then break end
        if name == "settingsList" then settingsList = val end
        if name == "dispatcher_menu_order" then dispatcher_menu_order = val end
        fn_idx = fn_idx + 1
    end

    if type(settingsList) ~= "table" then return {} end

    local order = (type(dispatcher_menu_order) == "table" and dispatcher_menu_order)
        or (function()
            local keys = {}
            for key in pairs(settingsList) do keys[#keys + 1] = key end
            table.sort(keys)
            return keys
        end)()

    local result = {}
    for __, action_id in ipairs(order) do
        local def = settingsList[action_id]
        if type(def) == "table" and def.title and def.category
                and (def.condition == nil or def.condition == true) then
            table.insert(result, {
                id = action_id,
                title = tostring(def.title),
                category = def.category,
            })
        end
    end

    return result
end

-- ============================================================
-- Register All Built-in Actions
-- ============================================================

-- ============================================================
-- Register All Built-in Actions
-- ============================================================

function QA.registerAllActions()
    if QA._registered then
        logger.info("QuickUI QA: actions already registered, skipping")
        return
    end

    QA._registered = true

    local config = _G.__QUICKUI_CONFIG

    -- ============================================================
    -- General actions (always registered)
    -- ============================================================

    -- Home (File Manager)
    QA.registerAction("home", _("Home"), "nerd:F46D", false, "common", function(ctx)
        local FM = require("apps/filemanager/filemanager")
        local RUI = require("apps/reader/readerui")
        
        if ctx and ctx.touch_menu then
            ctx.touch_menu:onClose()
        end
        
        local reader = RUI and RUI.instance
        if reader then
            reader:onHome()
            return
        end
        
        local fm = FM and FM.instance
        if fm then
            fm:onHome()
        end
    end)

    -- WiFi
    QA.registerAction("wifi", _("Wi-Fi"), "net-wifi.svg", true, "common", function(ctx)
        local NetworkMgr = getNetworkMgr()
        if not NetworkMgr then
            UIManager:show(InfoMessage:new{ text = _("WiFi not available"), timeout = 2 })
            return
        end
        local is_on = NetworkMgr:isWifiOn()
        _wifi_optimistic = not is_on
        if ctx.touch_menu then
            ctx.touch_menu:updateItems()
        end
        if is_on then
            NetworkMgr:turnOffWifi()
        else
            NetworkMgr:turnOnWifi()
        end
        UIManager:scheduleIn(2, function()
            _wifi_optimistic = nil
            if ctx.touch_menu then
                ctx.touch_menu:updateItems()
            end
        end)
    end)

    -- Night Mode
    QA.registerAction("night", _("Night Mode"), "nerd:F186", true, "common", function(ctx)
        local G = rawget(_G, "G_reader_settings")
        local night_mode = G and G:isTrue("night_mode") or false
        Screen:toggleNightMode()
        UIManager:ToggleNightMode(not night_mode)
        if G then G:saveSetting("night_mode", not night_mode) end
        UIManager:setDirty("all", "full")
    end)

    -- Rotate
    QA.registerAction("rotate", _("Rotate"), "nerd:E8BC", true, "common", function(ctx)
        UIManager:broadcastEvent(Event:new("SwapRotation"))
    end)

    -- Screenshot
    QA.registerAction("screenshot", _("Screenshot (4s delay)"), "nerd:E7FF", false, "common", function(ctx)
        local function showCountdown(num)
            UIManager:show(Notification:new{
                text = tostring(num),
                timeout = 1,
            })
        end
        showCountdown(3)
        UIManager:scheduleIn(1, function()
            showCountdown(2)
            UIManager:scheduleIn(1, function()
                UIManager:scheduleIn(1, function()
                    local ui = require("apps/reader/readerui").instance
                    if not ui then
                        local FM = require("apps/filemanager/filemanager")
                        ui = FM.instance
                    end
                    if ui and ui.screenshoter then
                        ui.screenshoter:onScreenshot()
                    else
                        local Screenshoter = require("ui/widget/screenshoter")
                        local temp = Screenshoter:new{ ui = ui }
                        temp:onScreenshot()
                    end
                end)
            end)
        end)
    end)

    -- Continue Reading
    QA.registerAction("continue", _("Continue Reading"), "nerd:F405", false, "common", function(ctx)
        local RUI = require("apps/reader/readerui")
        local reader = RUI and RUI.instance
        local RH = require("readhistory")
        local target_file = nil
        if reader and reader.document then
            local current_file = reader.document.file
            target_file = RH:getPreviousFile(current_file)
        else
            target_file = RH and RH.hist and RH.hist[1] and RH.hist[1].file
        end
        if target_file then
            if ctx and ctx.touch_menu then
                ctx.touch_menu:onClose()
            end
            local ReaderUI = require("apps/reader/readerui")
            ReaderUI:showReader(target_file)
        else
            UIManager:show(InfoMessage:new{
                text = _("No recent book found"),
                timeout = 2,
            })
        end
    end)

    -- Search
    QA.registerAction("search", _("Search"), "nerd:F002", false, "common", function(ctx)
        local ReaderUI = require("apps/reader/readerui")
        local reader = ReaderUI.instance
        if reader and reader.search then
            reader.search:onShowFulltextSearchInput()
        else
            local FM = require("apps/filemanager/filemanager")
            local fm = FM.instance
            if fm and fm.filesearcher then
                fm.filesearcher:onShowFileSearch()
            end
        end
    end)

    -- Quit
    QA.registerAction("quit", _("Quit"), "nerd:F08B", false, "common", function(ctx)
        UIManager:quit()
    end)

    -- Restart
    QA.registerAction("restart", _("Restart"), "nerd:F01E", false, "common", function(ctx)
        UIManager:restartKOReader()
    end)

    -- Power
    QA.registerAction("power", _("Power"), "nerd:F011", true, "common", function(ctx)
        local buttons = {}
        if Device:canRestart() then
            buttons[#buttons + 1] = {{ text = _("Restart"), callback = function()
                UIManager:restartKOReader()
            end }}
        end
        if Device:canSuspend() then
            buttons[#buttons + 1] = {{ text = _("Sleep"), callback = function()
                UIManager:suspend()
            end }}
        end
        buttons[#buttons + 1] = {{ text = _("Quit"), callback = function()
            UIManager:quit()
        end }}
        UIManager:show(ButtonDialog:new{ width = math.floor(Screen:getWidth() * 0.42), buttons = buttons })
    end)

    -- HTTP Inspector
    QA.registerAction("httpinspector", _("HTTP Server"), "nerd:E701", true, "common", function(ctx)
        local ui = require("apps/reader/readerui").instance
        if not ui then
            local FM = require("apps/filemanager/filemanager")
            ui = FM.instance
        end

        if not ui then
            UIManager:show(Notification:new{
                text = _("Unable to get UI instance"),
                timeout = 2,
            })
            return
        end

        if ui and ui.httpinspector then
            if ui.httpinspector:isRunning() then
                ui.httpinspector:stop()
                UIManager:show(Notification:new{
                    text = _("HTTP server stopped"),
                    timeout = 2,
                })
            else
                ui.httpinspector:start()
                UIManager:show(Notification:new{
                    text = _("HTTP server started"),
                    timeout = 2,
                })
            end
        else
            UIManager:show(InfoMessage:new{
                text = _("httpinspector plugin not found"),
                timeout = 2,
            })
        end
    end)

    -- Font List
    QA.registerAction("fontlist", _("Font List"), "nerd:F031", false, "reader", function(ctx)
        local RUI = require("apps/reader/readerui")
        local reader = RUI and RUI.instance
        local cre = require("document/credocument"):engineInit()
        local FontList = require("fontlist")
        local Event = require("ui/event")

        if not reader then
            UIManager:show(InfoMessage:new{
                text = _("Please open a book first"),
                timeout = 2,
            })
            return
        end

        if ctx and ctx.touch_menu then
            ctx.touch_menu:onClose()
        end

        local face_list = cre.getFontFaces()
        local buttons = {}

        table.sort(face_list, function(a, b)
            return a:lower() < b:lower()
        end)

        local current_font = reader.font and reader.font.font_face

        local font_dialog = nil

        for idx, face in ipairs(face_list) do
            local font_filename, font_faceindex = cre.getFontFaceFilenameAndFaceIndex(face)
            if not font_filename then
                font_filename, font_faceindex = cre.getFontFaceFilenameAndFaceIndex(face, nil, true)
            end
            local display_name = face
            if font_filename and font_faceindex then
                display_name = FontList:getLocalizedFontName(font_filename, font_faceindex) or face
            end
            local is_checked = (face == current_font)
            table.insert(buttons, {{
                text = display_name .. (is_checked and "  ✓" or ""),
                callback = function()
                    if font_dialog then
                        UIManager:close(font_dialog)
                        font_dialog = nil
                    end

                    if reader and reader.view and reader.font then
                        reader.font:onSetFont(face)
                        reader.view.ui:handleEvent(Event:new("UpdatePos"))
                        UIManager:setDirty(reader.view.dialog, "full")

                        UIManager:show(Notification:new{
                            text = string.format(_("Font set to: %s"), display_name),
                            timeout = 2,
                        })
                    end
                end,
            }})
        end

        font_dialog = ButtonDialog:new{
            title = _("Select Font"),
            title_align = "center",
            buttons = buttons,
            width = math.floor(Screen:getWidth() * 0.7),
            max_height = math.floor(Screen:getHeight() * 0.7),
            rows_per_page = 10,
        }
        UIManager:show(font_dialog)
    end)

    -- Reading Insights
    QA.registerAction("reading_insights", _("Reading Insights"), "nerd:F073", false, "common", function()
        UIManager:broadcastEvent(Event:new("ShowReadingInsightsPopup"))
    end)

    -- FileBrowserPlus
    QA.registerAction("filebrowserplus", _("FileBrowserPlus"), "nerd:F029", true, "common", function()
        local FM = require("apps/filemanager/filemanager")
        local fm = FM and FM.instance
        local RUI = require("apps/reader/readerui")
        local reader = RUI and RUI.instance
        local plugin = nil
        if fm and fm.filebrowserplus then
            plugin = fm.filebrowserplus
        elseif reader and reader.filebrowserplus then
            plugin = reader.filebrowserplus
        end
        if plugin then
            if plugin:isRunning() then
                plugin:stop()
            else
                plugin:start()
            end
        else
            UIManager:show(InfoMessage:new{
                text = _("filebrowserplus plugin not found"),
                timeout = 2,
            })
        end
    end)

    -- ZLibrary Search
    QA.registerAction("zlibrary_search", _("ZLibrary Search"), "nerd:E76F", false, "common", function()
        local FM = require("apps/filemanager/filemanager")
        local fm = FM and FM.instance
        local RUI = require("apps/reader/readerui")
        local reader = RUI and RUI.instance
        local plugin = nil
        if fm and fm.zlibrary then
            plugin = fm.zlibrary
        elseif reader and reader.zlibrary then
            plugin = reader.zlibrary
        end
        if plugin and plugin.onZlibrarySearch then
            plugin:onZlibrarySearch()
        else
            UIManager:show(InfoMessage:new{
                text = _("zlibrary plugin not found"),
                timeout = 2,
            })
        end
    end)

    -- CloudLibrary AutoSync
    QA.registerAction("cloudlibrary_autosync", _("CloudLibrary - AutoSync"), "nerd:E33B", false, "common", function()
        local FM = require("apps/filemanager/filemanager")
        local fm = FM and FM.instance
        local RUI = require("apps/reader/readerui")
        local reader = RUI and RUI.instance
        local plugin = nil
        if fm and fm.CloudLibrary then
            plugin = fm.CloudLibrary
        elseif reader and reader.CloudLibrary then
            plugin = reader.CloudLibrary
        end
        if plugin then
            plugin:toggleAutoSyncQuick()
        else
            UIManager:show(InfoMessage:new{
                text = _("CloudLibrary plugin not found"),
                timeout = 2,
            })
        end
    end)

    -- CloudLibrary Batch Download
    QA.registerAction("cloudlibrary_batch_download_books", _("CloudLibrary - Batch Download"), "nerd:F409", false, "common", function()
        local FM = require("apps/filemanager/filemanager")
        local fm = FM and FM.instance
        local RUI = require("apps/reader/readerui")
        local reader = RUI and RUI.instance
        local plugin = nil
        if fm and fm.CloudLibrary then
            plugin = fm.CloudLibrary
        elseif reader and reader.CloudLibrary then
            plugin = reader.CloudLibrary
        end
        if plugin then
            plugin:batchDownloadBooks()
        else
            UIManager:show(InfoMessage:new{
                text = _("CloudLibrary plugin not found"),
                timeout = 2,
            })
        end
    end)

    -- CloudLibrary Settings
    QA.registerAction("cloudlibrary_settings", _("CloudLibrary - Settings"), "nerd:E33D", false, "common", function()
        local FM = require("apps/filemanager/filemanager")
        local fm = FM and FM.instance
        local RUI = require("apps/reader/readerui")
        local reader = RUI and RUI.instance
        local plugin = nil
        if fm and fm.CloudLibrary then
            plugin = fm.CloudLibrary
        elseif reader and reader.CloudLibrary then
            plugin = reader.CloudLibrary
        end
        if plugin then
            if reader then
                plugin:onCloudLibrarySettingsReader()
            else
                plugin:onCloudLibrarySettingsFileManager()
            end
        else
            UIManager:show(InfoMessage:new{
                text = _("CloudLibrary plugin not found"),
                timeout = 2,
            })
        end
    end)

    -- Annotations Viewer
    QA.registerAction("annotations_viewer", _("Annotations Viewer"), "nerd:F040", false, "common", function()
        local RUI = require("apps/reader/readerui")
        local FM = require("apps/filemanager/filemanager")

        local reader = RUI and RUI.instance
        local fm = FM and FM.instance

        local has_plugin = false
        if reader and reader.annotationsviewer then
            has_plugin = true
        elseif fm and fm.annotationsviewer then
            has_plugin = true
        end

        if not has_plugin then
            UIManager:show(InfoMessage:new{
                text = _("annotationsviewer plugin not found"),
                timeout = 2,
            })
            return
        end

        if reader then
            UIManager:broadcastEvent(Event:new("ShowCurrentBookAnnotations"))
        else
            UIManager:broadcastEvent(Event:new("ShowAllAnnotations"))
        end
    end)

    -- ============================================================
    -- QuickUI Settings actions (qa_common_enabled)
    -- ============================================================
    if config and config.qa_common_enabled then
        -- QuickUI Settings
        QA.registerAction("quickui_settings", _("QuickUI Settings"), "nerd:F013", false, "common", function(ctx)
            if ctx and ctx.touch_menu then
                ctx.touch_menu:onClose()
            end
            
            local plugin = _G.__QUICKUI_PLUGIN_STORE and _G.__QUICKUI_PLUGIN_STORE.plugin_ref
            if plugin and plugin.quickuisettings then
                plugin:quickuisettings()
            end
        end)

        -- QA Settings
        QA.registerAction("qa_settings", _("QA Settings"), "nerd:E73A", false, "common", function(ctx)
            local settings = require("qui_actions/qa_settings")
            settings.showSettings()
        end)

        -- QA New
        QA.registerAction("qa_new", _("New Quick Action"), "nerd:F067", false, "common", function(ctx)
            local settings = require("qui_actions/qa_settings")
            settings.showCustomQADialog(nil, function()
                local fm = require("apps/filemanager/filemanager").instance
                if fm and fm.menu and fm.menu.menu_container and fm.menu.menu_container[1] then
                    fm.menu.menu_container[1]:updateItems()
                end
                local readerui = require("apps/reader/readerui").instance
                if readerui and readerui.menu and readerui.menu.menu_container and readerui.menu.menu_container[1] then
                    readerui.menu.menu_container[1]:updateItems()
                end
            end)
        end)

        -- UI Font Switch
        QA.registerAction("ui_font_switch", _("UI Font Switcher"), "nerd:F30B", true, "common", function(ctx)
            local UIFont = require("qui_actions/qa_uifont")
            UIFont.showUIFontSwitcher()
        end)

        -- ============================================================
        -- Panel actions (qa_panel_enabled)
        -- ============================================================
        if config.qa_panel_enabled then
            -- QA Panel Settings
            QA.registerAction("qa_panel_settings", _("QA Panel Settings"), "nerd:F1DE", false, "common", function(ctx)
                local settings = require("qui_actions/qa_settings")
                if settings and settings.showPanelSettings then
                    settings.showPanelSettings()
                else
                    UIManager:show(InfoMessage:new{
                        text = _("Panel settings not available"),
                        timeout = 2,
                    })
                end
            end)

            -- QA Add Panel Button
            QA.registerAction("qa_add_panel_button", _("QA Add Panel Button"), "nerd:F055", false, "common", function(ctx)
                local settings = require("qui_actions/qa_settings")
                local fm = require("apps/filemanager/filemanager").instance
                local touch_menu = nil
                if fm and fm.menu and fm.menu.menu_container and fm.menu.menu_container[1] then
                    touch_menu = fm.menu.menu_container[1]
                else
                    local readerui = require("apps/reader/readerui").instance
                    if readerui and readerui.menu and readerui.menu.menu_container and readerui.menu.menu_container[1] then
                        touch_menu = readerui.menu.menu_container[1]
                    end
                end
                settings.showAddButtonMenu(touch_menu, function()
                    settings.showPanelSettings()
                end)
            end)
        end

        -- ============================================================
        -- Bottom Bar actions (qa_bb_enabled)
        -- ============================================================
        if config.qa_bb_enabled then
            -- QA Bottom Bar Settings
            QA.registerAction("qa_bb_settings", _("QA Bottom Bar Settings"), "nerd:F1DE", false, "common", function(ctx)
                local settings = require("qui_actions/qa_settings")
                if settings and settings.showBottombarSettings then
                    settings.showBottombarSettings()
                else
                    UIManager:show(InfoMessage:new{
                        text = _("Bottom Bar settings not available"),
                        timeout = 2,
                    })
                end
            end)

            -- QA Add Bottom Bar Tab
            QA.registerAction("qa_add_bb_tab", _("QA Add Bottom Bar Tab"), "nerd:F055", false, "common", function(ctx)
                local bb = require("qui_actions/qa_bottombar")
                if bb and bb.showAddTabMenu then
                    bb.showAddTabMenu(function()
                        if bb.refresh then
                            bb.refresh()
                        end
                    end)
                else
                    UIManager:show(InfoMessage:new{
                        text = _("Bottom Bar module not available"),
                        timeout = 2,
                    })
                end
            end)
        end
    end

    -- ============================================================
    -- Cover actions (cover_enabled)
    -- ============================================================
    if config and config.cover_enabled then
        QA.registerAction("QuickUI_CoverSettings", _("Cover Visual Settings"), "nerd:E8C8", false, "filemanager", function(ctx)
            local RUI = require("apps/reader/readerui")
            local reader = RUI and RUI.instance
            if reader then
                UIManager:show(InfoMessage:new{
                    text = _("This feature is only available in File Manager"),
                    timeout = 2,
                })
            else
                if ctx and ctx.touch_menu then
                    ctx.touch_menu:onClose()
                end
                local cover_module = require("qui_cover")
                if cover_module and cover_module.showSettings then
                    cover_module.showSettings()
                end
            end
        end)
    end

    -- ============================================================
    -- Cloze actions (cl_enabled)
    -- ============================================================
    if config and config.cl_enabled then
        -- Toggle Cloze Mode
        QA.registerAction("toggle_cloze_mode", _("Toggle Cloze Mode"), "nerd:F040", false, "reader", function(ctx)
            local RUI = require("apps/reader/readerui")
            local reader = RUI and RUI.instance

            if reader then
                local cloze_module = require("qui_clozemode")
                if cloze_module and cloze_module.toggleAll then
                    cloze_module:toggleAll()
                end
                if ctx and ctx.touch_menu then
                    ctx.touch_menu:updateItems()
                end
            else
                UIManager:show(InfoMessage:new{
                    text = _("Please open a book first"),
                    timeout = 2,
                })
            end
        end)

        -- Cloze Settings
        QA.registerAction("QuickUI_ClozeSettings", _("Cloze Settings"), "nerd:F441", false, "reader", function(ctx)
            local cloze_module = require("qui_clozemode")
            if cloze_module and cloze_module.showSettings then
                cloze_module.showSettings()
            end
        end)
    end

    -- ============================================================
    -- Header/Footer actions (hf_enabled)
    -- ============================================================
    if config and config.hf_enabled then
        QA.registerAction("QuickUI_HFSettings", _("Header & Footer Settings"), "nerd:E7B5", false, "reader", function(ctx)
            local hf_module = require("qui_header_footer")
            if hf_module and hf_module.showSettings then
                hf_module.showSettings()
            end
        end)
    end

    logger.info("QuickUI QA: All built-in actions registered (" .. #ACTION_ORDER .. " actions)")
end

-- ============================================================
-- Initialization
-- ============================================================

function QA.init(plugin)
    logger.info("QuickUI QA Actions: initialized")
end

QA.ACTION_ORDER = ACTION_ORDER
QA.getDefaultViewForActionType = getDefaultViewForActionType

-- Register actions immediately when module loads
QA.registerAllActions()

return QA
