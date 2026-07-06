--[[
QuickUI - Quick Actions Module Entry Point
]]

local logger = require("logger")
local _ = require("gettext")
local UIManager = require("ui/uimanager")
local Device = require("device")
local Screen = Device.screen

local QA = {}

local panel_module = nil
local settings_module = nil
local actions_module = nil
local plugin_scan_module = nil
local icon_picker_module = nil
local menu_recorder_module = nil
local uifont_module = nil
local bottombar_module = nil

function QA.init(plugin)

    local config = _G.__QUICKUI_CONFIG
    local ok, err

    -- ============================================================
    -- Panel (only if qa_panel_enabled)
    -- ============================================================
    if config and config.qa_panel_enabled then
        ok, panel_module = pcall(require, "qui_actions.qa_panel")
        if ok and panel_module and panel_module.init then
            panel_module.init(plugin)
        else
        end
    end

    -- ============================================================
    -- Settings (always load if QA enabled)
    -- ============================================================
    ok, settings_module = pcall(require, "qui_actions.qa_settings")
    if ok and settings_module and settings_module.init then
        settings_module.init(plugin)
    else
        logger.warn("QuickUI QA: Settings module failed to load")
    end

    -- ============================================================
    -- Actions (always load if QA enabled)
    -- ============================================================
    ok, actions_module = pcall(require, "qui_actions.qa_actions")
    if ok and actions_module and actions_module.init then
        actions_module.init(plugin)
    else
        logger.warn("QuickUI QA: Actions module failed to load")
    end

    -- ============================================================
    -- Plugin Scan (always load if QA enabled)
    -- ============================================================
    ok, plugin_scan_module = pcall(require, "qui_actions.qa_plugin_scan")
    if ok and plugin_scan_module and plugin_scan_module.init then
        plugin_scan_module.init(plugin)
    else
        logger.warn("QuickUI QA: Plugin scan module failed to load")
    end

    -- ============================================================
    -- Icon Picker (always load if QA enabled)
    -- ============================================================
    ok, icon_picker_module = pcall(require, "qui_actions.qa_icon_picker")
    if ok and icon_picker_module and icon_picker_module.init then
        icon_picker_module.init(plugin)
    else
        logger.warn("QuickUI QA: Icon picker module failed to load")
    end

    -- ============================================================
    -- Menu Recorder (always load if QA enabled)
    -- ============================================================
    ok, menu_recorder_module = pcall(require, "qui_actions.qa_menu_recorder")
    if ok and menu_recorder_module and menu_recorder_module.init then
        menu_recorder_module.init(plugin)
    else
        logger.warn("QuickUI QA: Menu recorder module failed to load")
    end

    -- ============================================================
    -- UI Font (always load if QA enabled)
    -- ============================================================
    ok, uifont_module = pcall(require, "qui_actions.qa_uifont")
    if ok and uifont_module and uifont_module.init then
        uifont_module.init(plugin)
    else
        logger.warn("QuickUI QA: UI Font module failed to load")
    end

    -- ============================================================
    -- Bottom Bar (only if qa_bb_enabled)
    -- ============================================================
if config and config.qa_bb_enabled then
    ok, bottombar_module = pcall(require, "qui_actions.qa_bottombar")
    if ok and bottombar_module and bottombar_module.init then
        bottombar_module.init()
        _G.__QUICKUI_PLUGIN_STORE.bottombar = bottombar_module
    else
        logger.warn("QuickUI QA: Bottom Bar module failed to load")
    end
end

    if settings_module and settings_module.setBottombar then
        settings_module.setBottombar(bottombar_module)
    end

    if panel_module and panel_module.patchTouchMenu then
        panel_module.patchTouchMenu()
    end

    if icon_picker_module and icon_picker_module.patchIconWidget then
        icon_picker_module.patchIconWidget()
    end

end

function QA.showPanel()
    if panel_module and panel_module.showPanel then
        panel_module.showPanel()
    else
        logger.warn("QuickUI QA: Panel module not available")
    end
end

function QA.showSettings()
    if settings_module and settings_module.showSettings then
        settings_module.showSettings()
    end
end

function QA.getQuickActionsSubmenu()
    if settings_module and settings_module.getQuickActionsSubmenu then
        return settings_module.getQuickActionsSubmenu()
    end
    return {}
end

function QA.getPanelMenuItems()
    if settings_module and settings_module.getPanelMenuItems then
        return settings_module.getPanelMenuItems()
    end
    return {}
end

function QA.getBottomBarMenuItems()
    if settings_module and settings_module.getBottomBarMenuItems then
        return settings_module.getBottomBarMenuItems()
    end
    return {}
end

function QA.getInterfaceFilterMenuItems()
    if actions_module and actions_module.getInterfaceFilterMenuItems then
        return actions_module.getInterfaceFilterMenuItems()
    end
    return {}
end

function QA.executeAction(action_id, ctx)
    if actions_module and actions_module.executeAction then
        return actions_module.executeAction(action_id, ctx)
    end
    return false
end

function QA.getAllAvailableActions()
    if actions_module and actions_module.getAllAvailableActions then
        return actions_module.getAllAvailableActions()
    end
    return {}
end

function QA.getLabelForAction(action_id)
    if actions_module and actions_module.getLabelForAction then
        return actions_module.getLabelForAction(action_id)
    end
    return action_id
end

function QA.getIconForAction(action_id)
    if actions_module and actions_module.getIconForAction then
        return actions_module.getIconForAction(action_id)
    end
    return nil
end

function QA.getBottombarModule()
    return bottombar_module
end

function QA.showPanelSettings()
    if settings_module and settings_module.showPanelSettings then
        settings_module.showPanelSettings()
    end
end

function QA.showBottombarSettings()
    if settings_module and settings_module.showBottombarSettings then
        settings_module.showBottombarSettings()
    end
end

return QA
