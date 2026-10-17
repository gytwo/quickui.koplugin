--[[
QuickUI - Reader Sliders

Single source of truth for reader typography sliders, plus the reading
background feature (master toggle / background image / transparency),
exposed as a collapsible block right after Style Tweaks.

Reading background:
  - Painted by crengine via setBackgroundImage(), exactly like custombg.
  - The source image is scaled to screen size, the requested transparency
    is baked in by blending toward white per-pixel, and the result is
    written to cache/ so subsequent renders just reuse the cached file.
  - Transparency = 0 means "no overlay" (original image);
    transparency = 100 means "fully white" (image invisible).
  - Re-applied on open, on every render (via onPreRenderDocument), and on
    a short timer after open, so reflows that reset the background are
    corrected immediately.

Reading background storage:
  quickui.lua (via Utils.get/set):
    qa_common_reading_bg_enabled        master switch
    qa_common_reading_bg_transparency   global transparency 0..100
    qa_common_reading_bg_image          global default image path
  doc_settings (per book, sidecar):
    reading_bg_doc_image                this book's image path
    reading_bg_doc_none                 this book explicitly wants no background
    reading_bg_doc_transparency         this book's transparency override
]]
local ConfirmBox      = require("ui/widget/confirmbox")
local Dispatcher      = require("dispatcher")
local Event           = require("ui/event")
local ffiUtil         = require("ffi/util")
local Blitbuffer      = require("ffi/blitbuffer")
local Button          = require("ui/widget/button")
local ButtonDialog    = require("ui/widget/buttondialog")
local CenterContainer = require("ui/widget/container/centercontainer")
local MovableContainer = require("ui/widget/container/movablecontainer")
local Device          = require("device")
local Font            = require("ui/font")
local FrameContainer  = require("ui/widget/container/framecontainer")
local Geom            = require("ui/geometry")
local GestureRange    = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local InfoMessage     = require("ui/widget/infomessage")
local InputContainer  = require("ui/widget/container/inputcontainer")
local Notification    = require("ui/widget/notification")
local PathChooser     = require("ui/widget/pathchooser")
local Screen          = require("device").screen
local SpinWidget      = require("ui/widget/spinwidget")
local TextWidget      = require("ui/widget/textwidget")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local lfs             = require("libs/libkoreader-lfs")
local logger          = require("logger")
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
-- Reading Background — custombg port with baked-in transparency
-- ============================================================

local RBG_KEYS = {
    enabled      = "qa_common_reading_bg_enabled",
    transparency = "qa_common_reading_bg_transparency",
    image        = "qa_common_reading_bg_image",
    doc_image    = "reading_bg_doc_image",
    doc_none     = "reading_bg_doc_none",
    doc_transparency = "reading_bg_doc_transparency",
}

local RBG_DEFAULT_TRANSPARENCY = 85

local RBG_IMG_EXT = {
    jpg = true, jpeg = true, png = true, webp = true, bmp = true, gif = true,
}

local function rbg_warn(msg)
    logger.warn("QuickUI reading_bg: " .. tostring(msg))
end

local function rbg_cget(key, default)
    local v = Utils.get(key, nil)
    if v == nil then return default end
    return v
end

local function rbg_cset(key, value)
    Utils.set(key, value)
end

local function rbg_reader()
    local RUI = require("apps/reader/readerui")
    return RUI and RUI.instance
end

local function rbg_doc_settings()
    local reader = rbg_reader()
    return reader and reader.doc_settings, reader
end

local function rbg_file_is_image(path)
    if type(path) ~= "string" or path == "" then return false end
    if lfs.attributes(path, "mode") ~= "file" then return false end
    local ext = path:match("%.([^%.]+)$")
    return ext and RBG_IMG_EXT[ext:lower()] or false
end

local function rbg_filename(path)
    if type(path) ~= "string" or path == "" then return "" end
    return path:match("([^/]+)$") or path
end

local function rbg_current_scope()
    local doc_settings = rbg_doc_settings()
    if not doc_settings then return "global" end
    if doc_settings:readSetting(RBG_KEYS.doc_none) == true then return "none" end
    local p = doc_settings:readSetting(RBG_KEYS.doc_image)
    if p and p ~= "" then return "doc" end
    return "global"
end

local function rbg_current_label()
    local doc_settings = rbg_doc_settings()
    if doc_settings then
        if doc_settings:readSetting(RBG_KEYS.doc_none) == true then
            return _("No background")
        end
        local p = doc_settings:readSetting(RBG_KEYS.doc_image)
        if p and p ~= "" then
            return rbg_filename(p)
        end
    end
    local gp = rbg_cget(RBG_KEYS.image, "")
    if gp ~= "" then
        return _("Follow global") .. " (" .. rbg_filename(gp) .. ")"
    end
    return _("Follow global")
end

local function rbg_resolve_image()
    if rbg_cget(RBG_KEYS.enabled, false) ~= true then
        return nil
    end

    local doc_settings = rbg_doc_settings()
    if doc_settings then
        if doc_settings:readSetting(RBG_KEYS.doc_none) == true then
            return nil
        end
        local path = doc_settings:readSetting(RBG_KEYS.doc_image)
        if rbg_file_is_image(path) then return path end
    end

    local path = rbg_cget(RBG_KEYS.image, "")
    if rbg_file_is_image(path) then return path end
    return nil
end

local function rbg_resolve_transparency()
    local doc_settings = rbg_doc_settings()
    if doc_settings then
        local v = doc_settings:readSetting(RBG_KEYS.doc_transparency)
        if v ~= nil then return tonumber(v) end
    end
    return tonumber(rbg_cget(RBG_KEYS.transparency, RBG_DEFAULT_TRANSPARENCY))
        or RBG_DEFAULT_TRANSPARENCY
end

-- ---- cache ----

local function rbg_cache_dir()
    local dir = Utils.getPluginDir() .. "cache/"
    pcall(function() lfs.mkdir(dir) end)
    return dir
end

local function rbg_hash(s)
    local h = 5381
    for i = 1, #s do
        h = (h * 33 + string.byte(s, i)) % 2147483648
    end
    return string.format("%x", h)
end

local function rbg_read_rgb(px)
    if px == nil then return 0, 0, 0 end
    local ok, r, g, b = pcall(function()
        return px.r, px.g, px.b
    end)
    if ok and r ~= nil then
        return r, g, b
    end
    return 0, 0, 0
end

local function rbg_apply_white_overlay(bb, w, h, cover)
    if cover <= 0 then return end
    if cover >= 1 then
        bb:fill(Blitbuffer.Color8(0xFF))
        return
    end

    local solid = Blitbuffer.new(w, h, bb:getType())
    if not solid then return end
    solid:fill(Blitbuffer.Color8(0xFF))
    local intensity = math.floor((1 - cover) * 255)
    bb:addblitFrom(solid, 0, 0, 0, 0, w, h, intensity)
    solid:free()
end

local function rbg_apply_black_overlay(bb, w, h, cover)
    if cover <= 0 then return end
    if cover >= 1 then
        bb:fill(Blitbuffer.Color8(0x00))
        return
    end

    local solid = Blitbuffer.new(w, h, bb:getType())
    if not solid then return end
    solid:fill(Blitbuffer.Color8(0x00))
    local intensity = math.floor((1 - cover) * 255)
    bb:addblitFrom(solid, 0, 0, 0, 0, w, h, intensity)
    solid:free()
end

local function rbg_scaled_path(source, transparency)
    if not source or source == "" then return nil end
    transparency = math.max(0, math.min(100, math.floor((transparency or 0) + 0.5)))
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    local night = (Screen.night_mode == true)
        or G_reader_settings:isTrue("night_mode")

    local source_name = rbg_filename(source)
    source_name = source_name:gsub("%.[^.]+$", "")
    source_name = source_name:gsub("[^%w%-_]", "_")
    source_name = source_name:sub(1, 40)

    local cache_name = string.format(
        "%s_%s_%dx%d_%s_t%d.png",
        source_name, rbg_hash(source), sw, sh,
        night and "night" or "day", transparency
    )
    local cache_path = rbg_cache_dir() .. cache_name
    if lfs.attributes(cache_path, "mode") == "file" then
        return cache_path
    end

    local ok, result = pcall(function()
        local RenderImage = require("ui/renderimage")
        local src_bb = RenderImage:renderImageFile(source, false, nil, nil)
        if not src_bb then return nil end
        local final_bb
        if src_bb:getWidth() == sw and src_bb:getHeight() == sh then
            final_bb = src_bb:copy()
        else
            final_bb = RenderImage:scaleBlitBuffer(src_bb, sw, sh, true)
        end
        src_bb:free()
        if not final_bb then return nil end

        if transparency > 0 then
            if night then
                rbg_apply_black_overlay(final_bb, sw, sh, transparency / 100)
            else
                rbg_apply_white_overlay(final_bb, sw, sh, transparency / 100)
            end
        end

        if final_bb:writeToFile(cache_path, "png", 75) then
            final_bb:free()
            return cache_path
        else
            final_bb:free()
            return nil
        end
    end)

    if ok and result then
        return result
    end
    rbg_warn("scale failed for " .. tostring(source) .. " err=" .. tostring(result))
    return source
end

local function rbg_apply_background(doc)
    if not doc or type(doc.setBackgroundImage) ~= "function" then
        return
    end
    local source = rbg_resolve_image()
    if source then
        local transparency = rbg_resolve_transparency()
        local scaled = rbg_scaled_path(source, transparency)
        if scaled then
            doc:setBackgroundImage(scaled)
        else
            doc:setBackgroundImage()
        end
    else
        doc:setBackgroundImage()
    end
    if doc.setBackgroundColor then
        doc:setBackgroundColor(0xFFFFFF)
    end
end

local function rbg_reapply()
    local reader = rbg_reader()
    if not (reader and reader.document) then return end
    if type(reader.document.setBackgroundImage) ~= "function" then
        return
    end
    rbg_apply_background(reader.document)
    UIManager:setDirty("all", "full")
end

-- ---- public actions ----

local function rbg_set_enabled(on)
    rbg_cset(RBG_KEYS.enabled, on == true)
    rbg_reapply()
end

local function rbg_set_global_transparency(v)
    v = math.max(0, math.min(100, math.floor((v or 0) + 0.5)))
    rbg_cset(RBG_KEYS.transparency, v)
    rbg_reapply()
    return v
end

local function rbg_set_doc_transparency(v)
    v = math.max(0, math.min(100, math.floor((v or 0) + 0.5)))
    local doc_settings = rbg_doc_settings()
    if doc_settings then
        doc_settings:saveSetting(RBG_KEYS.doc_transparency, v)
    end
    rbg_reapply()
    return v
end

local function rbg_clear_doc_transparency()
    local doc_settings = rbg_doc_settings()
    if doc_settings then
        doc_settings:saveSetting(RBG_KEYS.doc_transparency, nil)
    end
    rbg_reapply()
end

local function rbg_apply_image(path, scope)
    if not rbg_file_is_image(path) then
        return
    end
    if scope == "doc" then
        local doc_settings = rbg_doc_settings()
        if doc_settings then
            doc_settings:saveSetting(RBG_KEYS.doc_image, path)
            doc_settings:saveSetting(RBG_KEYS.doc_none, nil)
        end
    else
        rbg_cset(RBG_KEYS.image, path)
    end
    rbg_reapply()
end

local function rbg_set_doc_none()
    local doc_settings = rbg_doc_settings()
    if not doc_settings then return end
    doc_settings:saveSetting(RBG_KEYS.doc_none, true)
    doc_settings:saveSetting(RBG_KEYS.doc_image, nil)
    rbg_reapply()
end

local function rbg_clear_doc_override()
    local doc_settings = rbg_doc_settings()
    if not doc_settings then return end
    doc_settings:saveSetting(RBG_KEYS.doc_none, nil)
    doc_settings:saveSetting(RBG_KEYS.doc_image, nil)
    rbg_reapply()
end

local function rbg_pick_image(on_done)
    local start = G_reader_settings:readSetting("home_dir") or "/"
    local current = rbg_cget(RBG_KEYS.image, "")
    if current ~= "" then
        local dir = current:match("^(.*)/[^/]+$")
        if dir then start = dir end
    end

    local chooser
    chooser = PathChooser:new{
        select_directory = false,
        select_file = true,
        path = start,
        title = _("Choose background image"),
        file_filter = function(filename)
            local ext = filename:lower():match("%.([^%.]+)$")
            return ext ~= nil and RBG_IMG_EXT[ext] == true
        end,
        onConfirm = function(path)
            if not rbg_file_is_image(path) then
                UIManager:show(InfoMessage:new{
                    text = _("Please choose an image file."),
                    timeout = 2,
                })
                return
            end
            local dlg
            local buttons = {
                {
                    {
                        text = _("All books"),
                        callback = function()
                            UIManager:close(dlg)
                            rbg_apply_image(path, "global")
                            if on_done then on_done() end
                        end,
                    },
                    {
                        text = _("This book only"),
                        callback = function()
                            UIManager:close(dlg)
                            rbg_apply_image(path, "doc")
                            if on_done then on_done() end
                        end,
                    },
                },
                {
                    {
                        text = _("Cancel"),
                        id = "close",
                        callback = function() UIManager:close(dlg) end,
                    },
                },
            }
            dlg = ButtonDialog:new{
                title = _("Apply this background image to"),
                title_align = "center",
                buttons = buttons,
                width = math.floor(Screen:getWidth() * 0.7),
            }
            UIManager:show(dlg)
        end,
        onCancel = function() end,
    }
    UIManager:show(chooser)
end

-- ---- hook ----

local function rbg_install_hook()
    local ReaderRolling = require("apps/reader/modules/readerrolling")
    if ReaderRolling._quickui_rbg_patched then return end
    ReaderRolling._quickui_rbg_patched = true

    local orig_read = ReaderRolling.onReadSettings
    ReaderRolling.onReadSettings = function(self, ...)
        orig_read(self, ...)
        pcall(function()
            local ui = self.ui
            if ui and ui.document then
                rbg_apply_background(ui.document)
                UIManager:scheduleIn(1.0, function()
                    pcall(function()
                        local doc = ui and ui.document
                        if doc then
                            rbg_apply_background(doc)
                            UIManager:setDirty("all", "full")
                        end
                    end)
                end)
            end
        end)
    end

    local orig_pre = ReaderRolling.onPreRenderDocument
    ReaderRolling.onPreRenderDocument = function(self, ...)
        if orig_pre then orig_pre(self, ...) end
        pcall(function()
            local doc = self.ui and self.ui.document
            if not doc then return end
            local night = (Screen.night_mode == true)
                or G_reader_settings:isTrue("night_mode")
            if doc._quickui_rbg_night ~= night then
                doc._quickui_rbg_night = night
                rbg_apply_background(doc)
                UIManager:setDirty("all", "full")
            else
                rbg_apply_background(doc)
            end
        end)
    end

    local orig_screen_toggle = Screen.toggleNightMode
    if type(orig_screen_toggle) == "function" then
        function Screen:toggleNightMode(...)
            local ret = orig_screen_toggle(self, ...)
            UIManager:nextTick(function()
                pcall(rbg_reapply)
            end)
            return ret
        end
    end

    local orig_SetNightMode = UIManager.SetNightMode
    if orig_SetNightMode then
        function UIManager:SetNightMode(nightmode)
            orig_SetNightMode(self, nightmode)
            rbg_reapply()
        end
    end
end

local function rbg_install_footer_transparent()
    local ReaderFooter = require("apps/reader/modules/readerfooter")
    if ReaderFooter._quickui_transparent_patched then return end
    ReaderFooter._quickui_transparent_patched = true

    local orig = ReaderFooter.updateFooterContainer
    ReaderFooter.updateFooterContainer = function(self, ...)
        orig(self, ...)
        if self.footer_content then
            self.footer_content.background = nil
        end
    end
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

        -- ── Reading Background ────────────────────────────────────────
        if rbg_cget(RBG_KEYS.enabled, false) == true then
            out[#out + 1] = {
                type = "choice",
                group = "reading_bg",
                key = RBG_KEYS.image,
                label = _("Background image"),
                default_label = _("Follow global"),
                choices = {
                    { id = "global", label = _("Follow global") },
                    { id = "pick",   label = _("Choose image…") },
                    { id = "none",   label = _("No background") },
                },
                get_active = function()
                    local scope = rbg_current_scope()
                    if scope == "doc" then return "pick" end
                    return scope
                end,
                get_current_label = rbg_current_label,
                on_pick = function(id)
                    if id == "none" then
                        rbg_set_doc_none()
                    elseif id == "global" then
                        rbg_clear_doc_override()
                    elseif id == "pick" then
                        rbg_pick_image(function()
                            if _dialog then
                                UIManager:close(_dialog)
                                _dialog = nil
                            end
                            M.show()
                        end)
                    end
                end,
            }

            out[#out + 1] = {
                key = "global_transparency",
                group = "reading_bg",
                label = _("Global transparency"),
                min = 0, max = 100, step = 1,
                default = function() return RBG_DEFAULT_TRANSPARENCY end,
                global_key = RBG_KEYS.transparency,
                get = function()
                    return tonumber(rbg_cget(RBG_KEYS.transparency,
                        RBG_DEFAULT_TRANSPARENCY)) or RBG_DEFAULT_TRANSPARENCY
                end,
                set = function(v)
                    return rbg_set_global_transparency(v)
                end,
            }

            out[#out + 1] = {
                key = "doc_transparency",
                group = "reading_bg",
                label = _("This book transparency"),
                min = 0, max = 100, step = 1,
                default = function()
                    local doc_settings = rbg_doc_settings()
                    if doc_settings then
                        doc_settings:saveSetting(RBG_KEYS.doc_transparency, nil)
                    end
                    rbg_reapply()
                    return rbg_resolve_transparency()
                end,
                get = function()
                    local doc_settings = rbg_doc_settings()
                    if doc_settings then
                        local v = doc_settings:readSetting(RBG_KEYS.doc_transparency)
                        if v ~= nil then return tonumber(v) end
                    end
                    return nil
                end,
                set = function(v)
                    return rbg_set_doc_transparency(v)
                end,
            }
        end

        -- ── Style Tweaks (crengine only) ─────────────────────────────
        if reader.styletweak and reader.styletweak.enabled ~= false then
            local RT = reader.styletweak

            out[#out + 1] = {
                type = "toggle",
                key = "cjk_tailored",
                label = _("Tailor widths and text-indent for CJK"),
                get_on = function() return RT:isTweakEnabled("cjk_tailored") end,
                on_toggle = function() RT:onToggleStyleTweak("cjk_tailored", nil, true) end,
            }

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
                    for _idx, id in ipairs(INDENT_IDS) do
                        if RT:isTweakEnabled(id) then return id end
                    end
                    return nil
                end,
                on_pick = function(chosen_id)
                    for _idx, id in ipairs(INDENT_IDS) do
                        if RT:isTweakEnabled(id) then
                            RT:onToggleStyleTweak(id, nil, true)
                        end
                    end
                    if chosen_id then
                        RT:onToggleStyleTweak(chosen_id, nil, true)
                    end
                end,
            }

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
                    for _idx, id in ipairs(SPACING_IDS) do
                        if RT:isTweakEnabled(id) then return id end
                    end
                    return nil
                end,
                on_pick = function(chosen_id)
                    for _idx, id in ipairs(SPACING_IDS) do
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
        if opts.get_current_label then
            local s = opts.get_current_label()
            if s and s ~= "" then return s end
        end
        local active_id = opts.get_active and opts.get_active() or nil
        for _idx, c in ipairs(opts.choices) do
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
            for _idx, c in ipairs(opts.choices) do
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
-- Toggle row builder
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

    local scale_pct = Utils.getNumber("qa_panel_label_scale_pct", 90)
    local label_size = Screen:scaleBySize(
        math.max(6, math.floor(12 * (scale_pct / 100)))
    )
    local panel_w    = math.floor(Screen:getWidth() * 0.85)
    local padding    = Screen:scaleBySize(14)
    local inner_w    = panel_w - padding * 2

    local vg = VerticalGroup:new{ align = "left" }

    local temp_parent = {}

    M._collapsed = M._collapsed or { styletweaks = true, reading_bg = true }

    local function makeCollapseHeader(title, key)
        local collapsed = M._collapsed[key]
        local arrow = collapsed and "▶   " or "▼ "
        local btn = Button:new{
            text = arrow .. title,
            width = inner_w,
            height = Screen:scaleBySize(30),
            padding = 0,
            bordersize = 0,
            text_font_size = label_size,
            text_font_bold = true,
            align = "left",
            show_parent = temp_parent,
            callback = function()
                M._collapsed[key] = not M._collapsed[key]
                UIManager:close(_dialog)
                _dialog = nil
                M.show()
            end,
        }
        return btn
    end

    local regular, tweak_rows, bg_rows = {}, {}, {}
    for _idx, opts in ipairs(sliders) do
        if opts.group == "reading_bg" then
            bg_rows[#bg_rows + 1] = opts
        elseif opts.type then
            tweak_rows[#tweak_rows + 1] = opts
        else
            regular[#regular + 1] = opts
        end
    end

    -- 1. Regular sliders
    for _idx, opts in ipairs(regular) do
        local row = M.buildSliderRow(opts, inner_w, label_size, temp_parent, nil)
        vg[#vg + 1] = row
        vg[#vg + 1] = VerticalSpan:new{ width = Screen:scaleBySize(8) }
    end

    -- 2 + 3. Style-Tweaks section (collapsible)
    if reader.styletweak then
        vg[#vg + 1] = VerticalSpan:new{ width = Screen:scaleBySize(16) }
        vg[#vg + 1] = makeCollapseHeader(_("Style Tweaks"), "styletweaks")

        if not M._collapsed.styletweaks then
            vg[#vg + 1] = VerticalSpan:new{ width = Screen:scaleBySize(8) }

            local RT = reader.styletweak
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
                align          = "left",
                show_parent    = temp_parent,
                callback = function()
                    RT.enabled = not (RT.enabled ~= false)
                    RT:updateCssText(true)
                    UIManager:close(_dialog)
                    _dialog = nil
                    M.show()
                end,
            }
            vg[#vg + 1] = master_btn

            for _idx, opts in ipairs(tweak_rows) do
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
        end
    end

    -- 4. Reading Background section (collapsible)
    if reader.document.provider == "crengine" then
        vg[#vg + 1] = VerticalSpan:new{ width = Screen:scaleBySize(16) }
        vg[#vg + 1] = makeCollapseHeader(_("Reading Background"), "reading_bg")

        if not M._collapsed.reading_bg then
            vg[#vg + 1] = VerticalSpan:new{ width = Screen:scaleBySize(8) }

            local enabled = rbg_cget(RBG_KEYS.enabled, false) == true
            local function master_label()
                return (enabled and "✓ " or "  ") .. _("Enable reading background")
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
                align          = "left",
                show_parent    = temp_parent,
                callback = function()
                    rbg_set_enabled(not enabled)
                    UIManager:close(_dialog)
                    _dialog = nil
                    M.show()
                end,
            }
            vg[#vg + 1] = master_btn

            if enabled then
                for _idx, opts in ipairs(bg_rows) do
                    local row
                    if opts.type == "choice" then
                        row = M.buildChoiceRow(opts, inner_w, label_size, temp_parent, nil)
                    else
                        row = M.buildSliderRow(opts, inner_w, label_size, temp_parent, nil)
                    end
                    if row then
                        vg[#vg + 1] = VerticalSpan:new{ width = Screen:scaleBySize(8) }
                        vg[#vg + 1] = row
                    end
                end
            end
        end
    end

    -- 5. Profiles section
    do
        local profiles = reader.profiles
        if profiles and profiles.data then
            vg[#vg + 1] = VerticalSpan:new{ width = Screen:scaleBySize(16) }

            local profile_names = {}
            for name in ffiUtil.orderedPairs(profiles.data) do
                profile_names[#profile_names + 1] = name
            end

            local COLS = 5
            local GAP = Screen:scaleBySize(6)
            local cell_w = math.floor((inner_w - (COLS - 1) * GAP) / COLS)
            local cell_h = Screen:scaleBySize(36)

            local entries = {}
            entries[#entries + 1] = { kind = "new" }
            for _idx, name in ipairs(profile_names) do
                entries[#entries + 1] = { kind = "profile", name = name }
            end

            local row_hg = nil
            for i, entry in ipairs(entries) do
                if (i - 1) % COLS == 0 then
                    if row_hg then
                        vg[#vg + 1] = row_hg
                        vg[#vg + 1] = VerticalSpan:new{ width = GAP }
                    end
                    row_hg = HorizontalGroup:new{ align = "center" }
                else
                    row_hg[#row_hg + 1] = HorizontalSpan:new{ width = GAP }
                end

                local btn
                if entry.kind == "new" then
                    btn = Button:new{
                        text = "＋ " .. _("Profile"),
                        width = cell_w,
                        height = cell_h,
                        bordersize = 0,
                        text_font_size = label_size,
                        text_font_bold = false,
                        show_parent = temp_parent,
                        callback = function()
                            profiles:editProfileName(function(name)
                                profiles.data[name] = profiles:getProfileFromCurrentBookSettings(name)
                                profiles.updated = true
                                UIManager:close(_dialog)
                                _dialog = nil
                                M.show()
                            end)
                        end,
                    }
                else
                    local _name = entry.name
                    btn = Button:new{
                        text = _name,
                        width = cell_w,
                        height = cell_h,
                        bordersize = 0,
                        text_font_size = label_size,
                        text_font_bold = false,
                        show_parent = temp_parent,
                        callback = function()
                            UIManager:close(_dialog)
                            _dialog = nil
                            profiles:onProfileExecute(_name, { qm_show = false })
                        end,
                        hold_callback = function()
                            UIManager:show(ConfirmBox:new{
                                text = string.format(_("Delete profile \"%s\"?"), _name),
                                ok_text = _("Delete"),
                                cancel_text = _("Cancel"),
                                ok_callback = function()
                                    local profile = profiles.data[_name]
                                    if profile then
                                        profiles:updateAutoExec(_name)
                                        if profile.settings and profile.settings.registered then
                                            Dispatcher:removeAction(profiles.prefix .. _name)
                                            UIManager:broadcastEvent(Event:new("DispatcherActionNameChanged",
                                                { old_name = profiles.prefix .. _name, new_name = nil }))
                                        end
                                        profiles.data[_name] = nil
                                        profiles.updated = true
                                        UIManager:close(_dialog)
                                        _dialog = nil
                                        M.show()
                                    end
                                end,
                            })
                        end,
                    }
                end

                row_hg[#row_hg + 1] = btn
            end

            if row_hg then
                vg[#vg + 1] = row_hg
            end
        end
    end

    -- 6. Document settings: Reset + Save as default
    do
        local reader2 = RUI and RUI.instance
        if reader2 and reader2.menu then
            vg[#vg + 1] = VerticalSpan:new{ width = Screen:scaleBySize(16) }

            local GAP = Screen:scaleBySize(6)
            local btn_w = math.floor((inner_w - GAP) / 2)
            local btn_h = Screen:scaleBySize(36)

            local reset_btn = Button:new{
                text = _("Reset document settings to default"),
                width = btn_w,
                height = btn_h,
                bordersize = 0,
                text_font_size = label_size,
                show_parent = temp_parent,
                callback = function()
                    UIManager:show(ConfirmBox:new{
                        text = _("Reset current document settings to their default values?\n\nReading position, highlights and bookmarks will be kept.\nThe document will be reloaded."),
                        ok_text = _("Reset"),
                        cancel_text = _("Cancel"),
                        ok_callback = function()
                            local current_file = reader2.document and reader2.document.file
                            UIManager:close(_dialog)
                            _dialog = nil
                            if not current_file then return end
                            reader2:onClose()
                            require("apps/filemanager/filemanagerutil").resetDocumentSettings(current_file)
                            require("apps/reader/readerui"):showReader(current_file)
                        end,
                    })
                end,
            }

            local save_btn = Button:new{
                text = _("Save document settings as default"),
                width = btn_w,
                height = btn_h,
                bordersize = 0,
                text_font_size = label_size,
                show_parent = temp_parent,
                callback = function()
                    UIManager:show(ConfirmBox:new{
                        text = _("Save current document settings as default values?"),
                        ok_text = _("Save"),
                        cancel_text = _("Cancel"),
                        ok_callback = function()
                            if reader2 and reader2.menu then
                                reader2.menu:saveDocumentSettingsAsDefault()
                                UIManager:show(Notification:new{
                                    text = _("Default settings updated"),
                                    timeout = 2,
                                })
                            end
                        end,
                    })
                end,
            }

            vg[#vg + 1] = HorizontalGroup:new{
                align = "center",
                reset_btn,
                HorizontalSpan:new{ width = GAP },
                save_btn,
            }
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

-- ============================================================
-- Init
-- ============================================================

function M.init()
    rbg_install_hook()
    rbg_install_footer_transparent()
end

pcall(rbg_install_hook)
pcall(rbg_install_footer_transparent)

return M
