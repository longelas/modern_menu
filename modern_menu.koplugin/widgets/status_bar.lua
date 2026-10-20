--[[--
Top status bar matched to Kobold: time on the left, then contrast, Wi-Fi,
and a battery icon or percentage. The file-browser copy is off until enabled
in settings. The menu copy can be hidden entirely.
@module modern_menu.widgets.status_bar
--]]

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Event = require("ui/event")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local Widget = require("ui/widget/widget")
local VerticalGroup = require("ui/widget/verticalgroup")
local Screen = Device.screen
local Settings = require("settings")

local NetworkMgr = require("ui/network/manager")

local SETTINGS_KEY = "modern_menu_show_status_elsewhere"

local StatusBar = InputContainer:extend{
    name = "modern_status_bar",
    ui = nil,
    show_parent = nil,
    width = nil,
    height = nil,
    side_margin = nil,
    right_inset = nil, -- extra right pad (e.g. scrollbar gutter in menu)
    _clock_action = nil,
    _hit_zones = nil,
}

--- Outline battery with a fill that follows the charge. KOReader has no
-- battery icon in its set, so this is drawn directly.
local BatteryGlyph = Widget:extend{
    width = 1,
    height = 1,
    capacity = nil,
}

function BatteryGlyph:getSize()
    return Geom:new{ w = self.width, h = self.height }
end

function BatteryGlyph:paintTo(bb, x, y)
    local w, h = self.width, self.height
    local cap = tonumber(self.capacity)
    local body_h = math.max(4, math.floor(h * 0.62))
    local nub_w = math.max(2, math.floor(w * 0.14))
    local body_w = math.max(4, w - nub_w)
    local top = y + math.floor((h - body_h) / 2)
    local thick = math.max(1, Screen:scaleBySize(1))
    local ink = Blitbuffer.COLOR_BLACK
    bb:paintRect(x, top, body_w, thick, ink)
    bb:paintRect(x, top + body_h - thick, body_w, thick, ink)
    bb:paintRect(x, top, thick, body_h, ink)
    bb:paintRect(x + body_w - thick, top, thick, body_h, ink)
    local nub_h = math.max(2, math.floor(body_h * 0.45))
    bb:paintRect(
        x + body_w,
        top + math.floor((body_h - nub_h) / 2),
        nub_w,
        nub_h,
        ink
    )
    if cap then
        local inner_w = body_w - thick * 4
        local inner_h = body_h - thick * 4
        local fill_w = math.floor(inner_w * math.max(0, math.min(100, cap)) / 100)
        if inner_w > 0 and inner_h > 0 and fill_w > 0 then
            bb:paintRect(x + thick * 2, top + thick * 2, fill_w, inner_h, ink)
        end
    end
    self.dimen = Geom:new{ x = x, y = y, w = w, h = h }
end

function StatusBar.elsewhereEnabled()
    return G_reader_settings and G_reader_settings:isTrue(SETTINGS_KEY) or false
end

function StatusBar.setElsewhereEnabled(enabled)
    if G_reader_settings then
        G_reader_settings:saveSetting(SETTINGS_KEY, enabled and true or false)
        G_reader_settings:flush()
    end
    UIManager:broadcastEvent(Event:new("ModernMenuStatusChromeChanged", enabled and true or false))
end

function StatusBar.make(opts)
    opts = opts or {}
    return StatusBar:new{
        ui = opts.ui,
        show_parent = opts.show_parent,
        width = opts.width or Screen:getWidth(),
        side_margin = opts.side_margin or Screen:scaleBySize(30),
        right_inset = opts.right_inset or 0,
        on_dismiss = opts.on_dismiss,
        show_close = opts.show_close == true,
    }
end

function StatusBar:init()
    self.width = self.width or Screen:getWidth()
    self.height = self.height or Screen:scaleBySize(40)
    self.side_margin = self.side_margin or Screen:scaleBySize(30)
    self.right_inset = self.right_inset or 0
    self.show_parent = self.show_parent or self
    self.icon_size = Screen:scaleBySize(16)
    self.icon_gap = Screen:scaleBySize(10)
    self._hit_zones = {}

    self.dimen = Geom:new{
        x = 0, y = 0,
        w = self.width,
        h = self.height,
    }

    self:_rebuild()

    if Device:isTouchDevice() then
        self.ges_events = {
            TapStatusBar = {
                GestureRange:new{
                    ges = "tap",
                    range = self.dimen,
                },
            },
        }
    end

    self:_scheduleClock()
end

function StatusBar:getSize()
    return Geom:new{ w = self.width, h = self.height }
end

function StatusBar:_clockText()
    return os.date("%I:%M %p")
end

function StatusBar:_wifiIconName()
    local ok_on, on = pcall(function()
        return NetworkMgr:isWifiOn()
    end)
    if ok_on and on then
        return "wifi.open.100"
    end
    return "wifi.open.0"
end

function StatusBar:_batteryCapacity()
    local powerd = Device:getPowerDevice()
    if not powerd or not powerd.getCapacity then
        return nil
    end
    local ok, cap = pcall(function()
        return powerd:getCapacity()
    end)
    if not ok or type(cap) ~= "number" then
        return nil
    end
    return math.floor(cap + 0.5)
end

function StatusBar:_iconBox(icon, id)
    local box = FrameContainer:new{
        bordersize = 0,
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        icon,
    }
    box._status_id = id
    return box
end

function StatusBar:_koIcon(name, id)
    local icon
    local ok, widget = pcall(function()
        return IconWidget:new{
            icon = name,
            width = self.icon_size,
            height = self.icon_size,
            alpha = true,
        }
    end)
    if ok and widget then
        icon = widget
    else
        icon = TextWidget:new{
            text = "·",
            face = Settings.face(16, "cfont"),
        }
    end
    return self:_iconBox(icon, id)
end

function StatusBar:_batteryLabel()
    local cap = self:_batteryCapacity()
    if not cap then
        return "--"
    end
    return string.format("%d%%", cap)
end

function StatusBar:_batteryIcon()
    self._battery_glyph = nil
    self._battery_text = nil
    if Settings.getBatteryPercent() then
        -- Hold the width of "100%" so a minute tick from 9% to 10% does not
        -- shift the icons beside it.
        local face = Settings.face(16, "cfont")
        local widest = TextWidget:new{
            text = "100%",
            face = face,
            fgcolor = Blitbuffer.COLOR_BLACK,
        }
        local label = TextWidget:new{
            text = self:_batteryLabel(),
            face = face,
            fgcolor = Blitbuffer.COLOR_BLACK,
        }
        local widest_size = widest:getSize()
        local label_size = label:getSize()
        local slot = RightContainer:new{
            dimen = Geom:new{
                w = widest_size.w,
                h = math.max(widest_size.h or 0, label_size.h or 0),
            },
            label,
        }
        self._battery_text = label
        return self:_iconBox(slot, "battery")
    end
    -- Kobold draws the battery a bit wider than the other status icons.
    local width = math.floor(self.icon_size * 1.3)
    local glyph = BatteryGlyph:new{
        width = width,
        height = self.icon_size,
        capacity = self:_batteryCapacity(),
    }
    self._battery_glyph = glyph
    return self:_iconBox(glyph, "battery")
end

function StatusBar:_rebuild()
    local time_w = TextWidget:new{
        text = self:_clockText(),
        face = Settings.face(16, "cfont"),
        fgcolor = Blitbuffer.COLOR_BLACK,
    }
    -- The text widget's height includes line spacing above the clock glyphs.
    -- The icons follow the glyphs, which sit at about 60% of that box.
    local time_h = time_w:getSize().h
    if time_h and time_h > 0 then
        self.icon_size = math.max(Screen:scaleBySize(12), math.floor(time_h * 0.62))
        self.icon_gap = math.max(Screen:scaleBySize(6), math.floor(self.icon_size * 0.4))
    end
    -- The close mark is inset inside its icon box. Pull the row out by that
    -- amount so the stroke meets the same margin the clock uses on the left.
    local close_inset = math.floor((self.icon_size or 0) * 0.16)
    local pad_right = math.max(0, self.side_margin - close_inset)
    local inner_w = self.width - self.side_margin - pad_right
    if inner_w < Screen:scaleBySize(80) then
        inner_w = Screen:scaleBySize(80)
    end

    local right = HorizontalGroup:new{ align = "center" }
    self._buttons = {}
    local function add_icon(box, id)
        if right[1] then
            table.insert(right, HorizontalSpan:new{ width = self.icon_gap })
        end
        table.insert(right, box)
        self._buttons[id] = box
    end

    -- Same order as Kobold: contrast, Wi-Fi, battery.
    if Device:hasFrontlight() then
        add_icon(self:_koIcon("appbar.contrast", "brightness"), "brightness")
    end
    local wifi_name = self:_wifiIconName()
    self._last_wifi_icon = wifi_name
    add_icon(self:_koIcon(wifi_name, "wifi"), "wifi")
    add_icon(self:_batteryIcon(), "battery")
    -- Menu dismiss sits with the status icons, not in the title row.
    if self.show_close then
        add_icon(self:_koIcon("close", "close"), "close")
    end

    local row = OverlapGroup:new{
        dimen = Geom:new{ w = inner_w, h = self.height },
        LeftContainer:new{
            dimen = Geom:new{ w = inner_w, h = self.height },
            time_w,
        },
        RightContainer:new{
            dimen = Geom:new{ w = inner_w, h = self.height },
            right,
        },
    }

    self[1] = FrameContainer:new{
        bordersize = 0,
        padding_top = Screen:scaleBySize(4),
        padding_bottom = Screen:scaleBySize(2),
        padding_left = self.side_margin,
        padding_right = pad_right,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        width = self.width,
        row,
    }

    self.time_widget = time_w
end

function StatusBar:refresh()
    self:_rebuild()
    UIManager:setDirty(self.show_parent or self, "ui", self.dimen)
end

function StatusBar:_scheduleClock()
    self:_unscheduleClock()
    local now = os.date("*t")
    local delay = 60 - (now.sec or 0)
    if delay < 1 then delay = 60 end
    self._clock_action = function()
        if self.time_widget then
            self.time_widget:setText(self:_clockText())
        end
        if self._battery_glyph then
            self._battery_glyph.capacity = self:_batteryCapacity()
        end
        if self._battery_text and self._battery_text.setText then
            self._battery_text:setText(self:_batteryLabel())
        end
        local wifi_name = self:_wifiIconName()
        local need_rebuild = self._last_wifi_icon ~= wifi_name
        if need_rebuild then
            self:refresh()
        else
            UIManager:setDirty(self.show_parent or self, "ui", self.dimen)
        end
        self:_scheduleClock()
    end
    UIManager:scheduleIn(delay, self._clock_action)
end

function StatusBar:_unscheduleClock()
    if self._clock_action then
        UIManager:unschedule(self._clock_action)
        self._clock_action = nil
    end
end

function StatusBar:onCloseWidget()
    self:_unscheduleClock()
end

function StatusBar:free()
    self:_unscheduleClock()
    InputContainer.free(self)
end

function StatusBar:paintTo(bb, x, y)
    self.dimen.x = x
    self.dimen.y = y
    self.dimen.w = self.width
    self.dimen.h = self.height
    if self[1] then
        self[1]:paintTo(bb, x, y)
    end
    self._hit_zones = {}
    local slop = Screen:scaleBySize(8)
    for id, btn in pairs(self._buttons or {}) do
        if btn.dimen then
            -- The glyph is the size of the clock. The tap target stays larger.
            self._hit_zones[#self._hit_zones + 1] = {
                id = id,
                geom = Geom:new{
                    x = btn.dimen.x - slop,
                    y = self.dimen.y,
                    w = btn.dimen.w + slop * 2,
                    h = self.height,
                },
            }
        end
    end
end

function StatusBar:onTapStatusBar(_, ges)
    if not ges or not ges.pos or not self.dimen then
        return false
    end
    if not self.dimen:contains(ges.pos) then
        return false
    end
    for _, zone in ipairs(self._hit_zones or {}) do
        if zone.geom and zone.geom:contains(ges.pos) then
            self:_handleAction(zone.id)
            return true
        end
    end
    return true
end

function StatusBar:_handleAction(id)
    if id == "wifi" then
        self:_onWifi()
    elseif id == "brightness" then
        self:_onBrightness()
    elseif id == "battery" then
        self:_onBattery()
    elseif id == "close" then
        self:_leaveMenu()
    end
end

function StatusBar:_leaveMenu()
    if self.on_dismiss then
        self.on_dismiss()
    end
end

function StatusBar:_onWifi()
    self:_leaveMenu()
    if NetworkMgr.promptWifi then
        NetworkMgr:promptWifi(function()
            self:refresh()
        end, false, true)
    elseif NetworkMgr.toggleWifi then
        NetworkMgr:toggleWifi()
        self:refresh()
    end
end

function StatusBar:_onBrightness()
    if not Device:hasFrontlight() then
        return
    end
    self:_leaveMenu()
    local ok, FrontLightWidget = pcall(require, "ui/widget/frontlightwidget")
    if ok and FrontLightWidget then
        UIManager:show(FrontLightWidget:new{})
    end
end

function StatusBar:_onBattery()
    -- Close first. The statistics screen is not modal, so it would open
    -- under this menu and stay hidden.
    self:_leaveMenu()
    -- Prefer batterystat plugin (same as stock "Battery statistics")
    local ui = self.ui
    if ui and ui.batterystat and ui.batterystat.onShowBatteryStatistics then
        ui.batterystat:onShowBatteryStatistics()
        return
    end
    UIManager:broadcastEvent(Event:new("ShowBatteryStatistics"))
end

---------------------------------------------------------------------------
-- FileManager title-bar wrapper: StatusBar stacked above stock TitleBar
---------------------------------------------------------------------------

local StatusTitleStack = InputContainer:extend{
    name = "modern_status_title_stack",
    status_bar = nil,
    title_bar = nil,
}

function StatusTitleStack:init()
    self[1] = VerticalGroup:new{
        align = "left",
        self.status_bar,
        self.title_bar,
    }
    self.left_button = self.title_bar and self.title_bar.left_button
    self.right_button = self.title_bar and self.title_bar.right_button
    self.dimen = Geom:new{
        w = self.status_bar.width or Screen:getWidth(),
        h = self:getHeight(),
    }
end

function StatusTitleStack:getHeight()
    local sh = self.status_bar and self.status_bar.height or 0
    local th = self.title_bar and self.title_bar:getHeight() or 0
    return sh + th
end

function StatusTitleStack:getSize()
    return Geom:new{
        w = self.status_bar and self.status_bar.width or Screen:getWidth(),
        h = self:getHeight(),
    }
end

function StatusTitleStack:paintTo(bb, x, y)
    self.dimen.x = x
    self.dimen.y = y
    self.dimen.w = self:getSize().w
    self.dimen.h = self:getHeight()
    if self[1] then
        self[1]:paintTo(bb, x, y)
    end
end

function StatusTitleStack:setTitle(title, no_refresh)
    if self.title_bar and self.title_bar.setTitle then
        return self.title_bar:setTitle(title, no_refresh)
    end
end

function StatusTitleStack:setSubTitle(subtitle, no_refresh)
    if self.title_bar and self.title_bar.setSubTitle then
        return self.title_bar:setSubTitle(subtitle, no_refresh)
    end
end

function StatusTitleStack:setLeftIcon(icon)
    if self.title_bar and self.title_bar.setLeftIcon then
        self.title_bar:setLeftIcon(icon)
        self.left_button = self.title_bar.left_button
    end
end

function StatusTitleStack:setRightIcon(icon)
    if self.title_bar and self.title_bar.setRightIcon then
        self.title_bar:setRightIcon(icon)
        self.right_button = self.title_bar.right_button
    end
end

function StatusTitleStack:generateHorizontalLayout()
    if self.title_bar and self.title_bar.generateHorizontalLayout then
        return self.title_bar:generateHorizontalLayout()
    end
    return {}
end

function StatusTitleStack:generateVerticalLayout()
    if self.title_bar and self.title_bar.generateVerticalLayout then
        return self.title_bar:generateVerticalLayout()
    end
    return {}
end

StatusBar.StatusTitleStack = StatusTitleStack
StatusBar.SETTINGS_KEY = SETTINGS_KEY

return StatusBar
