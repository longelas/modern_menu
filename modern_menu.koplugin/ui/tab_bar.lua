--[[--
Tab bar with stock KOReader appbar icons + short labels.
Equal columns inside an inset box matching the grey rule / content margins.
@module modern_menu.ui.tab_bar
--]]

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
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

function TabBar:_applyLayoutMetrics()
    local pad = Screen:scaleBySize(12)
    local gap = self.icons_only and 0 or Screen:scaleBySize(2)
    local label_h = self.icons_only and 0 or (self.face_size + Screen:scaleBySize(4))
    self.height = math.max(Screen:scaleBySize(48), self.icon_size + gap + label_h + pad)
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
    }
end

function TabBar:_rebuildTabs()
    if self.row.clear then
        self.row:clear()
    else
        for i = #self.row, 1, -1 do self.row[i] = nil end
    end

    local count = math.max(#self.tabs, 1)
    -- Even columns fill the inset box — comfortable gaps without edge overflow.
    local tab_w = math.floor(self.inner_width / count)
    local label_max = math.max(Screen:scaleBySize(12), tab_w - Screen:scaleBySize(8))
    local icon_px = math.min(self.icon_size, math.max(Screen:scaleBySize(16), tab_w - Screen:scaleBySize(8)))
    local unselected_fg = Settings.getMutedFg()

    for i, tab in ipairs(self.tabs) do
        local selected = (i == self.selected)
        local parts = VerticalGroup:new{ align = "center" }

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
                table.insert(parts, icon)
                if not self.icons_only then
                    table.insert(parts, VerticalSpan:new{ width = Screen:scaleBySize(2) })
                end
            end
        end

        if not self.icons_only then
            table.insert(parts, TextWidget:new{
                text = tab.title,
                face = Font:getFace("xx_smallinfofont", self.face_size),
                bold = selected,
                fgcolor = selected and Blitbuffer.COLOR_BLACK or unselected_fg,
                max_width = label_max,
                truncate_with_ellipsis = true,
            })
        end

        table.insert(self.row, CenterContainer:new{
            dimen = Geom:new{
                w = tab_w,
                h = self.height,
            },
            parts,
        })
    end
end

function TabBar:setSelected(index, skip_callback)
    if index < 1 or index > #self.tabs or index == self.selected then
        return
    end
    self.selected = index
    self:_rebuildTabs()
    UIManager:setDirty(self.show_parent or self, "ui")
    if not skip_callback and self.on_change then
        self.on_change(self.tabs[index].id, index)
    end
end

function TabBar:onTapSelect(_, ges)
    if not ges or not ges.pos or not self.dimen then
        return false
    end
    local count = math.max(#self.tabs, 1)
    local tab_w = math.floor(self.inner_width / count)
    local rel_x = ges.pos.x - self.dimen.x - self.side_margin
    if rel_x < 0 or rel_x >= self.inner_width then
        return false
    end
    local index = math.floor(rel_x / tab_w) + 1
    if index < 1 then index = 1 end
    if index > #self.tabs then index = #self.tabs end
    self:setSelected(index)
    return true
end

return TabBar
