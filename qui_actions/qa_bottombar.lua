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
local InputContainer = require("ui/widget/container/inputcontainer")
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
local Notification = require("ui/widget/notification")

local Utils = require("qui_utils")
local QA = require("qui_actions.qa_actions")
local settings = require("qui_actions.qa_settings")

-- ============================================================
-- Module State
-- ============================================================

local M = {}

M._add_tab_dialog = nil

-- ============================================================
-- Constants
-- ============================================================

local MAX_TABS = 16

-- ============================================================
-- Dimension Calculation
-- ============================================================

local function getNavbarScale()
    return (Utils.getNumber("qa_bb_size_pct", 100) or 100) / 100
end

function M.BAR_H()
    return math.floor(Screen:scaleBySize(60) * getNavbarScale())
end

function M.ICON_SZ()
    local icon_scale = (Utils.getNumber("qa_bb_icon_scale_pct", 100) or 100) / 100
    return math.floor(Screen:scaleBySize(19) * getNavbarScale() * icon_scale)
end

function M.LABEL_FS()
    local label_scale = (Utils.getNumber("qa_bb_label_scale_pct", 100) or 100) / 100
    return math.floor(12 * getNavbarScale() * label_scale)
end

function M.INDIC_H()
    return math.floor(Screen:scaleBySize(2) * getNavbarScale())
end

function M.TOP_SP()
    return Screen:scaleBySize(1)
end

function M.BOT_SP()
    local margin = (Utils.getNumber("qa_bb_bottom_margin_pct", 100) or 100) / 100
    return math.floor(Screen:scaleBySize(1) * margin)
end

function M.SIDE_M()
    return Screen:scaleBySize(12)
end

function M.SEP_H()
    if Utils.getString("qa_bb_style") == "framed" then return 0 end
    return Screen:scaleBySize(1)
end

function M.TOTAL_H()
    if not Utils.getBool("qa_bb_enabled", true) then return 0 end
    return M.BAR_H() + M.TOP_SP() + M.BOT_SP()
end

-- ============================================================
-- Colors
-- ============================================================

local function getBarBg()
    if Utils.getBool("qa_bb_transparent", false) then return nil end
    local hex = Utils.getString("qa_bb_bg_color", "")
    if hex ~= "" then
        local c = Utils.hexToColor(hex)
        if c then return c end
    end
    return Blitbuffer.COLOR_WHITE
end

local function getBarFg()
    local hex = Utils.getString("qa_bb_fg_color", "")
    if hex ~= "" then
        local c = Utils.hexToColor(hex)
        if c then return c end
    end
    return Blitbuffer.COLOR_BLACK
end

local function getInactiveColor()
    local hex = Utils.getString("qa_bb_inactive_color", "")
    if hex ~= "" then
        local c = Utils.hexToColor(hex)
        if c then return c end
    end
    return Blitbuffer.gray(0.55)
end

local function getAccentColor()
    local hex = Utils.getString("qa_bb_accent_color", "")
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
    local bar_style = Utils.getString("qa_bb_style", "default")
    local show_labels = Utils.getBool("qa_bb_labels", false)

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

    if bar_style == "default" and not Utils.getBool("qa_bb_transparent", false) then
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
    local style = Utils.getString("qa_bb_style", "default")
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
    -- Safely get tabs, always returns a table
    local tabs = getTabs() or {}
    local num_tabs = #tabs
    local mode = Utils.getString("qa_bb_mode", "both")
    local screen_w = Screen:getWidth()
    local side_m = M.SIDE_M()
    local usable_w = screen_w - side_m * 2
    local hg_args = { align = "top" }

    -- Handle empty tabs: show friendly message
    if num_tabs == 0 then
        local vg = VerticalGroup:new{ align = "center" }

        local hint_text = TextWidget:new{
            text = _("No actions configured, tap to add"),
            face = Utils.getFontFace("cfont", Utils.scaleBySize(14)),
            fgcolor = Blitbuffer.gray(0.5),
        }
        local hint_w = hint_text:getSize().w
        local hint_h = hint_text:getSize().h

        local hint_wrapper = InputContainer:new{
            dimen = Geom:new{ w = hint_w, h = hint_h },
        }
        hint_wrapper[1] = hint_text
        hint_wrapper:registerTouchZones({
            {
                id = "bb_empty_hint_tap",
                ges = "tap",
                screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
                handler = function(ges)
                    local d = hint_wrapper.dimen
                    if d and ges.pos.x >= d.x and ges.pos.x <= d.x + d.w
                       and ges.pos.y >= d.y and ges.pos.y <= d.y + d.h then
                        M.showAddTabMenu()
                        return true
                    end
                    return false
                end,
            },
        })

        local center = CenterContainer:new{
            dimen = Geom:new{ w = usable_w, h = M.BAR_H() },
            hint_wrapper,
        }
        vg[#vg + 1] = center
        hg_args[#hg_args + 1] = vg
        return buildContainer(hg_args)
    end

    -- Build tabs normally
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
    local tabs = Utils.get("qa_bb_tabs", nil)

    local filter_enabled = Utils.getBool("qa_common_context_filter")

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

    -- Ensure tabs is a table
    if type(tabs) == "table" and #tabs > 0 then
        local valid = {}
        local action_map = {}
        local available_actions = getAvailableActions() or {}
        for __, action in ipairs(available_actions) do
            if action and action.id then
                action_map[action.id] = true
            end
        end

        for __, id in ipairs(tabs) do
            -- Skip orphan ids and unavailable actions (plugin not loaded).
            -- Never writes back to config.
            if action_map[id] and #valid < MAX_TABS and QA.isActionAvailable(id) then
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
        -- No valid tabs found, return empty table
        return {}
    end
    
    -- Always return a table (empty if no tabs configured)
    return {}
end

function M.isEnabled()
    return Utils.getBool("qa_bb_enabled", true)
end

function M.setEnabled(enabled)
    Utils.set("qa_bb_enabled", enabled)
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

function M.registerTouchZones(plugin_or_widget, widget)
    local fm_self = widget or plugin_or_widget
    if not fm_self then return end

    local tabs = getTabs() or {}
    local num_tabs = #tabs
    local screen_w = Screen:getWidth()
    local screen_h = Screen:getHeight()
    local nav_h = M.TOTAL_H()
    local bar_y = screen_h - nav_h
    local side_m = M.SIDE_M()
    local usable_w = screen_w - side_m * 2

    if nav_h <= 0 then
        -- Bottom bar is hidden or disabled, skip touch zone registration
        return
    end

    -- ============================================================
    -- Clear ALL previously registered bottom-bar zones.
    -- Use the "^bb_" prefix instead of a count, so removing the
    -- rightmost tab cannot leave stale zones behind.
    -- Mirrors M.removeBottombar()'s FileManager cleanup.
    -- ============================================================
    if fm_self._zones then
        for id, _ in pairs(fm_self._zones) do
            if type(id) == "string" and id:match("^bb_") then
                fm_self._zones[id] = nil
            end
        end
    end

    if fm_self.touch_zone_dg then
        -- Collect first, then remove (don't mutate while iterating)
        local to_remove = {}
        for id, _ in pairs(fm_self._zones or {}) do
            if type(id) == "string" and id:match("^bb_") then
                to_remove[#to_remove + 1] = id
            end
        end
        for _, id in ipairs(to_remove) do
            fm_self.touch_zone_dg:removeNode(id)
        end
    end

    -- Rebuild the ordered zone list without any bb_ zones
    fm_self._ordered_touch_zones = {}
    if fm_self.touch_zone_dg then
        for _, zone_id in ipairs(fm_self.touch_zone_dg:serialize()) do
            if fm_self._zones and fm_self._zones[zone_id] then
                table.insert(fm_self._ordered_touch_zones, fm_self._zones[zone_id])
            end
        end
    end

    -- ============================================================
    -- Register fresh zones for the current tab set
    -- ============================================================
    local zones = {}

    -- Tab zones first (tap + hold for each tab)
    if num_tabs > 0 then
        local widths = M.getTabWidths(num_tabs, usable_w)
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
                overrides = { "tap_left_bottom_corner", "tap_right_bottom_corner" },
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
                overrides = {
                    "tap_left_bottom_corner",
                    "tap_right_bottom_corner",
                    "bb_hold_settings",
                    "readerhighlight_hold",
                },
                screen_zone = {
                    ratio_x = x_start / screen_w,
                    ratio_y = bar_y / screen_h,
                    ratio_w = this_tab_w / screen_w,
                    ratio_h = nav_h / screen_h,
                },
                handler = function()
                    if not Utils.getBool("qa_bb_button_hold_edit", true) then
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
    end

    -- Register hold-settings zone LAST so tab hold zones take priority
    -- when their screen_zones overlap.
    zones[#zones + 1] = {
        id = "bb_hold_settings",
        ges = "hold",
        overrides = { "readerhighlight_hold" },
        screen_zone = {
            ratio_x = 0,
            ratio_y = bar_y / screen_h,
            ratio_w = 1,
            ratio_h = nav_h / screen_h,
        },
        handler = function()
            if Utils.getBool("qa_bb_settings_on_hold", true) then
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

-- Helper: check if widget is a reader view
local function isReaderWidget(widget)
    if not widget then return false end
    local RUI = require("apps/reader/readerui")
    if not RUI or not RUI.instance then return false end
    
    -- Direct match
    if widget == RUI.instance or widget == RUI.instance.view then
        return true
    end
    
    -- Check if it's a wrapped reader
    local function checkChild(w)
        if not w then return false end
        if w == RUI.instance or w == RUI.instance.view then return true end
        if type(w) == "table" and w[1] then
            return checkChild(w[1])
        end
        return false
    end
    return checkChild(widget)
end

function M.wrapWithBottombar(inner_widget)
    if not Utils.getBool("qa_bb_enabled", true) then return inner_widget end

    -- Guard: if inner_widget is already a bottombar container, avoid double-wrapping
    if inner_widget._bottombar_container then
        return inner_widget
    end

    local screen_w = Screen:getWidth()
    local screen_h = Screen:getHeight()
    local nav_h = M.TOTAL_H()

    if nav_h <= 0 then return inner_widget end

    local is_reader = isReaderWidget(inner_widget)
    local overlap = is_reader and Utils.getBool("qa_bb_overlap", false) or false

    local content_h = screen_h - nav_h
    if content_h <= 0 then return inner_widget end

    -- Check if this is a BookList (History/Collections) or Menu (coll_list)
    local is_booklist = inner_widget.is_borderless and inner_widget.name and
                        (inner_widget.name == "history" or inner_widget.name == "collections" or inner_widget.name == "coll_list")

    -- Injection scenario: the injected inner container should also be treated as a BookList
    local is_injected = inner_widget._bottombar_injected_container == true
    if is_injected then
        is_booklist = true
    end

    -- ReaderView: its dimen is already shrunk in ReaderUI.new before creation,
    -- so do NOT resize it here (would subtract nav_h twice).
    local is_readerview = inner_widget.recalculate ~= nil and inner_widget.document ~= nil

    if not overlap then
        if is_booklist then
            -- Injection case: inner IS the container itself, adjust it directly.
            -- Non-injection case: adjust inner_widget[1].
            local container = is_injected and inner_widget or inner_widget[1]
            if container and container.dimen then
                container.dimen.h = content_h
                container.dimen.y = 0
            end
            local mgr_owner = inner_widget
            if mgr_owner._manager and mgr_owner._manager.updateItemTable then
                mgr_owner._manager:updateItemTable()
            end
            if mgr_owner.updateItems then
                mgr_owner:updateItems()
            end
        elseif not is_readerview then
            -- FM/FileChooser: original logic
            if inner_widget.dimen then
                inner_widget.dimen.h = content_h
                inner_widget.dimen.w = screen_w
                inner_widget.dimen.y = 0
            end
            if inner_widget.height ~= nil then
                inner_widget.height = content_h
            end
            if inner_widget.y ~= nil then
                inner_widget.y = 0
            end

            local fc = inner_widget.file_chooser or inner_widget
            if fc then
                if fc.height ~= nil then
                    fc.height = content_h
                end
                if fc.y ~= nil then
                    fc.y = 0
                end
                if fc.dimen then
                    fc.dimen.h = content_h
                    fc.dimen.y = 0
                end
                if fc._recalculateDimen then
                    fc:_recalculateDimen()
                end
                if fc.updateItems then
                    fc:updateItems()
                end
            end
        end
        -- If is_readerview: no dimen change here, already handled in ReaderUI.new
    end

    -- Build bottom bar (shared by all)
    local tabs = getTabs() or {}
    local active_action = (tabs and #tabs > 0) and tabs[1] or nil
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

    local is_bare = Utils.getString("qa_bb_style") == "bare"
    local use_transparent = Utils.getBool("qa_bb_transparent", false) or overlap
    local bg = (use_transparent or is_bare) and nil or Blitbuffer.COLOR_WHITE

    local fc = FrameContainer:new{
        bordersize = 0,
        padding = 0,
        margin = 0,
        background = bg,
        og,
    }
    fc._bottombar_inner = inner_widget      -- ★ 新增
    fc._bottombar_container = og            -- ★ 新增
    return fc
end

-- ============================================================
-- Inject into a SimpleUI ScreenWidget
--
-- SimpleUI's Homescreen (engines/sui_screen_engine.lua) wraps its content
-- in an OverlapGroup stored at w._navbar_container, with its own bar at
-- w._navbar_bar_idx. When SimpleUI's bar is disabled, that slot is empty
-- and SimpleUI has already reserved the height via
-- _G.__QUICKUI_BAR_HEIGHT, so all we do here is append our bar to the
-- OverlapGroup and register our touch zones.
--
-- Safe to call on any widget: bails out silently when the widget is not a
-- SimpleUI screen (no _navbar_container / no _navbar_content_h), when the
-- bar is disabled, or when it has already been injected.
-- ============================================================
function M.injectIntoScreenWidget(w)
    if not Utils.getBool("qa_bb_enabled", true) then return end
    if not w or not w._navbar_container then return end
    -- _navbar_content_h is always set by sui_core.applyNavbarState() on a
    -- genuine SimpleUI screen — use it as the identification marker instead
    -- of name, which is shared with QuickUI's own homescreen widget.
    if not w._navbar_content_h then return end
    if w._quickui_bb_injected then return end

    local nav_h = M.TOTAL_H()
    if nav_h <= 0 then return end

    -- Reuse SimpleUI's own content height so our bar sits exactly in the
    -- reserved band; never recompute from Screen:getHeight() here.
    local bar = M.buildBar(nil)
    bar.overlap_offset = { 0, Screen:getHeight() - nav_h }

    local container = w._navbar_container
    container[#container + 1] = bar

    w._quickui_bb_bar      = bar
    w._quickui_bb_injected = true

    M.registerTouchZones(w)
end

-- Removes a previously injected bar (used when the bar is disabled at
-- runtime, before SimpleUI rebuilds its own container).
function M.removeFromScreenWidget(w)
    if not w or not w._quickui_bb_injected then return end
    local container = w._navbar_container
    local bar = w._quickui_bb_bar
    if container and bar then
        for i = #container, 1, -1 do
            if container[i] == bar then
                table.remove(container, i)
                break
            end
        end
    end
    w._quickui_bb_bar      = nil
    w._quickui_bb_injected = nil
end

-- ============================================================
-- Rebuild Bottombar
-- ============================================================

function M.rebuildBottombar(skip_remove)
    -- ============================================================
    -- Fully disabled: tear down everything and restore full height
    -- ============================================================
    if not M.isEnabled() then
        M.removeBottombar()

        local RUI = require("apps/reader/readerui")
        local reader = RUI.instance
        if reader and reader.dimen and reader.dimen.h ~= Screen:getHeight() then
            local full_dimen = Geom:new{
                x = 0, y = 0,
                w = Screen:getWidth(),
                h = Screen:getHeight(),
            }
            reader.dimen = full_dimen
            if reader.view and reader.view.onSetDimensions then
                reader.view:onSetDimensions(full_dimen)
            end
            if reader.onScreenResize then
                reader:onScreenResize(full_dimen)
            end
            UIManager:setDirty(reader, "full")
        end
        return
    end

    -- ============================================================
    -- Tear down existing wrappers (do NOT touch reader height)
    -- ============================================================
    if skip_remove then
        -- On rotation: only clear _bottombar_original_inner, do not execute remove
        local FM = require("apps/filemanager/filemanager")
        local fm = FM.instance
        if fm then
            fm._bottombar_original_inner = nil
        end
        local RUI = require("apps/reader/readerui")
        local reader = RUI.instance
        if reader then
            reader._bottombar_original_inner = nil
        end
    else
        M.removeBottombar()
    end

    -- ============================================================
    -- Refresh FileManager (injection handled by setupLayout wrapper)
    -- ============================================================
    local FM = require("apps/filemanager/filemanager")
    local fm = FM.instance
    if fm and fm.setupLayout then
        -- 清除注入标记，让 setupLayout 里的 wrapper 重跑注入逻辑
        fm._bottombar_injected = nil
        fm:setupLayout()
    end
    
    -- ============================================================
    -- Wrap Reader
    -- ============================================================
    local RUI = require("apps/reader/readerui")
    local reader = RUI.instance
    if reader then
        local config = _G.__QUICKUI_CONFIG
        local show_in_reader = config and config.qa_bb_reader_enabled
        local hide_in_pdf = config and config.qa_bb_hide_in_pdf
        local is_pdf = false
        if reader.document then
            local file = reader.document.file or ""
            is_pdf = file:match("%.pdf$") ~= nil
        end

        local should_show = show_in_reader ~= false and not (hide_in_pdf and is_pdf)

        if should_show then
            local inner_reader = reader[1]
            while inner_reader and inner_reader._bottombar_inner do
                inner_reader = inner_reader._bottombar_inner
            end
            reader._bottombar_original_inner = inner_reader

            local new_wrapped_reader = M.wrapWithBottombar(inner_reader)
            reader[1] = new_wrapped_reader
            reader._bottombar_container = new_wrapped_reader

            M.registerTouchZones(reader)
        end

        -- Unified: always reflow to the target height
        local target_h
        if should_show and not Utils.getBool("qa_bb_overlap", false) then
            target_h = Screen:getHeight() - M.TOTAL_H()
        else
            target_h = Screen:getHeight()
        end

        -- Keep ReaderUI (reader) fullscreen so bottom-bar touch zones
        -- near the screen bottom are still dispatched to it.
        reader.dimen = Geom:new{
            x = 0, y = 0,
            w = Screen:getWidth(),
            h = Screen:getHeight(),
        }

        -- Only shrink ReaderView so content avoids the bar.
        local view_dimen = Geom:new{
            x = 0, y = 0,
            w = Screen:getWidth(),
            h = target_h,
        }
        if reader.view and reader.view.onSetDimensions then
            reader.view:onSetDimensions(view_dimen)
        end
        -- Do NOT call reader:onScreenResize (it would shrink reader.dimen too).

        UIManager:setDirty(reader, "full")
    end

    -- ============================================================
    -- Wrap History/Collections/coll_list already on screen
    -- ============================================================
    local stack = UIManager._window_stack or {}
    local INJECT_NAMES = {
        history = true,
        collections = true,
        coll_list = true,
    }
    for _, entry in ipairs(stack) do
        local w = entry.widget
        if w and w.covers_fullscreen and w.name and INJECT_NAMES[w.name] then
            if not w._bottombar_injected then
                local inner = w[1]
                if inner and not inner._bottombar_inner then
                    inner._bottombar_injected_container = true

                    local wrapped = M.wrapWithBottombar(inner)
                    if wrapped and wrapped ~= inner then
                        w[1] = wrapped
                        w._bottombar_injected = true
                        w._bottombar_inner = inner
                        M.registerTouchZones(w)
                        UIManager:setDirty(w, "full")
                    else
                        inner._bottombar_injected_container = nil
                    end
                end
            end
        end
    end
end

-- ============================================================
-- Remove Bottombar
-- ============================================================

--- Remove bottom bar from FileManager, Reader, and all injected fullscreen widgets
-- Tear down the bottom bar widget tree and clear all touch zones.
-- Does NOT touch reader height (caller handles that).
function M.removeBottombar()
    -- ============================================================
    -- FileManager
    -- ============================================================
    local FM = require("apps/filemanager/filemanager")
    local fm = FM and FM.instance
    if fm and fm._bottombar_original_inner then
        if fm._zones then
            for id, _ in pairs(fm._zones) do
                if type(id) == "string" and id:match("^bb_") then
                    fm._zones[id] = nil
                end
            end
        end

        if fm.touch_zone_dg then
            for id, _ in pairs(fm._zones or {}) do
                if type(id) == "string" and id:match("^bb_") then
                    fm.touch_zone_dg:removeNode(id)
                end
            end
        end

        fm._ordered_touch_zones = {}
        if fm.touch_zone_dg then
            for _, zone_id in ipairs(fm.touch_zone_dg:serialize()) do
                if fm._zones and fm._zones[zone_id] then
                    table.insert(fm._ordered_touch_zones, fm._zones[zone_id])
                end
            end
        end

        fm[1] = fm._bottombar_original_inner
        fm._bottombar_container = nil
        fm._bottombar_original_inner = nil
        UIManager:setDirty(fm, "ui")
    end

    -- ============================================================
    -- Reader (widget tree only, height is caller's responsibility)
    -- ============================================================
    local RUI = require("apps/reader/readerui")
    local reader = RUI and RUI.instance
    if reader and reader._bottombar_original_inner then
        if reader._zones then
            for id, _ in pairs(reader._zones) do
                if type(id) == "string" and id:match("^bb_") then
                    reader._zones[id] = nil
                end
            end
        end

        if reader.touch_zone_dg then
            for id, _ in pairs(reader._zones or {}) do
                if type(id) == "string" and id:match("^bb_") then
                    reader.touch_zone_dg:removeNode(id)
                end
            end
        end

        reader._ordered_touch_zones = {}
        if reader.touch_zone_dg then
            for _, zone_id in ipairs(reader.touch_zone_dg:serialize()) do
                if reader._zones and reader._zones[zone_id] then
                    table.insert(reader._ordered_touch_zones, reader._zones[zone_id])
                end
            end
        end

        reader[1] = reader._bottombar_original_inner
        reader._bottombar_container = nil
        reader._bottombar_original_inner = nil
        reader._bottombar_overlap_last = nil
        UIManager:setDirty(reader, "ui")
    end

    -- ============================================================
    -- History / Collections / coll_list / homescreen
    -- ============================================================
    local stack = UIManager._window_stack or {}
    local INJECT_NAMES = { history = true, collections = true, coll_list = true, homescreen = true }
    for _, entry in ipairs(stack) do
        local w = entry.widget
        if w and w.name and INJECT_NAMES[w.name] and w._bottombar_injected then
            local inner = w._bottombar_inner
            if inner and w[1] then
                w[1] = inner
            end
            w._bottombar_injected = nil
            w._bottombar_inner = nil
            w._bottombar_container = nil
            w._bottombar_wrapped = nil
            w._bottombar_tabs = nil
            w._navbar_container = nil
            if inner then inner._bottombar_injected_container = nil end
        end
    end
end

-- ============================================================
-- Refresh
-- ============================================================

function M.refresh()
    -- Keep SimpleUI's reserved height in sync — it reads this live on every
    -- getContentHeight() call, so the value must reflect the current size.
    _G.__QUICKUI_BAR_HEIGHT = M.isEnabled() and M.TOTAL_H() or 0

    M.rebuildBottombar()

    -- Re-inject into any live SimpleUI screen. rebuildBottombar() only
    -- handles FM/ReaderUI/BookList; SimpleUI screens need their own pass.
    local ok, ScreenEngine = pcall(require, "engines/sui_screen_engine")
    if not (ok and ScreenEngine and ScreenEngine.liveScreenIds) then return end
    for _i, id in ipairs(ScreenEngine.liveScreenIds()) do
        local inst = ScreenEngine.getInstance(id)
        if inst then
            M.removeFromScreenWidget(inst)   -- drop the stale bar first
            M.injectIntoScreenWidget(inst)
        end
    end
end

-- ============================================================
-- Show Add Tab Menu
-- ============================================================

function M.showAddTabMenu(on_back, filtered_actions)
    local current_tabs = Utils.get("qa_bb_tabs", nil)
    if type(current_tabs) ~= "table" then
        current_tabs = {}
    end

    -- Build tab_set for checking which actions are already added
    local tab_set = {}
    for __, id in ipairs(current_tabs) do
        tab_set[id] = true
    end

    local available = filtered_actions or getAvailableActions()

    -- Set of actions that are currently unavailable (plugin not loaded)
    local unavailable_set = QA.getUnavailableActions()

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
                if on_back then
                    on_back()
                elseif settings and settings.showBottombarSettings then
                    settings.showBottombarSettings()
                end
            end
        }
    })
    table.insert(buttons, {})

    -- Select All / Deselect All
    table.insert(buttons, {
        {
            text_func = function()
                if #current_tabs > 0 then
                    return "☑ " .. _("Deselect All")
                else
                    return "☐ " .. _("Select All")
                end
            end,
            callback = function()
                local new_tabs = {}

                if #current_tabs > 0 then
                    -- Deselect: keep unavailable ones
                    for __, id in ipairs(current_tabs) do
                        if unavailable_set[id] then
                            new_tabs[#new_tabs + 1] = id
                        end
                    end
                else
                    -- Select: only add available ones
                    for __, action in ipairs(available) do
                        if not unavailable_set[action.id] then
                            if #new_tabs >= MAX_TABS then
                                UIManager:show(Notification:new{
                                    text = string.format(_("Max %d tabs, only first %d added"), MAX_TABS, MAX_TABS),
                                    timeout = 2,
                                })
                                break
                            end
                            new_tabs[#new_tabs + 1] = action.id
                        end
                    end
                end

                Utils.set("qa_bb_tabs", new_tabs)
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

    -- Apply preset: use saved preset if available, otherwise fall back to defaults
    table.insert(buttons, {
        {
            text = _("Apply preset (QA bb)"),
            callback = function()
                Utils.applyDefault({"qa_common", "qa_bb"})
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
        local is_available = not unavailable_set[action.id]
        local symbol = QA.getActionSymbol(action.id)
        local view_tag = " [" .. (action.view or "common") .. "]"

        local display_text
        if is_available then
            display_text = (is_checked and "✓ " or "  ") .. symbol .. action.label .. view_tag
        else
            display_text = "  " .. symbol .. action.label .. view_tag .. "  ✗"
        end

        table.insert(buttons, {
            {
                text = display_text,
                enabled = is_available,
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

                    Utils.set("qa_bb_tabs", new_tabs)
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
    return getTabs() or {}
end

-- ============================================================
-- Initialization
-- ============================================================

function M.init()
    Utils.patchFileChooserForBottombar()
    Utils.patchReaderUIForBottombar()
    Utils.patchBookListForBottombar()
    Utils.patchSimpleUIHomescreenForBottombar()
    Utils.registerRefreshHandler("qa_bb", M.refresh)
    
    -- Expose QuickUI bottom bar height globally for SimpleUI compatibility
    if Utils.getBool("qa_bb_enabled", true) then
        _G.__QUICKUI_BAR_HEIGHT = M.TOTAL_H()
    else
        _G.__QUICKUI_BAR_HEIGHT = 0
    end
    
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
                M.rebuildBottombar(true)
            end
            return result
        end
    end
    UIManager:scheduleIn(0.5, hookDeviceListener)

    -- Android: hook Device.input.handleMiscEv to catch APP_CMD_CONFIG_CHANGED
    local function hookAndroidRotation()
        local Device = require("device")
        if not Device.isAndroid or not Device.input then return end
        if Device.input._quickui_hooked then return end
        Device.input._quickui_hooked = true

        local C = require("ffi").C
        local orig_handleMiscEv = Device.input.handleMiscEv
        Device.input.handleMiscEv = function(this, ev)
            local result
            if orig_handleMiscEv then
                result = orig_handleMiscEv(this, ev)
            end
            if ev.code == C.APP_CMD_CONFIG_CHANGED then
                if _G.__QUICKUI_CONFIG and _G.__QUICKUI_CONFIG.qa_bb_enabled then
                    M.rebuildBottombar(true)
                end
            end
            return result
        end
    end
    UIManager:scheduleIn(0.5, hookAndroidRotation)
    
    UIManager:scheduleIn(0.1, function()
       M.rebuildBottombar()
    end)
end

return M
