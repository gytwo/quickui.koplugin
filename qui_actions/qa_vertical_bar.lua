--[[
QuickUI - Vertical Action Bar (侧边栏)

A draggable pop-up launcher styled EXACTLY like bookshelf's start menu:
  * PanelFrame -- hand-painted concentric rounded rect + drop shadow
  * row_h / icon_col_w / pad / icon_gap / font faces all copied from
    bookshelf_start_menu.lua
  * press feedback is a full-width underline across the row's bottom edge
  * rows are [icon][label], icon butts directly against label

Dragging uses KOReader's MovableContainer. Position is NOT persisted --
every open starts at the side-configured default (left or right, vertically
centred). Dragging is a per-session convenience only.

Pagination: only what fits the screen per page is drawn. When there are
more slots than fit, a pager row (prev/next) is appended. Storage is
unbounded -- VISIBLE_ROWS only controls how many rows per page.

Background: white (default) or transparent. Transparent keeps the border
ring but skips the white fill and the shadow, letting the page beneath
show through.

Open/close animation: direct port of bookshelf_start_menu.lua's open/close
wipe, working on a fixed _dirty_region (panel + shadow) so the shadow is
part of the animation rather than popping in at the end. e-ink only; on
LCD the per-strip refreshes coalesce and nothing shows, so it falls through
to the instant show/hide. Speed via qa_vb_animation (off/fast/medium/slow).
]]

local Blitbuffer      = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device          = require("device")
local Font            = require("ui/font")
local FrameContainer  = require("ui/widget/container/framecontainer")
local Geom            = require("ui/geometry")
local GestureRange    = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local IconWidget      = require("ui/widget/iconwidget")
local InputContainer  = require("ui/widget/container/inputcontainer")
local MovableContainer= require("ui/widget/container/movablecontainer")
local Size            = require("ui/size")
local TextWidget      = require("ui/widget/textwidget")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local ButtonDialog    = require("ui/widget/buttondialog")
local InfoMessage     = require("ui/widget/infomessage")
local Notification    = require("ui/widget/notification")
local Screen          = Device.screen
local _               = require("gettext")

local Utils    = require("qui_utils")
local QA       = require("qui_actions.qa_actions")
local settings = require("qui_actions.qa_settings")

local M = {}

local _overlay        = nil
local _current_page   = 1

-- ============================================================
-- Metrics -- bookshelf's constants, scaled by our own percentage keys
-- ============================================================

local function pct(key, default)
    return (Utils.getNumber(key, default) or default) / 100
end

local function _metrics()
    local size_scale  = pct("qa_vb_size_pct", 100)
    local icon_scale  = pct("qa_vb_icon_scale_pct", 100)
    local label_scale = pct("qa_vb_label_scale_pct", 100)
    -- Overall size multiplier applies to every fixed dimension; the icon /
    -- label percentages then further scale the icon column and the two
    -- font sizes respectively.
    local function S(n) return Screen:scaleBySize(math.max(1, math.floor(n * size_scale))) end
    return {
        row_h        = S(40),
        pad          = S(10),
        icon_col_w   = S(math.max(1, math.floor(30 * icon_scale))),
        icon_gap     = S(5),
        icon_face    = Font:getFace("cfont", math.max(6, math.floor(22 * size_scale * icon_scale))),
        label_face   = Font:getFace("cfont", math.max(6, math.floor(18 * size_scale * label_scale))),
        panel_border = S(2),
        panel_pad    = S(3),
        panel_radius = S(4),
        panel_shadow = S(2),
        focus_border = S(2),
    }
end

-- ============================================================
-- Animation step counts, keyed by qa_vb_animation
-- ============================================================

local ANIM_STEPS = { off = nil, fast = 5, medium = 8, slow = 12 }

local function _resolveSteps()
    if not (Device.hasEinkScreen and Device:hasEinkScreen()) then return nil end
    local key = Utils.getString("qa_vb_animation", "fast")
    return ANIM_STEPS[key]
end

-- ============================================================
-- PanelFrame -- concentric rounded rect + optional white fill
-- ============================================================

local PANEL_SHADOW_DAY   = Blitbuffer.gray(0.5)
local PANEL_SHADOW_NIGHT = Blitbuffer.gray(0.15)

local function _shadowGray()
    local ok, sync = pcall(require("lib/bookshelf_night_mode_sync"))
    if ok and sync and sync.active and sync.active() then
        return PANEL_SHADOW_NIGHT
    end
    return PANEL_SHADOW_DAY
end

local PanelFrame = WidgetContainer:extend{
    bordersize = 0,
    padding    = 0,
    radius     = 0,
    margin     = 0,
    shadow     = 0,
    bg         = "white",
}
function PanelFrame:getSize()
    local s = self[1]:getSize()
    local chrome = 2 * (self.bordersize + self.padding)
    return Geom:new{ w = s.w + chrome, h = s.h + chrome }
end
function PanelFrame:paintTo(bb, x, y)
    local sz = self:getSize()
    self.dimen = Geom:new{ x = x, y = y, w = sz.w, h = sz.h }
    local t = self.bordersize
    local r = self.radius

    if self.bg == "transparent" then
        bb:paintRect(x, y, sz.w, t, Blitbuffer.COLOR_BLACK)
        bb:paintRect(x, y + sz.h - t, sz.w, t, Blitbuffer.COLOR_BLACK)
        bb:paintRect(x, y, t, sz.h, Blitbuffer.COLOR_BLACK)
        bb:paintRect(x + sz.w - t, y, t, sz.h, Blitbuffer.COLOR_BLACK)
        self[1]:paintTo(bb, x + t + self.padding, y + t + self.padding)
        return
    end

    if self.shadow and self.shadow > 0 then
        bb:paintRoundedRect(x + self.shadow, y + self.shadow, sz.w, sz.h,
            _shadowGray(), r)
    end
    bb:paintRoundedRect(x, y, sz.w, sz.h, Blitbuffer.COLOR_BLACK, r)

    local fill = Blitbuffer.COLOR_WHITE
    if self.bg == "flat" then
        fill = Blitbuffer.gray(0.08)
    end

    bb:paintRoundedRect(x + t, y + t, sz.w - 2 * t, sz.h - 2 * t,
        fill, math.max(0, r - t))
    self[1]:paintTo(bb, x + t + self.padding, y + t + self.padding)
end

-- ============================================================
-- Slots (context filter)
-- ============================================================

local function currentView()
    if not Utils.getBool("qa_common_context_filter") then return "common" end
    local RUI = require("apps/reader/readerui")
    if RUI and RUI.instance and not RUI.instance.tearing_down then
        return "reader"
    end
    local FM = require("apps/filemanager/filemanager")
    if FM and FM.instance then return "filemanager" end
    return "common"
end

local function getSlots()
    local slots = Utils.get("qa_vb_slots", nil)
    if type(slots) ~= "table" then return {} end
    if not Utils.getBool("qa_common_context_filter") then return slots end

    local view = currentView()
    local valid = {}
    for __, id in ipairs(slots) do
        local v = QA.getActionViewFinal(id)
        if view == "filemanager" then
            if v == "filemanager" or v == "common" then valid[#valid + 1] = id end
        elseif view == "reader" then
            if v == "reader" or v == "common" then valid[#valid + 1] = id end
        else
            valid[#valid + 1] = id
        end
    end
    return valid
end

-- ============================================================
-- Icon helper
-- ============================================================

local function _makeIcon(icon_value, m)
    local nerd_char = QA.nerdIconChar(icon_value)
    if nerd_char then
        return TextWidget:new{
            text    = nerd_char,
            face    = m.icon_face,
            fgcolor = Blitbuffer.COLOR_BLACK,
        }
    end
    local file = Utils.getIconFile(icon_value)
    if file and Utils.fileExists(file) then
        local iw = IconWidget:new{
            file = file,
            width = m.icon_col_w,
            height = m.icon_col_w,
            alpha = true,
        }
        if iw.file and iw.file:find("icon-not-found", 1, true) then
            if iw.free then iw:free() end
            return TextWidget:new{ text = " ", face = m.icon_face }
        end
        return iw
    end
    return TextWidget:new{ text = " ", face = m.icon_face }
end

-- ============================================================
-- One row -- [icon][label]
-- ============================================================
-- Rows must NOT register a `hold` ges_event -- hold bubbles to the wrapping
-- MovableContainer for dragging. Only `tap` is registered.

local function _buildRow(action_id, m, row_w)
    local label, icon_path
    if action_id == "__add" then
        label     = _("Add")
        icon_path = "nerd:F44D"   -- fa-plus
    else
        label     = QA.getLabelForAction(action_id) or action_id
        icon_path = QA.getIconForAction(action_id)
    end
    local show_labels = Utils.getBool("qa_vb_labels", true)

    local icon = _makeIcon(icon_path, m)

    local label_widget
    if show_labels then
        local label_max = math.max(Screen:scaleBySize(40),
            row_w - m.pad - m.icon_col_w - m.icon_gap - m.pad - 2 * m.focus_border)
        label_widget = TextWidget:new{
            text      = label,
            face      = m.label_face,
            fgcolor   = Blitbuffer.COLOR_BLACK,
            max_width = label_max,
        }
    end

    local group = HorizontalGroup:new{
        align = "center",
        HorizontalSpan:new{ width = m.pad },
        CenterContainer:new{
            dimen = Geom:new{ w = m.icon_col_w, h = m.row_h },
            icon,
        },
    }
    if label_widget then
        group[#group + 1] = HorizontalSpan:new{ width = m.icon_gap }
        group[#group + 1] = label_widget
    end
    local used = 0
    for __, child in ipairs(group) do used = used + child:getSize().w end
    group[#group + 1] = HorizontalSpan:new{
        width = math.max(0, row_w - 2 * m.focus_border - used - m.pad),
    }
    group[#group + 1] = HorizontalSpan:new{ width = m.pad }

    local frame = FrameContainer:new{
        width      = row_w,
        bordersize = 0,
        margin     = m.focus_border,
        padding    = 0,
        group,
    }

    local row = InputContainer:new{ dimen = frame:getSize(), frame }
    row._frame = frame

    if Device:isTouchDevice() then
        row.ges_events = {
            Tap  = { GestureRange:new{ ges = "tap",  range = row.dimen } },
            Hold = { GestureRange:new{ ges = "hold", range = row.dimen } },
        }
    end
    return row
end

-- ============================================================
-- Panel width
-- ============================================================

local function _measurePanelWidth(slots, m)
    local show_labels = Utils.getBool("qa_vb_labels", true)
    if not show_labels then
        return m.pad + m.icon_col_w + m.pad + 2 * m.focus_border
    end
    local chrome = m.pad + m.icon_col_w + m.icon_gap + m.pad + 2 * m.focus_border
    local max_natural = 0
    for __, id in ipairs(slots) do
        local label = QA.getLabelForAction(id) or id
        local probe = TextWidget:new{ text = label, face = m.label_face }
        local w = probe:getSize().w
        probe:free()
        local row_w = w + chrome
        if row_w > max_natural then max_natural = row_w end
    end
    local sw = Screen:getWidth()
    local min_w = Screen:scaleBySize(120)
    local max_w = math.floor(sw * 0.6)
    return math.max(min_w, math.min(max_w, max_natural))
end

-- ============================================================
-- Build the panel content (paginated)
-- ============================================================

-- Rows the screen can fit, measured against a REAL row (a TextWidget's ink
-- box is taller than its point size, so row_stride underestimates the height
-- and the old formula overshot). One row is reserved for the pager when the
-- panel is paginated.
local function _measureRowH(m)
    -- Build a throwaway row to get its real rendered height.
    local probe = _buildRow("wifi", m, Screen:scaleBySize(200))
    local h = probe:getSize().h
    return h
end

local function VISIBLE_ROWS()
    local m = _metrics()
    local real_row_h  = _measureRowH(m)
    -- Panel max height = 80% of the screen (10% top + 10% bottom margin).
    local max_panel_h = math.floor(Screen:getHeight() * 0.80)
    local chrome      = 2 * (m.panel_border + m.panel_pad)
    return math.max(2, math.floor((max_panel_h - chrome) / real_row_h))
end

local function _buildPanel(page)
    local m     = _metrics()
    local slots = getSlots()
    local total = #slots

    local row_w = _measurePanelWidth(slots, m)
    local vg    = VerticalGroup:new{ align = "left" }

    -- Reserve one row for the pager if we need more than one page.
    local rows_max  = VISIBLE_ROWS()
    local has_pager = total > rows_max
    local per_page  = has_pager and (rows_max - 1) or rows_max
    local pages     = math.max(1, math.ceil(total / per_page))
    page = math.max(1, math.min(page or 1, pages))

    local first = (page - 1) * per_page + 1
    local last  = math.min(first + per_page - 1, total)
    local page_slots = {}
    for i = first, last do page_slots[#page_slots + 1] = slots[i] end
    local shown = #page_slots

    local function pressFeedback(row)
        local f = row._frame
        if not f or not row.dimen then return end

        f.background = Blitbuffer.gray(0.5)
        UIManager:widgetRepaint(row, row.dimen.x, row.dimen.y)
        UIManager:setDirty(nil, "ui", row.dimen)
        UIManager:forceRePaint()
        UIManager:scheduleIn(0.1, function()
            f.background = nil
            if row.dimen and UIManager:isWidgetShown(row) then
                UIManager:widgetRepaint(row, row.dimen.x, row.dimen.y)
                UIManager:setDirty(nil, "ui", row.dimen)
            end
        end)
    end

    if total == 0 then
        local add_row = _buildRow("__add", m, row_w)
        function add_row:onTap()
            pressFeedback(self)
            M.showAddButtonMenu(function() M.refresh() end)
            return true
        end
        function add_row:onHold()
            pressFeedback(self)
            if Utils.getBool("qa_vb_settings_on_hold", true) then
                M.hide()
                settings.showVerticalBarSettings()
            end
            return true
        end
        vg[#vg + 1] = add_row
    else
        for i = 1, shown do
            local id = page_slots[i]
            local row = _buildRow(id, m, row_w)
            local _id = id
            function row:onTap()
                pressFeedback(self)
                local in_place = QA.isInPlace(_id)
                local bar_ref = _overlay
                if not in_place then M.hide() end
                UIManager:scheduleIn(0, function()
                    QA.executeAction(_id, { touch_menu = bar_ref })
                    if in_place and _overlay then M.refresh() end
                end)
                return true
            end
            function row:onHold()
                pressFeedback(self)
                local is_builtin = QA.isBuiltinAction and QA.isBuiltinAction(_id)
                M.hide()
                if is_builtin then
                    settings.showEditActionDialog(_id, function() M.refresh() end, "verticalbar")
                else
                    settings.showCustomQADialog(_id, function() M.refresh() end, "verticalbar")
                end
                return true
            end
            vg[#vg + 1] = row
        end

        -- Pager row: two halves (prev / next), one row.
        if has_pager then
            local half_w  = math.floor(row_w / 2)
            local other_w = row_w - half_w

            local function mkHalf(glyph, enabled, on_tap, w)
                local t = TextWidget:new{
                    text    = glyph,
                    face    = m.label_face,
                    fgcolor = enabled and Blitbuffer.COLOR_BLACK or Blitbuffer.gray(0.6),
                }
                local cell_frame = FrameContainer:new{
                    width      = w,
                    height     = m.row_h,
                    bordersize = 0,
                    padding    = 0,
                    background = nil,
                    CenterContainer:new{
                        dimen = Geom:new{ w = w, h = m.row_h },
                        t,
                    },
                }
                local c = InputContainer:new{
                    dimen = cell_frame:getSize(),
                    cell_frame,
                }
                c._frame = cell_frame
                if Device:isTouchDevice() then
                    c.ges_events = {
                        Tap  = { GestureRange:new{ ges = "tap",  range = c.dimen } },
                        Hold = { GestureRange:new{ ges = "hold", range = c.dimen } },
                    }
                end
                function c:onTap()
                    pressFeedback(self)
                    if enabled then on_tap() end
                    return true
                end
                function c:onHold()
                    pressFeedback(self)
                    if Utils.getBool("qa_vb_settings_on_hold", true) then
                        M.hide()
                        settings.showVerticalBarSettings()
                    end
                    return true
                end
                return c
            end

            local prev_cell = mkHalf(
                QA.nerdIconChar("nerd:F077") or "▲",   -- fa-chevron-up
                page > 1,
                function()
                    _current_page = page - 1
                    M.refresh()
                end,
                half_w)

            local next_cell = mkHalf(
                QA.nerdIconChar("nerd:F078") or "▼",   -- fa-chevron-down
                page < pages,
                function()
                    _current_page = page + 1
                    M.refresh()
                end,
                other_w)

            vg[#vg + 1] = HorizontalGroup:new{ align = "center", prev_cell, next_cell }
        end
    end

    local frame = PanelFrame:new{
        bordersize = m.panel_border,
        padding    = m.panel_pad,
        radius     = m.panel_radius,
        shadow     = m.panel_shadow,
        bg         = Utils.getString("qa_vb_bg", "white"),
        vg,
    }
    return frame, m, row_w
end

-- ============================================================
-- MovablePanel
-- ============================================================

local MovablePanel = MovableContainer:extend{}

function MovablePanel:_moveBy(dx, dy, restrict_to_screen)
    MovableContainer._moveBy(self, dx, dy, restrict_to_screen)
    if self.on_move then self.on_move(self) end
end

-- ============================================================
-- VerticalBar -- full-screen overlay that hosts the movable panel
-- ============================================================

local VerticalBar = InputContainer:extend{
    _dragged = false,
}

-- Close the bar when an action that needs its host gone calls
-- ctx.touch_menu:onClose(). The panel and bottom bar pass a real TouchMenu
-- here; our equivalent is the bar widget itself.
function VerticalBar:onClose()
    M.hide()
end

function VerticalBar:updateItems()
    -- no-op
end

function VerticalBar:closeMenu()
    M.hide()
end

function VerticalBar:init()
    self.dimen = Geom:new{ x = 0, y = 0,
        w = Screen:getWidth(), h = Screen:getHeight() }

    local frame, m, row_w = _buildPanel(_current_page)
    local sz = frame:getSize()

    -- Default position: side edge, vertically centred. Never restored from
    -- disk -- the panel always reopens at the configured side.
    local side = Utils.getString("qa_vb_side", "left")
    local edge_margin = Screen:scaleBySize(6)
    local default_x = (side == "left")
        and edge_margin
        or  (Screen:getWidth() - sz.w - edge_margin)
    local default_y = math.max(0, math.floor((Screen:getHeight() - sz.h) / 2))

    self._panel_frame = frame
    self._panel_size  = sz

    -- MovableContainer treats its paintTo(x, y) args as the ORIGIN, and
    -- paints at (x + _moved_offset_x, y + _moved_offset_y). VerticalBar:paintTo
    -- passes (0, 0), so the panel's position is decided entirely by
    -- _moved_offset, which we set to the side-configured default here.
    self.movable = MovablePanel:new{
        frame,
        dimen = Geom:new{ x = 0, y = 0, w = sz.w, h = sz.h },
        -- Drag with SWIPE only. Hold and tap are left free for the rows:
        -- hold = edit dialog, tap = run the action. MovableContainer's
        -- own swipe handler does the repositioning.
        ignore_events = {
            "touch",         -- don't pre-arm pan from a plain touch
            "hold",          -- hold is the row's long-press
            "hold_pan",      -- no pan-drag
            "hold_release",  -- no pan-drag end
            "pan",           -- no pan-drag
            "pan_release",   -- no pan-drag end
            -- "swipe" is deliberately left ON: that's the drag gesture.
        },
        on_move = function(movable)
            local moved_x = (movable._orig_x or 0) + (movable._moved_offset_x or 0)
            local moved_y = (movable._orig_y or 0) + (movable._moved_offset_y or 0)
            local cx, cy = self:clampPosition(moved_x, moved_y, sz)
            if cx ~= moved_x or cy ~= moved_y then
                movable:setMovedOffset(Geom:new{
                    x = cx - (movable._orig_x or 0),
                    y = cy - (movable._orig_y or 0),
                })
            end
            if self._bg_snapshot then
                self._bg_snapshot:free()
                self._bg_snapshot = nil
            end
            self._dragged = true
        end,
    }
    self.movable:setMovedOffset(Geom:new{ x = default_x, y = default_y })
    self[1] = self.movable

    self._dirty_region = Geom:new{
        x = default_x,
        y = default_y,
        w = sz.w + m.panel_shadow,
        h = sz.h + m.panel_shadow,
    }

    if Device:isTouchDevice() then
        self.ges_events = {
            TapOutside = { GestureRange:new{ ges = "tap", range = self.dimen } },
        }
    end
end

function VerticalBar:_anchoredSide()
    local d = self:getVisibleDimen()
    return (d.x + d.w / 2 < Screen:getWidth() / 2) and "left" or "right"
end

-- ============================================================
-- Open / close animations -- direct ports of
-- bookshelf_start_menu.lua's StartMenu.open / _close wipe.
-- ============================================================

function VerticalBar:showWithAnimation()
    local _sr = self._dirty_region
    local anim_steps = _resolveSteps()
    if anim_steps and _sr and Screen.refreshUI then
        local shown = pcall(function()
            local rx, ry, rw, rh = _sr.x, _sr.y, _sr.w, _sr.h
            local old_bb = Screen.bb:copy()
            local new_bb = old_bb:copy()
            self:paintTo(new_bb, 0, 0)
            local from_top = false
            local STEPS, prev_dh = anim_steps, 0
            for i = 1, STEPS do
                local dh = math.floor(rh * i / STEPS)
                local strip_h = dh - prev_dh
                if strip_h > 0 then
                    local strip_y = from_top and (ry + prev_dh) or (ry + rh - dh)
                    Screen.bb:blitFrom(new_bb, rx, strip_y, rx, strip_y, rw, strip_h)
                    if i < STEPS then
                        Screen:refreshUI(rx, strip_y, rw, strip_h)
                        UIManager:yieldToEPDC(20000)
                    end
                end
                if i == STEPS then
                    Screen:refreshUI(rx, ry, rw, rh)
                end
                prev_dh = dh
            end
            new_bb:free()
            self._bg_snapshot = old_bb
        end)
        if shown then
            UIManager:show(self)
            if UIManager._dirty then UIManager._dirty[self] = nil end
            return
        end
    end
    UIManager:show(self, "ui")
end

function VerticalBar:hideWithAnimation()
    local bg = self._bg_snapshot
    local r  = self._dirty_region
    local anim_steps = _resolveSteps()
    local wiped = false
    if bg and r and anim_steps and Screen.refreshUI then
        wiped = pcall(function()
            local rx, ry, rw, rh = r.x, r.y, r.w, r.h
            local from_top = false
            local STEPS, prev_dh = anim_steps, 0
            for i = 1, STEPS do
                local dh = math.floor(rh * i / STEPS)
                local strip_h = dh - prev_dh
                if strip_h > 0 then
                    local strip_y = from_top and (ry + rh - dh) or (ry + prev_dh)
                    Screen.bb:blitFrom(bg, rx, strip_y, rx, strip_y, rw, strip_h)
                    if i < STEPS then
                        Screen:refreshUI(rx, strip_y, rw, strip_h)
                        UIManager:yieldToEPDC(20000)
                    end
                end
                if i == STEPS then
                    Screen:refreshUI(rx, ry, rw, rh)
                end
                prev_dh = dh
            end
        end)
    end
    if bg then bg:free(); self._bg_snapshot = nil end
    if wiped then
        self.invisible = true
        UIManager:close(self)
    else
        UIManager:close(self, "ui")
    end
end

function VerticalBar:clampPosition(x, y, sz)
    sz = sz or self._panel_size
    if not sz then return x, y end
    local max_x = math.max(0, Screen:getWidth()  - sz.w)
    local max_y = math.max(0, Screen:getHeight() - sz.h)
    if x < 0 then x = 0 elseif x > max_x then x = max_x end
    if y < 0 then y = 0 elseif y > max_y then y = max_y end
    return x, y
end

function VerticalBar:getVisibleDimen()
    if not self.movable then return self.dimen end
    local d = self.movable.dimen
    d.x = (self.movable._orig_x or self.dimen.x)
        + (self.movable._moved_offset_x or 0)
    d.y = (self.movable._orig_y or self.dimen.y)
        + (self.movable._moved_offset_y or 0)
    return d
end

function VerticalBar:paintTo(bb, x, y)
    self.movable:paintTo(bb, self.dimen.x, self.dimen.y)
end

function VerticalBar:onCloseWidget()
    if self._bg_snapshot then
        self._bg_snapshot:free()
        self._bg_snapshot = nil
    end
end

function VerticalBar:onTapOutside(_, ges)
    local d = self:getVisibleDimen()
    if d and ges.pos:intersectWith(d) then
        return false
    end
    M.hide()
    return true
end

-- ============================================================
-- Show / hide / refresh
-- ============================================================

function M.isEnabled()
    return Utils.getBool("qa_vb_enabled", false)
end

function M.show(skip_anim)
    if not M.isEnabled() then return end
    if _overlay then return end
    -- A fresh open starts on page 1; an internal refresh (skip_anim = true)
    -- keeps the current page so pagination doesn't reset underfoot.
    if not skip_anim then
        _current_page = 1
    end
    _overlay = VerticalBar:new{}
    if skip_anim then
        UIManager:show(_overlay, "ui")
    else
        _overlay:showWithAnimation()
    end
end

function M.hide(skip_anim)
    if not _overlay then return end
    local o = _overlay
    _overlay = nil
    if skip_anim or o._dragged or not o._bg_snapshot then
        UIManager:close(o, "ui")
    else
        o:hideWithAnimation()
    end
end

function M.toggle()
    if _overlay then M.hide() else M.show() end
end

function M.refresh()
    if _overlay then
        M.hide(true)
        M.show(true)
    end
end

-- ============================================================
-- Add-button menu -- no storage cap, pagination handles overflow.
-- ============================================================

local _add_dialog = nil

function M.showAddButtonMenu(on_back, filtered_actions)
    local slots = Utils.getTable("qa_vb_slots")
    local slot_set = {}
    for __, id in ipairs(slots) do slot_set[id] = true end

    local available = filtered_actions or QA.getAllAvailableActions()
    table.sort(available, function(a, b)
        local ac, bc = slot_set[a.id] or false, slot_set[b.id] or false
        if ac ~= bc then return ac end
        local ap, bp = QA.getTypePriority(a.id) or 999, QA.getTypePriority(b.id) or 999
        if ap ~= bp then return ap < bp end
        return a.label:lower() < b.label:lower()
    end)

    local buttons = {}
    table.insert(buttons, { Utils.createSearchButton(
        function() M.showAddButtonMenu(on_back) end,
        function(keyword)
            if _add_dialog then UIManager:close(_add_dialog); _add_dialog = nil end
            M.showAddButtonMenu(on_back,
                Utils.filterActionsByKeyword(QA.getAllAvailableActions(), keyword))
        end,
        function() if _add_dialog then UIManager:close(_add_dialog); _add_dialog = nil end end
    ) })
    table.insert(buttons, {})

    if on_back then
        table.insert(buttons, {{ text = "◂◂ " .. _("Back to Root"),
            callback = function()
                if _add_dialog then UIManager:close(_add_dialog); _add_dialog = nil end
                settings.showSettings()
            end }})
        table.insert(buttons, {{ text = "◂ " .. _("Back"),
            callback = function()
                if _add_dialog then UIManager:close(_add_dialog); _add_dialog = nil end
                on_back()
            end }})
        table.insert(buttons, {})
    else
        table.insert(buttons, {{ text = "⚙️ " .. _("QA Settings"),
            callback = function()
                if _add_dialog then UIManager:close(_add_dialog); _add_dialog = nil end
                settings.showSettings()
            end }})
        table.insert(buttons, {})
    end

    table.insert(buttons, {{
        text = _("Show Labels"),
        checked_func = function() return Utils.getBool("qa_vb_labels", true) end,
        callback = function(tm)
            Utils.set("qa_vb_labels", not Utils.getBool("qa_vb_labels", true))
            if tm then tm:updateItems() end
            M.refresh()
            if _add_dialog then UIManager:close(_add_dialog); _add_dialog = nil end
            M.showAddButtonMenu(on_back)
        end,
    }})

    -- Select All / Deselect All -- no cap, storage is unbounded.
    table.insert(buttons, {
        {
            text_func = function()
                if #slots > 0 then
                    return "☑ " .. _("Deselect All")
                else
                    return "☐ " .. _("Select All")
                end
            end,
            callback = function()
                local new_slots = {}
                if #slots > 0 then
                    new_slots = {}
                else
                    for __, action in ipairs(available) do
                        table.insert(new_slots, action.id)
                    end
                end
                Utils.set("qa_vb_slots", new_slots)
                M.refresh()
                if _add_dialog then
                    UIManager:close(_add_dialog)
                    _add_dialog = nil
                end
                M.showAddButtonMenu(on_back)
            end,
        }
    })
    table.insert(buttons, {})

    table.insert(buttons, {{
        text = _("Apply preset (QA vb)"),
        callback = function()
            Utils.applyDefault({"qa_common", "qa_vb"})
            M.refresh()
            if _add_dialog then UIManager:close(_add_dialog); _add_dialog = nil end
            M.showAddButtonMenu(on_back)
        end,
    }})
    table.insert(buttons, {})

    for __, action in ipairs(available) do
        local is_checked = slot_set[action.id] or false
        local symbol = QA.getActionSymbol(action.id)
        local view_tag = " [" .. (action.view or "common") .. "]"
        table.insert(buttons, {{
            text = (is_checked and "✓ " or "  ") .. symbol .. action.label .. view_tag,
            callback = function()
                local new_slots = {}
                if is_checked then
                    for __, id in ipairs(slots) do
                        if id ~= action.id then new_slots[#new_slots + 1] = id end
                    end
                else
                    for __, id in ipairs(slots) do new_slots[#new_slots + 1] = id end
                    new_slots[#new_slots + 1] = action.id
                end
                Utils.set("qa_vb_slots", new_slots)
                M.refresh()
                if _add_dialog then UIManager:close(_add_dialog); _add_dialog = nil end
                M.showAddButtonMenu(on_back)
            end,
        }})
    end

    table.insert(buttons, {})
    table.insert(buttons, {{ text = _("Close"),
        callback = function()
            if _add_dialog then UIManager:close(_add_dialog); _add_dialog = nil end
        end }})

    local dialog = ButtonDialog:new{
        title = _("Add Button"),
        title_align = "center",
        buttons = buttons,
        width = math.floor(Screen:getWidth() * 0.7),
        max_height = math.floor(Screen:getHeight() * 0.7),
        rows_per_page = 10,
    }
    if _add_dialog then UIManager:close(_add_dialog) end
    _add_dialog = dialog
    UIManager:show(dialog)
end

-- ============================================================
-- Init
-- ============================================================

function M.init()
    Utils.registerRefreshHandler("qa_vb", M.refresh)
end

return M
