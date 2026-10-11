--[[--
Touch-friendly toggle card (≥ 48×48px) with solid e-ink borders.
@module modern_menu.widgets.toggle_card
--]]

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local Device = require("device")
local Screen = Device.screen
local _ = require("gettext")

local ToggleCard = InputContainer:extend{
    title = "",
    subtitle = nil,
    checked = false,
    enabled = true,
    width = nil,
    height = nil,
    callback = nil,
    show_parent = nil,
    padding = nil,
    bordersize = nil,
}

function ToggleCard:init()
    self.padding = self.padding or Size.padding.large
    self.bordersize = self.bordersize or Size.border.thin
    local min_h = Screen:scaleBySize(48)

    self.title_widget = TextWidget:new{
        text = self.title,
        face = Font:getFace("smallinfofont", 20),
        max_width = (self.width or Screen:getWidth()) - Screen:scaleBySize(100),
    }

    local left_column = VerticalGroup:new{
        align = "left",
        self.title_widget,
    }

    if self.subtitle and self.subtitle ~= "" then
        table.insert(left_column, TextWidget:new{
            text = self.subtitle,
            face = Font:getFace("xx_smallinfofont"),
            fgcolor = Blitbuffer.COLOR_DARK_GRAY,
            max_width = (self.width or Screen:getWidth()) - Screen:scaleBySize(100),
        })
    end

    self.state_widget = TextWidget:new{
        text = self.checked and _("ON") or _("OFF"),
        face = Font:getFace("smallinfofont", 18),
        bold = true,
        fgcolor = self.checked and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK,
    }

    self.state_box = FrameContainer:new{
        bordersize = Size.border.thin,
        padding = Size.padding.default,
        margin = 0,
        background = self.checked and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE,
        CenterContainer:new{
            dimen = Geom:new{
                w = Screen:scaleBySize(56),
                h = Screen:scaleBySize(32),
            },
            self.state_widget,
        },
    }

    self.frame = FrameContainer:new{
        bordersize = self.bordersize,
        padding = self.padding,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        width = self.width or (Screen:getWidth() - Screen:scaleBySize(32)),
        HorizontalGroup:new{
            align = "center",
            left_column,
            HorizontalSpan:new{ width = Size.span.horizontal_default },
            self.state_box,
        },
    }

    self[1] = self.frame
    self.dimen = self.frame:getSize()
    if self.dimen.h < min_h then
        self.dimen.h = min_h
    end

    local screen_range = Geom:new{
        x = 0, y = 0,
        w = Screen:getWidth(),
        h = Screen:getHeight(),
    }
    self.ges_events = {
        TapToggle = {
            GestureRange:new{
                ges = "tap",
                range = screen_range,
            },
        },
    }
end

function ToggleCard:_paintState()
    self.state_widget:setText(self.checked and _("ON") or _("OFF"))
    self.state_widget.fgcolor = self.checked and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK
    self.state_box.background = self.checked and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE
end

function ToggleCard:setChecked(checked)
    checked = checked and true or false
    if self.checked == checked then
        return
    end
    self.checked = checked
    self:_paintState()
    UIManager:setDirty(self.show_parent or self, "ui", self.dimen)
end

function ToggleCard:onTapToggle(_, ges)
    if not self.enabled or not ges or not ges.pos or not self.dimen then
        return false
    end
    if not self.dimen:contains(ges.pos) then
        return false
    end
    self:setChecked(not self.checked)
    if self.callback then
        self.callback(self.checked)
    end
    return true
end

return ToggleCard
