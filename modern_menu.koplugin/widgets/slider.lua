--[[--
E-ink optimized slider: discrete paint updates, no continuous animation.
@module modern_menu.widgets.slider
--]]

local Blitbuffer = require("ffi/blitbuffer")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local InputContainer = require("ui/widget/container/inputcontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Device = require("device")
local Screen = Device.screen
local _ = require("gettext")

local Slider = InputContainer:extend{
    title = "",
    value = 0,
    value_min = 0,
    value_max = 100,
    value_step = 1,
    width = nil,
    callback = nil,
    -- Only notify on release / tap end to cut refresh noise
    callback_on_release = true,
}

function Slider:init()
    self.width = self.width or (Screen:getWidth() - Screen:scaleBySize(32))
    self.track_height = Screen:scaleBySize(8)
    self.thumb_size = Screen:scaleBySize(28)
    self.bar_height = math.max(Screen:scaleBySize(48), self.thumb_size + Screen:scaleBySize(8))

    self.value_widget = TextWidget:new{
        text = tostring(self.value),
        face = require("settings").face(18),
        bold = true,
    }

    self.title_widget = TextWidget:new{
        text = self.title,
        face = require("settings").face(18),
        max_width = self.width - Screen:scaleBySize(64),
    }

    self.header = HorizontalGroup:new{
        self.title_widget,
        TextWidget:new{
            text = "  ",
            face = require("settings").face(18),
        },
        self.value_widget,
    }

    -- Interactive track region (painted in paintTo)
    self.track_dimen = Geom:new{
        x = 0,
        y = 0,
        w = self.width,
        h = self.bar_height,
    }

    self.frame = FrameContainer:new{
        bordersize = Size.border.thin,
        padding = Size.padding.large,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        width = self.width,
        VerticalGroup:new{
            align = "left",
            self.header,
            VerticalSpan:new{ width = Size.span.vertical_default },
            -- Spacer reserving hit area for custom paint
            VerticalSpan:new{ width = self.bar_height },
        },
    }

    self[1] = self.frame
    self.dimen = self.frame:getSize()

    self.ges_events = {
        TapSelect = {
            GestureRange:new{
                ges = "tap",
                range = self.dimen,
            },
        },
        HoldPan = {
            GestureRange:new{
                ges = "hold_pan",
                range = self.dimen,
            },
        },
        HoldRelease = {
            GestureRange:new{
                ges = "hold_release",
                range = self.dimen,
            },
        },
        Pan = {
            GestureRange:new{
                ges = "pan",
                range = self.dimen,
            },
        },
        PanRelease = {
            GestureRange:new{
                ges = "pan_release",
                range = self.dimen,
            },
        },
    }
end

function Slider:_ratioFromX(x)
    local pad = Size.padding.large
    local track_w = self.dimen.w - 2 * pad - self.thumb_size
    if track_w <= 0 then
        return 0
    end
    local local_x = x - self.dimen.x - pad - (self.thumb_size / 2)
    local ratio = local_x / track_w
    if ratio < 0 then ratio = 0 end
    if ratio > 1 then ratio = 1 end
    return ratio
end

function Slider:_valueFromRatio(ratio)
    local span = self.value_max - self.value_min
    local raw = self.value_min + ratio * span
    local stepped = math.floor((raw - self.value_min) / self.value_step + 0.5) * self.value_step + self.value_min
    if stepped < self.value_min then stepped = self.value_min end
    if stepped > self.value_max then stepped = self.value_max end
    return stepped
end

function Slider:setValue(value, from_user)
    if value < self.value_min then value = self.value_min end
    if value > self.value_max then value = self.value_max end
    if value == self.value then
        return
    end
    self.value = value
    self.value_widget:setText(tostring(self.value))
    UIManager:setDirty(self.show_parent or self, "ui", self.dimen)
    if from_user and self.callback and not self.callback_on_release then
        self.callback(self.value)
    end
end

function Slider:_applyFromGes(ges, is_release)
    if not ges or not ges.pos then
        return
    end
    local ratio = self:_ratioFromX(ges.pos.x)
    self:setValue(self:_valueFromRatio(ratio), true)
    if is_release and self.callback and self.callback_on_release then
        self.callback(self.value)
    end
end

function Slider:onTapSelect(_, ges)
    self:_applyFromGes(ges, true)
    return true
end

function Slider:onHoldPan(_, ges)
    self:_applyFromGes(ges, false)
    return true
end

function Slider:onPan(_, ges)
    self:_applyFromGes(ges, false)
    return true
end

function Slider:onHoldRelease(_, ges)
    self:_applyFromGes(ges, true)
    return true
end

function Slider:onPanRelease(_, ges)
    self:_applyFromGes(ges, true)
    return true
end

function Slider:paintTo(bb, x, y)
    InputContainer.paintTo(self, bb, x, y)

    local pad = Size.padding.large
    local track_y = y + pad + self.header:getSize().h + Size.span.vertical_default + math.floor(self.bar_height / 2)
    local track_x = x + pad + math.floor(self.thumb_size / 2)
    local track_w = self.dimen.w - 2 * pad - self.thumb_size
    local span = self.value_max - self.value_min
    local ratio = span > 0 and ((self.value - self.value_min) / span) or 0

    -- Track
    bb:paintRect(track_x, track_y - math.floor(self.track_height / 2), track_w, self.track_height, Blitbuffer.COLOR_BLACK)
    -- Clear inner to leave 2px border look
    local inner = 2
    if self.track_height > inner * 2 then
        bb:paintRect(track_x + inner, track_y - math.floor(self.track_height / 2) + inner,
            track_w - inner * 2, self.track_height - inner * 2, Blitbuffer.COLOR_WHITE)
    end
    -- Filled portion
    local fill_w = math.floor(track_w * ratio)
    if fill_w > 0 then
        bb:paintRect(track_x, track_y - math.floor(self.track_height / 2), fill_w, self.track_height, Blitbuffer.COLOR_BLACK)
    end
    -- Thumb (≥ 48px touch via bar_height hit area; visual thumb solid square)
    local thumb_x = track_x + fill_w - math.floor(self.thumb_size / 2)
    local thumb_y = track_y - math.floor(self.thumb_size / 2)
    bb:paintRect(thumb_x, thumb_y, self.thumb_size, self.thumb_size, Blitbuffer.COLOR_BLACK)
    bb:paintRect(thumb_x + 2, thumb_y + 2, self.thumb_size - 4, self.thumb_size - 4, Blitbuffer.COLOR_WHITE)
    bb:paintRect(thumb_x + 6, thumb_y + 6, self.thumb_size - 12, self.thumb_size - 12, Blitbuffer.COLOR_BLACK)
end

return Slider
