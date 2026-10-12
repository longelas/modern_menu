--[[--
Clara-style top status bar: time left; Wi‑Fi, brightness (if frontlight), battery %.
In the modern menu: chrome toggle left of the icons (show bar in file browser).
@module modern_menu.widgets.status_bar
--]]

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Event = require("ui/event")
local Font = require("ui/font")
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
local VerticalGroup = require("ui/widget/verticalgroup")
local Screen = Device.screen

local NetworkMgr = require("ui/network/manager")
local ToggleSwitch = require("widgets/toggle_switch")

local SETTINGS_KEY = "modern_menu_show_status_elsewhere"

local StatusBar = InputContainer:extend{
    name = "modern_status_bar",
    ui = nil,
    show_parent = nil,
    menu_shell = nil, -- when set, show chrome toggle (menu popup only)
    width = nil,
    height = nil,
    side_margin = nil,
    right_inset = nil, -- extra right pad (e.g. scrollbar gutter in menu)
    _clock_action = nil,
    _hit_zones = nil,
}

local function plugin_icons_dir()
    local src = debug.getinfo(1, "S").source
    local dir = src:match("@(.*/)")
    if dir then
        return dir .. "../icons/"
    end
    return "icons/"
end

local ICONS_DIR = plugin_icons_dir()

local function icon_path(name)
    return ICONS_DIR .. name .. ".svg"
end

function StatusBar.elsewhereEnabled()
    if not G_reader_settings then
        return true
    end
    return G_reader_settings:nilOrTrue(SETTINGS_KEY)
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
        menu_shell = opts.menu_shell,
        width = opts.width or Screen:getWidth(),
        side_margin = opts.side_margin or Screen:scaleBySize(36),
        right_inset = opts.right_inset or 0,
    }
end

function StatusBar:init()
    self.width = self.width or Screen:getWidth()
    self.height = self.height or Screen:scaleBySize(34)
    self.side_margin = self.side_margin or Screen:scaleBySize(36)
    self.right_inset = self.right_inset or 0
    self.show_parent = self.show_parent or self
    self.icon_size = Screen:scaleBySize(20)
    self.icon_gap = Screen:scaleBySize(12)
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

function StatusBar:_wifiIconName()
    if not NetworkMgr:isWifiOn() then
        return "wifi-off"
    end
    if not NetworkMgr:isConnected() then
        return "wifi-low"
    end
    local quality
    local ok, nw = pcall(function() return NetworkMgr:getCurrentNetwork() end)
    if ok and nw and nw.signal_quality then
        quality = nw.signal_quality
    end
    if quality and quality < 40 then
        return "wifi-low"
    elseif quality and quality < 70 then
        return "wifi"
    end
    return "wifi-high"
end

function StatusBar:_batteryText()
    local powerd = Device:getPowerDevice()
    if not powerd or not powerd.getCapacity then
        return "--%"
    end
    local ok, cap = pcall(function() return powerd:getCapacity() end)
    if not ok or type(cap) ~= "number" then
        return "--%"
    end
    return string.format("%d%%", math.floor(cap + 0.5))
end

function StatusBar:_makeIconButton(icon_file, id)
    local icon
    local ok, widget = pcall(function()
        return IconWidget:new{
            file = icon_path(icon_file),
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
            face = Font:getFace("smallinfofont", 16),
        }
    end
    local pad = Screen:scaleBySize(2)
    local box = FrameContainer:new{
        bordersize = 0,
        padding = pad,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        icon,
    }
    box._status_id = id
    return box
end

function StatusBar:_rebuild()
    local pad_right = self.side_margin + (self.right_inset or 0)
    local inner_w = self.width - self.side_margin - pad_right
    if inner_w < Screen:scaleBySize(80) then
        inner_w = Screen:scaleBySize(80)
    end

    local time_w = TextWidget:new{
        text = os.date("%H:%M"),
        face = Font:getFace("xx_smallinfofont", 14),
        fgcolor = Blitbuffer.COLOR_BLACK,
        bold = true,
    }

    local battery_w = TextWidget:new{
        text = self:_batteryText(),
        face = Font:getFace("xx_smallinfofont", 13),
        fgcolor = Blitbuffer.COLOR_DARK_GRAY,
    }
    local battery_btn = FrameContainer:new{
        bordersize = 0,
        padding = Screen:scaleBySize(2),
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        battery_w,
    }
    battery_btn._status_id = "battery"

    local right = HorizontalGroup:new{ align = "center" }
    self._buttons = {}

    -- Menu popup only: toggle for showing this bar in the file browser
    if self.menu_shell then
        local toggle = ToggleSwitch:new{
            checked = StatusBar.elsewhereEnabled(),
            width = Screen:scaleBySize(36),
            height = Screen:scaleBySize(20),
        }
        local toggle_btn = FrameContainer:new{
            bordersize = 0,
            padding = Screen:scaleBySize(2),
            margin = 0,
            background = Blitbuffer.COLOR_WHITE,
            toggle,
        }
        toggle_btn._status_id = "chrome_toggle"
        table.insert(right, toggle_btn)
        table.insert(right, HorizontalSpan:new{ width = self.icon_gap })
        self._buttons.chrome_toggle = toggle_btn
        self._chrome_toggle = toggle
    end

    local wifi_btn = self:_makeIconButton(self:_wifiIconName(), "wifi")
    table.insert(right, wifi_btn)
    self._buttons.wifi = wifi_btn

    if Device:hasFrontlight() then
        local sun_btn = self:_makeIconButton("sun", "brightness")
        table.insert(right, HorizontalSpan:new{ width = self.icon_gap })
        table.insert(right, sun_btn)
        self._buttons.brightness = sun_btn
    end

    table.insert(right, HorizontalSpan:new{ width = self.icon_gap })
    table.insert(right, battery_btn)
    self._buttons.battery = battery_btn

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
    self.battery_widget = battery_w
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
            self.time_widget:setText(os.date("%H:%M"))
        end
        if self.battery_widget then
            self.battery_widget:setText(self:_batteryText())
        end
        local need_rebuild = false
        local wifi_name = self:_wifiIconName()
        if self._last_wifi_icon ~= wifi_name then
            self._last_wifi_icon = wifi_name
            need_rebuild = true
        end
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
    for id, btn in pairs(self._buttons or {}) do
        if btn.dimen then
            self._hit_zones[#self._hit_zones + 1] = {
                id = id,
                geom = btn.dimen,
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
    elseif id == "chrome_toggle" then
        self:_onChromeToggle()
    end
end

function StatusBar:_onWifi()
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
    local ok, FrontLightWidget = pcall(require, "ui/widget/frontlightwidget")
    if ok and FrontLightWidget then
        UIManager:show(FrontLightWidget:new{})
    end
end

function StatusBar:_onBattery()
    -- Prefer batterystat plugin (same as stock "Battery statistics")
    local ui = self.ui
    if ui and ui.batterystat and ui.batterystat.onShowBatteryStatistics then
        ui.batterystat:onShowBatteryStatistics()
        return
    end
    UIManager:broadcastEvent(Event:new("ShowBatteryStatistics"))
end

function StatusBar:_onChromeToggle()
    local enabled = not StatusBar.elsewhereEnabled()
    StatusBar.setElsewhereEnabled(enabled)
    if self._chrome_toggle then
        self._chrome_toggle.checked = enabled
    end
    UIManager:setDirty(self.show_parent or self, "ui", self.dimen)
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
