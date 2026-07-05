--[[
QuickUI - Quick Actions Panel Builder

Builds the Quick Actions panel (the tab that appears in the Tools menu)
with buttons, sliders, and TouchMenu integration.

Original: 2-quickactions.lua (buildQSPanel + TouchMenu patches)
]]

local logger = require("logger")
local _ = require("gettext")
local Blitbuffer = require("ffi/blitbuffer")
local Font = require("ui/font")
local Screen = require("device").screen
local Device = require("device")
local Geom = require("ui/geometry")
local UIManager = require("ui/uimanager")
local datetime = require("datetime")
local BD = require("ui/bidi")

local CenterContainer = require("ui/widget/container/centercontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local FocusManager = require("ui/widget/focusmanager")
local TextWidget = require("ui/widget/textwidget")
local Button = require("ui/widget/button")
local ImageWidget = require("ui/widget/imagewidget")
local IconWidget = require("ui/widget/iconwidget")
local TouchMenu = require("ui/widget/touchmenu")

local Utils = require("qui_utils")

-- Load submodules using require with path
local actions = require("qui_actions/qa_actions")
local icon_picker = require("qui_actions/qa_icon_picker")
local settings_mod = require("qui_actions/qa_settings")

-- ============================================================
-- Global storage
-- ============================================================

local PLUGIN_STORE = _G.__QUICKUI_PLUGIN_STORE or {}
_G.__QUICKUI_PLUGIN_STORE = PLUGIN_STORE

local QA = {}
local _qs_refs = nil


-- ============================================================
-- Initialization
-- ============================================================

function QA.init(plugin)
    PLUGIN_STORE.plugin_ref = plugin
end

-- ============================================================
-- Forward to actions module
-- ============================================================

local function getAction(id)
    return actions.getAction(id)
end

local function executeAction(id, ctx)
    return actions.executeAction(id, ctx)
end

local function getLabelForAction(id)
    return actions.getLabelForAction(id)
end

local function getIconForAction(id)
    return actions.getIconForAction(id)
end

local function isInPlace(id)
    return actions.isInPlace(id)
end

local function isActionVisible(action_id, current_view)
    return actions.isActionVisible(action_id, current_view)
end

-- ============================================================
-- SlimSlider Widget
-- ============================================================

local SlimSlider = require("ui/widget/widget"):extend{
    width = 200,
    height = Screen:scaleBySize(28),
    minimum = 0,
    maximum = 100,
    value = 0,
    show_parent = nil,
    enabled = true,
}

function SlimSlider:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
end

function SlimSlider:getSize()
    return Geom:new{ w = self.width, h = self.height }
end

function SlimSlider:setValue(v)
    self.value = math.max(self.minimum, math.min(self.maximum, v or 0))
end

function SlimSlider:getValueFromPosition(pos)
    if not self.dimen or not pos then return nil end
    local rel_x = pos.x - self.dimen.x
    rel_x = math.max(0, math.min(self.width, rel_x))
    local range = self.maximum - self.minimum
    if range <= 0 then return self.minimum end
    return self.minimum + (rel_x / self.width) * range
end

function SlimSlider:paintTo(bb, x, y)
    self.dimen.x = x
    self.dimen.y = y
    local track_h = Screen:scaleBySize(2)
    local thumb_w = Screen:scaleBySize(3)
    local thumb_h = Screen:scaleBySize(14)
    local cy = y + math.floor(self.height / 2)
    local range = math.max(1, self.maximum - self.minimum)
    local pct = (self.value - self.minimum) / range
    local fill_w = math.floor(pct * self.width)
    fill_w = math.max(0, math.min(self.width, fill_w))
    bb:paintRect(x, cy - math.floor(track_h / 2), self.width, track_h, Blitbuffer.COLOR_LIGHT_GRAY)
    if fill_w > 0 then
        bb:paintRect(x, cy - math.floor(track_h / 2), fill_w, track_h, Blitbuffer.COLOR_BLACK)
    end
    local tx = x + fill_w - math.floor(thumb_w / 2)
    tx = math.max(x, math.min(x + self.width - thumb_w, tx))
    bb:paintRect(tx, cy - math.floor(thumb_h / 2), thumb_w, thumb_h, Blitbuffer.COLOR_BLACK)
end

-- ============================================================
-- Build the Quick Actions Panel
-- ============================================================

function QA.buildPanel(touch_menu)
    local panel_w = touch_menu.item_width
    local padding = Screen:scaleBySize(28)
    local inner_w = panel_w - padding * 2
    local base_btn_size = Screen:scaleBySize(60)
    local button_scale = Utils.getNumber("qa_panel_button_size_pct") / 100
    if button_scale <= 0 then button_scale = 1 end
    local btn_size = math.floor(base_btn_size * button_scale)
    local icon_size = math.floor(btn_size * 0.52)
    local label_fs = math.max(6, math.floor(15 * (Utils.getNumber("qa_panel_label_scale_pct") / 100)))
    local label_face = Utils.getFontFace("cfont", label_fs)
    local medium_face = Utils.getFontFace("ffont", Utils.scaleBySize(14))
    local border_sz = 1
    local shape = Utils.getString("qa_panel_shape")
    if shape == "" then shape = "round" end
    local is_bare = (shape == "bare")

    local function makeButton(action_id)
        local label = getLabelForAction(action_id)
        local icon_path = getIconForAction(action_id)
        local icon_widget = nil

        if icon_picker and icon_picker.getIconWidget then
            icon_widget = icon_picker.getIconWidget(icon_path, icon_size)
        end

        if not icon_widget then
            local first_char = label
            local chars = require("util").splitToChars(label)
            if chars and #chars > 0 then
                first_char = chars[1]
            end
            icon_widget = TextWidget:new{
                text = first_char,
                face = Utils.getFontFace("cfont", math.floor(icon_size * 0.55)),
                fgcolor = Blitbuffer.COLOR_BLACK,
            }
        end

        local corner_r
        if shape == "round" then
            corner_r = math.floor(btn_size / 2)
        elseif shape == "square_round" then
            corner_r = math.floor(btn_size / 4)
        else
            corner_r = math.floor(btn_size / 4)
        end

        local bg = Utils.getString("qa_panel_bg")
        if bg == "" then bg = "flat" end
        local current_border = 0
        local bg_color = nil
        if not is_bare then
            current_border = (bg == "solid" or bg == "transparent") and border_sz or 0
            if bg == "flat" then
                bg_color = Blitbuffer.gray(0.08)
            elseif bg == "solid" then
                bg_color = Blitbuffer.COLOR_WHITE
            end
        end

        local btn_frame = FrameContainer:new{
            width = btn_size,
            height = btn_size,
            radius = corner_r,
            bordersize = current_border,
            color = current_border > 0 and Blitbuffer.gray(0.75) or nil,
            background = bg_color,
            padding = 0,
            CenterContainer:new{
                dimen = Geom:new{
                    w = btn_size - current_border * 2,
                    h = btn_size - current_border * 2,
                },
                icon_widget,
            },
        }

        local btn_wrapper = InputContainer:new{
            dimen = Geom:new{ w = btn_size, h = btn_size },
        }
        btn_wrapper[1] = btn_frame

        local function applyPressFeedback(widget)
            local original_bg = widget.background
            local original_color = widget.color
            widget.background = Blitbuffer.gray(0.3)
            if widget.color then
                widget.color = Blitbuffer.gray(0.3)
            end
            UIManager:setDirty(touch_menu.show_parent, function()
                return "ui", widget.dimen
            end)
            UIManager:scheduleIn(0.1, function()
                widget.background = original_bg
                widget.color = original_color
                UIManager:setDirty(touch_menu.show_parent, function()
                    return "ui", widget.dimen
                end)
            end)
        end

        local zones = {
            {
                id = "btn_tap_" .. action_id,
                ges = "tap",
                screen_zone = {
                    ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1,
                },
                handler = function(ges)
                    local rel_x = ges.pos.x - (btn_wrapper.dimen and btn_wrapper.dimen.x or 0)
                    local rel_y = ges.pos.y - (btn_wrapper.dimen and btn_wrapper.dimen.y or 0)
                    if rel_x >= 0 and rel_x <= btn_size and rel_y >= 0 and rel_y <= btn_size then
                        applyPressFeedback(btn_frame)
                        local stay_open = isInPlace(action_id)
                        if stay_open then
                            executeAction(action_id, { touch_menu = touch_menu })
                            touch_menu:updateItems()
                        else
                            UIManager:scheduleIn(0.05, function()
                                executeAction(action_id, { touch_menu = touch_menu })
                            end)
                        end
                        return true
                    end
                    return false
                end,
            },
        }

        if Utils.getBool("qa_panel_button_hold_edit") then
            table.insert(zones, {
                id = "btn_hold_" .. action_id,
                ges = "hold",
                screen_zone = {
                    ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1,
                },
                handler = function(ges)
                    local rel_x = ges.pos.x - (btn_wrapper.dimen and btn_wrapper.dimen.x or 0)
                    local rel_y = ges.pos.y - (btn_wrapper.dimen and btn_wrapper.dimen.y or 0)
                    if rel_x >= 0 and rel_x <= btn_size and rel_y >= 0 and rel_y <= btn_size then
                        local is_builtin = actions.isBuiltinAction(action_id)
                        if is_builtin then
                            if settings_mod and settings_mod.showEditActionDialog then
                                settings_mod.showEditActionDialog(action_id, function()
                                    if touch_menu then touch_menu:updateItems() end
                                end)
                            end
                        else
                            if settings_mod and settings_mod.showCustomQADialog then
                                settings_mod.showCustomQADialog(action_id, function()
                                    if touch_menu then touch_menu:updateItems() end
                                end)
                            end
                        end
                        return true
                    end
                    return false
                end,
            })
        end

        btn_wrapper:registerTouchZones(zones)
        btn_wrapper.onShow = function() end

        local vg = VerticalGroup:new{ align = "center", btn_wrapper }
        if Utils.getBool("qa_panel_labels") then
            local lbl_w = btn_size + Screen:scaleBySize(6)
            table.insert(vg, VerticalSpan:new{ width = Screen:scaleBySize(2) })
            table.insert(vg, CenterContainer:new{
                dimen = Geom:new{ w = lbl_w, h = label_face.size },
                TextWidget:new{
                    text = label,
                    face = label_face,
                    fgcolor = Blitbuffer.COLOR_BLACK,
                    max_width = lbl_w,
                    width = lbl_w,
                    truncate_with_ellipsis = true,
                },
            })
        end

        return vg, btn_frame
    end

    local context_filter_enabled = Utils.getBool("qa_common_context_filter")
    local current_view = "filemanager"
    if context_filter_enabled then
        local RUI = require("apps/reader/readerui")
        local in_reader = RUI and RUI.instance and not RUI.instance.tearing_down
        current_view = in_reader and "reader" or "filemanager"
    end

    local slots = Utils.getTable("qa_panel_slots")
    local visible_slots = {}
    for __, id in ipairs(slots) do
        local action = getAction(id)
        if action then
            if isActionVisible(id, current_view) then
                visible_slots[#visible_slots + 1] = id
            end
        end
    end

    local n = #visible_slots
    local fixed_gap = Screen:scaleBySize(8)
    local max_per_row = math.max(1, math.floor((inner_w + fixed_gap) / (btn_size + fixed_gap)))
    local rows = {}
    for i = 1, n, max_per_row do
        local row_slots = {}
        for j = i, math.min(i + max_per_row - 1, n) do
            table.insert(row_slots, visible_slots[j])
        end
        table.insert(rows, row_slots)
    end

    local rows_vg = VerticalGroup:new{ align = "center" }
    local row_gap = Screen:scaleBySize(8)
    local refs = { buttons = {} }

    if n > 0 then
        for ri, row_slots in ipairs(rows) do
            local row_n = #row_slots
            local gap = (row_n > 1) and math.max(0, math.floor((inner_w - row_n * btn_size) / (row_n - 1))) or 0
            local hg = HorizontalGroup:new{ align = "center" }
            for i, action_id in ipairs(row_slots) do
                local vg, btn_frame = makeButton(action_id)
                local _aid = action_id
                table.insert(refs.buttons, {
                    widget = btn_frame,
                    callback = function()
                        local stay_open = isInPlace(_aid)
                        if stay_open then
                            executeAction(_aid, { touch_menu = touch_menu })
                            touch_menu:updateItems()
                        else
                            UIManager:scheduleIn(0, function()
                                executeAction(_aid, { touch_menu = touch_menu })
                            end)
                        end
                        return stay_open
                    end,
                })
                table.insert(hg, vg)
                if i < row_n then
                    table.insert(hg, HorizontalSpan:new{ width = gap })
                end
            end
            table.insert(rows_vg, hg)
            if ri < #rows then
                table.insert(rows_vg, VerticalSpan:new{ width = row_gap })
            end
        end
    else
        table.insert(rows_vg, TextWidget:new{
               text = _("No actions configured, long press to add"),
               face = Utils.getFontFace("cfont", Utils.scaleBySize(14)),
               fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        })
    end

    local panel = VerticalGroup:new{
        align = "center",
        VerticalSpan:new{ width = Screen:scaleBySize(20) },
        CenterContainer:new{ dimen = Geom:new{ w = panel_w, h = rows_vg:getSize().h }, rows_vg },
        VerticalSpan:new{ width = Screen:scaleBySize(16) },
    }

    -- Frontlight slider
    if Utils.getBool("qa_panel_frontlight") and Device:hasFrontlight() then
        local powerd = Device:getPowerDevice()
        local fl = {
            min = powerd.fl_min,
            max = powerd.fl_max,
            cur = powerd:frontlightIntensity(),
        }
        local small_btn_w = Screen:scaleBySize(40)
        local max_btn_w = Screen:scaleBySize(50)
        local slider_gap = Screen:scaleBySize(4)
        local slider_width = inner_w - 2 * small_btn_w - max_btn_w - 3 * slider_gap

        local fl_label = nil
        if Utils.getBool("qa_panel_slider_show_value") then
            fl_label = TextWidget:new{
                text = _("Frontlight") .. ": " .. tostring(fl.cur),
                face = medium_face,
                max_width = inner_w,
            }
        end

        local _dummy = Button:new{ text = "−", width = small_btn_w, show_parent = touch_menu.show_parent, callback = function() end }
        local btn_height = math.max(30, _dummy:getSize().h)

        local fl_slider = SlimSlider:new{
            width = slider_width,
            height = btn_height,
            minimum = fl.min,
            maximum = fl.max,
            value = fl.cur,
            show_parent = touch_menu.show_parent,
            enabled = true,
        }

        local fl_saved_brightness = (fl.cur > fl.min) and fl.cur or fl.max
        local fl_toggle_btn

        local function updateFLWidgets()
            fl_slider:setValue(fl.cur)
            if fl_label then
                fl_label:setText(_("Frontlight") .. ": " .. tostring(fl.cur))
            end
            if fl_toggle_btn then
                fl_toggle_btn:setText(fl.cur > fl.min and "ON" or "OFF")
            end
            UIManager:setDirty(touch_menu.show_parent, "ui")
        end

        local function setBrightness(intensity)
            if intensity ~= fl.min and intensity == fl.cur then return end
            intensity = math.max(fl.min, math.min(fl.max, intensity))
            powerd:setIntensity(intensity)
            fl.cur = powerd:frontlightIntensity()
            updateFLWidgets()
        end

        local fl_minus = Button:new{
            text = "−", width = small_btn_w, show_parent = touch_menu.show_parent,
            callback = function() setBrightness(fl.cur - 1) end,
            bordersize = 0,
            background = nil,
            framebg = nil,
        }

        local fl_plus = Button:new{
            text = "＋", width = small_btn_w, show_parent = touch_menu.show_parent,
            callback = function() setBrightness(fl.cur + 1) end,
            bordersize = 0,
            background = nil,
            framebg = nil,
        }

        fl_toggle_btn = Button:new{
            text = fl.cur > fl.min and "ON" or "OFF",
            width = max_btn_w,
            show_parent = touch_menu.show_parent,
            callback = function()
                if fl.cur > fl.min then
                    fl_saved_brightness = fl.cur
                    setBrightness(fl.min)
                else
                    setBrightness(fl_saved_brightness)
                end
            end,
            bordersize = 0,
            background = nil,
            framebg = nil,
        }

        local fl_row = HorizontalGroup:new{
            align = "center",
            fl_minus,
            HorizontalSpan:new{ width = slider_gap },
            fl_slider,
            HorizontalSpan:new{ width = slider_gap },
            fl_plus,
            HorizontalSpan:new{ width = slider_gap },
            fl_toggle_btn,
        }

        local fl_group = VerticalGroup:new{ align = "center" }
        if fl_label then
            table.insert(fl_group, fl_label)
            table.insert(fl_group, VerticalSpan:new{ width = Screen:scaleBySize(6) })
        end
        table.insert(fl_group, fl_row)

        table.insert(panel, VerticalSpan:new{ width = Screen:scaleBySize(10) })
        table.insert(panel, CenterContainer:new{ dimen = Geom:new{ w = panel_w, h = fl_group:getSize().h }, fl_group })

        refs.fl_slider = fl_slider
        refs.setBrightness = setBrightness
    end

    -- Warmth slider
    if Utils.getBool("qa_panel_warmth") and Device:hasNaturalLight() then
        local powerd = Device:getPowerDevice()
        local nl = {
            min = powerd.fl_warmth_min,
            max = powerd.fl_warmth_max,
            cur = powerd:toNativeWarmth(powerd:frontlightWarmth()),
        }
        local small_btn_w = Screen:scaleBySize(40)
        local max_btn_w = Screen:scaleBySize(50)
        local slider_gap = Screen:scaleBySize(4)
        local warmth_slider_w = inner_w - 2 * small_btn_w - max_btn_w - 3 * slider_gap

        local nl_label = nil
        if Utils.getBool("qa_panel_slider_show_value") then
            nl_label = TextWidget:new{
                text = _("Warmth") .. ": " .. tostring(nl.cur),
                face = medium_face,
                max_width = inner_w,
            }
        end

        local _dummy2 = Button:new{ text = "−", width = small_btn_w, show_parent = touch_menu.show_parent, callback = function() end }
        local btn_height2 = math.max(30, _dummy2:getSize().h)

        local nl_slider = SlimSlider:new{
            width = warmth_slider_w,
            height = btn_height2,
            minimum = nl.min,
            maximum = nl.max,
            value = nl.cur,
            show_parent = touch_menu.show_parent,
            enabled = true,
        }

        local function setWarmth(warmth)
            if warmth == nl.cur then return end
            warmth = math.max(nl.min, math.min(nl.max, warmth))
            powerd:setWarmth(powerd:fromNativeWarmth(warmth))
            nl.cur = powerd:toNativeWarmth(powerd:frontlightWarmth())
            nl_slider:setValue(nl.cur)
            if nl_label then
                nl_label:setText(_("Warmth") .. ": " .. tostring(nl.cur))
            end
            UIManager:setDirty(touch_menu.show_parent, "ui")
        end

        local nl_minus = Button:new{
            text = "−", width = small_btn_w, show_parent = touch_menu.show_parent,
            callback = function() setWarmth(nl.cur - 1) end,
            bordersize = 0,
            background = nil,
            framebg = nil,
        }

        local nl_plus = Button:new{
            text = "＋", width = small_btn_w, show_parent = touch_menu.show_parent,
            callback = function() setWarmth(nl.cur + 1) end,
            bordersize = 0,
            background = nil,
            framebg = nil,
        }

        local nl_max_btn = Button:new{
            text = _("Max"), width = max_btn_w, show_parent = touch_menu.show_parent,
            callback = function() setWarmth(nl.max) end,
            bordersize = 0,
            background = nil,
            framebg = nil,
        }

        local nl_row = HorizontalGroup:new{
            align = "center",
            nl_minus,
            HorizontalSpan:new{ width = slider_gap },
            nl_slider,
            HorizontalSpan:new{ width = slider_gap },
            nl_plus,
            HorizontalSpan:new{ width = slider_gap },
            nl_max_btn,
        }

        local warmth_group = VerticalGroup:new{ align = "center" }
        table.insert(warmth_group, VerticalSpan:new{ width = Screen:scaleBySize(12) })
        if nl_label then
            table.insert(warmth_group, nl_label)
            table.insert(warmth_group, VerticalSpan:new{ width = Screen:scaleBySize(6) })
        end
        table.insert(warmth_group, nl_row)

        table.insert(panel, CenterContainer:new{ dimen = Geom:new{ w = panel_w, h = warmth_group:getSize().h }, warmth_group })
        refs.nl_slider = nl_slider
    end

    table.insert(panel, VerticalSpan:new{ width = Screen:scaleBySize(14) })

    local panel_h = panel:getSize().h
    local ic = InputContainer:new{ dimen = Geom:new{ w = panel_w, h = panel_h }, [1] = panel }

    ic.ges_events = {
        HoldPanel = { require("ui/gesturerange"):new{ ges = "hold", range = function() return ic.dimen end } },
    }

    function ic:onHoldPanel()
        if not Utils.getBool("qa_panel_settings_on_hold") then return false end
        if settings_mod and settings_mod.showPanelSettings then
            settings_mod.showPanelSettings()
        end
        return true
    end

    _qs_refs = refs
    return ic, refs
end

-- ============================================================
-- TouchMenu Patches
-- ============================================================

function QA.patchTouchMenu()
    -- Inject _qa_panel tab into tab_item_table
    local function injectQATab(menu)
        if not menu or not menu.tab_item_table then return end
        for __, tab in ipairs(menu.tab_item_table) do
            if tab._qa_panel then
                return
            end
        end
        table.insert(menu.tab_item_table, 1, {
            icon = Utils.getString("qa_common_tab_icon"),
            remember = false,
            _qa_panel = true,
        })
    end

    -- Patch FileManager menu
    local FMMenu = require("apps/filemanager/filemanagermenu")
    if not FMMenu._qa_tab_patched then
        FMMenu._qa_tab_patched = true
        local orig_setup = FMMenu.setUpdateItemTable
        FMMenu.setUpdateItemTable = function(self, ...)
            orig_setup(self, ...)
            injectQATab(self)
        end
    end

    -- Patch Reader menu
    local RMenu = require("apps/reader/modules/readermenu")
    if not RMenu._qa_tab_patched then
        RMenu._qa_tab_patched = true
        local orig_setup = RMenu.setUpdateItemTable
        RMenu.setUpdateItemTable = function(self, ...)
            orig_setup(self, ...)
            injectQATab(self)
            -- Move FileManager tab to the end in reader
            if self.tab_item_table then
                local fm_idx = nil
                for i, tab in ipairs(self.tab_item_table) do
                    if tab.id == "filemanager" or (tab.text and tab.text == _("File manager")) then
                        fm_idx = i
                        break
                    end
                end
                if fm_idx then
                    local fm_tab = table.remove(self.tab_item_table, fm_idx)
                    table.insert(self.tab_item_table, fm_tab)
                end
            end
        end
    end

    -- Remember last selected tab (QA tab is index 1)
    if FMMenu and not FMMenu._qa_close_patched then
        FMMenu._qa_close_patched = true
        local orig_onClose = FMMenu.onCloseFileManagerMenu
        FMMenu.onCloseFileManagerMenu = function(self)
            if self.menu_container and self.menu_container[1] then
                self.menu_container[1].last_index = 1
            end
            return orig_onClose(self)
        end
    end

    if RMenu and not RMenu._qa_close_patched then
        RMenu._qa_close_patched = true
        local orig_onClose = RMenu.onCloseReaderMenu
        RMenu.onCloseReaderMenu = function(self)
            if self.menu_container and self.menu_container[1] then
                self.menu_container[1].last_index = 1
                self.last_tab_index = 1
            end
            return orig_onClose(self)
        end
    end

    -- Override TouchMenu methods
    local TouchMenu = require("ui/widget/touchmenu")
    if TouchMenu._quickui_qa_patched then
        return
    end
    TouchMenu._quickui_qa_patched = true

    local _orig_updateItems = TouchMenu.updateItems
    local _orig_onTap = TouchMenu.onTapCloseAllMenus
    local _orig_onSwipe = TouchMenu.onSwipe
    local _orig_onPan = TouchMenu.onPan

    function TouchMenu:updateItems(target_page, target_item_id)
        if not self.item_table or not self.item_table._qa_panel then
            self._qs_refs = nil
            return _orig_updateItems(self, target_page, target_item_id)
        end

        self.page = 1
        self.page_num = 1

        self.item_group:clear()
        self.layout = {}
        table.insert(self.item_group, self.bar)
        table.insert(self.layout, self.bar.icon_widgets)

        local panel, refs = QA.buildPanel(self)
        self._qs_refs = refs
        table.insert(self.item_group, panel)
        table.insert(self.item_group, self.footer_top_margin)
        table.insert(self.item_group, self.footer)

        self.page_info_text:setText("")
        self.page_info_left_chev:showHide(false)
        self.page_info_right_chev:showHide(false)
        if self.page_info_left_chev then
            self.page_info_left_chev.hold_callback = nil
        end
        if self.page_info_right_chev then
            self.page_info_right_chev.hold_callback = nil
        end

        local G = rawget(_G, "G_reader_settings")
        local time_txt = datetime.secondsToHour(os.time(), G and G:isTrue("twelve_hour_clock") or false)
        if Device:hasBattery() then
            local powerd = Device:getPowerDevice()
            local lvl = powerd:getCapacity()
            local sym = powerd:getBatterySymbol(powerd:isCharged(), powerd:isCharging(), lvl)
            time_txt = BD.wrap(time_txt) .. " " .. BD.wrap("⌁") .. BD.wrap(sym) .. BD.wrap(lvl .. "%")
        end
        self.time_info:setText(time_txt)

        local old_dimen = self.dimen:copy()
        self.dimen.w = self.width
        self.dimen.h = self.item_group:getSize().h + self.bordersize * 2 + self.padding
        self:moveFocusTo(self.cur_tab, 1, FocusManager.NOT_FOCUS)

        local keep_bg = old_dimen and self.dimen.h >= old_dimen.h
        UIManager:setDirty(
            (self.is_fresh or keep_bg) and self.show_parent or "all",
            function()
                local refresh_dimen = old_dimen and old_dimen:combine(self.dimen) or self.dimen
                local refresh_type = self.is_fresh and "flashui" or "ui"
                self.is_fresh = false
                return refresh_type, refresh_dimen
            end
        )
    end

    function TouchMenu:onTapCloseAllMenus(arg, ges_ev)
        if self._qs_refs and self.item_table and self.item_table._qa_panel then
            if self._qs_refs.fl_slider and self._qs_refs.fl_slider.dimen and ges_ev.pos:intersectWith(self._qs_refs.fl_slider.dimen) then
                local new_val = self._qs_refs.fl_slider:getValueFromPosition(ges_ev.pos)
                if new_val and self._qs_refs.setBrightness then
                    self._qs_refs.setBrightness(math.floor(new_val + 0.5))
                    return true
                end
            end
            if self._qs_refs.nl_slider and self._qs_refs.nl_slider.dimen and ges_ev.pos:intersectWith(self._qs_refs.nl_slider.dimen) then
                local new_val = self._qs_refs.nl_slider:getValueFromPosition(ges_ev.pos)
                if new_val then
                    local powerd = Device:getPowerDevice()
                    powerd:setWarmth(powerd:fromNativeWarmth(math.floor(new_val + 0.5)))
                    return true
                end
            end
            for __, ref in ipairs(self._qs_refs.buttons or {}) do
                if ref.widget.dimen and ges_ev.pos:intersectWith(ref.widget.dimen) then
                    local stay_open = ref.callback()
                    if stay_open then
                        return true
                    end
                    self:onClose()
                    return true
                end
            end
        end
        return _orig_onTap(self, arg, ges_ev)
    end

    function TouchMenu:onSwipe(arg, ges_ev)
        if self._qs_refs and self.item_table and self.item_table._qa_panel then
            if self._qs_refs.fl_slider and self._qs_refs.fl_slider.dimen and ges_ev.pos:intersectWith(self._qs_refs.fl_slider.dimen) then
                local new_val = self._qs_refs.fl_slider:getValueFromPosition(ges_ev.pos)
                if new_val and self._qs_refs.setBrightness then
                    self._qs_refs.setBrightness(math.floor(new_val + 0.5))
                    return true
                end
            end
            if self._qs_refs.nl_slider and self._qs_refs.nl_slider.dimen and ges_ev.pos:intersectWith(self._qs_refs.nl_slider.dimen) then
                local new_val = self._qs_refs.nl_slider:getValueFromPosition(ges_ev.pos)
                if new_val then
                    local powerd = Device:getPowerDevice()
                    powerd:setWarmth(powerd:fromNativeWarmth(math.floor(new_val + 0.5)))
                    return true
                end
            end
            for __, ref in ipairs(self._qs_refs.buttons or {}) do
                if ref.widget.dimen and ges_ev.pos:intersectWith(ref.widget.dimen) then
                    local stay_open = ref.callback()
                    if stay_open then
                        return true
                    end
                    self:onClose()
                    return true
                end
            end
        end
        if _orig_onSwipe then
            return _orig_onSwipe(self, arg, ges_ev)
        end
    end

    function TouchMenu:onPan(arg, ges_ev)
        if self._qs_refs and self.item_table and self.item_table._qa_panel then
            if self._qs_refs.fl_slider and self._qs_refs.fl_slider.dimen and ges_ev.pos:intersectWith(self._qs_refs.fl_slider.dimen) then
                local new_val = self._qs_refs.fl_slider:getValueFromPosition(ges_ev.pos)
                if new_val and self._qs_refs.setBrightness then
                    self._qs_refs.setBrightness(math.floor(new_val + 0.5))
                    return true
                end
            end
            if self._qs_refs.nl_slider and self._qs_refs.nl_slider.dimen and ges_ev.pos:intersectWith(self._qs_refs.nl_slider.dimen) then
                local new_val = self._qs_refs.nl_slider:getValueFromPosition(ges_ev.pos)
                if new_val then
                    local powerd = Device:getPowerDevice()
                    powerd:setWarmth(powerd:fromNativeWarmth(math.floor(new_val + 0.5)))
                    return true
                end
            end
        end
        if _orig_onPan then
            return _orig_onPan(self, arg, ges_ev)
        end
    end
end

-- ============================================================
-- Public API: Show the panel
-- ============================================================

function QA.showPanel()
    local fm = require("apps/filemanager/filemanager").instance
    if fm and fm.menu then
        fm.menu:onShowMenu()
        local target_menu = fm.menu.menu_container and fm.menu.menu_container[1]
        if target_menu then
            for i, tab in ipairs(target_menu.tab_item_table or {}) do
                if tab._qa_panel then
                    target_menu:switchMenuTab(i)
                    break
                end
            end
        end
    end
end

return QA
