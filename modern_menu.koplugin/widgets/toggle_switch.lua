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
    -- A fresh size. The painted dimen carries screen coordinates, and a
    -- parent that keeps that table would shift the next layout.
    return Geom:new{
        w = self.width,
        h = self.height,
    }
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

    -- Same fill as the track. paintCircle goes through per-pixel rotation
    -- and, once this row is scrolled into the offscreen buffer, lands the
    -- thumb in a column of its own. Kindle shows that as a dot beside the name.
    local thumb_r = math.max(2, r - Screen:scaleBySize(3))
    local cx = checked and (x + w - r) or (x + r)
    local cy = y + r
    local color = checked and Blitbuffer.COLOR_WHITE or ink
    bb:paintRoundedRect(cx - thumb_r, cy - thumb_r, thumb_r * 2, thumb_r * 2, color, thumb_r)
end

return ToggleSwitch
