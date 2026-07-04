# QuickUI - KOReader Enhancement Plugin

> **QuickUI: Quick Actions, Cover Visuals, Cloze Mode, Header & Footer — more efficient KOReader.**

> **Version**: v1.0.0 | **Author**: gytwo | **License**: AGPL-3.0 | **Compatible**: KOReader ≥ v2026.03

---

## 📖 Overview

QuickUI is a comprehensive KOReader enhancement plugin that integrates **four core features** to make your reading experience smoother and more efficient:

| Feature | Description |
| :--- | :--- |
| ⚡ **Quick Actions** | Customizable action center: panel, bottom bar, custom actions, icon picker, UI font switcher, and more |
| 🎨 **Cover Visual Enhancements** | Placeholder covers, badges, rounded corners, unified aspect ratio, folder previews |
| 🎭 **Cloze Mode** | Annotation masking for review and self-testing (highlights, underlines, strikeouts) |
| 📐 **Header & Footer** | Display time, page numbers, progress, chapter info, battery status at top/bottom of reading screen |

> 💡 **Inspiration**: SimpleUI, ZenUI, ShortcutsToolbar

![Qui-filemanager](pictures/Qui-filemanager.png)
![Qui-reader](pictures/Qui-reader.png)

---

## 📄 License

This project is licensed under the **GNU Affero General Public License v3.0 (AGPL-3.0)**.

You are free to:
- Use this plugin for any purpose
- Modify and adapt the code
- Distribute copies of the original or modified code

Under the following conditions:
- You must **disclose the source code** when you distribute the software
- You must **include the original copyright notice and license**
- You must **state all changes** you have made to the code
- If you run the software as a **network service**, you must make the source code available to users

For the full license text, see: [https://www.gnu.org/licenses/agpl-3.0.en.html](https://www.gnu.org/licenses/agpl-3.0.en.html)

---

## 🚀 Core Features

### 1. ⚡ Quick Actions

This is QuickUI's most powerful module, consisting of the following sub-modules:

#### 📌 1.1 Quick Actions Panel

A customizable action panel integrated into the top menu bar:

| Setting | Options / Description |
| :--- | :--- |
| **Built-in Actions** | WiFi, night mode, rotate, screenshot, continue reading, search, restart, quit, power, HTTP server, font list, etc. |
| **Custom Actions** | Folders, collections, plugins, system actions (Dispatcher), recorded menu actions |
| **Icon Picker** | Nerd Font icons, SVG/PNG files, system icon override |
| **Interface Filter** | Show/hide actions based on current view (Filemanager/Reader) |
| **Button Shape** | Round / Rounded Square / Bare |
| **Button Background** | Transparent / Solid / Light Gray |
| **Button Size** | 60% ~ 150% (step 5%) |
| **Label Size** | 50% ~ 200% (step 10%) |
| **Show Labels** | Toggle |
| **Sliders** | Frontlight intensity / Color temperature (with value display) |
| **Long Press** | Edit button / Open settings |

**Complete Built-in Action List:**

| Action ID | Name | View | Description |
| :--- | :--- | :--- | :--- |
| `home` | Home | Common | Return to Filemanager |
| `wifi` | Wi-Fi | Common | Toggle Wi-Fi |
| `night` | Night Mode | Common | Toggle night mode |
| `rotate` | Rotate | Common | Rotate screen |
| `screenshot` | Screenshot (4s delay) | Common | Take screenshot with delay |
| `continue` | Continue Reading | Common | Open most recently read book |
| `search` | Search | Common | Full-text search / file search |
| `quit` | Quit | Common | Quit KOReader |
| `restart` | Restart | Common | Restart KOReader |
| `power` | Power | Common | Power menu (sleep/restart/quit) |
| `httpinspector` | HTTP Server | Common | Start/stop HTTP inspector server |
| `fontlist` | Font List | Reader | Quick switch reading font |
| `reading_insights` | Reading Insights | Common | Show reading statistics popup |
| `filebrowserplus` | FileBrowserPlus | Common | Launch FileBrowserPlus plugin |
| `zlibrary_search` | ZLibrary Search | Common | Launch ZLibrary search |
| `cloudlibrary_autosync` | CloudLibrary-AutoSync | Common | Toggle auto-sync |
| `cloudlibrary_batch_download_books` | CloudLibrary-Batch Download | Common | Batch download books |
| `cloudlibrary_settings` | CloudLibrary-Settings | Common | CloudLibrary settings |
| `annotations_viewer` | Annotations Viewer | Common | View all/current book annotations |
| `quickui_settings` | QuickUI Settings | Common | Open QuickUI global settings |
| `qa_settings` | QA Settings | Common | Open Quick Actions settings |
| `qa_new` | New Quick Action | Common | Create a new custom action |
| `qa_panel_settings` | Panel Settings | Common | Quick panel settings |
| `qa_add_panel_button` | Add Panel Button | Common | Add button to panel |
| `qa_bb_settings` | Bottom Bar Settings | Common | Bottom bar settings |
| `qa_add_bb_tab` | Add Bottom Bar Tab | Common | Add tab to bottom bar |
| `ui_font_switch` | UI Font Switcher | Common | Switch system UI font |
| `system_icon_override` | System Icon Override | Common | Open system icon replacement picker |
| `interface_filter` | Interface Filter | Common | Open interface filter settings |
| `toggle_cloze_mode` | Toggle Cloze Mode | Reader | Toggle Cloze mode |
| `QuickUI_CoverSettings` | Cover Settings | Filemanager | Cover visual settings |
| `QuickUI_ClozeSettings` | Cloze Settings | Reader | Cloze mode settings |
| `QuickUI_HFSettings` | Header/Footer Settings | Reader | Header/Footer settings |

#### 📌 1.2 Quick Actions Bottom Bar

A customizable navigation bar at the bottom of the screen:

| Setting | Options / Description |
| :--- | :--- |
| **Enable/Disable** | Global toggle |
| **Show in Reader** | Whether to show in reading view |
| **Mode** | Icons only / Text only / Both |
| **Style** | Default / Framed / Bare |
| **Background** | Solid / Transparent |
| **Colors** | Background / Foreground / Inactive / Accent (HEX support) |
| **Size** | 50% ~ 150% (step 10%) |
| **Icon Size** | 50% ~ 200% (step 10%) |
| **Label Size** | 50% ~ 200% (step 10%) |
| **Show Labels** | Toggle |
| **Tab Management** | Add/Remove/Arrange |
| **Long Press** | Edit tab / Open settings |

#### 📌 1.3 Custom Actions

Supports five types of custom actions:

| Type | Description | Default View |
| :--- | :--- | :--- |
| 📁 **Folder** | Jump to a specific folder | Filemanager (changeable)  |
| 📚 **Collection** | Open a specific collection | Filemanager (changeable)  |
| 🔌 **Plugin/Patch** | Launch any plugin or menu patch | Common (changeable)  |
| ⚙️ **System Action** | Call Dispatcher system actions | Auto-detected (changeable)  |
| 📋 **Recorded Menu Action** | Record any menu item as a quick action | Auto-detected,locked (unchangeable) |

#### 📌 1.4 Icon Picker

| Feature | Description |
| :--- | :--- |
| **Nerd Font Icons** | Automatically scan all available Nerd Font symbols, displayed by hex code |
| **File Icons** | Scan `icons/` directory for SVG/PNG files |
| **Browse** | File browser to select custom icons |
| **Filter** | Search icons by name or codepoint |
| **System Icon Override** | Replace built-in system icons (requires restart) |
| **Batch Operations** | Reset all overrides / Apply all replacements |

#### 📌 1.5 UI Font Switcher

| Font Type | Default Font | Description |
| :--- | :--- | :--- |
| **Regular** | NotoSans-Regular.ttf | Primary UI font |
| **Bold** | NotoSans-Bold.ttf | Bold UI font |
| **Monospace** | DroidSansMono.ttf | Monospace UI font |

- Supports any TTF/OTF font
- Real-time preview
- One-click reset all fonts

#### 📌 1.6 Interface Filter

| Feature | Description |
| :--- | :--- |
| **Enable Filter** | Automatically filter actions based on current view (Filemanager/Reader) |
| **Filemanager Only** | Mark actions to show only in Filemanager |
| **Reader Only** | Mark actions to show only in Reader |
| **Reset Defaults** | Restore all actions to common view |

---

### 2. 🎨 Cover Visual Enhancements

| Category | Options | Description |
| :--- | :--- | :--- |
| **Placeholder Cover** | Simple / Gradient | Placeholder style for books without covers |
| **Badge Size** | Compact / Normal / Large / Extra Large | Badge size adjustment |
| **Badge Color** | Black / White / Gray / Blue / Green / Amber / Red | Badge background color |
| **Badge Display** | Favorite star / Progress % / NEW banner / Dim finished / Page count / Format | Individual toggles |
| **Cover Title Banner** | Show / Centered / Bottom / Opaque background | Show title on cover |
| **Folder Cover** | Gallery (4-grid collage) / Stack / Normal (first cover) / None (folder name only) | Folder display mode |
| **Folder Decorations** | Spine lines / File count / Folder name (centered/bottom/opaque background) | Folder cover details |
| **Aspect Ratio** | 3:4 (default) / 2:3 | Cover aspect ratio |
| **Other** | Rounded corners / Title below cover / Author below cover / Hide underline / Hide up folder | General toggles |

---

### 3. 🎭 Cloze Mode

| Feature | Description |
| :--- | :--- |
| **Maskable Annotations** | Highlights, underlines, strikeouts, inversions |
| **Toggle Modes** | Double-tap / Single-tap (block menu) / Single-tap (show menu) |
| **Maskable Styles** | Individually select which annotation types to mask |
| **Quick Actions** | Cover all / Uncover all |
| **Dispatcher Actions** | `QuickUI_ClozeEnable`, `QuickUI_ClozeToggleAll`, `QuickUI_ClozeSettings` |

---

### 4. 📐 Header & Footer

| Setting | Options |
| :--- | :--- |
| **Position** | Top (left/center/right) / Bottom (left/center/right) |
| **Content** | Time / Page (current/total) / Progress % / Page + Progress / Chapter page / Author / Title / Chapter title / Battery |
| **Font** | Selectable font face / Size / Bold |
| **Padding** | Top padding / Bottom padding / Left/right offset |
| **Time Format** | 24-hour / 12-hour |
| **Progress Decimals** | 0, 1, or 2 |
| **PDF Support** | Show in PDF documents (disabled by default) |

---

## 💡 Lightweight Alternative: Standalone Patches

If QuickUI feels too feature-rich or you only need one specific function, here are two flexible alternatives:

### Option 1: Disable Modules in QuickUI

You can independently enable/disable the four feature modules in QuickUI's settings menu:

| Feature | Settings Entry | Description |
| :--- | :--- | :--- |
| **Quick Actions** | `Settings → Plugin Management → QuickUI` | Uncheck **"Enable Quick Actions"** |
| **Cover Visual Enhancements** | `Settings → Plugin Management → QuickUI` | Uncheck **"Enable Cover"** |
| **Cloze Mode** | `Settings → Plugin Management → QuickUI` | Uncheck **"Enable Cloze Mode"** |
| **Header & Footer** | `Settings → Plugin Management → QuickUI` | Uncheck **"Enable Header & Footer"** |

> Disabling a module requires a **KOReader restart** to take effect.

### Option 2: Use Standalone Patches (Complete QuickUI Replacement)

If you prefer a lighter, single-function experience, you can use these standalone patches. They contain only one feature each, with leaner code and no plugin management overhead.

These patches are by the same author as QuickUI and share the same functionality:

| Module | Patch File | Description | Source |
| :--- | :--- | :--- | :--- |
| **Quick Actions** | `2-quickactions.lua` | Customizable quick action panel (same as QuickUI's panel) | [kopatches repo](https://github.com/gytwo/kopatches) |
| **Cover Visual Enhancements** | `2-fm-cover.lua` | Comprehensive cover and folder cover visual overhaul | [kopatches repo](https://github.com/gytwo/kopatches) |
| **Cloze Mode** | `2-reader-clozemode.lua` | Annotation masking for review and self-testing | [kopatches repo](https://github.com/gytwo/kopatches) |

#### Standalone Patch Installation

1. Download the corresponding `.lua` file from [gytwo/kopatches](https://github.com/gytwo/kopatches).
2. Place it in KOReader's `patches` folder (typically `koreader/patches/`).
3. Restart KOReader.

> To uninstall: simply delete the `.lua` file. Optionally delete any auto-generated config files.

#### How to Choose?

| Scenario | Recommendation |
| :--- | :--- |
| Want **integrated management** of all features, like All-in-One | Use **QuickUI plugin** and disable modules as needed |
| Only interested in **one specific feature**, prefer minimalism | Use the corresponding **standalone patch** |
| Want to try out a feature | Try the standalone patch first, then migrate to QuickUI if desired |

> 💡 **Tip**: QuickUI and standalone patches should **not be installed together**, as they may conflict. Choose one based on your needs.

---

## 🔧 Gesture / Shortcut Support

| Action | Dispatcher Event | View |
| :--- | :--- | :--- |
| Open Quick Panel | `QuickUI_Panel` | Filemanager / Reader |
| Quick Actions Settings | `QuickUI_QASettings` | Filemanager / Reader |
| Cover Settings | `QuickUI_CoverSettings` | Filemanager |
| Enable/Disable Cloze | `QuickUI_ClozeEnable` | Reader |
| Cover/Uncover All | `QuickUI_ClozeToggleAll` | Reader |
| Cloze Settings | `QuickUI_ClozeSettings` | Reader |
| Header/Footer Settings | `QuickUI_HFSettings` | Reader |
| New Quick Action | `QuickUI_NewAction` | Filemanager / Reader |
| Panel Settings | `QuickUI_PanelSettings` | Filemanager / Reader |
| Add Panel Button | `QuickUI_AddPanelButton` | Filemanager / Reader |
| Toggle Bottom Bar | `QuickUI_BottombarToggle` | Filemanager / Reader |
| Bottom Bar Settings | `QuickUI_BottombarSettings` | Filemanager / Reader |
| Add Bottom Bar Tab | `QuickUI_AddBottomBarTab` | Filemanager / Reader |

---

## 📁 File Structure
```
quickui.koplugin/
├── _meta.lua
├── changelog.lua
├── main.lua
├── README.md
├── README.zh_CN.md
│
├── locales/
│   └── zh_CN.po
│
├── qui_actions/
│   ├── qa_actions.lua
│   ├── qa_bottombar.lua
│   ├── qa_icon_picker.lua
│   ├── qa_init.lua
│   ├── qa_menu_recorder.lua
│   ├── qa_panel.lua
│   ├── qa_plugin_scan.lua
│   ├── qa_settings.lua
│   └── qa_uifont.lua
│
├── qui_cover.lua
├── qui_clozemode.lua
├── qui_header_footer.lua
├── qui_i18n.lua
├── qui_updates.lua
└── qui_utils.lua
```
| File | Purpose |
| :--- | :--- |
| `_meta.lua` | Plugin metadata (name, version, author) |
| `changelog.lua` | Version history and update notes |
| `main.lua` | Main entry point, registers Dispatcher actions, builds main menu |
| `README.md` | English documentation |
| `README.zh_CN.md` | Chinese documentation |
| `locales/zh_CN.po` | Simplified Chinese translation |
| `qui_actions/qa_actions.lua` | Action registry (built-in + custom) and execution logic |
| `qui_actions/qa_bottombar.lua` | Bottom navigation bar builder |
| `qui_actions/qa_icon_picker.lua` | Icon picker (Nerd Font + SVG/PNG) |
| `qui_actions/qa_init.lua` | Quick Actions module entry point |
| `qui_actions/qa_menu_recorder.lua` | Menu action recorder (for custom actions) |
| `qui_actions/qa_panel.lua` | Quick panel builder |
| `qui_actions/qa_plugin_scan.lua` | Plugin scanner |
| `qui_actions/qa_settings.lua` | Quick Actions settings menu |
| `qui_actions/qa_uifont.lua` | UI font switcher |
| `qui_cover.lua` | Cover Visual Enhancements module |
| `qui_clozemode.lua` | Cloze Mode module |
| `qui_header_footer.lua` | Header & Footer module |
| `qui_i18n.lua` | Internationalization loader (loads .po files) |
| `qui_updates.lua` | Update checker (GitHub / Gitee) |
| `qui_utils.lua` | Common utilities (config, serialization, fonts, colors) |

---

## ⚙️ Configuration

All settings are stored in: `~/.adds/koreader/settings/quickui.lua`

Default settings are defined in `DEFAULT_SETTINGS` in `qui_utils.lua`:

| Section | Key Prefix | Description |
| :--- | :--- | :--- |
| Panel | `qa_panel_*` | Panel enable, button layout, shape, size, labels, sliders |
| Bottom Bar | `qa_bb_*` | Bottom bar enable, mode, style, size, colors, labels |
| Quick Actions Common | `qa_common_*` | Custom actions, interface filter, icon overrides, UI font overrides |
| Cover | `cover_*` | Cover style, badges, aspect ratio, rounded corners, folder mode |
| Cloze | `cl_*` | Cloze enable, toggle mode, maskable styles |
| Header/Footer | `hf_*` | Header/Footer enable, content, font, padding, time format |

### Preset Management

Each module supports **Save Preset**, **Apply Preset**, and **Reset to Default**:

| Preset Scope | Modules Included |
| :--- | :--- |
| All | Panel + Bottom Bar + Quick Actions Common + Cover + Cloze + Header/Footer |
| QA | Panel + Bottom Bar + Quick Actions Common |
| Cover | Cover settings only |
| Cloze | Cloze settings only |
| Header/Footer | Header/Footer settings only |

---

## 🌐 Internationalization

| Language | Support |
| :--- | :--- |
| English | ✅ Default |
| Chinese (Simplified/Traditional) | ✅ via `locales/zh_CN.po` |
| Other Languages | Add `.po` files to `locales/` directory |

---

## 📦 Updates

| Source | Type | Description |
| :--- | :--- | :--- |
| GitHub (Latest) | Stable | Latest stable release |
| GitHub (Pre-release) | Pre-release | Beta/development version |
| Gitee (Latest) | Stable | Chinese mirror |

Update process:
1. Check network connection
2. Fetch latest version info
3. Compare version numbers
4. Download ZIP package
5. Auto-extract and install
6. Prompt to restart KOReader

Supports **downgrading** to any historical version.

---

## 🔌 Compatibility & Dependencies

| Item | Requirement |
| :--- | :--- |
| **KOReader** | ≥ v2026.03 |
| **Device** | Frontlight/warmth controls require device support |

---

## 📝 Changelog

### v1.0.0 (2026-07-04)

**New Features**

- Four core features integrated: Quick Actions, Cover Visual Enhancements, Cloze Mode, Header & Footer
- Quick Actions: 28+ built-in actions (WiFi, night mode, rotate, screenshot, etc.)
- Quick Actions: Custom actions (folders, collections, plugins, system actions, recorded menu actions)
- Quick Actions: Icon picker (Nerd Font + SVG/PNG + system icon override)
- Quick Actions: Interface filter (auto-switch between Filemanager/Reader)
- Quick Actions: Bottom navigation bar (customizable tabs, styles, colors)
- Cover Visual Enhancements: Placeholder covers, badges (favorite/progress/NEW/page count/format), rounded corners, unified aspect ratio
- Cover Visual Enhancements: Folder covers (Gallery/Stack/Normal/None)
- Cloze Mode: Annotation masking (highlights/underlines/strikeouts/inversions), three toggle modes
- Header & Footer: Time, page numbers, progress, chapter info, author, title, battery
- UI Font Switcher: Regular/Bold/Monospace font replacement
- Internationalization support (Chinese translation)
- Online updates (GitHub/Gitee)

**Improvements**

- Unified configuration management (`quickui.lua`)
- Module-independent enable/disable
- Preset management (save/apply/reset)

**Fixes**

- None (initial release)

---

## 🧑‍💻 Developer Info

- **Author**: gytwo
- **Repository**: [github.com/gytwo/quickui.koplugin](https://github.com/gytwo/quickui.koplugin)
- **License**: AGPL-3.0
