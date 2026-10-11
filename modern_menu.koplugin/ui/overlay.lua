--[[--
Main full-screen modal overlay for Modern Menu.
@module modern_menu.ui.overlay
--]]

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
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
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen
local _ = require("gettext")

local TabBar = require("ui/tab_bar")
local DisplayTab = require("ui/tabs/display")
local TypeTab = require("ui/tabs/type")
local NetworkTab = require("ui/tabs/network")
local SystemTab = require("ui/tabs/system")

local Overlay = InputContainer:extend{
    name = "modern_menu_overlay",
    modal = true,
    covers_fullscreen = true,
    ui = nil,
    selected_tab = 1,
}

local TAB_DEFS = {
    { id = "display", title = _("Display") },
    { id = "type", title = _("Typography") },
    { id = "network", title = _("Network") },
    { id = "system", title = _("System") },
}

function Overlay:init()
    self.dimen = Geom:new{
        x = 0, y = 0,
        w = Screen:getWidth(),
        h = Screen:getHeight(),
    }

    self.title_widget = TextWidget:new{
        text = _("Quick Settings"),
        face = Font:getFace("infofont", 22),
        bold = true,
    }

    self.close_label = TextWidget:new{
        text = _("Close"),
        face = Font:getFace("smallinfofont", 18),
        bold = true,
    }

    self.close_button = FrameContainer:new{
        bordersize = Size.border.thin,
        padding = Size.padding.default,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        self.close_label,
    }

    local header = HorizontalGroup:new{
        align = "center",
        self.title_widget,
        HorizontalSpan:new{ width = Size.span.horizontal_small },
        self.close_button,
    }

    -- Right-align close via stretching title area
    header = HorizontalGroup:new{
        align = "center",
        FrameContainer:new{
            bordersize = 0,
            padding = 0,
            margin = 0,
            background = Blitbuffer.COLOR_WHITE,
            width = self.dimen.w - Screen:scaleBySize(32) - self.close_button:getSize().w,
            self.title_widget,
        },
        self.close_button,
    }

    self.tab_bar = TabBar:new{
        tabs = TAB_DEFS,
        selected = self.selected_tab,
        width = self.dimen.w - Screen:scaleBySize(32),
        show_parent = self,
        on_change = function(_, index)
            self:switchTab(index)
        end,
    }

    self.content_container = VerticalGroup:new{ align = "left" }
    self:rebuildContent()

    local panel = FrameContainer:new{
        bordersize = Size.border.window,
        padding = Size.padding.large,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        width = self.dimen.w,
        height = self.dimen.h,
        VerticalGroup:new{
            align = "left",
            header,
            VerticalSpan:new{ width = Size.span.vertical_default },
            self.tab_bar,
            VerticalSpan:new{ width = Size.span.vertical_default },
            self.content_container,
        },
    }

    self[1] = CenterContainer:new{
        dimen = self.dimen,
        panel,
    }

    local screen_range = Geom:new{
        x = 0, y = 0,
        w = Screen:getWidth(),
        h = Screen:getHeight(),
    }

    self.ges_events = {
        TapClose = {
            GestureRange:new{
                ges = "tap",
                range = screen_range,
            },
        },
        SwipeClose = {
            GestureRange:new{
                ges = "swipe",
                range = screen_range,
            },
        },
        KeyClose = {
            GestureRange:new{
                ges = "key",
                range = screen_range,
            },
        },
    }

    if Device:hasKeys() then
        self.key_events = {
            Close = { { Device.input.group.Back } },
        }
    end
end

function Overlay:rebuildContent()
    local builders = {
        DisplayTab,
        TypeTab,
        NetworkTab,
        SystemTab,
    }
    local builder = builders[self.selected_tab] or DisplayTab
    -- Clear children
    for i = #self.content_container, 1, -1 do
        self.content_container[i] = nil
    end
    local panel = builder:build(self)
    table.insert(self.content_container, panel)
end

function Overlay:switchTab(index)
    if index == self.selected_tab then
        return
    end
    self.selected_tab = index
    self:rebuildContent()
    UIManager:setDirty(self, "ui")
end

function Overlay:onClose()
    UIManager:close(self)
    return true
end

function Overlay:onTapClose(_, ges)
    if not ges or not ges.pos then
        return false
    end
    -- Close button hit test
    if self.close_button.dimen and self.close_button.dimen:contains(ges.pos) then
        return self:onClose()
    end
    -- Let child widgets (tabs, sliders, toggles) handle taps in their areas
    return false
end

function Overlay:onSwipeClose(_, ges)
    if ges and ges.direction == "north" then
        return self:onClose()
    end
    return false
end

function Overlay:onShow()
    UIManager:setDirty(self, "ui")
    return true
end

return Overlay
