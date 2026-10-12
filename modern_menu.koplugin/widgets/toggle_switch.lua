--[[--
Rounded e-ink toggle switch — muted gray by default, pure black when enabled.
@module modern_menu.widgets.toggle_switch
--]]

local Blitbuffer = require("ffi/blitbuffer")
local Geom = require("ui/geometry")
local Size = require("ui/size")
local Widget = require("ui/widget/widget")
local Device = require("device")
local Screen = Device.screen
local Settings = require("settings")

local ToggleSwitch = Widget:extend{
    checked = false,
    width = nil,
    height = nil,
    dimen = nil,
}

function ToggleSwitch:init()
    self.width = self.width or Screen:scaleBySize(44)
    self.height = self.height or Screen:scaleBySize(24)
    self.dimen = Geom:new{
        w = self.width,
        h = self.height,
    }
end

function ToggleSwitch:getSize()
    return self.dimen
end

function ToggleSwitch:paintTo(bb, x, y)
    self.dimen.x = x
    self.dimen.y = y

    local w, h = self.width, self.height
    local r = math.floor(h / 2)
    local checked = self.checked
    local bw = math.max(1, Size.border.thin)
    local ink = Settings.getToggleFg()

    if checked then
        bb:paintRoundedRect(x, y, w, h, ink, r)
    else
        bb:paintRoundedRect(x, y, w, h, Blitbuffer.COLOR_WHITE, r)
        bb:paintBorder(x, y, w, h, bw, ink, r)
    end

    local thumb_r = math.max(2, r - Screen:scaleBySize(3))
    local cx = checked and (x + w - r) or (x + r)
    local cy = y + r
    bb:paintCircle(cx, cy, thumb_r, checked and Blitbuffer.COLOR_WHITE or ink)
end

return ToggleSwitch
