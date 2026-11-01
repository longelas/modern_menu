--[[--
Web-style breadcrumb trail for menu depth.
Parents are tappable to jump back; current crumb is bold.
@module modern_menu.widgets.breadcrumb
--]]

local BD = require("ui/bidi")
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
    if self[1] and self[1].free then
        self[1]:free()
        self[1] = nil
    end
    local row = HorizontalGroup:new{ align = "center" }
    self.segments = {}
    local n = #self.crumbs
    if n == 0 then
        self[1] = row
        self.hit_rects = nil
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
            face = Settings.face(is_last and 16 or 15, "cfont"),
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
                face = Settings.face(15, "cfont"),
                fgcolor = Settings.getMutedFg(),
            })
        end
    end

    self[1] = row
    self.hit_rects = nil
    self.dimen = Geom:new{
        w = self.width,
        h = math.max(Screen:scaleBySize(22), row:getSize().h),
    }
end

--- Text labels do not keep a screen position. Record each crumb from
-- the row's layout once it has been painted.
function Breadcrumb:_cacheHitRects()
    self.hit_rects = {}
    local row = self[1]
    if not row or not row._offsets or not row._size or not self.dimen then
        return
    end
    local size = row._size
    local origin_x = self.dimen.x or 0
    local origin_y = self.dimen.y or 0
    if self.align == "center" then
        origin_x = origin_x + math.floor(((self.dimen.w or 0) - size.w) / 2)
    end
    if self.vertical_align == "center" then
        origin_y = origin_y + math.floor(((self.dimen.h or 0) - size.h) / 2)
    end
    local mirrored = BD.mirroredUILayout() and row.allow_mirroring ~= false
    local n = #row
    local index_of = {}
    for i, widget in ipairs(row) do
        index_of[widget] = i
    end
    for _, seg in ipairs(self.segments) do
        local i = index_of[seg.widget]
        local off_i = i and (mirrored and (n - i + 1) or i)
        local off = off_i and row._offsets[off_i]
        local w_size = seg.widget and seg.widget.getSize and seg.widget:getSize()
        if off and w_size then
            seg.rect = Geom:new{
                x = origin_x + off.x,
                y = origin_y,
                w = w_size.w,
                h = size.h,
            }
        else
            seg.rect = nil
        end
    end
    -- The separator belongs to the crumb before it, so the gap is tappable.
    local ordered = {}
    for _, seg in ipairs(self.segments) do
        if seg.rect then
            ordered[#ordered + 1] = seg
        end
    end
    table.sort(ordered, function(a, b)
        return a.rect.x < b.rect.x
    end)
    for i, seg in ipairs(ordered) do
        local nxt = ordered[i + 1]
        if nxt and nxt.rect.x > seg.rect.x then
            seg.rect.w = nxt.rect.x - seg.rect.x
        end
    end
end

function Breadcrumb:paintTo(bb, x, y)
    InputContainer.paintTo(self, bb, x, y)
    self:_cacheHitRects()
end

function Breadcrumb:setCrumbs(crumbs)
    crumbs = crumbs or {}
    local key = tostring(self.width) .. "\0" .. table.concat(crumbs, "\0")
    if key == self._crumb_key and self[1] then
        return
    end
    self._crumb_key = key
    self.crumbs = crumbs
    self:_rebuild()
end

function Breadcrumb:onTapCrumb(_, ges)
    if not ges or not ges.pos then
        return false
    end
    if not self.hit_rects then
        self:_cacheHitRects()
    end
    for _, seg in ipairs(self.segments or {}) do
        if seg.rect and seg.rect:contains(ges.pos) then
            -- The last crumb is the menu already on screen.
            if seg.index < #self.crumbs and self.on_select then
                self.on_select(seg.index)
            end
            return true
        end
    end
    if self.dimen and self.dimen:contains(ges.pos) then
        return true
    end
    return false
end

return Breadcrumb
