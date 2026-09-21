--[[
QuickUI - Reader Sliders

Single source of truth for reader typography sliders.

Exports:
  M.getSliders(reader)  -> list of slider descriptors
  M.buildSliderRow(opts, row_width, label_size, show_parent, on_change, no_touch)
                        -> HorizontalGroup row (shared by panel & popup)
  M.show()              -> standalone popup with ALL sliders

no_touch:
  nil / false -> register tap / pan / pan_release / hold on the slider
                 (used by the standalone popup)
  true        -> register only the hold handler
                 (used by qa_panel.lua, whose TouchMenu already handles
                  tap / pan for slider dragging)
]]

local Blitbuffer      = require("ffi/blitbuffer")
local Button          = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device          = require("device")
local Event           = require("ui/event")
local Font            = require("ui/font")
local FrameContainer  = require("ui/widget/container/framecontainer")
local Geom            = require("ui/geometry")
local GestureRange    = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local InfoMessage     = require("ui/widget/infomessage")
local InputContainer  = require("ui/widget/container/inputcontainer")
local Notification    = require("ui/widget/notification")
local Screen          = require("device").screen
local SpinWidget      = require("ui/widget/spinwidget")
local TextWidget      = require("ui/widget/textwidget")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("gettext")

local M = {}

-- ============================================================
-- SlimSlider
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
    self.dimen = Geom:new{
        x = -10000, y = -10000,
        w = self.width, h = self.height,
    }
end

function SlimSlider:getSize()
    return Geom:new{
        x = -10000, y = -10000,
        w = self.width, h = self.height,
    }
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
-- Slider definitions
-- ============================================================

function M.getSliders(reader)
    if not reader or not reader.document then return {} end

    local provider = reader.document.provider
    local is_cre = provider == "crengine"
    local is_pdf = provider == "mupdf" or provider == "kopt"
    local configurable = reader.document.configurable
    local G_defaults = rawget(_G, "G_defaults")

    local function readDefault(global_key, factory_key, fallback)
        if G_reader_settings and global_key then
            local v = G_reader_settings:readSetting(global_key)
            if v ~= nil then return v end
        end
        if G_defaults and factory_key then
            local v = G_defaults:readSetting(factory_key)
            if v ~= nil then return v end
        end
        return fallback
    end

    local out = {}

    if is_cre then
        out[#out + 1] = {
            key = "font_size",
            label = _("Font Size"),
            min = 12, max = 90, step = 1,
            default = function()
                return readDefault("copt_font_size", "DCREREADER_CONFIG_DEFAULT_FONT_SIZE", 22)
            end,
            global_key = "copt_font_size",
            get = function() return reader.font.configurable.font_size end,
            set = function(v)
                v = math.max(12, math.min(90, math.floor(v + 0.5)))
                reader.font:onSetFontSize(v)
                return reader.font.configurable.font_size
            end,
            enabled_key = "qa_panel_reader_font_size",
        }
        out[#out + 1] = {
            key = "line_spacing",
            label = _("Line Spacing"),
            min = 50, max = 200, step = 1,
            default = function()
                return readDefault("copt_line_spacing", "DCREREADER_CONFIG_LINE_SPACE_PERCENT_MEDIUM", 100)
            end,
            global_key = "copt_line_spacing",
            get = function() return reader.font.configurable.line_spacing end,
            set = function(v)
                v = math.max(50, math.min(200, math.floor(v + 0.5)))
                reader.font:onSetLineSpace(v)
                return reader.font.configurable.line_spacing
            end,
            enabled_key = "qa_panel_reader_line_spacing",
        }
        out[#out + 1] = {
            key = "gamma",
            label = _("Contrast"),
            min = 10, max = 56, step = 1,
            default = function()
                return readDefault("copt_font_gamma", nil, 15)
            end,
            global_key = "copt_font_gamma",
            get = function() return reader.font.configurable.font_gamma end,
            set = function(v)
                v = math.max(10, math.min(56, math.floor(v + 0.5)))
                reader:handleEvent(Event:new("SetFontGamma", v))
                return reader.font.configurable.font_gamma
            end,
            enabled_key = "qa_panel_reader_gamma",
        }
        out[#out + 1] = {
            key = "h_margin",
            label = _("L/R Margins"),
            min = 0, max = 140, step = 1,
            default = function()
                local v = readDefault("copt_h_page_margins", "DCREREADER_CONFIG_H_MARGIN_SIZES_MEDIUM", 10)
                if type(v) == "table" then return v[1] or 10 end
                return v
            end,
            global_key = "copt_h_page_margins",
            global_is_pair = true,
            get = function()
                local m = reader.font.configurable.h_page_margins
                return type(m) == "table" and m[1] or 10
            end,
            set = function(v)
                v = math.max(0, math.min(140, math.floor(v + 0.5)))
                reader.typeset:onSetPageHorizMargins({ v, v })
                return v
            end,
            enabled_key = "qa_panel_reader_margins_h",
        }
        out[#out + 1] = {
            key = "t_margin",
            label = _("Top Margin"),
            min = 0, max = 140, step = 1,
            default = function()
                return readDefault("copt_t_page_margin", "DCREREADER_CONFIG_T_MARGIN_SIZES_LARGE", 10)
            end,
            global_key = "copt_t_page_margin",
            get = function() return reader.font.configurable.t_page_margin end,
            set = function(v)
                v = math.max(0, math.min(140, math.floor(v + 0.5)))
                reader.typeset:onSetPageTopMargin(v)
                return v
            end,
            enabled_key = "qa_panel_reader_margin_top",
        }
        out[#out + 1] = {
            key = "b_margin",
            label = _("Bottom Margin"),
            min = 0, max = 140, step = 1,
            default = function()
                return readDefault("copt_b_page_margin", "DCREREADER_CONFIG_B_MARGIN_SIZES_LARGE", 10)
            end,
            global_key = "copt_b_page_margin",
            get = function() return reader.font.configurable.b_page_margin end,
            set = function(v)
                v = math.max(0, math.min(140, math.floor(v + 0.5)))
                reader.typeset:onSetPageBottomMargin(v)
                return v
            end,
            enabled_key = "qa_panel_reader_margin_bot",
        }
    end

    if is_pdf then
        out[#out + 1] = {
            key = "pdf_contrast",
            label = _("Contrast"),
            min = 0.8, max = 50, step = 0.1, precision = "%.1f",
            default = function()
                return readDefault("kopt_contrast", "DKOPTREADER_CONFIG_CONTRAST", 1.0)
            end,
            global_key = "kopt_contrast",
            get = function() return configurable.contrast end,
            set = function(v)
                v = math.max(0.8, math.min(50, v))
                configurable.contrast = v
                reader:handleEvent(Event:new("GammaUpdate", v, true))
                UIManager:setDirty(reader, "full")
                return v
            end,
            enabled_key = "qa_panel_reader_gamma",
        }
        out[#out + 1] = {
            key = "pdf_zoom_overlap_h",
            label = _("Horizontal overlap"),
            min = 0, max = 84, step = 1,
            default = function()
                return readDefault("kopt_zoom_overlap_h", nil, 36)
            end,
            global_key = "kopt_zoom_overlap_h",
            get = function() return configurable.zoom_overlap_h end,
            set = function(v)
                v = math.max(0, math.min(84, math.floor(v + 0.5)))
                reader:handleEvent(Event:new("SetZoomPan", { zoom_overlap_h = v }))
                return configurable.zoom_overlap_h
            end,
            enabled_key = "qa_panel_reader_zoom",
            should_show = function()
                local g = configurable.zoom_mode_genus
                return g ~= nil and g < 3
            end,
        }
        out[#out + 1] = {
            key = "pdf_zoom_overlap_v",
            label = _("Vertical overlap"),
            min = 0, max = 84, step = 1,
            default = function()
                return readDefault("kopt_zoom_overlap_v", nil, 36)
            end,
            global_key = "kopt_zoom_overlap_v",
            get = function() return configurable.zoom_overlap_v end,
            set = function(v)
                v = math.max(0, math.min(84, math.floor(v + 0.5)))
                reader:handleEvent(Event:new("SetZoomPan", { zoom_overlap_v = v }))
                return configurable.zoom_overlap_v
            end,
            enabled_key = "qa_panel_reader_zoom",
            should_show = function()
                local g = configurable.zoom_mode_genus
                return g ~= nil and g < 3
            end,
        }
        out[#out + 1] = {
            key = "pdf_zoom_range_number",
            label = _("Rows") .. "/" .. _("Columns"),
            min = 0.1, max = 8, step = 0.1, precision = "%.1f",
            default = function()
                return readDefault("kopt_zoom_range_number", nil, 2)
            end,
            global_key = "kopt_zoom_range_number",
            get = function() return configurable.zoom_range_number end,
            set = function(v)
                v = math.max(0.1, math.min(8, v))
                configurable.zoom_range_number = v
                reader:handleEvent(Event:new("DefineZoom"))
                return configurable.zoom_range_number
            end,
            enabled_key = "qa_panel_reader_zoom",
            should_show = function()
                local g = configurable.zoom_mode_genus
                return g ~= nil and (g == 1 or g == 2)
            end,
        }
        out[#out + 1] = {
            key = "pdf_zoom_factor",
            label = _("Zoom factor"),
            min = 0.1, max = 20, step = 0.1, precision = "%.1f",
            default = function()
                return readDefault("kopt_zoom_factor", nil, 1.5)
            end,
            global_key = "kopt_zoom_factor",
            get = function() return configurable.zoom_factor end,
            set = function(v)
                v = math.max(0.1, math.min(20, v))
                reader:handleEvent(Event:new("SetZoomPan", { kopt_zoom_factor = v }))
                return configurable.zoom_factor
            end,
            enabled_key = "qa_panel_reader_zoom",
            should_show = function()
                local g = configurable.zoom_mode_genus
                return g ~= nil and g == 0
            end,
        }
    end

    return out
end

-- ============================================================
-- Slider row builder -- shared by panel & popup
-- ============================================================
-- Tap label     -> reset to minimum
-- Hold label    -> reset to default
-- Tap value btn -> SpinWidget
-- Hold value btn-> reset to default
-- Tap slider    -> jump to value
-- Pan slider    -> drag to change
-- Hold slider   -> open Sliders settings menu
-- Tap +/-       -> step

function M.buildSliderRow(opts, row_width, label_size, show_parent, on_change, no_touch)
    local gap         = Screen:scaleBySize(4)
    local small_btn_w = Screen:scaleBySize(40)
    local label_w     = Screen:scaleBySize(70)
    local value_w     = Screen:scaleBySize(50)

    local _d = Button:new{
        text = "\u{2212}", width = small_btn_w,
        show_parent = show_parent,
        callback = function() end,
    }
    local btn_h = math.max(30, _d:getSize().h)

    -- forward declarations so touch handlers & spin callbacks can use them
    local apply, refresh

    -- -- Label button: tap -> min, hold -> default
    local label_widget = Button:new{
        text = opts.label,
        width = label_w,
        height = btn_h,
        padding = 0,
        bordersize = 0,
        text_font_size = label_size,
        text_font_bold = false,
        show_parent = show_parent,
        callback = function()
            if apply then apply(opts.min) end
        end,
        hold_callback = function()
            local dv = opts.default and opts.default() or opts.min
            if type(dv) == "table" then dv = dv[1] end
            if dv ~= nil and apply then
                apply(dv)
                UIManager:show(Notification:new{
                    text = string.format(_("Reset to %s"), tostring(dv)),
                    timeout = 2,
                })
            end
        end,
    }

    local slider_w = row_width - label_w - 2 * small_btn_w - 3 * gap - value_w

    local slider = SlimSlider:new{
        width = slider_w,
        height = btn_h,
        minimum = opts.min,
        maximum = opts.max,
        value = opts.get() or opts.min,
        show_parent = show_parent,
        enabled = true,
    }

    local slider_wrapper = InputContainer:new{
        dimen = Geom:new{ w = slider_w, h = btn_h },
    }
    slider_wrapper[1] = slider

    -- -- Slider touch zones
    local function _is_inside(ges)
        local rel_x = ges.pos.x - (slider_wrapper.dimen and slider_wrapper.dimen.x or 0)
        local rel_y = ges.pos.y - (slider_wrapper.dimen and slider_wrapper.dimen.y or 0)
        return rel_x >= 0 and rel_x <= slider_w and rel_y >= 0 and rel_y <= btn_h
    end

    local function _set_from_pos(ges)
        local new_val = slider:getValueFromPosition(ges.pos)
        if new_val and apply then apply(new_val) end
    end

    local zones = {}
    if not no_touch then
        -- popup mode: register tap / pan / pan_release
        zones[#zones + 1] = {
            id = "sld_tap_" .. opts.key,
            ges = "tap",
            screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
            handler = function(ges)
                if _is_inside(ges) then _set_from_pos(ges); return true end
                return false
            end,
        }
        zones[#zones + 1] = {
            id = "sld_pan_" .. opts.key,
            ges = "pan",
            screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
            handler = function(ges)
                if _is_inside(ges) then _set_from_pos(ges); return true end
                return false
            end,
        }
        zones[#zones + 1] = {
            id = "sld_pan_release_" .. opts.key,
            ges = "pan_release",
            screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
            handler = function(ges)
                if _is_inside(ges) then _set_from_pos(ges); return true end
                return false
            end,
        }
    end
    -- hold is always registered (both panel & popup)
    zones[#zones + 1] = {
        id = "sld_hold_" .. opts.key,
        ges = "hold",
        screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
        handler = function(ges)
            if _is_inside(ges) then
                if show_parent and type(show_parent.handleEvent) == "function" then
                    UIManager:close(show_parent)
                end
                local settings = require("qui_actions/qa_settings")
                if settings and settings.showSlidersMenu then
                    settings.showSlidersMenu(nil, nil)
                end
                return true
            end
            return false
        end,
    }
    slider_wrapper:registerTouchZones(zones)

    local _init_val = opts.get()
    if _init_val == nil then _init_val = opts.min end

    local initial_text
    if opts.precision then
        initial_text = string.format(opts.precision, _init_val)
    else
        initial_text = tostring(_init_val)
    end

    -- -- Value button: tap -> SpinWidget, hold -> default
    local value_btn = Button:new{
        text = initial_text,
        width = value_w,
        height = btn_h,
        padding = 0,
        bordersize = 0,
        text_font_size = label_size,
        text_font_bold = false,
        show_parent = show_parent,
        callback = function()
            local dv = opts.default and opts.default() or opts.min
            if type(dv) == "table" then dv = dv[1] end
            local spin = SpinWidget:new{
                title_text = opts.label,
                value = opts.get() or opts.min,
                value_min = opts.min,
                value_max = opts.max,
                value_step = opts.step or 1,
                value_hold_step = opts.hold_step or 5,
                precision = opts.precision,
                default_value = dv,
                callback = function(spin_w)
                    if apply then apply(spin_w.value) end
                end,
                extra_text = _("Set as default"),
                extra_callback = function(spin_w)
                    if G_reader_settings and opts.global_key then
                        local v = spin_w.value
                        if opts.global_is_pair then
                            G_reader_settings:saveSetting(opts.global_key, {v, v})
                        else
                            G_reader_settings:saveSetting(opts.global_key, v)
                        end
                        UIManager:show(Notification:new{
                            text = _("Set as default"),
                            timeout = 2,
                        })
                    end
                end,
            }
            UIManager:show(spin)
        end,
        hold_callback = function()
            local dv = opts.default and opts.default() or opts.min
            if type(dv) == "table" then dv = dv[1] end
            if dv ~= nil and apply then
                apply(dv)
                UIManager:show(Notification:new{
                    text = string.format(_("Reset to %s"), tostring(dv)),
                    timeout = 2,
                })
            end
        end,
    }

    refresh = function(v)
        if v == nil then v = opts.min end
        slider:setValue(v)
        if opts.precision then
            value_btn:setText(string.format(opts.precision, v), value_w)
        else
            value_btn:setText(tostring(v), value_w)
        end
        UIManager:setDirty(show_parent, "ui")
    end

    apply = function(v)
        if v == nil then return end
        local real = opts.set(v)
        refresh(real or v)
        if on_change then on_change(real or v) end
    end

    local minus = Button:new{
        text = "\u{2212}", width = small_btn_w,
        show_parent = show_parent,
        callback = function() apply(slider.value - (opts.step or 1)) end,
        bordersize = 0, background = nil, framebg = nil,
    }
    local plus = Button:new{
        text = "\u{FF0B}", width = small_btn_w,
        show_parent = show_parent,
        callback = function() apply(slider.value + (opts.step or 1)) end,
        bordersize = 0, background = nil, framebg = nil,
    }

    local row = HorizontalGroup:new{
        align = "center",
        label_widget,
        HorizontalSpan:new{ width = gap },
        minus,
        HorizontalSpan:new{ width = gap },
        slider_wrapper,
        HorizontalSpan:new{ width = gap },
        plus,
        HorizontalSpan:new{ width = gap },
        value_btn,
    }

    return row, slider, apply
end

-- ============================================================
-- Standalone popup with ALL sliders
-- ============================================================

local _dialog = nil

function M.show()
    local RUI = require("apps/reader/readerui")
    local reader = RUI and RUI.instance
    if not reader or not reader.document then
        UIManager:show(InfoMessage:new{
            text = _("Please open a book first"),
            timeout = 2,
        })
        return
    end

    local sliders = M.getSliders(reader)
    if #sliders == 0 then
        UIManager:show(InfoMessage:new{
            text = _("No reader sliders available for this document"),
            timeout = 3,
        })
        return
    end

    if _dialog then
        UIManager:close(_dialog)
        _dialog = nil
    end

    local label_size = Screen:scaleBySize(12)
    local panel_w    = math.floor(Screen:getWidth() * 0.85)
    local padding    = Screen:scaleBySize(14)
    local inner_w    = panel_w - padding * 2

    local vg = VerticalGroup:new{ align = "left" }

    -- temporary placeholder for show_parent; the sliders only need it for
    -- UIManager:setDirty() and Button show_parent; passing a table is fine.
    local temp_parent = {}

    for __, opts in ipairs(sliders) do
        -- no_touch = nil: popup registers its own tap/pan handlers
        local row = M.buildSliderRow(opts, inner_w, label_size, temp_parent, nil)
        vg[#vg + 1] = row
        vg[#vg + 1] = VerticalSpan:new{ width = Screen:scaleBySize(8) }
    end

    local frame = FrameContainer:new{
        width = panel_w,
        padding = padding,
        margin = 0,
        bordersize = Screen:scaleBySize(1),
        color = Blitbuffer.COLOR_BLACK,
        background = Blitbuffer.COLOR_WHITE,
        vg,
    }

    local PickerDlg = InputContainer:extend{ is_always_active = true }
    function PickerDlg:init()
        self.dimen = Geom:new{
            x = 0, y = 0,
            w = Screen:getWidth(), h = Screen:getHeight(),
        }
        self[1] = CenterContainer:new{
            dimen = Geom:new{
                w = Screen:getWidth(),
                h = Screen:getHeight(),
            },
            frame,
        }
        if Device:isTouchDevice() then
            self.ges_events.Tap = {
                GestureRange:new{
                    ges = "tap",
                    range = Geom:new{
                        w = Screen:getWidth(),
                        h = Screen:getHeight(),
                    },
                },
            }
        end
    end
    function PickerDlg:onTap(arg, ges)
        if ges.pos:notIntersectWith(frame.dimen) then
            UIManager:close(self)
            _dialog = nil
        end
        return true
    end

    _dialog = PickerDlg:new{}
    UIManager:show(_dialog, "ui")
end

return M
