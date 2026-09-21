--[[
QuickUI - Quick Actions Settings Menu

The two per-action editors (built-in + custom) and the three per-container
settings menus (panel / bottom bar / vertical bar) live in
qui_actions/qa_settings_bars.lua. This file keeps the root menu, the
dialog lifecycle helpers, and the small menu-item builders that are not
per-bar (interface filter, quick actions submenu, etc.), and forwards the
per-bar work to Bars.
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
local Notification = require("ui/widget/notification")
local SortWidget = require("ui/widget/sortwidget")
local SpinWidget = require("ui/widget/spinwidget")
local PathChooser = require("ui/widget/pathchooser")

local Utils = require("qui_utils")

local actions = require("qui_actions.qa_actions")
local icon_picker = require("qui_actions.qa_icon_picker")
local plugin_scan = require("qui_actions.qa_plugin_scan")
local uifont = require("qui_actions.qa_uifont")
local settings_icon = icon_picker.nerdIconChar("nerd:E73A") or "⚙️"

local Bars = require("qui_actions/qa_bar_settings")

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

    Utils.registerRefreshHandler("qa_panel", function()
        QA.refreshQuickPanel()
    end)
end

function QA.setBottombar(bb)
    PLUGIN_STORE.bottombar = bb
    if not bb then
        logger.warn("QuickUI QA Settings: BottomBar not available")
    end
end

function QA.setVerticalBar(vb)
    PLUGIN_STORE.verticalbar = vb
    if not vb then
        logger.warn("QuickUI QA Settings: VerticalBar not available")
    end
end

-- ============================================================
-- Forward to actions module
-- ============================================================

local function getAction(id)         return actions.getAction(id) end
local function getLabelForAction(id) return actions.getLabelForAction(id) end
local function getActionViewFinal(id) return actions.getActionViewFinal(id) end
local function getAllAvailableActions() return actions.getAllAvailableActions() end
local function getTypePriority(id)   return actions.getTypePriority(id) end
local function getActionSymbol(id)   return actions.getActionSymbol(id) end

-- ============================================================
-- Dialog Management
-- ============================================================

local function closeSettingsDialog(exclude)
    local exclude_set = {}
    if type(exclude) == "string" then
        exclude_set[exclude] = true
    elseif type(exclude) == "table" then
        for __, key in ipairs(exclude) do
            exclude_set[key] = true
        end
    end

    if not exclude_set["_active_dialog"] and _active_dialog then
        UIManager:close(_active_dialog); _active_dialog = nil
    end
    if not exclude_set["_settings_dialog"] and _settings_dialog then
        UIManager:close(_settings_dialog); _settings_dialog = nil
    end
    if not exclude_set["_sub_dialog"] and _sub_dialog then
        UIManager:close(_sub_dialog); _sub_dialog = nil
    end
    if not exclude_set["_choice_dialog"] and _choice_dialog then
        UIManager:close(_choice_dialog); _choice_dialog = nil
    end
    if not exclude_set["_coll_picker"] and _coll_picker then
        UIManager:close(_coll_picker); _coll_picker = nil
    end
    if not exclude_set["_view_dialog"] and _view_dialog then
        UIManager:close(_view_dialog); _view_dialog = nil
    end
end

-- Expose the shared helpers to Bars via PLUGIN_STORE (Bars calls them back).
PLUGIN_STORE.close_settings_dialog = closeSettingsDialog

function QA.refreshQuickPanel()
    local fm = require("apps/filemanager/filemanager").instance
    if fm and fm.menu and fm.menu.menu_container then
        local menu = fm.menu.menu_container[1]
        if menu and menu.updateItems then menu:updateItems() end
    end
    local readerui = require("apps/reader/readerui").instance
    if readerui and readerui.menu and readerui.menu.menu_container then
        local menu = readerui.menu.menu_container[1]
        if menu and menu.updateItems then menu:updateItems() end
    end
end
PLUGIN_STORE.refresh_quick_panel = QA.refreshQuickPanel

-- ============================================================
-- Show Menu
-- ============================================================

local function showMenu(items, title, parent_stack, touch_menu, root_items)
    local buttons = {}

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
            if type(display_text) == "function" then display_text = display_text() end
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
                        table.insert(new_stack, { items = items, title = title, parent_stack = parent_stack })
                        showMenu(sub_table, display_text, new_stack, touch_menu, root_items)
                    end
                }
            })
        else
            local checked = item.checked_func and item.checked_func() or false
            local display_text = item.text_func and item.text_func() or item.text
            if type(display_text) == "function" then display_text = display_text() end
            local prefix = (checked and "✓ " or "  ")
            local enabled = (item.enabled == nil) or (type(item.enabled) == "function" and item.enabled()) or item.enabled

            table.insert(buttons, {
                {
                    text = prefix .. display_text,
                    enabled = enabled,
                    callback = function()
                        if item.callback then item.callback(touch_menu) end
                        if item.close_on_click then
                            local exclude = {}
                            if type(item.close_on_click) == "table" then exclude = item.close_on_click end
                            closeSettingsDialog(exclude)
                        else
                            if touch_menu then touch_menu:updateItems() end
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

-- Expose showMenu to Bars via PLUGIN_STORE.
PLUGIN_STORE.show_menu = showMenu

-- ============================================================
-- Edit dialogs -- thin forwarders to Bars
-- ============================================================

function QA.showEditActionDialog(action_id, on_done, source)
    return Bars.showEditActionDialog(action_id, on_done, source)
end

function QA.showCustomQADialog(qa_id, on_done, source)
    return Bars.showCustomQADialog(qa_id, on_done, source)
end

-- ============================================================
-- Add Button Menu (panel)
-- ============================================================

local _add_button_dialog = nil
local _sliders_dialog = nil

function QA.showAddButtonMenu(touch_menu, on_back, filtered_actions)
    local slots = Utils.getTable("qa_panel_slots")
    local slot_set = {}
    for __, id in ipairs(slots) do slot_set[id] = true end
    local available = filtered_actions or getAllAvailableActions()
    table.sort(available, function(a, b)
        local a_checked = slot_set[a.id] or false
        local b_checked = slot_set[b.id] or false
        if a_checked ~= b_checked then return a_checked end
        local a_prio = getTypePriority(a.id)
        local b_prio = getTypePriority(b.id)
        if a_prio ~= b_prio then return a_prio < b_prio end
        return a.label:lower() < b.label:lower()
    end)

    local buttons = {}

    table.insert(buttons, { Utils.createSearchButton(
        function() QA.showAddButtonMenu(touch_menu, on_back) end,
        function(keyword)
            if _add_button_dialog then UIManager:close(_add_button_dialog); _add_button_dialog = nil end
            local filtered = Utils.filterActionsByKeyword(getAllAvailableActions(), keyword)
            QA.showAddButtonMenu(touch_menu, on_back, filtered)
        end,
        function()
            if _add_button_dialog then UIManager:close(_add_button_dialog); _add_button_dialog = nil end
        end
    ) })
    table.insert(buttons, {})

    if on_back then
        table.insert(buttons, {{
            text = "◂◂ " .. _("Back to Root"),
            callback = function()
                if _add_button_dialog then UIManager:close(_add_button_dialog); _add_button_dialog = nil end
                closeSettingsDialog()
                QA.showSettings()
            end
        }})
        table.insert(buttons, {{
            text = "◂ " .. _("Back"),
            callback = function()
                if _add_button_dialog then UIManager:close(_add_button_dialog); _add_button_dialog = nil end
                closeSettingsDialog()
                on_back()
            end
        }})
        table.insert(buttons, {})
    else
        table.insert(buttons, {{
            text = settings_icon .. " " .. _("QA Settings"),
            callback = function()
                if _add_button_dialog then UIManager:close(_add_button_dialog); _add_button_dialog = nil end
                closeSettingsDialog()
                QA.showSettings()
            end
        }})
        table.insert(buttons, {})
    end

    table.insert(buttons, {{
        text = _("Sliders") .. " ▸",
        callback = function()
            if _add_button_dialog then
                UIManager:close(_add_button_dialog)
                _add_button_dialog = nil
            end
            closeSettingsDialog()
            QA.showSlidersMenu(touch_menu, on_back)
        end,
    }})

    local function getAllChecked()
        for __, action in ipairs(available) do
            if not slot_set[action.id] then return false end
        end
        return true
    end

    local all_checked = getAllChecked()
    table.insert(buttons, {{
        text = all_checked and "☑ " .. _("Deselect All") or "☐ " .. _("Select All"),
        callback = function(touchmenu_instance)
            local is_all_checked = getAllChecked()
            local current_slots = Utils.getTable("qa_panel_slots")
            local new_slots = {}
            if is_all_checked then
                for __, id in ipairs(current_slots) do
                    local is_available = false
                    for __, action in ipairs(available) do
                        if action.id == id then is_available = true; break end
                    end
                    if not is_available then table.insert(new_slots, id) end
                end
            else
                for __, id in ipairs(current_slots) do table.insert(new_slots, id) end
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
            Utils.set("qa_panel_slots", new_slots)
            if touchmenu_instance then touchmenu_instance:updateItems() end
            if touch_menu then touch_menu:updateItems() end
            QA.refreshQuickPanel()
            closeSettingsDialog()
            QA.showAddButtonMenu(touch_menu, on_back)
        end,
    }})

    table.insert(buttons, {})

    table.insert(buttons, {{
        text = _("Apply preset (QA panel)"),
        callback = function()
            Utils.applyDefault({"qa_common", "qa_panel"})
            if touchmenu_instance then touchmenu_instance:updateItems() end
            if touch_menu then touch_menu:updateItems() end
            QA.refreshQuickPanel()
            closeSettingsDialog()
            QA.showAddButtonMenu(touch_menu, on_back)
        end,
    }})
    table.insert(buttons, {})

    for i = 1, #available do
        local action = available[i]
        local is_checked = slot_set[action.id] or false
        local symbol = getActionSymbol(action.id)
        local check_mark = is_checked and "✓ " or "  "
        local view_tag = " [" .. (action.view or "common") .. "]"
        local display_text = check_mark .. symbol .. action.label .. view_tag

        table.insert(buttons, {{
            text = display_text,
            callback = function(touchmenu_instance)
                local current_slots = Utils.getTable("qa_panel_slots")
                local found = false
                for j = 1, #current_slots do
                    if current_slots[j] == action.id then found = true; break end
                end
                if found then
                    local new_slots = {}
                    for j = 1, #current_slots do
                        if current_slots[j] ~= action.id then new_slots[#new_slots + 1] = current_slots[j] end
                    end
                    Utils.set("qa_panel_slots", new_slots)
                else
                    if #current_slots >= 66 then
                        UIManager:show(Notification:new{
                            text = string.format(_("Max %d buttons"), 66),
                            timeout = 2,
                        })
                        return
                    end
                    current_slots[#current_slots + 1] = action.id
                    Utils.set("qa_panel_slots", current_slots)
                end
                if touchmenu_instance then touchmenu_instance:updateItems() end
                if touch_menu then touch_menu:updateItems() end
                QA.refreshQuickPanel()
                closeSettingsDialog()
                QA.showAddButtonMenu(touch_menu, on_back)
            end,
        }})
    end

    table.insert(buttons, {})
    table.insert(buttons, {{ text = _("Close"), callback = function()
        if _add_button_dialog then UIManager:close(_add_button_dialog); _add_button_dialog = nil end
        closeSettingsDialog()
    end }})

    local dialog = ButtonDialog:new{
        title = _("Add Button"),
        title_align = "center",
        buttons = buttons,
        width = math.floor(Screen:getWidth() * 0.7),
        max_height = math.floor(Screen:getHeight() * 0.7),
    }
    if _add_button_dialog then UIManager:close(_add_button_dialog); _add_button_dialog = nil end
    _add_button_dialog = dialog
    UIManager:show(dialog)
end

function QA.showSlidersMenu(touch_menu, on_back)
    local buttons = {}

    table.insert(buttons, {{
        text = "◂ " .. _("Back"),
        callback = function()
            if _sliders_dialog then
                UIManager:close(_sliders_dialog)
                _sliders_dialog = nil
            end
            closeSettingsDialog()
            QA.showAddButtonMenu(touch_menu, on_back)
        end,
    }})
    table.insert(buttons, {})

    table.insert(buttons, {{
        text = _("Show Slider Value"),
        checked_func = function() return Utils.getBool("qa_panel_slider_show_value") end,
        callback = function(tm)
            Utils.set("qa_panel_slider_show_value", not Utils.getBool("qa_panel_slider_show_value"))
            if tm then tm:updateItems() end
            if touch_menu then touch_menu:updateItems() end
            QA.refreshQuickPanel()
            if _sliders_dialog then UIManager:close(_sliders_dialog); _sliders_dialog = nil end
            QA.showSlidersMenu(touch_menu, on_back)
        end,
    }})
    table.insert(buttons, {})
    
    -- ---- Hardware ----
    table.insert(buttons, {{
        text = _("Frontlight Slider"),
        checked_func = function() return Utils.getBool("qa_panel_frontlight") end,
        callback = function(tm)
            Utils.set("qa_panel_frontlight", not Utils.getBool("qa_panel_frontlight"))
            if tm then tm:updateItems() end
            if touch_menu then touch_menu:updateItems() end
            QA.refreshQuickPanel()
            if _sliders_dialog then UIManager:close(_sliders_dialog); _sliders_dialog = nil end
            QA.showSlidersMenu(touch_menu, on_back)
        end,
    }})
    table.insert(buttons, {{
        text = _("Warmth Slider"),
        checked_func = function() return Utils.getBool("qa_panel_warmth") end,
        enabled_func = function() return Device:hasNaturalLight() end,
        callback = function(tm)
            Utils.set("qa_panel_warmth", not Utils.getBool("qa_panel_warmth"))
            if tm then tm:updateItems() end
            if touch_menu then touch_menu:updateItems() end
            QA.refreshQuickPanel()
            if _sliders_dialog then UIManager:close(_sliders_dialog); _sliders_dialog = nil end
            QA.showSlidersMenu(touch_menu, on_back)
        end,
    }})

    table.insert(buttons, {})

    -- ---- Reader ----
    local function readerAvailable()
        local RUI = require("apps/reader/readerui")
        return RUI and RUI.instance ~= nil
    end

    local reader_items = {
        { key = "qa_panel_reader_font_size",    label = _("Font Size") },
        { key = "qa_panel_reader_line_spacing", label = _("Line Spacing") },
        { key = "qa_panel_reader_gamma",        label = _("Contrast") },
        { key = "qa_panel_reader_margins_h",    label = _("L/R Margins")  },
        { key = "qa_panel_reader_margin_top",   label = _("Top Margin") },
        { key = "qa_panel_reader_margin_bot",   label = _("Bottom Margin") },
        { key = "qa_panel_reader_zoom",         label = _("Zoom") },
    }
    for _, item in ipairs(reader_items) do
        local key, label = item.key, item.label
        table.insert(buttons, {{
            text = label,
            checked_func = function() return Utils.getBool(key) end,
            enabled_func = readerAvailable,
            callback = function(tm)
                Utils.set(key, not Utils.getBool(key))
                if tm then tm:updateItems() end
                if touch_menu then touch_menu:updateItems() end
                QA.refreshQuickPanel()
                if _sliders_dialog then UIManager:close(_sliders_dialog); _sliders_dialog = nil end
                QA.showSlidersMenu(touch_menu, on_back)
            end,
        }})
    end

    table.insert(buttons, {})

    -- ---- General ----
    table.insert(buttons, {{
        text = _("Close"),
        callback = function()
            if _sliders_dialog then
                UIManager:close(_sliders_dialog)
                _sliders_dialog = nil
            end
            closeSettingsDialog()
        end,
    }})

    local dialog = ButtonDialog:new{
        title = _("Sliders"),
        title_align = "center",
        buttons = buttons,
        width = math.floor(Screen:getWidth() * 0.7),
        max_height = math.floor(Screen:getHeight() * 0.7),
    }
    if _sliders_dialog then UIManager:close(_sliders_dialog) end
    _sliders_dialog = dialog
    UIManager:show(dialog)
end

PLUGIN_STORE.show_add_button_menu = QA.showAddButtonMenu

-- ============================================================
-- Custom items
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
                        QA.showEditActionDialog(id, function() QA.refreshQuickPanel() end)
                    end,
                    on_delete = nil,
                }
            end
        end
    end

    local custom_list = Utils.getTable("qa_common_custom_list")
    for i = 1, #custom_list do
        local id = custom_list[i]
        local cfg = Utils.getTable("qa_common_custom")[id]
        if cfg then
            local symbol = getActionSymbol(id)
            local view_tag = " [" .. getActionViewFinal(id) .. "]"
            items[#items + 1] = {
                id = id,
                text = symbol .. cfg.label .. view_tag,
                is_builtin = false,
                on_edit = function()
                    QA.showCustomQADialog(id, function() QA.refreshQuickPanel() end)
                end,
                on_delete = function()
                    local custom_tbl = Utils.getTable("qa_common_custom")
                    custom_tbl[id] = nil
                    Utils.set("qa_common_custom", custom_tbl)
                    local list = Utils.getTable("qa_common_custom_list")
                    local new_list = {}
                    for __, lid in ipairs(list) do
                        if lid ~= id then table.insert(new_list, lid) end
                    end
                    Utils.set("qa_common_custom_list", new_list)
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

    items[#items + 1] = {
        text = _("Auto-add to panel on save"),
        checked_func = function()
            return Utils.getBool("qa_common_auto_add_to_panel")
        end,
        callback = function(touchmenu_instance)
            Utils.set("qa_common_auto_add_to_panel", not Utils.getBool("qa_common_auto_add_to_panel"))
            if touchmenu_instance then touchmenu_instance:updateItems() end
            QA.refreshQuickPanel()
        end,
    }

    items[#items + 1] = {
        text = "+ " .. _("New"),
        close_on_click = {"_active_dialog"},
        callback = function()
            QA.showCustomQADialog(nil, function() QA.refreshQuickPanel() end)
        end,
    }

    local builtin_items = {}
    for __, item in ipairs(getCustomItems()) do
        if item.is_builtin then
            table.insert(builtin_items, {
                text = item.text,
                close_on_click = {"_active_dialog"},
                callback = function() item.on_edit() end,
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
                callback = function() item.on_edit() end,
            })
        end
    end

    return items
end

-- ============================================================
-- Bar menu items -- forwards to Bars
-- ============================================================

function QA.getPanelMenuItems()
    return Bars.getPanelMenuItems()
end

function QA.getBottomBarMenuItems()
    return Bars.getBottomBarMenuItems()
end

function QA.getVerticalBarMenuItems()
    return Bars.getVerticalBarMenuItems()
end

function QA.showPanelSettings()
    Bars.showPanelSettings(showMenu, QA.buildRootMenuItems)
end

function QA.showBottombarSettings()
    Bars.showBottombarSettings(showMenu, QA.buildRootMenuItems)
end

function QA.showVerticalBarSettings()
    Bars.showVerticalBarSettings(showMenu, QA.buildRootMenuItems)
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
            if a_checked ~= b_checked then return a_checked end
            local a_is_common = (a.view == "common")
            local b_is_common = (b.view == "common")
            if a_is_common ~= b_is_common then return a_is_common end
            local a_prio = actions.getTypePriority(a.id)
            local b_prio = actions.getTypePriority(b.id)
            if a_prio ~= b_prio then return a_prio < b_prio end
            return a.label:lower() < b.label:lower()
        end)

        table.insert(items, {
            text = _("Select All Dedicated"),
            checked_func = function()
                local current_actions = actions.getAllAvailableActions()
                for __, action in ipairs(current_actions) do
                    if action.id and not (Utils.getTable("qa_common_custom")[action.id] and Utils.getTable("qa_common_custom")[action.id].action_type == "menu") then
                        if action.view ~= target_view then return false end
                    end
                end
                return true
            end,
            enabled = function()
                local current_actions = actions.getAllAvailableActions()
                for __, action in ipairs(current_actions) do
                    if action.id and not (Utils.getTable("qa_common_custom")[action.id] and Utils.getTable("qa_common_custom")[action.id].action_type == "menu") then
                        return true
                    end
                end
                return false
            end,
            callback = function(touchmenu_instance)
                local current_actions = actions.getAllAvailableActions()
                local all_checked = true
                for __, action in ipairs(current_actions) do
                    if action.id and not (Utils.getTable("qa_common_custom")[action.id] and Utils.getTable("qa_common_custom")[action.id].action_type == "menu") then
                        if action.view ~= target_view then all_checked = false; break end
                    end
                end
                for __, action in ipairs(current_actions) do
                    if not action.id then goto continue end
                    if Utils.getTable("qa_common_custom")[action.id] and Utils.getTable("qa_common_custom")[action.id].action_type == "menu" then
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
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
        })

        for __, action in ipairs(all_actions) do
            if not action.id then goto continue end
            local is_locked = (Utils.getTable("qa_common_custom")[action.id] and Utils.getTable("qa_common_custom")[action.id].action_type == "menu")
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
                    if touchmenu_instance then touchmenu_instance:updateItems() end
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
                return Utils.getBool("qa_common_context_filter")
            end,
            callback = function(touchmenu_instance)
                local p = PLUGIN_STORE.plugin_ref
                if p then
                    _G.__QUICKUI_CONFIG.qa_common_context_filter = not Utils.getBool("qa_common_context_filter")
                    Utils.saveConfig()
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end
            end,
        },
        {
            text_func = function()
                local actions_list = actions.getAllAvailableActions()
                local fm = 0
                for __, act in ipairs(actions_list) do
                    if act.view == "filemanager" then fm = fm + 1 end
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
                    if act.view == "reader" then rd = rd + 1 end
                end
                return string.format(_("Reader Dedicated (%d)"), rd)
            end,
            sub_item_table = buildDedicatedListItems("reader"),
        },
        {
            text = _("Reset to Defaults"),
            close_on_click = true,
            callback = function(touchmenu_instance)
                UIManager:show(ConfirmBox:new{
                    text = _("Reset all dedicated view settings to defaults?"),
                    ok_text = _("Reset"),
                    cancel_text = _("Cancel"),
                    ok_callback = function()
                        local p = PLUGIN_STORE.plugin_ref
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
                            if touchmenu_instance then touchmenu_instance:updateItems() end
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

function QA.showInterfaceFilter()
    closeSettingsDialog()
    local filter_items = QA.getInterfaceFilterMenuItems()
    if filter_items and #filter_items > 0 then
        showMenu(filter_items, "Interface Filter", nil, nil, QA.buildRootMenuItems())
    else
        UIManager:show(InfoMessage:new{
            text = "Interface Filter not available",
            timeout = 2,
        })
    end
end

-- ============================================================
-- Root menu
-- ============================================================

function QA.buildRootMenuItems()
    local items = {}

    table.insert(items, {
        text = _("Enable Panel"),
        checked_func = function() return Utils.getBool("qa_panel_enabled") end,
        callback = function()
            local new_val = not Utils.getBool("qa_panel_enabled")
            Utils.set("qa_panel_enabled", new_val)
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
                ok_callback = function() UIManager:restartKOReader() end,
            })
        end,
    })

    table.insert(items, {
        text = _("Enable Bottom Bar"),
        checked_func = function() return Utils.getBool("qa_bb_enabled") end,
        callback = function()
            local new_val = not Utils.getBool("qa_bb_enabled")
            Utils.set("qa_bb_enabled", new_val)
            local bb = PLUGIN_STORE.bottombar
            if bb then bb.refresh() end
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
                ok_callback = function() UIManager:restartKOReader() end,
            })
        end,
    })

    table.insert(items, {
        text = _("Enable Vertical Bar"),
        checked_func = function() return Utils.getBool("qa_vb_enabled", false) end,
        callback = function()
            local new_val = not Utils.getBool("qa_vb_enabled", false)
            Utils.set("qa_vb_enabled", new_val)
            local vb = PLUGIN_STORE.verticalbar
            if vb then
                if new_val then
                    vb.show()
                else
                    vb.hide()
                end
            end
            UIManager:show(ConfirmBox:new{
                text = _("Restart required.\n\nRestart KOReader now?"),
                ok_text = _("Restart"),
                cancel_text = _("Later"),
                ok_callback = function() UIManager:restartKOReader() end,
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
        text = _("Reader Sliders"),
        enabled_func = function()
            local RUI = require("apps/reader/readerui")
            return RUI and RUI.instance ~= nil
        end,
        close_on_click = true,
        callback = function()
            closeSettingsDialog()
            require("qui_actions/qa_reader_sliders").show()
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

    table.insert(items, {
        text = _("Vertical Bar"),
        sub_item_table = QA.getVerticalBarMenuItems(),
    })

    local default_items = Utils.buildDefaultMenuItems({"qa_common", "qa_panel", "qa_bb", "qa_vb"}, function()
        QA.refreshQuickPanel()
        local bb = PLUGIN_STORE.bottombar
        if bb then bb.refresh() end
        local vb = PLUGIN_STORE.verticalbar
        if vb then vb.refresh() end
    end)
    for __, item in ipairs(default_items) do
        table.insert(items, item)
    end

    return items
end

-- ============================================================
-- Show Settings
-- ============================================================

function QA.showSettings()
    closeSettingsDialog()
    local root_items = QA.buildRootMenuItems()
    _root_items = root_items
    showMenu(root_items, _("Quick Actions Settings"), nil, nil, root_items)
end

function QA.getMenuItems()
    return {}
end

QA.showMenu = showMenu

-- Expose the root-menu builder for callers (qa_bar_settings.lua's spin
-- callbacks) that need to re-open a bar's settings without threading the
-- function through every call site.
PLUGIN_STORE.build_root_menu_items = QA.buildRootMenuItems

return QA
