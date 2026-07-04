--[[
QuickUI - Bottom Navigation Bar

Based on QA Actions, uses registered quick actions as tabs.
Only responsible for building and displaying, all settings managed by qa_settings.lua.
]]

local logger = require("logger")
local _ = require("gettext")
local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Screen = Device.screen
local UIManager = require("ui/uimanager")
local Geom = require("ui/geometry")

-- Widget classes
local FrameContainer = require("ui/widget/container/framecontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local OverlapGroup = require("ui/widget/overlapgroup")
local LineWidget = require("ui/widget/linewidget")
local TextWidget = require("ui/widget/textwidget")
local ImageWidget = require("ui/widget/imagewidget")
local Font = require("ui/font")
local ButtonDialog = require("ui/widget/buttondialog")
local InfoMessage = require("ui/widget/infomessage")

local Utils = require("qui_utils")
local QA = require("qui_actions.qa_actions")
local settings = require("qui_actions.qa_settings")

-- ============================================================
-- Module State
-- ============================================================

local M = {}

M._add_tab_dialog = nil

-- ============================================================
-- Configuration - Read from _G.__QUICKUI_CONFIG
-- ============================================================

local function get(key, default)
    local config = _G.__QUICKUI_CONFIG
    if config and config[key] ~= nil then
        return config[key]
    end
    return default
end

local function getBool(key, default)
    local config = _G.__QUICKUI_CONFIG
    if config and config[key] ~= nil then
        return config[key] == true
    end
    return default or false
end

local function getString(key, default)
    local config = _G.__QUICKUI_CONFIG
    if config and config[key] ~= nil then
        return config[key]
    end
    return default or ""
end

local function getNumber(key, default)
    local config = _G.__QUICKUI_CONFIG
    if config and config[key] ~= nil then
        return config[key]
    end
    return default or 0
end

local function set(key, value)
    local config = _G.__QUICKUI_CONFIG
    if config then
        config[key] = value
        Utils.saveConfig()
    end
end

-- ============================================================
-- Constants
-- ============================================================

local MAX_TABS = 16

-- ============================================================
-- Dimension Calculation
-- ============================================================

local function getNavbarScale()
    return (getNumber("qa_bb_size_pct", 100) or 100) / 100
end

function M.BAR_H()
    return math.floor(Screen:scaleBySize(60) * getNavbarScale())
end

function M.ICON_SZ()
    local icon_scale = (getNumber("qa_bb_icon_scale_pct", 100) or 100) / 100
    return math.floor(Screen:scaleBySize(19) * getNavbarScale() * icon_scale)
end

function M.LABEL_FS()
    local label_scale = (getNumber("qa_bb_label_scale_pct", 100) or 100) / 100
    return math.floor(12 * getNavbarScale() * label_scale)
end

function M.INDIC_H()
    return math.floor(Screen:scaleBySize(2) * getNavbarScale())
end

function M.TOP_SP()
    return Screen:scaleBySize(1)
end

function M.BOT_SP()
    local margin = (getNumber("qa_bb_bottom_margin_pct", 100) or 100) / 100
    return math.floor(Screen:scaleBySize(1) * margin)
end

function M.SIDE_M()
    return Screen:scaleBySize(12)
end

function M.SEP_H()
    if getString("qa_bb_style") == "framed" then return 0 end
    return Screen:scaleBySize(1)
end

function M.TOTAL_H()
    if not getBool("qa_bb_enabled", true) then return 0 end
    return M.BAR_H() + M.TOP_SP() + M.BOT_SP()
end

-- ============================================================
-- Colors
-- ============================================================

local function getBarBg()
    if getBool("qa_bb_transparent", false) then return nil end
    local hex = getString("qa_bb_bg_color", "")
    if hex ~= "" then
        local c = Utils.hexToColor(hex)
        if c then return c end
    end
    return Blitbuffer.COLOR_WHITE
end

local function getBarFg()
    local hex = getString("qa_bb_fg_color", "")
    if hex ~= "" then
        local c = Utils.hexToColor(hex)
        if c then return c end
    end
    return Blitbuffer.COLOR_BLACK
end

local function getInactiveColor()
    local hex = getString("qa_bb_inactive_color", "")
    if hex ~= "" then
        local c = Utils.hexToColor(hex)
        if c then return c end
    end
    return Blitbuffer.gray(0.55)
end

local function getAccentColor()
    local hex = getString("qa_bb_accent_color", "")
    if hex ~= "" then
        local c = Utils.hexToColor(hex)
        if c then return c end
    end
    return getBarFg()
end

-- ============================================================
-- Icon Widget
-- ============================================================

local function makeIconWidget(icon_path, size, fgcolor)
    if not icon_path then
        return TextWidget:new{
            text = "?",
            face = Font:getFace("cfont", math.floor(size * 0.6)),
            fgcolor = fgcolor,
        }
    end

    local nerd_char = QA.nerdIconChar(icon_path)
    if nerd_char then
        local tw = TextWidget:new{
            text = nerd_char,
            face = Font:getFace("symbols", math.floor(size * 0.75)),
            fgcolor = fgcolor,
            padding = 0,
        }
        local wrapper = require("ui/widget/container/widgetcontainer"):new{}
        wrapper.dimen = Geom:new{ w = size, h = size }
        wrapper._inner = tw
        wrapper._fg = fgcolor
        function wrapper:getSize() return self.dimen end
        function wrapper:paintTo(bb, x, y)
            self.dimen.x, self.dimen.y = x, y
            self._inner.fgcolor = self._fg
            local sz = self._inner:getSize()
            local ox = x + math.floor((size - sz.w) / 2)
            local oy = y + math.floor((size - sz.h) / 2)
            self._inner:paintTo(bb, ox, oy)
        end
        function wrapper:free()
            if self._inner then self._inner:free(); self._inner = nil end
        end
        return wrapper
    end

    local file_path = Utils.getIconFile(icon_path)
    if file_path and Utils.fileExists(file_path) then
        local iw = ImageWidget:new{
            file = file_path,
            width = size,
            height = size,
            alpha = true,
        }
        local ok_render = pcall(function() iw:_render() end)
        if ok_render then
            return iw
        else
            iw:free()
        end
    end

    return nil
end

-- ============================================================
-- Build Tab Cell
-- ============================================================

function M.buildTabCell(action_id, active, tab_w, mode)
    local label = QA.getLabelForAction(action_id) or action_id
    local icon_path = QA.getIconForAction(action_id)
    local vg = VerticalGroup:new{ align = "center" }
    local fg = active and getAccentColor() or getBarFg()
    local bar_style = getString("qa_bb_style", "default")
    local show_labels = getBool("qa_bb_labels", false)

    if mode == "icons" or mode == "both" then
        local icon_widget = makeIconWidget(icon_path, M.ICON_SZ(), fg)
        if icon_widget then
            vg[#vg + 1] = CenterContainer:new{
                dimen = Geom:new{ w = tab_w, h = M.ICON_SZ() },
                icon_widget,
            }
        else
            local first = label:sub(1, 1):upper()
            vg[#vg + 1] = CenterContainer:new{
                dimen = Geom:new{ w = tab_w, h = M.ICON_SZ() },
                TextWidget:new{
                    text = first,
                    face = Font:getFace("cfont", math.floor(M.ICON_SZ() * 0.55)),
                    fgcolor = fg,
                },
            }
        end
    end

    if show_labels and (mode == "text" or mode == "both") then
        if mode == "both" then
            vg[#vg + 1] = VerticalSpan:new{ width = Screen:scaleBySize(2) }
        end
        local label_max_w = math.max(20, tab_w - Screen:scaleBySize(8))
        vg[#vg + 1] = TextWidget:new{
            text = label,
            face = Font:getFace("cfont", M.LABEL_FS()),
            fgcolor = fg,
            bold = active or false,
            max_width = label_max_w,
            truncate_with_ellipsis = true,
        }
    end

    local content = CenterContainer:new{
        dimen = Geom:new{ w = tab_w, h = M.BAR_H() },
        vg,
    }

    local og = OverlapGroup:new{
        allow_mirroring = false,
        dimen = Geom:new{ w = tab_w, h = M.BAR_H() },
        content,
    }

    if bar_style == "default" and not getBool("qa_bb_transparent", false) then
        if active then
            og[#og + 1] = LineWidget:new{
                dimen = Geom:new{ w = tab_w, h = M.INDIC_H() },
                background = getAccentColor(),
                overlap_offset = { 0, 0 },
            }
        else
            og[#og + 1] = LineWidget:new{
                dimen = Geom:new{ w = tab_w, h = M.INDIC_H() },
                background = getBarBg() or Blitbuffer.COLOR_WHITE,
                overlap_offset = { 0, 0 },
            }
        end
    end

    return og
end

-- ============================================================
-- Tab Width Calculation
-- ============================================================

local _tab_widths_cache = {}

function M.getTabWidths(num_tabs, usable_w)
    local base_w = math.floor(usable_w / num_tabs)
    for i = 1, num_tabs do
        _tab_widths_cache[i] = (i == num_tabs) and (usable_w - base_w * (num_tabs - 1)) or base_w
    end
    for i = num_tabs + 1, #_tab_widths_cache do _tab_widths_cache[i] = nil end
    return _tab_widths_cache
end

-- ============================================================
-- Container Builder
-- ============================================================

local function buildContainer(hg_args)
    local style = getString("qa_bb_style", "default")
    local bg = getBarBg()

    if style == "framed" then
        local radius = math.floor(Screen:scaleBySize(8) * getNavbarScale())
        local border_color = getBarFg()
        local border_sz = Screen:scaleBySize(1)

        local hg = HorizontalGroup:new(hg_args)
        local fc = FrameContainer:new{
            bordersize = border_sz,
            color = border_color,
            background = bg,
            radius = radius,
            padding = 0,
            margin = 0,
            hg,
        }

        return FrameContainer:new{
            bordersize = 0,
            padding = 0,
            margin = 0,
            padding_left = M.SIDE_M(),
            padding_right = M.SIDE_M(),
            padding_top = M.TOP_SP(),
            padding_bottom = M.BOT_SP(),
            background = nil,
            fc,
        }
    end

    local hg = HorizontalGroup:new(hg_args)
    local fc = FrameContainer:new{
        bordersize = 0,
        padding = 0,
        padding_left = M.SIDE_M(),
        padding_right = M.SIDE_M(),
        padding_bottom = M.BOT_SP(),
        margin = 0,
        background = bg,
        hg,
    }

    local top_vg = VerticalGroup:new{ align = "center" }
    local sep_h = M.SEP_H()

    if style == "default" and sep_h > 0 then
        top_vg[#top_vg + 1] = LineWidget:new{
            dimen = Geom:new{ w = Screen:getWidth() - M.SIDE_M() * 2, h = sep_h },
            background = Blitbuffer.gray(0.7),
        }
    else
        top_vg[#top_vg + 1] = VerticalSpan:new{ width = M.TOP_SP() }
    end

    local top_fc = FrameContainer:new{
        bordersize = 0,
        padding = 0,
        margin = 0,
        padding_left = M.SIDE_M(),
        padding_right = M.SIDE_M(),
        background = nil,
        top_vg,
    }

    return VerticalGroup:new{
        align = "center",
        top_fc,
        fc,
    }
end

-- ============================================================
-- Build Full Bar
-- ============================================================

function M.buildBar(active_action_id)
    local tabs = getTabs()
    local num_tabs = #tabs
    local mode = getString("qa_bb_mode", "both")
    local screen_w = Screen:getWidth()
    local side_m = M.SIDE_M()
    local usable_w = screen_w - side_m * 2
    local hg_args = { align = "top" }

    if num_tabs == 0 then
        local vg = VerticalGroup:new{ align = "center" }
        vg[#vg + 1] = VerticalSpan:new{ width = M.BAR_H() }
        return buildContainer({ align = "top", vg })
    end

    local widths = M.getTabWidths(num_tabs, usable_w)
    for i = 1, num_tabs do
        local action_id = tabs[i]
        hg_args[#hg_args + 1] = M.buildTabCell(
            action_id,
            action_id == active_action_id,
            widths[i],
            mode
        )
    end

    return buildContainer(hg_args)
end

-- ============================================================
-- Tab Configuration
-- ============================================================

function getAvailableActions()
    return QA.getAllAvailableActions() or {}
end

function getTabs()
    local tabs = get("qa_bb_tabs", nil)

    local filter_enabled = getBool("qa_common_context_filter")

    local current_view = "common"
    if filter_enabled then
        local RUI = require("apps/reader/readerui")
        local in_reader = RUI and RUI.instance and not RUI.instance.tearing_down
        if in_reader then
            current_view = "reader"
        else
            local FM = require("apps/filemanager/filemanager")
            local in_fm = FM and FM.instance
            if in_fm then
                current_view = "filemanager"
            end
        end
    end

    if type(tabs) == "table" and #tabs > 0 then
        local valid = {}
        local action_map = {}
        for __, action in ipairs(getAvailableActions()) do
            action_map[action.id] = true
        end

        for __, id in ipairs(tabs) do
            if action_map[id] and #valid < MAX_TABS then
                if filter_enabled then
                    local view = QA.getActionViewFinal(id)
                    if current_view == "filemanager" then
                        if view == "filemanager" or view == "common" then
                            valid[#valid + 1] = id
                        end
                    elseif current_view == "reader" then
                        if view == "reader" or view == "common" then
                            valid[#valid + 1] = id
                        end
                    else
                        valid[#valid + 1] = id
                    end
                else
                    valid[#valid + 1] = id
                end
            end
        end

        if #valid > 0 then
            return valid
        end
        if _G.__QUICKUI_CONFIG and _G.__QUICKUI_CONFIG.qa_bb_tabs then
           return _G.__QUICKUI_CONFIG.qa_bb_tabs
        end
       return  {}
   end
end

function M.isEnabled()
    return getBool("qa_bb_enabled", true)
end

function M.setEnabled(enabled)
    set("qa_bb_enabled", enabled)
end

-- ============================================================
-- Execute Action
-- ============================================================

function M.executeAction(action_id, ctx)
    return QA.executeAction(action_id, ctx)
end

-- ============================================================
-- Touch Zone Registration
-- ============================================================

function M.registerTouchZones(fm_self)
    local tabs = getTabs()
    local num_tabs = #tabs
    local screen_w = Screen:getWidth()
    local screen_h = Screen:getHeight()
    local nav_h = M.TOTAL_H()
    local bar_y = screen_h - nav_h
    local side_m = M.SIDE_M()
    local usable_w = screen_w - side_m * 2

    if nav_h <= 0 or num_tabs == 0 then return end

    local old_zones = {}
    for i = 1, num_tabs do
        old_zones[#old_zones + 1] = { id = "bb_tab_" .. i }
        old_zones[#old_zones + 1] = { id = "bb_tab_hold_" .. i }
    end
    old_zones[#old_zones + 1] = { id = "bb_hold_settings" }
    if fm_self.unregisterTouchZones then
        fm_self:unregisterTouchZones(old_zones)
    end

    local widths = M.getTabWidths(num_tabs, usable_w)
    local zones = {}
    local overrides = { "tap_left_bottom_corner", "tap_right_bottom_corner" }

    local cumulative = 0
    for i = 1, num_tabs do
        local x_start = side_m + cumulative
        local this_tab_w = widths[i]
        cumulative = cumulative + this_tab_w

        local pos = i

        -- tap to execute
        zones[#zones + 1] = {
            id = "bb_tab_" .. i,
            ges = "tap",
            overrides = overrides,
            screen_zone = {
                ratio_x = x_start / screen_w,
                ratio_y = bar_y / screen_h,
                ratio_w = this_tab_w / screen_w,
                ratio_h = nav_h / screen_h,
            },
            handler = function()
                local action_id = tabs[pos]
                if action_id then
                    M.executeAction(action_id, {})
                end
                return true
            end,
        }

        -- hold to edit
        zones[#zones + 1] = {
            id = "bb_tab_hold_" .. i,
            ges = "hold",
            overrides = overrides,
            screen_zone = {
                ratio_x = x_start / screen_w,
                ratio_y = bar_y / screen_h,
                ratio_w = this_tab_w / screen_w,
                ratio_h = nav_h / screen_h,
            },
            handler = function()
                if not getBool("qa_bb_button_hold_edit", true) then
                    return true
                end
                local action_id = tabs[pos]
                if not action_id then return true end

                local is_builtin = QA.isBuiltinAction and QA.isBuiltinAction(action_id)
                local settings = require("qui_actions.qa_settings")

                if settings then
                    if is_builtin then
                        settings.showEditActionDialog(action_id, function()
                            if fm_self and fm_self.updateItems then
                                fm_self:updateItems()
                            end
                            M.rebuildBottombar()
                        end, "bottombar")
                    else
                        settings.showCustomQADialog(action_id, function()
                            if fm_self and fm_self.updateItems then
                                fm_self:updateItems()
                            end
                            M.rebuildBottombar()
                        end, "bottombar")
                    end
                end
                return true
            end,
        }
    end

    -- hold on empty area to open settings
    zones[#zones + 1] = {
        id = "bb_hold_settings",
        ges = "hold_release",
        screen_zone = {
            ratio_x = 0,
            ratio_y = bar_y / screen_h,
            ratio_w = 1,
            ratio_h = nav_h / screen_h,
        },
        handler = function()
            if getBool("qa_bb_settings_on_hold", true) then
                local settings = require("qui_actions.qa_settings")
                if settings and settings.showBottombarSettings then
                    settings.showBottombarSettings()
                end
            end
            return true
        end,
    }

    if fm_self.registerTouchZones then
        fm_self:registerTouchZones(zones)
    end
end

-- ============================================================
-- Wrapper - Add bottombar to existing UI
-- ============================================================

function M.wrapWithBottombar(inner_widget)
    if not getBool("qa_bb_enabled", true) then return inner_widget end

    local screen_w = Screen:getWidth()
    local screen_h = Screen:getHeight()
    local nav_h = M.TOTAL_H()
    local content_h = screen_h - nav_h
    local content_y = 0

    if inner_widget.dimen then
        inner_widget.dimen.h = content_h
        inner_widget.dimen.w = screen_w
        inner_widget.dimen.y = content_y
    end
    if inner_widget.height ~= nil then
        inner_widget.height = content_h
    end
    if inner_widget.y ~= nil then
        inner_widget.y = content_y
    end

    local fc = inner_widget.file_chooser or inner_widget
    if fc then
        if fc.height ~= nil then
            fc.height = content_h
        end
        if fc.y ~= nil then
            fc.y = content_y
        end
        if fc.dimen then
            fc.dimen.h = content_h
            fc.dimen.y = content_y
        end

        local bordersize = fc.bordersize or 0
        local padding = fc.padding or 0
        fc.available_height = content_h - bordersize * 2 - padding * 2

        if fc._recalculateDimen then
            fc:_recalculateDimen()
        end
        if fc.updateItems then
            fc:updateItems()
        end
    end

    if inner_widget._bottombar_injected then
        if inner_widget.dimen then
            inner_widget.dimen.h = content_h
            inner_widget.dimen.y = content_y
        end
        if inner_widget[1] and inner_widget[1].dimen then
            inner_widget[1].dimen.h = content_h
            inner_widget[1].dimen.y = content_y
        end
        if inner_widget._recalculateDimen then
            inner_widget:_recalculateDimen()
        end
    end

    local active_action = getTabs()[1]
    local bar = M.buildBar(active_action)
    local bar_y = screen_h - nav_h
    bar.overlap_offset = { 0, bar_y }

    local og = OverlapGroup:new{
        allow_mirroring = false,
        dimen = Geom:new{ w = screen_w, h = screen_h },
        inner_widget,
        bar,
    }

    og._bottombar_inner = inner_widget
    og._bottombar_bar = bar
    og._bottombar_bar_idx = 2
    og._bottombar_container = og

    local is_bare = getString("qa_bb_style") == "bare"
    local bg = (getBool("qa_bb_transparent", false) or is_bare) and nil or Blitbuffer.COLOR_WHITE

    return FrameContainer:new{
        bordersize = 0,
        padding = 0,
        margin = 0,
        background = bg,
        og,
    }
end

-- ============================================================
-- Rebuild Bottombar
-- ============================================================

function M.rebuildBottombar()
    if not M.isEnabled() then
        M.removeBottombar()
        return
    end

    local FM = require("apps/filemanager/filemanager")
    local fm = FM.instance
    if fm then
        local inner = fm[1]
        if inner and inner._bottombar_inner then
            inner = inner._bottombar_inner
        end
        fm._bottombar_original_inner = inner

        local new_wrapped = M.wrapWithBottombar(inner)
        fm[1] = new_wrapped
        fm._bottombar_container = new_wrapped
        UIManager:setDirty(fm, "full")
        M.registerTouchZones(fm)
    end

    local RUI = require("apps/reader/readerui")
    local reader = RUI.instance
    if reader then
        local config = _G.__QUICKUI_CONFIG
        local show_in_reader = config and config.qa_bb_reader_enabled
        if show_in_reader ~= false then
            local inner_reader = reader[1]
            if inner_reader and inner_reader._bottombar_inner then
                inner_reader = inner_reader._bottombar_inner
            end
            reader._bottombar_original_inner = inner_reader

            local new_wrapped_reader = M.wrapWithBottombar(inner_reader)
            reader[1] = new_wrapped_reader
            reader._bottombar_container = new_wrapped_reader
            UIManager:setDirty(reader, "full")
            M.registerTouchZones(reader)
        else
            if reader._bottombar_original_inner then
                reader[1] = reader._bottombar_original_inner
                reader._bottombar_container = nil
                reader._bottombar_original_inner = nil
                UIManager:setDirty(reader, "full")
                if reader.unregisterTouchZones then
                    local tabs = M.getTabs() or {}
                    local zones = {}
                    for i = 1, #tabs do
                        zones[#zones + 1] = { id = "bb_tab_" .. i }
                        zones[#zones + 1] = { id = "bb_tab_hold_" .. i }
                    end
                    zones[#zones + 1] = { id = "bb_hold_settings" }
                    reader:unregisterTouchZones(zones)
                end
            end
        end
    end
   logger.info("QuickUI QA BottomBar: rebuildBottombar done")
end

-- ============================================================
-- Remove Bottombar
-- ============================================================

function M.removeBottombar()
    logger.info("QuickUI QA BottomBar: removeBottombar called")

    local FM = require("apps/filemanager/filemanager")
    local fm = FM and FM.instance
    if fm and fm._bottombar_original_inner then
        logger.info("QuickUI QA BottomBar: removing from FileManager")
        fm[1] = fm._bottombar_original_inner
        fm._bottombar_container = nil
        fm._bottombar_original_inner = nil
        UIManager:setDirty(fm, "ui")
        if fm.unregisterTouchZones then
            local tabs = M.getTabs() or {}
            local zones = {}
            for i = 1, #tabs do
                zones[#zones + 1] = { id = "bb_tab_" .. i }
                zones[#zones + 1] = { id = "bb_tab_hold_" .. i }
            end
            zones[#zones + 1] = { id = "bb_hold_settings" }
            fm:unregisterTouchZones(zones)
        end
    end

    local RUI = require("apps/reader/readerui")
    local reader = RUI and RUI.instance
    if reader and reader._bottombar_original_inner then
        logger.info("QuickUI QA BottomBar: removing from Reader")
        reader[1] = reader._bottombar_original_inner
        reader._bottombar_container = nil
        reader._bottombar_original_inner = nil
        UIManager:setDirty(reader, "ui")
        if reader.unregisterTouchZones then
            local tabs = M.getTabs() or {}
            local zones = {}
            for i = 1, #tabs do
                zones[#zones + 1] = { id = "bb_tab_" .. i }
                zones[#zones + 1] = { id = "bb_tab_hold_" .. i }
            end
            zones[#zones + 1] = { id = "bb_hold_settings" }
            reader:unregisterTouchZones(zones)
        end
    end
end

-- ============================================================
-- Refresh
-- ============================================================

function M.refresh()
    logger.info("QuickUI QA BottomBar: refresh called")
    M.rebuildBottombar()
end

-- ============================================================
-- Show Add Tab Menu
-- ============================================================

function M.showAddTabMenu(on_back, filtered_actions)
    local current_tabs = get("qa_bb_tabs", nil)
    if type(current_tabs) ~= "table" then
        current_tabs = {}
    end

    -- Build tab_set for checking which actions are already added
    local tab_set = {}
    for __, id in ipairs(current_tabs) do
        tab_set[id] = true
    end

    local available = filtered_actions or getAvailableActions()

    table.sort(available, function(a, b)
        local a_checked = tab_set[a.id] or false
        local b_checked = tab_set[b.id] or false
        if a_checked ~= b_checked then
            return a_checked
        end
        local a_prio = QA.getTypePriority(a.id) or 999
        local b_prio = QA.getTypePriority(b.id) or 999
        if a_prio ~= b_prio then
            return a_prio < b_prio
        end
        return a.label:lower() < b.label:lower()
    end)

    local buttons = {}

    -- Search button
    table.insert(buttons, { Utils.createSearchButton(
        function()
            M.showAddTabMenu(on_back)
        end,
        function(keyword)
            local filtered = Utils.filterActionsByKeyword(getAvailableActions(), keyword)
            M.showAddTabMenu(on_back, filtered)
        end,
        function()
            if M._add_tab_dialog then
                UIManager:close(M._add_tab_dialog)
                M._add_tab_dialog = nil
            end
        end
    ) })
    table.insert(buttons, {})

    -- Navigation buttons
    table.insert(buttons, {
        {
            text = "◂◂ " .. _("Back to Root"),
            callback = function()
                if M._add_tab_dialog then
                    UIManager:close(M._add_tab_dialog)
                    M._add_tab_dialog = nil
                end
                if settings and settings.showSettings then
                    settings.showSettings()
                end
            end
        }
    })

    table.insert(buttons, {
        {
            text = "◂ " .. _("Back"),
            callback = function()
                if M._add_tab_dialog then
                    UIManager:close(M._add_tab_dialog)
                    M._add_tab_dialog = nil
                end
                if settings and settings.showBottombarSettings then
                    settings.showBottombarSettings()
                end
            end
        }
    })
    table.insert(buttons, {})

    -- Select All / Deselect All
    local all_checked = true
    for __, action in ipairs(available) do
        if not tab_set[action.id] then
            all_checked = false
            break
        end
    end

    table.insert(buttons, {
        {
            text = all_checked and "☑ " .. _("Deselect All") or "☐ " .. _("Select All"),
            callback = function()
                local is_all_checked = true
                for __, action in ipairs(available) do
                    if not tab_set[action.id] then
                        is_all_checked = false
                        break
                    end
                end

                local new_tabs = {}
                if is_all_checked then
                    for __, id in ipairs(current_tabs) do
                        local still_available = false
                        for __, action in ipairs(available) do
                            if action.id == id then
                                still_available = true
                                break
                            end
                        end
                        if not still_available then
                            new_tabs[#new_tabs + 1] = id
                        end
                    end
                else
                    for __, id in ipairs(current_tabs) do
                        new_tabs[#new_tabs + 1] = id
                    end
                    for __, action in ipairs(available) do
                        if not tab_set[action.id] then
                            if #new_tabs < MAX_TABS then
                                new_tabs[#new_tabs + 1] = action.id
                            end
                        end
                    end
                end

                set("qa_bb_tabs", new_tabs)
                M.refresh()
                if M._add_tab_dialog then
                    UIManager:close(M._add_tab_dialog)
                    M._add_tab_dialog = nil
                end
                M.showAddTabMenu(on_back)
            end,
        }
    })

    table.insert(buttons, {})

    -- Action list
    for __, action in ipairs(available) do
        local is_checked = tab_set[action.id] or false
        local symbol = QA.getActionSymbol(action.id)
        local view_tag = " [" .. (action.view or "common") .. "]"
        local display_text = (is_checked and "✓ " or "  ") .. symbol .. action.label .. view_tag

        table.insert(buttons, {
            {
                text = display_text,
                callback = function()
                    local new_tabs = {}

                    if is_checked then
                        for __, id in ipairs(current_tabs) do
                            if id ~= action.id then
                                new_tabs[#new_tabs + 1] = id
                            end
                        end
                    else
                        if #current_tabs >= MAX_TABS then
                            UIManager:show(InfoMessage:new{
                                text = string.format(_("Max %d tabs"), MAX_TABS),
                                timeout = 2,
                            })
                            return
                        end
                        for __, id in ipairs(current_tabs) do
                            new_tabs[#new_tabs + 1] = id
                        end
                        new_tabs[#new_tabs + 1] = action.id
                    end

                    set("qa_bb_tabs", new_tabs)
                    M.refresh()
                    if M._add_tab_dialog then
                        UIManager:close(M._add_tab_dialog)
                        M._add_tab_dialog = nil
                    end
                    M.showAddTabMenu(on_back)
                end,
            }
        })
    end

    table.insert(buttons, {})
    table.insert(buttons, {
        {
            text = _("Close"),
            callback = function()
                if M._add_tab_dialog then
                    UIManager:close(M._add_tab_dialog)
                    M._add_tab_dialog = nil
                end
            end
        }
    })

    M._add_tab_dialog = ButtonDialog:new{
        title = _("Add Tab"),
        title_align = "center",
        buttons = buttons,
        width = math.floor(Screen:getWidth() * 0.7),
        max_height = math.floor(Screen:getHeight() * 0.7),
        rows_per_page = 10,
    }
    UIManager:show(M._add_tab_dialog)
end

-- ============================================================
-- Export getTabs for qa_settings
-- ============================================================

function M.getTabs()
    return getTabs()
end

-- ============================================================
-- Initialization
-- ============================================================

function M.init()
    Utils.patchFileChooserForBottombar()
    Utils.registerRefreshHandler("qa_bb", M.refresh)

    -- Hook screen rotation
    local function hookDeviceListener()
        local ok, DeviceListener = pcall(require, "device/devicelistener")
        if not ok or not DeviceListener then
            logger.warn("QuickUI QA BottomBar: DeviceListener not found")
            return
        end

        local orig_onSwapRotation = DeviceListener.onSwapRotation
        function DeviceListener:onSwapRotation()
            local result
            if orig_onSwapRotation then
                result = orig_onSwapRotation(self)
            end
            if _G.__QUICKUI_CONFIG and _G.__QUICKUI_CONFIG.qa_bb_enabled then
                M.rebuildBottombar()
            end
            return result
        end
    end
    UIManager:scheduleIn(0.5, hookDeviceListener)

    logger.info("QuickUI QA BottomBar: initialized")
    UIManager:scheduleIn(0.1, function()
       M.rebuildBottombar()
    end)
end

return M