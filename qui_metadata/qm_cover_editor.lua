--[[
QuickUI - Cover Editor

Pick a cover for the current book:
  1. From a local image file (PathChooser)
  2. From an online metadata source (reuses the metadata provider list)

Online candidates are downloaded to settings/quickui/covers/, shown in a
grid, and the tapped one is copied into the book's .sdr as cover.<ext>.
]]

local ButtonDialog    = require("ui/widget/buttondialog")
local InfoMessage     = require("ui/widget/infomessage")
local Notification    = require("ui/widget/notification")
local PathChooser     = require("ui/widget/pathchooser")
local DocumentRegistry= require("document/documentregistry")
local Screen          = require("device").screen
local Device          = require("device")
local UIManager       = require("ui/uimanager")
local Event           = require("ui/event")
local _               = require("gettext")
local logger          = require("logger")

local Blitbuffer      = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local LeftContainer   = require("ui/widget/container/leftcontainer")
local FrameContainer  = require("ui/widget/container/framecontainer")
local Geom            = require("ui/geometry")
local GestureRange    = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local ImageWidget     = require("ui/widget/imagewidget")
local InputContainer  = require("ui/widget/container/inputcontainer")
local OverlapGroup    = require("ui/widget/overlapgroup")
local TextWidget      = require("ui/widget/textwidget")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local Font            = require("ui/font")
local DataStorage     = require("datastorage")
local lfs             = require("libs/libkoreader-lfs")
local ffiutil         = require("ffi/util")
local util            = require("util")

local Http = require("qui_metadata.qm_http")

local M = {}

-- Same provider list as qm_provider_picker.lua.
local PROVIDERS = {
    { id = "douban",       name = _("Douban"),       key_config = nil,                          require_key = false },
    { id = "weread",       name = _("WeRead"),       key_config = "metadata_weread_key",        require_key = true  },
    { id = "google_books", name = _("Google Books"), key_config = "metadata_google_books_key",  require_key = true  },
    { id = "hardcover",    name = _("Hardcover"),    key_config = "metadata_hardcover_token",   require_key = true  },
    { id = "open_library", name = _("Open Library"), key_config = nil,                          require_key = false },
}

local MAX_CANDIDATES = 10

local function get_config()
    return _G.__QUICKUI_CONFIG or {}
end

local function provider_key(provider)
    if not provider.key_config then return true end
    local key = get_config()[provider.key_config]
    if type(key) ~= "string" or key == "" then return nil end
    return key
end

local function provider_module(provider)
    return require("qui_metadata.qm_" .. provider.id)
end

local function cover_cache_dir()
    local dir = DataStorage:getSettingsDir() .. "/quickui/covers"
    util.makePath(dir)
    return dir
end

local function clear_cache_dir()
    local dir = cover_cache_dir()
    local ok_iter, iter, dobj = pcall(lfs.dir, dir)
    if not ok_iter then return end
    for f in iter, dobj do
        if f ~= "." and f ~= ".." then
            os.remove(dir .. "/" .. f)
        end
    end
end

local function is_image_file(path)
    local f = io.open(path, "rb")
    if not f then return false end
    local magic = f:read(8)
    f:close()
    if not magic or #magic < 4 then return false end
    if magic:sub(1, 3) == "\xFF\xD8\xFF" then return true end
    if magic:sub(1, 4) == "\x89PNG" then return true end
    if magic:sub(1, 3) == "GIF" then return true end
    if magic:sub(1, 4) == "RIFF" and magic:sub(5, 8) == "WEBP" then return true end
    return false
end

-- ============================================================
-- Entry
-- ============================================================

function M.show(editor)
    local dialog
    dialog = ButtonDialog:new{
        title = _("Edit cover"),
        title_align = "center",
        buttons = {
            {{
                text = _("Select from device"),
                callback = function()
                    UIManager:close(dialog)
                    M.pick_from_device(editor)
                end,
            }},
            {{
                text = _("Search online"),
                callback = function()
                    UIManager:close(dialog)
                    M.search_online(editor)
                end,
            }},
            {{
                text = _("Remove custom cover"),
                callback = function()
                    UIManager:close(dialog)
                    M.remove_cover(editor)
                end,
            }},
            {},
            {{
                text = "◂ " .. _("Back"),
                callback = function()
                    UIManager:close(dialog)
                    UIManager:nextTick(function() editor:show_menu() end)
                end,
            }},
        },
        width = math.floor(Screen:getWidth() * 0.7),
    }
    UIManager:show(dialog)
end

-- ============================================================
-- Remove custom cover
-- ============================================================

function M.remove_cover(editor)
    local DocSettings = require("docsettings")
    local cover = DocSettings:findCustomCoverFile(editor.file)
    if not cover then
        UIManager:show(InfoMessage:new{
            text = _("No custom cover to remove."),
            timeout = 2,
        })
        UIManager:nextTick(function() editor:show_menu() end)
        return
    end
    local ok = os.remove(cover)
    if not ok then
        UIManager:show(InfoMessage:new{
            text = _("Failed to remove cover."),
            timeout = 3,
        })
        return
    end
    pcall(function() DocSettings:getCustomCoverFile(true) end)

    UIManager:broadcastEvent(Event:new("InvalidateMetadataCache", editor.file))
    UIManager:broadcastEvent(Event:new("BookMetadataChanged"))

    UIManager:show(Notification:new{
        text = _("Custom cover removed"),
        timeout = 2,
    })
    UIManager:nextTick(function() editor:show_menu() end)
end

-- ============================================================
-- From device
-- ============================================================

function M.pick_from_device(editor)
    local chooser = PathChooser:new{
        select_directory = false,
        file_filter = function(filename)
            return DocumentRegistry:isImageFile(filename)
        end,
        onConfirm = function(image_file)
            M.apply_cover(editor, image_file)
        end,
        onCancel = function()
            UIManager:nextTick(function() M.show(editor) end)
        end,
    }
    UIManager:show(chooser)
end

-- ============================================================
-- Online: pick a provider
-- ============================================================

function M.search_online(editor)
    local buttons = {}
    for _i, p in ipairs(PROVIDERS) do
        local _p = p
        local has_key = (provider_key(p) ~= nil)
        local display = p.name
        if p.key_config and not has_key then
            display = p.name .. "  (" .. _("API key required") .. ")"
        end
        table.insert(buttons, {{
            text = display,
            callback = function()
                UIManager:close(editor.dialog)
                if not has_key then
                    UIManager:nextTick(function()
                        UIManager:show(InfoMessage:new{
                            text = string.format(
                                _("%s requires an API key.\n\nSet it in QuickUI Settings → Metadata Settings → Provider API Keys."),
                                _p.name),
                            timeout = 5,
                        })
                    end)
                else
                    UIManager:nextTick(function() M.do_search(editor, _p) end)
                end
            end,
        }})
    end
    table.insert(buttons, {})
    table.insert(buttons, {{
        text = "◂ " .. _("Back"),
        callback = function()
            UIManager:close(editor.dialog)
            UIManager:nextTick(function() M.show(editor) end)
        end,
    }})

    editor.dialog = ButtonDialog:new{
        title = _("Select a source"),
        title_align = "center",
        buttons = buttons,
        width = math.floor(Screen:getWidth() * 0.7),
    }
    UIManager:show(editor.dialog)
end

-- ============================================================
-- Search
-- ============================================================

function M.do_search(editor, provider)
    local key = provider_key(provider)
    if not key then
        UIManager:show(InfoMessage:new{
            text = _("This provider requires an API key."),
            timeout = 3,
        })
        return
    end

    local Mod = provider_module(provider)
    local input = {
        title = editor.draft.title,
        authors = editor.draft.authors,
        author = editor.draft.authors and editor.draft.authors[1],
        isbn = editor.draft.isbn,
        limit = 10,
    }
    if (not input.title or input.title == "")
            and (not input.isbn or input.isbn == "") then
        UIManager:show(InfoMessage:new{
            text = _("Enter a title or ISBN first."),
            timeout = 3,
        })
        return
    end

    UIManager:show(Notification:new{
        text = _("Searching ") .. provider.name .. "...",
        timeout = 1,
    })

    UIManager:scheduleIn(0.1, function()
        local ok, works, err = pcall(Mod.search, key, input)
        if not ok then
            logger.warn("QuickUI cover search crashed:", works)
            UIManager:show(InfoMessage:new{
                text = _("Search failed"),
                timeout = 3,
            })
            return
        end
        if not works or #works == 0 then
            local msg = _("No match found")
            if err and err.kind then msg = msg .. " (" .. tostring(err.kind) .. ")" end
            UIManager:show(InfoMessage:new{ text = msg, timeout = 3 })
            return
        end
        M.download_candidates(editor, provider, works)
    end)
end

-- ============================================================
-- Download all candidates
-- ============================================================

local function result_label(work, edition)
    local title = (edition and edition.title ~= "" and edition.title) or work.title or ""
    local authors = ""
    if type(work.authors) == "table" and #work.authors > 0 then
        authors = table.concat(work.authors, ", ")
    end
    local year = (edition and edition.release_year) or work.release_year
    local parts = {}
    if authors ~= "" then parts[#parts + 1] = authors end
    if year then parts[#parts + 1] = tostring(year) end
    if #parts > 0 then
        return title .. " - " .. table.concat(parts, ", ")
    end
    return title
end

function M.download_candidates(editor, provider, works)
    local key = provider_key(provider)
    local Mod = provider_module(provider)

    clear_cache_dir()
    local cache_dir = cover_cache_dir()

    UIManager:show(Notification:new{
        text = _("Downloading covers..."),
        timeout = 1,
    })

    UIManager:scheduleIn(0.1, function()
        local covers = {}
        local count = 0
        local ts = os.time()

        for _i, work in ipairs(works) do
            if count >= MAX_CANDIDATES then break end

            local edition
            local ok_e, editions = pcall(Mod.editions, key, work)
            if ok_e and type(editions) == "table" and #editions > 0 then
                edition = editions[1]
            end

            local url = Mod.cover_url and Mod.cover_url(work) or nil
            if url and url ~= "" then
                local ext = url:match("%.([pP][nN][gG])[%?%#]?$") and "png" or "jpg"
                local dest = cache_dir .. "/" .. ts .. "_" .. count .. "." .. ext
                local host = url:match("^https://([^/]+)")
                if host then
                    local referer = Mod.cover_referer or ("https://" .. host .. "/")
                    local path = Http.download(url, dest, host, {
                        ["Referer"] = referer,
                        ["Accept"] = "image/jpeg, image/png, image/webp, image/gif",
                    })
                    if path and is_image_file(path) then
                        covers[#covers + 1] = {
                            path = path,
                            label = result_label(work, edition),
                        }
                        count = count + 1
                    elseif path then
                        os.remove(path)
                    end
                end
            end
        end

        if #covers == 0 then
            UIManager:show(InfoMessage:new{
                text = _("No covers could be downloaded."),
                timeout = 3,
            })
            return
        end

        M.show_cover_grid(editor, covers)
    end)
end

-- ============================================================
-- Cover grid
-- ============================================================

function M.show_cover_grid(editor, covers)
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    local pad = Screen:scaleBySize(16)
    local brd = Screen:scaleBySize(1)

    local frame_w = math.floor(sw * 0.92)
    local frame_h = math.floor(sh * 0.88)
    local content_w = frame_w - 2 * pad - 2 * brd

    local aspect = sw / sh
    local cols
    if aspect <= 0.62 then cols = 4
    elseif aspect <= 0.75 then cols = 4
    else cols = 5 end

    local h_gap = Screen:scaleBySize(12)
    local v_gap = Screen:scaleBySize(12)
    local cell_w = math.floor((content_w - (cols - 1) * h_gap) / cols)

    local TITLE_H = Screen:scaleBySize(50)
    local PAGER_H = Screen:scaleBySize(44)
    local V_GAP   = Screen:scaleBySize(10)
    local grid_h = frame_h - 2 * pad - TITLE_H - PAGER_H - 2 * V_GAP

    local CELL_PAD = Screen:scaleBySize(2)
    local LABEL_GAP = Screen:scaleBySize(2)

    -- 测标签真实高度
    local probe_label = TextWidget:new{
        text = "Ag",
        face = Font:getFace("cfont", 13),
        padding = 0,
    }
    local LABEL_H = probe_label:getSize().h
    probe_label:free()

    -- 内容区宽度（cell 去掉 padding + border 后）
    local inner_w = cell_w - 2 * CELL_PAD - 2 * brd

    -- 图片 3:4，宽度 = 内容区宽度
    local img_w = inner_w
    local img_h = math.floor(img_w * 4 / 3)
    local cell_h = img_h + LABEL_H + LABEL_GAP + 2 * CELL_PAD

    -- 行数自动：grid_h 放得下几行就几行
    local rows = math.max(1, math.floor((grid_h + v_gap) / (cell_h + v_gap)))
    local per_page = cols * rows

    local cur_page = 1
    local total_pages = math.max(1, math.ceil(#covers / per_page))

    local dialog = nil
    local grid_container = nil
    local pagination_container = nil

    local function buildCell(c)
        local img = ImageWidget:new{
            file = c.path,
            width = img_w,
            height = img_h,
            scale_factor = 0,
            image_disposable = true,
        }

        local img_box = FrameContainer:new{
            width = inner_w,
            height = img_h,
            bordersize = 0,
            padding = 0,
            background = Blitbuffer.COLOR_WHITE,
            CenterContainer:new{
                dimen = Geom:new{ w = inner_w, h = img_h },
                img,
            },
        }

        local label = TextWidget:new{
            text = c.label or "",
            face = Font:getFace("cfont", 13),
            fgcolor = Blitbuffer.COLOR_BLACK,
            max_width = inner_w,
            padding = 0,
            truncate_with_ellipsis = true,
        }

        local cell_content = VerticalGroup:new{
            align = "center",
            img_box,
            VerticalSpan:new{ width = LABEL_GAP },
            label,
        }

        local cell = FrameContainer:new{
            width = cell_w,
            height = cell_h,
            bordersize = brd,
            color = Blitbuffer.COLOR_LIGHT_GRAY,
            background = Blitbuffer.COLOR_WHITE,
            radius = Screen:scaleBySize(4),
            padding = CELL_PAD,
            cell_content,
        }

        local ic = InputContainer:new{
            dimen = Geom:new{ w = cell_w, h = cell_h },
            cell,
        }
        ic.ges_events = {
            TapSelect = { GestureRange:new{ ges = "tap", range = ic.dimen } },
        }
        ic.onTapSelect = function()
            UIManager:close(dialog)
            UIManager:setDirty("all", "full")
            M.apply_cover(editor, c.path)
            return true
        end
        return ic
    end

    local refreshGrid
    local goToPage

    local function buildPage(page_num)
        local page_vg = VerticalGroup:new{ align = "center" }
        local start_idx = (page_num - 1) * per_page + 1
        for row = 0, rows - 1 do
            local row_hg = HorizontalGroup:new{ align = "top" }
            for col = 0, cols - 1 do
                local idx = start_idx + row * cols + col
                local c = covers[idx]
                if c then
                    table.insert(row_hg, buildCell(c))
                else
                    table.insert(row_hg, HorizontalSpan:new{ width = cell_w })
                end
                if col < cols - 1 then
                    table.insert(row_hg, HorizontalSpan:new{ width = h_gap })
                end
            end
            table.insert(page_vg, row_hg)
            if row < rows - 1 then
                table.insert(page_vg, VerticalSpan:new{ width = v_gap })
            end
        end
        return page_vg
    end

    local function buildPager()
        local btn_w = Screen:scaleBySize(60)
        local prev_enabled = cur_page > 1
        local next_enabled = cur_page < total_pages

        local prev_btn = require("ui/widget/button"):new{
            text = "◂",
            width = btn_w,
            enabled = prev_enabled,
            callback = function() goToPage(cur_page - 1) end,
        }
        local next_btn = require("ui/widget/button"):new{
            text = "▸",
            width = btn_w,
            enabled = next_enabled,
            callback = function() goToPage(cur_page + 1) end,
        }
        local page_label = TextWidget:new{
            text = string.format("%d / %d", cur_page, total_pages),
            face = Font:getFace("cfont", 15),
        }
        return HorizontalGroup:new{
            align = "center",
            prev_btn,
            HorizontalSpan:new{ width = Screen:scaleBySize(20) },
            page_label,
            HorizontalSpan:new{ width = Screen:scaleBySize(20) },
            next_btn,
        }
    end

    refreshGrid = function()
        grid_container[1] = CenterContainer:new{
            dimen = Geom:new{ w = content_w, h = grid_h },
            buildPage(cur_page),
        }
        pagination_container[1] = buildPager()
        UIManager:setDirty(dialog, function() return "ui", dialog.dimen end)
    end

    goToPage = function(p)
        if p < 1 or p > total_pages then return end
        cur_page = p
        refreshGrid()
    end

    -- 标题栏：标题居中，返回按钮浮在左边
    local back_btn = require("ui/widget/button"):new{
        text = "◂ " .. _("Back"),
        callback = function()
            UIManager:close(dialog)
            UIManager:setDirty("all", "full")
            UIManager:nextTick(function() M.search_online(editor) end)
        end,
    }

    local title_label = CenterContainer:new{
        dimen = Geom:new{ w = content_w, h = TITLE_H },
        TextWidget:new{
            text = _("Select a cover"),
            face = Font:getFace("smallinfofont"),
            bold = true,
        },
    }

    local title_widget = OverlapGroup:new{
        dimen = Geom:new{ w = content_w, h = TITLE_H },
        allow_mirroring = false,
        title_label,
        LeftContainer:new{
            dimen = Geom:new{ w = content_w, h = TITLE_H },
            back_btn,
        },
    }

    grid_container = CenterContainer:new{
        dimen = Geom:new{ w = content_w, h = grid_h },
    }
    pagination_container = CenterContainer:new{
        dimen = Geom:new{ w = content_w, h = PAGER_H },
    }

    local inner_frame = FrameContainer:new{
        width = frame_w,
        height = frame_h,
        background = Blitbuffer.COLOR_WHITE,
        bordersize = brd,
        radius = Screen:scaleBySize(8),
        padding = pad,
        VerticalGroup:new{
            align = "center",
            title_widget,
            VerticalSpan:new{ width = V_GAP },
            grid_container,
            VerticalSpan:new{ width = V_GAP },
            pagination_container,
        },
    }

    local PickerDlg = InputContainer:extend{ is_always_active = true }
    function PickerDlg:init()
        self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
        self[1] = CenterContainer:new{
            dimen = Geom:new{ w = sw, h = sh },
            inner_frame,
        }
        if Device:isTouchDevice() then
            self.ges_events.Tap = {
                GestureRange:new{ ges = "tap", range = self.dimen },
            }
        end
    end
    function PickerDlg:onTap(arg, ges)
        if ges.pos:notIntersectWith(inner_frame.dimen) then
            UIManager:close(self)
            UIManager:setDirty("all", "full")
        end
        return true
    end

    dialog = PickerDlg:new{}
    UIManager:show(dialog, "full")
    refreshGrid()
end

-- ============================================================
-- Apply
-- ============================================================

function M.apply_cover(editor, image_path)
    local DocSettings = require("docsettings")

    if lfs.attributes(image_path, "mode") ~= "file" then
        UIManager:show(InfoMessage:new{
            text = _("Cover image not found."), timeout = 3,
        })
        return
    end

    local dir = DocSettings:getSidecarDir(editor.file)
    if not dir then
        UIManager:show(InfoMessage:new{
            text = _("Failed to set cover (no sidecar dir)."), timeout = 3,
        })
        return
    end
    util.makePath(dir)

    -- 删旧 cover.*（保留 cover.orig.*）
    local ok_iter, iter, dobj = pcall(lfs.dir, dir)
    if ok_iter then
        for f in iter, dobj do
            if f:match("^cover%.[^.]+$") then
                os.remove(dir .. "/" .. f)
            end
        end
    end
    pcall(function() DocSettings:getCustomCoverFile(true) end)

    -- 复制新封面
    local ext = image_path:match("%.([^.]+)$") or "jpg"
    local dest = dir .. "/cover." .. ext:lower()
    ffiutil.copyFile(image_path, dest)

    local attr = lfs.attributes(dest)
    if not attr or attr.mode ~= "file" or attr.size == 0 then
        UIManager:show(InfoMessage:new{
            text = _("Failed to set cover."), timeout = 3,
        })
        return
    end

    pcall(function() DocSettings:getCustomCoverFile(true) end)

    UIManager:broadcastEvent(Event:new("InvalidateMetadataCache", editor.file))
    UIManager:broadcastEvent(Event:new("BookMetadataChanged"))
    UIManager:show(Notification:new{
        text = _("Cover updated"), timeout = 2,
    })
    editor:close()
end

return M
