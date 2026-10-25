--[[--
Tab bar in the Kobold library style: icon and cfont label, bold when
selected. A light rule under the row is drawn by the menu shell.
@module modern_menu.ui.tab_bar
--]]

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Device = require("device")
local Screen = Device.screen

local Settings = require("settings")

local TabBar = InputContainer:extend{
    tabs = nil,
    selected = 1,
    width = nil, -- full outer width (screen / panel)
    height = nil,
    side_margin = nil, -- inset to match grey rule / content box
    on_change = nil,
    show_parent = nil,
    face_size = nil,
    icon_size = nil,
    icons_only = nil,
}

local function free_widget(widget)
    if widget and widget.free then
        widget:free()
    end
end

function TabBar:_applyLayoutMetrics()
    local gap = self.icons_only and 0 or Screen:scaleBySize(3)
    local label_h = 0
    if not self.icons_only then
        -- Measure the real face, including descenders, so the row is tall
        -- enough and the label does not run into the rule below.
        local size_key = tostring(self.face_size)
        if self._label_h_key ~= size_key then
            local probe = TextWidget:new{
                text = "Ag",
                face = Settings.face(self.face_size or Settings.getTabFontSize(), "cfont"),
                bold = true,
            }
            self._label_h = probe:getSize().h
            self._label_h_key = size_key
            free_widget(probe)
        end
        label_h = self._label_h or 0
    end
    self.height = self.icon_size + gap + label_h + Screen:scaleBySize(2)
    self.inner_width = math.max(0, self.width - 2 * self.side_margin)
    if self.dimen then
        self.dimen.w = self.width
        self.dimen.h = self.height
    end
end

--- Re-read Settings and rebuild so SpinWidget changes apply immediately.
function TabBar:reloadFromSettings()
    self.icons_only = Settings.getTabIconsOnly()
    self.face_size = Settings.getTabFontSize()
    self.icon_size = Settings.getTabIconPx()
    self._label_widths = nil
    self:_applyLayoutMetrics()
    self:_rebuildTabs()
end

function TabBar:init()
    self.tabs = self.tabs or {}
    self.width = self.width or Screen:getWidth()
    self.side_margin = self.side_margin or 0
    self.icons_only = self.icons_only
    if self.icons_only == nil then
        self.icons_only = Settings.getTabIconsOnly()
    end
    self.face_size = self.face_size or Settings.getTabFontSize()
    self.icon_size = self.icon_size or Settings.getTabIconPx()

    self:_applyLayoutMetrics()

    self.row = HorizontalGroup:new{ align = "center" }
    self[1] = HorizontalGroup:new{
        align = "center",
        HorizontalSpan:new{ width = self.side_margin },
        self.row,
        HorizontalSpan:new{ width = self.side_margin },
    }
    self.dimen = Geom:new{ w = self.width, h = self.height }
    self:_rebuildTabs()

    self.ges_events = {
        TapSelect = {
            GestureRange:new{
                ges = "tap",
                range = self.dimen,
            },
        },
        HoldSelect = {
            GestureRange:new{
                ges = "hold",
                range = self.dimen,
            },
        },
    }
end

function TabBar:_labelWidth(text, max_width)
    local key = tostring(text) .. "\0" .. tostring(self.face_size) .. "\0" .. tostring(max_width)
    self._label_widths = self._label_widths or {}
    local cached = self._label_widths[key]
    if cached then
        return cached
    end
    local face = Settings.face(self.face_size, "cfont")
    -- Bold is wider. Measure that so selecting a tab does not shift the row.
    local probe = TextWidget:new{
        text = text,
        face = face,
        bold = true,
        max_width = max_width,
        truncate_with_ellipsis = true,
    }
    local width = probe:getSize().w
    free_widget(probe)
    self._label_widths[key] = width
    return width
end

function TabBar:_rebuildTabs()
    if self.row.clear then
        self.row:clear()
    else
        for i = #self.row, 1, -1 do self.row[i] = nil end
    end
    self._slots = {}

    local count = math.max(#self.tabs, 1)
    local label_max = math.max(Screen:scaleBySize(12), math.floor(self.inner_width / count) - Screen:scaleBySize(8))
    local icon_px = math.min(self.icon_size, math.max(Screen:scaleBySize(16), math.floor(self.inner_width / count) - Screen:scaleBySize(8)))

    local blocks = {}
    self._blocks = blocks
    for i, tab in ipairs(self.tabs) do
        local selected = (i == self.selected)
        local parts = VerticalGroup:new{ align = "center" }
        local showed_icon = false
        if tab.icon and tab.icon ~= "" then
            local ok, icon = pcall(function()
                return IconWidget:new{
                    icon = tab.icon,
                    width = icon_px,
                    height = icon_px,
                    alpha = true,
                    dim = false,
                }
            end)
            if ok and icon then
                showed_icon = true
                table.insert(parts, icon)
                if not self.icons_only then
                    table.insert(parts, VerticalSpan:new{ width = Screen:scaleBySize(2) })
                end
            end
        end

        local block_w = showed_icon and icon_px or 0
        -- Icons-only still needs a label when the icon name is unknown
        -- (Quick Menu's "home" / "exit" glyphs, for example).
        if not self.icons_only or not showed_icon then
            local text_w = self:_labelWidth(tab.title, label_max)
            block_w = math.max(block_w, text_w)
            local label = TextWidget:new{
                text = tab.title,
                face = Settings.face(self.face_size, "cfont"),
                bold = selected,
                fgcolor = Blitbuffer.COLOR_BLACK,
                max_width = label_max,
                truncate_with_ellipsis = true,
            }
            -- The icon sits in the middle of this width, bold or not.
            local holder = CenterContainer:new{
                dimen = Geom:new{ w = text_w, h = label:getSize().h },
                label,
            }
            table.insert(parts, holder)
            blocks[i] = {
                widget = parts,
                w = math.max(block_w, 1),
                label_holder = holder,
                title = tab.title,
                label_max = label_max,
            }
        end

        if not blocks[i] then
            blocks[i] = { widget = parts, w = math.max(block_w, 1) }
        end
    end

    -- First word starts on the clock's margin, last word ends on the close
    -- mark. Icon centers are spaced evenly between those two.
    local n = #blocks
    local centers = {}
    if n == 1 then
        centers[1] = blocks[1].w / 2
    else
        local first = blocks[1].w / 2
        local last = self.inner_width - blocks[n].w / 2
        if last < first then
            last = first
        end
        for i = 1, n do
            centers[i] = first + (i - 1) * (last - first) / (n - 1)
        end
    end

    local cursor = 0
    for i, block in ipairs(blocks) do
        local left = math.floor(centers[i] - block.w / 2 + 0.5)
        if i == 1 then
            left = 0
        elseif i == n then
            left = math.max(cursor, self.inner_width - block.w)
        elseif left < cursor then
            left = cursor
        end
        local gap = left - cursor
        if gap > 0 then
            table.insert(self.row, HorizontalSpan:new{ width = gap })
        end
        table.insert(self.row, block.widget)
        self._slots[i] = { x = left, w = block.w }
        cursor = left + block.w
    end
    if self.row.resetLayout then
        self.row:resetLayout()
    end
    if self[1] and self[1].resetLayout then
        self[1]:resetLayout()
    end
end

function TabBar:_restyleLabel(index, selected)
    local block = self._blocks and self._blocks[index]
    if not block or not block.label_holder then
        return
    end
    local label = TextWidget:new{
        text = block.title or "",
        face = Settings.face(self.face_size, "cfont"),
        bold = selected,
        fgcolor = Blitbuffer.COLOR_BLACK,
        max_width = block.label_max,
        truncate_with_ellipsis = true,
    }
    local old = block.label_holder[1]
    block.label_holder[1] = label
    free_widget(old)
    if block.label_holder.resetLayout then
        block.label_holder:resetLayout()
    end
end

function TabBar:setSelected(index, skip_callback)
    if index < 1 or index > #self.tabs or index == self.selected then
        return
    end
    local previous = self.selected
    self.selected = index
    -- Bold is the only selected state. Rebuilding every icon here doubled
    -- the work of a tab tap, because the shell refresh used to rebuild again.
    self:_restyleLabel(previous, false)
    self:_restyleLabel(index, true)
    if not skip_callback and self.on_change then
        self.on_change(self.tabs[index].id, index)
    end
end

function TabBar:onTapSelect(_, ges)
    local index = self:_indexAt(ges)
    if not index then
        return false
    end
    -- Tapping the already highlighted tab still has to run. The exit tab
    -- stays highlighted when its action does not switch pages.
    if index == self.selected then
        if self.on_change then
            self.on_change(self.tabs[index].id, index)
        end
        return true
    end
    self:setSelected(index)
    return true
end

function TabBar:onHoldSelect(_, ges)
    local index = self:_indexAt(ges)
    if not index or not self.on_hold then
        return false
    end
    return self.on_hold(self.tabs[index].id, index) == true
end

function TabBar:_indexAt(ges)
    if not ges or not ges.pos or not self.dimen then
        return nil
    end
    local slots = self._slots
    if not slots or #slots == 0 then
        return nil
    end
    local rel_x = ges.pos.x - self.dimen.x - self.side_margin
    for i, slot in ipairs(slots) do
        local left = 0
        local right = self.inner_width
        local mid = slot.x + slot.w / 2
        if i > 1 then
            local prev = slots[i - 1]
            left = (prev.x + prev.w / 2 + mid) / 2
        end
        if i < #slots then
            local nxt = slots[i + 1]
            right = (mid + nxt.x + nxt.w / 2) / 2
        end
        if rel_x >= left and rel_x < right then
            return i
        end
    end
    return nil
end

return TabBar
