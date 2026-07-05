--[[
QuickUI: Quick Actions, Cover Visuals, Cloze Mode, Header & Footer — more efficient KOReader
]]

local Utils = require("qui_utils")
local _plugin_dir = Utils.getPluginDir()

local i18n = dofile(_plugin_dir .. "qui_i18n.lua")
if i18n and i18n.install then
    i18n.install()
end

local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Dispatcher = require("dispatcher")
local UIManager = require("ui/uimanager")
local Device = require("device")
local Screen = Device.screen
local _ = require("gettext")
local logger = require("logger")
local lfs = require("libs/libkoreader-lfs")
local InfoMessage = require("ui/widget/infomessage")
local ConfirmBox = require("ui/widget/confirmbox")
local Notification = require("ui/widget/notification")
local TextViewer = require("ui/widget/textviewer")

local cover_module = nil
local actions_module = nil
local cloze_module = nil
local hf_module = nil
local updates_module = nil

local icon_picker = nil
local uifont = nil
local qa_actions = nil
local qa_settings = nil

-- ============================================================
-- QuickUI Class Definition
-- ============================================================

local QuickUI = WidgetContainer:extend{
    is_doc_only = false,
    VERSION = "1.0.0",
}

function QuickUI:init()
    local ButtonDialog = require("ui/widget/buttondialog")
    local orig_new = ButtonDialog.new
    ButtonDialog.new = function(_, ...)
        local args = ... or {}
        if type(args) == "table" and args.rows_per_page == nil then
            args.rows_per_page = 10
        end
        return orig_new(_, args)
    end

    Utils.loadConfig()

    self.ui.menu:registerToMainMenu(self)

    local config = _G.__QUICKUI_CONFIG
    local ok

    -- ============================================================
    -- Module 1: Cover
    -- ============================================================
    if config and config.cover_enabled then
        ok, cover_module = pcall(require, "qui_cover")
        if ok and cover_module and cover_module.init then
            cover_module.init(self)
        else
            logger.warn("QuickUI: Cover failed to load")
        end
    end

    -- ============================================================
    -- Module 2: Quick Actions
    -- ============================================================
    if config and config.qa_common_enabled then
        ok, icon_picker = pcall(require, "qui_actions/qa_icon_picker")
        if not ok then icon_picker = nil end

        ok, uifont = pcall(require, "qui_actions/qa_uifont")
        if not ok then uifont = nil end

        ok, qa_actions = pcall(require, "qui_actions/qa_actions")
        if not ok then qa_actions = nil end

        ok, qa_settings = pcall(require, "qui_actions/qa_settings")
        if not ok then qa_settings = nil end

        ok, actions_module = pcall(require, "qui_actions/qa_init")
        if ok and actions_module and actions_module.init then
            actions_module.init(self)
        else
            logger.warn("QuickUI: Quick Actions failed to load")
        end
    end

    -- ============================================================
    -- Module 3: Cloze
    -- ============================================================
    if config and config.cl_enabled then
        ok, cloze_module = pcall(require, "qui_clozemode")
        if ok and cloze_module and cloze_module.init then
            cloze_module.init(self)
        else
            logger.warn("QuickUI: Cloze failed to load")
        end
    end

    -- ============================================================
    -- Module 4: Header & Footer
    -- ============================================================
    if config and config.hf_enabled then
        ok, hf_module = pcall(require, "qui_header_footer")
        if ok and hf_module and hf_module.init then
            hf_module.init(self)
        else
            logger.warn("QuickUI: Header/Footer failed to load")
        end
    end

    -- ============================================================
    -- Module 5: Updates (always load)
    -- ============================================================
    ok, updates_module = pcall(require, "qui_updates")
    if ok and updates_module and updates_module.init then
        updates_module.init(self)
    else
        logger.warn("QuickUI: Updates failed to load")
    end

    self:registerDispatcherActions()

    logger.info("QuickUI: init completed")
end

-- ============================================================
-- Register Dispatcher Actions
-- ============================================================

function QuickUI:registerDispatcherActions()
    local config = _G.__QUICKUI_CONFIG

    -- ============================================================
    -- General (always registered)
    -- ============================================================
    Dispatcher:registerAction("QuickUI_Settings", {
        category = "none",
        event = "QuickUI_Settings",
        title = _("QuickUI_Settings"),
        general = true,
    })

    -- ============================================================
    -- Cover
    -- ============================================================
    if config and config.cover_enabled then
        Dispatcher:registerAction("QuickUI_CoverSettings", {
            category = "none",
            event = "QuickUI_CoverSettings",
            title = _("QuickUI_CoverSettings"),
            filemanager = true,
        })
    end

    -- ============================================================
    -- Cloze
    -- ============================================================
    if config and config.cl_enabled then
        Dispatcher:registerAction("QuickUI_ClozeEnable", {
            category = "none",
            event = "QuickUI_ClozeEnable",
            title = _("QuickUI_ClozeEnable"),
            reader = true,
        })
        Dispatcher:registerAction("QuickUI_ClozeToggleAll", {
            category = "none",
            event = "QuickUI_ClozeToggleAll",
            title = _("QuickUI_ClozeToggleAll"),
            reader = true,
        })
        Dispatcher:registerAction("QuickUI_ClozeSettings", {
            category = "none",
            event = "QuickUI_ClozeSettings",
            title = _("QuickUI_ClozeSettings"),
            reader = true,
        })
    end

    -- ============================================================
    -- Header & Footer
    -- ============================================================
    if config and config.hf_enabled then
        Dispatcher:registerAction("QuickUI_HFSettings", {
            category = "none",
            event = "QuickUI_HFSettings",
            title = _("QuickUI_HFSettings"),
            reader = true,
        })
    end

    -- ============================================================
    -- Quick Actions (QA)
    -- ============================================================
    if config and config.qa_common_enabled then
        -- Always register when QA is enabled
                Dispatcher:registerAction("QuickUI_SystemIconOverride", {
            category = "none",
            event = "QuickUI_SystemIconOverride",
            title = _("QuickUI_SystemIconOverride"),
            general = true,
        })
        Dispatcher:registerAction("QuickUI_InterfaceFilter", {
            category = "none",
            event = "QuickUI_InterfaceFilter",
            title = _("QuickUI_InterfaceFilter"),
            general = true,
        })
        Dispatcher:registerAction("QuickUI_Panel", {
            category = "none",
            event = "QuickUI_Panel",
            title = _("QuickUI_Panel"),
            general = true,
        })
        Dispatcher:registerAction("QuickUI_QASettings", {
            category = "none",
            event = "QuickUI_QASettings",
            title = _("QuickUI_QASettings"),
            general = true,
        })
        Dispatcher:registerAction("QuickUI_NewAction", {
            category = "none",
            event = "QuickUI_NewAction",
            title = _("QuickUI_NewAction"),
            general = true,
        })

        -- Panel related (only if qa_panel_enabled)
        if config.qa_panel_enabled then
            Dispatcher:registerAction("QuickUI_PanelSettings", {
                category = "none",
                event = "QuickUI_PanelSettings",
                title = _("QuickUI_PanelSettings"),
                general = true,
            })
            Dispatcher:registerAction("QuickUI_AddPanelButton", {
                category = "none",
                event = "QuickUI_AddPanelButton",
                title = _("QuickUI_AddPanelButton"),
                general = true,
            })
        end

        -- Bottom Bar related (only if qa_bb_enabled)
        if config.qa_bb_enabled then
            Dispatcher:registerAction("QuickUI_BottombarToggle", {
                category = "none",
                event = "QuickUI_BottombarToggle",
                title = _("QuickUI_BottombarToggle"),
                general = true,
            })
            Dispatcher:registerAction("QuickUI_BottombarSettings", {
                category = "none",
                event = "QuickUI_BottombarSettings",
                title = _("QuickUI_BottombarSettings"),
                general = true,
            })
            Dispatcher:registerAction("QuickUI_AddBottomBarTab", {
                category = "none",
                event = "QuickUI_AddBottomBarTab",
                title = _("QuickUI_AddBottomBarTab"),
                general = true,
            })
        end
    end
end

-- ============================================================
-- Dispatcher Action Event Handlers
-- ============================================================
function QuickUI:onQuickUI_SystemIconOverride()
    local icon_picker = require("qui_actions/qa_icon_picker")
    icon_picker.showIconPicker(nil, nil, nil, "system")
    return true
end

function QuickUI:onQuickUI_InterfaceFilter()
    local QA = require("qui_actions/qa_actions")
    QA.executeAction("interface_filter", {})
    return true
end

function QuickUI:onQuickUI_Panel()
    if actions_module and actions_module.showPanel then
        actions_module.showPanel()
    else
        Notification:notify(_("Quick Actions module is disabled"))
    end
    return true
end

function QuickUI:onQuickUI_Settings()
    if self and self.quickuisettings then
        self:quickuisettings()
    end
    return true
end

function QuickUI:onQuickUI_CoverSettings()
    if not cover_module then
        Notification:notify(_("Cover module is disabled"))
        return true
    end
    cover_module.showSettings(self)
    return true
end

function QuickUI:onQuickUI_ClozeEnable()
    if not cloze_module then
        Notification:notify(_("Cloze module is disabled"))
        return true
    end
    cloze_module:toggleEnable(self)
    return true
end

function QuickUI:onQuickUI_ClozeToggleAll()
    if not cloze_module then
        Notification:notify(_("Cloze module is disabled"))
        return true
    end
    cloze_module:toggleAll()
    return true
end

function QuickUI:onQuickUI_ClozeSettings()
    if not cloze_module then
        Notification:notify(_("Cloze module is disabled"))
        return true
    end
    cloze_module.showSettings(self)
    return true
end

function QuickUI:onQuickUI_HFSettings()
    if not hf_module then
        Notification:notify(_("Header/Footer module is disabled"))
        return true
    end
    hf_module.showSettings()
    return true
end

function QuickUI:onQuickUI_QASettings()
    if not qa_settings then
        Notification:notify(_("Quick Actions module is disabled"))
        return true
    end
    qa_settings.showSettings()
    return true
end

function QuickUI:onQuickUI_PanelSettings()
    if not qa_settings then
        Notification:notify(_("Quick Actions module is disabled"))
        return true
    end
    qa_settings.showPanelSettings()
    return true
end

function QuickUI:onQuickUI_NewAction()
    if not qa_settings then
        Notification:notify(_("Quick Actions module is disabled"))
        return true
    end
    qa_settings.showCustomQADialog(nil, function()
        if qa_settings and qa_settings.refreshQuickPanel then
            qa_settings.refreshQuickPanel()
        end
    end)
    return true
end

function QuickUI:onQuickUI_AddPanelButton()
    if not qa_settings then
        Notification:notify(_("Quick Actions module is disabled"))
        return true
    end
    local fm = require("apps/filemanager/filemanager").instance
    local touch_menu = nil
    if fm and fm.menu and fm.menu.menu_container and fm.menu.menu_container[1] then
        touch_menu = fm.menu.menu_container[1]
    else
        local readerui = require("apps/reader/readerui").instance
        if readerui and readerui.menu and readerui.menu.menu_container and readerui.menu.menu_container[1] then
            touch_menu = readerui.menu.menu_container[1]
        end
    end
    qa_settings.showAddButtonMenu(touch_menu)
    return true
end

function QuickUI:onQuickUI_BottombarToggle()
    local bb = _G.__QUICKUI_PLUGIN_STORE and _G.__QUICKUI_PLUGIN_STORE.bottombar
    if not bb then
        Notification:notify(_("Bottom Bar module is disabled"))
        return true
    end
    local config = _G.__QUICKUI_CONFIG
    local enabled = config and config.qa_bb_enabled
    config.qa_bb_enabled = not enabled
    Utils.saveConfig()
    if bb and bb.rebuildBottombar then
        bb.rebuildBottombar()
    end
    Notification:notify(enabled and _("Bottom Bar disabled") or _("Bottom Bar enabled"))
    return true
end

function QuickUI:onQuickUI_BottombarSettings()
    if not qa_settings then
        Notification:notify(_("Quick Actions module is disabled"))
        return true
    end
    qa_settings.showBottombarSettings()
    return true
end

function QuickUI:onQuickUI_AddBottomBarTab()
    local bb = _G.__QUICKUI_PLUGIN_STORE and _G.__QUICKUI_PLUGIN_STORE.bottombar
    if not bb then
        Notification:notify(_("Bottom Bar module is disabled"))
        return true
    end
    if bb and bb.showAddTabMenu then
        bb.showAddTabMenu(function()
            if bb and bb.refresh then
                bb.refresh()
            end
        end)
    end
    return true
end

-- ============================================================
-- Build Menu Items
-- ============================================================

local function refreshQuickPanel()
    local fm = require("apps/filemanager/filemanager").instance
    if fm and fm.menu and fm.menu.menu_container then
        local menu = fm.menu.menu_container[1]
        if menu and menu.updateItems then
            menu:updateItems()
        end
    end
    local readerui = require("apps/reader/readerui").instance
    if readerui and readerui.menu and readerui.menu.menu_container then
        local menu = readerui.menu.menu_container[1]
        if menu and menu.updateItems then
            menu:updateItems()
        end
    end
end

-- ============================================================
-- Show Plugin Info (README viewer)
-- ============================================================

function QuickUI:showPluginInfo()
    -- Get current language setting
    local current_lang = G_reader_settings:readSetting("language") or "en"
    local is_chinese = current_lang == "zh_CN" or current_lang == "zh-TW" or current_lang:match("^zh")

    -- Select README file based on language
    local readme_path
    if is_chinese then
        readme_path = _plugin_dir .. "README.zh_CN.md"
        -- Fallback to English if Chinese README doesn't exist
        if not lfs.attributes(readme_path, "mode") then
            readme_path = _plugin_dir .. "README.md"
        end
    else
        readme_path = _plugin_dir .. "README.md"
        -- Fallback to Chinese if English README doesn't exist
        if not lfs.attributes(readme_path, "mode") then
            readme_path = _plugin_dir .. "README.zh_CN.md"
        end
    end

    local f = io.open(readme_path, "r")
    local content = nil
    if f then
        content = f:read("*all")
        f:close()
    end

    if not content or content == "" then
        content = _("README file not found")
    end

    local textviewer = TextViewer:new{
        title = _("QuickUI - Plugin Info"),
        text = content,
        justified = false,
    }
    UIManager:show(textviewer)
end

function QuickUI:buildMenuItems()
    local items = {}

    -- ============================================================
    -- Enable/Disable switches (always shown)
    -- ============================================================

    table.insert(items, {
        text = _("Enable Quick Actions"),
        checked_func = function()
            local config = _G.__QUICKUI_CONFIG
            return config and config.qa_common_enabled
        end,
        callback = function()
            local config = _G.__QUICKUI_CONFIG
            config.qa_common_enabled = not config.qa_common_enabled
            Utils.saveConfig()
            UIManager:show(ConfirmBox:new{
                text = _("Restart required.\n\nRestart KOReader now?"),
                ok_text = _("Restart"),
                cancel_text = _("Later"),
                ok_callback = function()
                    UIManager:restartKOReader()
                end,
            })
        end,
    })

    table.insert(items, {
        text = _("Enable Cover"),
        checked_func = function()
            local config = _G.__QUICKUI_CONFIG
            return config and config.cover_enabled
        end,
        callback = function()
            local config = _G.__QUICKUI_CONFIG
            config.cover_enabled = not config.cover_enabled
            Utils.saveConfig()
            UIManager:show(ConfirmBox:new{
                text = _("Restart required.\n\nRestart KOReader now?"),
                ok_text = _("Restart"),
                cancel_text = _("Later"),
                ok_callback = function()
                    UIManager:restartKOReader()
                end,
            })
        end,
    })

    table.insert(items, {
        text = _("Enable Cloze Mode"),
        checked_func = function()
            local config = _G.__QUICKUI_CONFIG
            return config and config.cl_enabled
        end,
        callback = function()
            local config = _G.__QUICKUI_CONFIG
            config.cl_enabled = not config.cl_enabled
            Utils.saveConfig()
            UIManager:show(ConfirmBox:new{
                text = _("Restart required.\n\nRestart KOReader now?"),
                ok_text = _("Restart"),
                cancel_text = _("Later"),
                ok_callback = function()
                    UIManager:restartKOReader()
                end,
            })
        end,
    })

    table.insert(items, {
        text = _("Enable Header & Footer"),
        checked_func = function()
            local config = _G.__QUICKUI_CONFIG
            return config and config.hf_enabled
        end,
        callback = function()
            local config = _G.__QUICKUI_CONFIG
            config.hf_enabled = not config.hf_enabled
            Utils.saveConfig()
            UIManager:show(ConfirmBox:new{
                text = _("Restart required.\n\nRestart KOReader now?"),
                ok_text = _("Restart"),
                cancel_text = _("Later"),
                ok_callback = function()
                    UIManager:restartKOReader()
                end,
            })
        end,
    })

    -- ============================================================
    -- Module sub-menus (only shown if module is loaded)
    -- ============================================================

    -- Quick Actions Settings
    if qa_settings then
        table.insert(items, {
            text = _("Quick Actions Settings"),
            sub_item_table = qa_settings.buildRootMenuItems(),
        })
    end

    -- Cover Settings
    if cover_module then
        local function getFlattenedMenuItems(module, method_name)
            if not module or not module[method_name] then
                return nil
            end
            local result = module[method_name](self)
            if type(result) == "function" then
                result = result()
            end
            if type(result) == "table" and #result > 0 then
                return result
            end
            return nil
        end

        local cover_items = getFlattenedMenuItems(cover_module, "getMenuItems")
        if cover_items and #cover_items > 0 then
            table.insert(items, {
                text = _("Cover Settings"),
                sub_item_table = cover_items,
            })
        end
    end

    -- Cloze Settings
    if cloze_module then
        local function getFlattenedMenuItems(module, method_name)
            if not module or not module[method_name] then
                return nil
            end
            local result = module[method_name](self)
            if type(result) == "function" then
                result = result()
            end
            if type(result) == "table" and #result > 0 then
                return result
            end
            return nil
        end

        local cl_items = getFlattenedMenuItems(cloze_module, "getMenuItems")
        if cl_items and #cl_items > 0 then
            table.insert(items, {
                text = _("Cloze Settings"),
                sub_item_table = cl_items,
            })
        end
    end

    -- Header & Footer Settings
    if hf_module then
        local function getFlattenedMenuItems(module, method_name)
            if not module or not module[method_name] then
                return nil
            end
            local result = module[method_name](self)
            if type(result) == "function" then
                result = result()
            end
            if type(result) == "table" and #result > 0 then
                return result
            end
            return nil
        end

        local hf_items = getFlattenedMenuItems(hf_module, "getMenuItems")
        if hf_items and #hf_items > 0 then
            table.insert(items, {
                text = _("Header & Footer Settings"),
                sub_item_table = hf_items,
            })
        end
    end

    -- ============================================================
    -- Default Config Management
    -- ============================================================
local all_modules = {"qa_panel", "qa_bb", "qa_common", "cover", "cloze", "hf"}
local all_items = Utils.buildDefaultMenuItems(all_modules, function()
    refreshQuickPanel()
    local bb = _G.__QUICKUI_PLUGIN_STORE and _G.__QUICKUI_PLUGIN_STORE.bottombar
    if bb and bb.rebuildBottombar then
        bb.rebuildBottombar()
    end
end)
for _, item in ipairs(all_items) do
    table.insert(items, item)
end

    -- ============================================================
    -- Updates
    -- ============================================================
    if updates_module and updates_module.checkForUpdates then
        table.insert(items, {
            text = _("Check for Updates") .. "  (" .. _("Current version") .. ": " .. self.VERSION .. ")",
            callback = function()
                updates_module.checkForUpdates(false, self)
            end,
        })
    end
    
    -- ============================================================
    -- Plugin Info
    -- ============================================================
    table.insert(items, {
        text = _("Plugin Info"),
        callback = function()
            self:showPluginInfo()
        end,
    })

    return items
end

function QuickUI:addToMainMenu(menu_items)
    menu_items.quickui = {
        text = _("QuickUI"),
        sorting_hint = "tools",
        sub_item_table = self:buildMenuItems(),
    }
end

-- ============================================================
-- QuickUI Settings
-- ============================================================

function QuickUI:quickuisettings()
    local items = self:buildMenuItems()
    local ButtonDialog = require("ui/widget/buttondialog")
    local Screen = require("device").screen
    local UIManager = require("ui/uimanager")
    local _ = require("gettext")
    
    local _quickui_settings_dialog = nil
    
    local function showQuickUIMenu(item_table, title, parent_stack)
        local buttons = {}
        local is_top_level = (parent_stack == nil or #parent_stack == 0)
        
        if parent_stack and #parent_stack > 0 then
            if #parent_stack > 1 then
                table.insert(buttons, {
                    {
                        text = "◂◂ " .. _("Back to Root"),
                        callback = function()
                            if _quickui_settings_dialog then
                                UIManager:close(_quickui_settings_dialog)
                                _quickui_settings_dialog = nil
                            end
                            showQuickUIMenu(items, _("QuickUI"), nil)
                        end
                    }
                })
            end
            table.insert(buttons, {
                {
                    text = "◂ " .. _("Back"),
                    callback = function()
                        if _quickui_settings_dialog then
                            UIManager:close(_quickui_settings_dialog)
                            _quickui_settings_dialog = nil
                        end
                        local parent = parent_stack[#parent_stack]
                        local new_stack = {}
                        for i = 1, #parent_stack - 1 do
                            table.insert(new_stack, parent_stack[i])
                        end
                        showQuickUIMenu(parent.items, parent.title, new_stack)
                    end
                }
            })
            table.insert(buttons, {})
        end
        
        for _, item in ipairs(item_table) do
            local display_text
            if item.text_func then
                display_text = type(item.text_func) == "function" and item.text_func() or item.text_func
            elseif item.text then
                display_text = type(item.text) == "function" and item.text() or item.text
            else
                display_text = ""
            end
            
            if item.sub_item_table then
                table.insert(buttons, {
                    {
                        text = display_text .. " ▸",
                        callback = function()
                            if _quickui_settings_dialog then
                                UIManager:close(_quickui_settings_dialog)
                                _quickui_settings_dialog = nil
                            end
                            local new_stack = {}
                            if parent_stack then
                                for _, v in ipairs(parent_stack) do
                                    table.insert(new_stack, v)
                                end
                            end
                            table.insert(new_stack, { title = title, items = item_table })
                            showQuickUIMenu(item.sub_item_table, display_text, new_stack)
                        end
                    }
                })
            else
                local checked = item.checked_func and item.checked_func() or false
                local enabled = (item.enabled == nil) or (type(item.enabled) == "function" and item.enabled()) or item.enabled
                local prefix = checked and "✓ " or "  "
                
                table.insert(buttons, {
                    {
                        text = prefix .. display_text,
                        enabled = enabled,
                        callback = function()
                            if item.callback then
                                item.callback()
                            end
                            
                            if is_top_level then
                                if _quickui_settings_dialog then
                                    UIManager:close(_quickui_settings_dialog)
                                    _quickui_settings_dialog = nil
                                end
                            else
                                if _quickui_settings_dialog then
                                    UIManager:close(_quickui_settings_dialog)
                                    _quickui_settings_dialog = nil
                                end
                                showQuickUIMenu(item_table, title, parent_stack)
                            end
                        end
                    }
                })
            end
        end
        
        _quickui_settings_dialog = ButtonDialog:new{
            title = title or _("QuickUI"),
            title_align = "center",
            buttons = buttons,
            width = math.floor(Screen:getWidth() * 0.7),
            max_height = math.floor(Screen:getHeight() * 0.7),
        }
        UIManager:show(_quickui_settings_dialog)
    end
    
    showQuickUIMenu(items, _("QuickUI"), nil)
end

return QuickUI
