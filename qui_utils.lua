--[[
QuickUI - Common Utility Functions
]]

local logger = require("logger")
local Blitbuffer = require("ffi/blitbuffer")
local Font = require("ui/font")
local Screen = require("device").screen
local _ = require("gettext")
local lfs = require("libs/libkoreader-lfs")
local UIManager = require("ui/uimanager")

local Utils = {}

-- ============================================================
-- Default Settings (single source of truth)
-- ============================================================

local DEFAULT_SETTINGS = {
    -- Panel Settings
    qa_panel_enabled = true,
    qa_panel_slots = {"wifi", "night", "rotate", "screenshot", "QuickUI_CoverSettings","system_icon_override", "ui_font_switch", "QuickUI_ClozeSettings", "QuickUI_HFSettings", "fontlist", "restart", "qa_settings","interface_filter", "qa_add_panel_button", "qa_new"},
    qa_panel_shape = "round",
    qa_panel_bg = "flat",
    qa_panel_labels = true,
    qa_panel_label_scale_pct = 90,
    qa_panel_settings_on_hold = true,
    qa_panel_button_size_pct = 100,
    qa_panel_button_hold_edit = true,
    qa_panel_frontlight          = true,
    qa_panel_warmth              = true,
    qa_panel_slider_show_value   = false,
    qa_panel_reader_font_size    = true,
    qa_panel_reader_line_spacing = true,
    qa_panel_reader_gamma        = false,
    qa_panel_reader_margins_h    = false,
    qa_panel_reader_margin_top   = false,
    qa_panel_reader_margin_bot   = false,
    qa_panel_reader_zoom         = false,

    -- Bottom Bar Settings
    qa_bb_enabled = true,
    qa_bb_mode = "both",
    qa_bb_style = "default",
    qa_bb_size_pct = 100,
    qa_bb_icon_scale_pct = 100,
    qa_bb_label_scale_pct = 100,
    qa_bb_bottom_margin_pct = 100,
    qa_bb_transparent = true,
    qa_bb_settings_on_hold = true,
    qa_bb_bg_color = "",
    qa_bb_fg_color = "",
    qa_bb_inactive_color = "",
    qa_bb_accent_color = "",
    qa_bb_labels = false,
    qa_bb_tabs = {"home", "annotations_viewer", "continue", "reading_insights", "qa_add_bb_tab","search","cloudlibrary_batch_download_books", "zlibrary_search"},
    qa_bb_reader_enabled = true,
    qa_bb_overlap = false,  -- Allow bottom bar to overlap content
    qa_bb_hide_in_pdf = true,

    -- Common Settings
    qa_common_enabled = true,
    qa_common_tab_icon = "star.empty",
    qa_common_context_filter = true,
    qa_common_auto_add_to_panel = true,
    qa_common_filter_initialized = false,
    qa_common_custom_list = {},
    qa_common_custom = {},
    qa_common_builtin_overrides = {},
    qa_common_icon_overrides = {},
    qa_common_ui_font_overrides = {},
    qa_common_icon_labels = false,

    -- Vertical Bar Settings
    qa_vb_enabled = true,
    qa_vb_side = "right",
    qa_vb_slots = {"quickui_settings", "system_icon_override", "ui_font_switch", "QuickUI_CoverSettings","bookshelf_toggle", "Sui-toggle", "continue", "annotations_viewer","artgallery_show",  "fontlist", "reader_sliders", "toggle_cloze_mode", "QuickUI_HFSettings","fingerink_bar", "toggle_side_toc", "reading_insights", "rssreader_open", "zlibrary_search", "fanqie_shelf_or_toc", "fanqie_search","weread_bookshelf", "weread_search", "weread_fetch_underlines",  "weread_quick_menu", "Sui-settings", "Sui-author", "Sui-series", "Sui-tags",  "koassistant_quick_actions", "koassistant_ai_settings", "storefront_open", "qa_add_vb_button"},
    qa_vb_labels = true,
    qa_vb_size_pct = 100,
    qa_vb_icon_scale_pct = 100,
    qa_vb_label_scale_pct = 100,
    qa_vb_button_hold_edit = true,
    qa_vb_settings_on_hold = true,
    qa_vb_bg = "white",
    qa_vb_animation = "fast",
    qa_vb_swipe_paging = true,
    
    -- Cover Settings
    cover_enabled = true,
    cover_placeholder_style = "simple",
    cover_badge_size = "normal",
    cover_badge_color_r = 204,
    cover_badge_color_g = 204,
    cover_badge_color_b = 204,
    cover_show_favorite = true,
    cover_show_progress = true,
    cover_show_new = true,
    cover_dim_finished = false,
    cover_show_pagecount = false,
    cover_show_format =false,
    cover_show_title_on_cover = false,
    cover_title_centered = false,
    cover_title_opaque = false,
    cover_ratio = "3:4",
    cover_rounded_corners = true,
    cover_show_title = false,
    cover_show_author = false,
    cover_hide_underline = true,
    cover_hide_up_folder = false,
    cover_folder_mode = "stack",
    cover_show_spine = false,
    cover_show_itemcount = true,
    cover_show_foldername = true,
    cover_name_centered = false,
    cover_name_opaque = false,

    -- Cloze Settings
    cl_enabled = true,
    cl_toggle_mode = 1,
    cl_drawers = { lighten = true, underscore = true, strikeout = true, invert = true },

    -- Header/Footer Settings
    hf_enabled = true,
    hf_header_enabled = true,
    hf_footer_enabled = true,
    hf_pdf_enabled = false,
    hf_top_left = "none",
    hf_top_center = "time",
    hf_top_right = "none",
    hf_bottom_left = "none",
    hf_bottom_center = "page",
    hf_bottom_right = "none",
    hf_header_font_face = "Noto Sans",
    hf_header_font_size = 14,
    hf_header_font_bold = false,
    hf_footer_font_face = "Noto Sans",
    hf_footer_font_size = 14,
    hf_footer_font_bold = false,
    hf_header_top_padding = 10,
    hf_footer_bottom_padding = 10,
    hf_left_offset = 0,
    hf_right_offset = 0,
    hf_time_format = "24h",
    hf_progress_decimals = 2,
}

-- ============================================================
-- Get the plugin directory path
-- ============================================================
local _plugin_dir = nil

function Utils.getPluginDir()
    if _plugin_dir then
        return _plugin_dir
    end

    local src = debug.getinfo(2, "S").source or ""
    if src:sub(1, 1) == "@" then
        local path = src:sub(2):match("^(.*)/[^/]+$")
        if path then
            if path:sub(1, 1) ~= "/" then
                local cwd = lfs.currentdir()
                if cwd then
                    path = cwd .. "/" .. path
                end
            end
            _plugin_dir = path .. "/"
            return _plugin_dir
        end
    end

    _plugin_dir = "./"
    return _plugin_dir
end

-- ============================================================
-- Configuration - Single global instance
-- ============================================================

local CONFIG_PATH = nil
local function getConfigPath()
    if CONFIG_PATH then return CONFIG_PATH end
    local ok, DataStorage = pcall(require, "datastorage")
    if ok and DataStorage then
        CONFIG_PATH = DataStorage:getSettingsDir() .. "/quickui.lua"
    else
        CONFIG_PATH = "quickui.lua"
    end
    return CONFIG_PATH
end

-- Global config instance, accessible via _G.__QUICKUI_CONFIG
_G.__QUICKUI_CONFIG = nil

function Utils.loadConfig()
    local data = {}
    local path = getConfigPath()
    local f = io.open(path, "r")
    if f then
        local content = f:read("*all")
        f:close()
        if content and content ~= "" then
            content = content:gsub("^\239\187\191", "")
            local chunk, err = load(content)
            if chunk then
                local ok, loaded = pcall(chunk)
                if ok and type(loaded) == "table" then
                    data = loaded
                end
            end
        end
    end

    -- Fill missing keys with defaults
    for key, default_val in pairs(DEFAULT_SETTINGS) do
        if data[key] == nil then
            data[key] = default_val
        end
    end

    _G.__QUICKUI_CONFIG = data
    return data
end

function Utils.saveConfig()
    local config = _G.__QUICKUI_CONFIG
    if not config then return end
    local f = io.open(getConfigPath(), "w")
    if f then
        f:write("return " .. Utils.serializeTable(config))
        f:close()
    end
    -- Reload after save to ensure consistency
    Utils.loadConfig()
end

function Utils.getDefaultSettings()
    return DEFAULT_SETTINGS
end

-- ============================================================
-- Configuration Getters/Setters (统一接口)
-- ============================================================

function Utils.get(key, default)
    local config = _G.__QUICKUI_CONFIG
    if config and config[key] ~= nil then
        return config[key]
    end
    return default
end

function Utils.getBool(key, default)
    local val = Utils.get(key, default)
    if type(val) == "boolean" then
        return val
    end
    return default or false
end

function Utils.getNumber(key, default)
    local val = Utils.get(key, default)
    if type(val) == "number" then
        return val
    end
    return default or 0
end

function Utils.getString(key, default)
    local val = Utils.get(key, default)
    if type(val) == "string" then
        return val
    end
    return default or ""
end

function Utils.getTable(key)
    local val = Utils.get(key, {})
    if type(val) == "table" then
        return val
    end
    return {}
end

function Utils.set(key, value)
    local config = _G.__QUICKUI_CONFIG
    if config then
        config[key] = value
        Utils.saveConfig()
    end
end

-- ============================================================
-- Refresh handler registry
-- ============================================================

local _refresh_handlers = {}

function Utils.registerRefreshHandler(module_key, handler)
    _refresh_handlers[module_key] = handler
end

-- ============================================================
-- Module Configuration Management
-- ============================================================

function Utils.getDefaultKeys(module_key)
    local keys = {
        qa_panel = {
            "qa_panel_enabled", "qa_panel_slots", "qa_panel_frontlight",
            "qa_panel_warmth", "qa_panel_slider_show_value", "qa_panel_shape",
            "qa_panel_bg", "qa_panel_labels", "qa_panel_label_scale_pct",
            "qa_panel_button_size_pct", "qa_panel_button_hold_edit",
            "qa_panel_settings_on_hold",
            "qa_panel_reader_font_size", "qa_panel_reader_line_spacing",
            "qa_panel_reader_gamma", "qa_panel_reader_margins_h",
            "qa_panel_reader_margin_top", "qa_panel_reader_margin_bot","qa_panel_reader_zoom",
        },
        qa_bb = {
            "qa_bb_enabled", "qa_bb_mode", "qa_bb_style", "qa_bb_size_pct",
            "qa_bb_icon_scale_pct", "qa_bb_label_scale_pct", "qa_bb_bottom_margin_pct",
            "qa_bb_transparent", "qa_bb_settings_on_hold", "qa_bb_button_hold_edit",
            "qa_bb_bg_color", "qa_bb_fg_color", "qa_bb_inactive_color",
            "qa_bb_accent_color", "qa_bb_labels", "qa_bb_tabs", "qa_bb_reader_enabled",
            "qa_bb_overlap",
        },
        qa_vb = {
            "qa_vb_enabled", "qa_vb_side", "qa_vb_slots", "qa_vb_labels",
            "qa_vb_size_pct", "qa_vb_icon_scale_pct", "qa_vb_label_scale_pct",
            "qa_vb_button_hold_edit", "qa_vb_settings_on_hold","qa_vb_bg", "qa_vb_animation", "qa_vb_swipe_paging",
        },
        qa_common = {
            "qa_common_tab_icon", "qa_common_custom_list", "qa_common_custom",
            "qa_common_builtin_overrides", "qa_common_context_filter",
            "qa_common_auto_add_to_panel", "qa_common_icon_overrides",
            "qa_common_ui_font_overrides", "qa_common_icon_labels",
        },
        cover = {
            "cover_enabled", "cover_placeholder_style", "cover_badge_size",
            "cover_badge_color_r", "cover_badge_color_g", "cover_badge_color_b",
            "cover_show_favorite", "cover_show_progress", "cover_show_new",
            "cover_dim_finished", "cover_show_pagecount", "cover_show_format",
            "cover_show_title_on_cover", "cover_title_centered", "cover_title_opaque",
            "cover_ratio", "cover_rounded_corners", "cover_show_title",
            "cover_show_author", "cover_hide_underline", "cover_hide_up_folder",
            "cover_folder_mode", "cover_show_spine", "cover_show_itemcount",
            "cover_show_foldername", "cover_name_centered", "cover_name_opaque",
        },
        cloze = {
            "cl_enabled", "cl_toggle_mode", "cl_drawers",
        },
        hf = {
            "hf_enabled", "hf_header_enabled", "hf_footer_enabled", "hf_pdf_enabled",
            "hf_top_left", "hf_top_center", "hf_top_right",
            "hf_bottom_left", "hf_bottom_center", "hf_bottom_right",
            "hf_header_font_face", "hf_header_font_size", "hf_header_font_bold",
            "hf_footer_font_face", "hf_footer_font_size", "hf_footer_font_bold",
            "hf_header_top_padding", "hf_footer_bottom_padding",
            "hf_left_offset", "hf_right_offset",
            "hf_time_format", "hf_progress_decimals",
        },
    }
    return keys[module_key] or {}
end

function Utils.moduleDisplayName(module_key)
    local names = {
        qa_panel = _("Panel"),
        qa_bb = _("Bottom Bar"),
        qa_common = _("Quick Actions"),
        cover = _("Cover"),
        cloze = _("Cloze"),
        hf = _("Header & Footer"),
    }
    return names[module_key] or module_key
end

function Utils.saveDefault(module_key)
    local config = _G.__QUICKUI_CONFIG
    if not config then return end

    local keys = Utils.getDefaultKeys(module_key)
    local default = {}

    for _, key in ipairs(keys) do
        local val = config[key]
        if val ~= nil then
            if type(val) == "table" then
                default[key] = Utils.deepCopy(val)
            else
                default[key] = val
            end
        end
    end

    config[module_key .. "_preset"] = default
    Utils.saveConfig()

    local Notification = require("ui/widget/notification")
    Notification:notify(string.format(_("%s preset saved"), Utils.moduleDisplayName(module_key)))
end

function Utils.applyDefault(module_keys)
    local config = _G.__QUICKUI_CONFIG
    if not config then
        local Notification = require("ui/widget/notification")
        Notification:notify(_("Configuration not loaded"))
        return false
    end

    -- Check which keys actually have a saved preset
    local has_preset = {}
    local any_preset = false
    for _, key in ipairs(module_keys) do
        local preset = config[key .. "_preset"]
        if type(preset) == "table" and next(preset) ~= nil then
            has_preset[key] = true
            any_preset = true
        end
    end

    -- If none of the keys have a preset, ask once whether to fall back to defaults
    if not any_preset then
        local names = {}
        for _, key in ipairs(module_keys) do
            names[#names + 1] = Utils.moduleDisplayName(key)
        end
        local ConfirmBox = require("ui/widget/confirmbox")
        UIManager:show(ConfirmBox:new{
            text = string.format(_("No saved preset for: %s.\n\nApply default settings instead?"),
                table.concat(names, ", ")),
            ok_text = _("Apply Default"),
            cancel_text = _("Cancel"),
            ok_callback = function()
                Utils.resetDefault(module_keys)
            end,
        })
        return false
    end

    -- Apply preset for keys that have one; silently reset keys that don't
    for _, key in ipairs(module_keys) do
        if has_preset[key] then
            local preset = config[key .. "_preset"]
            for k, v in pairs(preset) do
                if type(v) == "table" then
                    config[k] = Utils.deepCopy(v)
                else
                    config[k] = v
                end
            end
        else
            -- Silently reset this key without notifying
            local defaults = DEFAULT_SETTINGS
            for _, k in ipairs(Utils.getDefaultKeys(key)) do
                if defaults[k] ~= nil then
                    if type(defaults[k]) == "table" then
                        config[k] = Utils.deepCopy(defaults[k])
                    else
                        config[k] = defaults[k]
                    end
                end
            end
        end
    end

    Utils.saveConfig()

    -- Trigger refresh handlers for all affected keys
    for _, key in ipairs(module_keys) do
        local handler = _refresh_handlers[key]
        if handler then handler() end
    end

    -- One single notification for the whole batch
    local names = {}
    for _, key in ipairs(module_keys) do
        names[#names + 1] = Utils.moduleDisplayName(key)
    end
    local Notification = require("ui/widget/notification")
    Notification:notify(string.format(_("%s preset applied"), table.concat(names, ", ")))

    return true
end

function Utils.resetDefault(module_keys)
    local config = _G.__QUICKUI_CONFIG
    if not config then return end

    local defaults = DEFAULT_SETTINGS

    for _, key in ipairs(module_keys) do
        for _, k in ipairs(Utils.getDefaultKeys(key)) do
            if defaults[k] ~= nil then
                if type(defaults[k]) == "table" then
                    config[k] = Utils.deepCopy(defaults[k])
                else
                    config[k] = defaults[k]
                end
            end
        end
    end

    Utils.saveConfig()

    -- Trigger refresh handlers for all affected keys
    for _, key in ipairs(module_keys) do
        local handler = _refresh_handlers[key]
        if handler then handler() end
    end

    -- One single notification for the whole batch
    local names = {}
    for _, key in ipairs(module_keys) do
        names[#names + 1] = Utils.moduleDisplayName(key)
    end
    local Notification = require("ui/widget/notification")
    Notification:notify(string.format(_("%s reset to default"), table.concat(names, ", ")))

    return true
end

-- qui_utils.lua
function Utils.buildDefaultMenuItems(module_keys, refresh_callback)
    -- Accept either a single module key string or a table of keys
    if type(module_keys) == "string" then
        module_keys = {module_keys}
    end

    -- Determine suffix
    local suffix = ""
    local n = #module_keys

    if n == 1 then
        suffix = " (" .. module_keys[1] .. ")"
    else
        local qa_modules = {qa_common=true, qa_panel=true, qa_bb=true, qa_vb=true}
        local all_modules = {qa_common=true, qa_panel=true, qa_bb=true, qa_vb=true, cover=true, cloze=true, hf=true}

        local is_qa = true
        local is_all = true
        for _, key in ipairs(module_keys) do
            if not qa_modules[key] then
                is_qa = false
            end
            if not all_modules[key] then
                is_all = false
            end
        end

        if is_all and n == 7 then
            suffix = " (All)"
        elseif is_qa and n == 4 then
            suffix = " (QA)"
        else
            suffix = " (" .. table.concat(module_keys, " & ") .. ")"
        end
    end

    local items = {}

    -- 1. Save as preset
    table.insert(items, {
        text = _("Save as preset") .. suffix,
        callback = function()
            for _, key in ipairs(module_keys) do
                Utils.saveDefault(key)
            end
            if refresh_callback then refresh_callback() end
        end,
    })

    -- 2. Apply preset
    table.insert(items, {
        text = _("Apply preset") .. suffix,
        callback = function()
            Utils.applyDefault(module_keys)
            if refresh_callback then refresh_callback() end
        end,
    })

    -- 3. Reset to default
    table.insert(items, {
        text = _("Reset to default") .. suffix,
        callback = function()
            Utils.resetDefault(module_keys)
            if refresh_callback then refresh_callback() end
        end,
    })

    return items
end

-- ============================================================
-- Table Serialization
-- ============================================================

function Utils.serializeTable(t, indent)
    indent = indent or ""
    local lines = {}
    lines[#lines+1] = "{\n"
    local keys = {}
    for k in pairs(t) do table.insert(keys, k) end
    table.sort(keys)
    for i, k in ipairs(keys) do
        local v = t[k]
        local key_str
        if type(k) == "string" then
            key_str = string.format('["%s"]', k)
        else
            key_str = string.format('[%s]', tostring(k))
        end
        if type(v) == "table" then
            lines[#lines+1] = string.format('%s  %s = %s,', indent, key_str, Utils.serializeTable(v, indent .. "  "))
        elseif type(v) == "string" then
            local escaped = v:gsub('"', '\\"'):gsub("\n", "\\n")
            lines[#lines+1] = string.format('%s  %s = "%s",', indent, key_str, escaped)
        elseif type(v) == "number" then
            lines[#lines+1] = string.format('%s  %s = %s,', indent, key_str, tostring(v))
        elseif type(v) == "boolean" then
            lines[#lines+1] = string.format('%s  %s = %s,', indent, key_str, v and "true" or "false")
        end
    end
    lines[#lines+1] = indent .. "}"
    return table.concat(lines, "\n")
end

-- ============================================================
-- Deep Copy
-- ============================================================

function Utils.deepCopy(t, seen)
    seen = seen or {}
    if type(t) ~= "table" then return t end
    if seen[t] then return seen[t] end

    local copy = {}
    seen[t] = copy

    for k, v in pairs(t) do
        local k_copy = (type(k) == "table") and Utils.deepCopy(k, seen) or k
        local v_copy = (type(v) == "table") and Utils.deepCopy(v, seen) or v
        copy[k_copy] = v_copy
    end

    return copy
end

-- ============================================================
-- Font Utilities
-- ============================================================

function Utils.getFontFace(name, size)
    if not name or name == "" then
        name = "cfont"
    end
    local ok, face = pcall(Font.getFace, Font, name, math.max(1, math.floor(size or 14)))
    if ok and face then
        return face
    end
    return Font:getFace("cfont", math.max(1, math.floor(size or 14)))
end

function Utils.scaleBySize(val)
    return Screen:scaleBySize(val)
end

function Utils.getFontList()
    local cre = require("document/credocument"):engineInit()
    local FontList = require("fontlist")
    local faces = cre.getFontFaces()
    local result = {}
    if faces then
        for _, face in ipairs(faces) do
            local font_filename, font_faceindex = cre.getFontFaceFilenameAndFaceIndex(face)
            if not font_filename then
                font_filename, font_faceindex = cre.getFontFaceFilenameAndFaceIndex(face, nil, true)
            end
            local display_name = face
            if font_filename and font_faceindex then
                display_name = FontList:getLocalizedFontName(font_filename, font_faceindex) or face
            end
            table.insert(result, {
                name = face,
                display = display_name
            })
        end
        table.sort(result, function(a, b)
            return a.display:lower() < b.display:lower()
        end)
    end
    return result
end

function Utils.getAvailableFonts()
    local cre = require("document/credocument"):engineInit()
    local FontList = require("fontlist")
    local face_list = cre.getFontFaces()
    local result = {}

    for _, face in ipairs(face_list) do
        local font_filename, font_faceindex = cre.getFontFaceFilenameAndFaceIndex(face)
        if not font_filename then
            font_filename, font_faceindex = cre.getFontFaceFilenameAndFaceIndex(face, nil, true)
        end
        if font_filename then
            local fname = font_filename:match("([^/]+)$") or font_filename
            if fname:match("%.ttf$") or fname:match("%.otf$") then
                local display = face
                if font_faceindex then
                    display = FontList:getLocalizedFontName(font_filename, font_faceindex) or face
                end
                table.insert(result, {
                    name    = fname,          -- 文件名，用于 patch Font.fontmap
                    display = display,        -- 显示名
                    path    = font_filename,  -- 完整路径，用于 font_face 预览
                    face    = face,           -- face 名，用于最近排序
                })
            end
        end
    end

    table.sort(result, function(a, b)
        return a.display:lower() < b.display:lower()
    end)

    return result
end

function Utils.splitFilePathName(path)
    if not path or path == "" then return nil, nil end
    local fname = path:match("([^/]+)$")
    local dir = path:sub(1, #path - #fname - 1)
    return dir, fname
end

-- ============================================================
-- Color Utilities
-- ============================================================

function Utils.hexToColor(hex)
    if type(hex) ~= "string" then return Blitbuffer.COLOR_BLACK end
    hex = hex:gsub("#", "")
    if #hex == 6 then
        local r = tonumber(hex:sub(1,2), 16) or 0
        local g = tonumber(hex:sub(3,4), 16) or 0
        local b = tonumber(hex:sub(5,6), 16) or 0
        return Blitbuffer.ColorRGB32(r, g, b, 255)
    elseif #hex == 8 then
        local r = tonumber(hex:sub(1,2), 16) or 0
        local g = tonumber(hex:sub(3,4), 16) or 0
        local b = tonumber(hex:sub(5,6), 16) or 0
        local a = tonumber(hex:sub(7,8), 16) or 255
        return Blitbuffer.ColorRGB32(r, g, b, a)
    end
    return Blitbuffer.COLOR_BLACK
end

function Utils.rgb(r, g, b)
    return Blitbuffer.ColorRGB32(r or 0, g or 0, b or 0, 255)
end

-- ============================================================
-- Debug / Introspection Utilities
-- ============================================================

function Utils.getUpvalue(fn, name)
    if type(fn) ~= "function" then return nil end
    for i = 1, 128 do
        local upname, value = debug.getupvalue(fn, i)
        if not upname then break end
        if upname == name then return value end
    end
    return nil
end

function Utils.setUpvalue(fn, name, value)
    if type(fn) ~= "function" then return false end
    for i = 1, 128 do
        local upname = debug.getupvalue(fn, i)
        if not upname then break end
        if upname == name then
            debug.setupvalue(fn, i, value)
            return true
        end
    end
    return false
end

-- ============================================================
-- File System Utilities
-- ============================================================

function Utils.fileExists(path)
    if not path or path == "" then return false end
    local ok, attr = pcall(lfs.attributes, path)
    return ok and attr and attr.mode == "file"
end

function Utils.dirExists(path)
    if not path or path == "" then return false end
    local ok, attr = pcall(lfs.attributes, path)
    return ok and attr and attr.mode == "directory"
end

function Utils.basename(path)
    if not path or path == "" then return "" end
    return path:match("([^/]+)$") or path
end

function Utils.stem(path)
    local name = Utils.basename(path)
    return name:gsub("%.[^%.]+$", "")
end

function Utils.extension(path)
    local name = Utils.basename(path)
    return name:match("%.([^%.]+)$") or ""
end

-- ============================================================
-- String Utilities
-- ============================================================

function Utils.truncate(text, max_len)
    if not text or text == "" then return "" end
    if #text <= max_len then return text end
    return text:sub(1, max_len - 1) .. "…"
end

-- ============================================================
-- Table Utilities
-- ============================================================

function Utils.isEmpty(t)
    if not t then return true end
    return next(t) == nil
end

-- ============================================================
-- UI / Display Utilities
-- ============================================================

function Utils.parseAspectRatio(ratio_str)
    if not ratio_str then return 3/4 end
    local num, den = ratio_str:match("(%d+):(%d+)")
    if num and den then
        return tonumber(num) / tonumber(den)
    end
    return 3/4
end

function Utils.calcDims(max_w, max_h, ratio_str)
    local ratio = Utils.parseAspectRatio(ratio_str)
    local target_h = max_h
    local target_w = math.floor(target_h * ratio)

    if target_w > max_w then
        target_w = max_w
        target_h = math.floor(target_w / ratio)
    end

    return target_w, target_h
end

-- ============================================================
-- Icon Utilities
-- ============================================================

function Utils.getIconsDirPath()
    local ok, DataStorage = pcall(require, "datastorage")
    if ok and DataStorage then
        return DataStorage:getDataDir() .. "/icons"
    end
    return "./icons"
end

function Utils.getIconFile(icon_name)
    if not icon_name then return nil end

    if icon_name:match("^nerd:") then
        return icon_name
    end

    if icon_name:sub(1,1) == "/" then
        if Utils.fileExists(icon_name) then
            return icon_name
        end
        return nil
    end

    local filename = icon_name:match("([^/]+)$") or icon_name
    local dirs_to_check = {
        Utils.getIconsDirPath(),
        "resources/icons/mdlight",
        "resources/icons",
        "resources",
    }
    for _, dir in ipairs(dirs_to_check) do
        local path = dir .. "/" .. filename
        if Utils.fileExists(path) then
            return path
        end
    end

    return nil
end

-- ============================================================
-- Patch FileChooser for Bottom Navigation Bar
-- ============================================================

function Utils.patchFileChooserForBottombar()
    local FileChooser = require("ui/widget/filechooser")
    if FileChooser._quickui_bottombar_patched then return end
    FileChooser._quickui_bottombar_patched = true

    -- ── 缩高度（原有逻辑不变） ──────────────────────────────
    local orig_init = FileChooser.init
    FileChooser.init = function(fc_self, ...)
        if fc_self.height == nil and fc_self.width == nil then
            local bb = _G.__QUICKUI_PLUGIN_STORE and _G.__QUICKUI_PLUGIN_STORE.bottombar
            if bb and bb.isEnabled and bb.isEnabled() then
                local screen_h = Screen:getHeight()
                local nav_h = bb.TOTAL_H()
                fc_self.height = screen_h - nav_h
                fc_self.y = 0
            end
        end
        return orig_init(fc_self, ...)
    end

    local orig_recalc = FileChooser._recalculateDimen
    FileChooser._recalculateDimen = function(fc_self, ...)
        local bb = _G.__QUICKUI_PLUGIN_STORE and _G.__QUICKUI_PLUGIN_STORE.bottombar
        if bb and bb.isEnabled and bb.isEnabled() then
            local screen_h = Screen:getHeight()
            local nav_h = bb.TOTAL_H()
            local content_h = screen_h - nav_h
            if fc_self.height ~= content_h then fc_self.height = content_h end
            if fc_self.y ~= 0 then fc_self.y = 0 end
        end
        return orig_recalc(fc_self, ...)
    end

    local orig_update = FileChooser.updateItems
    FileChooser.updateItems = function(fc_self, ...)
        local bb = _G.__QUICKUI_PLUGIN_STORE and _G.__QUICKUI_PLUGIN_STORE.bottombar
        if bb and bb.isEnabled and bb.isEnabled() then
            local screen_h = Screen:getHeight()
            local nav_h = bb.TOTAL_H()
            local content_h = screen_h - nav_h
            if fc_self.height ~= content_h then fc_self.height = content_h end
            if fc_self.y ~= 0 then fc_self.y = 0 end
        end
        return orig_update(fc_self, ...)
    end

    -- ★ 新增：一次性注入，等价于 ReaderUI 的 patchReaderUIForBottombar ──
    local FileManager = require("apps/filemanager/filemanager")
    if not FileManager._quickui_fm_inject_patched then
        FileManager._quickui_fm_inject_patched = true
        local orig_setup = FileManager.setupLayout
        FileManager.setupLayout = function(fm_self)
            orig_setup(fm_self)

            local bb = _G.__QUICKUI_PLUGIN_STORE and _G.__QUICKUI_PLUGIN_STORE.bottombar
            if not (bb and bb.isEnabled and bb.isEnabled()) then return end

            -- 已经注入过则跳过（幂等）
            if fm_self._bottombar_injected then return end

            -- 拿 fm_self[1] 作为 inner。如果它已经被 QuickUI 包过（比如
            -- rebuildBottombar 先跑过一次），剥到真正的 inner。
            local inner = fm_self[1]
            if inner and inner._bottombar_inner then
                inner = inner._bottombar_inner
            end
            if not inner then return end

            local wrapped = bb.wrapWithBottombar(inner)
            if wrapped and wrapped ~= inner then
                fm_self[1] = wrapped
                fm_self._bottombar_injected = true
                fm_self._bottombar_inner = inner
                fm_self._bottombar_original_inner = inner
                UIManager:scheduleIn(0, function()
                    if bb.registerTouchZones then bb.registerTouchZones(fm_self) end
                end)
            end
        end
    end
end

-- ============================================================
-- Patch ReaderUI for Bottom Navigation Bar
-- ============================================================
function Utils.patchReaderUIForBottombar()
    local ReaderUI = require("apps/reader/readerui")
    if ReaderUI._quickui_bottombar_patched then return end
    ReaderUI._quickui_bottombar_patched = true

    local Geom = require("ui/geometry")
    local orig_new = ReaderUI.new

    ReaderUI.new = function(class, attrs, ...)
        attrs = attrs or {}

        -- ============================================================
        -- Same gating logic as rebuildBottombar:
        --   1. Bottom bar globally enabled
        --   2. "Show in reader" is not false
        --   3. Not (hide_in_pdf AND current doc is PDF)
        -- ============================================================
        local bb = _G.__QUICKUI_PLUGIN_STORE and _G.__QUICKUI_PLUGIN_STORE.bottombar
        local should_inject = false
        local shrink_height = false
        local nav_h = 0

        if bb and bb.isEnabled and bb.isEnabled() then
            local config = _G.__QUICKUI_CONFIG
            local show_in_reader = config and config.qa_bb_reader_enabled
            local hide_in_pdf = config and config.qa_bb_hide_in_pdf
            local is_pdf = false
            if attrs.document and attrs.document.file then
                is_pdf = attrs.document.file:match("%.pdf$") ~= nil
            end

            if show_in_reader ~= false and not (hide_in_pdf and is_pdf) then
                should_inject = true
                nav_h = bb.TOTAL_H()
                -- Only shrink reader height when overlap is NOT enabled
                if not Utils.getBool("qa_bb_overlap", false) then
                    shrink_height = true
                end
            end
        end

        -- Shrink the reader's dimen BEFORE ReaderView is created,
        -- so CREngine/PDF layout uses the reduced height from the start.
        -- Skip when overlap mode is enabled (content should go under the bar).
        if should_inject and shrink_height and nav_h > 0 and attrs.dimen then
            local d = attrs.dimen
            attrs.dimen = Geom:new{
                x = d.x or 0,
                y = d.y or 0,
                w = d.w or Screen:getWidth(),
                h = (d.h or Screen:getHeight()) - nav_h,
            }
        end

        local instance = orig_new(class, attrs, ...)

        if should_inject then
            -- Inject the bottom bar widget into reader[1]
            local inner = instance[1]
            if inner and not inner._bottombar_inner then
                inner._bottombar_injected_container = true
                local wrapped = bb.wrapWithBottombar(inner)
                if wrapped and wrapped ~= inner then
                    instance[1] = wrapped
                    instance._bottombar_injected = true
                    instance._bottombar_inner = inner
                    instance._bottombar_original_inner = inner
                else
                    inner._bottombar_injected_container = nil
                end
            end

            -- Register touch zones after the reader is on screen
            UIManager:scheduleIn(0, function()
                if bb.registerTouchZones then
                    bb.registerTouchZones(instance)
                end
            end)
        end

        return instance
    end
end

-- ============================================================
-- Patch BookList for Bottom Navigation Bar
-- ============================================================

function Utils.patchBookListForBottombar()
    local BookList = require("ui/widget/booklist")
    if BookList._quickui_patched then return end
    BookList._quickui_patched = true

    local orig_new = BookList.new
    BookList.new = function(class, attrs, ...)
        attrs = attrs or {}
        local is_booklist = attrs.name == "history" or attrs.name == "collections" or attrs.name == "coll_list" or attrs.name == "filesearcher" 

        if is_booklist then
            local bb = _G.__QUICKUI_PLUGIN_STORE and _G.__QUICKUI_PLUGIN_STORE.bottombar
            if bb and bb.isEnabled and bb.isEnabled() then
                local nav_h = bb.TOTAL_H()
                attrs.height = Screen:getHeight() - nav_h
                attrs.width = Screen:getWidth()
                attrs._navbar_height_reduced = true
            end
        end

        local instance = orig_new(class, attrs, ...)

        if is_booklist then
            local bb = _G.__QUICKUI_PLUGIN_STORE and _G.__QUICKUI_PLUGIN_STORE.bottombar
            if bb and bb.isEnabled and bb.isEnabled() then
                -- Inject the bottom bar BEFORE UIManager:show runs,
                -- so the very first paint already includes the bar (single flash).
                local inner = instance[1]
                if inner and not inner._bottombar_inner then
                    inner._bottombar_injected_container = true
                    local wrapped = bb.wrapWithBottombar(inner)
                    if wrapped and wrapped ~= inner then
                        instance[1] = wrapped
                        instance._bottombar_injected = true
                        instance._bottombar_inner = inner
                    else
                        inner._bottombar_injected_container = nil
                    end
                end

                -- Register touch zones after the widget is on screen
                -- (needs dimen to be settled).
                UIManager:scheduleIn(0, function()
                    if bb.registerTouchZones then
                        bb.registerTouchZones(instance)
                    end
                end)
            end
        end

        return instance
    end
end

-- ============================================================
-- Patch SimpleUI for Bottom Navigation Bar
--
-- SimpleUI is an optional third-party plugin — unlike FileManager /
-- ReaderUI / BookList (all built into KOReader), it may not be installed.
-- Everything here must therefore go through pcall(require) and bail out
-- silently when SimpleUI is absent, so QuickUI never breaks on its behalf.
--
-- Two hook points:
--   ScreenEngine._open              — first show of any screen
--   ScreenEngine.rebuildAllLayouts  — rotation / theme / wallpaper rebuilds,
--                                     which replace _navbar_container in place
--                                     without going through _open.
-- ============================================================
function Utils.patchSimpleUIHomescreenForBottombar()
    local ok, ScreenEngine = pcall(require, "engines/sui_screen_engine")
    if not ok or not ScreenEngine then return end        -- SimpleUI not installed
    if type(ScreenEngine._open) ~= "function" then return end
    if ScreenEngine._quickui_bb_patched then return end  -- idempotent
    ScreenEngine._quickui_bb_patched = true

    local function inject(w)
        local bb = _G.__QUICKUI_PLUGIN_STORE and _G.__QUICKUI_PLUGIN_STORE.bottombar
        if bb and bb.injectIntoScreenWidget and w then
            bb.injectIntoScreenWidget(w)
        end
    end

    -- Hook 1: first show
    local orig_open = ScreenEngine._open
    ScreenEngine._open = function(instance_cfg, on_qa_tap, on_goal_tap)
        local w = orig_open(instance_cfg, on_qa_tap, on_goal_tap)
        inject(w)
        return w
    end

    -- Hook 2: in-place rebuilds (rotation, style/wallpaper changes)
    local orig_rebuild = ScreenEngine.rebuildAllLayouts
    if orig_rebuild then
        ScreenEngine.rebuildAllLayouts = function(...)
            local r = orig_rebuild(...)
            local bb = _G.__QUICKUI_PLUGIN_STORE and _G.__QUICKUI_PLUGIN_STORE.bottombar
            if bb and bb.injectIntoScreenWidget then
                for _i, id in ipairs(ScreenEngine.liveScreenIds()) do
                    local inst = ScreenEngine.getInstance(id)
                    if inst then
                        -- Container was rebuilt — allow re-injection.
                        inst._quickui_bb_injected = nil
                        bb.injectIntoScreenWidget(inst)
                    end
                end
            end
            return r
        end
    end
end
-- ============================================================
-- Search Utilities
-- ============================================================

local InputDialog = require("ui/widget/inputdialog")

--[[
Filter actions by keyword (matches label, id, view).
@param actions - table of action objects { id, label, view, ... }
@param keyword - search keyword
@return filtered table of actions
]]
function Utils.filterActionsByKeyword(actions, keyword)
    if not keyword or keyword == "" then
        return actions
    end
    local filtered = {}
    local keyword_lower = keyword:lower()
    for _, action in ipairs(actions) do
        local view = action.view or "common"
        if (action.label or ""):lower():find(keyword_lower, 1, true)
           or (action.id or ""):lower():find(keyword_lower, 1, true)
           or view:lower():find(keyword_lower, 1, true) then
            table.insert(filtered, action)
        end
    end
    return filtered
end

--[[
Create a search button for any ButtonDialog menu.
@param on_back - function to call when going back (after search dialog closes)
@param on_search - function to call with search keyword: on_search(keyword)
@param on_open - function to call before opening search dialog (e.g., close current dialog)
@return button definition table
]]
function Utils.createSearchButton(on_back, on_search, on_open)
    local UIManager = require("ui/uimanager")
    local InputDialog = require("ui/widget/inputdialog")

    local search_icon = "🔍"
    local ok, QA = pcall(require, "qui_actions.qa_actions")
    if ok and QA and QA.nerdIconChar then
        local icon = QA.nerdIconChar("nerd:F002")
        if icon then
            search_icon = icon
        end
    end

    return {
        text = search_icon .. " " .. _("Search..."),
        callback = function()
            -- Close current dialog before opening search
            if on_open then
                on_open()
            end

            local search_dialog

            search_dialog = InputDialog:new{
                title = _("Search"),
                input = "",
                input_hint = _("Search label, id (e.g. custom), or view"),
                buttons = {
                    {
                        {
                            text = _("Back"),
                            callback = function()
                                UIManager:close(search_dialog)
                                if on_back then on_back() end
                            end,
                        },
                        {
                            text = _("Cancel"),
                            id = "close",
                            callback = function()
                                UIManager:close(search_dialog)
                            end,
                        },
                        {
                            text = _("Search"),
                            is_enter_default = true,
                            callback = function()
                                local keyword = search_dialog:getInputText()
                                UIManager:close(search_dialog)
                                if keyword and keyword ~= "" then
                                    if on_search then on_search(keyword) end
                                else
                                    if on_back then on_back() end
                                end
                            end,
                        },
                    }
                },
            }
            UIManager:show(search_dialog)
            pcall(function() search_dialog:onShowKeyboard() end)
        end,
    }
end

return Utils
