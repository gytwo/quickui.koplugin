--[[
QuickUI - Menu Action Recorder

Records menu navigation paths and replays them as actions.
Allows users to record any menu item as a quick action.

Original: 2-quickactions.lua (menu recording functions)
]]

local logger = require("logger")
local _ = require("gettext")
local Screen = require("device").screen
local UIManager = require("ui/uimanager")
local Device = require("device")
local Size = require("ui/size")
local Blitbuffer = require("ffi/blitbuffer")

local Button = require("ui/widget/button")
local ButtonDialog = require("ui/widget/buttondialog")
local InfoMessage = require("ui/widget/infomessage")
local Notification = require("ui/widget/notification")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")

-- ============================================================
-- Global storage
-- ============================================================

local PLUGIN_STORE = _G.__QUICKUI_PLUGIN_STORE or {}
_G.__QUICKUI_PLUGIN_STORE = PLUGIN_STORE


local MenuRecorder = {}

-- ============================================================
-- Constants
-- ============================================================

local SENTINEL = "__menu_callback"
local SUBMENU = "__menu_submenu"

-- ============================================================
-- Recording State
-- ============================================================

local _pick_state = {
    active = false,
    menu = nil,
    nav_path = {},
    tab_index = 1,
    on_done = nil,
    on_cancel = nil,
    view = nil,
    action_bar = nil,
    bars_span = nil,
}

-- Save original methods for restoration
local _orig_onMenuSelect = nil
local _orig_backToUpperMenu = nil
local _orig_switchMenuTab = nil
local _orig_closeMenu = nil
local _orig_updateItems = nil

-- ============================================================
-- Helper Functions
-- ============================================================

-- Get display text from a menu item
local function entryText(item)
    local t = item.text
    if type(t) == "function" then t = t() end
    if not t and item.text_func then t = item.text_func() end
    return type(t) == "string" and t or ""
end

-- Snapshot current menu state for later restoration
local function snapshotMenuState(menu)
    local item_table_stack = {}
    for i, item_table in ipairs(menu.item_table_stack or {}) do
        item_table_stack[i] = item_table
    end
    return {
        cur_tab = menu.cur_tab,
        item_table = menu.item_table,
        item_table_stack = item_table_stack,
        page = menu.page,
    }
end

-- Restore menu state from snapshot
local function restoreMenuState(menu, state)
    if not menu or not state then return end
    menu.cur_tab = state.cur_tab
    menu.item_table = state.item_table
    menu.item_table_stack = {}
    for i, tbl in ipairs(state.item_table_stack or {}) do
        menu.item_table_stack[i] = tbl
    end
    menu.parent_id = nil
    menu.page = state.page or 1
    menu:updateItems(menu.page)
end

-- ============================================================
-- Stop Recording
-- ============================================================

local function stopRecording()
    local menu = _pick_state.menu
    local action_bar = _pick_state.action_bar
    local bars_span = _pick_state.bars_span

    _pick_state.action_bar = nil
    _pick_state.bars_span = nil
    _pick_state.active = false
    _pick_state.menu = nil
    _pick_state.on_done = nil
    _pick_state.on_cancel = nil
    _pick_state.tab_index = nil
    _pick_state.nav_path = nil
    _pick_state.view = nil

    -- Remove the action bar from the menu
    if menu and action_bar then
        local ig = menu.item_group
        for i = #ig, 1, -1 do
            if ig[i] == action_bar or ig[i] == bars_span then
                table.remove(ig, i)
            end
        end
        ig:resetLayout()
        menu.dimen.h = ig:getSize().h + menu.bordersize * 2 + menu.padding
        UIManager:setDirty(menu.show_parent, function()
            return "ui", menu.dimen
        end)
    end

    UIManager:setDirty("all", "flashui")

    -- Restore original TouchMenu methods
    local TouchMenu = require("ui/widget/touchmenu")
    if _orig_onMenuSelect then
        TouchMenu.onMenuSelect = _orig_onMenuSelect
        TouchMenu.backToUpperMenu = _orig_backToUpperMenu
        TouchMenu.switchMenuTab = _orig_switchMenuTab
        TouchMenu.closeMenu = _orig_closeMenu
        TouchMenu.updateItems = _orig_updateItems
        _orig_onMenuSelect = nil
        _orig_backToUpperMenu = nil
        _orig_switchMenuTab = nil
        _orig_closeMenu = nil
        _orig_updateItems = nil
    end
end

-- ============================================================
-- Build Action Bar
-- ============================================================

-- Build the action bar shown at the bottom of the menu during recording
local function makeActionBar(menu)
    local buttons = {}

    -- Save button
    table.insert(buttons, Button:new{
        text = _("Save as Quick Action"),
        width = menu.item_width,
        text_font_bold = true,
        bordersize = Size.border.thin,
        background = Blitbuffer.COLOR_LIGHT_GRAY,
        show_parent = menu.show_parent,
        callback = function()
            if _pick_state.active then
                local index_path = {}
                for _, step in ipairs(_pick_state.nav_path) do
                    table.insert(index_path, step.index)
                end
                local path_record = {
                    tab_index = _pick_state.tab_index,
                    display_label = _pick_state.nav_path[#_pick_state.nav_path] and
                        _pick_state.nav_path[#_pick_state.nav_path].text or _("Menu Action"),
                    index_path = index_path,
                    view = _pick_state.view,
                    is_leaf = false,
                }
                local cb = _pick_state.on_done
                stopRecording()
                if cb then cb(path_record) end
            end
        end,
    })

    -- Cancel button
    table.insert(buttons, Button:new{
        text = _("Back to Edit"),
        width = menu.item_width,
        text_font_bold = true,
        bordersize = Size.border.thin,
        background = Blitbuffer.COLOR_LIGHT_GRAY,
        show_parent = menu.show_parent,
        callback = function()
            if _pick_state.active then
                local cb = _pick_state.on_cancel
                stopRecording()
                if cb then cb() end
            end
        end,
    })

    local vg = VerticalGroup:new{ align = "center" }
    for _, btn in ipairs(buttons) do
        table.insert(vg, btn)
        table.insert(vg, VerticalSpan:new{ width = Size.padding.small })
    end
    return vg
end

-- ============================================================
-- Start Recording
-- ============================================================

function MenuRecorder.startRecording(menu, view, on_done, on_cancel)
    local TouchMenu = require("ui/widget/touchmenu")

    -- If menu is not provided, try to find it
    if not menu then
        local FM = require("apps/filemanager/filemanager")
        local fm = FM and FM.instance
        local RUI = require("apps/reader/readerui")
        local rui = RUI and RUI.instance

        if rui and rui.menu then
            if not rui.menu.menu_container or not rui.menu.menu_container[1] then
                rui.menu:onShowMenu()
            end
            menu = rui.menu.menu_container and rui.menu.menu_container[1]
            view = "reader"
        elseif fm and fm.menu then
            if not fm.menu.menu_container or not fm.menu.menu_container[1] then
                fm.menu:onShowMenu()
            end
            menu = fm.menu.menu_container and fm.menu.menu_container[1]
            view = "filemanager"
        end

        if not menu then
            UIManager:show(InfoMessage:new{
                text = _("Please open the menu first"),
                timeout = 3
            })
            if on_cancel then on_cancel() end
            return
        end
    end

    view = view or "common"

    -- Stop any existing recording
    if _pick_state.active then
        stopRecording()
    end

    -- Save original methods
    if not _orig_onMenuSelect then
        _orig_onMenuSelect = TouchMenu.onMenuSelect
        _orig_backToUpperMenu = TouchMenu.backToUpperMenu
        _orig_switchMenuTab = TouchMenu.switchMenuTab
        _orig_closeMenu = TouchMenu.closeMenu
        _orig_updateItems = TouchMenu.updateItems
    end

    -- Start recording state
    _pick_state.active = true
    _pick_state.menu = menu
    _pick_state.tab_index = 1
    _pick_state.nav_path = {}
    _pick_state.view = view
    _pick_state.on_done = on_done
    _pick_state.on_cancel = on_cancel

    -- Patch TouchMenu methods for recording
    TouchMenu.updateItems = function(self, ...)
        local result = _orig_updateItems(self, ...)
        if _pick_state.active and self == menu then
            if not _pick_state.action_bar then
                _pick_state.action_bar = makeActionBar(self)
            end
            if not _pick_state.bars_span then
                _pick_state.bars_span = VerticalSpan:new{ width = Size.padding.default }
            end
            table.insert(self.item_group, _pick_state.bars_span)
            table.insert(self.item_group, _pick_state.action_bar)
            self.item_group:resetLayout()
            self.dimen.h = self.item_group:getSize().h + self.bordersize * 2 + self.padding
            UIManager:setDirty(self.show_parent, function()
                return "ui", self.dimen
            end)
        end
        return result
    end

    TouchMenu.closeMenu = function(self, ...)
        if _pick_state.active and self == menu then
            local cb = _pick_state.on_cancel
            stopRecording()
            if cb then cb() end
        end
        return _orig_closeMenu(self, ...)
    end

    TouchMenu.onMenuSelect = function(self, item, tap_on_checkmark)
        if not _pick_state.active then
            return _orig_onMenuSelect(self, item, tap_on_checkmark)
        end

        local sub = (item.sub_item_table_func and item.sub_item_table_func())
                 or item.sub_item_table

        local item_index
        for i, it in ipairs(self.item_table or {}) do
            if it == item then
                item_index = i
                break
            end
        end

        -- If this item has a submenu, record the navigation step and continue
        if sub then
            table.insert(_pick_state.nav_path, {
                index = item_index,
                text = entryText(item),
            })
            return _orig_onMenuSelect(self, item, tap_on_checkmark)
        end

        -- Leaf node (action) - complete recording
        local label = entryText(item)
        local index_path = {}
        for _, step in ipairs(_pick_state.nav_path) do
            table.insert(index_path, step.index)
        end
        table.insert(index_path, item_index)

        local path_record = {
            tab_index = _pick_state.tab_index,
            display_label = label,
            index_path = index_path,
            view = _pick_state.view,
            is_leaf = true,
        }

        local cb = _pick_state.on_done
        stopRecording()
        if cb then cb(path_record) end
        return true
    end

    TouchMenu.backToUpperMenu = function(self, no_close)
        if _pick_state.active and self == menu then
            if #self.item_table_stack ~= 0 then
                if #_pick_state.nav_path > 0 then
                    table.remove(_pick_state.nav_path)
                end
            else
                local cb = _pick_state.on_cancel
                stopRecording()
                if cb then cb() end
            end
        end
        return _orig_backToUpperMenu(self, no_close)
    end

    TouchMenu.switchMenuTab = function(self, tab_num)
        if _pick_state.active and self == menu then
            _pick_state.tab_index = tab_num
            _pick_state.nav_path = {}
        end
        return _orig_switchMenuTab(self, tab_num)
    end

    -- Switch to first tab
    menu.cur_tab = nil
    if menu.bar and menu.bar.switchToTab then
        menu.bar:switchToTab(1)
    end

    UIManager:show(Notification:new{
        text = _("Tap any menu item to record it as a quick action"),
        timeout = 3,
    })
end

-- ============================================================
-- Replay a Recorded Path
-- ============================================================

function MenuRecorder.replayPath(menu, path_record)
    if not path_record or not path_record.index_path then
        return false
    end

    -- Check if view matches current context
    local recorded_view = path_record.view or "common"
    local FM = require("apps/filemanager/filemanager")
    local fm = FM and FM.instance
    local RUI = require("apps/reader/readerui")
    local rui = RUI and RUI.instance
    local current_view = nil
    if rui and rui.instance and not rui.instance.tearing_down then
        current_view = "reader"
    elseif fm and fm.instance then
        current_view = "filemanager"
    end
    if recorded_view ~= "common" and recorded_view ~= current_view then
        local msg = (recorded_view == "reader")
            and _("This action can only be executed in the reader. Please open a book first.")
            or _("This action can only be executed in the file manager.")
        UIManager:show(InfoMessage:new{ text = msg, timeout = 3 })
        return false
    end

    local TouchMenu = require("ui/widget/touchmenu")
    local _orig_switchMenuTab = TouchMenu.switchMenuTab

    -- Switch to the recorded tab
    if path_record.tab_index then
        local switch = _orig_switchMenuTab or TouchMenu.switchMenuTab
        switch(menu, path_record.tab_index)
    end

    local saved_state = snapshotMenuState(menu)
    local current_menu = menu
    local current_item = nil

    -- Helper to ensure the correct page is displayed
    local function ensurePageForIndex(target_idx)
        if not current_menu.perpage then return end
        local target_page = math.ceil(target_idx / current_menu.perpage)
        if target_page > 1 and target_page ~= current_menu.page then
            if current_menu.onGotoPage then
                current_menu:onGotoPage(target_page)
            end
        end
    end

    -- Navigate through the path
    for i, idx in ipairs(path_record.index_path) do
        ensurePageForIndex(idx)

        if not current_menu.item_table or not current_menu.item_table[idx] then
            restoreMenuState(menu, saved_state)
            return false
        end

        current_item = current_menu.item_table[idx]

        -- Determine if we need to enter a submenu
        local should_enter_submenu = (i < #path_record.index_path) or
            (i == #path_record.index_path and not path_record.is_leaf)

        if should_enter_submenu then
            local sub = (current_item.sub_item_table_func and current_item.sub_item_table_func())
                     or current_item.sub_item_table

            if not sub or #sub == 0 then
                restoreMenuState(menu, saved_state)
                return false
            end

            table.insert(current_menu.item_table_stack, current_menu.item_table)
            current_menu.item_table = sub
            current_menu.page = 1
            if current_menu.updateItems then
                current_menu:updateItems()
            end
        end
    end

    -- If this is a leaf action, execute the callback
    if path_record.is_leaf then
        local callback = (current_item.callback_func and current_item.callback_func()) or current_item.callback
        if callback then
            pcall(callback, current_menu)
        end
        restoreMenuState(menu, saved_state)
        menu:closeMenu()
        return true
    end

    -- If is_leaf is false, keep the submenu open (do not restore state)
    return true
end

-- ============================================================
-- Initialization
-- ============================================================

function MenuRecorder.init(plugin_ref)
    PLUGIN_STORE.plugin_ref = plugin_ref
    logger.info("QuickUI QA MenuRecorder: initialized")
end

return MenuRecorder