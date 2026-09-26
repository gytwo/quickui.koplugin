# QuickUI - KOReader Enhancement Plugin

> **QuickUI: Quick Actions · Cover Visuals · Cloze Mode · Header & Footer · Metadata Editor — more efficient KOReader.**

> **Author**: gytwo | **License**: AGPL-3.0 | **Compatible**: KOReader ≥ v2026.03

---

## 📖 Overview

QuickUI is a comprehensive KOReader enhancement plugin that integrates **five core features** to make your reading experience smoother and more efficient:

| Feature | Description |
| :--- | :--- |
| ⚡ **Quick Actions** | Customizable action center: panel, bottom bar, vertical bar, custom actions, icon picker, UI font switcher, and more |
| 🎨 **Cover Visual Enhancements** | Placeholder covers, badges, rounded corners, unified aspect ratio, folder previews |
| 🔍 **Cloze Mode** | Annotation masking for review and self-testing (highlights, underlines, strikeouts) |
| 📐 **Header & Footer** | Display time, page numbers, progress, chapter info, battery status at top/bottom of reading screen |
| 📖 **Metadata Editor** | Edit book metadata (title, authors, series, etc.) manually or via online sources |

> 💡 **Inspiration**:
- [shortcutstoolbar.koplugin](https://github.com/xusoo/shortcutstoolbar.koplugin)
- [simpleui.koplugin](https://github.com/doctorhetfield-cmd/simpleui.koplugin)
- [zenos.koplugin](https://github.com/xZenLabs/zen-os)
- [metadata.koplugin](https://github.com/ZHA30/metadata.koplugin) (metadata editor reference)
- [kopatches repo](https://github.com/gytwo/kopatches)
- [KOReader.patches](https://github.com/joshuacant/KOReader.patches)

<table>
  <tr>
    <td><img src="pictures/Qui-filemanager.png" alt="Qui-filemanager" width="400" /></td>
    <td><img src="pictures/Qui-reader.png" alt="Qui-reader" width="400" /></td>
  </tr>
</table>

---

## 📄 License

This project is licensed under the **GNU Affero General Public License v3.0 (AGPL-3.0)**.

For the full license text, see: [https://www.gnu.org/licenses/agpl-3.0.en.html](https://www.gnu.org/licenses/agpl-3.0.en.html)

---

## 🚀 Core Features

<img src="pictures/Qui-settings-Qui.png" alt="Qui-settings-Qui" width="400" />

### 1. ⚡ Quick Actions

This is QuickUI's most powerful module, consisting of the following sub-modules:

<img src="pictures/Qui-settings-QA.png" alt="Qui-settings-QA" width="400" />

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

<table>
  <tr>
    <td><img src="pictures/Qui-settings-QA-panel.png" alt="Qui-settings-QA-panel" width="400" /></td>
    <td><img src="pictures/Qui-settings-QA-panel-addbutton.png" alt="Qui-settings-QA-panel-addbutton" width="400" /></td>
  </tr>
</table>

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
| `qa_vb_toggle` | Toggle Vertical Bar | Common | Show/hide the vertical bar |
| `qa_vb_settings` | Vertical Bar Settings | Common | Open vertical bar settings |
| `qa_add_vb_button` | Add Vertical Bar Button | Common | Add a button to the vertical bar |
| `reader_sliders` | Reader Sliders | Reader | Open the full typesetting-slider popup |
| `QuickUI_EditMetadata` | Edit Metadata | Filemanager | Edit the selected book's metadata |

<table>
  <tr>
    <td><img src="pictures/Qui-settings-QA-qa.png" alt="Qui-settings-QA-qa" width="400" /></td>
    <td><img src="pictures/Qui-settings-QA-qa-editqa.png" alt="Qui-settings-QA-qa-editqa" width="400" /></td>
  </tr>
</table>

#### 📌 1.2 Bottom Bar

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

<table>
  <tr>
    <td><img src="pictures/Qui-settings-QA-bottom.png" alt="Qui-settings-QA-bottom" width="400" /></td>
    <td><img src="pictures/Qui-settings-QA-bottom-addtab.png" alt="Qui-settings-QA-bottom-addtab" width="400" /></td>
  </tr>
</table>

#### 📌 1.3 Vertical Bar

A launcher docked to the screen edge, shown as a vertical strip.

**How to enable**:

| Method | Action |
| :--- | :--- |
| **QuickUI Settings** | Tools → QuickUI → Quick Actions Settings → Vertical Bar → check "Enable Vertical Bar" |
| **Dispatcher action** | Bind `QuickUI_VerticalBarToggle` to a gesture / shortcut; each activation toggles show/hide |
| **Quick panel button** | Add `qa_vb_toggle` ("Toggle Vertical Bar") to the panel or bottom bar |
| **Action pool** | Add `qa_vb_settings` (open settings) or `qa_add_vb_button` (add button) to the panel |

**Interaction**:

- **Drag**: swipe horizontally to move the bar to the other screen edge
- **Tap button**: run the action
- **Long-press button**: edit that button
- **Vertical swipe**: page through buttons (if "Swipe to page" is on)
- **Tap outside**: dismiss

**Settings**:

| Setting | Options |
| :--- | :--- |
| **Enable/Disable** | Global toggle |
| **Side** | Left / Right |
| **Background** | White / Light gray / Transparent |
| **Animation** | Off / Fast / Medium / Slow |
| **Swipe to page** | Vertical swipe to page through buttons |
| **Button management** | Add / Remove / Reorder |
| **Show labels** | Toggle |
| **Bar size** | 60% ~ 150% (step 10%) |
| **Icon size** | 50% ~ 200% (step 10%) |
| **Label size** | 50% ~ 200% (step 10%) |
| **Long-press action** | Edit button / Open settings |

#### 📌 1.4 Reader Sliders

Typesetting sliders for the reader.

**How to enable**:

| Method | Action |
| :--- | :--- |
| **Dispatcher action** | Bind `QuickUI_ReaderSliders` to a gesture / shortcut; opens the full popup |
| **Action pool** | Add `reader_sliders` to the panel or vertical bar; tapping opens the popup |
| **Embed in panel / vertical bar** | Enable individual slider toggles in the panel / vertical bar settings for inline sliders |

**Interaction**:

- **Drag slider**: adjust value
- **Tap −/+ buttons**: step adjustment
- **Tap value**: open SpinWidget for fine-tuning, can set as default
- **Long-press label**: reset to default
- **Long-press slider**: open the full slider list popup

**Sliders**:

| Slider | Description | Applies to |
| :--- | :--- | :--- |
| **Font size** | Body text size (12-90) | Reflowable (EPUB / FB2 / TXT) |
| **Line spacing** | Line spacing percentage (50-200%) | Reflowable |
| **Contrast** | Font gamma (10-56) | Reflowable / PDF |
| **Left/right margins** | Horizontal page margins (0-140) | Reflowable |
| **Top margin** | Top page margin (0-140) | Reflowable |
| **Bottom margin** | Bottom page margin (0-140) | Reflowable |
| **PDF contrast** | PDF rendering contrast (0.8-50) | PDF / DJVU |
| **PDF zoom** | Zoom factor, overlap, rows/columns | PDF / DJVU |
| **First-line indent** | Paragraph first-line indent mode | Reflowable |
| **Paragraph spacing** | Spacing between paragraphs | Reflowable |
| **CJK tailoring** | CJK typesetting optimization | Reflowable |

#### 📌 1.5 Custom Actions

Supports five types of custom actions:

| Type | Description | Default View |
| :--- | :--- | :--- |
| 📁 **Folder** | Jump to a specific folder | Filemanager (changeable) |
| 📚 **Collection** | Open a specific collection | Filemanager (changeable) |
| 🔌 **Plugin/Patch** | Launch any plugin or menu patch | Common (changeable) |
| ⚙️ **System Action** | Call Dispatcher system actions | Auto-detected (changeable) |
| 📋 **Recorded Menu Action** | Record any menu item as a quick action | Auto-detected, locked (unchangeable) |

<table>
  <tr>
    <td><img src="pictures/Qui-settings-QA-qa-addnew.png" alt="Qui-settings-QA-qa-addnew" width="400" /></td>
    <td><img src="pictures/Qui-settings-QA-actiontype.png" alt="Qui-settings-QA-actiontype" width="400" /></td>
  </tr>
</table>

#### 📌 1.6 Icon Picker

| Feature | Description |
| :--- | :--- |
| **Nerd Font Icons** | Automatically scan all available Nerd Font symbols, displayed by hex code |
| **File Icons** | Scan `icons/` directory for SVG/PNG files |
| **Browse** | File browser to select custom icons |
| **Filter** | Search icons by name or codepoint |
| **System Icon Override** | Replace built-in system icons (requires restart) |
| **Batch Operations** | Reset all overrides / Apply all replacements |

<table>
  <tr>
    <td><img src="pictures/Qui-settings-QA-iconpicker.png" alt="Qui-settings-QA-iconpicker" width="400" /></td>
    <td><img src="pictures/Qui-settings-QA-systemiconoverride.png" alt="Qui-settings-QA-systemiconoverride" width="400" /></td>
  </tr>
</table>

#### 📌 1.7 UI Font Switcher

| Font Type | Default Font | Description |
| :--- | :--- | :--- |
| **Regular** | NotoSans-Regular.ttf | Primary UI font |
| **Bold** | NotoSans-Bold.ttf | Bold UI font |
| **Monospace** | DroidSansMono.ttf | Monospace UI font |

- Supports any TTF/OTF font
- Real-time preview
- One-click reset all fonts

<img src="pictures/Qui-settings-QA-uifontswitch.png" alt="Qui-settings-QA-uifontswitch" width="400" />

#### 📌 1.8 Interface Filter

| Feature | Description |
| :--- | :--- |
| **Enable Filter** | Automatically filter actions based on current view (Filemanager/Reader) |
| **Filemanager Only** | Mark actions to show only in Filemanager |
| **Reader Only** | Mark actions to show only in Reader |
| **Reset Defaults** | Restore all actions to default view |

<img src="pictures/Qui-settings-QA-filter.png" alt="Qui-settings-QA-filter" width="400" />

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

<img src="pictures/Qui-settings-Cover.png" alt="Qui-settings-Cover" width="400" />

---

### 3. 🔍 Cloze Mode

| Feature | Description |
| :--- | :--- |
| **Maskable Annotations** | Highlights, underlines, strikeouts, inversions |
| **Toggle Modes** | Double-tap / Single-tap (block menu) / Single-tap (show menu) |
| **Maskable Styles** | Individually select which annotation types to mask |
| **Quick Actions** | Cover all / Uncover all |
| **Dispatcher Actions** | `QuickUI_ClozeEnable`, `QuickUI_ClozeToggleAll`, `QuickUI_ClozeSettings` |

<img src="pictures/Qui-settings-Cloze.png" alt="Qui-settings-Cloze" width="400" />

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

<img src="pictures/Qui-settings-HF.png" alt="Qui-settings-HF" width="400" />

---

### 5. 📖 Metadata Editor

Edit book metadata (title, authors, series, genres, language, publisher, description), either manually or by searching online sources.

#### Editable fields

| Field | Notes |
| :--- | :--- |
| **Title** | Book title |
| **Authors** | Multiple authors, one per line |
| **Series** | Series name + position |
| **Genres** | Multiple genres, one per line |
| **Language** | ISO code, e.g. `zh`, `en`, `ja` |
| **Publisher** | Publisher name (EPUB only) |
| **Description** | Book description, multi-paragraph |

#### How to edit

**Manually**: tap any field row and edit in the popup input. Edited fields are marked with `●`.

**Online search**: tap "Find metadata online", edit the query, pick a source (Douban, Google Books, Hardcover, Open Library), search. Preview each result, then tap "Apply". **Manually edited fields are never overwritten.**

- Douban and Open Library work without configuration
- Google Books needs an API key, Hardcover needs an API token — tapping one without a key prompts for input, then searches automatically
- Unconfigured sources are labelled `(API key required)`

#### How changes are applied

**EPUB**: the embedded OPF metadata is edited and the file is repacked. Before replacement, a backup is created:

| File | Purpose |
| :--- | :--- |
| `book.epub.quickui-metadata.bak` | Original EPUB before the edit |
| `book.epub.quickui-metadata.bak.json` | Sidecar snapshot |

As long as both files exist, the editor shows "Restore original metadata" — a one-step undo. **Delete both files if you no longer need to undo** (the book itself is unaffected; the next edit will create a fresh backup).

**Non-EPUB (PDF, MOBI, AZW3, FB2, TXT, etc.)**: the original file is not modified. Custom metadata is written to the book's `.sdr/` folder:
```
book.sdr/
└── custom_metadata.lua
```

This metadata is KOReader-only and does not travel with the file to other readers. Delete the custom metadata to revert.

#### How to open

**Option 1: Long-press a book**
- In FileManager, History, Collections, or FileSearcher, **long-press a book** → "Edit metadata"
- The entry is greyed out if the book is currently open in the reader

**Option 2: QuickUI Settings**
- Tools → QuickUI → **Metadata Settings** → "Edit current book's metadata"
- If one book is checked, opens it directly; if multiple are checked, shows a picker; if none, prompts to select a book first

**Option 3: Dispatcher action**
- Action name: `QuickUI_EditMetadata`
- Bind it to a gesture in **Gestures**, or to a shortcut in **Dispatcher**
- It edits the currently selected book in the file manager

**Option 4: Quick panel / vertical bar**
- Add `QuickUI_EditMetadata` ("Edit Metadata") from the action pool
- Tapping it edits the currently selected book

> ⚠️ **A book currently open in the reader cannot have its metadata edited.** Close it first.

#### Credits

The metadata read/write logic in this module is adapted from [zen_ui.koplugin](https://github.com/AnthonyGress/zen_ui.koplugin) (MIT).

The online source scrapers reference [metadata.koplugin](https://github.com/ZHA30/metadata.koplugin).

Vendored libraries:

- **SLAXML / SLAXDOM** (v0.8, MIT, Copyright © 2013-2018 Gavin Kistner) — XML parsing
- **ca-bundle.crt** (certifi 2026.6.17, MPL-2.0) — HTTPS certificate validation

See [`LICENSES.md`](LICENSES.md) for details.

---

## 💡 Lightweight Alternative: Standalone Patches

If QuickUI feels too feature-rich or you only need one specific function, here are two flexible alternatives:

### Option 1: Disable Modules in QuickUI

You can independently enable/disable each feature module in QuickUI's settings menu:

| Feature | Settings Entry | Description |
| :--- | :--- | :--- |
| **Quick Actions** | `Tools → QuickUI` | Uncheck **"Enable Quick Actions"** |
| **Cover Visual Enhancements** | `Tools → QuickUI` | Uncheck **"Enable Cover"** |
| **Cloze Mode** | `Tools → QuickUI` | Uncheck **"Enable Cloze Mode"** |
| **Header & Footer** | `Tools → QuickUI` | Uncheck **"Enable Header & Footer"** |
| **Metadata Editor** | `Tools → QuickUI` | Uncheck **"Enable Metadata Editor"** |

> Disabling a module requires a **KOReader restart** to take effect.

### Option 2: Use Standalone Patches (Complete QuickUI Replacement)

If you prefer a lighter, single-function experience, you can use these standalone patches. They contain only one feature each, with leaner code and no plugin management overhead.

| Module | Patch File | Description | Source |
| :--- | :--- | :--- | :--- |
| **Quick Actions** | `2-quickactions.lua` | Customizable quick action panel | [kopatches repo](https://github.com/gytwo/kopatches) |
| **Cover Visual Enhancements** | `2-fm-cover.lua` | Comprehensive cover and folder cover visual overhaul | [kopatches repo](https://github.com/gytwo/kopatches) |
| **Cloze Mode** | `2-reader-clozemode.lua` | Annotation masking for review and self-testing | [kopatches repo](https://github.com/gytwo/kopatches) |

#### Standalone Patch Installation

1. Download the corresponding `.lua` file from [gytwo/kopatches](https://github.com/gytwo/kopatches).
2. Place it in KOReader's `patches` folder (typically `koreader/patches/`).
3. Restart KOReader.

> To uninstall: simply delete the `.lua` file.

---

## 🔧 Gesture / Shortcut Support

| Action | Dispatcher Event | View |
| :--- | :--- | :--- |
| Open Quick Panel | `QuickUI_Panel` | General |
| Quick Actions Settings | `QuickUI_QASettings` | General |
| Cover Settings | `QuickUI_CoverSettings` | Filemanager |
| Enable/Disable Cloze | `QuickUI_ClozeEnable` | Reader |
| Cover/Uncover All | `QuickUI_ClozeToggleAll` | Reader |
| Cloze Settings | `QuickUI_ClozeSettings` | Reader |
| Header/Footer Settings | `QuickUI_HFSettings` | Reader |
| New Quick Action | `QuickUI_NewAction` | General |
| Panel Settings | `QuickUI_PanelSettings` | General |
| Add Panel Button | `QuickUI_AddPanelButton` | General |
| Toggle Bottom Bar | `QuickUI_BottombarToggle` | General |
| Bottom Bar Settings | `QuickUI_BottombarSettings` | General |
| Add Bottom Bar Tab | `QuickUI_AddBottomBarTab` | General |
| Toggle Vertical Bar | `QuickUI_VerticalBarToggle` | General |
| Vertical Bar Settings | `QuickUI_VerticalBarSettings` | General |
| Add Vertical Bar Button | `QuickUI_AddVerticalBarButton` | General |
| Reader Sliders | `QuickUI_ReaderSliders` | Reader |
| Edit Metadata | `QuickUI_EditMetadata` | Filemanager |

---

## 📁 File Structure
```
quickui.koplugin/
├── _meta.lua
├── changelog.lua
├── main.lua
├── README.md
├── README.zh_CN.md
├── LICENSES.md
│
├── locales/
│ └── zh_CN.po
│
├── qui_actions/
│ ├── qa_actions.lua # Action registry (built-in + custom) and execution
│ ├── qa_bar_settings.lua # Panel / bottom bar / vertical bar editors and settings
│ ├── qa_bottombar.lua # Bottom navigation bar builder
│ ├── qa_icon_picker.lua # Icon picker (Nerd Font + SVG/PNG)
│ ├── qa_init.lua # Quick Actions module entry
│ ├── qa_menu_recorder.lua # Menu action recorder
│ ├── qa_panel.lua # Quick panel builder
│ ├── qa_plugin_scan.lua # Plugin scanner
│ ├── qa_reader_sliders.lua # Reader typesetting sliders (font/line spacing/margins/PDF zoom)
│ ├── qa_settings.lua # Quick Actions settings menu
│ ├── qa_uifont.lua # UI font switcher
│ └── qa_vertical_bar.lua # Vertical bar builder
│
├── qui_metadata/
│ ├── qm_init.lua # Metadata module entry
│ ├── qm_editor.lua # Field editor UI
│ ├── qm_service.lua # Metadata read/write orchestration (EPUB / sidecar)
│ ├── qm_epub.lua # EPUB OPF parsing, repacking, transaction recovery
│ ├── qm_http.lua # Unified HTTP / HTTPS layer
│ ├── qm_isbn.lua # ISBN validation
│ ├── qm_google_books.lua # Google Books source
│ ├── qm_hardcover.lua # Hardcover source
│ ├── qm_open_library.lua # Open Library source
│ ├── qm_douban.lua # Douban source (HTML scraping)
│ ├── qm_provider_picker.lua # Provider picker / search / result preview
│ ├── qm_slaxml.lua # SLAXML v0.8 (XML parsing)
│ ├── qm_slaxdom.lua # SLAXML DOM wrapper
│ └── ca-bundle.crt # certifi root certificate bundle
│
├── qui_cover.lua # Cover visual enhancements
├── qui_clozemode.lua # Cloze mode
├── qui_header_footer.lua # Header & footer
├── qui_i18n.lua # i18n loader
├── qui_updates.lua # Update checker
└── qui_utils.lua # Common utilities
```

---

## ⚙️ Configuration

All settings are stored in: `~/koreader/settings/quickui.lua`

Default settings are defined in `DEFAULT_SETTINGS` in `qui_utils.lua`:

| Section | Key Prefix | Description |
| :--- | :--- | :--- |
| Panel | `qa_panel_*` | Panel enable, button layout, shape, size, labels, sliders |
| Bottom Bar | `qa_bb_*` | Bottom bar enable, mode, style, size, colors, labels |
| Vertical Bar | `qa_vb_*` | Vertical bar enable, side, style, size, labels |
| Quick Actions Common | `qa_common_*` | Custom actions, interface filter, icon overrides, UI font overrides |
| Cover | `cover_*` | Cover style, badges, aspect ratio, rounded corners, folder mode |
| Cloze | `cl_*` | Cloze enable, toggle mode, maskable styles |
| Header/Footer | `hf_*` | Header/Footer enable, content, font, padding, time format |
| Metadata | `metadata_*` | Metadata module toggle, Google Books API key, Hardcover token |

### Preset Management

Each module supports **Save Preset**, **Apply Preset**, and **Reset to Default**:

| Preset Scope | Modules Included |
| :--- | :--- |
| All | Panel + Bottom Bar + Vertical Bar + Quick Actions Common + Cover + Cloze + Header/Footer + Metadata |
| QA | Panel + Bottom Bar + Vertical Bar + Quick Actions Common |
| Cover | Cover settings only |
| Cloze | Cloze settings only |
| Header/Footer | Header/Footer settings only |
| Metadata | Metadata settings only |

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

## 🧑‍💻 Developer Info

- **Author**: gytwo
- **Repository**: [github.com/gytwo/quickui.koplugin](https://github.com/gytwo/quickui.koplugin)
- **License**: AGPL-3.0
