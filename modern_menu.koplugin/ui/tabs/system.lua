--[[--
System tab: battery, storage, sleep / reboot actions.
@module modern_menu.ui.tabs.system
--]]

local Device = require("device")
local Font = require("ui/font")
local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local T = require("ffi/util").template
local Screen = Device.screen
local _ = require("gettext")

local ToggleCard = require("widgets/toggle_card")

local SystemTab = {}

local function battery_text()
    local pd = Device.powerd
    if not pd then
        return _("Battery: n/a")
    end
    local capacity = pd:getCapacity()
    if capacity == nil then
        return _("Battery: n/a")
    end
    local charging = pd:isCharging() and _("charging") or _("discharging")
    return T(_("Battery: %1% (%2)"), capacity, charging)
end

local function storage_text()
    local ok, util = pcall(require, "util")
    if not ok or not util then
        return _("Storage: n/a")
    end
    local DataStorage = require("datastorage")
    local path = DataStorage:getDataDir()
    if util.diskUsage then
        local usage = util.diskUsage(path)
        if usage and usage.available then
            local mb = math.floor(usage.available / (1024 * 1024))
            return T(_("Free storage: %1 MB"), mb)
        end
    end
    return T(_("Storage: %1"), tostring(path))
end

function SystemTab:build(parent)
    local width = Screen:getWidth() - Screen:scaleBySize(32)
    local content = VerticalGroup:new{ align = "left" }

    table.insert(content, TextWidget:new{
        text = battery_text(),
        face = Font:getFace("smallinfofont", 20),
        bold = true,
        max_width = width,
    })
    table.insert(content, VerticalSpan:new{ width = Size.span.vertical_small })
    table.insert(content, TextWidget:new{
        text = storage_text(),
        face = Font:getFace("smallinfofont", 18),
        max_width = width,
    })
    table.insert(content, VerticalSpan:new{ width = Size.span.vertical_large })

    local sleep = ToggleCard:new{
        title = _("Sleep"),
        subtitle = _("Suspend device now"),
        checked = false,
        width = width,
        show_parent = parent,
        callback = function()
            sleep:setChecked(false)
            UIManager:show(ConfirmBox:new{
                text = _("Suspend the device?"),
                ok_text = _("Sleep"),
                ok_callback = function()
                    UIManager:close(parent)
                    Device:suspend()
                end,
            })
        end,
    }
    table.insert(content, sleep)
    table.insert(content, VerticalSpan:new{ width = Size.span.vertical_default })

    local reboot = ToggleCard:new{
        title = _("Reboot"),
        subtitle = _("Restart the device"),
        checked = false,
        width = width,
        show_parent = parent,
        callback = function()
            reboot:setChecked(false)
            if not Device:canReboot() then
                UIManager:show(InfoMessage:new{
                    text = _("Reboot is not supported on this device."),
                    timeout = 2,
                })
                return
            end
            UIManager:show(ConfirmBox:new{
                text = _("Reboot the device?"),
                ok_text = _("Reboot"),
                ok_callback = function()
                    UIManager:close(parent)
                    Device:reboot()
                end,
            })
        end,
    }
    table.insert(content, reboot)

    return content
end

return SystemTab
