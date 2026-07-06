--[[
QuickUI - Header & Footer Module

Display time, page numbers, progress, chapter info, battery status,
and more at the top or bottom of the reading screen.

Fully customizable via the QuickUI menu.

Original: 2-reader-header-footer-v6.lua
]]

local TextWidget = require("ui/widget/textwidget")
local CenterContainer = require("ui/widget/container/centercontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputDialog = require("ui/widget/inputdialog")
local UIManager = require("ui/uimanager")
local BD = require("ui/bidi")
local Size = require("ui/size")
local Geom = require("ui/geometry")
local Device = require("device")
local Font = require("ui/font")
local Screen = Device.screen
local _ = require("gettext")
local T = require("ffi/util").template
local ReaderView = require("apps/reader/modules/readerview")
local cre = require("document/credocument"):engineInit()
local PowerD = require("device").powerd
local logger = require("logger")
local ButtonDialog = require("ui/widget/buttondialog")
local Notification = require("ui/widget/notification")
local ConfirmBox = require("ui/widget/confirmbox")

local Utils = require("qui_utils")

local HeaderFooter = {}

local plugin_ref = nil

-- Settings keys
local S = {
    HEADER_ENABLED = "hf_header_enabled",
    FOOTER_ENABLED = "hf_footer_enabled",
    PDF_ENABLED = "hf_pdf_enabled",

    TOP_LEFT = "hf_top_left",
    TOP_CENTER = "hf_top_center",
    TOP_RIGHT = "hf_top_right",
    BOTTOM_LEFT = "hf_bottom_left",
    BOTTOM_CENTER = "hf_bottom_center",
    BOTTOM_RIGHT = "hf_bottom_right",

    HEADER_FONT_FACE = "hf_header_font_face",
    HEADER_FONT_SIZE = "hf_header_font_size",
    HEADER_FONT_BOLD = "hf_header_font_bold",

    FOOTER_FONT_FACE = "hf_footer_font_face",
    FOOTER_FONT_SIZE = "hf_footer_font_size",
    FOOTER_FONT_BOLD = "hf_footer_font_bold",

    HEADER_TOP_PADDING = "hf_header_top_padding",
    FOOTER_BOTTOM_PADDING = "hf_footer_bottom_padding",
    LEFT_OFFSET = "hf_left_offset",
    RIGHT_OFFSET = "hf_right_offset",

    TIME_FORMAT = "hf_time_format",
    PROGRESS_DECIMALS = "hf_progress_decimals",
}

-- Default values
local DEFAULTS = {
    [S.HEADER_ENABLED] = true,
    [S.FOOTER_ENABLED] = true,
    [S.PDF_ENABLED] = false,

    [S.TOP_LEFT] = "none",
    [S.TOP_CENTER] = "time",
    [S.TOP_RIGHT] = "none",
    [S.BOTTOM_LEFT] = "none",
    [S.BOTTOM_CENTER] = "page",
    [S.BOTTOM_RIGHT] = "none",

    [S.HEADER_FONT_FACE] = "Noto Sans",
    [S.HEADER_FONT_SIZE] = 14,
    [S.HEADER_FONT_BOLD] = false,

    [S.FOOTER_FONT_FACE] = "Noto Sans",
    [S.FOOTER_FONT_SIZE] = 14,
    [S.FOOTER_FONT_BOLD] = false,

    [S.HEADER_TOP_PADDING] = 10,
    [S.FOOTER_BOTTOM_PADDING] = 10,
    [S.LEFT_OFFSET] = 0,
    [S.RIGHT_OFFSET] = 0,

    [S.TIME_FORMAT] = "24h",
    [S.PROGRESS_DECIMALS] = 2,
}

-- ============================================================
-- Configuration Helpers
-- ============================================================

local function cfg(key)
    local config = _G.__QUICKUI_CONFIG
    if config and config[key] ~= nil then
        return config[key]
    end
    return DEFAULTS[key]
end

local function setCfg(key, value)
    local config = _G.__QUICKUI_CONFIG
    if config then
        config[key] = value
        Utils.saveConfig()
    end
    local ReaderUI = require("apps/reader/readerui")
    if ReaderUI and ReaderUI.instance then
        UIManager:setDirty(ReaderUI.instance, "full")
    end
end

local function getFontFace(name, size)
    local path = cre.getFontFaceFilenameAndFaceIndex(name)
    if path then
        return Font:getFace(path, size)
    end
    return Font:getFace("ffont", size)
end

-- Content item definitions
local ITEM_LABELS = {
    none = _("(None)"),
    time = _("Current Time"),
    page = _("Page (current/total)"),
    progress = _("Progress Percentage"),
    book_progress = _("Page + Progress"),
    chapter_page = _("Chapter Page"),
    book_author = _("Book Author"),
    book_title = _("Book Title"),
    chapter_title = _("Chapter Title"),
    battery = _("Battery"),
}

local ITEM_KEYS = {
    "none", "time", "page", "progress", "book_progress",
    "chapter_page", "book_author", "book_title", "chapter_title", "battery",
}

-- Get item value
local function getItemValue(key, view)
    if key == "none" or key == nil then return "" end

    local pageno = view.state.page or 1
    local doc_pages = view.ui.doc_settings.data.doc_pages or 1
    local decimals = cfg(S.PROGRESS_DECIMALS)
    local fmt_pct = "%." .. decimals .. "f%%"

    if key == "time" then
        return os.date(cfg(S.TIME_FORMAT) == "12h" and "%I:%M %p" or "%H:%M")

    elseif key == "page" then
        return string.format("%d/%d", pageno, doc_pages)

    elseif key == "progress" then
        local pct = doc_pages > 0 and (pageno / doc_pages * 100) or 0
        return string.format(fmt_pct, pct)

    elseif key == "book_progress" then
        local pct = doc_pages > 0 and (pageno / doc_pages * 100) or 0
        return string.format("%d/%d " .. fmt_pct, pageno, doc_pages, pct)

    elseif key == "chapter_page" then
        local pages_chapter = view.ui.toc:getChapterPageCount(pageno) or doc_pages
        local pages_done = (view.ui.toc:getChapterPagesDone(pageno) or 0) + 1
        return pages_done .. " / " .. pages_chapter

    elseif key == "book_author" then
        local props = view.ui.document:getProps()
        return (props and (props.authors or props.author)) or ""

    elseif key == "book_title" then
        local props = view.ui.document:getProps()
        return (props and props.title) or ""

    elseif key == "chapter_title" then
        return view.ui.toc:getTocTitleByPage(pageno) or ""

    elseif key == "battery" then
        local capacity = PowerD:getCapacity()
        if capacity then
            local icon = PowerD:getBatterySymbol(PowerD:isCharged(), PowerD:isCharging(), capacity) or ""
            return icon .. " " .. string.format("%d%%", capacity)
        end
        return ""
    end

    return ""
end

-- Fit text to width
local function getFitted(text, face, size, bold, max_pct, avail_width)
    if not text or text == "" then return "" end
    local tw = TextWidget:new{
        text = text:gsub(" ", "\u{00A0}"),
        max_width = math.floor(avail_width * max_pct * 0.01),
        face = getFontFace(face, size),
        bold = bold,
        padding = 0,
    }
    local fitted, add_ellipsis = tw:getFittedText()
    tw:free()
    if add_ellipsis then fitted = fitted .. "…" end
    return BD.auto(fitted)
end

-- Draw a bar with left, center, right content
local function drawBar(canvas, bar_x, bar_y, lstr, cstr, rstr, face, size, bold, sw, left_margin, right_margin)
    if lstr == "" and cstr == "" and rstr == "" then return end

    local f = getFontFace(face, size)
    local ltw = TextWidget:new{ text = lstr, face = f, bold = bold, padding = 0 }
    local ctw = TextWidget:new{ text = cstr, face = f, bold = bold, padding = 0 }
    local rtw = TextWidget:new{ text = rstr, face = f, bold = bold, padding = 0 }

    local lw = ltw:getSize().w
    local cw = ctw:getSize().w
    local rw = rtw:getSize().w

    local avail = sw - left_margin - right_margin

    local left_x = left_margin
    local right_x = sw - right_margin - rw
    local center_x = left_margin + (avail - cw) / 2

    if lstr ~= "" and cstr ~= "" and left_x + lw > center_x then
        center_x = left_x + lw + Screen:scaleBySize(4)
    end

    if cstr ~= "" and rstr ~= "" and center_x + cw > right_x then
        center_x = right_x - cw - Screen:scaleBySize(4)
    end

    if center_x < left_margin then
        center_x = left_margin
    end
    if center_x + cw > sw - right_margin then
        center_x = sw - right_margin - cw
    end

    if lstr ~= "" then
        ltw:paintTo(canvas, bar_x + left_x, bar_y)
    end
    if cstr ~= "" then
        ctw:paintTo(canvas, bar_x + center_x, bar_y)
    end
    if rstr ~= "" then
        rtw:paintTo(canvas, bar_x + right_x, bar_y)
    end

    ltw:free()
    ctw:free()
    rtw:free()
end

--[[
Initialize Header/Footer module
]]
function HeaderFooter.init(plugin)
    plugin_ref = plugin

    local originalPaintTo = ReaderView.paintTo

    function ReaderView:paintTo(bb, x, y)
        originalPaintTo(self, bb, x, y)

        if self.render_mode ~= nil and not cfg(S.PDF_ENABLED) then return end

        local header_enabled = cfg(S.HEADER_ENABLED)
        local footer_enabled = cfg(S.FOOTER_ENABLED)
        if not header_enabled and not footer_enabled then return end

        local page_margins = self.document:getPageMargins() or {}
        local left_margin = (page_margins.left or Size.padding.large) + cfg(S.LEFT_OFFSET)
        local right_margin = (page_margins.right or Size.padding.large) + cfg(S.RIGHT_OFFSET)
        local sw = Screen:getWidth()
        local avail_width = sw - left_margin - right_margin

        local function getItem(key)
            return getItemValue(key, self)
        end

        if header_enabled then
            local ff = cfg(S.HEADER_FONT_FACE)
            local fs = cfg(S.HEADER_FONT_SIZE)
            local bold = cfg(S.HEADER_FONT_BOLD)
            local lval = getFitted(getItem(cfg(S.TOP_LEFT)), ff, fs, bold, 48, avail_width)
            local cval = getFitted(getItem(cfg(S.TOP_CENTER)), ff, fs, bold, 48, avail_width)
            local rval = getFitted(getItem(cfg(S.TOP_RIGHT)), ff, fs, bold, 48, avail_width)
            drawBar(bb, x, y + cfg(S.HEADER_TOP_PADDING), lval, cval, rval, ff, fs, bold, sw, left_margin, right_margin)
        end

        if footer_enabled then
            local ff = cfg(S.FOOTER_FONT_FACE)
            local fs = cfg(S.FOOTER_FONT_SIZE)
            local bold = cfg(S.FOOTER_FONT_BOLD)
            local lval = getFitted(getItem(cfg(S.BOTTOM_LEFT)), ff, fs, bold, 48, avail_width)
            local cval = getFitted(getItem(cfg(S.BOTTOM_CENTER)), ff, fs, bold, 48, avail_width)
            local rval = getFitted(getItem(cfg(S.BOTTOM_RIGHT)), ff, fs, bold, 48, avail_width)

            local probe = TextWidget:new{
                text = "A",
                face = getFontFace(ff, fs),
                bold = bold,
                padding = 0,
            }
            local bar_h = probe:getSize().h
            probe:free()

            drawBar(bb, x, Screen:getHeight() - bar_h - cfg(S.FOOTER_BOTTOM_PADDING), lval, cval, rval, ff, fs, bold, sw, left_margin, right_margin)
        end
    end

    Utils.registerRefreshHandler("hf", function()
        local ReaderUI = require("apps/reader/readerui")
        if ReaderUI and ReaderUI.instance then
            UIManager:setDirty(ReaderUI.instance, "full")
        end
    end)
end

--[[
Public API: Get menu items
]]
function HeaderFooter.getMenuItems()
    local items = {}

    local function buildFontSubmenu(setting_key)
        local sub = {}
        local fonts = Utils.getFontList()
        for _, font in ipairs(fonts) do
            table.insert(sub, {
                text = font.display,
                radio = true,
                checked_func = function()
                    return cfg(setting_key) == font.name
                end,
                callback = function(touchmenu_instance)
                    setCfg(setting_key, font.name)
                    if touchmenu_instance then
                        touchmenu_instance:updateItems()
                    end
                end,
            })
        end
        return sub
    end

    -- Header sub-menu
    local header_items = {
        {
            text = _("Enable Header"),
            checked_func = function()
                return cfg(S.HEADER_ENABLED)
            end,
            callback = function(touchmenu_instance)
                setCfg(S.HEADER_ENABLED, not cfg(S.HEADER_ENABLED))
                if touchmenu_instance then
                    touchmenu_instance:updateItems()
                end
            end,
        },
        {
            text = _("Top Left"),
            sub_item_table = function()
                local sub = {}
                for _, key in ipairs(ITEM_KEYS) do
                    local k = key
                    table.insert(sub, {
                        text = ITEM_LABELS[k],
                        radio = true,
                        checked_func = function()
                            return cfg(S.TOP_LEFT) == k
                        end,
                        callback = function()
                            setCfg(S.TOP_LEFT, k)
                        end,
                    })
                end
                return sub
            end,
        },
        {
            text = _("Top Center"),
            sub_item_table = function()
                local sub = {}
                for _, key in ipairs(ITEM_KEYS) do
                    local k = key
                    table.insert(sub, {
                        text = ITEM_LABELS[k],
                        radio = true,
                        checked_func = function()
                            return cfg(S.TOP_CENTER) == k
                        end,
                        callback = function()
                            setCfg(S.TOP_CENTER, k)
                        end,
                    })
                end
                return sub
            end,
        },
        {
            text = _("Top Right"),
            sub_item_table = function()
                local sub = {}
                for _, key in ipairs(ITEM_KEYS) do
                    local k = key
                    table.insert(sub, {
                        text = ITEM_LABELS[k],
                        radio = true,
                        checked_func = function()
                            return cfg(S.TOP_RIGHT) == k
                        end,
                        callback = function()
                            setCfg(S.TOP_RIGHT, k)
                        end,
                    })
                end
                return sub
            end,
        },
        {
            text = _("Font"),
            sub_item_table = function()
                return buildFontSubmenu(S.HEADER_FONT_FACE)
            end,
        },
        {
            text_func = function()
                return T(_("Font Size: %1"), cfg(S.HEADER_FONT_SIZE))
            end,
            close_on_click = true,
            callback = function()
                local dialog
                dialog = InputDialog:new{
                    title = _("Header Font Size"),
                    input = tostring(cfg(S.HEADER_FONT_SIZE)),
                    hint = _("Enter font size (e.g. 14)"),
                    input_type = "number",
                    buttons = {
                        {
                            {
                                text = _("Cancel"),
                                callback = function()
                                    UIManager:close(dialog)
                                end,
                            },
                            {
                                text = _("OK"),
                                callback = function()
                                    local val = tonumber(dialog:getInputText())
                                    if val and val > 0 then
                                        setCfg(S.HEADER_FONT_SIZE, val)
                                    end
                                    UIManager:close(dialog)
                                end,
                            },
                        },
                    },
                }
                UIManager:show(dialog)
            end,
        },
        {
            text = _("Bold"),
            checked_func = function()
                return cfg(S.HEADER_FONT_BOLD)
            end,
            callback = function(touchmenu_instance)
                setCfg(S.HEADER_FONT_BOLD, not cfg(S.HEADER_FONT_BOLD))
                if touchmenu_instance then
                    touchmenu_instance:updateItems()
                end
            end,
        },
        {
            text_func = function()
                return T(_("Top Padding: %1"), cfg(S.HEADER_TOP_PADDING))
            end,
            close_on_click = true,
            callback = function()
                local dialog
                dialog = InputDialog:new{
                    title = _("Header Top Padding"),
                    input = tostring(cfg(S.HEADER_TOP_PADDING)),
                    hint = _("Enter padding value"),
                    input_type = "number",
                    buttons = {
                        {
                            {
                                text = _("Cancel"),
                                callback = function()
                                    UIManager:close(dialog)
                                end,
                            },
                            {
                                text = _("OK"),
                                callback = function()
                                    local val = tonumber(dialog:getInputText())
                                    if val then
                                        setCfg(S.HEADER_TOP_PADDING, val)
                                    end
                                    UIManager:close(dialog)
                                end,
                            },
                        },
                    },
                }
                UIManager:show(dialog)
            end,
        },
    }
    table.insert(items, {
        text = _("Header"),
        sub_item_table = header_items,
    })

    -- Footer sub-menu
    local footer_items = {
        {
            text = _("Enable Footer"),
            checked_func = function()
                return cfg(S.FOOTER_ENABLED)
            end,
            callback = function(touchmenu_instance)
                setCfg(S.FOOTER_ENABLED, not cfg(S.FOOTER_ENABLED))
                if touchmenu_instance then
                    touchmenu_instance:updateItems()
                end
            end,
        },
        {
            text = _("Bottom Left"),
            sub_item_table = function()
                local sub = {}
                for _, key in ipairs(ITEM_KEYS) do
                    local k = key
                    table.insert(sub, {
                        text = ITEM_LABELS[k],
                        radio = true,
                        checked_func = function()
                            return cfg(S.BOTTOM_LEFT) == k
                        end,
                        callback = function()
                            setCfg(S.BOTTOM_LEFT, k)
                        end,
                    })
                end
                return sub
            end,
        },
        {
            text = _("Bottom Center"),
            sub_item_table = function()
                local sub = {}
                for _, key in ipairs(ITEM_KEYS) do
                    local k = key
                    table.insert(sub, {
                        text = ITEM_LABELS[k],
                        radio = true,
                        checked_func = function()
                            return cfg(S.BOTTOM_CENTER) == k
                        end,
                        callback = function()
                            setCfg(S.BOTTOM_CENTER, k)
                        end,
                    })
                end
                return sub
            end,
        },
        {
            text = _("Bottom Right"),
            sub_item_table = function()
                local sub = {}
                for _, key in ipairs(ITEM_KEYS) do
                    local k = key
                    table.insert(sub, {
                        text = ITEM_LABELS[k],
                        radio = true,
                        checked_func = function()
                            return cfg(S.BOTTOM_RIGHT) == k
                        end,
                        callback = function()
                            setCfg(S.BOTTOM_RIGHT, k)
                        end,
                    })
                end
                return sub
            end,
        },
        {
            text = _("Font"),
            sub_item_table = function()
                return buildFontSubmenu(S.FOOTER_FONT_FACE)
            end,
        },
        {
            text_func = function()
                return T(_("Font Size: %1"), cfg(S.FOOTER_FONT_SIZE))
            end,
            close_on_click = true, 
            callback = function()
                local dialog
                dialog = InputDialog:new{
                    title = _("Footer Font Size"),
                    input = tostring(cfg(S.FOOTER_FONT_SIZE)),
                    hint = _("Enter font size (e.g. 14)"),
                    input_type = "number",
                    buttons = {
                        {
                            {
                                text = _("Cancel"),
                                callback = function()
                                    UIManager:close(dialog)
                                end,
                            },
                            {
                                text = _("OK"),
                                callback = function()
                                    local val = tonumber(dialog:getInputText())
                                    if val and val > 0 then
                                        setCfg(S.FOOTER_FONT_SIZE, val)
                                    end
                                    UIManager:close(dialog)
                                end,
                            },
                        },
                    },
                }
                UIManager:show(dialog)
            end,
        },
        {
            text = _("Bold"),
            checked_func = function()
                return cfg(S.FOOTER_FONT_BOLD)
            end,
            callback = function(touchmenu_instance)
                setCfg(S.FOOTER_FONT_BOLD, not cfg(S.FOOTER_FONT_BOLD))
                if touchmenu_instance then
                    touchmenu_instance:updateItems()
                end
            end,
        },
        {
            text_func = function()
                return T(_("Bottom Padding: %1"), cfg(S.FOOTER_BOTTOM_PADDING))
            end,
            close_on_click = true,
            callback = function()
                local dialog
                dialog = InputDialog:new{
                    title = _("Footer Bottom Padding"),
                    input = tostring(cfg(S.FOOTER_BOTTOM_PADDING)),
                    hint = _("Enter padding value"),
                    input_type = "number",
                    buttons = {
                        {
                            {
                                text = _("Cancel"),
                                callback = function()
                                    UIManager:close(dialog)
                                end,
                            },
                            {
                                text = _("OK"),
                                callback = function()
                                    local val = tonumber(dialog:getInputText())
                                    if val then
                                        setCfg(S.FOOTER_BOTTOM_PADDING, val)
                                    end
                                    UIManager:close(dialog)
                                end,
                            },
                        },
                    },
                }
                UIManager:show(dialog)
            end,
        },
    }
    table.insert(items, {
        text = _("Footer"),
        sub_item_table = footer_items,
    })

    -- Global settings
    local global_items = {
        {
            text_func = function()
                return T(_("Left Offset: %1"), cfg(S.LEFT_OFFSET))
            end,
            close_on_click = true,
            callback = function()
                local dialog
                dialog = InputDialog:new{
                    title = _("Left Offset"),
                    input = tostring(cfg(S.LEFT_OFFSET)),
                    hint = _("Positive moves right, negative moves left"),
                    input_type = "number",
                    buttons = {
                        {
                            {
                                text = _("Cancel"),
                                callback = function()
                                    UIManager:close(dialog)
                                end,
                            },
                            {
                                text = _("OK"),
                                callback = function()
                                    local val = tonumber(dialog:getInputText())
                                    if val then
                                        setCfg(S.LEFT_OFFSET, val)
                                    end
                                    UIManager:close(dialog)
                                end,
                            },
                        },
                    },
                }
                UIManager:show(dialog)
            end,
        },
        {
            text_func = function()
                return T(_("Right Offset: %1"), cfg(S.RIGHT_OFFSET))
            end,
            close_on_click = true, 
            callback = function()
                local dialog
                dialog = InputDialog:new{
                    title = _("Right Offset"),
                    input = tostring(cfg(S.RIGHT_OFFSET)),
                    hint = _("Positive moves left, negative moves right"),
                    input_type = "number",
                    buttons = {
                        {
                            {
                                text = _("Cancel"),
                                callback = function()
                                    UIManager:close(dialog)
                                end,
                            },
                            {
                                text = _("OK"),
                                callback = function()
                                    local val = tonumber(dialog:getInputText())
                                    if val then
                                        setCfg(S.RIGHT_OFFSET, val)
                                    end
                                    UIManager:close(dialog)
                                end,
                            },
                        },
                    },
                }
                UIManager:show(dialog)
            end,
        },
        {
            text = _("Time Format"),
            sub_item_table = {
                {
                    text = _("24-hour"),
                    radio = true,
                    checked_func = function()
                        return cfg(S.TIME_FORMAT) == "24h"
                    end,
                    callback = function()
                        setCfg(S.TIME_FORMAT, "24h")
                    end,
                },
                {
                    text = _("12-hour"),
                    radio = true,
                    checked_func = function()
                        return cfg(S.TIME_FORMAT) == "12h"
                    end,
                    callback = function()
                        setCfg(S.TIME_FORMAT, "12h")
                    end,
                },
            },
        },
        {
            text_func = function()
                return T(_("Progress Decimals: %1"), cfg(S.PROGRESS_DECIMALS))
            end,
            close_on_click = true, 
            callback = function()
                local dialog
                dialog = InputDialog:new{
                    title = _("Progress Decimals"),
                    input = tostring(cfg(S.PROGRESS_DECIMALS)),
                    hint = _("0, 1, or 2"),
                    input_type = "number",
                    buttons = {
                        {
                            {
                                text = _("Cancel"),
                                callback = function()
                                    UIManager:close(dialog)
                                end,
                            },
                            {
                                text = _("OK"),
                                callback = function()
                                    local val = tonumber(dialog:getInputText())
                                    if val and val >= 0 then
                                        setCfg(S.PROGRESS_DECIMALS, val)
                                    end
                                    UIManager:close(dialog)
                                end,
                            },
                        },
                    },
                }
                UIManager:show(dialog)
            end,
        },
        {
            text = _("Show in PDF Documents"),
            checked_func = function()
                return cfg(S.PDF_ENABLED)
            end,
            callback = function(touchmenu_instance)
                setCfg(S.PDF_ENABLED, not cfg(S.PDF_ENABLED))
                if touchmenu_instance then
                    touchmenu_instance:updateItems()
                end
            end,
        },
    }
    table.insert(items, {
        text = _("Global Settings"),
        sub_item_table = global_items,
    })

    -- Add default config menu items
    local default_items = Utils.buildDefaultMenuItems("hf", function()
        local ReaderUI = require("apps/reader/readerui")
        if ReaderUI and ReaderUI.instance then
            UIManager:setDirty(ReaderUI.instance, "full")
        end
    end)
    for _, item in ipairs(default_items) do
        table.insert(items, item)
    end

    return items
end

-- ============================================================
-- Public API: Show Settings
-- ============================================================

function HeaderFooter.showSettings()
    local items = HeaderFooter.getMenuItems()
    local self_ref = { _hf_settings_dialog = nil }

    local function getItemText(item)
        if item.text_func then
            return type(item.text_func) == "function" and (item.text_func() or "") or ""
        elseif item.text then
            return type(item.text) == "function" and (item.text() or "") or (item.text or "")
        end
        return ""
    end

    local function showMenu(title, item_table, parent_stack)
        local buttons = {}

        -- Only add QuickUI Settings button if no parent (root menu)
        if parent_stack == nil or #parent_stack == 0 then
            table.insert(buttons, {
                {
                    text = "⚙️ " .. _("QuickUI Settings"),
                    callback = function()
                        if self_ref._hf_settings_dialog then
                            UIManager:close(self_ref._hf_settings_dialog)
                            self_ref._hf_settings_dialog = nil
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
                            if self_ref._hf_settings_dialog then
                                UIManager:close(self_ref._hf_settings_dialog)
                                self_ref._hf_settings_dialog = nil
                            end
                            showMenu(_("Header & Footer"), items, nil)
                        end
                    }
                })
            end

            table.insert(buttons, {
                {
                    text = "◂ " .. _("Back"),
                    callback = function()
                        if self_ref._hf_settings_dialog then
                            UIManager:close(self_ref._hf_settings_dialog)
                            self_ref._hf_settings_dialog = nil
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
            local sub_table = item.sub_item_table
            if type(sub_table) == "function" then
                sub_table = sub_table()
            end

            if sub_table and type(sub_table) == "table" and #sub_table > 0 then
                local display_text = getItemText(item)
                table.insert(buttons, {
                    {
                        text = display_text .. " ▸",
                        callback = function()
                            if self_ref._hf_settings_dialog then
                                UIManager:close(self_ref._hf_settings_dialog)
                                self_ref._hf_settings_dialog = nil
                            end
                            local new_stack = {}
                            if parent_stack then
                                for _, v in ipairs(parent_stack) do
                                    table.insert(new_stack, v)
                                end
                            end
                            table.insert(new_stack, { title = title, items = item_table })
                            showMenu(display_text, sub_table, new_stack)
                        end
                    }
                })
            else
                local checked = item.checked_func and item.checked_func() or false
                local display_text = getItemText(item)
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

                            if item.close_on_click then
                                -- Close settings menu and do not reopen (for InputDialog popups)
                                if self_ref._hf_settings_dialog then
                                    UIManager:close(self_ref._hf_settings_dialog)
                                    self_ref._hf_settings_dialog = nil
                                end
                            else
                                -- Close and refresh the menu (for regular toggles/selections)
                                if self_ref._hf_settings_dialog then
                                    UIManager:close(self_ref._hf_settings_dialog)
                                    self_ref._hf_settings_dialog = nil
                                end
                                showMenu(title, item_table, parent_stack)
                            end
                        end
                     end
                    }
                })
            end
        end

        if self_ref._hf_settings_dialog then
            UIManager:close(self_ref._hf_settings_dialog)
            self_ref._hf_settings_dialog = nil
        end

        local dialog = ButtonDialog:new{
            title = title or _("Header & Footer"),
            title_align = "center",
            buttons = buttons,
            width = math.floor(Screen:getWidth() * 0.7),
            max_height = math.floor(Screen:getHeight() * 0.7),
        }
        self_ref._hf_settings_dialog = dialog
        UIManager:show(dialog)
    end

    showMenu(_("Header & Footer"), items, nil)
end

return HeaderFooter
