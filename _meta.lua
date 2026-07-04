--[[
QuickUI: Quick Actions, Cover Visuals, Cloze Mode, Header & Footer — more efficient KOReader.

This plugin brings together four powerful enhancements:

1. Quick Actions Panel - A customizable action panel that puts your most-used features at your fingertips. Toggle WiFi, switch night mode, rotate screen, take screenshots, launch plugins, and more - all with a single tap. Create custom actions for any menu item or plugin.

2. Cover Visual Enhancements - Make your library look clean and consistent. Beautiful placeholder covers for books without covers, unified aspect ratios, rounded corners, badges, progress indicators, favorite stars, and folder cover previews.

3. Cloze Mode - Mask annotations (highlights, underlines, strikeouts) for effective review and self-testing. Perfect for language learning and exam preparation.

4. Header & Footer - Display time, page numbers, progress, chapter info, battery status, and more at the top or bottom of your reading screen. Fully customizable.

Inspired by SimpleUI, ZenUI, and ShortcutsToolbar.

Author: gytwo
]]

local _ = require("gettext")

return {
    name = "quickui",
    fullname = _("QuickUI"),
    plugin_id = "quickui_plugin",
    description = _([[QuickUI: Quick Actions, Cover Visuals, Cloze Mode, Header & Footer — more efficient KOReader]]),
    version = "1.0.0",
    author = "gytwo",
}