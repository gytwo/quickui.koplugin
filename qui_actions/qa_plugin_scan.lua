--[[
QuickUI - Plugin Scanner

Scans for available plugins and their menu entries.
Supports both regular plugins and patch menu items.

Original: 2-quickactions.lua (PluginScan)
]]

local logger = require("logger")
local _ = require("gettext")
local Screen = require("device").screen
local UIManager = require("ui/uimanager")
local Device = require("device")

local InfoMessage = require("ui/widget/infomessage")
local ButtonDialog = require("ui/widget/buttondialog")
local icon_picker = require("qui_actions/qa_icon_picker")
local settings_icon = icon_picker.nerdIconChar("nerd:E73A") or "⚙️"

-- ============================================================
-- Global storage
-- ============================================================

local PLUGIN_STORE = _G.__QUICKUI_PLUGIN_STORE or {}
_G.__QUICKUI_PLUGIN_STORE = PLUGIN_STORE

local function getPlugin()
    return PLUGIN_STORE.plugin_ref
end

local PluginScan = {}

-- ============================================================
-- Constants
-- ============================================================

local EXCLUDED_PLUGINS = {
    quickui = true,
}

local LAUNCH_METHODS = { "onShow", "show", "open", "launch", "onOpen" }

local PluginScan_sentinel = "__menu_callback"
local PluginScan_submenu = "__menu_submenu"

-- ============================================================
-- Stub for menu callbacks
-- ============================================================

local TOUCHMENU_STUB = {
    closeMenu = function() end,
    onClose = function() end,
    updateItems = function() end,
    handleEvent = function() return false end,
}

-- ============================================================
-- Helper Functions
-- ============================================================

local function plugin_loader()
    local ok, loader = pcall(require, "pluginloader")
    return ok and loader or nil
end

local function live_uis()
    local out = {}
    local fm_mod = package.loaded["apps/filemanager/filemanager"]
    if fm_mod and fm_mod.instance then
        out[#out + 1] = fm_mod.instance
    end
    local reader_mod = package.loaded["apps/reader/readerui"]
    if reader_mod and reader_mod.instance then
        out[#out + 1] = reader_mod.instance
    end
    return out
end

local function enabled_plugin_names()
    local names = {}
    local loader = plugin_loader()
    if not (loader and type(loader.loadPlugins) == "function") then
        return names
    end
    local ok, enabled = pcall(loader.loadPlugins, loader)
    if not ok or type(enabled) ~= "table" then
        return names
    end
    for _, plugin in ipairs(enabled) do
        if type(plugin) == "table" and type(plugin.name) == "string" then
            names[plugin.name] = true
        end
    end
    names.zen_ui = nil
    return names
end

local function is_callable(value)
    if type(value) == "function" then return true end
    local mt = type(value) == "table" and getmetatable(value) or nil
    return type(mt) == "table" and type(mt.__call) == "function"
end

local function probe_menu_entry(mod, key)
    if type(mod.addToMainMenu) ~= "function" then return nil end
    local probe = {}
    local ok = pcall(mod.addToMainMenu, mod, probe)
    if not ok then return nil end
    local entry = probe[key]
    if entry == nil and type(mod.name) == "string" then
        entry = probe[mod.name]
    end
    if entry == nil then
        local only, count = nil, 0
        for _, value in pairs(probe) do
            if type(value) == "table" then
                count = count + 1
                only = value
            end
        end
        if count == 1 then entry = only end
    end
    return type(entry) == "table" and entry or nil
end

local function text_without_glyph(text)
    if type(text) ~= "string" then return nil end
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function entry_text(entry)
    if type(entry) ~= "table" then return nil end
    if type(entry.text_func) == "function" then
        local ok, text = pcall(entry.text_func)
        if ok then return text_without_glyph(text) end
    end
    return text_without_glyph(entry.text)
end

local function find_method(mod, key)
    for _, method in ipairs(LAUNCH_METHODS) do
        if is_callable(mod[method]) then return method end
    end
    local camel = "on" .. key:sub(1, 1):upper() .. key:sub(2)
    if is_callable(mod[camel]) then return camel end
    local entry = probe_menu_entry(mod, key)
    if entry then
        if type(entry.callback) == "function" then
            return PluginScan_sentinel
        end
        if entry.sub_item_table ~= nil or entry.sub_item_table_func ~= nil then
            return PluginScan_submenu
        end
    end
end

local function live_plugin(key)
    local loader = plugin_loader()
    local loaded = loader and loader.loaded_plugins
    if type(loaded) == "table" and type(loaded[key]) == "table" then
        return loaded[key]
    end
    if loader and type(loader.getPluginInstance) == "function" then
        local ok, plugin_inst = pcall(loader.getPluginInstance, loader, key)
        if ok and type(plugin_inst) == "table" then
            return plugin_inst
        end
    end
    for _, ui in ipairs(live_uis()) do
        if type(ui[key]) == "table" then
            return ui[key]
        end
    end
    return nil
end

local function add_candidate(out, seen, key, mod)
    if type(key) ~= "string" or key == "" or EXCLUDED_PLUGINS[key] or seen[key]
            or type(mod) ~= "table" then
        return
    end
    local method = find_method(mod, key)
    if not method then return end
    seen[key] = true
    local entry = probe_menu_entry(mod, key)
    local title = entry_text(entry)
    if not title or title == "" then
        title = key:sub(1, 1):upper() .. key:sub(2)
    end
    out[#out + 1] = { key = key, method = method, title = title }
end

-- ============================================================
-- Scan for Plugins and Patches
-- ============================================================

function PluginScan.scan()
    local ok, results = pcall(function()
        local out, seen = {}, {}
        local loader = plugin_loader()

        -- Scan loaded plugins
        if loader and type(loader.loaded_plugins) == "table" then
            for key, mod in pairs(loader.loaded_plugins) do
                add_candidate(out, seen, key, mod)
            end
        end

        -- Scan enabled plugins
        local names = enabled_plugin_names()
        if loader and type(loader.getPluginInstance) == "function" then
            for key in pairs(names) do
                local ok_plugin, plugin_inst = pcall(loader.getPluginInstance, loader, key)
                if ok_plugin then
                    add_candidate(out, seen, key, plugin_inst)
                end
            end
        end

        -- Scan live UIs
        for _, ui in ipairs(live_uis()) do
            for key in pairs(names) do
                add_candidate(out, seen, key, ui[key])
            end
        end

        -- Scan patches from menu_items
        local FM = require("apps/filemanager/filemanager")
        local fm = FM and FM.instance
        local RUI = require("apps/reader/readerui")
        local reader = RUI and RUI.instance

        local function scanPatchItems(items, parent_title)
            if type(items) ~= "table" then return end
            for _, item in ipairs(items) do
                if type(item) == "table" then
                    local text = entry_text(item)

                    local sub = item.sub_item_table
                    if sub == nil and type(item.sub_item_table_func) == "function" then
                        local ok_sub, res = pcall(item.sub_item_table_func, TOUCHMENU_STUB)
                        if ok_sub then sub = res end
                    end

                    if type(sub) == "table" and #sub > 0 then
                        scanPatchItems(sub, text)
                    elseif text and type(item.callback) == "function" then
                        local display_title = parent_title and (parent_title .. " · " .. text) or text
                        local patch_key = "patch_" .. display_title
                        if not seen[patch_key] then
                            seen[patch_key] = true
                            table.insert(out, {
                                key = patch_key,
                                method = PluginScan_sentinel,
                                title = text,
                                display_title = display_title,
                                is_patch = true,
                            })
                        end
                    end
                end
            end
        end

        if fm and fm.menu and fm.menu.menu_items then
            scanPatchItems(fm.menu.menu_items)
        end

        if reader and reader.menu and reader.menu.menu_items then
            scanPatchItems(reader.menu.menu_items)
        end

        table.sort(out, function(a, b) return (a.title or ""):lower() < (b.title or ""):lower() end)
        return out
    end)

    return ok and results or {}
end

-- ============================================================
-- Execute Plugin or Patch
-- ============================================================

function PluginScan.executePlugin(plugin_key, plugin_method, ctx)
    -- Handle patches (patch_ prefix)
    if type(plugin_key) == "string" and string.sub(plugin_key, 1, 6) == "patch_" then
        local full_name = string.sub(plugin_key, 7)
        local menu_title = full_name
        local last_dot = string.find(full_name, " · ", 1, true)
        if last_dot then
            menu_title = string.sub(full_name, last_dot + 3)
        end
        menu_title = menu_title:gsub("^%s+", ""):gsub("%s+$", "")

        local FM = require("apps/filemanager/filemanager")
        local fm = FM and FM.instance
        local RUI = require("apps/reader/readerui")
        local reader = RUI and RUI.instance

        local function findAndExecute(items)
            if type(items) ~= "table" then return false end
            for _, item in ipairs(items) do
                if type(item) == "table" then
                    local text = entry_text(item)
                    if text == menu_title and type(item.callback) == "function" then
                        pcall(item.callback)
                        if ctx and ctx.touch_menu then
                            ctx.touch_menu:onClose()
                        end
                        return true
                    end
                    local sub = item.sub_item_table
                    if sub == nil and type(item.sub_item_table_func) == "function" then
                        local ok_sub, res = pcall(item.sub_item_table_func, TOUCHMENU_STUB)
                        if ok_sub then sub = res end
                    end
                    if type(sub) == "table" then
                        if findAndExecute(sub) then
                            return true
                        end
                    end
                end
            end
            return false
        end

        local found = false
        if fm and fm.menu and fm.menu.menu_items then
            found = findAndExecute(fm.menu.menu_items)
        end
        if not found and reader and reader.menu and reader.menu.menu_items then
            found = findAndExecute(reader.menu.menu_items)
        end
        if not found then
            UIManager:show(InfoMessage:new{
                text = string.format(_("Patch not found: %s"), menu_title),
                timeout = 2,
            })
        end
        return
    end

    -- ============================================================
    -- Handle plugin submenu (path_indices from menu recording)
    -- ============================================================
    if type(plugin_method) == "table" and plugin_method.type == "submenu" then
        local path_indices = plugin_method.path_indices
        if not path_indices or #path_indices == 0 then
            UIManager:show(InfoMessage:new{
                text = _("Invalid submenu path"),
                timeout = 2,
            })
            return
        end

        local mod = live_plugin(plugin_key)
        if not mod or type(mod.addToMainMenu) ~= "function" then
            UIManager:show(InfoMessage:new{
                text = string.format(_("Plugin not found: %s"), plugin_key),
                timeout = 2,
            })
            return
        end

        -- Get the plugin's menu entry
        local entry = probe_menu_entry(mod, plugin_key)
        if not entry then
            UIManager:show(InfoMessage:new{
                text = string.format(_("Plugin menu not found: %s"), plugin_key),
                timeout = 2,
            })
            return
        end

        -- Navigate through the submenu path
        local current_items = {}
        local sub = entry.sub_item_table
        if sub == nil and type(entry.sub_item_table_func) == "function" then
            local ok_sub, res = pcall(entry.sub_item_table_func, TOUCHMENU_STUB)
            if ok_sub then sub = res end
        end
        if type(sub) == "table" then
            current_items = sub
        end

        local found_item = nil
        for i, idx in ipairs(path_indices) do
            if current_items and current_items[idx] then
                found_item = current_items[idx]
                if i < #path_indices then
                    -- Continue deeper into submenu
                    local sub2 = found_item.sub_item_table
                    if sub2 == nil and type(found_item.sub_item_table_func) == "function" then
                        local ok2, res2 = pcall(found_item.sub_item_table_func, TOUCHMENU_STUB)
                        if ok2 then sub2 = res2 end
                    end
                    current_items = sub2
                end
            else
                found_item = nil
                break
            end
        end

        if found_item and type(found_item.callback) == "function" then
            pcall(found_item.callback)
            if ctx and ctx.touch_menu then
                ctx.touch_menu:onClose()
            end
            return
        else
            UIManager:show(InfoMessage:new{
                text = string.format(_("Submenu item not found (index: %s)"), table.concat(path_indices, ", ")),
                timeout = 2,
            })
            return
        end
    end

    -- ============================================================
    -- Regular plugin execution
    -- ============================================================
    local mod = live_plugin(plugin_key)
    if not mod then
        UIManager:show(InfoMessage:new{
            text = string.format(_("Plugin not found: %s"), plugin_key),
            timeout = 2,
        })
        return
    end

    local method = plugin_method
    if type(method) ~= "string" then
        method = PluginScan_sentinel
    end

    -- Handle submenu plugins (from PluginScan scan results)
    if method == PluginScan_submenu then
        local entry = probe_menu_entry(mod, plugin_key)
        if not entry then
            UIManager:show(InfoMessage:new{
                text = string.format(_("Plugin submenu not found: %s"), plugin_key),
                timeout = 2,
            })
            return
        end
        local sub_items = entry.sub_item_table
        if sub_items == nil and type(entry.sub_item_table_func) == "function" then
            local ok_sub, res = pcall(entry.sub_item_table_func, TOUCHMENU_STUB)
            if ok_sub then sub_items = res end
        end
        if type(sub_items) ~= "table" or #sub_items == 0 then
            UIManager:show(InfoMessage:new{
                text = string.format(_("No submenu items for: %s"), plugin_key),
                timeout = 2,
            })
            return
        end
        -- Show submenu as ButtonDialog
        local buttons = {}
        for _, item in ipairs(sub_items) do
            local cb = item.callback
            local text = entry_text(item) or _("Unnamed")
            table.insert(buttons, {{
                text = text,
                callback = function()
                    if cb then cb(TOUCHMENU_STUB) end
                    if ctx and ctx.touch_menu then
                        ctx.touch_menu:onClose()
                    end
                end,
            }})
        end
        table.insert(buttons, {{
            text = _("Close"),
            callback = function()
                UIManager:close(sub_dialog)
            end,
        }})
        local sub_dialog = ButtonDialog:new{
            title = entry_text(entry) or plugin_key,
            title_align = "center",
            buttons = buttons,
            width = math.floor(Screen:getWidth() * 0.7),
        }
        UIManager:show(sub_dialog)
        if ctx and ctx.touch_menu then
            ctx.touch_menu:onClose()
        end
        return
    end

    if method == PluginScan_sentinel then
        local entry = probe_menu_entry(mod, plugin_key)
        local callback = entry and entry.callback
        if type(callback) == "function" then
            pcall(callback, TOUCHMENU_STUB)
            if ctx and ctx.touch_menu then
                ctx.touch_menu:onClose()
            end
            return
        end
    end

    if is_callable(mod[method]) then
        pcall(mod[method], mod)
        if ctx and ctx.touch_menu then
            ctx.touch_menu:onClose()
        end
        return
    end

    UIManager:show(InfoMessage:new{
        text = string.format(_("Cannot execute plugin: %s"), plugin_key),
        timeout = 2,
    })
end

-- ============================================================
-- Show Plugin Picker Dialog
-- ============================================================

function PluginScan.showPluginPicker(on_select, on_cancel, on_back_to_edit, on_back, on_open_main_menu)
    local plugins = PluginScan.scan()

    if #plugins == 0 then
        UIManager:show(InfoMessage:new{ text = _("No plugins or patches available"), timeout = 3 })
        if on_cancel then on_cancel() end
        return
    end

    local _plugin_picker_dialog = nil

    local function showPluginList()
        local buttons = {}

        -- ============================================================
        -- Three return buttons at the top (same as 2-quickactions)
        -- ============================================================

        table.insert(buttons, {{
            text = settings_icon .. " " .. _("QA Settings"),
            callback = function()
                if _plugin_picker_dialog then
                    UIManager:close(_plugin_picker_dialog)
                    _plugin_picker_dialog = nil
                end
                if on_open_main_menu then on_open_main_menu() end
            end
        }})

        table.insert(buttons, {{
            text = "◂◂ " .. _("Back to Edit"),
            callback = function()
                if _plugin_picker_dialog then
                    UIManager:close(_plugin_picker_dialog)
                    _plugin_picker_dialog = nil
                end
                if on_back_to_edit then on_back_to_edit() end
            end
        }})

        table.insert(buttons, {{
            text = "◂ " .. _("Back"),
            callback = function()
                if _plugin_picker_dialog then
                    UIManager:close(_plugin_picker_dialog)
                    _plugin_picker_dialog = nil
                end
                if on_back then on_back() end
            end
        }})

        table.insert(buttons, {})

        -- Separate plugins and patches
        local plugin_buttons = {}
        local patch_buttons = {}

        for _, p in ipairs(plugins) do
            if p.is_patch then
                table.insert(patch_buttons, {{
                    text = p.display_title or p.title,
                    callback = function()
                        if _plugin_picker_dialog then
                            UIManager:close(_plugin_picker_dialog)
                            _plugin_picker_dialog = nil
                        end
                        if on_select then
                            on_select(p.key, PluginScan_sentinel, p.title)
                        end
                    end,
                }})
            else
                local mod = live_plugin(p.key)
                if mod and type(mod.addToMainMenu) == "function" then
                    local entry = probe_menu_entry(mod, p.key)
                    if entry then
                        local sub = entry.sub_item_table
                        if sub == nil and type(entry.sub_item_table_func) == "function" then
                            local ok_sub, res = pcall(entry.sub_item_table_func, TOUCHMENU_STUB)
                            if ok_sub then sub = res end
                        end

                        if type(sub) == "table" and #sub > 0 then
                            table.insert(plugin_buttons, {{
                                text = p.title .. " ▸",
                                callback = function()
                                    if _plugin_picker_dialog then
                                        UIManager:close(_plugin_picker_dialog)
                                        _plugin_picker_dialog = nil
                                    end
                                    PluginScan.showSubmenuPicker(
                                        p.key, p.title, sub,
                                        on_select,
                                        on_cancel,
                                        on_back_to_edit,
                                        function()
                                            showPluginList()
                                        end,
                                        on_open_main_menu,
                                        {}
                                    )
                                end,
                            }})
                        elseif type(entry.callback) == "function" then
                            table.insert(plugin_buttons, {{
                                text = p.title,
                                callback = function()
                                    if _plugin_picker_dialog then
                                        UIManager:close(_plugin_picker_dialog)
                                        _plugin_picker_dialog = nil
                                    end
                                    if on_select then
                                        on_select(p.key, PluginScan_sentinel, p.title)
                                    end
                                end,
                            }})
                        end
                    end
                end
            end
        end

        -- Sort and add to buttons
        table.sort(plugin_buttons, function(a, b)
            return (a[1].text or ""):lower() < (b[1].text or ""):lower()
        end)
        table.sort(patch_buttons, function(a, b)
            return (a[1].text or ""):lower() < (b[1].text or ""):lower()
        end)

        for _, btn in ipairs(plugin_buttons) do
            table.insert(buttons, btn)
        end

        if #plugin_buttons > 0 and #patch_buttons > 0 then
            table.insert(buttons, {{
                text = "──────────────────",
                enabled = false,
            }})
        end

        for _, btn in ipairs(patch_buttons) do
            table.insert(buttons, btn)
        end

        if #buttons == 4 then
            table.insert(buttons, {{
                text = _("No actions available"),
                enabled = false,
            }})
        end

        _plugin_picker_dialog = ButtonDialog:new{
            title = _("Select Plugin or Patch"),
            title_align = "center",
            buttons = buttons,
            width = math.floor(Screen:getWidth() * 0.7),
            max_height = math.floor(Screen:getHeight() * 0.7),
        }
        UIManager:show(_plugin_picker_dialog)
    end

    showPluginList()
end

-- ============================================================
-- Show Submenu Picker (for plugins with submenus)
-- ============================================================

local _submenu_picker_dialog = nil

function PluginScan.showSubmenuPicker(plugin_key, plugin_title, items, on_select, on_cancel, on_back_to_edit, on_back, on_open_main_menu, parent_indices)
    parent_indices = parent_indices or {}

    local buttons = {}

    if parent_indices then
        -- ============================================================
        -- Three return buttons at the top for submenu (same as 2-quickactions)
        -- ============================================================

        table.insert(buttons, {{
            text = settings_icon .. " " .. _("QA Settings"),
            callback = function()
                if _submenu_picker_dialog then
                    UIManager:close(_submenu_picker_dialog)
                    _submenu_picker_dialog = nil
                end
                if on_open_main_menu then on_open_main_menu() end
            end
        }})

        table.insert(buttons, {{
            text = "◂◂ " .. _("Back to Edit"),
            callback = function()
                if _submenu_picker_dialog then
                    UIManager:close(_submenu_picker_dialog)
                    _submenu_picker_dialog = nil
                end
                if on_back_to_edit then on_back_to_edit() end
            end
        }})

        table.insert(buttons, {{
            text = "◂ " .. _("Back"),
            callback = function()
                if _submenu_picker_dialog then
                    UIManager:close(_submenu_picker_dialog)
                    _submenu_picker_dialog = nil
                end
                if on_back then on_back() end
            end
        }})

        table.insert(buttons, {})
    end

    for idx, item in ipairs(items or {}) do
        if type(item) == "table" then
            local text = entry_text(item) or _("Unnamed")

            local sub = item.sub_item_table
            if sub == nil and type(item.sub_item_table_func) == "function" then
                local ok_sub, res = pcall(item.sub_item_table_func, TOUCHMENU_STUB)
                if ok_sub then sub = res end
            end

            if type(sub) == "table" and #sub > 0 then
                local new_indices = {}
                for _, p in ipairs(parent_indices) do
                    table.insert(new_indices, p)
                end
                table.insert(new_indices, idx)

                table.insert(buttons, {{
                    text = text .. " ▸",
                    callback = function()
                        if _submenu_picker_dialog then
                            UIManager:close(_submenu_picker_dialog)
                            _submenu_picker_dialog = nil
                        end
                        PluginScan.showSubmenuPicker(
                            plugin_key, plugin_title .. " → " .. text, sub,
                            on_select,
                            on_cancel,
                            on_back_to_edit,
                            function()
                                -- Back to previous submenu level
                                PluginScan.showSubmenuPicker(plugin_key, plugin_title, items, on_select, on_cancel, on_back_to_edit, on_back, on_open_main_menu, parent_indices)
                            end,
                            on_open_main_menu,
                            new_indices
                        )
                    end,
                }})
            elseif type(item.callback) == "function" then
                local full_indices = {}
                for _, p in ipairs(parent_indices) do
                    table.insert(full_indices, p)
                end
                table.insert(full_indices, idx)

                table.insert(buttons, {{
                    text = text,
                    callback = function()
                        if _submenu_picker_dialog then
                            UIManager:close(_submenu_picker_dialog)
                            _submenu_picker_dialog = nil
                        end
                        if on_select then
                            on_select(plugin_key, { type = "submenu", path_indices = full_indices }, text)
                        end
                    end,
                }})
            end
        end
    end

    if #buttons == (#parent_indices > 0 and 4 or 0) then
        table.insert(buttons, {{
            text = _("(No actions available)"),
            enabled = false,
        }})
    end

    _submenu_picker_dialog = ButtonDialog:new{
        title = (#parent_indices == 0) and _("Select Plugin or Patch") or plugin_title,
        title_align = "center",
        buttons = buttons,
        width = math.floor(Screen:getWidth() * 0.7),
        max_height = math.floor(Screen:getHeight() * 0.7),
    }
    UIManager:show(_submenu_picker_dialog)
end

-- ============================================================
-- Initialization
-- ============================================================

function PluginScan.init(plugin_ref)
    PLUGIN_STORE.plugin_ref = plugin_ref
end

return PluginScan
