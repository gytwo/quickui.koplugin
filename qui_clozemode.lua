--[[
QuickUI - Cloze Mode Module

Mask annotations (highlights, underlines, strikeouts, inversions) for effective review.
Three toggle modes: double-tap, single-tap (block menu), single-tap (show menu).

Original: 2-reader-clozemode.lua
]]

local Blitbuffer = require("ffi/blitbuffer")
local UIManager = require("ui/uimanager")
local Dispatcher = require("dispatcher")
local Event = require("ui/event")
local _ = require("gettext")
local logger = require("logger")
local ButtonDialog = require("ui/widget/buttondialog")
local Screen = require("device").screen
local Utils = require("qui_utils")
local ConfirmBox = require("ui/widget/confirmbox") 

local ClozeMode = {}

local plugin = nil

-- Helper: check if point is inside a rectangle
local function insideBox(pos, box)
    if pos then
        local x, y = pos.x, pos.y
        if box.x <= x and box.y <= y
            and box.x + box.w >= x
            and box.y + box.h >= y then
            return true
        end
    end
    return false
end

-- Helper: force redraw without recalculate (avoids PDF page jump)
local function forceRedraw(ui)
    if not ui or not ui.view then
        return
    end
    UIManager:setDirty(ui.dialog, "ui")
end

-- Get page number from screen rect (for continuous mode)
local function getPageFromScreenRect(self, rect)
    if not self.page_states then
        return self.state and self.state.page or 1
    end

    local y = rect.y
    local y_offset = 0
    local gap = (self.page_gap and self.page_gap.height) or 0

    for _, state in ipairs(self.page_states) do
        if y >= y_offset and y < y_offset + state.visible_area.h then
            return state.page
        end
        y_offset = y_offset + state.visible_area.h + gap
    end

    return self.page_states[1] and self.page_states[1].page or 1
end

-- ============================================================
-- Configuration Helpers
-- ============================================================

local function getSetting(key)
    local config = _G.__QUICKUI_CONFIG
    if config then
        return config[key]
    end
    return nil
end

local function setSetting(key, value)
    local config = _G.__QUICKUI_CONFIG
    if config then
        config[key] = value
        Utils.saveConfig()
    end
end

local function getBool(key)
    local val = getSetting(key)
    if type(val) == "boolean" then return val end
    return false
end

local function getNumber(key)
    local val = getSetting(key)
    if type(val) == "number" then return val end
    return 1
end

local function isEnabled()
    return getBool("cl_enabled")
end

local function getToggleMode()
    return getNumber("cl_toggle_mode")
end

local function getCoveredDrawers()
    local val = getSetting("cl_drawers")
    if type(val) == "table" then return val end
    return { lighten = true }
end

local function shouldCoverDrawer(drawer)
    if not isEnabled() then
        return false
    end
    local covered = getCoveredDrawers()
    return covered[drawer] == true
end

local function toggleHighlight(highlight, index)
    if not isEnabled() then
        return
    end
    highlight._temp_covered = highlight._temp_covered or {}
    local is_covered = highlight._temp_covered[index] == true
    highlight._temp_covered[index] = not is_covered

    local ReaderUI = require("apps/reader/readerui")
    if ReaderUI and ReaderUI.instance then
        forceRedraw(ReaderUI.instance)
    else
        UIManager:setDirty(nil, "full")
    end
end

local function coverAllHighlights(highlight)
    if not isEnabled() then
        return
    end
    highlight._temp_covered = highlight._temp_covered or {}
    local annotations = highlight.ui.annotation.annotations
    for idx, item in ipairs(annotations) do
        if item.drawer then
            highlight._temp_covered[idx] = true
        end
    end
end

local function uncoverAllHighlights(highlight)
    if not isEnabled() then
        return
    end
    highlight._temp_covered = highlight._temp_covered or {}
    local annotations = highlight.ui.annotation.annotations
    for idx, item in ipairs(annotations) do
        if item.drawer then
            highlight._temp_covered[idx] = false
        end
    end
end

function ClozeMode.init(plugin_ref)
    plugin = plugin_ref

    local ReaderHighlight = require("apps/reader/modules/readerhighlight")
    local ReaderView = require("apps/reader/modules/readerview")

    if not ReaderView then
        return
    end

    -- Patch drawHighlightRect
    local originalDraw = ReaderView.drawHighlightRect

    function ReaderView.drawHighlightRect(self, bb, _x, _y, rect, drawer, color, draw_note_mark)
        if shouldCoverDrawer(drawer) then
            local index = nil
            if self.highlight.visible_boxes then
                for _, box in ipairs(self.highlight.visible_boxes) do
                    if box.rect == rect then
                        index = box.index
                        break
                    end
                end
            end

            if index == nil and self.highlight.visible_boxes then
                local current_page = getPageFromScreenRect(self, rect)
                for _, box in ipairs(self.highlight.visible_boxes) do
                    local screen_rect = self:pageToScreenTransform(current_page, box.rect)
                    if screen_rect and math.abs(screen_rect.x - rect.x) < 2 and math.abs(screen_rect.y - rect.y) < 2 then
                        index = box.index
                        break
                    end
                end
            end

            local is_covered = false
            if index and self.ui and self.ui.highlight and self.ui.highlight._temp_covered then
                is_covered = self.ui.highlight._temp_covered[index] == true
            end

            local x, y, w, h = rect.x, rect.y, rect.w, rect.h

            if is_covered then
                if color then
                    local c = Blitbuffer.ColorRGB32(color.r, color.g, color.b, 0xFF)
                    bb:blendRectRGB32(x, y, w, h, c)
                else
                    local yellow = Blitbuffer.colorFromName("yellow")
                    if yellow then
                        local c = Blitbuffer.ColorRGB32(yellow.r, yellow.g, yellow.b, 0xFF)
                        bb:blendRectRGB32(x, y, w, h, c)
                    else
                        bb:darkenRect(x, y, w, h, 1)
                    end
                end
                return
            end
        end

        if originalDraw then
            originalDraw(self, bb, _x, _y, rect, drawer, color, draw_note_mark)
        end
    end

    -- Patch onReaderReady for gesture registration
    local originalReady = ReaderHighlight.onReaderReady

    function ReaderHighlight:onReaderReady()
        if originalReady then
            originalReady(self)
        end

        self.ui:registerTouchZones({
            {
                id = "readerhighlight_double_tap",
                ges = "double_tap",
                screen_zone = {
                    ratio_x = 0, ratio_y = 0,
                    ratio_w = 1, ratio_h = 1,
                },
                handler = function(ges)
                    local mode = getToggleMode()
                    if not isEnabled() or mode ~= 1 then
                        return false
                    end
                    return self:onDoubleTap(ges)
                end,
                overrides = {
                    "readerhighlight_tap",
                    "readerhighlight_hold",
                },
            },
        })

        local menu = self.ui.menu
        if menu and menu.menu_items then
            ClozeMode.addToMainMenu(menu.menu_items)
            if menu.touchmenu_instance then
                menu:updateItems()
            end
        end
    end

    -- Double-tap handler
    function ReaderHighlight:onDoubleTap(ges)
        if not isEnabled() or getToggleMode() ~= 1 then
            return false
        end

        local pos = self.view:screenToPageTransform(ges.pos)
        if not pos then
            return false
        end

        local tapped_index = nil
        if self.view.highlight.visible_boxes then
            for _, box in ipairs(self.view.highlight.visible_boxes) do
                if insideBox(pos, box.rect) then
                    tapped_index = box.index
                    break
                end
            end
        end

        if tapped_index then
            toggleHighlight(self, tapped_index)
            return true
        end

        return false
    end

    -- Single-tap handler
    local originalTap = ReaderHighlight.onTap

    function ReaderHighlight:onTap(_, ges)
        local mode = getToggleMode()

        if not isEnabled() or mode == 1 then
            return originalTap(self, _, ges)
        end

        local pos = self.view:screenToPageTransform(ges.pos)

        local tapped_index = nil
        if self.view.highlight.visible_boxes then
            for _, box in ipairs(self.view.highlight.visible_boxes) do
                if insideBox(pos, box.rect) then
                    tapped_index = box.index
                    break
                end
            end
        end

        if tapped_index then
            local annotations = self.ui.annotation.annotations
            local item = annotations and annotations[tapped_index]

            if item and shouldCoverDrawer(item.drawer) then
                toggleHighlight(self, tapped_index)
                if mode == 2 then
                    return true
                end
            end
        end

        return originalTap(self, _, ges)
    end

    -- Register dispatcher action
    Dispatcher:registerAction("quickui_toggle_cloze_action", {
        category = "none",
        event = "QuickUIToggleClozeAction",
        title = _("QuickUI - Cover All / Uncover All"),
        reader = true,
    })

    local ReaderUI = require("apps/reader/readerui")
    if ReaderUI and not ReaderUI._quickui_cloze_handler then
        function ReaderUI:onQuickUIToggleClozeAction()
            if not isEnabled() then
                return
            end
            local highlight = self.highlight
            if not highlight then
                return
            end

            local has_covered = false
            local annotations = highlight.ui.annotation.annotations
            for idx, item in ipairs(annotations) do
                if item.drawer then
                    local is_cov = highlight._temp_covered and highlight._temp_covered[idx]
                    if is_cov then
                        has_covered = true
                        break
                    end
                end
            end

            if has_covered then
                uncoverAllHighlights(highlight)
            else
                coverAllHighlights(highlight)
            end

            forceRedraw(self)
        end
        ReaderUI._quickui_cloze_handler = true
    end

    Utils.registerRefreshHandler("cloze", function()
        local ReaderUI = require("apps/reader/readerui")
        if ReaderUI and ReaderUI.instance then
            UIManager:setDirty(ReaderUI.instance, "full")
        end
    end)
end

function ClozeMode.toggleAll()
    local ReaderUI = require("apps/reader/readerui")
    local ui = ReaderUI.instance
    if ui then
        ui:onQuickUIToggleClozeAction()
    end
end

function ClozeMode.addToMainMenu(menu_items)
    if menu_items.cloze_mode then
        return
    end

    menu_items.cloze_mode = {
        text = _("Cloze Mode"),
        sorting_hint = "typeset",
        sub_item_table = ClozeMode.getMenuItems(plugin),
    }
end

function ClozeMode.getMenuItems(plugin_ref)
    plugin = plugin_ref or plugin

    local items = {}

    -- Cover all / uncover all
    table.insert(items, {
            text_func = function()
                local ReaderUI = require("apps/reader/readerui")
                if not ReaderUI or not ReaderUI.instance then
                    return _("Cover All")
                end
                local highlight = ReaderUI.instance.highlight
                if not highlight or not highlight._temp_covered then
                    return _("Cover All")
                end
                local annotations = highlight.ui.annotation.annotations
                for idx, item in ipairs(annotations) do
                    if item.drawer and highlight._temp_covered[idx] then
                        return _("Uncover All")
                    end
                end
                return _("Cover All")
            end,
            enabled_func = function()
                return isEnabled()
            end,
            callback = function(touchmenu_instance)
            local ReaderUI = require("apps/reader/readerui")
            if not ReaderUI or not ReaderUI.instance then
                return
            end
            local highlight = ReaderUI.instance.highlight
            if not highlight then
                return
            end

            local has_covered = false
            local annotations = highlight.ui.annotation.annotations
            for idx, item in ipairs(annotations) do
                if item.drawer and highlight._temp_covered and highlight._temp_covered[idx] then
                    has_covered = true
                    break
                end
            end

            if has_covered then
                uncoverAllHighlights(highlight)
            else
                coverAllHighlights(highlight)
            end

            forceRedraw(ReaderUI.instance)
            if touchmenu_instance then
                touchmenu_instance:updateItems()
            end
        end,
    })

    -- Toggle mode selection
    table.insert(items, {
        text = _("Toggle Mode"),
        enabled_func = function()
            return isEnabled()
        end,
        sub_item_table = {
            {
                text = _("Double-tap to toggle"),
                checked_func = function()
                    return getToggleMode() == 1
                end,
                callback = function(touchmenu_instance)
                    setSetting("cl_toggle_mode", 1)
                    if touchmenu_instance then
                        touchmenu_instance:updateItems()
                    end
                end,
            },
            {
                text = _("Single-tap (block menu)"),
                checked_func = function()
                    return getToggleMode() == 2
                end,
                callback = function(touchmenu_instance)
                    setSetting("cl_toggle_mode", 2)
                    if touchmenu_instance then
                        touchmenu_instance:updateItems()
                    end
                end,
            },
            {
                text = _("Single-tap (show menu)"),
                checked_func = function()
                    return getToggleMode() == 3
                end,
                callback = function(touchmenu_instance)
                    setSetting("cl_toggle_mode", 3)
                    if touchmenu_instance then
                        touchmenu_instance:updateItems()
                    end
                end,
            },
        },
    })

    -- Covered styles
    local drawer_names = {
        lighten = _("Highlight"),
        underscore = _("Underline"),
        strikeout = _("Strikeout"),
        invert = _("Invert"),
    }

    local covered_styles = {}
    for drawer, name in pairs(drawer_names) do
        table.insert(covered_styles, {
            text = name,
            enabled_func = function()
                return isEnabled()
            end,
            checked_func = function()
                local covered = getCoveredDrawers()
                return covered[drawer] == true
            end,
            callback = function(touchmenu_instance)
                local covered = getCoveredDrawers()
                covered[drawer] = not covered[drawer]
                setSetting("cl_drawers", covered)

                local ReaderUI = require("apps/reader/readerui")
                if ReaderUI and ReaderUI.instance then
                    forceRedraw(ReaderUI.instance)
                end
                if touchmenu_instance then
                    touchmenu_instance:updateItems()
                end
            end,
        })
    end

    table.insert(items, {
        text = _("Coverable Styles"),
        enabled_func = function()
            return isEnabled()
        end,
        sub_item_table = covered_styles,
    })

    -- Add default config menu items
    local default_items = Utils.buildDefaultMenuItems("cloze", function()
        local ReaderUI = require("apps/reader/readerui")
        if ReaderUI and ReaderUI.instance then
            forceRedraw(ReaderUI.instance)
        end
    end)
    for _, item in ipairs(default_items) do
        table.insert(items, item)
    end

    return items
end

function ClozeMode.onReaderReady(plugin_ref)
    plugin = plugin_ref or plugin
    -- No-op, patches are applied in init()
end

-- ============================================================
-- Public API: Show Settings
-- ============================================================

function ClozeMode.showSettings(plugin_ref)
    plugin = plugin_ref or plugin

    local items = ClozeMode.getMenuItems(plugin)
    local self_ref = { _cloze_settings_dialog = nil }

    local function showMenu(title, item_table, parent_stack)
        local buttons = {}

        -- Only add QuickUI Settings button if no parent (root menu)
        if parent_stack == nil or #parent_stack == 0 then
            table.insert(buttons, {
                {
                    text = "⚙️ " .. _("QuickUI Settings"),
                    callback = function()
                        if self_ref._cloze_settings_dialog then
                            UIManager:close(self_ref._cloze_settings_dialog)
                            self_ref._cloze_settings_dialog = nil
                        end
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
                            if self_ref._cloze_settings_dialog then
                                UIManager:close(self_ref._cloze_settings_dialog)
                                self_ref._cloze_settings_dialog = nil
                            end
                            showMenu(_("Cloze Mode"), items, nil)
                        end
                    }
                })
            end

            table.insert(buttons, {
                {
                    text = "◂ " .. _("Back"),
                    callback = function()
                        if self_ref._cloze_settings_dialog then
                            UIManager:close(self_ref._cloze_settings_dialog)
                            self_ref._cloze_settings_dialog = nil
                        end
                        local parent = parent_stack[#parent_stack]
                        local new_stack = {}
                        for i = 1, #parent_stack - 1 do
                            table.insert(new_stack, parent_stack[i])
                        end
                        showMenu(parent.title, parent.items, new_stack)
                    end
                }
            })

            table.insert(buttons, {})
        end

        for _, item in ipairs(item_table) do
            if item.sub_item_table then
                local display_text
if item.text_func then
                display_text = type(item.text_func) == "function" and item.text_func() or item.text_func
                elseif item.text then
                    display_text = type(item.text) == "function" and item.text() or item.text
                else
                    display_text = ""
                end
                table.insert(buttons, {
                    {
                        text = display_text .. " ▸",
                        callback = function()
                            if self_ref._cloze_settings_dialog then
                                UIManager:close(self_ref._cloze_settings_dialog)
                                self_ref._cloze_settings_dialog = nil
                            end
                            local new_stack = {}
                            if parent_stack then
                                for _, v in ipairs(parent_stack) do
                                    table.insert(new_stack, v)
                                end
                            end
                            table.insert(new_stack, { title = title, items = item_table })
                            showMenu(display_text, item.sub_item_table, new_stack)
                        end
                    }
                })
            else
                local checked = item.checked_func and item.checked_func() or false
                local display_text
if item.text_func then
                display_text = type(item.text_func) == "function" and item.text_func() or item.text_func
                elseif item.text then
                    display_text = type(item.text) == "function" and item.text() or item.text
                else
                    display_text = ""
                end
                local enabled = (item.enabled_func == nil) or item.enabled_func()
                local prefix = checked and "✓ " or "  "

                table.insert(buttons, {
                    {
                        text = prefix .. display_text,
                        enabled = enabled,
                        callback = function()
                            if item.callback then
                                item.callback()
                            end
                            if self_ref._cloze_settings_dialog then
                                UIManager:close(self_ref._cloze_settings_dialog)
                                self_ref._cloze_settings_dialog = nil
                            end
                            showMenu(title, item_table, parent_stack)
                        end
                    }
                })
            end
        end

        if self_ref._cloze_settings_dialog then
            UIManager:close(self_ref._cloze_settings_dialog)
            self_ref._cloze_settings_dialog = nil
        end

        local dialog = ButtonDialog:new{
            title = title or _("Cloze Mode"),
            title_align = "center",
            buttons = buttons,
            width = math.floor(Screen:getWidth() * 0.7),
            max_height = math.floor(Screen:getHeight() * 0.7),
        }
        self_ref._cloze_settings_dialog = dialog
        UIManager:show(dialog)
    end

    showMenu(_("Cloze Mode"), items, nil)
end

return ClozeMode