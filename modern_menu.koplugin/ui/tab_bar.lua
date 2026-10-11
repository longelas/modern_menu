--[[--
Tab bar with stock KOReader appbar icons + short labels, active underline.
@module modern_menu.ui.tab_bar
--]]

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UnderlineContainer = require("ui/widget/container/underlinecontainer")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Device = require("device")
local Screen = Device.screen

local TabBar = InputContainer:extend{
    tabs = nil,
    selected = 1,
    width = nil,
    height = nil,
    on_change = nil,
    show_parent = nil,
}

function TabBar:init()
    self.tabs = self.tabs or {}
    self.width = self.width or Screen:getWidth()
    self.height = self.height or Screen:scaleBySize(56)
    self.face_size = (#self.tabs > 5) and 11 or 12
    self.icon_size = Screen:scaleBySize((#self.tabs > 5) and 22 or 24)

    self.row = HorizontalGroup:new{ align = "center" }
    self[1] = self.row
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
    local tab_w = math.floor(self.width / count)

    for i, tab in ipairs(self.tabs) do
        local selected = (i == self.selected)
        local parts = VerticalGroup:new{ align = "center" }

        if tab.icon and tab.icon ~= "" then
            local ok, icon = pcall(function()
                return IconWidget:new{
                    icon = tab.icon,
                    width = self.icon_size,
                    height = self.icon_size,
                    alpha = true,
                    dim = not selected,
                }
            end)
            if ok and icon then
                table.insert(parts, icon)
                table.insert(parts, VerticalSpan:new{ width = Screen:scaleBySize(2) })
            end
        end

        table.insert(parts, TextWidget:new{
            text = tab.title,
            face = Font:getFace("xx_smallinfofont", self.face_size),
            bold = selected,
            fgcolor = selected and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_DARK_GRAY,
            max_width = tab_w - Screen:scaleBySize(4),
        })

        -- Underline only the icon+label (not the full tab cell) so edge tabs
        -- don't draw a black bar to the screen edge.
        local labeled = parts
        if selected then
            labeled = UnderlineContainer:new{
                linesize = Size.line.thick,
                padding = Size.padding.tiny,
                color = Blitbuffer.COLOR_BLACK,
                parts,
            }
        end
        table.insert(self.row, CenterContainer:new{
            dimen = Geom:new{
                w = tab_w,
                h = self.height,
            },
            labeled,
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
    local tab_w = math.floor(self.width / count)
    local rel_x = ges.pos.x - self.dimen.x
    local index = math.floor(rel_x / tab_w) + 1
    if index < 1 then index = 1 end
    if index > #self.tabs then index = #self.tabs end
    self:setSelected(index)
    return true
end

return TabBar
