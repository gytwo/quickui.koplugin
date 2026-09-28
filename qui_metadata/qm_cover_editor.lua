--[[
QuickUI - Cover Editor

Pick a cover for the current book:
  1. From a local image file (PathChooser)
  2. From an online metadata source (reuses the metadata provider list)

The chosen image is written into the book's sidecar as cover.<ext>
via DocSettings:flushCustomCover, so KOReader's file browser / history /
Book info all pick it up.
]]

local ButtonDialog = require("ui/widget/buttondialog")
local InfoMessage = require("ui/widget/infomessage")
local Notification = require("ui/widget/notification")
local PathChooser = require("ui/widget/pathchooser")
local DocumentRegistry = require("document/documentregistry")
local Screen = require("device").screen
local UIManager = require("ui/uimanager")
local Event = require("ui/event")
local _ = require("gettext")
local logger = require("logger")

local Http = require("qui_metadata.qm_http")

local M = {}

-- Same provider list as qm_provider_picker.lua.
local PROVIDERS = {
    { id = "douban",       name = _("Douban"),       key_config = nil,                       require_key = false },
    { id = "weread",       name = _("WeRead"),       key_config = "metadata_weread_key",     require_key = true  },
    { id = "google_books", name = _("Google Books"), key_config = "metadata_google_books_key", require_key = true },
    { id = "hardcover",    name = _("Hardcover"),    key_config = "metadata_hardcover_token", require_key = true },
    { id = "open_library", name = _("Open Library"), key_config = nil,                       require_key = false },
}

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
-- remove custom cover
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
    pcall(function() DocSettings:getCustomCoverFile(true) end)  -- 清缓存

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
        M.show_result_list(editor, provider, works)
    end)
end

-- ============================================================
-- Result list (same shape as the metadata picker's)
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

function M.show_result_list(editor, provider, works)
    local key = provider_key(provider)
    local Mod = provider_module(provider)

    local buttons = {}
    table.insert(buttons, {{
        text = "◂ " .. _("Back"),
        callback = function()
            UIManager:close(editor.dialog)
            UIManager:nextTick(function() M.search_online(editor) end)
        end,
    }})
    table.insert(buttons, {})

    for _i, work in ipairs(works) do
        local edition
        local ok, editions = pcall(Mod.editions, key, work)
        if ok and type(editions) == "table" and #editions > 0 then
            edition = editions[1]
        end
        local label = result_label(work, edition)
        local _work = work
        table.insert(buttons, {{
            text = label,
            callback = function()
                UIManager:close(editor.dialog)
                UIManager:nextTick(function()
                    M.download_and_apply(editor, provider, _work)
                end)
            end,
        }})
    end

    editor.dialog = ButtonDialog:new{
        title = _("Select a cover"),
        title_align = "center",
        buttons = buttons,
        width = math.floor(Screen:getWidth() * 0.8),
        max_height = math.floor(Screen:getHeight() * 0.75),
        rows_per_page = 10,
    }
    UIManager:show(editor.dialog)
end

-- ============================================================
-- Download + apply
-- ============================================================

function M.download_and_apply(editor, provider, work)
    local Mod = provider_module(provider)
    local url = Mod.cover_url and Mod.cover_url(work) or nil
    if not url or url == "" then
        UIManager:show(InfoMessage:new{
            text = _("This result has no cover."),
            timeout = 3,
        })
        UIManager:nextTick(function() M.show_result_list(editor, provider, { work }) end)
        return
    end

    UIManager:show(Notification:new{
        text = _("Downloading cover..."),
        timeout = 1,
    })

    UIManager:scheduleIn(0.1, function()
        local ext = url:match("%.([pP][nN][gG])[%?%#]?$") and "png" or "jpg"
        local tmp = "/tmp/quickui_cover." .. ext

        local host = url:match("^https://([^/]+)")
        if not host then
            UIManager:show(InfoMessage:new{
                text = _("Invalid cover URL"),
                timeout = 3,
            })
            return
        end

        local referer = Mod.cover_referer or ("https://" .. host .. "/")
        local path, err = Http.download(url, tmp, host, {
            ["Referer"] = referer,
            ["Accept"] = "image/jpeg, image/png, image/webp, image/gif",
        })
        if not path then
            UIManager:show(InfoMessage:new{
                text = _("Download failed") .. ": " .. tostring(err),
                timeout = 3,
            })
            return
        end

        M.apply_cover(editor, tmp)
        os.remove(tmp)
    end)
end

-- ============================================================
-- Apply
-- ============================================================

function M.apply_cover(editor, image_path)
    local DocSettings = require("docsettings")
    local ok = DocSettings:flushCustomCover(editor.file, image_path)
    if not ok then
        UIManager:show(InfoMessage:new{
            text = _("Failed to set cover."),
            timeout = 3,
        })
        return
    end

    UIManager:broadcastEvent(Event:new("InvalidateMetadataCache", editor.file))
    UIManager:broadcastEvent(Event:new("BookMetadataChanged"))

    UIManager:show(Notification:new{
        text = _("Cover updated"),
        timeout = 2,
    })

    UIManager:nextTick(function() editor:show_menu() end)
end

return M