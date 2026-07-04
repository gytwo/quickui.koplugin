--[[
QuickUI - Cover Visual Enhancements Module

Make your library look clean and consistent with:
- Beautiful placeholder covers for books without covers
- Unified aspect ratios
- Rounded corners
- Badges (favorite, progress, NEW, page count, format)
- Folder cover previews (Gallery, Stack, Normal, None)
- Title and author display below covers

Original: 2-fm-cover.lua
]]

local logger = require("logger")
local _ = require("gettext")
local Blitbuffer = require("ffi/blitbuffer")
local Font = require("ui/font")
local Size = require("ui/size")
local Screen = require("device").screen
local Geom = require("ui/geometry")
local UIManager = require("ui/uimanager")
local Device = require("device")
local BD = require("ui/bidi")
local util = require("util")
local lfs = require("libs/libkoreader-lfs")
local RenderImage = require("ui/renderimage")
local filemanagerutil = require("apps/filemanager/filemanagerutil")

local CenterContainer = require("ui/widget/container/centercontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local LineWidget = require("ui/widget/linewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local AlphaContainer = require("ui/widget/container/alphacontainer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local TopContainer = require("ui/widget/container/topcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local ImageWidget = require("ui/widget/imagewidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local ButtonDialog = require("ui/widget/buttondialog")
local InputDialog = require("ui/widget/inputdialog")
local Notification = require("ui/widget/notification") 
local ConfirmBox = require("ui/widget/confirmbox") 

local Utils = require("qui_utils")

local Cover = {}

local plugin = nil

-- Cache
local _banner_cache = {}
local _rounded_corner_templates = {}
local MAX_BANNER_CACHE = 50

-- ============================================================
-- Initialization
-- ============================================================

function Cover.init(plugin_ref)
    plugin = plugin_ref

    Cover._patchMosaic()
    Cover._patchList()
    Cover._patchHideUpFolder()

    Utils.registerRefreshHandler("cover", function()
        local fm = require("apps/filemanager/filemanager").instance
        if fm and fm.file_chooser then
            fm.file_chooser:updateItems()
            UIManager:setDirty(fm.file_chooser, "full")
        end
    end)
end

-- ============================================================
-- Configuration Helpers
-- ============================================================

local function get(key)
    local config = _G.__QUICKUI_CONFIG
    if config then
        return config[key]
    end
    return nil
end

local function set(key, value)
    local config = _G.__QUICKUI_CONFIG
    if config then
        config[key] = value
        Utils.saveConfig()
    end
end

local function getBool(key)
    local val = get(key)
    if type(val) == "boolean" then return val end
    return false
end

local function setBool(key, value)
    set(key, value == true)
end

local function getString(key)
    local val = get(key)
    if type(val) == "string" then return val end
    return ""
end

local function setString(key, value)
    set(key, tostring(value))
end

local function getNumber(key)
    local val = get(key)
    if type(val) == "number" then return val end
    return 0
end

-- ============================================================
-- Refresh File Manager
-- ============================================================

local function refreshFileManager()
    local fm = require("apps/filemanager/filemanager").instance
    if fm and fm.file_chooser then
        fm.file_chooser:updateItems()
        UIManager:setDirty(fm.file_chooser, "full")
    end
end

-- ============================================================
-- Aspect Ratio
-- ============================================================

function Cover.getAspectRatio()
    local ratio_str = getString("cover_ratio")
    if ratio_str == "" then ratio_str = "3:4" end
    return Utils.parseAspectRatio(ratio_str)
end

function Cover.calcDims(max_w, max_h)
    return Utils.calcDims(max_w, max_h, getString("cover_ratio"))
end

-- ============================================================
-- Badge Helpers
-- ============================================================

local function getBadgeColor()
    local r = getNumber("cover_badge_color_r")
    local g = getNumber("cover_badge_color_g")
    local b = getNumber("cover_badge_color_b")
    if r == 0 and g == 0 and b == 0 then
        return Blitbuffer.COLOR_BLACK
    end
    return Utils.rgb(r, g, b)
end

local function getBadgeTextColor()
    local r = getNumber("cover_badge_color_r")
    local g = getNumber("cover_badge_color_g")
    local b = getNumber("cover_badge_color_b")
    if r == 0 and g == 0 and b == 0 then
        return Blitbuffer.COLOR_WHITE
    end
    return Blitbuffer.COLOR_BLACK
end

local function getBadgeScale()
    local size = getString("cover_badge_size")
    if size == "compact" then return 0.75
    elseif size == "large" then return 1.25
    elseif size == "extra_large" then return 1.5
    else return 1.0 end
end

local function getFolderConfig()
    return {
        show_spine_lines = getBool("cover_show_spine"),
        show_item_count = getBool("cover_show_itemcount"),
        show_folder_name = getBool("cover_show_foldername"),
        name_centered = getBool("cover_name_centered"),
        name_opaque = getBool("cover_name_opaque"),
        cover_mode = getString("cover_folder_mode"),
    }
end

local function isTitleVisible()
    return getBool("cover_show_title") or getBool("cover_show_author")
end

-- ============================================================
-- Generate Placeholder Cover
-- ============================================================

function Cover.genCover(filepath, target_w, target_h, no_fallback)
    local width, height = Cover.calcDims(target_w, target_h)

    local title = ""
    local authors = ""
    local ok, BookInfoManager = pcall(require, "bookinfomanager")

    if ok then
        local success, bookinfo = pcall(function()
            return BookInfoManager:getBookInfo(filepath, true)
        end)
        if success and bookinfo and not bookinfo.ignore_meta then
            title = bookinfo.title or ""
            authors = bookinfo.authors or ""
            if authors and authors:find("\n") then
                authors = authors:match("^([^\n]+)")
            end
        end
    end

    if title == "" and not no_fallback then
        local fname = filepath:match("([^/]+)$") or ""
        title = fname:gsub("%.[^%.]+$", "")
    end

    if not no_fallback then
        if title == "" then title = _("Unknown") end
        if authors == "" then authors = _("Unknown Author") end
    end

    local final_bb = Blitbuffer.new(width, height, Blitbuffer.TYPE_BBRGB32)
    local style = getString("cover_placeholder_style")
    if style == "" then style = "simple" end
    local split_y = math.floor(height * 2 / 3)
    local title_area_h = split_y - 10
    local author_area_h = height - split_y - 10
    local max_text_width = width - 16

    -- Create text widget with adjustable font size
    local function createTextWidget(text, max_w, max_h, fg_color, bg_color, bold, is_author)
        if not text or text == "" then return nil end
        local font_size
        local min_font
        if is_author then
            font_size = Utils.scaleBySize(8)
            min_font = Utils.scaleBySize(4)
        else
            font_size = Utils.scaleBySize(11)
            min_font = Utils.scaleBySize(6)
        end
        local widget = nil

        while font_size >= min_font do
            if widget then widget:free() end
            local face = Utils.getFontFace("cfont", font_size)
            widget = TextBoxWidget:new{
                text = text,
                face = face,
                width = max_w,
                alignment = "center",
                bold = bold,
                fgcolor = fg_color,
                bgcolor = bg_color,
            }
            if widget:getSize().h <= max_h then break end
            font_size = font_size - 1
        end

        if widget and widget:getSize().h > max_h then
            widget:free()
            local face = Utils.getFontFace("cfont", min_font)
            widget = TextBoxWidget:new{
                text = text,
                face = face,
                width = max_w,
                alignment = "center",
                bold = bold,
                fgcolor = fg_color,
                bgcolor = bg_color,
                height = max_h,
                height_adjust = true,
                height_overflow_show_ellipsis = true,
            }
        end

        if widget then
            widget.handleEvent = function() return false end
        end
        return widget
    end

    if style == "simple" then
        final_bb:fill(Blitbuffer.ColorRGB32(255, 255, 255, 255))
        local title_color = Blitbuffer.ColorRGB32(0, 0, 0, 255)
        local authors_color = Blitbuffer.ColorRGB32(0, 0, 0, 255)
        local bg_color = Blitbuffer.ColorRGB32(255, 255, 255, 255)

        local title_widget = createTextWidget(title, max_text_width, title_area_h, title_color, bg_color, true, false)
        if title_widget then
            local title_y = math.max(5, (split_y - title_widget:getSize().h) / 2)
            title_widget:paintTo(final_bb, math.max(0, (width - title_widget:getSize().w) / 2), title_y)
            title_widget:free()
        end

        if authors ~= "" then
            local author_widget = createTextWidget(authors, max_text_width, author_area_h, authors_color, bg_color, false, true)
            if author_widget then
                local authors_y = split_y + math.max(5, (author_area_h - author_widget:getSize().h) / 2)
                author_widget:paintTo(final_bb, math.max(0, (width - author_widget:getSize().w) / 2), authors_y)
                author_widget:free()
            end
        end
    else
        -- Gradient style
        local lighter_color = Blitbuffer.ColorRGB32(212, 220, 243, 255)
        local darker_color = Blitbuffer.ColorRGB32(130, 159, 227, 255)
        local title_color = Blitbuffer.ColorRGB32(1, 68, 142, 255)
        local authors_color = Blitbuffer.ColorRGB32(8, 51, 93, 255)

        for y = 0, split_y - 1 do
            for x = 0, width - 1 do
                final_bb:setPixel(x, y, lighter_color)
            end
        end
        for y = split_y, height - 1 do
            for x = 0, width - 1 do
                final_bb:setPixel(x, y, darker_color)
            end
        end

        local title_widget = createTextWidget(title, max_text_width, title_area_h, title_color, lighter_color, true, false)
        if title_widget then
            local title_y = math.max(5, (split_y - title_widget:getSize().h) / 2)
            title_widget:paintTo(final_bb, math.max(0, (width - title_widget:getSize().w) / 2), title_y)
            title_widget:free()
        end

        if authors ~= "" then
            local author_widget = createTextWidget(authors, max_text_width, author_area_h, authors_color, darker_color, false, true)
            if author_widget then
                local authors_y = split_y + math.max(5, (author_area_h - author_widget:getSize().h) / 2)
                author_widget:paintTo(final_bb, math.max(0, (width - author_widget:getSize().w) / 2), authors_y)
                author_widget:free()
            end
        end
    end

    return final_bb, width, height
end

-- ============================================================
-- Banner Cache
-- ============================================================

local function cleanBannerCache()
    if #_banner_cache < MAX_BANNER_CACHE then return end
    local count = 0
    for k, v in pairs(_banner_cache) do
        count = count + 1
        if count > MAX_BANNER_CACHE then
            _banner_cache[k] = nil
        end
    end
end

local function paintCornerBanner(bb, cover_left, cover_right, cover_top, cover_h,
                                span, band_thick, label, font_sz,
                                fill_color, border_color)
    local C = 0.70711
    local tw = math.ceil((span + band_thick * 2) * 1.41422)
    local th = band_thick
    if tw <= 0 or th <= 0 then return end

    local bb_type = bb:getType()
    local _fc = fill_color:getColorRGB32()
    local cache_key = string.format("%d|%d|%d|%s|%d|%d|%d|%d|%d",
        tw, th, bb_type, label, font_sz,
        _fc.r, _fc.g, _fc.b, border_color:getColor8().a)
    local tmp = _banner_cache[cache_key]

    if not tmp then
        tmp = Blitbuffer.new(tw, th, bb_type)
        if not tmp then return end

        tmp:paintRectRGB32(0, 0, tw, th, border_color)
        local bw = 1
        if bw * 2 < th then
            tmp:paintRectRGB32(0, bw, tw, th - 2 * bw, fill_color)
        end

        local inner_h = math.max(1, th - bw * 2)
        local max_w = math.floor(tw * 0.82)
        local lbl, lsz
        local fs = font_sz
        repeat
            if lbl and lbl.free then lbl:free() end
            lbl = TextWidget:new{
                text = label,
                face = Font:getFace("cfont", fs),
                bold = true,
                fgcolor = border_color,
                padding = 0,
            }
            lsz = lbl:getSize()
            if lsz.w <= max_w and lsz.h <= inner_h then break end
            fs = fs - 1
        until fs < 6
        local lx = math.max(0, math.floor((tw - lsz.w) / 2))
        local ly = math.max(0, math.floor((th - lsz.h) / 2))
        lbl:paintTo(tmp, lx, ly)
        if lbl.free then lbl:free() end

        _banner_cache[cache_key] = tmp
        cleanBannerCache()
    end

    local cx = cover_right - math.floor(span / 2)
    local cy = cover_top + math.floor(span / 2)
    local half_box = math.ceil((tw + th) * C / 2) + 1
    local bb_w = bb:getWidth()
    local bb_h = bb:getHeight()
    local tw_half = tw / 2
    local th_half = th / 2
    for dy = cy - half_box, cy + half_box do
        if dy >= cover_top and dy < cover_top + cover_h and dy >= 0 and dy < bb_h then
            local dy_rel = dy - cy
            for dx = cx - half_box, cx + half_box do
                if dx >= cover_left and dx < cover_right and dx >= 0 and dx < bb_w then
                    local dx_rel = dx - cx
                    local sx = math.floor(tw_half + (dx_rel + dy_rel) * C)
                    local sy = math.floor(th_half + (dy_rel - dx_rel) * C)
                    if sx >= 0 and sx < tw and sy >= 0 and sy < th then
                        bb:setPixel(dx, dy, tmp:getPixel(sx, sy))
                    end
                end
            end
        end
    end
end

-- ============================================================
-- Drawing Functions
-- ============================================================

local function paintCircle(bb, cx, cy, r, color)
    for row = -r, r do
        local half_w = math.floor(math.sqrt(math.max(0, r * r - row * row)))
        if half_w > 0 then
            bb:paintRectRGB32(cx - half_w, cy + row, 2 * half_w, 1, color)
        end
    end
end

local function paintPentagon(bb, bx, by, bw, bh, color)
    local rect_h = math.floor(bh * 30 / 42)
    local tip_h = bh - rect_h
    bb:paintRectRGB32(bx, by, bw, rect_h, color)
    for row = 0, tip_h - 1 do
        local frac = (row + 1) / tip_h
        local rw = math.max(2, math.floor(bw * (1 - frac)))
        local rx = bx + math.floor((bw - rw) / 2)
        bb:paintRectRGB32(rx, by + rect_h + row, rw, 1, color)
    end
end

local function paintPill(bb, bx, by, bw, bh, color)
    local r = bh / 2
    for row = 0, bh - 1 do
        local dy = math.abs(row + 0.5 - r)
        local dx = math.sqrt(math.max(0, r * r - dy * dy))
        local x0 = math.ceil(bx + r - dx)
        local x1 = math.floor(bx + bw - r + dx)
        local w = x1 - x0
        if w > 0 then
            bb:paintRectRGB32(x0, by + row, w, 1, color)
        end
    end
end

local function drawFavoriteStar(bb, cover_left, cover_top, cover_w, filepath)
    if not getBool("cover_show_favorite") then return end

    local ReadCollection = require("readcollection")
    local is_fav = ReadCollection:isFileInCollections(filepath, true)
    if not is_fav then return end

    local corner_mark_size = 20
    local badge_scale = getBadgeScale()
    local eff_size = math.floor(math.max(corner_mark_size, math.floor(cover_w * 0.14)) * badge_scale)
    local r = math.floor(eff_size * 0.45)
    local cx = cover_left + r + 4
    local cy = cover_top + r + 4
    local bg_color = getBadgeColor()
    local fg_color = getBadgeTextColor()

    paintCircle(bb, cx, cy, r + 2, Blitbuffer.COLOR_BLACK)
    paintCircle(bb, cx, cy, r, bg_color)
    local star = TextWidget:new{
        text = "\u{2606}",
        face = Font:getFace("cfont", math.floor(r * 0.9)),
        fgcolor = fg_color,
        padding = 0
    }
    local sz = star:getSize()
    star:paintTo(bb, cx - math.floor(sz.w / 2), cy - math.floor(sz.h / 2))
    star:free()
end

local function drawProgressBadge(bb, cover_left, cover_top, cover_w, percent_finished)
    if not getBool("cover_show_progress") then return end
    if not percent_finished then return end

    local pct = math.floor(100 * percent_finished)
    if pct <= 0 or pct >= 100 then return end

    local corner_mark_size = 20
    local badge_scale = getBadgeScale()
    local eff_size = math.floor(math.max(corner_mark_size, math.floor(cover_w * 0.14)) * badge_scale)
    local bw = math.floor(eff_size * 1.2)
    local bh = math.floor(eff_size * 1.1)
    local bdg_x = cover_left + cover_w - bw - math.floor(bw * 0.25)
    local bdg_y = cover_top + 2
    local bg_color = getBadgeColor()
    local fg_color = getBadgeTextColor()

    paintPentagon(bb, bdg_x - 2, bdg_y - 2, bw + 4, bh + 4, Blitbuffer.COLOR_BLACK)
    paintPentagon(bb, bdg_x, bdg_y, bw, bh, bg_color)
    local tw = TextWidget:new{
        text = pct .. "%",
        face = Font:getFace("cfont", math.max(7, math.floor(eff_size * 0.24))),
        bold = true,
        fgcolor = fg_color,
        padding = 0
    }
    local tw_sz = tw:getSize()
    local rect_h = math.floor(bh * 30 / 42)
    tw:paintTo(bb, bdg_x + math.floor((bw - tw_sz.w) / 2), bdg_y + math.floor((rect_h - tw_sz.h) / 2))
    tw:free()
end

local function drawNewBanner(bb, cover_left, cover_top, cover_w, cover_h, status)
    if not getBool("cover_show_new") then return end
    if status ~= "new" then return end

    local corner_mark_size = 20
    local badge_scale = getBadgeScale()
    local eff_size = math.floor(math.max(corner_mark_size, math.floor(cover_w * 0.14)) * badge_scale)
    local span = math.floor(eff_size * 2.5)
    local band_thick = math.floor(span * 0.35)
    local font_sz = math.max(6, math.floor(eff_size * 0.25))
    local bg_color = getBadgeColor()
    local fg_color = getBadgeTextColor()

    paintCornerBanner(bb,
        cover_left, cover_left + cover_w,
        cover_top, cover_h,
        span, band_thick, "New", font_sz,
        bg_color, fg_color)
end

local function dimFinishedBook(bb, cover_left, cover_top, cover_w, cover_h, status)
    if not getBool("cover_dim_finished") then return end
    if status ~= "complete" then return end
    bb:lightenRect(cover_left, cover_top, cover_w, cover_h, 0.4)
end

local function getPages(filepath)
    local success, result = pcall(function()
        local ok_bl, BookList = pcall(require, "ui/widget/booklist")
        if ok_bl and BookList and BookList.getBookInfo then
            local bi = BookList.getBookInfo(filepath)
            if bi and bi.pages and bi.pages > 0 then
                return bi.pages
            end
        end

        local ok_bim, BookInfoManager = pcall(require, "bookinfomanager")
        if ok_bim and BookInfoManager then
            local bookinfo = BookInfoManager:getBookInfo(filepath, false)
            if bookinfo and bookinfo.pages and bookinfo.pages > 0 then
                return bookinfo.pages
            end
        end
        return nil
    end)

    if success then
        return result
    else
        return nil
    end
end

local function formatPageCount(pages)
    if pages >= 1000000 then
        return string.format("%.1fM", pages / 1000000)
    elseif pages >= 1000 then
        return string.format("%.1fK", pages / 1000)
    end
    return tostring(pages)
end

local function drawPageCountBadge(bb, cover_left, cover_top, cover_w, cover_h, filepath)
    if not getBool("cover_show_pagecount") then return end

    local pages = getPages(filepath)
    if not pages or pages <= 0 then return end

    local corner_mark_size = 20
    local badge_scale = getBadgeScale()
    local eff_size = math.floor(math.max(corner_mark_size, math.floor(cover_w * 0.14)) * badge_scale)
    local font_size = math.max(7, math.floor(eff_size * 0.24))
    local page_str = formatPageCount(pages)

    local bg_color = getBadgeColor()
    local fg_color = getBadgeTextColor()

    local tw = TextWidget:new{
        text = page_str,
        face = Font:getFace("cfont", font_size),
        bold = true,
        fgcolor = fg_color,
        padding = 0,
    }
    local tw_sz = tw:getSize()
    local ph = math.floor(eff_size * 0.85)
    local h_pad = math.floor(eff_size * 0.15)
    local pw = tw_sz.w + 2 * h_pad
    local inset = 4
    local bx = cover_left + inset
    local by = cover_top + cover_h - ph - inset

    paintPill(bb, bx - 2, by - 2, pw + 4, ph + 4, Blitbuffer.COLOR_BLACK)
    paintPill(bb, bx, by, pw, ph, bg_color)
    tw:paintTo(bb, bx + math.floor((pw - tw_sz.w) / 2), by + math.floor((ph - tw_sz.h) / 2))
    tw:free()
end

local function drawFormatBadge(bb, cover_left, cover_top, cover_w, cover_h, filepath)
    if not getBool("cover_show_format") then return end

    local ext = filepath:match("%.([^%.]+)$")
    if not ext then return end

    ext = ext:upper()
    local format_map = {
        EPUB = "EPUB", PDF = "PDF", DJVU = "DJVU",
        CBZ = "CBZ", CBR = "CBR", MOBI = "MOBI",
        AZW3 = "AZW3", FB2 = "FB2", TXT = "TXT",
        HTML = "HTML", CHM = "CHM", RTF = "RTF",
    }
    local display_text = format_map[ext] or ext

    local corner_mark_size = 20
    local badge_scale = getBadgeScale()
    local eff_size = math.floor(math.max(corner_mark_size, math.floor(cover_w * 0.14)) * badge_scale)
    local font_size = math.max(7, math.floor(eff_size * 0.24))

    local tw = TextWidget:new{
        text = display_text,
        face = Font:getFace("cfont", font_size),
        bold = true,
        fgcolor = getBadgeTextColor(),
        padding = 0,
    }
    local tw_sz = tw:getSize()

    local bg_pad_h = math.floor(eff_size * 0.15)
    local bg_pad_v = math.floor(eff_size * 0.1)
    local bg_w = tw_sz.w + bg_pad_h * 2
    local bg_h = tw_sz.h + bg_pad_v * 2
    local radius = math.floor(bg_h / 2)

    local inset_x = math.floor(eff_size * 0.2)
    local inset_y = math.floor(eff_size * 0.2)
    local bx = cover_left + cover_w - bg_w - inset_x
    local by = cover_top + cover_h - bg_h - inset_y

    local bg_color = getBadgeColor()

    local border_offset = 2
    bb:paintRoundedRect(bx - border_offset, by - border_offset,
        bg_w + border_offset * 2, bg_h + border_offset * 2,
        Blitbuffer.COLOR_BLACK, radius + border_offset)

    bb:paintRoundedRect(bx, by, bg_w, bg_h, bg_color, radius)

    tw:paintTo(bb, bx + bg_pad_h, by + bg_pad_v)
    tw:free()
end

-- ============================================================
-- Rounded Corners
-- ============================================================

local function getRoundedCornerTemplate(r, border_size, border_color_key)
    local cache_key = string.format("%d|%d|%s", r, border_size, tostring(border_color_key))
    local template = _rounded_corner_templates[cache_key]

    if not template then
        template = {}
        for j = 0, r - 1 do
            local inner = math.sqrt(r * r - (r - j) * (r - j))
            local cut = math.ceil(r - inner)
            if cut > 0 then
                template[j] = cut
            end
        end

        local border_pixels = {}
        for j = 0, r - 1 do
            for c = 0, r - 1 do
                local dx = r - c - 0.5
                local dy = r - j - 0.5
                local dist = math.sqrt(dx * dx + dy * dy)
                if dist >= (r - border_size) and dist <= r then
                    if not border_pixels[j] then border_pixels[j] = {} end
                    border_pixels[j][c] = true
                end
            end
        end
        template.border_pixels = border_pixels
        _rounded_corner_templates[cache_key] = template
    end

    return template
end

local function applyRoundedCornersToCover(bb, cover_frame)
    if not getBool("cover_rounded_corners") then
        return
    end

    if not cover_frame or not cover_frame.dimen then
        return
    end

    local cover_left = cover_frame.dimen.x
    local cover_top = cover_frame.dimen.y
    local cover_w = cover_frame.dimen.w
    local cover_h = cover_frame.dimen.h
    local border_size = cover_frame.bordersize or 0
    local border_color = cover_frame.bordercolor or cover_frame.color or Blitbuffer.COLOR_BLACK

    local r = Screen:scaleBySize(8)
    local template = getRoundedCornerTemplate(r, border_size, tostring(border_color:getColorRGB32()))

    for j = 0, r - 1 do
        local cut = template[j]
        if cut and cut > 0 then
            bb:paintRect(cover_left, cover_top + j, cut, 1, Blitbuffer.COLOR_WHITE)
            bb:paintRect(cover_left + cover_w - cut, cover_top + j, cut, 1, Blitbuffer.COLOR_WHITE)
            bb:paintRect(cover_left, cover_top + cover_h - 1 - j, cut, 1, Blitbuffer.COLOR_WHITE)
            bb:paintRect(cover_left + cover_w - cut, cover_top + cover_h - 1 - j, cut, 1, Blitbuffer.COLOR_WHITE)
        end
    end

    if border_size > 0 then
        local border_pixels = template.border_pixels
        for j = 0, r - 1 do
            local row_pixels = border_pixels[j]
            if row_pixels then
                for c = 0, r - 1 do
                    if row_pixels[c] then
                        bb:paintRect(cover_left + c, cover_top + j, 1, 1, border_color)
                        bb:paintRect(cover_left + cover_w - 1 - c, cover_top + j, 1, 1, border_color)
                        bb:paintRect(cover_left + c, cover_top + cover_h - 1 - j, 1, 1, border_color)
                        bb:paintRect(cover_left + cover_w - 1 - c, cover_top + cover_h - 1 - j, 1, 1, border_color)
                    end
                end
            end
        end
    end
end

-- ============================================================
-- Folder Cover Drawing
-- ============================================================

local function coverBg()
    local ok, Device = pcall(require, "device")
    if ok and not Device:hasEinkScreen() then
        return Blitbuffer.COLOR_WHITE
    end
    return Blitbuffer.COLOR_LIGHT_GRAY
end

local function scaleCover(cover_bb, src_w, src_h, target_w, target_h)
    local scaled_bb = cover_bb:scale(target_w, target_h)
    return scaled_bb, target_w, target_h
end

local function drawGallery(covers, portrait_w, portrait_h, border)
    local sep = 1
    local half_w = math.floor((portrait_w - sep) / 2)
    local half_w2 = portrait_w - sep - half_w
    local half_h = math.floor((portrait_h - sep) / 2)
    local half_h2 = portrait_h - sep - half_h
    local cell_dims = {
        { w = half_w,  h = half_h  },
        { w = half_w2, h = half_h  },
        { w = half_w,  h = half_h2 },
        { w = half_w2, h = half_h2 },
    }

    local cells = {}
    for i = 1, 4 do
        local c = covers[i]
        local cd = cell_dims[i]
        if c then
            cells[i] = CenterContainer:new{
                dimen = { w = cd.w, h = cd.h },
                ImageWidget:new{
                    image = c.data,
                    width = cd.w,
                    height = cd.h,
                },
            }
        else
            cells[i] = CenterContainer:new{
                dimen = { w = cd.w, h = cd.h },
                VerticalSpan:new{ width = 1 },
            }
        end
    end

    local bg = coverBg()
    local dimen = { w = portrait_w + 2 * border, h = portrait_h + 2 * border }

    return FrameContainer:new{
        padding = 0,
        bordersize = border,
        width = dimen.w,
        height = dimen.h,
        background = bg,
        CenterContainer:new{
            dimen = { w = portrait_w, h = portrait_h },
            VerticalGroup:new{
                HorizontalGroup:new{
                    cells[1],
                    LineWidget:new{
                        background = Blitbuffer.COLOR_WHITE,
                        dimen = { w = sep, h = half_h },
                    },
                    cells[2],
                },
                LineWidget:new{
                    background = Blitbuffer.COLOR_WHITE,
                    dimen = { w = portrait_w, h = sep },
                },
                HorizontalGroup:new{
                    cells[3],
                    LineWidget:new{
                        background = Blitbuffer.COLOR_WHITE,
                        dimen = { w = sep, h = half_h2 },
                    },
                    cells[4],
                },
            },
        },
        overlap_align = "center",
    }
end

local function drawStack(covers, portrait_w, portrait_h, border)
    local stack_count = #covers
    local dimen = { w = portrait_w + 2 * border, h = portrait_h + 2 * border }
    local border_color = Blitbuffer.ColorRGB32(128, 128, 128, 255)

    if stack_count == 0 then
        return FrameContainer:new{
            padding = 0,
            bordersize = border,
            width = dimen.w,
            height = dimen.h,
            background = Blitbuffer.COLOR_WHITE,
            CenterContainer:new{
                dimen = { w = portrait_w, h = portrait_h },
                VerticalSpan:new{ width = 1 },
            },
            overlap_align = "center",
        }
    end

    local book_width = math.floor(portrait_w * 0.72)
    local book_height = math.floor(book_width * (portrait_h / portrait_w))
    local base_x = math.floor((portrait_w - book_width) / 2)
    local base_y = math.floor((portrait_h - book_height) / 2)
    local step_x = math.floor(base_x / 2)
    local step_y = math.floor(base_y / 2)

    local n = math.min(stack_count, 4)
    local offsets

    if n == 1 then
        offsets = { { x = 0, y = 0 } }
    elseif n == 2 then
        offsets = { { x = step_x, y = -step_y }, { x = -step_x, y = step_y } }
    elseif n == 3 then
        offsets = { { x = step_x, y = -step_y }, { x = 0, y = 0 }, { x = -step_x, y = step_y } }
    else
        local s3x = math.floor(step_x / 3)
        local s3y = math.floor(step_y / 3)
        offsets = {
            { x = step_x, y = -step_y },
            { x = s3x,    y = -s3y    },
            { x = -s3x,   y = s3y     },
            { x = -step_x, y = step_y },
        }
    end

    local children = {}
    for i = n, 1, -1 do
        local cover = covers[i]
        local off = offsets[n - i + 1] or { x = 0, y = 0 }
        local scaled_bb, sw, sh = scaleCover(cover.data, cover.w, cover.h, book_width, book_height)

        for x = 0, sw - 1 do
            scaled_bb:setPixel(x, 0, border_color)
            scaled_bb:setPixel(x, sh - 1, border_color)
        end
        for y = 0, sh - 1 do
            scaled_bb:setPixel(0, y, border_color)
            scaled_bb:setPixel(sw - 1, y, border_color)
        end

        table.insert(children, ImageWidget:new{
            image = scaled_bb,
            image_disposable = true,
            width = sw,
            height = sh,
            overlap_offset = { base_x + off.x, base_y + off.y },
        })
    end

    return FrameContainer:new{
        padding = 0,
        bordersize = border,
        width = dimen.w,
        height = dimen.h,
        background = Blitbuffer.COLOR_WHITE,
        CenterContainer:new{
            dimen = { w = portrait_w, h = portrait_h },
            OverlapGroup:new{
                dimen = { w = portrait_w, h = portrait_h },
                allow_mirroring = false,
                table.unpack(children),
            },
        },
        overlap_align = "center",
    }
end

local function drawSingle(cover_data, portrait_w, portrait_h, border)
    local bg = Blitbuffer.COLOR_LIGHT_GRAY
    local dimen = { w = portrait_w + 2 * border, h = portrait_h + 2 * border }

    return FrameContainer:new{
        padding = 0,
        bordersize = border,
        width = dimen.w,
        height = dimen.h,
        background = bg,
        CenterContainer:new{
            dimen = { w = portrait_w, h = portrait_h },
            ImageWidget:new{
                image = cover_data,
                width = portrait_w,
                height = portrait_h,
            },
        },
        overlap_align = "center",
    }
end

local function drawNoImage(folder_name, portrait_w, portrait_h, border)
    local bg = Blitbuffer.COLOR_WHITE
    local fg = Blitbuffer.COLOR_BLACK
    local final_bb = Blitbuffer.new(portrait_w, portrait_h, Blitbuffer.TYPE_BBRGB32)
    final_bb:fill(bg)

    local font_size = Utils.scaleBySize(11)
    local min_font = Utils.scaleBySize(4)
    local text_widget = nil

    while font_size >= min_font do
        if text_widget then text_widget:free() end
        local face = Utils.getFontFace("cfont", font_size)
        text_widget = TextBoxWidget:new{
            text = folder_name,
            face = face,
            width = portrait_w - 16,
            alignment = "center",
            bold = true,
            fgcolor = fg,
            bgcolor = bg,
        }
        if text_widget:getSize().h <= portrait_h - 10 then
            break
        end
        font_size = font_size - 1
    end

    text_widget.handleEvent = function() return false end

    if text_widget:getSize().h > portrait_h - 10 then
        text_widget:free()
        local face = Utils.getFontFace("cfont", min_font)
        text_widget = TextBoxWidget:new{
            text = folder_name,
            face = face,
            width = portrait_w - 16,
            alignment = "center",
            bold = true,
            fgcolor = fg,
            bgcolor = bg,
            height = portrait_h - 10,
            height_adjust = true,
            height_overflow_show_ellipsis = true,
        }
        text_widget.handleEvent = function() return false end
    end

    local y = (portrait_h - text_widget:getSize().h) / 2
    text_widget:paintTo(final_bb, (portrait_w - text_widget:getSize().w) / 2, y)
    text_widget:free()

    local dimen = { w = portrait_w + 2 * border, h = portrait_h + 2 * border }

    return FrameContainer:new{
        padding = 0,
        bordersize = border,
        width = dimen.w,
        height = dimen.h,
        background = bg,
        CenterContainer:new{
            dimen = { w = portrait_w, h = portrait_h },
            ImageWidget:new{
                image = final_bb,
                image_disposable = true,
                width = portrait_w,
                height = portrait_h,
                original_in_nightmode = false,
            },
        },
        overlap_align = "center",
    }
end

-- ============================================================
-- Title and Author Drawing (below cover)
-- ============================================================

local TITLE_FONT = Utils.scaleBySize(11)
local AUTHOR_FONT = Utils.scaleBySize(9)
local TITLE_PAD = Screen:scaleBySize(3)
local TITLE_PAD_H = Screen:scaleBySize(6)

local function drawTitleAndAuthor(bb, cover_left, cover_w, cover_top, cover_h, filepath, y_offset, max_bottom, show_title, show_author, is_folder)
    local ok_bim, BookInfoManager = pcall(require, "bookinfomanager")

    local text_y = cover_top + cover_h + TITLE_PAD + (y_offset or 0)
    local total_available = max_bottom - text_y
    if total_available <= 0 then return end

    local title = nil
    local authors = nil

    if is_folder then
        title = filepath
    else
        if ok_bim then
            local success, bookinfo = pcall(function()
                return BookInfoManager:getBookInfo(filepath, true)
            end)
            if success and bookinfo and not bookinfo.ignore_meta then
                title = bookinfo.title
                authors = bookinfo.authors
                if authors and authors:find("\n") then
                    authors = authors:match("^([^\n]+)")
                end
            end
        end

        if (not title or title == "") and show_title then
            local fname = filepath:match("([^/]+)$") or ""
            title = fname:gsub("%.[^%.]+$", "")
        end
    end

    local title_font_sizes = {14, 13, 12, 11, 10}
    local author_font_sizes = {13, 12, 11, 10, 9}

    local tw = nil
    local aw = nil
    local title_h = 0
    local author_h = 0

    if show_title and not show_author and title and title ~= "" then
        for _, fs in ipairs(title_font_sizes) do
            if tw then tw:free() end
            local face = Utils.getFontFace("cfont", fs)
            tw = TextWidget:new{
                text = BD.auto(title),
                face = face,
                bold = true,
                fgcolor = Blitbuffer.COLOR_BLACK,
                padding = 0,
                max_width = cover_w - 2 * TITLE_PAD_H,
                truncate_with_ellipsis = true,
            }
            title_h = tw:getSize().h
            if title_h <= total_available then
                break
            end
        end
    end

    if not is_folder and not show_title and show_author and authors and authors ~= "" then
        for _, fs in ipairs(author_font_sizes) do
            if aw then aw:free() end
            local face = Utils.getFontFace("cfont", fs)
            aw = TextWidget:new{
                text = BD.auto(authors),
                face = face,
                bold = false,
                fgcolor = Blitbuffer.ColorRGB32(96, 96, 96, 255),
                padding = 0,
                max_width = cover_w - 2 * TITLE_PAD_H,
                truncate_with_ellipsis = true,
            }
            author_h = aw:getSize().h
            if author_h <= total_available then
                break
            end
        end
    end

    if not is_folder and show_title and show_author then
        if authors and authors ~= "" then
            local title_min_fs = title_font_sizes[#title_font_sizes]
            local author_min_fs = author_font_sizes[#author_font_sizes]

            local title_face_min = Utils.getFontFace("cfont", title_min_fs)
            local tw_min = TextWidget:new{
                text = BD.auto(title),
                face = title_face_min,
                bold = true,
                fgcolor = Blitbuffer.COLOR_BLACK,
                padding = 0,
                max_width = cover_w - 2 * TITLE_PAD_H,
                truncate_with_ellipsis = true,
            }
            local title_min_h = tw_min:getSize().h
            tw_min:free()

            local author_face_min = Utils.getFontFace("cfont", author_min_fs)
            local aw_min = TextWidget:new{
                text = BD.auto(authors),
                face = author_face_min,
                bold = false,
                fgcolor = Blitbuffer.ColorRGB32(96, 96, 96, 255),
                padding = 0,
                max_width = cover_w - 2 * TITLE_PAD_H,
                truncate_with_ellipsis = true,
            }
            local author_min_h = aw_min:getSize().h
            aw_min:free()

            if title_min_h + author_min_h + 2 <= total_available then
                local current_title_fs = title_min_fs
                local current_author_fs = author_min_fs
                local current_title_h = title_min_h
                local current_author_h = author_min_h

                local function get_title_h(fs)
                    local face = Utils.getFontFace("cfont", fs)
                    local w = TextWidget:new{
                        text = BD.auto(title),
                        face = face,
                        bold = true,
                        fgcolor = Blitbuffer.COLOR_BLACK,
                        padding = 0,
                        max_width = cover_w - 2 * TITLE_PAD_H,
                        truncate_with_ellipsis = true,
                    }
                    local h = w:getSize().h
                    w:free()
                    return h
                end

                local function get_author_h(fs)
                    local face = Utils.getFontFace("cfont", fs)
                    local w = TextWidget:new{
                        text = BD.auto(authors),
                        face = face,
                        bold = false,
                        fgcolor = Blitbuffer.ColorRGB32(96, 96, 96, 255),
                        padding = 0,
                        max_width = cover_w - 2 * TITLE_PAD_H,
                        truncate_with_ellipsis = true,
                    }
                    local h = w:getSize().h
                    w:free()
                    return h
                end

                local title_idx = 1
                for i, fs in ipairs(title_font_sizes) do
                    if fs == current_title_fs then
                        title_idx = i
                        break
                    end
                end

                local author_idx = 1
                for i, fs in ipairs(author_font_sizes) do
                    if fs == current_author_fs then
                        author_idx = i
                        break
                    end
                end

                while true do
                    local changed = false

                    if title_idx > 1 then
                        local next_title_fs = title_font_sizes[title_idx - 1]
                        local next_title_h = get_title_h(next_title_fs)
                        if current_title_h - current_title_fs + next_title_fs + current_author_h + 2 <= total_available then
                            title_idx = title_idx - 1
                            current_title_fs = next_title_fs
                            current_title_h = next_title_h
                            changed = true
                        end
                    end

                    if author_idx > 1 then
                        local next_author_fs = author_font_sizes[author_idx - 1]
                        local next_author_h = get_author_h(next_author_fs)
                        if current_title_h + current_author_h - current_author_fs + next_author_fs + 2 <= total_available then
                            author_idx = author_idx - 1
                            current_author_fs = next_author_fs
                            current_author_h = next_author_h
                            changed = true
                        end
                    end

                    if not changed then
                        break
                    end
                end

                local title_face = Utils.getFontFace("cfont", current_title_fs)
                tw = TextWidget:new{
                    text = BD.auto(title),
                    face = title_face,
                    bold = true,
                    fgcolor = Blitbuffer.COLOR_BLACK,
                    padding = 0,
                    max_width = cover_w - 2 * TITLE_PAD_H,
                    truncate_with_ellipsis = true,
                }
                title_h = tw:getSize().h

                local author_face = Utils.getFontFace("cfont", current_author_fs)
                aw = TextWidget:new{
                    text = BD.auto(authors),
                    face = author_face,
                    bold = false,
                    fgcolor = Blitbuffer.ColorRGB32(96, 96, 96, 255),
                    padding = 0,
                    max_width = cover_w - 2 * TITLE_PAD_H,
                    truncate_with_ellipsis = true,
                }
                author_h = aw:getSize().h
            else
                for _, fs in ipairs(title_font_sizes) do
                    if tw then tw:free() end
                    local face = Utils.getFontFace("cfont", fs)
                    tw = TextWidget:new{
                        text = BD.auto(title),
                        face = face,
                        bold = true,
                        fgcolor = Blitbuffer.COLOR_BLACK,
                        padding = 0,
                        max_width = cover_w - 2 * TITLE_PAD_H,
                        truncate_with_ellipsis = true,
                    }
                    title_h = tw:getSize().h
                    if title_h <= total_available then
                        break
                    end
                end
                aw = nil
            end
        else
            if title and title ~= "" then
                for _, fs in ipairs(title_font_sizes) do
                    if tw then tw:free() end
                    local face = Utils.getFontFace("cfont", fs)
                    tw = TextWidget:new{
                        text = BD.auto(title),
                        face = face,
                        bold = true,
                        fgcolor = Blitbuffer.COLOR_BLACK,
                        padding = 0,
                        max_width = cover_w - 2 * TITLE_PAD_H,
                        truncate_with_ellipsis = true,
                    }
                    title_h = tw:getSize().h
                    if title_h <= total_available then
                        break
                    end
                end
            end
            aw = nil
        end
    end

    if tw then
        local sz = tw:getSize()
        tw:paintTo(bb, cover_left + math.floor((cover_w - sz.w) / 2), text_y)
        tw:free()
    end

    if aw then
        local author_y = text_y + title_h + 2
        local sz_a = aw:getSize()
        aw:paintTo(bb, cover_left + math.floor((cover_w - sz_a.w) / 2), author_y)
        aw:free()
    end
end

-- ============================================================
-- Folder Name Banner (on cover)
-- ============================================================

local function drawFolderNameOnCover(folder_name, portrait_w, portrait_h, cfg)
    local border = 1
    local dimen = { w = portrait_w + 2 * border, h = portrait_h + 2 * border }

    local directory = TextBoxWidget:new{
        text = BD.directory(folder_name),
        face = Utils.getFontFace("cfont", Utils.scaleBySize(8)),
        width = portrait_w,
        alignment = "center",
        bold = true,
    }

    local NameContainer = cfg.name_centered and CenterContainer or BottomContainer

    local name_frame = FrameContainer:new{
        padding = 0,
        bordersize = border,
        background = Blitbuffer.COLOR_WHITE,
        directory,
    }

    local name_widget
    if cfg.name_opaque then
        name_widget = NameContainer:new{
            dimen = dimen,
            name_frame,
            overlap_align = "center",
        }
    else
        name_widget = NameContainer:new{
            dimen = dimen,
            AlphaContainer:new{ alpha = 0.75, name_frame },
            overlap_align = "center",
        }
    end

    return name_widget
end

-- ============================================================
-- Spine Lines
-- ============================================================

local FolderEdge = {
    thick = Screen:scaleBySize(2.5),
    margin = Size.line.medium,
    color = Blitbuffer.COLOR_GRAY_4,
    width = 0.97,
}

local function drawSpineLinesOnCover(portrait_w, portrait_h, border, use_top_lines, centered_top, dimen_w, dimen_h, self_width)
    local line_inset = 0
    local spine_gap = Screen:scaleBySize(9)

    if use_top_lines then
        local top_h = 2 * (FolderEdge.thick + FolderEdge.margin)
        local line1_w = math.max(0, math.floor(dimen_w * (FolderEdge.width ^ 2)) - 2 * line_inset)
        local line2_w = math.max(0, math.floor(dimen_w * FolderEdge.width) - 2 * line_inset)
        return TopContainer:new{
            dimen = { w = self_width, h = portrait_h + 2 * border },
            VerticalGroup:new{
                VerticalSpan:new{ width = centered_top - top_h },
                CenterContainer:new{
                    dimen = { w = self_width, h = top_h },
                    VerticalGroup:new{
                        LineWidget:new{
                            background = FolderEdge.color,
                            dimen = { w = line1_w, h = FolderEdge.thick },
                        },
                        VerticalSpan:new{ width = FolderEdge.margin },
                        LineWidget:new{
                            background = FolderEdge.color,
                            dimen = { w = line2_w, h = FolderEdge.thick },
                        },
                    },
                },
            },
        }
    else
        local spine_x = math.max(0, math.floor((self_width - dimen_w) / 2))
        local line1_h = math.max(0, math.floor(dimen_h * (FolderEdge.width ^ 2)) - 2 * line_inset)
        local line2_h = math.max(0, math.floor(dimen_h * FolderEdge.width) - 2 * line_inset)
        return LeftContainer:new{
            dimen = { w = self_width, h = portrait_h + 2 * border },
            HorizontalGroup:new{
                HorizontalSpan:new{ width = math.max(0, spine_x - spine_gap) },
                CenterContainer:new{
                    dimen = { w = FolderEdge.thick, h = portrait_h + 2 * border },
                    LineWidget:new{
                        background = FolderEdge.color,
                        dimen = { w = FolderEdge.thick, h = line1_h },
                    },
                },
                HorizontalSpan:new{ width = FolderEdge.margin },
                CenterContainer:new{
                    dimen = { w = FolderEdge.thick, h = portrait_h + 2 * border },
                    LineWidget:new{
                        background = FolderEdge.color,
                        dimen = { w = FolderEdge.thick, h = line2_h },
                    },
                },
            },
        }
    end
end

-- ============================================================
-- Collect Covers (for folders)
-- ============================================================

local function collectCovers(dir_path, max_covers, target_w, target_h)
    local covers = {}
    local ok, BookInfoManager = pcall(require, "bookinfomanager")
    if not ok then return covers end

    local doc_exts = { epub=1, pdf=1, djvu=1, cbz=1, cbr=1, mobi=1, azw3=1, fb2=1, txt=1, rtf=1, html=1, chm=1, zip=1, kpub=1, epub3=1 }

    local ok2, iter, dir_obj = pcall(lfs.dir, dir_path)
    if not ok2 then return covers end

    local files = {}
    for f in iter, dir_obj do
        if f:sub(1,1) ~= "." then
            local ext = (f:match("%.([^%.]+)$") or ""):lower()
            if doc_exts[ext] then
                local fullpath = dir_path .. "/" .. f
                local attr = lfs.attributes(fullpath)
                table.insert(files, {
                    name = f,
                    path = fullpath,
                    modification = attr and attr.modification or 0,
                    access = attr and attr.access or 0,
                })
            end
        end
    end

    local G = rawget(_G, "G_reader_settings")
    local collate = G and G:readSetting("collate") or "strcoll"
    local reverse = G and G:isTrue("reverse_collate") or false

    if collate == "access" or collate == "modification" or collate == "creation" then
        local time_field = collate
        if time_field == "creation" then time_field = "modification" end
        table.sort(files, function(a, b)
            if a[time_field] == b[time_field] then
                return a.name:lower() < b.name:lower()
            end
            if reverse then
                return a[time_field] < b[time_field]
            else
                return a[time_field] > b[time_field]
            end
        end)
    else
        table.sort(files, function(a, b)
            if reverse then
                return a.name:lower() > b.name:lower()
            else
                return a.name:lower() < b.name:lower()
            end
        end)
    end

    for i = 1, math.min(#files, max_covers) do
        local f = files[i]
        local success, bookinfo = pcall(function()
            return BookInfoManager:getBookInfo(f.path, true)
        end)
        if success and bookinfo and bookinfo.cover_bb and bookinfo.has_cover and bookinfo.cover_fetched then
            local scaled_bb = bookinfo.cover_bb:scale(target_w, target_h)
            covers[#covers + 1] = { data = scaled_bb, w = target_w, h = target_h }
        else
            local cover_bb, pw, ph = Cover.genCover(f.path, target_w, target_h)
            covers[#covers + 1] = { data = cover_bb, w = pw, h = ph }
        end
    end

    return covers
end

-- ============================================================
-- Load Explicit Covers (cover1.jpg, cover2.jpg, etc.)
-- ============================================================

local function loadExplicitCovers(path)
    local EXTS = { ".jpg", ".jpeg", ".png", ".webp", ".gif" }

    local function findAny(dir, stem)
        for _i, ext in ipairs(EXTS) do
            local f = dir .. "/" .. stem .. ext
            if Utils.fileExists(f) then return f end
        end
        return nil
    end

    local cover_files = {}
    for i = 1, 4 do
        local f = findAny(path, "cover" .. (i == 1 and "" or i))
        if f then
            table.insert(cover_files, f)
        end
    end

    if #cover_files == 0 then
        return nil
    end

    table.sort(cover_files, function(a, b)
        local num_a = a:match("cover(%d*)")
        local num_b = b:match("cover(%d*)")
        num_a = num_a == "" and 0 or tonumber(num_a) or 999
        num_b = num_b == "" and 0 or tonumber(num_b) or 999
        return num_a < num_b
    end)

    local mode = getString("cover_folder_mode")
    local max_count = (mode == "gallery" or mode == "stack") and 4 or 1
    local result = {}
    for i = 1, math.min(#cover_files, max_count) do
        local ok, bb = pcall(function()
            return RenderImage:renderImageFile(cover_files[i], false)
        end)
        if ok and bb then
            table.insert(result, { data = bb, w = bb:getWidth(), h = bb:getHeight() })
        end
    end

    return #result > 0 and result or nil
end

-- ============================================================
-- Get Folder File Count
-- ============================================================

local function getFolderFileCount(dir_path)
    local count = 0
    local doc_exts = { epub=1, pdf=1, djvu=1, cbz=1, cbr=1, mobi=1, azw3=1, fb2=1, txt=1 }
    local ok, iter, dir_obj = pcall(lfs.dir, dir_path)
    if ok then
        for f in iter, dir_obj do
            if f:sub(1,1) ~= "." then
                local ext = (f:match("%.([^%.]+)$") or ""):lower()
                if doc_exts[ext] then
                    count = count + 1
                end
            end
        end
    end
    return count
end

-- ============================================================
-- Mosaic Mode Patch
-- ============================================================

function Cover._patchMosaic()
    local MosaicMenu = require("mosaicmenu")
    local MosaicMenuItem = Utils.getUpvalue(MosaicMenu._updateItemsBuildUI, "MosaicMenuItem")

    if not MosaicMenuItem then
        logger.warn("QuickUI Cover: Cannot get MosaicMenuItem")
        return
    end

    if MosaicMenuItem._quickui_mosaic_patched then
        return
    end
    MosaicMenuItem._quickui_mosaic_patched = true

    local orig_update = MosaicMenuItem.update
    local orig_paintTo = MosaicMenuItem.paintTo
    local orig_init = MosaicMenuItem.init
    local orig_onFocus = MosaicMenuItem.onFocus
    local orig_onUnfocus = MosaicMenuItem.onUnfocus

    local UNDERLINE_RESERVE = 0
    local max_img_w, max_img_h

    local StretchingImageWidget = ImageWidget:extend({})

    StretchingImageWidget.init = function(self)
        if ImageWidget.init then
            ImageWidget.init(self)
        end
        if not max_img_w or not max_img_h then
            return
        end

        local aspect_ratio = Cover.getAspectRatio()
        local target_h = max_img_h
        local target_w = math.floor(target_h * aspect_ratio)
        if target_w > max_img_w then
            target_w = max_img_w
            target_h = math.floor(target_w / aspect_ratio)
        end

        self.width = target_w
        self.height = target_h
        self.keep_aspect_ratio = false
        self.scale_factor = nil
    end

    StretchingImageWidget.free = function(self)
        if self.image and self.image_disposable then
            self.image = nil
        end
        if ImageWidget.free then
            ImageWidget.free(self)
        end
    end

    function MosaicMenuItem:init()
        if self.width and self.height then
            local border = Size.border.thin
            max_img_w = self.width - 2 * border

            local UNIT_STRIP = 40
            local title_visible = getBool("cover_show_title")
            local author_visible = getBool("cover_show_author")

            local strip_h = 0
            if title_visible and author_visible then
                strip_h = UNIT_STRIP * 3
            elseif title_visible or author_visible then
                strip_h = UNIT_STRIP * 2
            end

            self._quickui_strip_h = strip_h

            if title_visible or author_visible then
                max_img_h = self.height - 2 * border - UNDERLINE_RESERVE - self._quickui_strip_h
            else
                max_img_h = self.height - 2 * border - UNDERLINE_RESERVE
            end
        end

        if orig_init then
            orig_init(self)
        end

        if self._underline_container then
            self._underline_container.color = Blitbuffer.COLOR_WHITE
        end
    end

    function MosaicMenuItem:onFocus()
        if orig_onFocus then
            orig_onFocus(self)
        end
        if self._underline_container then
            if getBool("cover_hide_underline") then
                self._underline_container.color = Blitbuffer.COLOR_WHITE
            else
                self._underline_container.color = Blitbuffer.COLOR_BLACK
            end
        end
        return true
    end

    function MosaicMenuItem:onUnfocus()
        if orig_onUnfocus then
            orig_onUnfocus(self)
        end
        if self._underline_container then
            self._underline_container.color = Blitbuffer.COLOR_WHITE
        end
        return true
    end

    local upvalue_idx
    for i = 1, 128 do
        local name, value = debug.getupvalue(orig_update, i)
        if not name then break end
        if name == "ImageWidget" then
            upvalue_idx = i
            break
        end
    end
    if upvalue_idx then
        debug.setupvalue(orig_update, upvalue_idx, StretchingImageWidget)
    end

    function MosaicMenuItem:update(...)
        local filepath = self.entry.path or self.entry.file

        if self.entry and self.entry.is_go_up then
            local border = 1
            local max_w = self.width - 2 * border
            local title_visible = isTitleVisible()
            local max_h
            if title_visible then
                max_h = self.height - 2 * border - (self._quickui_strip_h or 0)
            else
                max_h = self.height - 2 * border
            end

            local portrait_w, portrait_h = Cover.calcDims(max_w, max_h)

            local text = "↑"
            local font_size = math.floor(math.min(portrait_w, portrait_h) * 0.2)
            local label = TextWidget:new{
                text = text,
                face = Font:getFace("cfont", font_size),
                fgcolor = Blitbuffer.COLOR_BLACK,
            }

            local cover_frame = FrameContainer:new{
                padding = 0,
                bordersize = border,
                width = portrait_w + 2 * border,
                height = portrait_h + 2 * border,
                background = Blitbuffer.COLOR_WHITE,
                CenterContainer:new{
                    dimen = { w = portrait_w, h = portrait_h },
                    label,
                },
                overlap_align = "center",
            }

            local cover_widget = CenterContainer:new{
                dimen = Geom:new{ w = self.width, h = self.height },
                cover_frame,
            }

            if self._underline_container then
                if self._underline_container[1] then
                    local old = self._underline_container[1]
                    if old.free then
                        old:free()
                    end
                end
                self._underline_container[1] = cover_widget
                self._cover_frame = cover_frame
            end
            return
        end

        orig_update(self, ...)

        if (self.entry.is_file or self.entry.file) and filepath and not self.is_directory then
            local ok, BookInfoManager = pcall(require, "bookinfomanager")
            if ok then
                local success, bookinfo = pcall(function()
                    return BookInfoManager:getBookInfo(filepath, true)
                end)

                if success then
                    local BookList = require("ui/widget/booklist")
                    local status = BookList.getBookStatus(filepath)
                    if status then
                        self.status = status
                        local bi = BookList.getBookInfo(filepath)
                        if bi then
                            self.percent_finished = bi.percent_finished
                        end
                    end

                    local has_cover = bookinfo and bookinfo.cover_bb and bookinfo.has_cover and bookinfo.cover_fetched

                    if not has_cover and self._underline_container and self._underline_container[1] then
                        local border = 1
                        local max_w = self.width - 2 * border
                        local title_visible = isTitleVisible()
                        local max_h
                        if title_visible then
                            max_h = self.height - 2 * border - (self._quickui_strip_h or 0)
                        else
                            max_h = self.height - 2 * border
                        end

                        local portrait_w, portrait_h = Cover.calcDims(max_w, max_h)
                        local cover_bb = Cover.genCover(filepath, portrait_w, portrait_h)

                        local cover_frame = FrameContainer:new{
                            padding = 0, bordersize = border,
                            width = portrait_w + 2 * border, height = portrait_h + 2 * border,
                            background = Blitbuffer.COLOR_LIGHT_GRAY,
                            CenterContainer:new{
                                dimen = { w = portrait_w, h = portrait_h },
                                ImageWidget:new{ image = cover_bb, width = portrait_w, height = portrait_h },
                            },
                            overlap_align = "center",
                        }

                        local cover_widget = CenterContainer:new{
                            dimen = Geom:new{
                                w = self.width,
                                h = self.height,
                            },
                            cover_frame,
                        }
                        self._underline_container[1] = cover_widget
                        self._cover_frame = cover_frame
                    end
                end
            end
            return
        end

        if not (self.entry.is_file or self.entry.file) and self.mandatory then
            local dir_path = self.entry and self.entry.path
            if not dir_path then return end

            local cfg = getFolderConfig()
            local mode = cfg.cover_mode

            if cfg.show_item_count then
                self._folder_file_count = getFolderFileCount(dir_path)
            else
                self._folder_file_count = nil
            end

            local border = 1
            local max_w = self.width - 2 * border
            local title_visible = isTitleVisible()
            local max_h
            if title_visible then
                max_h = self.height - 2 * border - (self._quickui_strip_h or 0)
            else
                max_h = self.height - 2 * border
            end

            local portrait_w, portrait_h = Cover.calcDims(max_w, max_h)

            local covers = loadExplicitCovers(dir_path)
            local max_covers = (mode == "gallery" or mode == "stack") and 4 or 1

            if not covers or #covers == 0 then
                covers = collectCovers(dir_path, max_covers, portrait_w, portrait_h)
            elseif #covers < max_covers then
                local combined = {}
                for _i, c in ipairs(covers) do table.insert(combined, c) end
                local extra = collectCovers(dir_path, max_covers - #combined, portrait_w, portrait_h)
                for _i, c in ipairs(extra) do table.insert(combined, c) end
                covers = combined
            end

            local folder_name = dir_path:match("([^/]+)/?$") or dir_path
            folder_name = folder_name:gsub("/$", "")

            local scaled_covers = {}
            for _i, c in ipairs(covers) do
                if c.w ~= portrait_w or c.h ~= portrait_h then
                    local scaled_bb, sw, sh = scaleCover(c.data, c.w, c.h, portrait_w, portrait_h)
                    table.insert(scaled_covers, { data = scaled_bb, w = sw, h = sh })
                else
                    table.insert(scaled_covers, { data = c.data, w = c.w, h = c.h })
                end
            end

            local cover_frame
            if #scaled_covers > 0 and mode ~= "none" then
                if mode == "gallery" then
                    cover_frame = drawGallery(scaled_covers, portrait_w, portrait_h, border)
                elseif mode == "stack" then
                    cover_frame = drawStack(scaled_covers, portrait_w, portrait_h, border)
                elseif mode == "normal" then
                    cover_frame = drawSingle(scaled_covers[1].data, portrait_w, portrait_h, border)
                else
                    cover_frame = drawNoImage(folder_name, portrait_w, portrait_h, border)
                end
            else
                cover_frame = drawNoImage(folder_name, portrait_w, portrait_h, border)
            end

            local cover_widget = CenterContainer:new{
                dimen = Geom:new{
                    w = self.width,
                    h = self.height,
                },
                cover_frame,
            }

            if self._underline_container and self._underline_container[1] then
                self._underline_container[1] = cover_widget
                self._cover_frame = cover_frame
            end

            self._folder_name = folder_name
            self._folder_cfg = cfg
            self._folder_portrait_w = portrait_w
            self._folder_portrait_h = portrait_h
        end
    end

    function MosaicMenuItem:paintTo(bb, x, y)
        local saved_do_hint_opened = self.do_hint_opened
        self.do_hint_opened = false
        orig_paintTo(self, bb, x, y)
        self.do_hint_opened = saved_do_hint_opened

        local filepath = self.entry.path or self.entry.file

        local target = self._cover_frame or (self[1] and self[1][1] and self[1][1][1])
        if not (target and target.dimen and target.dimen.y) then
            return
        end

        local corner_mark_size = 20
        local badge_scale = getBadgeScale()

        local cover_left = x + math.floor((self.width - target.dimen.w) / 2)
        local cover_top = target.dimen.y
        local cover_w = target.dimen.w
        local cover_h = target.dimen.h

        if not self.is_directory and filepath then
            drawFavoriteStar(bb, cover_left, cover_top, cover_w, filepath)
            drawProgressBadge(bb, cover_left, cover_top, cover_w, self.percent_finished)
            drawNewBanner(bb, cover_left, cover_top, cover_w, cover_h, self.status)
            dimFinishedBook(bb, cover_left, cover_top, cover_w, cover_h, self.status)
            drawPageCountBadge(bb, cover_left, cover_top, cover_w, cover_h, filepath)
            drawFormatBadge(bb, cover_left, cover_top, cover_w, cover_h, filepath)
        end

        if not self.is_directory and filepath then
            if getBool("cover_show_title_on_cover") then
                local ok_bim, BookInfoManager = pcall(require, "bookinfomanager")
                if ok_bim then
                    local success, bookinfo = pcall(function()
                        return BookInfoManager:getBookInfo(filepath, true)
                    end)
                    if success and bookinfo and not bookinfo.ignore_meta then
                        local title = bookinfo.title
                        if not title or title == "" then
                            local fname = filepath:match("([^/]+)$") or ""
                            title = fname:gsub("%.[^%.]+$", "")
                        end
                        local cfg = {
                            name_centered = getBool("cover_title_centered"),
                            name_opaque = getBool("cover_title_opaque"),
                        }
                        local border = 1
                        local name_widget = drawFolderNameOnCover(title, cover_w - 2*border, cover_h - 2*border, cfg)
                        if name_widget then
                            name_widget:paintTo(bb, cover_left, cover_top)
                        end
                    end
                end
            end
        end

        if self.is_directory and self._folder_name then
            local cfg = self._folder_cfg or getFolderConfig()
            local border = 1
            local portrait_w = self._folder_portrait_w or cover_w
            local portrait_h = self._folder_portrait_h or cover_h
            local dimen_w = portrait_w + 2 * border
            local dimen_h = portrait_h + 2 * border

            if cfg.show_folder_name then
                local name_widget = drawFolderNameOnCover(self._folder_name, portrait_w, portrait_h, cfg)
                if name_widget then
                    name_widget:paintTo(bb, cover_left, cover_top)
                end
            end

            if cfg.show_item_count and self._folder_file_count and self._folder_file_count > 0 then
                local eff_size = math.floor(math.max(corner_mark_size, math.floor(cover_w * 0.14)) * badge_scale)
                local font_size = math.max(7, math.floor(eff_size * 0.24))
                local count_str = tostring(self._folder_file_count)

                local bg_color = getBadgeColor()
                local fg_color = getBadgeTextColor()

                local tw = TextWidget:new{
                    text = count_str,
                    face = Font:getFace("cfont", font_size),
                    bold = true,
                    fgcolor = fg_color,
                    padding = 0,
                }
                local tw_sz = tw:getSize()
                local r = math.floor(eff_size * 0.45)
                local cx = cover_left + cover_w - r - 4
                local cy = cover_top + r + 4

                paintCircle(bb, cx, cy, r + 2, Blitbuffer.COLOR_BLACK)
                paintCircle(bb, cx, cy, r, bg_color)
                tw:paintTo(bb, cx - math.floor(tw_sz.w / 2), cy - math.floor(tw_sz.h / 2))
                tw:free()
            end

            if cfg.show_spine_lines then
                local centered_top = math.floor((self.height - dimen_h) / 2)
                local top_h = 2 * (FolderEdge.thick + FolderEdge.margin)
                local use_top_lines = centered_top >= top_h or math.floor((self.width - dimen_w) / 2) < Screen:scaleBySize(9)

                local spine_widget = drawSpineLinesOnCover(portrait_w, portrait_h, border, use_top_lines, centered_top, dimen_w, dimen_h, self.width)
                if spine_widget then
                    spine_widget:paintTo(bb, x, y)
                end
            end
        end

        applyRoundedCornersToCover(bb, target)

        local show_title = getBool("cover_show_title")
        local show_author = getBool("cover_show_author")

        if (show_title or show_author) and filepath then
            if not self.is_directory then
                drawTitleAndAuthor(bb, cover_left, cover_w, cover_top, cover_h, filepath, 0, y + self.height, show_title, show_author, false)
            else
                if show_title and self._folder_name then
                    drawTitleAndAuthor(bb, cover_left, cover_w, cover_top, cover_h, self._folder_name, 0, y + self.height, true, false, true)
                end
            end
        end
    end

    logger.info("QuickUI Cover: Mosaic patch applied")
end

-- ============================================================
-- List Mode Patch
-- ============================================================

function Cover._patchList()
    local ListMenu = require("listmenu")
    local ListMenuItem = Utils.getUpvalue(ListMenu._updateItemsBuildUI, "ListMenuItem")

    if not ListMenuItem then
        logger.warn("QuickUI Cover: Cannot get ListMenuItem")
        return
    end

    if ListMenuItem._quickui_list_patched then
        return
    end
    ListMenuItem._quickui_list_patched = true

    local orig_paintTo = ListMenuItem.paintTo

    local function getFontSize(nominal, dimen_h)
        local scale_by_size = Screen:scaleBySize(1000000) * (1/1000000)
        local scale = Utils.scaleBySize(1)
        local fs = math.floor(nominal * dimen_h * (1 / 64) / scale_by_size * scale + 0.5)
        local max_size = math.floor(24 * scale + 0.5)
        local min_size = math.max(8, math.floor(10 * scale + 0.5))
        if fs > max_size then fs = max_size end
        if fs < min_size then fs = min_size end
        return fs
    end

    function ListMenuItem:update()
        local filepath = self.filepath
        local is_dir = not (self.entry.is_file or self.entry.file)

        local underline_h = 1
        local dimen_h = self.height - 2 * underline_h
        local border = Size.border.thin
        local cover_v_pad = Screen:scaleBySize(4)
        local max_img = dimen_h - 2 * border - 2 * cover_v_pad

        local aspect_ratio = Cover.getAspectRatio()
        local target_w = math.floor(max_img * aspect_ratio)
        local target_h = max_img
        if target_w > max_img then
            target_w = max_img
            target_h = math.floor(target_w / aspect_ratio)
        end

        if self.entry and self.entry.is_go_up then
            local text = "↑"
            local font_size = math.floor(math.min(target_w, target_h) * 0.5)
            local label = TextWidget:new{
                text = text,
                face = Font:getFace("cfont", font_size),
                fgcolor = Blitbuffer.COLOR_BLACK,
            }

            local cover_frame = FrameContainer:new{
                padding = 0,
                bordersize = border,
                width = target_w + 2 * border,
                height = target_h + 2 * border,
                background = Blitbuffer.COLOR_WHITE,
                CenterContainer:new{
                    dimen = { w = target_w, h = target_h },
                    label,
                },
                overlap_align = "center",
            }

            self._cover_frame = cover_frame

            local pad_left = Screen:scaleBySize(8)
            local text_safe_pad_top = math.max(2, Screen:scaleBySize(4))
            local content_h = math.max(1, dimen_h - text_safe_pad_top * 2)
            local fs_title = getFontSize(16, dimen_h)
            fs_title = math.min(fs_title, math.max(9, math.floor(content_h * 0.45)))

            local up_text = BD.mirroredUILayout() and BD.ltr("../ \u{F062}") or "\u{F062}  ../"
            local wtitle = TextBoxWidget:new{
                text = up_text,
                face = Utils.getFontFace("cfont", fs_title),
                width = self.width - target_w - 3 * pad_left,
                height = content_h,
                height_adjust = true,
                height_overflow_show_ellipsis = true,
                alignment = "left",
                bold = true,
            }

            local right_stack = VerticalGroup:new{ align = "left" }
            table.insert(right_stack, VerticalSpan:new{ width = text_safe_pad_top })
            table.insert(right_stack, wtitle)

            local row_dimen = { w = self.width, h = dimen_h }
            local cover_total_w = target_w + 2 * border
            local right_available_w = self.width - cover_total_w - 3 * pad_left
            if right_available_w < 50 then
                right_available_w = 50
            end

            local widget = OverlapGroup:new{
                dimen = row_dimen,
                LeftContainer:new{
                    dimen = row_dimen,
                    HorizontalGroup:new{
                        HorizontalSpan:new{ width = pad_left },
                        CenterContainer:new{
                            dimen = { w = cover_total_w, h = dimen_h },
                            cover_frame,
                        },
                        HorizontalSpan:new{ width = pad_left },
                        LeftContainer:new{
                            dimen = { w = right_available_w, h = dimen_h },
                            right_stack,
                        },
                    },
                },
            }

            if self._underline_container then
                if self._underline_container[1] and self._underline_container[1].free then
                    self._underline_container[1]:free()
                end
                self._underline_container[1] = VerticalGroup:new{
                    VerticalSpan:new{ width = underline_h },
                    widget,
                }
            end

            self.bookinfo_found = true
            self.init_done = true
            return
        end

        if is_dir then
            local dir_path = self.entry and self.entry.path
            if not dir_path then
                return
            end

            local cfg = getFolderConfig()
            local mode = cfg.cover_mode
            local folder_file_count = nil

            if cfg.show_item_count then
                folder_file_count = getFolderFileCount(dir_path)
            end

            local covers = loadExplicitCovers(dir_path)
            local max_covers = (mode == "gallery" or mode == "stack") and 4 or 1

            if not covers or #covers == 0 then
                covers = collectCovers(dir_path, max_covers, target_w, target_h)
            elseif #covers < max_covers then
                local combined = {}
                for _i, c in ipairs(covers) do table.insert(combined, c) end
                local extra = collectCovers(dir_path, max_covers - #combined, target_w, target_h)
                for _i, c in ipairs(extra) do table.insert(combined, c) end
                covers = combined
            end

            local folder_name = dir_path:match("([^/]+)/?$") or dir_path
            folder_name = folder_name:gsub("/$", "")

            local scaled_covers = {}
            for _i, c in ipairs(covers) do
                if c.w ~= target_w or c.h ~= target_h then
                    local scaled_bb, sw, sh = scaleCover(c.data, c.w, c.h, target_w, target_h)
                    table.insert(scaled_covers, { data = scaled_bb, w = sw, h = sh })
                else
                    table.insert(scaled_covers, { data = c.data, w = c.w, h = c.h })
                end
            end

            local cover_frame
            if #scaled_covers > 0 and mode ~= "none" then
                if mode == "gallery" then
                    cover_frame = drawGallery(scaled_covers, target_w, target_h, border)
                elseif mode == "stack" then
                    cover_frame = drawStack(scaled_covers, target_w, target_h, border)
                elseif mode == "normal" then
                    cover_frame = drawSingle(scaled_covers[1].data, target_w, target_h, border)
                else
                    cover_frame = drawNoImage(folder_name, target_w, target_h, border)
                end
            else
                cover_frame = drawNoImage(folder_name, target_w, target_h, border)
            end

            self._cover_frame = cover_frame
            self._folder_name = folder_name
            self._folder_cfg = cfg
            self._folder_file_count = folder_file_count
            self._folder_portrait_w = target_w
            self._folder_portrait_h = target_h

            local right_widgets = {}
            local text_safe_pad_top = math.max(2, Screen:scaleBySize(4))
            local content_h = math.max(1, dimen_h - text_safe_pad_top * 2)

            local fs_title = getFontSize(16, dimen_h)
            fs_title = math.min(fs_title, math.max(9, math.floor(content_h * 0.45)))

            local title_text = BD.directory(folder_name)
            local wtitle = TextBoxWidget:new{
                text = title_text,
                face = Utils.getFontFace("cfont", fs_title),
                width = self.width - target_w - Screen:scaleBySize(24),
                height = content_h,
                height_adjust = true,
                height_overflow_show_ellipsis = true,
                alignment = "left",
                bold = true,
            }
            table.insert(right_widgets, wtitle)

            if folder_file_count and folder_file_count > 0 then
                local fs_info = getFontSize(12, dimen_h)
                fs_info = math.min(fs_info, math.max(8, math.floor(content_h * 0.34)))
                local count_str = tostring(folder_file_count) .. " " .. (folder_file_count == 1 and _("book") or _("books"))
                local wcount = TextWidget:new{
                    text = count_str,
                    face = Utils.getFontFace("cfont", fs_info),
                    fgcolor = Blitbuffer.COLOR_GRAY_3,
                }
                table.insert(right_widgets, wcount)
            end

            local right_stack = VerticalGroup:new{ align = "left" }
            table.insert(right_stack, VerticalSpan:new{ width = text_safe_pad_top })
            for _, w in ipairs(right_widgets) do
                table.insert(right_stack, w)
            end

            local row_dimen = { w = self.width, h = dimen_h }
            local pad_left = Screen:scaleBySize(8)
            local cover_total_w = target_w + 2 * border
            local right_available_w = self.width - cover_total_w - 3 * pad_left
            if right_available_w < 50 then
                right_available_w = 50
            end

            local widget = OverlapGroup:new{
                dimen = row_dimen,
                LeftContainer:new{
                    dimen = row_dimen,
                    HorizontalGroup:new{
                        HorizontalSpan:new{ width = pad_left },
                        CenterContainer:new{
                            dimen = { w = cover_total_w, h = dimen_h },
                            cover_frame,
                        },
                        HorizontalSpan:new{ width = pad_left },
                        LeftContainer:new{
                            dimen = { w = right_available_w, h = dimen_h },
                            right_stack,
                        },
                    },
                },
            }

            if self._underline_container then
                if self._underline_container[1] and self._underline_container[1].free then
                    self._underline_container[1]:free()
                end
                self._underline_container[1] = VerticalGroup:new{
                    VerticalSpan:new{ width = underline_h },
                    widget,
                }
            end

            self.bookinfo_found = true
            self.init_done = true
            return
        end

        if not filepath then
            return
        end

        local ok, BookInfoManager = pcall(require, "bookinfomanager")
        if not ok then
            return
        end

        local bookinfo = BookInfoManager:getBookInfo(filepath, true)
        local has_cover = bookinfo and bookinfo.cover_bb and bookinfo.has_cover and bookinfo.cover_fetched

        local BookList = require("ui/widget/booklist")
        local status = BookList.getBookStatus(filepath)
        if status then
            self.status = status
            local bi = BookList.getBookInfo(filepath)
            if bi then
                self.percent_finished = bi.percent_finished
            end
        end

        local cover_frame
        if has_cover and not bookinfo.ignore_cover then
            local scaled_bb = bookinfo.cover_bb:scale(target_w, target_h)
            local wimage = ImageWidget:new{
                image = scaled_bb,
                image_disposable = true,
                width = target_w,
                height = target_h,
            }
            wimage:_render()

            cover_frame = FrameContainer:new{
                width = target_w + 2 * border,
                height = target_h + 2 * border,
                margin = 0,
                padding = 0,
                bordersize = border,
                CenterContainer:new{
                    dimen = { w = target_w, h = target_h },
                    wimage,
                },
            }
        else
            local cover_bb = Cover.genCover(filepath, target_w, target_h)
            local wimage = ImageWidget:new{
                image = cover_bb,
                width = target_w,
                height = target_h,
                _free_image = true,
            }
            wimage:_render()

            cover_frame = FrameContainer:new{
                width = target_w + 2 * border,
                height = target_h + 2 * border,
                margin = 0,
                padding = 0,
                bordersize = border,
                CenterContainer:new{
                    dimen = { w = target_w, h = target_h },
                    wimage,
                },
            }
        end

        self._cover_frame = cover_frame

        local right_widgets = {}
        local text_safe_pad_top = math.max(2, Screen:scaleBySize(4))
        local content_h = math.max(1, dimen_h - text_safe_pad_top * 2)

        if bookinfo and not bookinfo.ignore_meta then
            local title = bookinfo.title
            local authors = bookinfo.authors

            if not title or title == "" then
                local fname = filepath:match("([^/]+)$") or ""
                title = fname:gsub("%.[^%.]+$", "")
            end

            if title then
                local fs_title = getFontSize(16, dimen_h)
                fs_title = math.min(fs_title, math.max(9, math.floor(content_h * 0.45)))
                local wtitle = TextBoxWidget:new{
                    text = BD.auto(title),
                    face = Utils.getFontFace("cfont", fs_title),
                    width = self.width - target_w - Screen:scaleBySize(24),
                    height = math.floor(content_h * 0.6),
                    height_adjust = true,
                    height_overflow_show_ellipsis = true,
                    alignment = "left",
                    bold = true,
                }
                table.insert(right_widgets, wtitle)
            end

            if authors and authors ~= "" then
                local fs_author = getFontSize(12, dimen_h)
                fs_author = math.min(fs_author, math.max(8, math.floor(content_h * 0.34)))
                local wauthors = TextWidget:new{
                    text = BD.auto(authors:gsub("\n", ", ")),
                    face = Utils.getFontFace("cfont", fs_author),
                    fgcolor = Blitbuffer.COLOR_GRAY,
                    max_width = self.width - target_w - Screen:scaleBySize(24),
                }
                table.insert(right_widgets, wauthors)
            end
        end

        local right_stack = VerticalGroup:new{ align = "left" }
        table.insert(right_stack, VerticalSpan:new{ width = text_safe_pad_top })
        for _, w in ipairs(right_widgets) do
            table.insert(right_stack, w)
        end

        local row_dimen = { w = self.width, h = dimen_h }
        local pad_left = Screen:scaleBySize(8)
        local cover_total_w = target_w + 2 * border
        local right_available_w = self.width - cover_total_w - 3 * pad_left
        if right_available_w < 50 then
            right_available_w = 50
        end

        local widget = OverlapGroup:new{
            dimen = row_dimen,
            LeftContainer:new{
                dimen = row_dimen,
                HorizontalGroup:new{
                    HorizontalSpan:new{ width = pad_left },
                    CenterContainer:new{
                        dimen = { w = cover_total_w, h = dimen_h },
                        cover_frame,
                    },
                    HorizontalSpan:new{ width = pad_left },
                    LeftContainer:new{
                        dimen = { w = right_available_w, h = dimen_h },
                        right_stack,
                    },
                },
            },
        }

        if self._underline_container then
            if self._underline_container[1] and self._underline_container[1].free then
                self._underline_container[1]:free()
            end
            self._underline_container[1] = VerticalGroup:new{
                VerticalSpan:new{ width = underline_h },
                widget,
            }
        end

        self.bookinfo_found = true
        self.init_done = true
    end

    function ListMenuItem:paintTo(bb, x, y)
        orig_paintTo(self, bb, x, y)

        local target = self._cover_frame
        if not target or not target.dimen then
            return
        end

        local cover_left = target.dimen.x
        local cover_top = target.dimen.y
        local cover_w = target.dimen.w
        local cover_h = target.dimen.h
        local filepath = self.filepath

        local corner_mark_size = 20
        local badge_scale = getBadgeScale()

        if not self.is_directory and filepath then
            drawFavoriteStar(bb, cover_left, cover_top, cover_w, filepath)
            drawProgressBadge(bb, cover_left, cover_top, cover_w, self.percent_finished)
            drawNewBanner(bb, cover_left, cover_top, cover_w, cover_h, self.status)
            dimFinishedBook(bb, cover_left, cover_top, cover_w, cover_h, self.status)
            drawPageCountBadge(bb, cover_left, cover_top, cover_w, cover_h, filepath)
            drawFormatBadge(bb, cover_left, cover_top, cover_w, cover_h, filepath)
        end

        if self.is_directory and self._folder_name then
            local cfg = self._folder_cfg or getFolderConfig()
            local portrait_w = self._folder_portrait_w or cover_w
            local portrait_h = self._folder_portrait_h or cover_h
            local dimen_w = portrait_w + 2
            local dimen_h = portrait_h + 2

            if cfg.show_item_count and self._folder_file_count and self._folder_file_count > 0 then
                local eff_size = math.floor(math.max(corner_mark_size, math.floor(cover_w * 0.14)) * badge_scale)
                local font_size = math.max(7, math.floor(eff_size * 0.24))
                local count_str = tostring(self._folder_file_count)

                local bg_color = getBadgeColor()
                local fg_color = getBadgeTextColor()

                local tw = TextWidget:new{
                    text = count_str,
                    face = Font:getFace("cfont", font_size),
                    bold = true,
                    fgcolor = fg_color,
                    padding = 0,
                }
                local tw_sz = tw:getSize()
                local r = math.floor(eff_size * 0.45)
                local cx = cover_left + cover_w - r - 4
                local cy = cover_top + r + 4

                paintCircle(bb, cx, cy, r + 2, Blitbuffer.COLOR_BLACK)
                paintCircle(bb, cx, cy, r, bg_color)
                tw:paintTo(bb, cx - math.floor(tw_sz.w / 2), cy - math.floor(tw_sz.h / 2))
                tw:free()
            end

            if cfg.show_spine_lines then
                local centered_top = math.floor((self.height - dimen_h) / 2)
                local top_h = 2 * (FolderEdge.thick + FolderEdge.margin)
                local use_top_lines = centered_top >= top_h or math.floor((self.width - dimen_w) / 2) < Screen:scaleBySize(9)

                local spine_widget = drawSpineLinesOnCover(portrait_w, portrait_h, 1, use_top_lines, centered_top, dimen_w, dimen_h, self.width)
                if spine_widget then
                    spine_widget:paintTo(bb, x, y)
                end
            end
        end

        applyRoundedCornersToCover(bb, target)
    end

    logger.info("QuickUI Cover: List patch applied")
end

-- ============================================================
-- Hide Up Folder Patch
-- ============================================================

function Cover._patchHideUpFolder()
    local FileChooser = require("ui/widget/filechooser")

    local orig_genItemTable = FileChooser.genItemTable

    function FileChooser:genItemTable(dirs, files, path)
        local item_table = orig_genItemTable(self, dirs, files, path)

        if self._dummy or self.name ~= "filemanager" then
            return item_table
        end

        if not getBool("cover_hide_up_folder") then
            return item_table
        end

        local items = {}
        for _, item in ipairs(item_table) do
            if not (item.is_go_up or (item.text and item.text:find("\u{2B06} .."))) then
                table.insert(items, item)
            end
        end

        return items
    end

    logger.info("QuickUI Cover: Hide up folder patch applied")
end

-- ============================================================
-- Public API: Get Menu Items
-- ============================================================

function Cover.getMenuItems()
    local items = {}

    -- Book Cover
    local book_cover_items = {}

    -- Placeholder Cover
    local placeholder_items = {
        {
            text = _("Simple (white background)"),
            radio = true,
            checked_func = function()
                return getString("cover_placeholder_style") == "simple"
            end,
            callback = function()
                setString("cover_placeholder_style", "simple")
                refreshFileManager()
            end
        },
        {
            text = _("Gradient"),
            radio = true,
            checked_func = function()
                return getString("cover_placeholder_style") == "gradient"
            end,
            callback = function()
                setString("cover_placeholder_style", "gradient")
                refreshFileManager()
            end
        },
    }
    table.insert(book_cover_items, {
        text = _("Placeholder Cover"),
        sub_item_table = placeholder_items,
    })

    -- Badges
    local badge_size_items = {
        {
            text = _("Compact"),
            radio = true,
            checked_func = function()
                return getString("cover_badge_size") == "compact"
            end,
            callback = function()
                setString("cover_badge_size", "compact")
                refreshFileManager()
            end
        },
        {
            text = _("Normal"),
            radio = true,
            checked_func = function()
                return getString("cover_badge_size") == "normal"
            end,
            callback = function()
                setString("cover_badge_size", "normal")
                refreshFileManager()
            end
        },
        {
            text = _("Large"),
            radio = true,
            checked_func = function()
                return getString("cover_badge_size") == "large"
            end,
            callback = function()
                setString("cover_badge_size", "large")
                refreshFileManager()
            end
        },
        {
            text = _("Extra Large"),
            radio = true,
            checked_func = function()
                return getString("cover_badge_size") == "extra_large"
            end,
            callback = function()
                setString("cover_badge_size", "extra_large")
                refreshFileManager()
            end
        },
    }

    local color_presets = {
        { text = _("Black"), r = 0, g = 0, b = 0 },
        { text = _("White"), r = 255, g = 255, b = 255 },
        { text = _("Gray"), r = 204, g = 204, b = 204 },
        { text = _("Blue"), r = 0x99, g = 0xBB, b = 0xF0 },
        { text = _("Green"), r = 0x99, g = 0xCC, b = 0x99 },
        { text = _("Amber"), r = 0xF0, g = 0xD0, b = 0x80 },
        { text = _("Red"), r = 0xDD, g = 0x99, b = 0x99 },
    }
    local badge_color_items = {}
    for _, preset in ipairs(color_presets) do
        table.insert(badge_color_items, {
            text = preset.text,
            radio = true,
            checked_func = function()
                local r = getNumber("cover_badge_color_r")
                local g = getNumber("cover_badge_color_g")
                local b = getNumber("cover_badge_color_b")
                return r == preset.r and g == preset.g and b == preset.b
            end,
            callback = function()
                set("cover_badge_color_r", preset.r)
                set("cover_badge_color_g", preset.g)
                set("cover_badge_color_b", preset.b)
                refreshFileManager()
            end,
        })
    end

    local badge_items = {
        {
            text = _("Badge Size"),
            sub_item_table = badge_size_items,
        },
        {
            text = _("Badge Color"),
            sub_item_table = badge_color_items,
        },
        {
            text = _("Show Favorite Star"),
            checked_func = function()
                return getBool("cover_show_favorite")
            end,
            callback = function()
                setBool("cover_show_favorite", not getBool("cover_show_favorite"))
                refreshFileManager()
            end
        },
        {
            text = _("Show Progress Percentage"),
            checked_func = function()
                return getBool("cover_show_progress")
            end,
            callback = function()
                setBool("cover_show_progress", not getBool("cover_show_progress"))
                refreshFileManager()
            end
        },
        {
            text = _("Show NEW Banner"),
            checked_func = function()
                return getBool("cover_show_new")
            end,
            callback = function()
                setBool("cover_show_new", not getBool("cover_show_new"))
                refreshFileManager()
            end
        },
        {
            text = _("Dim Finished Books"),
            checked_func = function()
                return getBool("cover_dim_finished")
            end,
            callback = function()
                setBool("cover_dim_finished", not getBool("cover_dim_finished"))
                refreshFileManager()
            end
        },
        {
            text = _("Show Page Count"),
            checked_func = function()
                return getBool("cover_show_pagecount")
            end,
            callback = function()
                setBool("cover_show_pagecount", not getBool("cover_show_pagecount"))
                refreshFileManager()
            end
        },
        {
            text = _("Show Format Badge"),
            checked_func = function()
                return getBool("cover_show_format")
            end,
            callback = function()
                setBool("cover_show_format", not getBool("cover_show_format"))
                refreshFileManager()
            end
        },
    }
    table.insert(book_cover_items, {
        text = _("Badges"),
        sub_item_table = badge_items,
    })

    -- Cover Title Banner
    local banner_items = {
        {
            text = _("Show Banner"),
            checked_func = function()
                return getBool("cover_show_title_on_cover")
            end,
            callback = function()
                setBool("cover_show_title_on_cover", not getBool("cover_show_title_on_cover"))
                refreshFileManager()
            end
        },
        {
            text = _("Centered"),
            radio = true,
            enabled_func = function()
                return getBool("cover_show_title_on_cover")
            end,
            checked_func = function()
                return getBool("cover_title_centered")
            end,
            callback = function()
                setBool("cover_title_centered", true)
                refreshFileManager()
            end
        },
        {
            text = _("Bottom"),
            radio = true,
            enabled_func = function()
                return getBool("cover_show_title_on_cover")
            end,
            checked_func = function()
                return not getBool("cover_title_centered")
            end,
            callback = function()
                setBool("cover_title_centered", false)
                refreshFileManager()
            end
        },
        {
            text = _("Opaque Background"),
            enabled_func = function()
                return getBool("cover_show_title_on_cover")
            end,
            checked_func = function()
                return getBool("cover_title_opaque")
            end,
            callback = function()
                setBool("cover_title_opaque", not getBool("cover_title_opaque"))
                refreshFileManager()
            end
        },
    }
    table.insert(book_cover_items, {
        text = _("Cover Title Banner"),
        sub_item_table = banner_items,
    })

    table.insert(items, {
        text = _("Book Cover"),
        sub_item_table = book_cover_items,
    })

    -- Folder Cover
    local folder_mode_items = {
        {
            text = _("Gallery (4-grid collage)"),
            radio = true,
            checked_func = function()
                return getString("cover_folder_mode") == "gallery"
            end,
            callback = function()
                setString("cover_folder_mode", "gallery")
                refreshFileManager()
            end
        },
        {
            text = _("Stack (stacking effect)"),
            radio = true,
            checked_func = function()
                return getString("cover_folder_mode") == "stack"
            end,
            callback = function()
                setString("cover_folder_mode", "stack")
                refreshFileManager()
            end
        },
        {
            text = _("Normal (first cover)"),
            radio = true,
            checked_func = function()
                return getString("cover_folder_mode") == "normal"
            end,
            callback = function()
                setString("cover_folder_mode", "normal")
                refreshFileManager()
            end
        },
        {
            text = _("None (folder name only)"),
            radio = true,
            checked_func = function()
                return getString("cover_folder_mode") == "none"
            end,
            callback = function()
                setString("cover_folder_mode", "none")
                refreshFileManager()
            end
        },
    }

    local folder_name_items = {
        {
            text = _("Show Name"),
            checked_func = function()
                return getBool("cover_show_foldername")
            end,
            callback = function()
                setBool("cover_show_foldername", not getBool("cover_show_foldername"))
                refreshFileManager()
            end
        },
        {
            text = _("Centered"),
            radio = true,
            enabled_func = function()
                return getBool("cover_show_foldername")
            end,
            checked_func = function()
                return getBool("cover_name_centered")
            end,
            callback = function()
                setBool("cover_name_centered", true)
                refreshFileManager()
            end
        },
        {
            text = _("Bottom"),
            radio = true,
            enabled_func = function()
                return getBool("cover_show_foldername")
            end,
            checked_func = function()
                return not getBool("cover_name_centered")
            end,
            callback = function()
                setBool("cover_name_centered", false)
                refreshFileManager()
            end
        },
        {
            text = _("Opaque Background"),
            enabled_func = function()
                return getBool("cover_show_foldername")
            end,
            checked_func = function()
                return getBool("cover_name_opaque")
            end,
            callback = function()
                setBool("cover_name_opaque", not getBool("cover_name_opaque"))
                refreshFileManager()
            end
        },
    }

    local folder_items = {
        {
            text = _("Folder Cover Mode"),
            sub_item_table = folder_mode_items,
        },
        {
            text = _("Show Spine Decoration Lines"),
            checked_func = function()
                return getBool("cover_show_spine")
            end,
            callback = function()
                setBool("cover_show_spine", not getBool("cover_show_spine"))
                refreshFileManager()
            end
        },
        {
            text = _("Show File Count"),
            checked_func = function()
                return getBool("cover_show_itemcount")
            end,
            callback = function()
                setBool("cover_show_itemcount", not getBool("cover_show_itemcount"))
                refreshFileManager()
            end
        },
        {
            text = _("Folder Name"),
            sub_item_table = folder_name_items,
        },
    }
    table.insert(items, {
        text = _("Folder Covers"),
        sub_item_table = folder_items,
    })

    -- Cover Aspect Ratio
    local ratio_items = {
        {
            text = _("3:4 (default)"),
            radio = true,
            checked_func = function()
                return getString("cover_ratio") == "3:4"
            end,
            callback = function()
                setString("cover_ratio", "3:4")
                refreshFileManager()
            end
        },
        {
            text = _("2:3"),
            radio = true,
            checked_func = function()
                return getString("cover_ratio") == "2:3"
            end,
            callback = function()
                setString("cover_ratio", "2:3")
                refreshFileManager()
            end
        },
    }
    table.insert(items, {
        text = _("Cover Aspect Ratio"),
        sub_item_table = ratio_items,
    })

    -- Toggle items
    table.insert(items, {
        text = _("Rounded Corners"),
        checked_func = function()
            return getBool("cover_rounded_corners")
        end,
        callback = function()
            setBool("cover_rounded_corners", not getBool("cover_rounded_corners"))
            refreshFileManager()
        end
    })

    table.insert(items, {
        text = _("Show Title Below Cover"),
        checked_func = function()
            return getBool("cover_show_title")
        end,
        callback = function()
            setBool("cover_show_title", not getBool("cover_show_title"))
            refreshFileManager()
        end
    })

    table.insert(items, {
        text = _("Show Author Below Cover"),
        checked_func = function()
            return getBool("cover_show_author")
        end,
        callback = function()
            setBool("cover_show_author", not getBool("cover_show_author"))
            refreshFileManager()
        end
    })

    table.insert(items, {
        text = _("Hide Underline"),
        checked_func = function()
            return getBool("cover_hide_underline")
        end,
        callback = function()
            setBool("cover_hide_underline", not getBool("cover_hide_underline"))
            refreshFileManager()
        end
    })

    table.insert(items, {
        text = _("Hide Up Folder"),
        checked_func = function()
            return getBool("cover_hide_up_folder")
        end,
        callback = function()
            setBool("cover_hide_up_folder", not getBool("cover_hide_up_folder"))
            refreshFileManager()
        end
    })

    -- Add default config menu items
    local default_items = Utils.buildDefaultMenuItems("cover", function()
        refreshFileManager()
    end)
    for _, item in ipairs(default_items) do
        table.insert(items, item)
    end

    return items
end

-- ============================================================
-- Public API: Show Settings
-- ============================================================

function Cover.showSettings(plugin_ref)
    plugin = plugin_ref or plugin

    local items = Cover.getMenuItems()
    local self_ref = { _cover_settings_dialog = nil }

    local function showMenu(title, item_table, parent_stack)
        local buttons = {}

        -- Only add QuickUI Settings button if no parent (root menu)
        if parent_stack == nil or #parent_stack == 0 then
            table.insert(buttons, {
                {
                    text = "⚙️ " .. _("QuickUI Settings"),
                    callback = function()
                        if self_ref._cover_settings_dialog then
                            UIManager:close(self_ref._cover_settings_dialog)
                            self_ref._cover_settings_dialog = nil
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
                            if self_ref._cover_settings_dialog then
                                UIManager:close(self_ref._cover_settings_dialog)
                                self_ref._cover_settings_dialog = nil
                            end
                            showMenu(_("Cover Visual Settings"), items, nil)
                        end
                    }
                })
            end

            table.insert(buttons, {
                {
                    text = "◂ " .. _("Back"),
                    callback = function()
                        if self_ref._cover_settings_dialog then
                            UIManager:close(self_ref._cover_settings_dialog)
                            self_ref._cover_settings_dialog = nil
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
                local display_text = type(item.text) == "function" and item.text() or item.text
                table.insert(buttons, {
                    {
                        text = display_text .. " ▸",
                        callback = function()
                            if self_ref._cover_settings_dialog then
                                UIManager:close(self_ref._cover_settings_dialog)
                                self_ref._cover_settings_dialog = nil
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
                local display_text = type(item.text) == "function" and item.text() or item.text
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
                            if self_ref._cover_settings_dialog then
                                UIManager:close(self_ref._cover_settings_dialog)
                                self_ref._cover_settings_dialog = nil
                            end
                            showMenu(title, item_table, parent_stack)
                        end
                    }
                })
            end
        end

        if self_ref._cover_settings_dialog then
            UIManager:close(self_ref._cover_settings_dialog)
            self_ref._cover_settings_dialog = nil
        end

        local dialog = ButtonDialog:new{
            title = title or _("Cover Visual Settings"),
            title_align = "center",
            buttons = buttons,
            width = math.floor(Screen:getWidth() * 0.7),
            max_height = math.floor(Screen:getHeight() * 0.7),
        }
        self_ref._cover_settings_dialog = dialog
        UIManager:show(dialog)
    end

    showMenu(_("Cover Visual Settings"), items, nil)
end

return Cover