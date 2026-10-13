--[[--
Web-style breadcrumb trail for menu depth.
Parents are tappable to jump back; current crumb is bold.
@module modern_menu.widgets.breadcrumb
--]]

local Blitbuffer = require("ffi/blitbuffer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local InputContainer = require("ui/widget/container/inputcontainer")
local TextWidget = require("ui/widget/textwidget")
local Device = require("device")
local Screen = Device.screen
local Settings = require("settings")

local Breadcrumb = InputContainer:extend{
    crumbs = nil, -- { "Library", "Settings", ... }
    width = nil,
    on_select = nil, -- function(index) — 1-based crumb index
    show_parent = nil,
}

function Breadcrumb:init()
    self.crumbs = self.crumbs or {}
    self.width = self.width or Screen:getWidth()
    self.segments = {} -- { widget=, index=, dimen filled on paint }
    self:_rebuild()
    self.ges_events = {
        TapCrumb = {
            GestureRange:new{
                ges = "tap",
                range = Geom:new{
                    x = 0, y = 0,
                    w = Screen:getWidth(),
                    h = Screen:getHeight(),
                },
            },
        },
    }
end

function Breadcrumb:_rebuild()
    local row = HorizontalGroup:new{ align = "center" }
    self.segments = {}
    local n = #self.crumbs
    if n == 0 then
        self[1] = row
        self.dimen = Geom:new{ w = self.width, h = Screen:scaleBySize(20) }
        return
    end

    local sep = " › "
    -- Budget width across crumbs; keep current readable
    local max_total = self.width
    for i, name in ipairs(self.crumbs) do
        local is_last = (i == n)
        local label = TextWidget:new{
            text = tostring(name),
            face = Settings.face(is_last and 16 or 15, "xx_smallinfofont"),
            bold = is_last,
            fgcolor = is_last and Blitbuffer.COLOR_BLACK or Settings.getMutedFg(),
            max_width = math.floor(max_total / math.max(n, 1)),
        }
        table.insert(row, label)
        self.segments[#self.segments + 1] = {
            index = i,
            widget = label,
        }
        if not is_last then
            table.insert(row, TextWidget:new{
                text = sep,
                face = Settings.face(15, "xx_smallinfofont"),
                fgcolor = Settings.getMutedFg(),
            })
        end
    end

    self[1] = row
    self.dimen = Geom:new{
        w = self.width,
        h = math.max(Screen:scaleBySize(22), row:getSize().h),
    }
end

function Breadcrumb:setCrumbs(crumbs)
    self.crumbs = crumbs or {}
    self:_rebuild()
end

function Breadcrumb:onTapCrumb(_, ges)
    if not ges or not ges.pos or not self.dimen or not self.dimen:contains(ges.pos) then
        return false
    end
    -- Hit-test individual crumb labels (skip separators)
    for _, seg in ipairs(self.segments) do
        local w = seg.widget
        if w.dimen and w.dimen:contains(ges.pos) then
            if self.on_select then
                self.on_select(seg.index)
            end
            return true
        end
    end
    return true -- consume taps on the breadcrumb band
end

return Breadcrumb
