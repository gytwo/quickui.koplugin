-- Post-update "What's New" bullet lists, keyed by version string.
-- Add an entry for each release with noteworthy changes.
-- Omit a version to show no changelog on that update.
--
-- Example:
-- ["0.1.0"] = {
--     "New feature added",
--     "Bug fix for ...",
-- },

return {
    ["1.0.0"] = {
        -- Quick Actions
        "Quick Actions: Built-in actions (WiFi, night mode, rotate, screenshot, continue reading, search, restart, quit, power, HTTP server, font list, etc.)",
        "Quick Actions: Custom actions (folders, collections, plugins, system actions, recorded menu actions)",
        "Quick Actions: Icon picker with Nerd Font and SVG/PNG support",
        "Quick Actions: System icon override and UI font switcher",
        "Quick Actions: Interface filter to show/hide actions based on current view (File Manager/Reader)",
        "Quick Actions: Customizable panel with button shapes, sizes, labels, and sliders (frontlight/warmth)",
        "Quick Actions: Bottom navigation bar with configurable tabs, styles, and colors",

        -- Cover Visual Enhancements
        "Cover Visuals: Placeholder covers (simple/gradient) with title/author",
        "Cover Visuals: Badges (favorite, progress, NEW, page count, format)",
        "Cover Visuals: Rounded corners and unified aspect ratio (3:4/2:3)",
        "Cover Visuals: Folder cover previews (Gallery/Stack/Normal/None)",
        "Cover Visuals: Title/author below cover, title banner on cover",

        -- Cloze Mode
        "Cloze Mode: Mask annotations (highlights, underlines, strikeouts, inversions)",
        "Cloze Mode: Three toggle modes (double-tap, single-tap block menu, single-tap show menu)",

        -- Header & Footer
        "Header & Footer: Display time, page numbers, progress, chapter info, author, title, battery",
        "Header & Footer: Customizable positions, font face/size/bold, padding, offsets",

        -- General
        "Unified settings management with configuration stored in quickui.lua",
        "Gesture support: Quick Actions Panel, Settings, Cover Settings, Toggle Cloze Mode",
        "Online update: Check for updates from GitHub (Latest/Pre-release) and Gitee",
        "i18n support: Chinese translation included",
        "Inspired by SimpleUI, ZenUI, and ShortcutsToolbar",
    },
}