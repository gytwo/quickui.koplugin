--[[
QuickUI - UI Font Switcher

Allows users to replace KOReader's system UI fonts with custom fonts.
Supports regular, bold, and monospace font families.

Original: 2-quickactions.lua (UI font switching functions)
]]

local logger = require("logger")
local _ = require("gettext")
local Screen = require("device").screen
local Device = require("device")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")

local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local Notification = require("ui/widget/notification")
local Font = require("ui/font")
local FontList = require("fontlist")

local Utils = require("qui_utils")

-- ============================================================
-- Module state
-- ============================================================

local UIFont = {}

-- ============================================================
-- Constants
-- ============================================================

local UI_FONT_ITEMS = {
    { key = "regular", label = _("Regular Font"), default = "NotoSans-Regular.ttf" },
    { key = "bold", label = _("Bold Font"), default = "NotoSans-Bold.ttf" },
    { key = "mono", label = _("Monospace Font"), default = "DroidSansMono.ttf" },
}

-- Dialog state
local _font_picker_dialog = nil
local _font_main_dialog = nil

-- ============================================================
-- Font List
-- ============================================================

function UIFont.getAvailableFonts()
    return Utils.getAvailableFonts()
end

-- ============================================================
-- Apply UI Font Changes
-- ============================================================

function UIFont.applyUIFontChanges()
    local Font = require("ui/font")

    local config = _G.__QUICKUI_CONFIG
    if not config then return end
    local overrides = config.qa_common_ui_font_overrides or {}

    local font_exists = {}
    local fonts = FontList:getFontList()
    for idx, path in ipairs(fonts) do
        local fname, name = Utils.splitFilePathName(path)
        if name then
            font_exists[name] = true
        end
    end

    local regular_font = overrides.regular or "NotoSans-Regular.ttf"
    local bold_font = overrides.bold or "NotoSans-Bold.ttf"
    local mono_font = overrides.mono or "DroidSansMono.ttf"

    -- Determine default KOReader regular / bold TTFs
    local def_regular = Font.fontmap and Font.fontmap["cfont"] or "NotoSans-Regular.ttf"
    local def_bold = Font.fontmap and Font.fontmap["ffont"] or "NotoSans-Bold.ttf"

    -- Derive bold variant
    local bold_name = regular_font:gsub("%-Regular%.", "-Bold.", 1)
    if bold_name == regular_font then
        bold_name = regular_font:gsub("%.ttf", "-Bold.ttf", 1)
    end

    -- Rewrite Font.fontmap
    if Font.fontmap and regular_font ~= def_regular then
        for name, file in pairs(Font.fontmap) do
            if file == def_regular then
                Font.fontmap[name] = regular_font
            elseif file == def_bold then
                Font.fontmap[name] = bold_font
            end
        end
    end

    -- Clear font face cache
    Font.faces = {}

    -- Patch various UI components with Font:getFace(regular_font, orig_size)
    local ok, Button = pcall(require, "ui/widget/button")
    if ok and Button then
        Button.text_font_face = regular_font
    end

    local ok, TouchMenu = pcall(require, "ui/widget/touchmenu")
    if ok and TouchMenu and TouchMenu.fface then
        local orig_size = TouchMenu.fface.orig_size or 24
        TouchMenu.fface = Font:getFace(regular_font, orig_size)
    end

    local ok, ConfirmBox = pcall(require, "ui/widget/confirmbox")
    if ok and ConfirmBox and ConfirmBox.face then
        local orig_size = ConfirmBox.face.orig_size or 22
        ConfirmBox.face = Font:getFace(regular_font, orig_size)
    end

    local ok, InfoMessage = pcall(require, "ui/widget/infomessage")
    if ok and InfoMessage then
        local def_face = Font:getFace("infofont")
        local orig_size = def_face.orig_size or 22
        InfoMessage.face = Font:getFace(regular_font, orig_size)
    end

    local ok, Notification = pcall(require, "ui/widget/notification")
    if ok and Notification then
        local orig_size = Notification.face.orig_size or 18
        Notification.face = Font:getFace(regular_font, orig_size)
    end

    local ok, ButtonDialog = pcall(require, "ui/widget/buttondialog")
    if ok and ButtonDialog then
        if ButtonDialog.title_face then
            local orig_size = ButtonDialog.title_face.orig_size or 20
            ButtonDialog.title_face = Font:getFace(regular_font, orig_size)
        end
        if ButtonDialog.info_face then
            local orig_size = ButtonDialog.info_face.orig_size or 22
            ButtonDialog.info_face = Font:getFace(regular_font, orig_size)
        end
    end

    local ok, InputDialog = pcall(require, "ui/widget/inputdialog")
    if ok and InputDialog and InputDialog.input_face then
        local orig_size = InputDialog.input_face.orig_size or 16
        InputDialog.input_face = Font:getFace(regular_font, orig_size)
    end

    local ok, MultiInputDialog = pcall(require, "ui/widget/multiinputdialog")
    if ok and MultiInputDialog then
        if MultiInputDialog.title_face then
            local orig_size = MultiInputDialog.title_face.orig_size or 20
            MultiInputDialog.title_face = Font:getFace(regular_font, orig_size)
        end
        if MultiInputDialog.info_face then
            local orig_size = MultiInputDialog.info_face.orig_size or 22
            MultiInputDialog.info_face = Font:getFace(regular_font, orig_size)
        end
    end

    -- Patch TouchMenu.updateItems to patch MenuItem face
    do
        local ok_tm, TouchMenu2 = pcall(require, "ui/widget/touchmenu")
        if ok_tm and TouchMenu2 and not TouchMenu2.__quickui_font_patched then
            TouchMenu2.__quickui_font_patched = true
            local orig_updateItems = TouchMenu2.updateItems
            TouchMenu2.updateItems = function(self, ...)
                orig_updateItems(self, ...)
                if not self.__quickui_items_patched then
                    for _i = 1, #self.item_group do
                        local widget = self.item_group[_i]
                        if type(widget) == "table" and widget.item and widget.face then
                            local cls = getmetatable(widget)
                            if cls and cls.face then
                                local orig_size = cls.face.orig_size or 18
                                cls.face = Font:getFace(regular_font, orig_size)
                                self.__quickui_items_patched = true
                                self.__quickui_items_patched = nil
                                orig_updateItems(self, ...)
                                self.__quickui_items_patched = true
                                return
                            end
                        end
                    end
                end
            end
        end
    end

    -- Patch Menu.updateItems to patch MenuItem font/infont
    do
        local ok_m, Menu = pcall(require, "ui/widget/menu")
        if ok_m and Menu and not Menu.__quickui_font_patched then
            Menu.__quickui_font_patched = true
            local orig_updateItems = Menu.updateItems
            Menu.updateItems = function(self, ...)
                orig_updateItems(self, ...)
                if not self.__quickui_items_patched then
                    for _i = 1, #self.item_group do
                        local widget = self.item_group[_i]
                        if type(widget) == "table" and widget.face then
                            local cls = getmetatable(widget)
                            if cls then
                                cls.font = regular_font
                                cls.infont = regular_font
                                self.__quickui_items_patched = true
                                self.__quickui_items_patched = nil
                                orig_updateItems(self, ...)
                                self.__quickui_items_patched = true
                                return
                            end
                        end
                    end
                end
            end
        end
    end

    -- Force refresh open menus
    local FM = require("apps/filemanager/filemanager")
    local fm = FM and FM.instance
    local RUI = require("apps/reader/readerui")
    local reader = RUI and RUI.instance

    if fm and fm.menu and fm.menu.menu_container and fm.menu.menu_container[1] then
        fm.menu.menu_container[1]:updateItems()
    end
    if reader and reader.menu and reader.menu.menu_container and reader.menu.menu_container[1] then
        reader.menu.menu_container[1]:updateItems()
    end

end

-- ============================================================
-- Reset All UI Fonts
-- ============================================================

function UIFont.resetAllUIFonts()
    local config = _G.__QUICKUI_CONFIG
    if config then
        config.qa_common_ui_font_overrides = {}
        Utils.saveConfig()
    end

    -- Apply default fonts
    UIFont.applyUIFontChanges()

    UIManager:show(Notification:new{
        text = _("All UI fonts reset, restart required"),
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
end

-- ============================================================
-- Font Picker Dialog
-- ============================================================

function UIFont.showFontPickerForUIKey(ui_key, ui_label, on_select, on_cancel)
    if _font_picker_dialog then
        UIManager:close(_font_picker_dialog)
        _font_picker_dialog = nil
    end

    local all_fonts = UIFont.getAvailableFonts()
    local overrides = Utils.getTable("qa_common_ui_font_overrides")
    local current = overrides[ui_key] or ""

    local buttons = {}

    -- Return button
    table.insert(buttons, {{
        text = "◂ " .. _("Back"),
        callback = function()
            if _font_picker_dialog then
                UIManager:close(_font_picker_dialog)
                _font_picker_dialog = nil
            end
            if on_cancel then on_cancel() end
        end,
    }})

    table.insert(buttons, {{
        text = _("Use Default"),
        callback = function()
            if _font_picker_dialog then
                UIManager:close(_font_picker_dialog)
                _font_picker_dialog = nil
            end
            if on_select then on_select(nil) end
        end,
    }})

    table.insert(buttons, {})

    if #all_fonts == 0 then
        table.insert(buttons, {{
            text = _("No fonts available"),
            enabled = false,
            alignment = "center",
        }})
        local dialog = ButtonDialog:new{
            title = string.format(_("Select %s Font"), ui_label),
            title_align = "center",
            buttons = buttons,
            width = math.floor(Screen:getWidth() * 0.7),
        }
        _font_picker_dialog = dialog
        UIManager:show(dialog)
        return
    end

    for i, font in ipairs(all_fonts) do
        local is_current = (font.name == current)
        table.insert(buttons, {{
            text = (is_current and "✓ " or "  ") .. font.display,
            callback = function()
                if _font_picker_dialog then
                    UIManager:close(_font_picker_dialog)
                    _font_picker_dialog = nil
                end
                if on_select then on_select(font.name) end
            end,
        }})
    end

    local dialog = ButtonDialog:new{
        title = string.format(_("Select %s Font"), ui_label),
        title_align = "center",
        buttons = buttons,
        width = math.floor(Screen:getWidth() * 0.7),
        max_height = math.floor(Screen:getHeight() * 0.7),
        rows_per_page = 10,
    }
    _font_picker_dialog = dialog
    UIManager:show(dialog)
end

-- ============================================================
-- Main UI Font Switcher Dialog
-- ============================================================

function UIFont.showUIFontSwitcher()
    if _font_main_dialog then
        UIManager:close(_font_main_dialog)
        _font_main_dialog = nil
    end
    if _font_picker_dialog then
        UIManager:close(_font_picker_dialog)
        _font_picker_dialog = nil
    end

    local config = _G.__QUICKUI_CONFIG
    local overrides = (config and config.qa_common_ui_font_overrides) or {}

    local buttons = {}

    -- Return button
    table.insert(buttons, {{
        text = "◂ " .. _("Back"),
        callback = function()
            if _font_main_dialog then
                UIManager:close(_font_main_dialog)
                _font_main_dialog = nil
            end
            local settings = require("qui_actions/qa_settings")
            settings.showSettings()
        end
    }})

    table.insert(buttons, {})

    local replaced_count = 0
    for i, item in ipairs(UI_FONT_ITEMS) do
        if overrides[item.key] then
            replaced_count = replaced_count + 1
        end
    end
    local total_count = #UI_FONT_ITEMS

    table.insert(buttons, {{
        text = string.format(_("Reset All (%d/%d)"), replaced_count, total_count),
        callback = function()
            if _font_main_dialog then
                UIManager:close(_font_main_dialog)
                _font_main_dialog = nil
            end
            UIFont.resetAllUIFonts()
        end,
    }})

    table.insert(buttons, {})

    for i, item in ipairs(UI_FONT_ITEMS) do
        local override = overrides[item.key]
        local display_name = override or item.default
        local display = display_name:gsub("%.ttf$", ""):gsub("%.otf$", ""):gsub("_", " ")

        local text = item.label .. ": " .. display
        if override then
            local default_display = item.default:gsub("%.ttf$", ""):gsub("%.otf$", ""):gsub("_", " ")
            text = item.label .. ": " .. default_display .. " → " .. display
        end

        table.insert(buttons, {{
            text = text,
            callback = function()
                if _font_main_dialog then
                    UIManager:close(_font_main_dialog)
                    _font_main_dialog = nil
                end
                UIFont.showFontPickerForUIKey(
                    item.key,
                    item.label,
                    function(new_font)
                        if new_font then
                            local overrides = Utils.getTable("qa_common_ui_font_overrides")
                            overrides[item.key] = new_font
                            Utils.set("qa_common_ui_font_overrides", overrides)
                            UIManager:show(Notification:new{
                                text = string.format(_("%s set to: %s"), item.label, new_font),
                                timeout = 2,
                            })
                        else
                            local overrides = Utils.getTable("qa_common_ui_font_overrides")
                            overrides[item.key] = nil
                            Utils.set("qa_common_ui_font_overrides", overrides)
                            UIManager:show(Notification:new{
                                text = string.format(_("%s reset to default"), item.label),
                                timeout = 2,
                            })
                        end
                        UIFont.showUIFontSwitcher()
                    end,
                    function()
                        UIFont.showUIFontSwitcher()
                    end
                )
            end,
        }})
    end

    local dialog = ButtonDialog:new{
        title = _("UI Font Switcher"),
        title_align = "center",
        buttons = buttons,
        width = math.floor(Screen:getWidth() * 0.7),
        max_height = math.floor(Screen:getHeight() * 0.7),
        rows_per_page = 10,
    }
    _font_main_dialog = dialog
    UIManager:show(dialog)
end

-- ============================================================
-- Initialization
-- ============================================================

function UIFont.init(plugin)
    UIFont.applyUIFontChanges()
    Utils.registerRefreshHandler("qa_common", function()
        UIFont.applyUIFontChanges()
    end)
end

return UIFont
