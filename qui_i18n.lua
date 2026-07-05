--[[
QuickUI - Internationalization (i18n) Module

Loads .po translation files from the locales/ directory and injects
them into KOReader's GetText system.
]]

local logger = require("logger")

-- Get the plugin directory path
local _dir = (debug.getinfo(1, "S").source:match("^@(.+/)") or "./")

--[[
Parse a .po file and return translations table

.po file format:
  msgid "original text"
  msgstr "translated text"

Returns: translations table, contexts table, entry count
]]
local function parsePO(path)
    local f = io.open(path, "r")
    if not f then return nil end

    local translations = {}
    local contexts = {}

    local ctx, id, str
    local in_id, in_str, in_ctx = false, false, false

    -- Unescape special characters from .po format
    local function unescape(s)
        return s:gsub("\\n", "\n"):gsub("\\t", "\t"):gsub('\\"', '"'):gsub("\\\\", "\\")
    end

    -- Flush current translation to the table
    local function flush()
        if id and id ~= "" and str and str ~= "" then
            if ctx and ctx ~= "" then
                if not contexts[ctx] then contexts[ctx] = {} end
                contexts[ctx][id] = str
            else
                translations[id] = str
            end
        end
        ctx, id, str = nil, nil, nil
        in_id, in_str, in_ctx = false, false, false
    end

    -- Parse each line
    for line in f:lines() do
        line = line:match("^%s*(.-)%s*$")
        if line == "" or line:match("^#") then
            if line == "" then flush() end
        elseif line:match("^msgctxt%s+\"") then
            flush()
            ctx = unescape(line:match('^msgctxt%s+"(.*)"') or "")
            in_ctx = true; in_id = false; in_str = false
        elseif line:match("^msgid%s+\"") then
            if not in_ctx then flush() end
            in_ctx = false
            id = unescape(line:match('^msgid%s+"(.*)"') or "")
            in_id = true; in_str = false
        elseif line:match("^msgstr%s+\"") then
            str = unescape(line:match('^msgstr%s+"(.*)"') or "")
            in_str = true; in_id = false; in_ctx = false
        elseif line:match('^"') then
            -- Multi-line continuation
            local cont = unescape(line:match('^"(.*)"') or "")
            if in_ctx and ctx then ctx = ctx .. cont end
            if in_id and id then id = id .. cont end
            if in_str and str then str = str .. cont end
        end
    end
    flush()
    f:close()

    local count = 0
    for _ in pairs(translations) do count = count + 1 end
    for _ in pairs(contexts) do count = count + 1 end

    return translations, contexts, count
end

--[[
Detect the user's current language setting

Returns: language code string (e.g., "zh_CN", "en")
]]
local function detectLang()
    -- Check KOReader's language setting first
    local lang = G_reader_settings and G_reader_settings:readSetting("language")
    if type(lang) == "string" and lang ~= "" then return lang end

    -- Fallback to environment variables
    local lc = os.getenv("LANG") or os.getenv("LC_ALL") or os.getenv("LC_MESSAGES") or ""
    lang = lc:match("^([a-zA-Z_]+)")
    return lang or "en"
end

--[[
Load translations for a specific language
]]
local function loadTranslationsForLang(lang)
    -- English is the default, no translation file needed
    if not lang or lang == "en" or lang:match("^en_") then return nil, nil end

    local function try(name)
        local path = _dir .. "locales/" .. name .. ".po"
        local t, c, n = parsePO(path)
        if t and n and n > 0 then
            return t, c
        end
        return nil, nil
    end

    -- Try exact match first (e.g., zh_CN.po)
    local t, c = try(lang)
    if t then return t, c end

    -- Try prefix match (e.g., zh.po for zh_CN, zh_TW, etc.)
    local prefix = lang:match("^([a-zA-Z]+)")
    if prefix and prefix ~= lang then
        return try(prefix)
    end

    return nil, nil
end

--[[
Inject translations into KOReader's GetText system
]]
local function applyTranslations(GetText, lang)
    local translations, contexts = loadTranslationsForLang(lang)
    if not translations then return end

    -- Inject into main translation table
    for msgid, msgstr in pairs(translations) do
        GetText.translation[msgid] = msgstr
    end

    -- Inject into context-aware translation tables
    for msgctxt, msgs in pairs(contexts or {}) do
        if not GetText.context[msgctxt] then
            GetText.context[msgctxt] = {}
        end
        for msgid, msgstr in pairs(msgs) do
            GetText.context[msgctxt][msgid] = msgstr
        end
    end
end

-- Module state
local _installed = false
local _orig_gettext = nil
local _orig_changeLang = nil

--[[
Install the i18n system
]]
local function install()
    if _installed then return end

    local GetText = package.loaded["gettext"]
    if not GetText then
        local ok, gt = pcall(require, "gettext")
        if not ok or not gt then
            logger.warn("QuickUI i18n: cannot load gettext — translations disabled")
            return
        end
        GetText = gt
    end
    _orig_gettext = GetText

    applyTranslations(GetText, detectLang())

    -- Hook into GetText's changeLang method
    local mt = getmetatable(GetText)
    if mt and type(mt.__index) == "table" then
        local mt_index = mt.__index
        _orig_changeLang = mt_index.changeLang
        mt_index.changeLang = function(new_lang)
            local result = _orig_changeLang(new_lang)
            applyTranslations(GetText, new_lang)
            return result
        end
    end

    _installed = true
end

--[[
Uninstall the i18n system
]]
local function uninstall()
    if not _installed then return end

    if _orig_gettext and _orig_changeLang then
        local mt = getmetatable(_orig_gettext)
        if mt and type(mt.__index) == "table" then
            mt.__index.changeLang = _orig_changeLang
            if _orig_changeLang then
                _orig_changeLang(_orig_gettext.current_lang)
            end
        end
    end

    _orig_changeLang = nil
    _orig_gettext = nil
    _installed = false
end

return {
    install = install,
    uninstall = uninstall,
    getLang = detectLang,
}
