--[[--
Display tab: frontlight, warmth, night mode, auto-rotate.
@module modern_menu.ui.tabs.display
--]]

local Device = require("device")
local Event = require("ui/event")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen
local _ = require("gettext")

local ToggleCard = require("widgets/toggle_card")
local Slider = require("widgets/slider")

local DisplayTab = {}

local function powerd()
    return Device.powerd
end

function DisplayTab:build(parent)
    local width = Screen:getWidth() - Screen:scaleBySize(32)
    local pd = powerd()
    local content = VerticalGroup:new{ align = "left" }

    local fl_min, fl_max, fl_val = 0, 100, 0
    if pd and Device:hasFrontlight() then
        fl_min = pd.fl_min or 0
        fl_max = pd.fl_max or 100
        fl_val = pd:frontlightIntensity() or fl_min
    end

    local brightness = Slider:new{
        title = _("Brightness"),
        value = fl_val,
        value_min = fl_min,
        value_max = fl_max,
        value_step = 1,
        width = width,
        show_parent = parent,
        callback = function(val)
            if pd and Device:hasFrontlight() then
                pd:setIntensity(val)
            end
        end,
    }
    table.insert(content, brightness)
    table.insert(content, VerticalSpan:new{ width = Size.span.vertical_default })

    if Device:hasNaturalLight() then
        local warmth_val = pd and pd:frontlightWarmth() or 0
        local warmth = Slider:new{
            title = _("Warmth"),
            value = warmth_val,
            value_min = 0,
            value_max = 100,
            value_step = 1,
            width = width,
            show_parent = parent,
            callback = function(val)
                if pd then
                    pd:setWarmth(val)
                end
            end,
        }
        table.insert(content, warmth)
        table.insert(content, VerticalSpan:new{ width = Size.span.vertical_default })
    end

    local night_checked = false
    if G_reader_settings then
        night_checked = G_reader_settings:isTrue("night_mode")
    end

    local night = ToggleCard:new{
        title = _("Night mode"),
        subtitle = _("Invert colors for dark reading"),
        checked = night_checked,
        width = width,
        show_parent = parent,
        callback = function()
            UIManager:broadcastEvent(Event:new("ToggleNightMode"))
        end,
    }
    table.insert(content, night)
    table.insert(content, VerticalSpan:new{ width = Size.span.vertical_default })

    local rotate_checked = false
    if G_reader_settings then
        local lock = G_reader_settings:readSetting("lock_rotation")
        rotate_checked = not lock
    end

    local rotate = ToggleCard:new{
        title = _("Auto-rotate"),
        subtitle = _("Allow orientation changes"),
        checked = rotate_checked,
        width = width,
        show_parent = parent,
        callback = function(checked)
            if G_reader_settings then
                G_reader_settings:saveSetting("lock_rotation", not checked)
            end
            UIManager:broadcastEvent(Event:new("SetRotationMode"))
        end,
    }
    table.insert(content, rotate)

    return content
end

return DisplayTab
