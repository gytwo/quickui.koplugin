--[[
QuickUI - Reader Sliders

Single source of truth for reader typography sliders.
]]

local Blitbuffer      = require("ffi/blitbuffer")
local Button          = require("ui/widget/button")
local ButtonDialog    = require("ui/widget/buttondialog")
local CenterContainer = require("ui/widget/container/centercontainer")
local MovableContainer = require("ui/widget/container/movablecontainer")
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
local Utils = require("qui_utils")

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
            enabled_key = "qa_panel_reader_font_size",
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
        }
        out[#out + 1] = {
            key = "line_spacing",
            label = _("Line Spacing"),
            enabled_key = "qa_panel_reader_line_spacing",
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
        }
        out[#out + 1] = {
            key = "gamma",
            label = _("Contrast"),
            enabled_key = "qa_panel_reader_gamma",
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
        }
        out[#out + 1] = {
            key = "h_margin",
            label = _("L/R Margins"),
            enabled_key = "qa_panel_reader_margins_h",
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
        }
        out[#out + 1] = {
            key = "t_margin",
            label = _("Top Margin"),
            enabled_key = "qa_panel_reader_margin_top",
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
        }
        out[#out + 1] = {
            key = "b_margin",
            label = _("Bottom Margin"),
            enabled_key = "qa_panel_reader_margin_bot",
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
        }

        -- ── Style Tweaks (crengine only) ─────────────────────────────
        -- The three tweak rows are only exposed when the master switch
        -- (RT.enabled) is on; otherwise they are not built at all.
        if reader.styletweak and reader.styletweak.enabled ~= false then
            local RT = reader.styletweak

            -- CJK Tailoring (toggle)
            out[#out + 1] = {
                type = "toggle",
                key = "cjk_tailored",
                label = _("Tailor widths and text-indent for CJK"),
                get_on = function() return RT:isTweakEnabled("cjk_tailored") end,
                on_toggle = function() RT:onToggleStyleTweak("cjk_tailored", nil, true) end,
            }

            -- First-line Indent (choice)
            local INDENT_IDS = {
                "paragraph_no_indent",
                "paragraph_indent",
                "paragraph_first_no_indent",
                "paragraph_following_no_indent",
            }
            out[#out + 1] = {
                type = "choice",
                key = "first_line_indent",
                label = _("Paragraph first-line indentation"),
                default_label = _("Default"),
                choices = {
                    { id = nil,                              label = _("Default") },
                    { id = "paragraph_no_indent",           label = _("No indentation on first paragraph line") },
                    { id = "paragraph_indent",              label = _("Indentation on first paragraph line") },
                    { id = "paragraph_first_no_indent",     label = _("No indentation on first paragraph") },
                    { id = "paragraph_following_no_indent", label = _("No indentation on following paragraphs") },
                },
                get_active = function()
                    for _, id in ipairs(INDENT_IDS) do
                        if RT:isTweakEnabled(id) then return id end
                    end
                    return nil
                end,
                on_pick = function(chosen_id)
                    for _, id in ipairs(INDENT_IDS) do
                        if RT:isTweakEnabled(id) then
                            RT:onToggleStyleTweak(id, nil, true)
                        end
                    end
                    if chosen_id then
                        RT:onToggleStyleTweak(chosen_id, nil, true)
                    end
                end,
            }

            -- Paragraph Spacing (choice)
            local SPACING_IDS = {
                "paragraph_whitespace",
                "paragraph_whitespace_half",
                "paragraph_no_whitespace",
            }
            out[#out + 1] = {
                type = "choice",
                key = "paragraph_spacing",
                label = _("Spacing between paragraphs"),
                default_label = _("Default"),
                choices = {
                    { id = nil,                          label = _("Default") },
                    { id = "paragraph_whitespace",      label = _("Spacing between paragraphs") },
                    { id = "paragraph_whitespace_half", label = _("Spacing between paragraphs (half)") },
                    { id = "paragraph_no_whitespace",   label = _("No spacing between paragraphs") },
                },
                get_active = function()
                    for _, id in ipairs(SPACING_IDS) do
                        if RT:isTweakEnabled(id) then return id end
                    end
                    return nil
                end,
                on_pick = function(chosen_id)
                    for _, id in ipairs(SPACING_IDS) do
                        if RT:isTweakEnabled(id) then
                            RT:onToggleStyleTweak(id, nil, true)
                        end
                    end
                    if chosen_id then
                        RT:onToggleStyleTweak(chosen_id, nil, true)
                    end
                end,
            }
        end
    end

    if is_pdf then
        out[#out + 1] = {
            key = "pdf_contrast",
            label = _("Contrast"),
            enabled_key = "qa_panel_reader_gamma",
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
        }
        out[#out + 1] = {
            key = "pdf_zoom_overlap_h",
            enabled_key = "qa_panel_reader_zoom",
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
            should_show = function()
                local g = configurable.zoom_mode_genus
                return g ~= nil and g < 3
            end,
        }
        out[#out + 1] = {
            key = "pdf_zoom_overlap_v",
            label = _("Vertical overlap"),
            enabled_key = "qa_panel_reader_zoom",
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
            should_show = function()
                local g = configurable.zoom_mode_genus
                return g ~= nil and g < 3
            end,
        }
        out[#out + 1] = {
            key = "pdf_zoom_range_number",
            enabled_key = "qa_panel_reader_zoom",
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
            should_show = function()
                local g = configurable.zoom_mode_genus
                return g ~= nil and (g == 1 or g == 2)
            end,
        }
        out[#out + 1] = {
            key = "pdf_zoom_factor",
            label = _("Zoom factor"),
            enabled_key = "qa_panel_reader_zoom",
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
            should_show = function()
                local g = configurable.zoom_mode_genus
                return g ~= nil and g == 0
            end,
        }
    end

    return out
end

-- ============================================================
-- Slider row builder
-- ============================================================

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

    local apply, refresh

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
-- Choice row builder
-- ============================================================

function M.buildChoiceRow(opts, row_width, label_size, show_parent, on_change)
    local gap         = Screen:scaleBySize(4)
    local small_btn_w = Screen:scaleBySize(40)
    local label_w     = Screen:scaleBySize(180)
    local value_w     = row_width - label_w - 2 * small_btn_w - 3 * gap

    local _d = Button:new{
        text = "\u{2212}", width = small_btn_w,
        show_parent = show_parent,
        callback = function() end,
    }
    local btn_h = math.max(30, _d:getSize().h)

    local function getCurrentLabel()
        local active_id = opts.get_active and opts.get_active() or nil
        for _, c in ipairs(opts.choices) do
            if c.id == active_id then return c.label end
        end
        return opts.default_label or "—"
    end

    local value_btn
    value_btn = Button:new{
        text           = getCurrentLabel(),
        width          = value_w,
        height         = btn_h,
        padding        = 0,
        bordersize     = 0,
        text_font_size = label_size,
        text_font_bold = false,
        align     = "left",  
        show_parent    = show_parent,
        callback = function()
            local dlg
            local btns = {}
            for _, c in ipairs(opts.choices) do
                local choice = c
                table.insert(btns, {{
                    text = choice.label,
                    callback = function()
                        UIManager:close(dlg)
                        if opts.on_pick then opts.on_pick(choice.id) end
                        value_btn:setText(getCurrentLabel(), value_w)
                        UIManager:setDirty(show_parent, "ui")
                        if on_change then on_change(choice.id) end
                    end,
                }})
            end
            table.insert(btns, {{
                text = _("Cancel"),
                id = "close",
                callback = function() UIManager:close(dlg) end,
            }})
            dlg = ButtonDialog:new{
                title = opts.label,
                buttons = btns,
                width = math.floor(Screen:getWidth() * 0.7),
                tap_close_callback = function() UIManager:close(dlg) end,
            }
            UIManager:show(dlg)
        end,
    }

    local label_widget = Button:new{
        text           = opts.label,
        width          = label_w,
        height         = btn_h,
        padding        = 0,
        bordersize     = 0,
        text_font_size = label_size,
        text_font_bold = false,
        align     = "left", 
        show_parent    = show_parent,
        callback       = function() end,
    }

    local row = HorizontalGroup:new{
        align = "center",
        label_widget,
        HorizontalSpan:new{ width = gap },
        value_btn,
    }

    return row, value_btn
end

-- ============================================================
-- Toggle row builder (checkbox-style: ✓ prefix on the label)
-- ============================================================

function M.buildToggleRow(opts, row_width, label_size, show_parent, on_change)
    local small_btn_w = Screen:scaleBySize(40)

    local _d = Button:new{
        text = "\u{2212}", width = small_btn_w,
        show_parent = show_parent,
        callback = function() end,
    }
    local btn_h = math.max(30, _d:getSize().h)

    local row_w = row_width

    local function label_text()
        local mark = opts.get_on() and "✓ " or "  "
        return mark .. opts.label
    end

    local btn
    btn = Button:new{
        text           = label_text(),
        width          = row_w,
        height         = btn_h,
        padding        = 0,
        bordersize     = 0,
        text_font_size = label_size,
        text_font_bold = false,
        align     = "left", 
        show_parent    = show_parent,
        callback = function()
            if opts.on_toggle then opts.on_toggle() end
            btn:setText(label_text(), row_w)
            UIManager:setDirty(show_parent, "ui")
            if on_change then on_change() end
        end,
    }

    return btn, btn
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

    local Utils = require("qui_utils")
    local scale_pct = Utils.getNumber("qa_panel_label_scale_pct", 90)
    local label_size = Screen:scaleBySize(
        math.max(6, math.floor(12 * (scale_pct / 100)))
    )
    local panel_w    = math.floor(Screen:getWidth() * 0.85)
    local padding    = Screen:scaleBySize(14)
    local inner_w    = panel_w - padding * 2

    local vg = VerticalGroup:new{ align = "left" }

    local temp_parent = {}

    -- Split into regular sliders (no `type`) and style-tweak rows
    -- (`type == "choice"` / `"toggle"`) so the master switch can sit
    -- between them: sliders → master → tweaks.
    local regular, tweak_rows = {}, {}
    for _, opts in ipairs(sliders) do
        if opts.type then
            tweak_rows[#tweak_rows + 1] = opts
        else
            regular[#regular + 1] = opts
        end
    end

    -- 1. Regular sliders
    for _, opts in ipairs(regular) do
        local row = M.buildSliderRow(opts, inner_w, label_size, temp_parent, nil)
        vg[#vg + 1] = row
        vg[#vg + 1] = VerticalSpan:new{ width = Screen:scaleBySize(8) }
    end

    -- 2. Style-Tweaks master switch (between regular sliders and tweaks)
    local RT = reader.styletweak
    if RT then
        local function master_label()
            local mark = (RT.enabled ~= false) and "✓ " or "  "
            return mark .. _("Enable style tweaks")
        end
        local master_btn
        master_btn = Button:new{
            text           = master_label(),
            width          = inner_w,
            height         = Screen:scaleBySize(30),
            padding        = 0,
            bordersize     = 0,
            text_font_size = label_size,
            text_font_bold = true,
            align     = "left", 
            show_parent    = temp_parent,
            callback = function()
                RT.enabled = not (RT.enabled ~= false)
                RT:updateCssText(true)
                UIManager:close(_dialog)
                _dialog = nil
                M.show()
            end,
        }
        vg[#vg + 1] = VerticalSpan:new{ width = Screen:scaleBySize(12) }
        vg[#vg + 1] = master_btn
    end

    -- 3. Style-tweak rows (only present in the list when RT.enabled)
    for _, opts in ipairs(tweak_rows) do
        local row
        if opts.type == "choice" then
            row = M.buildChoiceRow(opts, inner_w, label_size, temp_parent, nil)
        elseif opts.type == "toggle" then
            row = M.buildToggleRow(opts, inner_w, label_size, temp_parent, nil)
        end
        if row then
            vg[#vg + 1] = VerticalSpan:new{ width = Screen:scaleBySize(8) }
            vg[#vg + 1] = row
        end
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
        self.movable = MovableContainer:new{
            ignore_events = {
                "touch",
                "hold",
                "hold_pan",
                "hold_release",
                "pan",
                "pan_release",
            },
            frame,
        }
        self[1] = CenterContainer:new{
            dimen = Geom:new{
                w = Screen:getWidth(),
                h = Screen:getHeight(),
            },
            self.movable,
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
        if ges.pos:notIntersectWith(self.movable.dimen) then
            UIManager:close(self)
            _dialog = nil
        end
        return true
    end

    _dialog = PickerDlg:new{}
    UIManager:show(_dialog, "ui")
end

return M
