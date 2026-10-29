--[[
QuickUI - Book Switcher page

Renders one page of recent-book covers. Pagination and the
enable/disable toggle are handled by qa_panel.lua, which treats this
page group exactly like the button page group.
]]
local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local FrameContainer = require("ui/widget/container/framecontainer")
local _ = require("gettext")

local Utils = require("qui_utils")

local M = {}

M.MAX_BOOKS = 20

local function cfg(key, default) return Utils.get(key, default) end
local function setCfg(key, value) Utils.set(key, value) end

function M.normalizeCount(v)
    v = tonumber(v) or Utils.getNumber("qa_panel_bs_count", 5)
    return math.min(8, math.max(1, math.floor(v)))
end

-- ------------------------------------------------------------
-- Book loading (same as before, without lfs/inHomeDir checks)
-- ------------------------------------------------------------

local function isImageFile(path)
    return type(path) == "string"
        and path:lower():match("%.(jpg|jpeg|png|gif|bmp|webp)$") ~= nil
end

local function fallbackTitle(path)
    local fname = (path or ""):match("([^/\\]+)$") or path or ""
    return fname:gsub("%.[^%.]+$", "")
end

local function loadBook(path, BookInfoManager)
    local info
    if BookInfoManager and type(BookInfoManager.getBookInfo) == "function" then
        local ok, loaded = pcall(
            BookInfoManager.getBookInfo, BookInfoManager, path, true)
        if ok then info = loaded end
    end
    return {
        path = path,
        cover_bb = info and info.cover_bb or nil,
        cover_w = info and tonumber(info.cover_w) or nil,
        cover_h = info and tonumber(info.cover_h) or nil,
        has_real_cover = info and info.cover_fetched and info.has_cover
            and not info.ignore_cover or false,
    }
end

function M.loadBooks(limit, exclude_path)
    local hidden = Utils.getTable("qa_panel_bs_hidden") or {}
    local ok_history, ReadHistory = pcall(require, "readhistory")
    if not ok_history or not ReadHistory then return {} end
    if type(ReadHistory.reload) == "function" then
        pcall(ReadHistory.reload, ReadHistory, false)
    end
    local ok_bim, BookInfoManager = pcall(require, "bookinfomanager")
    if not ok_bim then BookInfoManager = nil end

    local hide_finished = cfg("qa_panel_bs_hide_finished", true)
    local books, seen = {}, {}
    for _i, entry in ipairs(ReadHistory.hist or {}) do
        local path = entry and entry.file
        local is_file = type(path) == "string" and path ~= ""
            and not isImageFile(path) and not entry.dim
        if is_file and path ~= exclude_path
                and not hidden[path] and not seen[path] then
            seen[path] = true
            local finished = entry.summary and entry.summary.status == "complete"
            if not (hide_finished and finished) then
                books[#books + 1] = loadBook(path, BookInfoManager)
                if limit and #books >= limit then break end
            end
        end
    end
    return books
end

-- ------------------------------------------------------------
-- Cover widget (no title / no author)
-- ------------------------------------------------------------

local function makeCover(book, max_w, max_h, border, is_current)
    border = tonumber(border) or 0
    local inner_w = math.max(1, max_w - border * 2)
    local inner_h = math.max(1, max_h - border * 2)

    local w, h = inner_w, inner_h
    if book.cover_w and book.cover_h and book.cover_w > 0 and book.cover_h > 0 then
        local ratio = book.cover_w / book.cover_h
        if ratio < w / h then
            w = math.floor(h * ratio)
        else
            h = math.floor(w / ratio)
        end
    end

    local img
    if book.has_real_cover and book.cover_bb then
        img = ImageWidget:new{
            image = book.cover_bb, width = w, height = h, scale_factor = 0,
        }
    else
        local ok_cover, Cover = pcall(require, "qui_cover")
        local bb
        if ok_cover and Cover.genCover then
            local ok_bb, cover_bb = pcall(Cover.genCover, book.path, w, h)
            if ok_bb and cover_bb then bb = cover_bb end
        end
        if not bb then
            bb = Blitbuffer.new(w, h, Blitbuffer.TYPE_BBRGB32)
            bb:fill(Blitbuffer.COLOR_LIGHT_GRAY)
        end
        img = ImageWidget:new{ image = bb, width = w, height = h }
    end

    if border > 0 then
        local frame_color = is_current
            and Blitbuffer.COLOR_BLACK
            or Blitbuffer.gray(0.6)
        return CenterContainer:new{
            dimen = Geom:new{ w = max_w, h = max_h },
            FrameContainer:new{
                bordersize = border,
                color = frame_color,
                background = Blitbuffer.COLOR_WHITE,
                margin = 0,
                padding = 0,
                CenterContainer:new{
                    dimen = Geom:new{ w = w, h = h },
                    img,
                },
            },
        }
    end

    return CenterContainer:new{
        dimen = Geom:new{ w = max_w, h = max_h },
        img,
    }
end

-- ------------------------------------------------------------
-- BookCell
-- ------------------------------------------------------------

local BookCell = InputContainer:extend{}

function BookCell:init()
    self.dimen = self.dimen or Geom:new{ w = self.width, h = self.height }
    self.ges_events = {
        HoldSelect = { GestureRange:new{ ges = "hold", range = self.dimen } },
    }
end

function BookCell:onHoldSelect()
    if self.hold_callback then self.hold_callback() end
    return true
end

-- ------------------------------------------------------------
-- Open / remove
-- ------------------------------------------------------------

function M.openBook(path, touch_menu)
    local ReaderUI = require("apps/reader/readerui")
    local FileManager = require("apps/filemanager/filemanager")
    local filemanagerutil = require("apps/filemanager/filemanagerutil")
    local ui = ReaderUI.instance or FileManager.instance
    if ui and type(filemanagerutil.openFile) == "function" then
        filemanagerutil.openFile(ui, path)
    else
        ReaderUI:showReader(path)
    end
end

function M.removeBook(path)
    local hidden = Utils.getTable("qa_panel_bs_hidden") or {}
    hidden[path] = true
    setCfg("qa_panel_bs_hidden", hidden)
end

-- ------------------------------------------------------------
-- buildPage(opts)
--   opts: width, padding, page, per_page, exclude_path,
--         touch_menu, on_remove, on_enable_toggle
-- Returns: widget, refs
-- ------------------------------------------------------------

function M.buildPage(opts)
    opts = opts or {}
    local Screen = Device.screen
    local panel_w = math.max(1, tonumber(opts.width) or Screen:getWidth())
    local pad = tonumber(opts.padding) or Screen:scaleBySize(8)
    local inner_w = panel_w - pad * 2
    local per_page = math.max(1, tonumber(opts.per_page) or 4)
    local page = math.max(1, tonumber(opts.page) or 1)

    local all = M.loadBooks(M.MAX_BOOKS, opts.exclude_path)
    local total = #all

    -- slice [page] window
    -- Reverse the slice so page 1 shows the oldest books and the last
    -- page shows the most recent ones. This makes the bs page group read
    -- [bs oldest] ... [bs newest] when it follows the button pages.
    local total_pages = math.max(1, math.ceil(total / per_page))
    local real_page = total_pages - page + 1
    local first = (real_page - 1) * per_page + 1
    local last  = math.min(first + per_page - 1, total)
    local books = {}
    for i = first, last do books[#books + 1] = all[i] end

    local vg = VerticalGroup:new{ align = "center" }
    local refs = { buttons = {} }

    if #books == 0 then
        vg[#vg + 1] = VerticalSpan:new{ width = Screen:scaleBySize(24) }
        vg[#vg + 1] = TextWidget:new{
            text = _("No books to switch to"),
            face = Utils.getFontFace("cfont", Screen:scaleBySize(14)),
            fgcolor = Blitbuffer.gray(0.5),
        }
        vg[#vg + 1] = VerticalSpan:new{ width = Screen:scaleBySize(24) }
        return vg, refs
    end

    local gap = Screen:scaleBySize(8)
    local columns = math.max(1, per_page)
    local cell_w = math.floor((inner_w - gap * (columns - 1)) / columns)

    local ratio_str = Utils.getString("cover_ratio", "3:4")
    local ratio = Utils.parseAspectRatio(ratio_str)
    if not ratio or ratio <= 0 then ratio = 3 / 4 end

    local border = Screen:scaleBySize(1)
    local cover_max_w = math.max(18, cell_w - border * 2)
    local cover_max_h = math.floor(cover_max_w / ratio)
    local cell_h = cover_max_h + border * 2

    local row = nil
    for i, book in ipairs(books) do
        if (i - 1) % columns == 0 then
            if row then
                vg[#vg + 1] = row
                vg[#vg + 1] = VerticalSpan:new{ width = gap }
            end
            row = HorizontalGroup:new{ align = "center" }
        else
            row[#row + 1] = HorizontalSpan:new{ width = gap }
        end

        local RUI = require("apps/reader/readerui")
        local reader = RUI and RUI.instance
        local current_path = reader and reader.document and reader.document.file
        local is_current = current_path and book.path == current_path

        local cover = makeCover(book,
            cover_max_w + border * 2,
            cover_max_h + border * 2,
            border, is_current)
        local content = CenterContainer:new{
            dimen = Geom:new{ w = cell_w, h = cell_h },
            cover,
        }

        local callback
        if is_current then
            callback = function()
                local filemanagerutil = require("apps/filemanager/filemanagerutil")
                local BookList = require("ui/widget/booklist")
                local doc_settings = BookList.getDocSettings(book.path)
                local book_props = doc_settings:readSetting("doc_props") or {}
                local btn = filemanagerutil.genBookInformationButton(
                    doc_settings, book_props, function() end, true)
                if btn and btn.callback then
                    btn.callback()
                end
            end
        else
            callback = function()
                M.openBook(book.path, opts.touch_menu)
            end
        end
        local hold_callback = function()
            local ButtonDialog = require("ui/widget/buttondialog")
            local dlg
            dlg = ButtonDialog:new{
                buttons = {{
                    {
                        text = "✕  " .. _("Remove"),
                        align = "left",
                        callback = function()
                            UIManager:close(dlg)
                            M.removeBook(book.path)
                            if opts.on_remove then opts.on_remove() end
                        end,
                    },
                }},
            }
            UIManager:show(dlg)
        end

        local cell = BookCell:new{
            width = cell_w, height = cell_h,
            dimen = Geom:new{ w = cell_w, h = cell_h },
            callback = callback, hold_callback = hold_callback, content,
        }
        row[#row + 1] = cell
        refs.buttons[#refs.buttons + 1] = {
            widget = cell, callback = callback, hold_callback = hold_callback,
        }
    end
    if row then
        local used = 0
        for _i, child in ipairs(row) do
            used = used + child:getSize().w
        end
        local pad_w = math.max(0, inner_w - used)
        if pad_w > 0 then
            row[#row + 1] = HorizontalSpan:new{ width = pad_w }
        end
        vg[#vg + 1] = row
    end

    return vg, refs
end

-- ------------------------------------------------------------
-- Pagination info helpers for qa_panel
-- ------------------------------------------------------------

function M.pageCount(exclude_path, per_page)
    local all = M.loadBooks(M.MAX_BOOKS, exclude_path)
    per_page = math.max(1, tonumber(per_page) or 4)
    return math.max(1, math.ceil(#all / per_page)), #all
end

function M.isEnabled()
    return cfg("qa_panel_bs_enabled", false) == true
end

return M
