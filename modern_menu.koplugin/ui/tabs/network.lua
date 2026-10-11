--[[--
Network tab: Wi-Fi toggle, sync status, OPDS shortcut.
@module modern_menu.ui.tabs.network
--]]

local Device = require("device")
local Font = require("ui/font")
local InfoMessage = require("ui/widget/infomessage")
local NetworkMgr = require("ui/network/manager")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen
local _ = require("gettext")

local ToggleCard = require("widgets/toggle_card")

local NetworkTab = {}

function NetworkTab:build(parent)
    local width = Screen:getWidth() - Screen:scaleBySize(32)
    local content = VerticalGroup:new{ align = "left" }

    local wifi_on = false
    if NetworkMgr.isWifiOn then
        wifi_on = NetworkMgr:isWifiOn()
    end

    local connected = false
    if NetworkMgr.isConnected then
        connected = NetworkMgr:isConnected()
    end

    local wifi = ToggleCard:new{
        title = _("Wi-Fi"),
        subtitle = connected and _("Connected") or (wifi_on and _("On, not connected") or _("Off")),
        checked = wifi_on,
        width = width,
        show_parent = parent,
        callback = function(checked)
            if checked then
                NetworkMgr:turnOnWifi(function()
                    UIManager:setDirty(parent, "ui")
                end, true)
            else
                NetworkMgr:turnOffWifi(function()
                    UIManager:setDirty(parent, "ui")
                end)
            end
        end,
    }
    table.insert(content, wifi)
    table.insert(content, VerticalSpan:new{ width = Size.span.vertical_default })

    local status_text = _("Status: offline")
    if connected then
        status_text = _("Status: online")
    elseif wifi_on then
        status_text = _("Status: Wi-Fi on, no link")
    end

    table.insert(content, TextWidget:new{
        text = status_text,
        face = Font:getFace("smallinfofont", 18),
        max_width = width,
    })
    table.insert(content, VerticalSpan:new{ width = Size.span.vertical_default })

    local opds = ToggleCard:new{
        title = _("OPDS catalogs"),
        subtitle = _("Open network library browser"),
        checked = false,
        width = width,
        show_parent = parent,
        callback = function()
            -- Open stock OPDS UI when the filemanager/reader exposes it
            local ok = pcall(function()
                if parent.ui and parent.ui.openOPDS then
                    parent.ui:openOPDS()
                else
                    UIManager:show(InfoMessage:new{
                        text = _("Open File Manager → Search → OPDS to browse catalogs."),
                        timeout = 3,
                    })
                end
            end)
            if not ok then
                UIManager:show(InfoMessage:new{
                    text = _("OPDS is available from the File Manager network menu."),
                    timeout = 3,
                })
            end
            -- Reset visual toggle; this is an action card, not a latch
            opds:setChecked(false)
        end,
    }
    table.insert(content, opds)

    return content
end

return NetworkTab
