--[[
QuickUI - Quick Actions Bar Editors & Bar Settings

Holds the two per-action editors (built-in + custom) and the three
per-container settings menus (panel / bottom bar / vertical bar), so all
the "which bar am I editing?" logic lives in one place.

Every editor takes a `source` tag identifying the container the long-press
came from:
    nil / "panel"  -> qa_panel_slots
    "bottombar"    -> qa_bb_tabs
    "verticalbar"  -> qa_vb_slots
]]

local logger = require("logger")
local _ = require("gettext")
local Screen = require("device").screen
local Device = require("device")
local UIManager = require("ui/uimanager")
local Geom = require("ui/geometry")

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

local getDefaultViewForActionType = actions.getDefaultViewForActionType

local Bars = {}

local PLUGIN_STORE = _G.__QUICKUI_PLUGIN_STORE or {}
_G.__QUICKUI_PLUGIN_STORE = PLUGIN_STORE

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
-- Dialog registry (shared with qa_settings.lua via PLUGIN_STORE)
-- ============================================================
-- The main module owns the actual dialog references; we only need a couple
-- of them for the editors' _active_dialog / _view_dialog / _choice_dialog
-- bookkeeping. Aliasing through PLUGIN_STORE keeps a single source of truth.

local function closeMainDialog(exclude)
    -- Normalise `exclude` to a set so we can honour it in the local checks
    -- below before handing it off to qa_settings' own closer.
    local ex = {}
    if type(exclude) == "string" then
        ex[exclude] = true
    elseif type(exclude) == "table" then
        for k, v in pairs(exclude) do ex[k] = v end
    end

    -- Close the bar-editor dialogs THIS module owns. They live on the shared
    -- PLUGIN_STORE, not on qa_settings.lua's module locals, so its
    -- close_settings_dialog cannot reach them -- which is exactly why an
    -- edit dialog used to be impossible to dismiss: tap-outside and Cancel
    -- both route here, and here only qa_settings' own dialogs were closed.
    if not ex["_bar_active_dialog"] and PLUGIN_STORE._bar_active_dialog then
        UIManager:close(PLUGIN_STORE._bar_active_dialog)
        PLUGIN_STORE._bar_active_dialog = nil
    end
    if not ex["_bar_view_dialog"] and PLUGIN_STORE._bar_view_dialog then
        UIManager:close(PLUGIN_STORE._bar_view_dialog)
        PLUGIN_STORE._bar_view_dialog = nil
    end
    if not ex["_bar_choice_dialog"] and PLUGIN_STORE._bar_choice_dialog then
        UIManager:close(PLUGIN_STORE._bar_choice_dialog)
        PLUGIN_STORE._bar_choice_dialog = nil
    end

    -- Then the main module's own dialogs, unchanged.
    local fn = PLUGIN_STORE.close_settings_dialog
    if fn then fn(exclude) end
end

-- ============================================================
-- Source-aware list helpers
-- ============================================================

local function sourceKey(source)
    if source == "bottombar" then return "qa_bb_tabs" end
    if source == "verticalbar" then return "qa_vb_slots" end
    return "qa_panel_slots"
end

local function sourceList(source)
    local key = sourceKey(source)
    if key == "qa_bb_tabs" then
        return Utils.get("qa_bb_tabs", {})
    end
    return Utils.getTable(key)
end

local function sourceSet(source, list)
    local key = sourceKey(source)
    Utils.set(key, list)
    if source == "bottombar" then
        if PLUGIN_STORE.bottombar then PLUGIN_STORE.bottombar.refresh() end
    elseif source == "verticalbar" then
        if PLUGIN_STORE.verticalbar then PLUGIN_STORE.verticalbar.refresh() end
    else
        if PLUGIN_STORE.refresh_quick_panel then PLUGIN_STORE.refresh_quick_panel() end
    end
end

local function sourceRefresh(source)
    if source == "bottombar" then
        if PLUGIN_STORE.bottombar then PLUGIN_STORE.bottombar.refresh() end
    elseif source == "verticalbar" then
        if PLUGIN_STORE.verticalbar then PLUGIN_STORE.verticalbar.refresh() end
    else
        if PLUGIN_STORE.refresh_quick_panel then PLUGIN_STORE.refresh_quick_panel() end
    end
end

local function listContains(list, id)
    for __, v in ipairs(list) do
        if v == id then return true end
    end
    return false
end

-- ============================================================
-- State-based nav row (shared by both editors)
-- ============================================================
-- When the action is IN the source it was opened from, the editor shows
-- the within-source nudge (◀ pos/total ▶ Remove). When it is NOT, there is
-- no position to nudge, so this row instead offers add/remove across the
-- three containers. Returns a button array.
local function buildCrossSourceRow(action_id, cur_source, on_done)
    local in_panel = listContains(sourceList("panel"), action_id)
    local in_bar   = listContains(sourceList("bottombar"), action_id)
    local in_vb    = listContains(sourceList("verticalbar"), action_id)

    local function toggle(which, present)
        return function()
            closeMainDialog()
            local list = sourceList(which)
            if present then
                local new = {}
                for __, v in ipairs(list) do
                    if v ~= action_id then new[#new + 1] = v end
                end
                sourceSet(which, new)
            else
                list[#list + 1] = action_id
                sourceSet(which, list)
            end
            if on_done then on_done() end
        end
    end

    local row = {}

    if cur_source == "verticalbar" then
        table.insert(row, { text = in_vb and _("Remove from Vertical Bar") or _("Add to Vertical Bar"),
                            callback = toggle("verticalbar", in_vb) })
        table.insert(row, { text = in_panel and _("Remove from Panel") or _("Add to Panel"),
                            callback = toggle("panel", in_panel) })
        table.insert(row, { text = in_bar and _("Remove from Bottom Bar") or _("Add to Bottom Bar"),
                            callback = toggle("bottombar", in_bar) })
    elseif cur_source == "bottombar" then
        table.insert(row, { text = in_bar and _("Remove from Bottom Bar") or _("Add to Bottom Bar"),
                            callback = toggle("bottombar", in_bar) })
        table.insert(row, { text = in_panel and _("Remove from Panel") or _("Add to Panel"),
                            callback = toggle("panel", in_panel) })
        table.insert(row, { text = in_vb and _("Remove from Vertical Bar") or _("Add to Vertical Bar"),
                            callback = toggle("verticalbar", in_vb) })
    else
        table.insert(row, { text = in_panel and _("Remove from Panel") or _("Add to Panel"),
                            callback = toggle("panel", in_panel) })
        table.insert(row, { text = in_bar and _("Remove from Bottom Bar") or _("Add to Bottom Bar"),
                            callback = toggle("bottombar", in_bar) })
        table.insert(row, { text = in_vb and _("Remove from Vertical Bar") or _("Add to Vertical Bar"),
                            callback = toggle("verticalbar", in_vb) })
    end

    return row
end

-- ============================================================
-- Edit Built-in Action Dialog
-- ============================================================

function Bars.showEditActionDialog(action_id, on_done, source)
    local action = getAction(action_id)
    if not action then return end

    local cur_source = source or "panel"

    local current_label = action.label
    local current_icon = action.icon
    local current_view = getActionViewFinal(action_id)

    local view_options = { "common", "filemanager", "reader" }
    local view_labels = {
        common = _("Common"),
        filemanager = _("Filemanager Dedicated"),
        reader = _("Reader Dedicated"),
    }

    local function getList()        return sourceList(cur_source)      end
    local function setList(list)    return sourceSet(cur_source, list) end
    local function refreshCurrent() return sourceRefresh(cur_source)   end

    local function getCurrentPosition()
        local list = getList()
        for i, id in ipairs(list) do
            if id == action_id then return i, #list end
        end
        return nil, #list
    end

    local function removeFromList()
        local list = getList()
        local new = {}
        for __, id in ipairs(list) do
            if id ~= action_id then new[#new + 1] = id end
        end
        setList(new)
    end

    local function moveLeft()
        local list = getList()
        local idx
        for i, id in ipairs(list) do
            if id == action_id then idx = i; break end
        end
        if idx and idx > 1 then
            list[idx], list[idx-1] = list[idx-1], list[idx]
            setList(list)
        end
    end

    local function moveRight()
        local list = getList()
        local idx
        for i, id in ipairs(list) do
            if id == action_id then idx = i; break end
        end
        if idx and idx < #list then
            list[idx], list[idx+1] = list[idx+1], list[idx]
            setList(list)
        end
    end

    local function openSortDialog()
        local list = getList()
        local sort_items = {}
        for i, id in ipairs(list) do
            sort_items[#sort_items + 1] = { text = getLabelForAction(id), orig_item = id }
        end
        local title = (cur_source == "bottombar") and _("Arrange Tabs") or _("Arrange Buttons")
        local sort_dialog = SortWidget:new{
            title = title,
            item_table = sort_items,
            covers_fullscreen = true,
            callback = function()
                local new = {}
                for j = 1, #sort_items do
                    new[#new + 1] = sort_items[j].orig_item
                end
                setList(new)
                if on_done then on_done() end
            end,
        }
        UIManager:show(sort_dialog)
    end

    local function rebuildDialog()
        local _active_dialog = PLUGIN_STORE._bar_active_dialog
        if _active_dialog then
            UIManager:close(_active_dialog)
            PLUGIN_STORE._bar_active_dialog = nil
        end
        local _view_dialog = PLUGIN_STORE._bar_view_dialog
        if _view_dialog then
            UIManager:close(_view_dialog)
            PLUGIN_STORE._bar_view_dialog = nil
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
            return _("Filter") .. ": " .. view_labels[current_view]
        end

        local fields = {
            { description = _("Name"), text = current_label, hint = _("Action name...") }
        }

        local pos, total = getCurrentPosition()

        local nav_row
        if pos then
            nav_row = {}
            table.insert(nav_row, {
                text = icon_picker.nerdIconChar("nerd:EE91") or "◀",
                enabled = (pos > 1),
                callback = function()
                    closeMainDialog()
                    moveLeft()
                    rebuildDialog()
                end
            })
            table.insert(nav_row, { text = pos .. "/" .. total, callback = function()
                closeMainDialog()
                openSortDialog()
            end })
            table.insert(nav_row, {
                text = icon_picker.nerdIconChar("nerd:EE92") or "▶",
                enabled = (pos < total),
                callback = function()
                    closeMainDialog()
                    moveRight()
                    rebuildDialog()
                end
            })
            table.insert(nav_row, { text = _("Remove"), callback = function()
                closeMainDialog()
                removeFromList()
                if on_done then on_done() end
            end })
        else
            nav_row = buildCrossSourceRow(action_id, cur_source, on_done)
        end

        local last_row = {
            { text = _("Cancel"), id = "close", callback = function()
                closeMainDialog()
            end },
            { text = _("Action Pool"), callback = function()
                closeMainDialog()
                if cur_source == "bottombar" then
                    local bb = PLUGIN_STORE.bottombar
                    if bb and bb.showAddTabMenu then
                        bb.showAddTabMenu(function()
                            if bb.refresh then bb.refresh() end
                            Bars.showEditActionDialog(action_id, on_done, cur_source)
                        end)
                    end
                elseif cur_source == "verticalbar" then
                    local vb = PLUGIN_STORE.verticalbar
                    if vb and vb.showAddButtonMenu then
                        vb.showAddButtonMenu(function()
                            if vb.refresh then vb.refresh() end
                            Bars.showEditActionDialog(action_id, on_done, cur_source)
                        end)
                    end
                else
                    local showAdd = PLUGIN_STORE.show_add_button_menu
                    if showAdd then
                        showAdd(nil, function()
                            Bars.showEditActionDialog(action_id, on_done, cur_source)
                        end)
                    end
                end
            end },
            { text = _("New"), callback = function()
                closeMainDialog()
                Bars.showCustomQADialog(nil, function()
                    if on_done then on_done() end
                end, cur_source)
            end },
            { text = _("Save"), is_enter_default = true, callback = function()
                local dlg = PLUGIN_STORE._bar_active_dialog
                if not dlg then return end
                local inputs = dlg:getFields()
                local new_label = inputs[1] or ""
                if new_label == "" then
                    UIManager:show(InfoMessage:new{ text = _("Please enter a name"), timeout = 2 })
                    return
                end
                closeMainDialog()

                local overrides = Utils.getTable("qa_common_builtin_overrides")
                if not overrides[action_id] then
                    overrides[action_id] = {}
                end
                overrides[action_id].label = new_label
                overrides[action_id].icon = current_icon
                overrides[action_id].view = current_view
                Utils.set("qa_common_builtin_overrides", overrides)
                refreshCurrent()
                if on_done then on_done() end
            end },
        }

        local buttons = {
            {
                { text = viewButtonText(), callback = function()
                    closeMainDialog()
                    local view_buttons = {}
                    for __, v in ipairs(view_options) do
                        local _v = v
                        table.insert(view_buttons, {{
                            text = (current_view == _v and "✓ " or "  ") .. view_labels[_v],
                            callback = function()
                                local vd = PLUGIN_STORE._bar_view_dialog
                                if vd then UIManager:close(vd); PLUGIN_STORE._bar_view_dialog = nil end
                                current_view = _v
                                rebuildDialog()
                            end,
                        }})
                    end
                    table.insert(view_buttons, {{
                        text = _("Back"),
                        callback = function()
                            local vd = PLUGIN_STORE._bar_view_dialog
                            if vd then UIManager:close(vd); PLUGIN_STORE._bar_view_dialog = nil end
                            rebuildDialog()
                        end,
                    }})
                    local vd = ButtonDialog:new{
                        title = _("Select Filter"),
                        title_align = "center",
                        buttons = view_buttons,
                        width = math.floor(Screen:getWidth() * 0.7),
                    }
                    PLUGIN_STORE._bar_view_dialog = vd
                    UIManager:show(vd)
                end },
                { text = iconButtonText(), callback = function()
                    closeMainDialog()
                    icon_picker.showIconPicker(function(new_icon)
                        current_icon = new_icon
                        rebuildDialog()
                    end, current_icon)
                end },
            },
            nav_row,
            last_row,
        }

        local dlg = MultiInputDialog:new{
            title = _("Edit Quick Action - Built-in Action"),
            fields = fields,
            tap_close_callback = function()
                closeMainDialog()
            end,
            buttons = buttons,
        }
        PLUGIN_STORE._bar_active_dialog = dlg
        UIManager:show(dlg)
    end

    rebuildDialog()
end

-- ============================================================
-- Custom QA Dialog
-- ============================================================

function Bars.showCustomQADialog(qa_id, on_done, source)
    closeMainDialog()

    local cur_source = source or "panel"

    local custom = Utils.getTable("qa_common_custom")
    local cfg = qa_id and custom[qa_id] or {}
    local chosen_icon = cfg.icon
    local dlg_title = qa_id and _("Edit Quick Action - Custom Action") or _("New Quick Action")
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
        filemanager = _("Filemanager Dedicated"),
        reader = _("Reader Dedicated"),
    }

    local function getList()        return sourceList(cur_source)      end
    local function setList(list)    return sourceSet(cur_source, list) end
    local function refreshCurrent() return sourceRefresh(cur_source)   end

    local function getCurrentPosition()
        local list = getList()
        for i, id in ipairs(list) do
            if id == qa_id then return i, #list end
        end
        return nil, #list
    end

    local function removeFromList()
        local list = getList()
        local new = {}
        for __, id in ipairs(list) do
            if id ~= qa_id then new[#new + 1] = id end
        end
        setList(new)
    end

    local function moveLeft()
        local list = getList()
        local idx
        for i, id in ipairs(list) do
            if id == qa_id then idx = i; break end
        end
        if idx and idx > 1 then
            list[idx], list[idx-1] = list[idx-1], list[idx]
            setList(list)
        end
    end

    local function moveRight()
        local list = getList()
        local idx
        for i, id in ipairs(list) do
            if id == qa_id then idx = i; break end
        end
        if idx and idx < #list then
            list[idx], list[idx+1] = list[idx+1], list[idx]
            setList(list)
        end
    end

    local function openSortDialog()
        local list = getList()
        local sort_items = {}
        for i, id in ipairs(list) do
            sort_items[#sort_items + 1] = { text = getLabelForAction(id), orig_item = id }
        end
        local title = (cur_source == "bottombar") and _("Arrange Tabs") or _("Arrange Buttons")
        local sort_dialog = SortWidget:new{
            title = title,
            item_table = sort_items,
            covers_fullscreen = true,
            callback = function()
                local new = {}
                for j = 1, #sort_items do
                    new[#new + 1] = sort_items[j].orig_item
                end
                setList(new)
                if on_done then on_done() end
            end,
        }
        UIManager:show(sort_dialog)
    end

    local function commitQA(final_label, path, collections, icon, plugin_key, plugin_method, dispatcher_action, dispatcher_value, menu_path, user_view)
        local list = Utils.getTable("qa_common_custom_list")
        local max_n = 0
        for __, id in ipairs(list) do
            local n = tonumber(id:match("^custom_qa_(%d+)$"))
            if n and n > max_n then max_n = n end
        end
        local final_id = qa_id or ("custom_qa_" .. (max_n + 1))

        local custom_tbl = Utils.getTable("qa_common_custom")
        local custom_list = Utils.getTable("qa_common_custom_list")

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
        Utils.set("qa_common_custom", custom_tbl)
        if PLUGIN_STORE.bottombar then
            PLUGIN_STORE.bottombar.refresh()
        end
        if PLUGIN_STORE.verticalbar then
            PLUGIN_STORE.verticalbar.refresh()
        end

        local auto_add = Utils.getBool("qa_common_auto_add_to_panel")
        if source ~= "bottombar" and source ~= "verticalbar" and auto_add then
            -- Historical behaviour: new custom actions land in the panel.
            -- Kept for panel-source creation. When created from the bottom
            -- bar or the vertical bar, the action is instead added to the
            -- bar it was created from, matching the panel's auto-add.
            local slots = Utils.getTable("qa_panel_slots")
            local already_exists = false
            for __, sid in ipairs(slots) do
                if sid == final_id then already_exists = true; break end
            end
            if not already_exists then
                if #slots < 66 then
                    slots[#slots + 1] = final_id
                    Utils.set("qa_panel_slots", slots)
                else
                    UIManager:show(InfoMessage:new{
                        text = string.format(_("Panel is full (max 66 buttons), cannot auto-add.")),
                        timeout = 3,
                    })
                end
            end
        elseif source == "bottombar" and auto_add then
            local tabs = Utils.get("qa_bb_tabs", {})
            local already_exists = false
            for __, sid in ipairs(tabs) do
                if sid == final_id then already_exists = true; break end
            end
            if not already_exists then
                tabs[#tabs + 1] = final_id
                Utils.set("qa_bb_tabs", tabs)
            end
        elseif source == "verticalbar" and auto_add then
            local slots = Utils.getTable("qa_vb_slots")
            local already_exists = false
            for __, sid in ipairs(slots) do
                if sid == final_id then already_exists = true; break end
            end
            if not already_exists then
                slots[#slots + 1] = final_id
                Utils.set("qa_vb_slots", slots)
            end
        end

        if not qa_id then
            custom_list[#custom_list + 1] = final_id
            Utils.set("qa_common_custom_list", custom_list)
        end

        if on_done then on_done() end
    end

    local buildSaveDialog = nil

    local function cancelActionPicker()
        if not current_action_type and not qa_id then
            if on_done then on_done() end
        else
            local dlg = PLUGIN_STORE._bar_active_dialog
            if dlg then UIManager:close(dlg); PLUGIN_STORE._bar_active_dialog = nil end
            if buildSaveDialog then
                buildSaveDialog(false)
            end
        end
    end

    local function openActionPicker()
        local dlg = PLUGIN_STORE._bar_active_dialog
        if dlg then
            UIManager:close(dlg)
            PLUGIN_STORE._bar_active_dialog = nil
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

        local choice = ButtonDialog:new{
            title = _("Action Type"),
            title_align = "center",
            buttons = {
                { { text = _("Folder"), callback = function()
                    closeMainDialog()
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
                            closeMainDialog()
                            if buildSaveDialog then
                                buildSaveDialog(true)
                            end
                        end,
                        onCancel = function()
                            closeMainDialog()
                            openActionPicker()
                        end,
                    }
                    UIManager:show(pc)
                end } },
                { { text = _("Collections"), enabled = (#collections > 0), callback = function()
                    closeMainDialog()
                    local coll_buttons = {}
                    for __, name in ipairs(collections) do
                        local _name = name
                        coll_buttons[#coll_buttons + 1] = {{ text = name, callback = function()
                            closeMainDialog()
                            if PLUGIN_STORE._coll_picker then
                                UIManager:close(PLUGIN_STORE._coll_picker)
                                PLUGIN_STORE._coll_picker = nil
                            end
                            if PLUGIN_STORE._bar_choice_dialog then
                                UIManager:close(PLUGIN_STORE._bar_choice_dialog)
                                PLUGIN_STORE._bar_choice_dialog = nil
                            end
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
                        if PLUGIN_STORE._coll_picker then
                            UIManager:close(PLUGIN_STORE._coll_picker)
                            PLUGIN_STORE._coll_picker = nil
                        end
                        openActionPicker()
                    end }}
                    local cp = ButtonDialog:new{
                        title = _("Select collections"),
                        title_align = "center",
                        buttons = coll_buttons,
                        width = math.floor(Screen:getWidth() * 0.7),
                    }
                    PLUGIN_STORE._coll_picker = cp
                    UIManager:show(cp)
                end } },
                { { text = _("Plugin or Patch"), callback = function()
                    closeMainDialog()
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
                        function() cancelActionPicker() end,
                        function() buildSaveDialog(false) end,
                        function() openActionPicker() end,
                        function() Bars.showSettings() end
                    )
                end } },
                { { text = _("System Action"), callback = function()
                    if PLUGIN_STORE._system_dialog then
                        UIManager:close(PLUGIN_STORE._system_dialog)
                        PLUGIN_STORE._system_dialog = nil
                    end
                    closeMainDialog()
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
                        function() cancelActionPicker() end,
                        function() buildSaveDialog(false) end,
                        function() openActionPicker() end,
                        function() Bars.showSettings() end
                    )
                end } },
                { { text = _("Record Menu Action"), callback = function()
                    closeMainDialog()
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
                        closeMainDialog()
                        if PLUGIN_STORE._bar_choice_dialog then
                            UIManager:close(PLUGIN_STORE._bar_choice_dialog)
                            PLUGIN_STORE._bar_choice_dialog = nil
                        end
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
                    if PLUGIN_STORE._bar_choice_dialog then
                        UIManager:close(PLUGIN_STORE._bar_choice_dialog)
                        PLUGIN_STORE._bar_choice_dialog = nil
                    end
                    if buildSaveDialog then
                        buildSaveDialog(false)
                    end
                end } },
            }
        }
        PLUGIN_STORE._bar_choice_dialog = choice
        UIManager:show(choice)
    end

    buildSaveDialog = function(update_name_with_title)
        if PLUGIN_STORE._coll_picker then
            UIManager:close(PLUGIN_STORE._coll_picker)
            PLUGIN_STORE._coll_picker = nil
        end
        if PLUGIN_STORE._bar_choice_dialog then
            UIManager:close(PLUGIN_STORE._bar_choice_dialog)
            PLUGIN_STORE._bar_choice_dialog = nil
        end
        if PLUGIN_STORE._bar_active_dialog then
            UIManager:close(PLUGIN_STORE._bar_active_dialog)
            PLUGIN_STORE._bar_active_dialog = nil
        end
        if PLUGIN_STORE._bar_view_dialog then
            UIManager:close(PLUGIN_STORE._bar_view_dialog)
            PLUGIN_STORE._bar_view_dialog = nil
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
                return _("Filter") .. ": " .. view_labels[current_view] .. " (" .. _("locked") .. ")"
            else
                return _("Filter") .. ": " .. view_labels[current_view]
            end
        end

        local fields = {
            { description = _("Name"), text = existing_label, hint = _("Action name...") },
        }

        local pos, total = getCurrentPosition()
        local is_new = (qa_id == nil)

        local nav_row = nil
        if not is_new then
            if pos then
                nav_row = {}
                table.insert(nav_row, {
                    text = icon_picker.nerdIconChar("nerd:EE91") or "◀",
                    enabled = (pos > 1),
                    callback = function()
                        closeMainDialog()
                        moveLeft()
                        buildSaveDialog(false)
                    end
                })
                table.insert(nav_row, { text = pos .. "/" .. total, callback = function()
                    closeMainDialog()
                    openSortDialog()
                end })
                table.insert(nav_row, {
                    text = icon_picker.nerdIconChar("nerd:EE92") or "▶",
                    enabled = (pos < total),
                    callback = function()
                        closeMainDialog()
                        moveRight()
                        buildSaveDialog(false)
                    end
                })
                table.insert(nav_row, { text = _("Remove"), callback = function()
                    closeMainDialog()
                    removeFromList()
                    if on_done then on_done() end
                end })
            else
                nav_row = buildCrossSourceRow(qa_id, cur_source, on_done)
            end
        end

        local last_row = {
            { text = _("Cancel"), id = "close", callback = function()
                closeMainDialog()
                if not qa_id and not current_action_type then
                    if on_done then on_done() end
                end
            end },
        }

        if qa_id then
            table.insert(last_row, { text = _("Delete"), callback = function()
                closeMainDialog()
                UIManager:show(ConfirmBox:new{
                    text = string.format(_("Delete quick action \"%s\"?"), existing_label),
                    ok_text = _("Delete"),
                    cancel_text = _("Cancel"),
                    ok_callback = function()
                        local custom_tbl = Utils.getTable("qa_common_custom")
                        custom_tbl[qa_id] = nil
                        Utils.set("qa_common_custom", custom_tbl)
                        local list = Utils.getTable("qa_common_custom_list")
                        local new_list = {}
                        for __, id in ipairs(list) do
                            if id ~= qa_id then
                                table.insert(new_list, id)
                            end
                        end
                        Utils.set("qa_common_custom_list", new_list)
                        removeFromList()
                        if on_done then on_done() end
                    end,
                })
            end })
        end

        table.insert(last_row, { text = _("Action Pool"), callback = function()
            closeMainDialog()
            if cur_source == "bottombar" then
                local bb = PLUGIN_STORE.bottombar
                if bb and bb.showAddTabMenu then
                    bb.showAddTabMenu(function()
                        if bb.refresh then bb.refresh() end
                        Bars.showCustomQADialog(qa_id, on_done, cur_source)
                    end)
                end
            elseif cur_source == "verticalbar" then
                local vb = PLUGIN_STORE.verticalbar
                if vb and vb.showAddButtonMenu then
                    vb.showAddButtonMenu(function()
                        if vb.refresh then vb.refresh() end
                        Bars.showCustomQADialog(qa_id, on_done, cur_source)
                    end)
                end
            else
                local showAdd = PLUGIN_STORE.show_add_button_menu
                if showAdd then
                    showAdd(nil, function()
                        Bars.showCustomQADialog(qa_id, on_done, cur_source)
                    end)
                end
            end
        end })

        if qa_id then
            table.insert(last_row, { text = _("New"), callback = function()
                closeMainDialog()
                Bars.showCustomQADialog(nil, function()
                    if on_done then on_done() end
                end, cur_source)
            end })
        end

        table.insert(last_row, { text = _("Save"), is_enter_default = true, callback = function()
            local dlg = PLUGIN_STORE._bar_active_dialog
            if not dlg then return end
            local inputs = dlg:getFields()
            local final_label = inputs[1] or ""
            if final_label == "" then
                UIManager:show(InfoMessage:new{ text = _("Please enter a name"), timeout = 2 })
                return
            end
            if not current_action_type then
                UIManager:show(InfoMessage:new{ text = _("Please select an action type"), timeout = 2 })
                return
            end

            closeMainDialog()

            local default_icon = "nerd:F114"
            if current_action_type == "plugin" then
                default_icon = "nerd:F1B2"
            elseif current_action_type == "dispatcher" then
                default_icon = "nerd:F08D"
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
            {
                { text = action_label, callback = function()
                    closeMainDialog()
                    openActionPicker()
                end },
            },
            {
                { text = viewButtonText(), enabled = (current_action_type ~= "menu"), callback = function()
                    if current_action_type == "menu" then return end
                    closeMainDialog()
                    local view_buttons = {}
                    for __, v in ipairs(view_options) do
                        local _v = v
                        table.insert(view_buttons, {{
                            text = (current_view == _v and "✓ " or "  ") .. view_labels[_v],
                            callback = function()
                                local vd = PLUGIN_STORE._bar_view_dialog
                                if vd then UIManager:close(vd); PLUGIN_STORE._bar_view_dialog = nil end
                                current_view = _v
                                buildSaveDialog(false)
                            end,
                        }})
                    end
                    table.insert(view_buttons, {{
                        text = _("Back"),
                        callback = function()
                            local vd = PLUGIN_STORE._bar_view_dialog
                            if vd then UIManager:close(vd); PLUGIN_STORE._bar_view_dialog = nil end
                            buildSaveDialog(false)
                        end,
                    }})
                    local vd = ButtonDialog:new{
                        title = _("Select Filter"),
                        title_align = "center",
                        buttons = view_buttons,
                        width = math.floor(Screen:getWidth() * 0.7),
                    }
                    PLUGIN_STORE._bar_view_dialog = vd
                    UIManager:show(vd)
                end },
                { text = iconButtonText(), callback = function()
                    closeMainDialog()
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
                end },
            },
        }

        if nav_row then
            table.insert(buttons, nav_row)
        end

        table.insert(buttons, last_row)

        local dlg = MultiInputDialog:new{
            title = dlg_title,
            fields = fields,
            tap_close_callback = function()
                closeMainDialog()
                if not qa_id and not current_action_type then
                    if on_done then on_done() end
                end
            end,
            buttons = buttons,
        }
        PLUGIN_STORE._bar_active_dialog = dlg
        UIManager:show(dlg)
    end

    buildSaveDialog(false)
end

-- ============================================================
-- Bar settings menus (panel / bottom bar / vertical bar)
-- ============================================================

function Bars.getPanelMenuItems()
    local items = {}

    items[#items + 1] = {
        text = _("Tab Icon") .. ": " .. Utils.getString("qa_common_tab_icon", "star.empty"),
        close_on_click = true,
        callback = function()
            closeMainDialog()
            icon_picker.showIconPicker(
                function(file_path)
                    if file_path then
                        local filename_with_ext = file_path:match("([^/]+)$")
                        local filename = filename_with_ext:gsub("%.[^%.]+$", "")
                        Utils.set("qa_common_tab_icon", filename)
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
            local slots = Utils.getTable("qa_panel_slots")
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
                    Utils.set("qa_panel_slots", new_slots)
                    if PLUGIN_STORE.refresh_quick_panel then PLUGIN_STORE.refresh_quick_panel() end
                end,
            }
            UIManager:show(sort_dialog)
        end,
    }

    items[#items + 1] = {
        text = _("Add Button"),
        close_on_click = true,
        callback = function()
            if PLUGIN_STORE.refresh_quick_panel then PLUGIN_STORE.refresh_quick_panel() end
            local showAdd = PLUGIN_STORE.show_add_button_menu
            if showAdd then
                showAdd(nil, function()
                    Bars.showPanelSettings()
                end)
            end
        end,
    }

    items[#items + 1] = {
        text = _("Button Shape"),
        sub_item_table = {
            {
                text = _("Round"),
                radio = true,
                checked_func = function()
                    return Utils.getString("qa_panel_shape", "round") == "round"
                end,
                callback = function(touchmenu_instance)
                    Utils.set("qa_panel_shape", "round")
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                    if PLUGIN_STORE.refresh_quick_panel then PLUGIN_STORE.refresh_quick_panel() end
                end,
            },
            {
                text = _("Rounded Square"),
                radio = true,
                checked_func = function()
                    return Utils.getString("qa_panel_shape", "round") == "square_round"
                end,
                callback = function(touchmenu_instance)
                    Utils.set("qa_panel_shape", "square_round")
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                    if PLUGIN_STORE.refresh_quick_panel then PLUGIN_STORE.refresh_quick_panel() end
                end,
            },
            {
                text = _("Bare"),
                radio = true,
                checked_func = function()
                    return Utils.getString("qa_panel_shape", "round") == "bare"
                end,
                callback = function(touchmenu_instance)
                    Utils.set("qa_panel_shape", "bare")
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                    if PLUGIN_STORE.refresh_quick_panel then PLUGIN_STORE.refresh_quick_panel() end
                end,
            },
        },
    }

    items[#items + 1] = {
        text = _("Button Background"),
        enabled = function()
            return Utils.getString("qa_panel_shape", "round") ~= "bare"
        end,
        sub_item_table = {
            {
                text = _("Transparent"),
                radio = true,
                checked_func = function()
                    return Utils.getString("qa_panel_bg", "flat") == "transparent"
                end,
                callback = function(touchmenu_instance)
                    Utils.set("qa_panel_bg", "transparent")
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                    if PLUGIN_STORE.refresh_quick_panel then PLUGIN_STORE.refresh_quick_panel() end
                end,
            },
            {
                text = _("Solid"),
                radio = true,
                checked_func = function()
                    return Utils.getString("qa_panel_bg", "flat") == "solid"
                end,
                callback = function(touchmenu_instance)
                    Utils.set("qa_panel_bg", "solid")
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                    if PLUGIN_STORE.refresh_quick_panel then PLUGIN_STORE.refresh_quick_panel() end
                end,
            },
            {
                text = _("Light Gray"),
                radio = true,
                checked_func = function()
                    return Utils.getString("qa_panel_bg", "flat") == "flat"
                end,
                callback = function(touchmenu_instance)
                    Utils.set("qa_panel_bg", "flat")
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                    if PLUGIN_STORE.refresh_quick_panel then PLUGIN_STORE.refresh_quick_panel() end
                end,
            },
        },
    }

    items[#items + 1] = {
        text = _("Show Labels"),
        checked_func = function()
            return Utils.getBool("qa_panel_labels", false)
        end,
        callback = function(touchmenu_instance)
            Utils.set("qa_panel_labels", not Utils.getBool("qa_panel_labels", false))
            if touchmenu_instance then touchmenu_instance:updateItems() end
            if PLUGIN_STORE.refresh_quick_panel then PLUGIN_STORE.refresh_quick_panel() end
        end,
    }

    items[#items + 1] = {
        text_func = function()
            return _("Button Size") .. ": " .. Utils.getNumber("qa_panel_button_size_pct", 100) .. "%"
        end,
        close_on_click = true,
        callback = function(touchmenu_instance)
            closeMainDialog()
            local spin = SpinWidget:new{
                title_text = _("Button Size"),
                value = Utils.getNumber("qa_panel_button_size_pct", 100),
                value_min = 60,
                value_max = 150,
                value_step = 5,
                unit = "%",
                callback = function(spin)
                    Utils.set("qa_panel_button_size_pct", spin.value)
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                    if PLUGIN_STORE.refresh_quick_panel then PLUGIN_STORE.refresh_quick_panel() end
                    Bars.showPanelSettings()
                end,
            }
            UIManager:show(spin)
        end,
    }

    items[#items + 1] = {
        text_func = function()
            return _("Label Size") .. ": " .. Utils.getNumber("qa_panel_label_scale_pct", 90) .. "%"
        end,
        close_on_click = true,
        callback = function(touchmenu_instance)
            closeMainDialog()
            local spin = SpinWidget:new{
                title_text = _("Label Size"),
                value = Utils.getNumber("qa_panel_label_scale_pct", 90),
                value_min = 50,
                value_max = 200,
                value_step = 10,
                unit = "%",
                callback = function(spin)
                    Utils.set("qa_panel_label_scale_pct", spin.value)
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                    if PLUGIN_STORE.refresh_quick_panel then PLUGIN_STORE.refresh_quick_panel() end
                    Bars.showPanelSettings()
                end,
            }
            UIManager:show(spin)
        end,
    }

    items[#items + 1] = {
        text = _("Long-press button to edit"),
        checked_func = function()
            return Utils.getBool("qa_panel_button_hold_edit", true)
        end,
        callback = function(touchmenu_instance)
            Utils.set("qa_panel_button_hold_edit", not Utils.getBool("qa_panel_button_hold_edit", true))
            if touchmenu_instance then touchmenu_instance:updateItems() end
            if PLUGIN_STORE.refresh_quick_panel then PLUGIN_STORE.refresh_quick_panel() end
        end,
    }

    items[#items + 1] = {
        text = _("Long-press panel to open settings"),
        checked_func = function()
            return Utils.getBool("qa_panel_settings_on_hold", true)
        end,
        callback = function(touchmenu_instance)
            Utils.set("qa_panel_settings_on_hold", not Utils.getBool("qa_panel_settings_on_hold", true))
            if touchmenu_instance then touchmenu_instance:updateItems() end
            if PLUGIN_STORE.refresh_quick_panel then PLUGIN_STORE.refresh_quick_panel() end
        end,
    }

    return items
end

function Bars.getBottomBarMenuItems()
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

    items[#items + 1] = {
        text = _("Show in Reader"),
        checked_func = function()
            return Utils.getBool("qa_bb_reader_enabled", true)
        end,
        callback = function(touchmenu_instance)
            Utils.set("qa_bb_reader_enabled", not Utils.getBool("qa_bb_reader_enabled", true))
            if touchmenu_instance then touchmenu_instance:updateItems() end
            bb.refresh()
        end,
    }

    items[#items + 1] = {
        text = _("Allow overlap with content (Reader only)"),
        checked_func = function()
            return Utils.getBool("qa_bb_overlap", false)
        end,
        callback = function(touchmenu_instance)
            Utils.set("qa_bb_overlap", not Utils.getBool("qa_bb_overlap", false))
            if touchmenu_instance then touchmenu_instance:updateItems() end
            bb.refresh()
            UIManager:show(Notification:new{
                text = _("Overlap mode changed"),
                timeout = 2,
            })
        end,
    }

    items[#items + 1] = {
        text = _("Hide in PDF"),
        checked_func = function()
            return Utils.getBool("qa_bb_hide_in_pdf", false)
        end,
        callback = function(touchmenu_instance)
            Utils.set("qa_bb_hide_in_pdf", not Utils.getBool("qa_bb_hide_in_pdf", false))
            if touchmenu_instance then touchmenu_instance:updateItems() end
            bb.refresh()
        end,
    }

    items[#items + 1] = {
        text = _("Long press to edit"),
        checked_func = function()
            return Utils.getBool("qa_bb_button_hold_edit", true)
        end,
        callback = function(touchmenu_instance)
            Utils.set("qa_bb_button_hold_edit", not Utils.getBool("qa_bb_button_hold_edit", true))
            if touchmenu_instance then touchmenu_instance:updateItems() end
        end,
    }

    items[#items + 1] = {
        text = _("Long press to open settings"),
        checked_func = function()
            return Utils.getBool("qa_bb_settings_on_hold", true)
        end,
        callback = function(touchmenu_instance)
            Utils.set("qa_bb_settings_on_hold", not Utils.getBool("qa_bb_settings_on_hold", true))
            if touchmenu_instance then touchmenu_instance:updateItems() end
        end,
    }

    items[#items + 1] = {
        text = _("Bar Style"),
        sub_item_table = {
            {
                text = _("Default"),
                radio = true,
                checked_func = function()
                    return Utils.getString("qa_bb_style", "default") == "default"
                end,
                callback = function(touchmenu_instance)
                    Utils.set("qa_bb_style", "default")
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                    bb.refresh()
                end,
            },
            {
                text = _("Framed"),
                radio = true,
                checked_func = function()
                    return Utils.getString("qa_bb_style", "default") == "framed"
                end,
                callback = function(touchmenu_instance)
                    Utils.set("qa_bb_style", "framed")
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                    bb.refresh()
                end,
            },
            {
                text = _("Bare"),
                radio = true,
                checked_func = function()
                    return Utils.getString("qa_bb_style", "default") == "bare"
                end,
                callback = function(touchmenu_instance)
                    Utils.set("qa_bb_style", "bare")
                    if touchmenu_instance then touchmenu_instance:updateItems() end
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
                    return Utils.getBool("qa_bb_transparent", false) == true
                end,
                callback = function(touchmenu_instance)
                    Utils.set("qa_bb_transparent", true)
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                    bb.refresh()
                end,
            },
            {
                text = _("Solid"),
                radio = true,
                checked_func = function()
                    return Utils.getBool("qa_bb_transparent", false) == false
                end,
                callback = function(touchmenu_instance)
                    Utils.set("qa_bb_transparent", false)
                    if touchmenu_instance then touchmenu_instance:updateItems() end
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
            local tabs = Utils.get("qa_bb_tabs", {})
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
                    Utils.set("qa_bb_tabs", new_tabs)
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
                Bars.showBottombarSettings()
            end)
        end,
    }

    items[#items + 1] = {
        text = _("Show Labels"),
        checked_func = function()
            return Utils.getBool("qa_bb_labels", false)
        end,
        callback = function(touchmenu_instance)
            Utils.set("qa_bb_labels", not Utils.getBool("qa_bb_labels", false))
            if touchmenu_instance then touchmenu_instance:updateItems() end
            bb.refresh()
        end,
    }

    items[#items + 1] = {
        text_func = function()
            return _("Bar Size") .. ": " .. Utils.getNumber("qa_bb_size_pct", 100) .. "%"
        end,
        close_on_click = true,
        callback = function(touchmenu_instance)
            closeMainDialog()
            local spin = SpinWidget:new{
                title_text = _("Bar Size"),
                value = Utils.getNumber("qa_bb_size_pct", 100),
                value_min = 50,
                value_max = 150,
                value_step = 10,
                unit = "%",
                callback = function(spin)
                    Utils.set("qa_bb_size_pct", spin.value)
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                    bb.refresh()
                    Bars.showBottombarSettings()
                end,
            }
            UIManager:show(spin)
        end,
    }

    items[#items + 1] = {
        text_func = function()
            return _("Icon Size") .. ": " .. Utils.getNumber("qa_bb_icon_scale_pct", 100) .. "%"
        end,
        close_on_click = true,
        callback = function(touchmenu_instance)
            closeMainDialog()
            local spin = SpinWidget:new{
                title_text = _("Icon Size"),
                value = Utils.getNumber("qa_bb_icon_scale_pct", 100),
                value_min = 50,
                value_max = 200,
                value_step = 10,
                unit = "%",
                callback = function(spin)
                    Utils.set("qa_bb_icon_scale_pct", spin.value)
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                    bb.refresh()
                    Bars.showBottombarSettings()
                end,
            }
            UIManager:show(spin)
        end,
    }

    items[#items + 1] = {
        text_func = function()
            return _("Label Size") .. ": " .. Utils.getNumber("qa_bb_label_scale_pct", 100) .. "%"
        end,
        close_on_click = true,
        callback = function(touchmenu_instance)
            closeMainDialog()
            local spin = SpinWidget:new{
                title_text = _("Label Size"),
                value = Utils.getNumber("qa_bb_label_scale_pct", 100),
                value_min = 50,
                value_max = 200,
                value_step = 10,
                unit = "%",
                callback = function(spin)
                    Utils.set("qa_bb_label_scale_pct", spin.value)
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                    bb.refresh()
                    Bars.showBottombarSettings()
                end,
            }
            UIManager:show(spin)
        end,
    }

    return items
end

function Bars.getVerticalBarMenuItems()
    local vb = PLUGIN_STORE.verticalbar
    if not vb then
        return {
            {
                text = _("Vertical Bar module not available (enable it first)"),
                enabled = false,
            }
        }
    end

    local items = {}

    items[#items + 1] = {
        text = _("Long press to edit"),
        checked_func = function()
            return Utils.getBool("qa_vb_button_hold_edit", true)
        end,
        callback = function(touchmenu_instance)
            Utils.set("qa_vb_button_hold_edit", not Utils.getBool("qa_vb_button_hold_edit", true))
            if touchmenu_instance then touchmenu_instance:updateItems() end
        end,
    }

    items[#items + 1] = {
        text = _("Long press to open settings"),
        checked_func = function()
            return Utils.getBool("qa_vb_settings_on_hold", true)
        end,
        callback = function(touchmenu_instance)
            Utils.set("qa_vb_settings_on_hold", not Utils.getBool("qa_vb_settings_on_hold", true))
            if touchmenu_instance then touchmenu_instance:updateItems() end
        end,
    }
    
    items[#items + 1] = {
        text = _("Swipe to page"),
        checked_func = function()
            return Utils.getBool("qa_vb_swipe_paging", false)
        end,
        callback = function(touchmenu_instance)
            Utils.set("qa_vb_swipe_paging", not Utils.getBool("qa_vb_swipe_paging", false))
            if touchmenu_instance then touchmenu_instance:updateItems() end
            if vb then vb.refresh() end
        end,
    }
    
    items[#items + 1] = {
        text = _("Side"),
        sub_item_table = {
            {
                text = _("Left"),
                radio = true,
                checked_func = function()
                    return Utils.getString("qa_vb_side", "right") == "left"
                end,
                callback = function(touchmenu_instance)
                    Utils.set("qa_vb_side", "left")
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                    if vb then vb.refresh() end
                end,
            },
            {
                text = _("Right"),
                radio = true,
                checked_func = function()
                    return Utils.getString("qa_vb_side", "right") == "right"
                end,
                callback = function(touchmenu_instance)
                    Utils.set("qa_vb_side", "right")
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                    if vb then vb.refresh() end
                end,
            },
        },
    }
    
    items[#items + 1] = {
        text = _("Background"),
        sub_item_table = {
            {
                text = _("White"),
                radio = true,
                checked_func = function()
                    return Utils.getString("qa_vb_bg", "white") == "white"
                end,
                callback = function(tm)
                    Utils.set("qa_vb_bg", "white")
                    if tm then tm:updateItems() end
                    if vb then vb.refresh() end
                end,
            },
            {
                text = _("Transparent"),
                radio = true,
                checked_func = function()
                    return Utils.getString("qa_vb_bg", "white") == "transparent"
                end,
                callback = function(tm)
                    Utils.set("qa_vb_bg", "transparent")
                    if tm then tm:updateItems() end
                    if vb then vb.refresh() end
                end,
            },
            {
                text = _("Light Gray"),
                radio = true,
                checked_func = function()
                    return Utils.getString("qa_vb_bg", "white") == "flat"
                end,
                callback = function(tm)
                    Utils.set("qa_vb_bg", "flat")
                    if tm then tm:updateItems() end
                    if vb then vb.refresh() end
                end,
            },
        },
    }

    items[#items + 1] = {
        text = _("Animation"),
        sub_item_table = {
            {
                text = _("Off"),
                radio = true,
                checked_func = function()
                    return Utils.getString("qa_vb_animation", "fast") == "off"
                end,
                callback = function(tm)
                    Utils.set("qa_vb_animation", "off")
                    if tm then tm:updateItems() end
                end,
            },
            {
                text = _("Fast"),
                radio = true,
                checked_func = function()
                    return Utils.getString("qa_vb_animation", "fast") == "fast"
                end,
                callback = function(tm)
                    Utils.set("qa_vb_animation", "fast")
                    if tm then tm:updateItems() end
                end,
            },
            {
                text = _("Medium"),
                radio = true,
                checked_func = function()
                    return Utils.getString("qa_vb_animation", "fast") == "medium"
                end,
                callback = function(tm)
                    Utils.set("qa_vb_animation", "medium")
                    if tm then tm:updateItems() end
                end,
            },
            {
                text = _("Slow"),
                radio = true,
                checked_func = function()
                    return Utils.getString("qa_vb_animation", "fast") == "slow"
                end,
                callback = function(tm)
                    Utils.set("qa_vb_animation", "slow")
                    if tm then tm:updateItems() end
                end,
            },
        },
    }
    items[#items + 1] = {
        text = _("Arrange Buttons"),
        close_on_click = true,
        callback = function()
            local slots = Utils.getTable("qa_vb_slots")
            if #slots == 0 then
                UIManager:show(InfoMessage:new{
                    text = _("No buttons configured"),
                    timeout = 2,
                })
                return
            end
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
                    Utils.set("qa_vb_slots", new_slots)
                    if vb then vb.refresh() end
                end,
            }
            UIManager:show(sort_dialog)
        end,
    }

    items[#items + 1] = {
        text = _("Add Button"),
        close_on_click = true,
        callback = function()
            if vb and vb.showAddButtonMenu then
                vb.showAddButtonMenu(function()
                    Bars.showVerticalBarSettings()
                end)
            end
        end,
    }

    items[#items + 1] = {
        text = _("Show Labels"),
        checked_func = function()
            return Utils.getBool("qa_vb_labels", true)
        end,
        callback = function(touchmenu_instance)
            Utils.set("qa_vb_labels", not Utils.getBool("qa_vb_labels", true))
            if touchmenu_instance then touchmenu_instance:updateItems() end
            if vb then vb.refresh() end
        end,
    }

    items[#items + 1] = {
        text_func = function()
            return _("Bar Size") .. ": " .. Utils.getNumber("qa_vb_size_pct", 100) .. "%"
        end,
        close_on_click = true,
        callback = function(touchmenu_instance)
            closeMainDialog()
            local spin = SpinWidget:new{
                title_text = _("Bar Size"),
                value = Utils.getNumber("qa_vb_size_pct", 100),
                value_min = 60,
                value_max = 150,
                value_step = 10,
                unit = "%",
                callback = function(spin)
                    Utils.set("qa_vb_size_pct", spin.value)
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                    if vb then vb.refresh() end
                    Bars.showVerticalBarSettings()
                end,
            }
            UIManager:show(spin)
        end,
    }

    items[#items + 1] = {
        text_func = function()
            return _("Icon Size") .. ": " .. Utils.getNumber("qa_vb_icon_scale_pct", 100) .. "%"
        end,
        close_on_click = true,
        callback = function(touchmenu_instance)
            closeMainDialog()
            local spin = SpinWidget:new{
                title_text = _("Icon Size"),
                value = Utils.getNumber("qa_vb_icon_scale_pct", 100),
                value_min = 50,
                value_max = 200,
                value_step = 10,
                unit = "%",
                callback = function(spin)
                    Utils.set("qa_vb_icon_scale_pct", spin.value)
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                    if vb then vb.refresh() end
                    Bars.showVerticalBarSettings()
                end,
            }
            UIManager:show(spin)
        end,
    }

    items[#items + 1] = {
        text_func = function()
            return _("Label Size") .. ": " .. Utils.getNumber("qa_vb_label_scale_pct", 100) .. "%"
        end,
        close_on_click = true,
        callback = function(touchmenu_instance)
            closeMainDialog()
            local spin = SpinWidget:new{
                title_text = _("Label Size"),
                value = Utils.getNumber("qa_vb_label_scale_pct", 100),
                value_min = 50,
                value_max = 200,
                value_step = 10,
                unit = "%",
                callback = function(spin)
                    Utils.set("qa_vb_label_scale_pct", spin.value)
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                    if vb then vb.refresh() end
                    Bars.showVerticalBarSettings()
                end,
            }
            UIManager:show(spin)
        end,
    }

    return items
end

-- ============================================================
-- Bar settings entry points (called by qa_settings.lua)
-- ============================================================

function Bars.showPanelSettings(showMenuFn, buildRootFn)
    closeMainDialog()
    -- Fallback: when this is called from inside a spin-dialog callback
    -- (Button Size / Label Size), the two helpers were never threaded
    -- through. Pull them from PLUGIN_STORE instead, which qa_settings.lua
    -- populates at load.
    showMenuFn  = showMenuFn  or PLUGIN_STORE.show_menu
    buildRootFn = buildRootFn or PLUGIN_STORE.build_root_menu_items
    if not (showMenuFn and buildRootFn) then return end
    local panel_items = Bars.getPanelMenuItems()
    local root_items = buildRootFn()
    local parent_stack = {{
        items = root_items,
        title = _("Quick Actions Settings"),
        parent_stack = nil,
    }}
    showMenuFn(panel_items, _("Panel Settings"), parent_stack, nil, root_items)
end

function Bars.showBottombarSettings(showMenuFn, buildRootFn)
    closeMainDialog()
    local bb = PLUGIN_STORE.bottombar
    if not bb then
        UIManager:show(InfoMessage:new{
            text = _("Bottom Bar module not available"),
            timeout = 2,
        })
        return
    end
    showMenuFn  = showMenuFn  or PLUGIN_STORE.show_menu
    buildRootFn = buildRootFn or PLUGIN_STORE.build_root_menu_items
    if not (showMenuFn and buildRootFn) then return end
    local bb_items = Bars.getBottomBarMenuItems()
    local root_items = buildRootFn()
    local parent_stack = {{
        items = root_items,
        title = _("Quick Actions Settings"),
        parent_stack = nil,
    }}
    showMenuFn(bb_items, _("Bottom Bar Settings"), parent_stack, nil, root_items)
end

function Bars.showVerticalBarSettings(showMenuFn, buildRootFn)
    closeMainDialog()
    local vb = PLUGIN_STORE.verticalbar
    if not vb then
        UIManager:show(InfoMessage:new{
            text = _("Vertical Bar module not available"),
            timeout = 2,
        })
        return
    end
    showMenuFn  = showMenuFn  or PLUGIN_STORE.show_menu
    buildRootFn = buildRootFn or PLUGIN_STORE.build_root_menu_items
    if not (showMenuFn and buildRootFn) then return end
    local vb_items = Bars.getVerticalBarMenuItems()
    local root_items = buildRootFn()
    local parent_stack = {{
        items = root_items,
        title = _("Quick Actions Settings"),
        parent_stack = nil,
    }}
    showMenuFn(vb_items, _("Vertical Bar Settings"), parent_stack, nil, root_items)
end

-- ============================================================
-- Introspection for tests (optional)
-- ============================================================

Bars._test = {
    sourceKey = sourceKey,
    sourceList = sourceList,
    sourceSet = sourceSet,
}

return Bars
