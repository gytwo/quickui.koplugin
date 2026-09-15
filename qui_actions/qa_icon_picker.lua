--[[
QuickUI - Icon Picker and Icon Management

Provides icon selection UI, Nerd Font support, file icon scanning,
and system icon override patching.

Original: 2-quickactions.lua (icon picker related functions)
]]

local logger = require("logger")
local _ = require("gettext")
local Blitbuffer = require("ffi/blitbuffer")
local Font = require("ui/font")
local Screen = require("device").screen
local Device = require("device")
local Geom = require("ui/geometry")
local UIManager = require("ui/uimanager")
local BD = require("ui/bidi")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")
local ffi = require("ffi")

local CenterContainer = require("ui/widget/container/centercontainer")
local TopContainer = require("ui/widget/container/topcontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local ImageWidget = require("ui/widget/imagewidget")
local TextWidget = require("ui/widget/textwidget")
local IconWidget = require("ui/widget/iconwidget")
local PathChooser = require("ui/widget/pathchooser")
local Notification = require("ui/widget/notification")
local Button = require("ui/widget/button")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputText = require("ui/widget/inputtext")
local Size = require("ui/size")
local Menu = require("ui/widget/menu")

local Utils = require("qui_utils")

-- ============================================================
-- Global storage
-- ============================================================

local QA = {}

-- Cache
local picker_cache = {}
local cached_file_icons = nil
local system_temp_overrides = nil

-- ============================================================
-- Constants
-- ============================================================

local THUMB_SIZE = Screen:scaleBySize(32)
local THUMB_GAP = Screen:scaleBySize(6)

-- ============================================================
-- Configuration 
-- ============================================================
-- Empty init to satisfy qa_init.lua's module loading pattern
function QA.init(plugin) end

local function getSystemTempOverrides()
    if system_temp_overrides == nil then
        system_temp_overrides = {}
        local saved = Utils.getTable("qa_common_icon_overrides")
        for k, v in pairs(saved) do
            system_temp_overrides[k] = v
        end
    end
    return system_temp_overrides
end

local function resetSystemTempOverrides()
    system_temp_overrides = nil
end

-- ============================================================
-- Nerd Font glyph-name reader (pure LuaJIT, no FreeType)
--
-- Android's bundled libfreetype does not export FT_Get_Glyph_Name,
-- so we parse the TTF binary ourselves:
--   offset table -> table directory -> post (2.0) -> cmap (4 / 12)
-- This yields { codepoint -> glyph name } at runtime, on all platforms.
-- ============================================================

-- Standard Macintosh glyph order (PostScript names for 0-257).
-- post table 2.0: glyphNameIndex < 258 refers to this list by position.
local MAC_GLYPH_NAMES = {
    ".notdef", ".null", "nonmarkingreturn", "space", "exclam", "quotedbl",
    "numbersign", "dollar", "percent", "ampersand", "quotesingle",
    "parenleft", "parenright", "asterisk", "plus", "comma", "hyphen",
    "period", "slash", "zero", "one", "two", "three", "four", "five",
    "six", "seven", "eight", "nine", "colon", "semicolon", "less",
    "equal", "greater", "question", "at", "A", "B", "C", "D", "E", "F",
    "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S",
    "T", "U", "V", "W", "X", "Y", "Z", "bracketleft", "backslash",
    "bracketright", "asciicircum", "underscore", "grave", "a", "b",
    "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o",
    "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z", "braceleft",
    "bar", "braceright", "asciitilde", "Adieresis", "Aring", "Ccedilla",
    "Eacute", "Ntilde", "Odieresis", "Udieresis", "aacute", "agrave",
    "acircumflex", "adieresis", "atilde", "aring", "ccedilla", "eacute",
    "egrave", "ecircumflex", "edieresis", "iacute", "igrave",
    "icircumflex", "idieresis", "ntilde", "oacute", "ograve",
    "ocircumflex", "odieresis", "otilde", "uacute", "ugrave",
    "ucircumflex", "udieresis", "dagger", "degree", "cent", "sterling",
    "section", "bullet", "paragraph", "germandbls", "registered",
    "copyright", "trademark", "acute", "dieresis", "notequal", "AE",
    "Oslash", "infinity", "plusminus", "lessequal", "greaterequal",
    "yen", "mu", "partialdiff", "summation", "product", "pi",
    "integral", "ordfeminine", "ordmasculine", "Omega", "ae", "oslash",
    "questiondown", "exclamdown", "logicalnot", "radical", "florin",
    "approxequal", "Delta", "guillemotleft", "guillemotright",
    "ellipsis", "nonbreakingspace", "Agrave", "Atilde", "Otilde", "OE",
    "oe", "endash", "emdash", "quotedblleft", "quotedblright",
    "quoteleft", "quoteright", "divide", "lozenge", "ydieresis",
    "Ydieresis", "fraction", "currency", "guilsinglleft",
    "guilsinglright", "fi", "fl", "daggerdbl", "periodcentered",
    "quotesinglbase", "quotedblbase", "perthousand", "Acircumflex",
    "Ecircumflex", "Aacute", "Edieresis", "Egrave", "Iacute",
    "Icircumflex", "Idieresis", "Igrave", "Oacute", "Ocircumflex",
    "apple", "Ograve", "Uacute", "Ucircumflex", "Ugrave", "dotlessi",
    "circumflex", "tilde", "macron", "breve", "dotaccent", "ring",
    "cedilla", "hungarumlaut", "ogonek", "caron", "Lslash", "lslash",
    "Scaron", "scaron", "Zcaron", "zcaron", "brokenbar", "Eth", "eth",
    "Yacute", "yacute", "Thorn", "thorn", "minus", "multiply",
    "onesuperior", "twosuperior", "threesuperior", "onehalf",
    "onequarter", "threequarters", "franc", "Gbreve", "gbreve",
    "Idotaccent", "Scedilla", "scedilla", "Cacute", "cacute", "Ccaron",
    "ccaron", "dcroat",
}

local function _readFile(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local data = f:read("*all")
    f:close()
    if not data or #data < 12 then return nil end
    return data
end

local function _u16(data, off)
    local b1, b2 = data:byte(off, off + 1)
    if not b1 or not b2 then return nil end
    return b1 * 256 + b2
end

local function _u32(data, off)
    local b1, b2, b3, b4 = data:byte(off, off + 3)
    if not b1 or not b4 then return nil end
    return ((b1 * 256 + b2) * 256 + b3) * 256 + b4
end

local function _readTableDirectory(data)
    local numTables = _u16(data, 5)
    if not numTables then return nil end
    local tables = {}
    local pos = 13
    for _ = 1, numTables do
        local tag = data:sub(pos, pos + 3)
        local offset = _u32(data, pos + 8)
        local length = _u32(data, pos + 12)
        if tag and offset and length then
            tables[tag] = { offset = offset + 1, length = length }
        end
        pos = pos + 16
    end
    return tables
end

local function _parsePostTable(data, post_off)
    local version = _u32(data, post_off)
    if version ~= 0x00020000 then
        logger.warn("QuickUI NerdFont: post table is not 2.0 (version=" ..
            string.format("0x%08X", version) .. ")")
        return nil
    end
    local numGlyphs = _u16(data, post_off + 32)
    if not numGlyphs or numGlyphs == 0 then return nil end

    local index_base = post_off + 34
    local names_base = index_base + numGlyphs * 2

    local indices = {}
    local max_extra_index = 0
    for i = 0, numGlyphs - 1 do
        local idx = _u16(data, index_base + i * 2)
        indices[i] = idx
        if idx and idx >= 258 then
            local rel = idx - 258
            if rel > max_extra_index then max_extra_index = rel end
        end
    end

    local extra_names = {}
    local pos = names_base
    for _ = 0, max_extra_index do
        local len = data:byte(pos)
        if not len then break end
        extra_names[#extra_names + 1] = data:sub(pos + 1, pos + len)
        pos = pos + 1 + len
    end

    local glyph_names = {}
    for i = 0, numGlyphs - 1 do
        local idx = indices[i]
        if idx then
            if idx < 258 then
                glyph_names[i] = MAC_GLYPH_NAMES[idx + 1]
            else
                glyph_names[i] = extra_names[idx - 258 + 1]
            end
        end
    end
    return glyph_names
end

local function _parseCmapSubtable4(data, base)
    local segCountX2 = _u16(data, base + 6)
    if not segCountX2 then return nil end
    local segCount = segCountX2 / 2
    local endBase = base + 14
    local startBase = endBase + segCountX2 + 2
    local deltaBase = startBase + segCountX2
    local rangeBase = deltaBase + segCountX2

    local map = {}
    for i = 0, segCount - 1 do
        local endCode = _u16(data, endBase + i * 2)
        local startCode = _u16(data, startBase + i * 2)
        local idDelta = _u16(data, deltaBase + i * 2)
        local idRangeOffset = _u16(data, rangeBase + i * 2)
        if startCode and endCode and startCode <= endCode then
            for cp = startCode, endCode do
                if cp ~= 0xFFFF then
                    local gid
                    if idRangeOffset == 0 then
                        gid = (cp + idDelta) % 65536
                    else
                        local ro_addr = rangeBase + i * 2 + idRangeOffset + (cp - startCode) * 2
                        local raw = _u16(data, ro_addr)
                        if raw and raw ~= 0 then
                            gid = (raw + idDelta) % 65536
                        end
                    end
                    if gid and gid ~= 0 then
                        map[cp] = gid
                    end
                end
            end
        end
    end
    return map
end

local function _parseCmapSubtable12(data, base)
    local nGroups = _u32(data, base + 12)
    if not nGroups then return nil end
    local map = {}
    local pos = base + 16
    for _ = 1, nGroups do
        local startChar = _u32(data, pos)
        local endChar = _u32(data, pos + 4)
        local startGid = _u32(data, pos + 8)
        if startChar and endChar then
            for cp = startChar, endChar do
                map[cp] = startGid + (cp - startChar)
            end
        end
        pos = pos + 12
    end
    return map
end

local function _parseCmapTable(data, cmap_off)
    local numTables = _u16(data, cmap_off + 2)
    if not numTables then return nil end
    local best, best_score = nil, -1
    for i = 0, numTables - 1 do
        local rec = cmap_off + 4 + i * 8
        local platformID = _u16(data, rec)
        local encodingID = _u16(data, rec + 2)
        local subOff = _u32(data, rec + 4)
        if platformID and subOff then
            local sub_base = cmap_off + subOff
            local fmt = _u16(data, sub_base)
            local score = -1
            if platformID == 3 and encodingID == 10 and fmt == 12 then
                score = 100
            elseif platformID == 3 and encodingID == 1 and fmt == 4 then
                score = 90
            elseif platformID == 0 and (fmt == 4 or fmt == 12) then
                score = 80
            end
            if score > best_score then
                best_score = score
                best = { base = sub_base, fmt = fmt }
            end
        end
    end
    if not best then return nil end
    if best.fmt == 4 then
        return _parseCmapSubtable4(data, best.base)
    elseif best.fmt == 12 then
        return _parseCmapSubtable12(data, best.base)
    end
    return nil
end

-- Locate KOReader's bundled Nerd Font file.
local function _findNerdFontFile()
    local candidates = {}
    local ok_ds, DataStorage = pcall(require, "datastorage")
    if ok_ds and DataStorage then
        local base = DataStorage:getDataDir()
        candidates[#candidates + 1] = base .. "/fonts/nerdfonts/symbols.ttf"
        candidates[#candidates + 1] = base .. "/fonts/symbols.ttf"
    end
    candidates[#candidates + 1] = "fonts/nerdfonts/symbols.ttf"
    candidates[#candidates + 1] = "./fonts/nerdfonts/symbols.ttf"
    for _i, p in ipairs(candidates) do
        if lfs.attributes(p, "mode") == "file" then return p end
    end
    return nil
end

-- Runtime cache: codepoint -> glyph name
local _nerd_glyph_names = nil

local function _ensureNerdGlyphNames()
    if _nerd_glyph_names then return _nerd_glyph_names end
    _nerd_glyph_names = {}
    local path = _findNerdFontFile()
    if not path then
        logger.warn("QuickUI NerdFont: symbols.ttf not found")
        return _nerd_glyph_names
    end
    local data = _readFile(path)
    if not data then return _nerd_glyph_names end
    local tables = _readTableDirectory(data)
    if not tables then return _nerd_glyph_names end
    local post = tables["post"]
    local cmap = tables["cmap"]
    if not post or not cmap then return _nerd_glyph_names end
    local glyph_names = _parsePostTable(data, post.offset)
    if not glyph_names then return _nerd_glyph_names end
    local cp_to_gid = _parseCmapTable(data, cmap.offset)
    if not cp_to_gid then return _nerd_glyph_names end
    for cp, gid in pairs(cp_to_gid) do
        local name = glyph_names[gid]
        if name and name ~= "" then
            _nerd_glyph_names[cp] = name
        end
    end
    return _nerd_glyph_names
end

-- ============================================================
-- Nerd Font Support
-- ============================================================

function QA.nerdIconChar(icon_value)
    if type(icon_value) ~= "string" then return nil end
    local hex = icon_value:match("^nerd:([0-9A-Fa-f]+)$")
    if not hex then return nil end
    local cp = tonumber(hex, 16)
    if not cp or cp < 0 or cp > 0x10FFFF then return nil end
    if cp < 0x80 then
        return string.char(cp)
    elseif cp < 0x800 then
        return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + (cp % 0x40))
    elseif cp < 0x10000 then
        return string.char(0xE0 + math.floor(cp / 0x1000), 0x80 + math.floor((cp % 0x1000) / 0x40), 0x80 + (cp % 0x40))
    else
        return string.char(0xF0 + math.floor(cp / 0x40000), 0x80 + math.floor((cp % 0x40000) / 0x1000),
                         0x80 + math.floor((cp % 0x1000) / 0x40), 0x80 + (cp % 0x40))
    end
end

function QA.isNerdIcon(icon_value)
    return QA.nerdIconChar(icon_value) ~= nil
end

local function getNerdGlyphName(cp)
    if not cp or type(cp) ~= "number" then return nil end
    local names = _ensureNerdGlyphNames()
    return names[cp]
end

local function getNerdIcons()
    local names = _ensureNerdGlyphNames()
    local icons = {}
    for cp, name in pairs(names) do
        local hex = string.format("%04X", cp)
        icons[#icons + 1] = {
            type = "nerd",
            hex = hex,
            value = "nerd:" .. hex,
            name = name,
        }
    end
    table.sort(icons, function(a, b)
        return (a.name or ""):lower() < (b.name or ""):lower()
    end)
    return icons
end

-- ============================================================
-- Icon Directory and File Scanning
-- ============================================================

function QA.getIconsDir()
    return Utils.getIconsDirPath()
end

local function scanAllIconDirs(mode)
    local all_files = {}
    local seen = {}

    local dirs_to_scan
    if mode == "system" then
        dirs_to_scan = { "resources/icons/mdlight" }
    else
        dirs_to_scan = {
            QA.getIconsDir(),
            "resources/icons/mdlight",
            "resources/icons",
            "resources",
        }
    end

    for _, dir in ipairs(dirs_to_scan) do
        if Utils.dirExists(dir) then
            for file in lfs.dir(dir) do
                if file ~= "." and file ~= ".." then
                    local ext = file:lower()
                    if ext:match("%.svg$") or ext:match("%.png$") then
                        local name = file:gsub("%.[^%.]+$", "")
                        if not seen[name] then
                            seen[name] = true
                            local path = dir .. "/" .. file
                            table.insert(all_files, {
                                path = path,
                                name = name,
                                display_name = name:gsub("_", " "),
                                ext = ext,
                                type = "file",
                            })
                        end
                    end
                end
            end
        end
    end

    return all_files
end

function QA.getFileIcons()
    if cached_file_icons == nil then
        cached_file_icons = scanAllIconDirs()
    end
    return cached_file_icons
end

function QA.clearFileIconsCache()
    picker_cache = {}
    cached_file_icons = nil
end

-- ============================================================
-- Get Icon Widget
-- ============================================================

function QA.getIconWidget(icon_path, size)
    size = size or Screen:scaleBySize(24)

    if QA.isNerdIcon(icon_path) then
        local nerd_char = QA.nerdIconChar(icon_path)
        if nerd_char then
            return TextWidget:new{
                text = nerd_char,
                face = Font:getFace("symbols", math.floor(size * 0.6)),
                fgcolor = Blitbuffer.COLOR_BLACK,
                padding = 0,
            }
        end
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
-- Icon Browser (file chooser for icons)
-- ============================================================

local _InnerIconChooser = PathChooser:extend{
    select_directory = false,
    select_file = true,
    state_w = THUMB_SIZE + THUMB_GAP,
    path = QA.getIconsDir(),
    onConfirm = nil,
    _filter_text = "",
    _all_items = nil,
    stop_events_propagation = true,
}

function _InnerIconChooser:init()
    self.title = _('Select Icon')
    self.file_filter = function(filename)
        local ext = filename:lower()
        return ext:match('%.svg$') ~= nil or ext:match('%.png$') ~= nil
    end
    self.state_w = THUMB_SIZE + THUMB_GAP
    PathChooser.init(self)
    if not self._all_items then
        self:refreshPath()
    end
end

function _InnerIconChooser:getCollate()
    return self.collates.strcoll, "strcoll"
end

function _InnerIconChooser:refreshPath()
    local _, folder_name = util.splitFilePathName(self.path)
    Screen:setWindowTitle(folder_name)
    self._all_items = self:genItemTableFromPath(self.path)
    self:_applyCurrentFilter()
end

function _InnerIconChooser:_applyCurrentFilter()
    local filter_text = self._filter_text or ""
    local items
    if filter_text == "" then
        items = self._all_items
    else
        items = {}
        local pattern = filter_text:lower()
        for _, item in ipairs(self._all_items) do
            if item.is_go_up or (item.text and item.text:lower():find(pattern, 1, true)) then
                table.insert(items, item)
            end
        end
    end
    local itemmatch
    if self.focused_path then
        itemmatch = {path = self.focused_path}
        self.focused_path = nil
    end
    local subtitle = BD.directory(require("apps/filemanager/filemanagerutil").abbreviate(self.path))
    self:switchItemTable(nil, items, filter_text == "" and self.path_items[self.path] or 1, itemmatch, subtitle)
end

function _InnerIconChooser:applyFilter(text)
    self._filter_text = text or ""
    if self._all_items then
        self:_applyCurrentFilter()
    end
end

function _InnerIconChooser:_recalculateDimen(no_recalculate_dimen)
    Menu._recalculateDimen(self, no_recalculate_dimen)
    if not self.item_dimen then return end
    if self._filter_bar_height and self._filter_bar_height > 0 and not no_recalculate_dimen then
        self.available_height = self.available_height - self._filter_bar_height
        self.item_dimen.h = math.floor(self.available_height / self.perpage)
    end
    local content_w = math.max(0, self.item_dimen.w - 2 * Size.padding.fullscreen)
    local max_state_w = math.max(1, math.floor(content_w / 4))
    local ts = THUMB_SIZE
    local tg = THUMB_GAP
    self.state_w = math.min(ts + tg, max_state_w)
    self._thumb_size = math.max(0, math.min(ts, self.state_w - tg))
end

function _InnerIconChooser:updateItems(select_number, no_recalculate_dimen)
    Menu.updateItems(self, select_number, no_recalculate_dimen)
    self.path_items[self.path] = (self.page - 1) * self.perpage + (select_number or 1)
    local eff_thumb = self._thumb_size or 0
    if eff_thumb <= 0 then return end
    local item_h = self.item_dimen and self.item_dimen.h or eff_thumb
    local center_y = math.max(0, math.floor((item_h - eff_thumb) / 2))
    for _, item_widget in ipairs(self.item_group) do
        local entry = item_widget.entry
        if not entry then goto continue end
        local filepath = entry.path or ""
        local ext = filepath:lower()
        if not (ext:match("%.svg$") or ext:match("%.png$")) then goto continue end
        local uc = item_widget._underline_container
        if not uc then goto continue end
        local hg = uc[1]
        if not hg then goto continue end
        local og = hg[1]
        if not og then goto continue end
        table.insert(og, 1, ImageWidget:new{
            file = filepath,
            width = eff_thumb,
            height = eff_thumb,
            alpha = true,
            overlap_offset = { 0, center_y },
        })
        og._size = nil
        ::continue::
    end
end

function _InnerIconChooser:onMenuSelect(item)
    local path = item.path or ""
    local ext = path:lower()
    if ext:match("%.svg$") or ext:match("%.png$") then
        if self.show_parent then
            self.show_parent:onClose()
        end
        if self.onConfirm then
            self.onConfirm(path)
        end
        return true
    end
    return PathChooser.onMenuSelect(self, item)
end

function _InnerIconChooser:onMenuHold(item)
    local path = item.path or ""
    local ext = path:lower()
    if ext:match("%.svg$") or ext:match("%.png$") then
        return true
    end
    return PathChooser.onMenuHold(self, item)
end

local IconBrowser = InputContainer:extend{
    path = QA.getIconsDir(),
    onConfirm = nil,
    is_always_active = true,
}

function IconBrowser:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    local paths_to_check = { self.path, "./resources/icons/mdlight", "./" }
    local final_path = nil
    for _, path in ipairs(paths_to_check) do
        if Utils.dirExists(path) then
            final_path = path
            break
        end
    end
    if not final_path then
        UIManager:show(InfoMessage:new{
            text = _("Cannot find icons directory"),
            timeout = 3,
        })
        return
    end
    self.path = final_path

    self._filter_input = InputText:new{
        text = "",
        hint = _("Filter by name..."),
        width = self.dimen.w - 4 * Size.padding.default,
        height = nil,
        face = Font:getFace("smallinfofont"),
        padding = Size.padding.small,
        margin = 0,
        bordersize = Size.border.inputtext,
        parent = self,
        scroll = false,
        focused = false,
        edit_callback = function()
            self:_applyFilter()
        end,
    }
    self._filter_input.addChars = function(inp, chars)
        if chars == "\n" then
            inp:onCloseKeyboard()
            return
        end
        InputText.addChars(inp, chars)
    end

    self._filter_bar = FrameContainer:new{
        padding = Size.padding.default,
        padding_top = Size.padding.small,
        padding_bottom = Size.padding.small,
        bordersize = 0,
        self._filter_input,
    }

    local filter_h = self._filter_bar:getSize().h
    self._chooser = _InnerIconChooser:new{
        show_parent = self,
        path = self.path,
        onConfirm = self.onConfirm,
        height = self.dimen.h,
        close_callback = function() self:onClose() end,
    }
    table.insert(self._chooser.content_group, 2, self._filter_bar)
    self._chooser._filter_bar_height = filter_h
    self._chooser:refreshPath()
    self[1] = self._chooser
end

function IconBrowser:_applyFilter()
    if not self._chooser then return end
    local text = self._filter_input and self._filter_input:getText() or ""
    self._chooser:applyFilter(text)
end

function IconBrowser:getFocusableWidgetXY()
    return nil, nil
end

function IconBrowser:onClose()
    if self._filter_input then
        self._filter_input:onCloseKeyboard()
    end
    UIManager:close(self)
end

-- ============================================================
-- Nerd Icon Preview
-- ============================================================

local function showNerdIconPreview(sentinel, on_select, on_cancel)
    local hex = sentinel:match("nerd:(.+)")
    UIManager:show(ConfirmBox:new{
        text = ("U+%s  %s"):format(hex, QA.nerdIconChar(sentinel)) .. "\n\n" .. _("Use this Nerd Font icon?"),
        ok_text = _("OK"),
        cancel_text = _("Back"),
        ok_callback = function()
            if on_select then on_select(sentinel) end
        end,
        cancel_callback = function()
            if on_cancel then on_cancel() end
        end,
    })
end

local function showNerdIconInput(current_icon, on_select)
    local current_hex = ""
    if current_icon then
        current_hex = current_icon:match("^nerd:([0-9A-Fa-f]+)$") or ""
    end

    local function openInputDlg()
        local dlg = InputDialog:new{
            title = _("Nerd Font Icon"),
            input = current_hex:upper(),
            input_hint = _("Hex codepoint, e.g. E001"),
            description = _("Enter the Unicode codepoint (hex) of a Nerd Font symbol."),
            buttons = {{
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(dlg)
                    end,
                },
                {
                    text = _("OK"),
                    is_enter_default = true,
                    callback = function()
                        local raw = dlg:getInputText()
                        if raw:match("^%s*$") then
                            UIManager:close(dlg)
                            if on_select then on_select(nil) end
                            return
                        end
                        local hex = raw:match("^%s*([0-9A-Fa-f]+)%s*$")
                        if hex and #hex >= 1 and #hex <= 6 then
                            local sentinel = "nerd:" .. hex:upper()
                            if QA.nerdIconChar(sentinel) then
                                UIManager:close(dlg)
                                showNerdIconPreview(sentinel, on_select, function()
                                    UIManager:nextTick(openInputDlg)
                                end)
                            else
                                UIManager:show(InfoMessage:new{
                                    text = _("Invalid Unicode codepoint"),
                                    timeout = 3,
                                })
                            end
                        else
                            UIManager:show(InfoMessage:new{
                                text = _("Please enter 1-6 hex digits (0-9, A-F)"),
                                timeout = 3,
                            })
                        end
                    end,
                },
            }},
        }
        UIManager:show(dlg)
    end
    openInputDlg()
end

-- ============================================================
-- Main Icon Picker Dialog
-- ============================================================

function QA.showIconPicker(on_select, saved_icon, filter, mode, parent_mode)
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    local pad = Screen:scaleBySize(10)
    local brd = Screen:scaleBySize(1)

    local cache_key = (filter or "all") .. "_" .. (mode or "normal")
    local use_cache = picker_cache[cache_key] ~= nil

    local icons_list, total_pages
    local frame_w, frame_h
    local content_w, title_bar_h, button_bar_h, footer_h
    local cols, rows, per_page, h_gap, v_gap
    local cell_w, cell_h, cell_pad, grid_w, grid_h

    local dialog = nil
    local cur_page = 1

    local filter_keyword = ""
    local filtered_icons_list = nil
    local show_labels = Utils.getBool("qa_icon_show_labels", false)
    local filter_input = nil
    local CLEAR_W = Screen:scaleBySize(56)

    local grid_container = nil
    local title_widget = nil
    local label_icon_widget = nil
    local pagination_container = nil
    local button_bar_widget = nil
    local filter_bar_widget = nil

    -- Vertical gap inserted between the five sections inside inner_frame.
    local V_GAP = Screen:scaleBySize(10)

    -- ============================================================
    -- Shared page builder: builds ONE page as a VerticalGroup
    -- ============================================================
    local function buildPageWidgets(display_list, page_num)
        local page_vg = VerticalGroup:new{ align = "left" }
        local start_idx = (page_num - 1) * per_page + 1
        for row = 0, rows - 1 do
            local row_hg = HorizontalGroup:new{ align = "top" }
            for col = 0, cols - 1 do
                local idx = start_idx + row * cols + col
                if idx <= #display_list then
                    local icon = display_list[idx]

                    local LABEL_FS = 11
                    local LABEL_STRIP = show_labels and Screen:scaleBySize(LABEL_FS + 4) or 10
                    local glyph_max_h = cell_h - cell_pad*2 - 2 - LABEL_STRIP
                    if glyph_max_h < 8 then glyph_max_h = 8 end
                    local glyph_factor = 0.5

                    local icon_widget
                    if icon.type == "nerd" then
                        local nerd_char = QA.nerdIconChar(icon.value)
                        icon_widget = TextWidget:new{
                            text = nerd_char or "?",
                            face = Font:getFace("symbols", math.floor(glyph_max_h * glyph_factor)),
                            fgcolor = Blitbuffer.COLOR_BLACK,
                            padding = 0,
                        }
                    else
                        local icon_path = icon.path
                        if mode == "system" and icon.is_overridden and icon.override_path then
                            icon_path = icon.override_path
                        end
                        icon_widget = IconWidget:new{
                            file = icon_path,
                            width = glyph_max_h,
                            height = glyph_max_h,
                            alpha = true,
                        }
                        pcall(function() icon_widget:_render() end)
                    end

                    local cell_content
                    if show_labels then
                        local label_text = icon.name or icon.display_name or ""
                        local label_widget = TextWidget:new{
                            text = label_text,
                            face = Font:getFace("cfont", LABEL_FS),
                            fgcolor = Blitbuffer.COLOR_BLACK,
                            max_width = cell_w - cell_pad*2 - 2,
                            padding = 0,
                        }
                        local stack = VerticalGroup:new{
                            align = "center",
                            CenterContainer:new{
                                dimen = Geom:new{ w = cell_w - cell_pad*2 - 2, h = glyph_max_h },
                                icon_widget,
                            },
                            label_widget,
                        }
                        cell_content = CenterContainer:new{
                            dimen = Geom:new{ w = cell_w - cell_pad*2 - 2, h = cell_h - cell_pad*2 - 2 },
                            stack,
                        }
                    else
                        cell_content = CenterContainer:new{
                            dimen = Geom:new{ w = cell_w - cell_pad*2 - 2, h = cell_h - cell_pad*2 - 2 },
                            icon_widget,
                        }
                    end

                    local border_color = Blitbuffer.COLOR_LIGHT_GRAY
                    local border_size = 1
                    if mode == "system" and icon.is_overridden then
                        border_color = Blitbuffer.COLOR_BLACK
                        border_size = 2
                    end

                    local cell = FrameContainer:new{
                        width = cell_w,
                        height = cell_h,
                        bordersize = border_size,
                        color = border_color,
                        background = Blitbuffer.COLOR_WHITE,
                        radius = Screen:scaleBySize(4),
                        padding = cell_pad,
                        cell_content,
                    }

                    local ic = InputContainer:new{
                        dimen = Geom:new{ w = cell_w, h = cell_h },
                        cell,
                    }
                    local _icon = icon
                    ic.ges_events = {
                        TapSelect = {
                            require("ui/gesturerange"):new{
                                ges = "tap",
                                range = ic.dimen,
                            },
                        },
                    }
                    ic.onTapSelect = function()
                        if filter_input then
                            filter_input:onCloseKeyboard()
                            if filter_input.focused then filter_input:unfocus() end
                        end
                        if mode == "system" then
                            local system_icon_name = _icon.name
                            local current = temp_overrides[system_icon_name]
                            UIManager:close(dialog)
                            UIManager:setDirty("all", "full")
                            QA.showIconPicker(
                                function(selected)
                                    if selected == current then return end
                                    if selected then
                                        local filename = selected:match("([^/]+)$") or selected
                                        temp_overrides[system_icon_name] = filename
                                    else
                                        temp_overrides[system_icon_name] = nil
                                    end
                                    picker_cache = {}
                                    QA.showIconPicker(nil, nil, nil, "system")
                                end,
                                current,
                                "file",
                                nil,
                                "system"
                            )
                        else
                            UIManager:close(dialog)
                            UIManager:setDirty("all", "full")
                            if on_select then on_select(_icon.value) end
                        end
                        return true
                    end

                    table.insert(row_hg, ic)
                    if col < cols - 1 then
                        table.insert(row_hg, HorizontalSpan:new{ width = h_gap })
                    end
                end
            end
            table.insert(page_vg, row_hg)
            if row < rows - 1 then
                table.insert(page_vg, VerticalSpan:new{ width = v_gap })
            end
        end
        return page_vg
    end

    local function getDisplayList()
        if filter_keyword == "" then
            return icons_list
        end
        if filtered_icons_list == nil then
            filtered_icons_list = {}
            local pattern = filter_keyword:lower()
            for _, icon in ipairs(icons_list) do
                local match = false
                if icon.type == "nerd" then
                    if icon.hex:lower():find(pattern, 1, true) then match = true end
                    if icon.name and icon.name:lower():find(pattern, 1, true) then match = true end
                else
                    if icon.display_name and icon.display_name:lower():find(pattern, 1, true) then
                        match = true
                    elseif icon.name and icon.name:lower():find(pattern, 1, true) then
                        match = true
                    end
                end
                if match then
                    table.insert(filtered_icons_list, icon)
                end
            end
        end
        return filtered_icons_list
    end

    local refreshGrid
    local goToPage

    local function buildPaginationNav()
        local chev_size = Screen:scaleBySize(32)
        local BTN_W = Screen:scaleBySize(60)
        local pn_span = Screen:scaleBySize(32)
        local function gap() return HorizontalSpan:new{ width = pn_span } end

        local icons_ok = pcall(function()
            local iw = IconWidget:new{ icon = "chevron.first", width = 16, height = 16 }
            iw:free()
        end)

        local CHEV_GLYPH = {
            ["chevron.first"] = "\xC2\xAB",
            ["chevron.left"]  = "\xE2\x80\xB9",
            ["chevron.right"] = "\xE2\x80\xBA",
            ["chevron.last"]  = "\xC2\xBB",
        }

        local function chev(icon_name, enabled, target)
            if icons_ok then
                return Button:new{
                    icon = icon_name,
                    icon_width = chev_size,
                    icon_height = chev_size,
                    width = BTN_W,
                    bordersize = 0,
                    enabled = enabled,
                    callback = enabled and function() goToPage(target) end or function() end,
                    show_parent = nil,
                }
            else
                return Button:new{
                    text = CHEV_GLYPH[icon_name] or "?",
                    text_font_size = 22,
                    text_font_bold = true,
                    width = BTN_W,
                    bordersize = 0,
                    enabled = enabled,
                    callback = enabled and function() goToPage(target) end or function() end,
                    show_parent = nil,
                }
            end
        end

        return HorizontalGroup:new{
            align = "center",
            chev("chevron.first", cur_page > 1, 1),
            gap(),
            chev("chevron.left",  cur_page > 1, cur_page - 1),
            gap(),
            Button:new{
                text = string.format(_("Page %d of %d"), cur_page, total_pages or 1),
                text_font_size = 15,
                bordersize = 0,
                callback = function()
                    local dlg
                    dlg = InputDialog:new{
                        title = _("Jump to page"),
                        input = tostring(cur_page),
                        input_hint = string.format("1 - %d", total_pages),
                        input_type = "number",
                        buttons = {{
                            {
                                text = _("Cancel"),
                                callback = function() UIManager:close(dlg) end,
                            },
                            {
                                text = _("Go"),
                                is_enter_default = true,
                                callback = function()
                                    local page = tonumber(dlg:getInputText())
                                    if page and page >= 1 and page <= total_pages then
                                        UIManager:close(dlg)
                                        goToPage(page)
                                    else
                                        UIManager:show(InfoMessage:new{
                                            text = string.format(_("Please enter a number between 1 and %d"), total_pages),
                                            timeout = 2,
                                        })
                                    end
                                end,
                            },
                        }},
                    }
                    UIManager:show(dlg)
                    pcall(function() dlg:onShowKeyboard() end)
                end,
                show_parent = nil,
            },
            gap(),
            chev("chevron.right", cur_page < (total_pages or 1), cur_page + 1),
            gap(),
            chev("chevron.last",  cur_page < (total_pages or 1), total_pages or 1),
        }
    end

    refreshGrid = function()
        local display_list = getDisplayList()
        total_pages = math.max(1, math.ceil(#display_list / per_page))
        if cur_page > total_pages then cur_page = 1 end

        local page_vg
        if #display_list == 0 then
            page_vg = CenterContainer:new{
                dimen = Geom:new{ w = grid_w, h = grid_h },
                TextWidget:new{
                    text = _("No matching icons"),
                    face = Font:getFace("cfont"),
                    fgcolor = Blitbuffer.COLOR_DARK_GRAY,
                },
            }
        else
            page_vg = buildPageWidgets(display_list, cur_page)
        end

        grid_container[1] = TopContainer:new{
            dimen = Geom:new{ w = grid_w, h = grid_h },
            page_vg,
        }
        if pagination_container then
            pagination_container[1] = buildPaginationNav()
        end
        UIManager:setDirty(dialog, function() return "ui", dialog.dimen end)
    end

    goToPage = function(p)
        if p < 1 or p > total_pages then return end
        cur_page = p
        refreshGrid()
    end

    local temp_overrides = {}
    if mode == "system" then
        temp_overrides = getSystemTempOverrides()
    end

    -- ============================================================
    -- Compute sizes (icons_list + layout)
    -- ============================================================
    if use_cache and mode ~= "system" then
        local cached = picker_cache[cache_key]
        if cached.sw == sw and cached.sh == sh then
            icons_list = cached.icons_list
            total_pages = cached.total_pages
            frame_w = cached.frame_w
            frame_h = cached.frame_h
            content_w = cached.content_w
            title_bar_h = cached.title_bar_h
            button_bar_h = cached.button_bar_h
            footer_h = cached.footer_h
            cols = cached.cols
            rows = cached.rows
            per_page = cached.per_page
            h_gap = cached.h_gap
            v_gap = cached.v_gap
            cell_w = cached.cell_w
            cell_h = cached.cell_h
            cell_pad = cached.cell_pad
            grid_w = cached.grid_w
            grid_h = cached.grid_h
        end
    end

    if not icons_list then
        icons_list = {}
        if (not filter or filter == "nerd") and mode ~= "system" then
            for _, icon in ipairs(getNerdIcons()) do
                table.insert(icons_list, {
                    type = "nerd", hex = icon.hex,
                    value = "nerd:" .. icon.hex, name = icon.name,
                })
            end
        end
        if not filter or filter == "file" then
            local file_icons = (mode == "system") and scanAllIconDirs("system") or QA.getFileIcons()
            for _, file in ipairs(file_icons) do
                local item = {
                    type = "file", path = file.path, name = file.name,
                    display_name = file.display_name, value = file.path,
                }
                if mode == "system" then
                    local override_icon = temp_overrides[file.name]
                    item.is_overridden = override_icon ~= nil
                    if override_icon then
                        local override_path = QA.getIconsDir() .. "/" .. override_icon
                        if Utils.fileExists(override_path) then
                            item.override_path = override_path
                        end
                    end
                end
                table.insert(icons_list, item)
            end
        end
    end

    if not cols then
        local aspect = sw / sh
        if sw > sh then
            frame_h = math.floor(sh * 0.85)
            if aspect <= 1.4 then cols, rows = 8, 4
            else cols, rows = 9, 4 end
        else
            frame_h = math.floor(sh * 0.80)
            if aspect <= 0.62 then cols, rows = 5, 7
            elseif aspect <= 0.70 then cols, rows = 6, 6
            else cols, rows = 6, 5 end
        end
        per_page = cols * rows
        h_gap = Screen:scaleBySize(15)
        v_gap = Screen:scaleBySize(15)
        frame_w = math.floor(sw * 0.90)
        content_w = frame_w - 2 * pad - 2 * brd

        -- cell_w is independent of grid_h; compute it now.
        cell_w = math.floor((content_w - (cols - 1) * h_gap) / cols)
        grid_w = cols * cell_w + (cols - 1) * h_gap

        -- grid_h / cell_h are deferred until every fixed-height section
        -- (title / button / filter / pagination) has been built and we can
        -- measure its real height. See below.
    end

    -- ============================================================
    -- Title bar widget (back / title / label toggle).
    -- Both icon slots are CenterContainer-wrapped at the same width
    -- so left and right margins are symmetric.
    -- ============================================================
    local title_text
    if mode == "system" then title_text = _("System Icon Preview")
    elseif filter == "file" then title_text = _("Select Icon File")
    else title_text = _("Select Icon") end

    local slot_w = Screen:scaleBySize(50)
    -- title_bar_h is only used as the height of the clickable slots; the
    -- row's real rendered height is title_widget:getSize().h (measured below).
    local title_slot_h = Screen:scaleBySize(50)

    local back_btn = InputContainer:new{
        dimen = Geom:new{ w = slot_w, h = title_slot_h },
        CenterContainer:new{
            dimen = Geom:new{ w = slot_w, h = title_slot_h },
            TextWidget:new{
                text = "↶", face = Font:getFace("cfont", 24),
                fgcolor = Blitbuffer.COLOR_BLACK,
            },
        },
    }
    back_btn.ges_events = { TapSelect = { require("ui/gesturerange"):new{ ges = "tap", range = back_btn.dimen } } }
    back_btn.onTapSelect = function()
        if filter_input then
            filter_input:onCloseKeyboard()
            if filter_input.focused then filter_input:unfocus() end
        end
        UIManager:close(dialog)
        UIManager:setDirty("all", "full")
        if mode == "system" then
            require("qui_actions/qa_settings").showSettings()
        elseif parent_mode == "system" then
            QA.showIconPicker(nil, nil, nil, "system")
        else
            if on_select then on_select(saved_icon) end
        end
        return true
    end

    label_icon_widget = TextWidget:new{
        text = (show_labels and (QA.nerdIconChar("nerd:E907") or "◉") or (QA.nerdIconChar("nerd:E908") or "◎")),
        face = Font:getFace("symbols", 22),
        fgcolor = show_labels and Blitbuffer.COLOR_BLACK or Blitbuffer.gray(0.5),
    }
    local label_btn = InputContainer:new{
        dimen = Geom:new{ w = slot_w, h = title_slot_h },
        CenterContainer:new{
            dimen = Geom:new{ w = slot_w, h = title_slot_h },
            label_icon_widget,
        },
    }
    label_btn.ges_events = { TapSelect = { require("ui/gesturerange"):new{ ges = "tap", range = label_btn.dimen } } }
    label_btn.onTapSelect = function()
        show_labels = not show_labels
        Utils.set("qa_icon_show_labels", show_labels)
        label_icon_widget:setText(
            show_labels and (QA.nerdIconChar("nerd:E907") or "◉")
                        or (QA.nerdIconChar("nerd:E908") or "◎")
        )
        label_icon_widget.fgcolor = show_labels and Blitbuffer.COLOR_BLACK or Blitbuffer.gray(0.5)
        refreshGrid()
        return true
    end

    title_widget = HorizontalGroup:new{
        align = "center",
        back_btn,
        CenterContainer:new{
            dimen = Geom:new{ w = content_w - 2 * slot_w, h = title_slot_h },
            TextWidget:new{
                text = title_text, face = Font:getFace("smallinfofont"), bold = true,
            },
        },
        label_btn,
    }

    -- ============================================================
    -- Button bar (Use Default / Refresh / File Icons / Browse,
    -- or Reset All / Apply for system mode)
    -- ============================================================
    if mode == "system" then
        local replaced = 0
        for _, item in ipairs(icons_list) do
            if temp_overrides[item.name] then replaced = replaced + 1 end
        end

        local reset_all_btn = Button:new{
            text = string.format(_("Reset All (%d)"), replaced),
            width = math.floor(content_w / 2) - 4,
            callback = function()
                if replaced == 0 then
                    UIManager:show(InfoMessage:new{ text = _("No icons to reset"), timeout = 2 })
                    return
                end
                resetSystemTempOverrides()
                Utils.set("qa_common_icon_overrides", {})
                picker_cache = {}
                UIManager:show(Notification:new{ text = _("All icons reset, restart required"), timeout = 2 })
                UIManager:show(ConfirmBox:new{
                    text = _("Restart required.\n\nRestart KOReader now?"),
                    ok_text = _("Restart"), cancel_text = _("Later"),
                    ok_callback = function() UIManager:restartKOReader() end,
                })
            end,
        }

        local apply_btn = Button:new{
            text = string.format(_("Apply Replacements (%d)"), replaced),
            width = math.floor(content_w / 2) - 4,
            callback = function()
                if replaced == 0 then
                    UIManager:show(InfoMessage:new{ text = _("No icons to apply"), timeout = 2 })
                    return
                end
                local overrides = Utils.getTable("qa_common_icon_overrides")
                for k, _ in pairs(overrides) do overrides[k] = nil end
                for k, v in pairs(temp_overrides) do
                    if v then overrides[k] = v end
                end
                Utils.set("qa_common_icon_overrides", overrides)
                resetSystemTempOverrides()
                picker_cache = {}
                UIManager:show(Notification:new{
                    text = string.format(_("Applied %d icon replacements"), replaced), timeout = 2,
                })
                UIManager:show(ConfirmBox:new{
                    text = _("Restart required.\n\nRestart KOReader now?"),
                    ok_text = _("Restart"), cancel_text = _("Later"),
                    ok_callback = function() UIManager:restartKOReader() end,
                })
            end,
        }

        button_bar_widget = HorizontalGroup:new{
            align = "center",
            reset_all_btn,
            HorizontalSpan:new{ width = 8 },
            apply_btn,
        }
    else
        local btn_width = math.floor(content_w / 4) - 5
        local show_browse_btn = not filter or filter == "file"

        local apply_default_btn = Button:new{
            text = _("Use Default"),
            width = btn_width,
            callback = function()
                if filter_input then
                    filter_input:onCloseKeyboard()
                    if filter_input.focused then filter_input:unfocus() end
                end
                UIManager:close(dialog)
                UIManager:setDirty("all", "full")
                if on_select then on_select(nil) end
            end,
        }

        local refresh_btn = Button:new{
            text = "↻",
            width = btn_width,
            callback = function()
                if filter_input then
                    filter_input:onCloseKeyboard()
                    if filter_input.focused then filter_input:unfocus() end
                end
                QA.clearFileIconsCache()
                picker_cache = {}
                UIManager:close(dialog)
                UIManager:setDirty("all", "full")
                QA.showIconPicker(on_select, saved_icon, filter, mode, parent_mode)
            end,
        }

        local toggle_btn = Button:new{
            text = (filter == "file") and _("All Icons") or _("File Icons"),
            width = btn_width,
            callback = function()
                if filter_input then
                    filter_input:onCloseKeyboard()
                    if filter_input.focused then filter_input:unfocus() end
                end
                UIManager:close(dialog)
                UIManager:setDirty("all", "full")
                if filter == "file" then
                    QA.showIconPicker(on_select, saved_icon, nil)
                else
                    QA.showIconPicker(on_select, saved_icon, "file")
                end
            end,
        }

        local browse_btn
        if show_browse_btn then
            browse_btn = Button:new{
                text = _("Browse"),
                width = btn_width,
                callback = function()
                    if filter_input then
                        filter_input:onCloseKeyboard()
                        if filter_input.focused then filter_input:unfocus() end
                    end
                    UIManager:close(dialog)
                    UIManager:setDirty("all", "full")
                    QA.clearFileIconsCache()
                    UIManager:show(IconBrowser:new{
                        path = QA.getIconsDir(),
                        onConfirm = function(file_path)
                            if on_select then on_select(file_path) end
                        end,
                    })
                end,
            }
        end

        local children = { apply_default_btn }
        table.insert(children, HorizontalSpan:new{ width = 8 })
        table.insert(children, refresh_btn)
        table.insert(children, HorizontalSpan:new{ width = 8 })
        table.insert(children, toggle_btn)
        if show_browse_btn then
            table.insert(children, HorizontalSpan:new{ width = 8 })
            table.insert(children, browse_btn)
        end
        button_bar_widget = HorizontalGroup:new{
            align = "center",
            unpack(children),
        }
    end

    -- ============================================================
    -- Filter bar widget
    -- ============================================================
    local input_border = Size.border.inputtext
    local input_padding = Size.padding.default
    local input_overhead = 2 * (input_border + input_padding)

    filter_input = InputText:new{
        text = filter_keyword,
        hint = _("Enter name or codepoint to filter icons"),
        width = content_w - CLEAR_W - 2 * Screen:scaleBySize(4) - input_overhead,
        face = Font:getFace("cfont", 14),
        padding = input_padding,
        margin = 0,
        bordersize = input_border,
        scroll = false,
        focused = false,
        parent = {},
        edit_callback = function()
            if not filter_input then return end
            filter_keyword = filter_input:getText() or ""
            filtered_icons_list = nil
            cur_page = 1
            refreshGrid()
        end,
    }

    local row_h = filter_input:getSize().h
    local btn_pad_h = Screen:scaleBySize(12)

    local clear_label = TextWidget:new{
        text = "✕",
        face = Font:getFace("cfont", 14),
        fgcolor = Blitbuffer.COLOR_BLACK,
        bold = true,
    }
    local clear_fc = FrameContainer:new{
        bordersize = input_border,
        color = Blitbuffer.COLOR_DARK_GRAY,
        padding = 0,
        padding_left = btn_pad_h,
        padding_right = btn_pad_h,
        padding_top = 0,
        padding_bottom = 0,
        margin = 0,
        radius = Size.radius.default,
        background = Blitbuffer.COLOR_WHITE,
        CenterContainer:new{
            dimen = Geom:new{
                w = CLEAR_W - 2 * btn_pad_h - 2 * input_border,
                h = row_h - 2 * input_border,
            },
            clear_label,
        },
    }
    local clear_btn = InputContainer:new{
        dimen = Geom:new{ w = CLEAR_W, h = row_h },
        clear_fc,
    }
    clear_btn.ges_events = {
        TapSelect = {
            require("ui/gesturerange"):new{ ges = "tap", range = clear_btn.dimen },
        },
    }
    clear_btn.onTapSelect = function()
        if filter_input then
            filter_input:setText("")
            filter_input:onCloseKeyboard()
            if filter_input.focused then filter_input:unfocus() end
        end
        filter_keyword = ""
        filtered_icons_list = nil
        cur_page = 1
        refreshGrid()
        return true
    end

    filter_bar_widget = HorizontalGroup:new{
        align = "center",
        filter_input,
        HorizontalSpan:new{ width = Screen:scaleBySize(4) },
        clear_btn,
    }

    -- ============================================================
    -- Pagination widget (bookshelf_pagination.buildNav style)
    -- ============================================================
    pagination_container = CenterContainer:new{
        dimen = Geom:new{ w = content_w, h = Screen:scaleBySize(40) },
    }

    -- ============================================================
    -- Now that every fixed-height section is built, measure them and
    -- derive grid_h / cell_h from the real heights. This guarantees the
    -- VerticalGroup inside inner_frame exactly fills frame_h - 2*pad,
    -- so the only space below the pagination row is `pad` itself.
    -- ============================================================
    if not cell_h then
        local title_actual      = title_widget:getSize().h
        local button_actual     = button_bar_widget:getSize().h
        local filter_actual     = filter_bar_widget:getSize().h
        local pagination_actual = pagination_container:getSize().h

        local available_h = frame_h - 2 * pad
                            - title_actual - button_actual
                            - filter_actual - pagination_actual
                            - 4 * V_GAP
        grid_h = math.max(1, available_h)
        cell_h = math.floor((grid_h - (rows - 1) * v_gap) / rows)
        if cell_h < 1 then cell_h = 1 end
        grid_h = cell_h * rows + (rows - 1) * v_gap
        cell_pad = math.max(2, math.floor(cell_h * 0.05))
    end

    -- ============================================================
    -- Grid container widget
    -- ============================================================
    grid_container = TopContainer:new{
        dimen = Geom:new{ w = grid_w, h = grid_h },
    }

    -- ============================================================
    -- Assemble the modal
    -- ============================================================
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
            button_bar_widget,
            VerticalSpan:new{ width = V_GAP },
            filter_bar_widget,
            VerticalSpan:new{ width = V_GAP },
            grid_container,
            VerticalSpan:new{ width = V_GAP },
            pagination_container,
        },
    }

    local PickerDlg = InputContainer:extend{
        is_always_active = true,
    }

    function PickerDlg:init()
        self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
        self[1] = CenterContainer:new{
            dimen = Geom:new{ w = sw, h = sh },
            inner_frame,
        }
        if Device:isTouchDevice() then
            self.ges_events.Tap = {
                require("ui/gesturerange"):new{
                    ges = "tap",
                    range = Geom:new{ w = sw, h = sh },
                },
            }
            self.ges_events.Swipe = {
                require("ui/gesturerange"):new{
                    ges = "swipe",
                    range = Geom:new{ w = sw, h = sh },
                },
            }
        end
    end

    function PickerDlg:onCloseWidget()
        if filter_input then
            filter_input:onCloseKeyboard()
            if filter_input.focused then filter_input:unfocus() end
        end
    end

    function PickerDlg:onTap(arg, ges)
        if filter_input and filter_input:isKeyboardVisible() then
            if filter_input.keyboard and filter_input.keyboard.dimen
                    and ges.pos:notIntersectWith(filter_input.keyboard.dimen) then
                filter_input:onCloseKeyboard()
                if filter_input.focused then filter_input:unfocus() end
                UIManager:setDirty(self, "ui")
            end
            return true
        end
        if ges.pos:notIntersectWith(inner_frame.dimen) then
            UIManager:close(self)
            UIManager:setDirty("all", "full")
        end
        return true
    end

    function PickerDlg:onSwipe(arg, ges)
        if ges.direction == "west" then goToPage(cur_page + 1)
        elseif ges.direction == "east" then goToPage(cur_page - 1)
        else
            UIManager:close(self)
            UIManager:setDirty("all", "full")
        end
        return true
    end

    dialog = PickerDlg:new{}
    UIManager:show(dialog, "full")

    -- Cache the computed layout for the next open of this same picker.
    if not use_cache and mode ~= "system" then
        picker_cache[cache_key] = {
            icons_list = icons_list,
            total_pages = total_pages,
            sw = sw, sh = sh,
            frame_w = frame_w, frame_h = frame_h,
            content_w = content_w,
            cols = cols, rows = rows, per_page = per_page,
            h_gap = h_gap, v_gap = v_gap,
            cell_w = cell_w, cell_h = cell_h, cell_pad = cell_pad,
            grid_w = grid_w, grid_h = grid_h,
        }
    end

    if not grid_container[1] then
        refreshGrid()
    end
end

-- ============================================================
-- Patch IconWidget for System Icon Overrides
-- ============================================================

function QA.patchIconWidget()
    local IconWidget = require("ui/widget/iconwidget")
    if IconWidget._quickui_icon_patched then
        return
    end
    IconWidget._quickui_icon_patched = true

    local orig_init = IconWidget.init

    function IconWidget:init()
        if self.icon then
            local overrides = Utils.getTable("qa_common_icon_overrides")
            if overrides and overrides[self.icon] then
                local user_icon = overrides[self.icon]
                local dir = QA.getIconsDir()
                local full_path = dir .. "/" .. user_icon
                if Utils.fileExists(full_path) then
                    self.file = full_path
                    self.icon = nil
                elseif Utils.fileExists(user_icon) then
                    self.file = user_icon
                    self.icon = nil
                end
            end
        end
        return orig_init(self)
    end

end

return QA
