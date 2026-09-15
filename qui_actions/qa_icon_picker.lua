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
    local pad = Screen:scaleBySize(24)
    local brd = Screen:scaleBySize(1)

    local cache_key = (filter or "all") .. "_" .. (mode or "normal")
    local use_cache = picker_cache[cache_key] ~= nil

    local icons_list, page_widgets, total_pages
    local frame_x, frame_y, frame_w, frame_h
    local content_w, title_bar_h, button_bar_h, footer_h
    local cols, rows, per_page, h_gap, v_gap
    local cell_w, cell_h, icon_sz, font_size, cell_pad, grid_w, grid_h

    local dialog = nil
    local cur_page = 1

    local filter_keyword = ""
    local filtered_icons_list = nil
    local search_dialog = nil

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
                    if icon.hex:lower():find(pattern, 1, true) then
                        match = true
                    end
                    if icon.name and icon.name:lower():find(pattern, 1, true) then
                        match = true
                    end
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

    local function rebuildPicker()
        filtered_icons_list = nil
        local display_list = getDisplayList()
        local new_total_pages = math.max(1, math.ceil(#display_list / per_page))

        local new_page_widgets = {}
        for p = 1, new_total_pages do
            local page_vg = VerticalGroup:new{ align = "left" }
            local start_idx = (p - 1) * per_page + 1
            for row = 0, rows - 1 do
                local row_hg = HorizontalGroup:new{ align = "top" }
                for col = 0, cols - 1 do
                    local idx = start_idx + row * cols + col
                    if idx <= #display_list then
                        local icon = display_list[idx]

                        local icon_widget
                        if icon.type == "nerd" then
                            local nerd_char = QA.nerdIconChar(icon.value)
                            icon_widget = TextWidget:new{
                                text = nerd_char or "?",
                                face = Font:getFace("symbols", font_size),
                                fgcolor = Blitbuffer.COLOR_BLACK,
                            }
                        else
                            local icon_path = icon.path
                            if mode == "system" and icon.is_overridden and icon.override_path then
                                icon_path = icon.override_path
                            end
                            icon_widget = IconWidget:new{
                                file = icon_path,
                                width = icon_sz,
                                height = icon_sz,
                                alpha = true,
                            }
                            pcall(function() icon_widget:_render() end)
                        end

                        local cell_content = CenterContainer:new{
                            dimen = Geom:new{ w = cell_w - cell_pad*2 - 2, h = cell_h - cell_pad*2 - 2 },
                            icon_widget,
                        }

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
                        table.insert(row_hg, cell)
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
            new_page_widgets[p] = page_vg
        end

        page_widgets = new_page_widgets
        total_pages = new_total_pages
        if cur_page > total_pages then
            cur_page = 1
        end
        if dialog then
            UIManager:setDirty(dialog, function() return "ui", dialog.dimen end)
        end
    end

    local function showSearchDialog()
        if search_dialog then
            UIManager:close(search_dialog)
            search_dialog = nil
        end

        local function onStrike()
            if search_dialog then
                filter_keyword = search_dialog:getInputText() or ""
                filtered_icons_list = nil
                rebuildPicker()
                UIManager:setDirty(dialog, function() return "ui", dialog.dimen end)
            end
        end

        search_dialog = InputDialog:new{
            title = _("Filter Icons"),
            input = filter_keyword,
            input_hint = _("Enter name or codepoint..."),
            strike_callback = onStrike,
            buttons = {
                {
                    {
                        text = _("Clear"),
                        callback = function()
                            UIManager:close(search_dialog)
                            search_dialog = nil
                            filter_keyword = ""
                            filtered_icons_list = nil
                            rebuildPicker()
                            UIManager:setDirty(dialog, function() return "ui", dialog.dimen end)
                        end,
                    },
                    {
                        text = _("Close"),
                        callback = function()
                            UIManager:close(search_dialog)
                            search_dialog = nil
                        end,
                    },
                }
            },
        }
        UIManager:show(search_dialog)
        pcall(function() search_dialog:onShowKeyboard() end)
    end

    local temp_overrides = {}
    if mode == "system" then
        temp_overrides = getSystemTempOverrides()
    end

    local cache_valid = false
    if use_cache and mode ~= "system" then
        local cached = picker_cache[cache_key]
        if cached.sw == sw and cached.sh == sh then
            cache_valid = true
            icons_list = cached.icons_list
            page_widgets = cached.page_widgets
            total_pages = cached.total_pages
            frame_x = cached.frame_x
            frame_y = cached.frame_y
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
            icon_sz = cached.icon_sz
            font_size = cached.font_size
            cell_pad = cached.cell_pad
            grid_w = cached.grid_w
            grid_h = cached.grid_h
        end
    end

    if not cache_valid then
        if use_cache and mode ~= "system" then
            icons_list = picker_cache[cache_key].icons_list
        else
            icons_list = {}

            if (not filter or filter == "nerd") and mode ~= "system" then
                local nerd_icons = getNerdIcons()
                for _, icon in ipairs(nerd_icons) do
                    table.insert(icons_list, {
                        type = "nerd",
                        hex = icon.hex,
                        value = "nerd:" .. icon.hex,
                        name = icon.name,
                    })
                end
            end

            if not filter or filter == "file" then
                local file_icons
                if mode == "system" then
                    file_icons = scanAllIconDirs("system")
                else
                    file_icons = QA.getFileIcons()
                end
                for _, file in ipairs(file_icons) do
                    local item = {
                        type = "file",
                        path = file.path,
                        name = file.name,
                        display_name = file.display_name,
                        value = file.path,
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

        -- Keep the original Kindle layout (portrait 7x5, landscape 9x4).
        -- Only reshape for very tall/narrow phone screens.
        local aspect = sw / sh

        if sw > sh then
            -- Landscape
            frame_h = math.floor(sh * 0.85)
            if aspect <= 1.4 then
                -- Kindle-ish landscape (4:3 ~ 1.33): 8x4
                cols = 8
                rows = 4
            else
                -- Phone landscape (16:9 ~ 1.78 and wider): 9x4
                cols = 9
                rows = 4
            end
        else
            -- Portrait
            frame_h = math.floor(sh * 0.70)
            if aspect <= 0.62 then
                cols = 5
                rows = 7
            elseif aspect <= 0.70 then
                cols = 6
                rows = 6
            else
                cols = 6
                rows = 5
            end
        end
        per_page = cols * rows

        h_gap = Screen:scaleBySize(15)
        v_gap = Screen:scaleBySize(15)
        frame_w = math.floor(sw * 0.90)
        content_w = frame_w - 2 * pad - 2 * brd
        title_bar_h = Screen:scaleBySize(50)
        button_bar_h = Screen:scaleBySize(50)
        footer_h = Screen:scaleBySize(40)
        cell_w = math.floor((content_w - (cols - 1) * h_gap) / cols)
        local available_h = frame_h - pad - title_bar_h - button_bar_h - footer_h - pad
        cell_h = math.max(44, math.floor((available_h - (rows - 1) * v_gap) / rows))
        icon_sz = math.floor(cell_h * 0.55)
        font_size = math.floor(icon_sz * 0.70)
        cell_pad = math.max(4, math.floor(cell_h * 0.2))
        grid_w = cols * cell_w + (cols - 1) * h_gap
        grid_h = cell_h * rows + (rows - 1) * v_gap
        frame_x = math.floor((sw - frame_w) / 2)
        frame_y = math.max(0, math.floor((sh - frame_h) / 2))

        local display_list = getDisplayList()
        total_pages = math.max(1, math.ceil(#display_list / per_page))
        page_widgets = {}

        for p = 1, total_pages do
            local page_vg = VerticalGroup:new{ align = "left" }
            local start_idx = (p - 1) * per_page + 1
            for row = 0, rows - 1 do
                local row_hg = HorizontalGroup:new{ align = "top" }
                for col = 0, cols - 1 do
                    local idx = start_idx + row * cols + col
                    if idx <= #display_list then
                        local icon = display_list[idx]

                        local icon_widget
                        if icon.type == "nerd" then
                            local nerd_char = QA.nerdIconChar(icon.value)
                            icon_widget = TextWidget:new{
                                text = nerd_char or "?",
                                face = Font:getFace("symbols", font_size),
                                fgcolor = Blitbuffer.COLOR_BLACK,
                            }
                        else
                            local icon_path = icon.path
                            if mode == "system" and icon.is_overridden and icon.override_path then
                                icon_path = icon.override_path
                            end
                            icon_widget = IconWidget:new{
                                file = icon_path,
                                width = icon_sz,
                                height = icon_sz,
                                alpha = true,
                            }
                            pcall(function() icon_widget:_render() end)
                        end

                        local cell_content = CenterContainer:new{
                            dimen = Geom:new{ w = cell_w - cell_pad*2 - 2, h = cell_h - cell_pad*2 - 2 },
                            icon_widget,
                        }

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
                        table.insert(row_hg, cell)
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
            page_widgets[p] = page_vg
        end

        if mode ~= "system" then
            picker_cache[cache_key] = {
                icons_list = icons_list,
                page_widgets = page_widgets,
                total_pages = total_pages,
                sw = sw,
                sh = sh,
                frame_x = frame_x,
                frame_y = frame_y,
                frame_w = frame_w,
                frame_h = frame_h,
                content_w = content_w,
                title_bar_h = title_bar_h,
                button_bar_h = button_bar_h,
                footer_h = footer_h,
                cols = cols,
                rows = rows,
                per_page = per_page,
                h_gap = h_gap,
                v_gap = v_gap,
                cell_w = cell_w,
                cell_h = cell_h,
                icon_sz = icon_sz,
                font_size = font_size,
                cell_pad = cell_pad,
                grid_w = grid_w,
                grid_h = grid_h,
            }
        end
    end

    -- Build button row
    local btn_row
    if mode == "system" then
        local all_overrides = Utils.getTable("qa_common_icon_overrides")
        local replaced = 0
        for _, item in ipairs(icons_list) do
            if temp_overrides[item.name] then
                replaced = replaced + 1
            end
        end

        local reset_all_btn = Button:new{
            text = string.format(_("Reset All (%d)"), replaced),
            width = math.floor(content_w / 2) - 4,
            show_parent = nil,
            callback = function()
                if replaced == 0 then
                    UIManager:show(InfoMessage:new{
                        text = _("No icons to reset"),
                        timeout = 2,
                    })
                    return
                end
                resetSystemTempOverrides()
                Utils.set("qa_common_icon_overrides", {})
                picker_cache = {}
                UIManager:show(Notification:new{
                    text = _("All icons reset, restart required"),
                    timeout = 2,
                })
                UIManager:show(ConfirmBox:new{
                    text = _("Restart required.\n\nRestart KOReader now?"),
                    ok_text = _("Restart"),
                    cancel_text = _("Later"),
                    ok_callback = function()
                        UIManager:restartKOReader()
                    end,
                })
            end,
        }

        local apply_btn = Button:new{
            text = string.format(_("Apply Replacements (%d)"), replaced),
            width = math.floor(content_w / 2) - 4,
            show_parent = nil,
            callback = function()
                if replaced == 0 then
                    UIManager:show(InfoMessage:new{
                        text = _("No icons to apply"),
                        timeout = 2,
                    })
                    return
                end
                local overrides = Utils.getTable("qa_common_icon_overrides")
                for k, _ in pairs(overrides) do
                    overrides[k] = nil
                end
                for k, v in pairs(temp_overrides) do
                    if v then
                        overrides[k] = v
                    end
                end
                Utils.set("qa_common_icon_overrides", overrides)
                resetSystemTempOverrides()
                picker_cache = {}
                UIManager:show(Notification:new{
                    text = string.format(_("Applied %d icon replacements"), replaced),
                    timeout = 2,
                })
                UIManager:show(ConfirmBox:new{
                    text = _("Restart required.\n\nRestart KOReader now?"),
                    ok_text = _("Restart"),
                    cancel_text = _("Later"),
                    ok_callback = function()
                        UIManager:restartKOReader()
                    end,
                })
            end,
        }

        btn_row = HorizontalGroup:new{
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
            show_parent = nil,
            callback = function()
                UIManager:close(dialog)
                UIManager:setDirty("all", "full")
                if on_select then on_select(nil) end
            end,
        }

        local refresh_btn = Button:new{
            text = "↻",
            width = btn_width,
            show_parent = nil,
            callback = function()
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
            show_parent = nil,
            callback = function()
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
                show_parent = nil,
                callback = function()
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

        local btn_row_children = { apply_default_btn }
        table.insert(btn_row_children, HorizontalSpan:new{ width = 8 })
        table.insert(btn_row_children, refresh_btn)
        table.insert(btn_row_children, HorizontalSpan:new{ width = 8 })
        table.insert(btn_row_children, toggle_btn)
        if show_browse_btn then
            table.insert(btn_row_children, HorizontalSpan:new{ width = 8 })
            table.insert(btn_row_children, browse_btn)
        end
        btn_row = HorizontalGroup:new{
            align = "center",
            unpack(btn_row_children),
        }
    end

    local inner_frame = FrameContainer:new{
        width = frame_w,
        height = frame_h,
        background = Blitbuffer.COLOR_WHITE,
        bordersize = brd,
        radius = Screen:scaleBySize(8),
        padding = pad,
        VerticalGroup:new{ align = "center" },
    }

    local PickerDlg = InputContainer:extend{}
    function PickerDlg:init()
        self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
        self:registerTouchZones({
            {
                id = "picker_tap",
                ges = "tap",
                screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
                handler = function(ges)
                    local fd = inner_frame.dimen
                    if not fd or not ges.pos:intersectWith(fd) then
                        UIManager:close(self)
                        UIManager:setDirty("all", "full")
                        return true
                    end
                    local gx, gy = ges.pos.x, ges.pos.y
                    local btn_hit = 80

                    if gx >= frame_x + pad and gx < frame_x + pad + btn_hit
                            and gy >= frame_y + pad and gy < frame_y + pad + btn_hit then
                        UIManager:close(self)
                        UIManager:setDirty("all", "full")
                        if mode == "system" then
                            local settings = require("qui_actions/qa_settings")
                            settings.showSettings()
                        elseif parent_mode == "system" then
                            QA.showIconPicker(nil, nil, nil, "system")
                        else
                            if on_select then on_select(saved_icon) end
                        end
                        return true
                    end

                    if gx >= frame_x + frame_w - pad - btn_hit and gx < frame_x + frame_w - pad
                            and gy >= frame_y + pad and gy < frame_y + pad + btn_hit then
                        showSearchDialog()
                        return true
                    end

                    local btn_y = frame_y + pad + title_bar_h
                    if gy >= btn_y and gy < btn_y + button_bar_h then
                        if mode == "system" then
                            local btn_width_sys = math.floor(content_w / 2) - 4
                            local btn_x_start = frame_x + pad
                            if gx >= btn_x_start and gx < btn_x_start + btn_width_sys then
                                local all_overrides = Utils.getTable("qa_common_icon_overrides")
                                local replaced = 0
                                for _, item in ipairs(icons_list) do
                                    if temp_overrides[item.name] then
                                        replaced = replaced + 1
                                    end
                                end
                                if replaced == 0 then
                                    UIManager:show(InfoMessage:new{
                                        text = _("No icons to reset"),
                                        timeout = 2,
                                    })
                                    return true
                                end
                                UIManager:close(self)
                                UIManager:setDirty("all", "full")
                                resetSystemTempOverrides()
                                Utils.set("qa_common_icon_overrides", {})
                                picker_cache = {}
                                UIManager:show(Notification:new{
                                    text = _("All icons reset, restart required"),
                                    timeout = 2,
                                })
                                UIManager:show(ConfirmBox:new{
                                    text = _("Restart required.\n\nRestart KOReader now?"),
                                    ok_text = _("Restart"),
                                    cancel_text = _("Later"),
                                    ok_callback = function()
                                        UIManager:restartKOReader()
                                    end,
                                })
                                return true
                            end
                            if gx >= btn_x_start + btn_width_sys + 8 and gx < btn_x_start + (btn_width_sys + 8) * 2 then
                                local all_overrides = Utils.getTable("qa_common_icon_overrides")
                                local replaced = 0
                                for _, item in ipairs(icons_list) do
                                    if temp_overrides[item.name] then
                                        replaced = replaced + 1
                                    end
                                end
                                if replaced == 0 then
                                    UIManager:show(InfoMessage:new{
                                        text = _("No icons to apply"),
                                        timeout = 2,
                                    })
                                    return true
                                end
                                UIManager:close(self)
                                UIManager:setDirty("all", "full")
                                local overrides = Utils.getTable("qa_common_icon_overrides")
                                for k, _ in pairs(overrides) do
                                    overrides[k] = nil
                                end
                                for k, v in pairs(temp_overrides) do
                                    if v then
                                        overrides[k] = v
                                    end
                                end
                                Utils.set("qa_common_icon_overrides", overrides)
                                resetSystemTempOverrides()
                                picker_cache = {}
                                UIManager:show(Notification:new{
                                    text = string.format(_("Applied %d icon replacements"), replaced),
                                    timeout = 2,
                                })
                                UIManager:show(ConfirmBox:new{
                                    text = _("Restart required.\n\nRestart KOReader now?"),
                                    ok_text = _("Restart"),
                                    cancel_text = _("Later"),
                                    ok_callback = function()
                                        UIManager:restartKOReader()
                                    end,
                                })
                                return true
                            end
                            return true
                        else
                            local btn_x_start = frame_x + pad
                            local current_btn_width = math.floor(content_w / 4) - 5
                            local btn_index = 0

                            if gx >= btn_x_start and gx < btn_x_start + current_btn_width then
                                UIManager:close(self)
                                UIManager:setDirty("all", "full")
                                if on_select then on_select(nil) end
                                return true
                            end
                            btn_index = btn_index + 1

                            local x_start = btn_x_start + (current_btn_width + 8) * btn_index
                            if gx >= x_start and gx < x_start + current_btn_width then
                                QA.clearFileIconsCache()
                                picker_cache = {}
                                UIManager:close(self)
                                UIManager:setDirty("all", "full")
                                QA.showIconPicker(on_select, saved_icon, filter, mode, parent_mode)
                                return true
                            end
                            btn_index = btn_index + 1

                            x_start = btn_x_start + (current_btn_width + 8) * btn_index
                            if gx >= x_start and gx < x_start + current_btn_width then
                                UIManager:close(self)
                                UIManager:setDirty("all", "full")
                                if filter == "file" then
                                    QA.showIconPicker(on_select, saved_icon, nil)
                                else
                                    QA.showIconPicker(on_select, saved_icon, "file")
                                end
                                return true
                            end
                            btn_index = btn_index + 1

                            if not filter or filter == "file" then
                                x_start = btn_x_start + (current_btn_width + 8) * btn_index
                                if gx >= x_start and gx < x_start + current_btn_width then
                                    UIManager:close(self)
                                    UIManager:setDirty("all", "full")
                                    QA.clearFileIconsCache()
                                    UIManager:show(IconBrowser:new{
                                        path = QA.getIconsDir(),
                                        onConfirm = function(file_path)
                                            if on_select then on_select(file_path) end
                                        end,
                                    })
                                    return true
                                end
                            end
                            return true
                        end
                    end

                    local bar_y = frame_y + pad + title_bar_h + button_bar_h + grid_h
                    if gy >= bar_y and gy < bar_y + footer_h then
                        local chev_w = 120
                        if gx < frame_x + pad + chev_w then
                            if cur_page > 1 then
                                cur_page = cur_page - 1
                                UIManager:setDirty(self, function() return "ui", self.dimen end)
                            end
                            return true
                        elseif gx > frame_x + frame_w - pad - chev_w then
                            if cur_page < total_pages then
                                cur_page = cur_page + 1
                                UIManager:setDirty(self, function() return "ui", self.dimen end)
                            end
                            return true
                        else
                            local dlg
                            dlg = InputDialog:new{
                                title = _("Jump to page"),
                                input = tostring(cur_page),
                                input_hint = string.format("1 - %d", total_pages),
                                input_type = "number",
                                buttons = {
                                    {
                                        {
                                            text = _("Cancel"),
                                            callback = function()
                                                UIManager:close(dlg)
                                            end,
                                        },
                                        {
                                            text = _("Go"),
                                            is_enter_default = true,
                                            callback = function()
                                                local page = tonumber(dlg:getInputText())
                                                if page and page >= 1 and page <= total_pages then
                                                    cur_page = page
                                                    UIManager:close(dlg)
                                                    UIManager:setDirty(self, function() return "ui", self.dimen end)
                                                else
                                                    UIManager:show(InfoMessage:new{
                                                        text = string.format(_("Please enter a number between 1 and %d"), total_pages),
                                                        timeout = 2,
                                                    })
                                                end
                                            end,
                                        },
                                    }
                                },
                            }
                            UIManager:show(dlg)
                            pcall(function() dlg:onShowKeyboard() end)
                            return true
                        end
                    end

                    local grid_start_x = frame_x + pad + (content_w - grid_w) / 2
                    local grid_y = frame_y + pad + title_bar_h + button_bar_h
                    if gx >= grid_start_x and gx < grid_start_x + grid_w
                            and gy >= grid_y and gy < grid_y + grid_h then
                        local col = math.floor((gx - grid_start_x) / (cell_w + h_gap))
                        local row = math.floor((gy - grid_y) / (cell_h + v_gap))
                        local display_list = getDisplayList()
                        local idx = (cur_page - 1) * per_page + row * cols + col + 1
                        if idx >= 1 and idx <= #display_list then
                            local selected_icon = display_list[idx]
                            if mode == "system" then
                                local system_icon_name = selected_icon.name
                                local current = temp_overrides[system_icon_name]
                                UIManager:close(self)
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
                                return true
                            else
                                UIManager:close(self)
                                UIManager:setDirty("all", "full")
                                if on_select then on_select(selected_icon.value) end
                                return true
                            end
                        end
                    end
                    return true
                end,
            },
            {
                id = "picker_swipe",
                ges = "swipe",
                screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
                handler = function(ges)
                    local dir = ges.direction
                    if dir == "west" then
                        if cur_page < total_pages then
                            cur_page = cur_page + 1
                            UIManager:setDirty(self, function() return "ui", self.dimen end)
                        end
                    elseif dir == "east" then
                        if cur_page > 1 then
                            cur_page = cur_page - 1
                            UIManager:setDirty(self, function() return "ui", self.dimen end)
                        end
                    else
                        UIManager:close(self)
                        UIManager:setDirty("all", "full")
                        return true
                    end
                    return true
                end,
            },
        })
    end

    function PickerDlg:paintTo(bb, x, y)
        self.dimen.x = x
        self.dimen.y = y
        inner_frame.dimen = Geom:new{ x = frame_x, y = frame_y, w = frame_w, h = frame_h }
        inner_frame:paintTo(bb, frame_x, frame_y)

        local content_x = frame_x + pad
        local content_y = frame_y + pad

        local title_text
        if mode == "system" then
            title_text = _("System Icon Preview")
        elseif filter == "file" then
            title_text = _("Select Icon File")
        else
            title_text = _("Select Icon")
        end
        if filter_keyword ~= "" then
            title_text = title_text .. " [" .. _("Filter") .. ": \"" .. filter_keyword .. "\"]"
        end

        local title_tw = TextWidget:new{
            text = title_text,
            face = Font:getFace("smallinfofont"),
            bold = true,
        }
        local title_w = title_tw:getSize().w
        title_tw:paintTo(bb, content_x + (content_w - title_w) / 2, content_y + 12)

        local back_tw = TextWidget:new{
            text = "↶",
            face = Font:getFace("cfont", 24),
            fgcolor = Blitbuffer.COLOR_BLACK,
        }
        back_tw:paintTo(bb, content_x, content_y + 5)

        local search_char = QA.nerdIconChar("nerd:F002") or "?"
        local search_tw = TextWidget:new{
            text = search_char,
            face = Font:getFace("symbols", 22),
            fgcolor = Blitbuffer.COLOR_BLACK,
        }
        search_tw:paintTo(bb, content_x + content_w - 35, content_y + 5)

        local btn_y = content_y + title_bar_h
        btn_row:paintTo(bb, content_x, btn_y)

        local grid_start_x = content_x + (content_w - grid_w) / 2
        local grid_start_y = content_y + title_bar_h + button_bar_h

        local display_list = getDisplayList()
        if #display_list == 0 then
            local empty_tw = TextWidget:new{
                text = _("No matching icons"),
                face = Font:getFace("cfont"),
                fgcolor = Blitbuffer.COLOR_DARK_GRAY,
            }
            local empty_w = empty_tw:getSize().w
            empty_tw:paintTo(bb, grid_start_x + (grid_w - empty_w) / 2, grid_start_y + grid_h / 2 - 20)
        else
            page_widgets[cur_page]:paintTo(bb, grid_start_x, grid_start_y)
        end

        if total_pages > 1 then
            local bar_y = grid_start_y + grid_h + (footer_h - 20) / 2

            local left_arrow = TextWidget:new{
                text = "◀",
                face = Font:getFace("cfont", 20),
                fgcolor = Blitbuffer.COLOR_BLACK,
            }
            left_arrow:paintTo(bb, content_x + 10, bar_y)

            local right_arrow = TextWidget:new{
                text = "▶",
                face = Font:getFace("cfont", 20),
                fgcolor = Blitbuffer.COLOR_BLACK,
            }
            right_arrow:paintTo(bb, frame_x + frame_w - pad - 50, bar_y)

            local page_text = TextWidget:new{
                text = string.format("%d / %d", cur_page, total_pages),
                face = Font:getFace("cfont", 14),
                fgcolor = Blitbuffer.gray(0.5),
            }
            local text_w = page_text:getSize().w
            page_text:paintTo(bb, frame_x + (frame_w - text_w) / 2, bar_y)
        end
    end

    dialog = PickerDlg:new{}
    UIManager:show(dialog, "full")
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
