--[[--
Kobo-style menu row: inset content, one hairline between options.
Category groups alternate white / light gray (zebra striping).
@module modern_menu.widgets.menu_item_card
--]]

local Blitbuffer = require("ffi/blitbuffer")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local Device = require("device")
local Screen = Device.screen

local ToggleSwitch = require("widgets/toggle_switch")
local Settings = require("settings")

local MenuItemCard = InputContainer:extend{
    item = nil,
    width = nil,
    show_parent = nil,
    menu = nil,
    index = 1,
    show_separator = true,
    side_margin = nil,
    -- 0 = white, 1 = light gray (category zebra)
    stripe = 0,
}

local function has_submenu(item)
    return item.sub_item_table_func ~= nil or item.sub_item_table ~= nil
end

local function item_text(item)
    if not item then return "" end
    if item.text_func then
        local ok, text = pcall(item.text_func)
        if ok and text then return text end
    end
    -- Stock TouchMenu empty-section placeholders (e.g. user style tweaks)
    if item.text and item.text ~= "" then
        return item.text
    end
    if item.if_empty_menu_title then
        return item.if_empty_menu_title
    end
    if item.title and item.title ~= "" and not has_submenu(item) then
        return item.title
    end
    return item.text or ""
end

local function item_enabled(item)
    if item.enabled_func then
        local ok, enabled = pcall(item.enabled_func)
        if ok then return enabled end
    end
    if item.enabled ~= nil then
        return item.enabled
    end
    return true
end

local function item_checked(item)
    if item.checked_func then
        local ok, checked = pcall(item.checked_func)
        if ok then return checked end
    end
    return item.checked
end

function MenuItemCard:init()
    local item = self.item or {}
    local side_margin = self.side_margin or Screen:scaleBySize(28)
    self.width = self.width or Screen:getWidth()
    local option_font = Settings.getOptionFontSize()
    local v_pad_raw = Settings.getOptionPaddingPx()
    -- FrameContainer padding must stay >= 0; negative settings shrink min row height.
    local v_pad = math.max(0, v_pad_raw)
    local base_min = Screen:scaleBySize(44)
    local min_h
    if v_pad_raw >= 0 then
        min_h = math.max(base_min, option_font + v_pad * 2)
    else
        min_h = math.max(
            Screen:scaleBySize(math.max(16, option_font)),
            base_min + v_pad_raw * 2
        )
    end
    local enabled = item_enabled(item)
    local checked = item_checked(item)
    local submenu = has_submenu(item)
    local text = item_text(item)
    local fg = enabled and Blitbuffer.COLOR_BLACK or Settings.getDisabledFg()
    local inner_w = self.width - side_margin * 2
    -- Soft inset so text / › sit inside the stripe, not on its edges
    local content_pad = Screen:scaleBySize(12)
    local trailing_w = Screen:scaleBySize(56)
    local row_w = inner_w - content_pad * 2

    local icon_size = Screen:scaleBySize(math.max(18, math.floor(option_font * 1.1)))
    local icon_slot = 0
    local leading = HorizontalGroup:new{ align = "center" }
    if item.icon and item.icon ~= "" then
        local ok, icon = pcall(function()
            return IconWidget:new{
                icon = item.icon,
                width = icon_size,
                height = icon_size,
                alpha = true,
            }
        end)
        if ok and icon then
            table.insert(leading, icon)
            table.insert(leading, HorizontalSpan:new{ width = Screen:scaleBySize(10) })
            icon_slot = icon_size + Screen:scaleBySize(10)
        end
    end

    local title = TextWidget:new{
        text = text,
        face = Font:getFace("smallinfofont", option_font),
        fgcolor = fg,
        max_width = row_w - trailing_w - icon_slot - Screen:scaleBySize(8),
    }
    table.insert(leading, title)

    local trailing
    if submenu then
        trailing = TextWidget:new{
            text = "›",
            face = Font:getFace("cfont", math.max(20, option_font + 4)),
            fgcolor = Settings.getMutedFg(),
        }
    elseif checked ~= nil then
        if item.radio then
            trailing = TextWidget:new{
                text = checked and "◉" or "○",
                face = Font:getFace("smallinfofont", math.max(16, option_font - 1)),
                fgcolor = Settings.getMutedFg(),
            }
        else
            trailing = ToggleSwitch:new{ checked = checked }
        end
    else
        trailing = TextWidget:new{
            text = "",
            face = Font:getFace("smallinfofont", 16),
        }
    end

    local row = HorizontalGroup:new{
        align = "center",
        LeftContainer:new{
            dimen = Geom:new{
                w = row_w - trailing_w,
                h = min_h,
            },
            leading,
        },
        RightContainer:new{
            dimen = Geom:new{
                w = trailing_w,
                h = min_h,
            },
            trailing,
        },
    }

    local bg = (self.stripe == 1) and Settings.getStripeBg() or Blitbuffer.COLOR_WHITE

    -- Stripe fills only the content column (side margins stay white)
    local body = FrameContainer:new{
        bordersize = 0,
        padding_top = v_pad,
        padding_bottom = v_pad,
        padding_left = content_pad,
        padding_right = content_pad,
        margin = 0,
        background = bg,
        width = inner_w,
        row,
    }

    local group = VerticalGroup:new{
        align = "left",
        HorizontalGroup:new{
            HorizontalSpan:new{ width = side_margin },
            body,
        },
    }

    -- One hairline between options, same inset + stripe as the row above
    if self.show_separator then
        table.insert(group, HorizontalGroup:new{
            HorizontalSpan:new{ width = side_margin },
            FrameContainer:new{
                bordersize = 0,
                padding = 0,
                margin = 0,
                background = bg,
                width = inner_w,
                LineWidget:new{
                    background = Settings.getSeparatorFg(),
                    dimen = Geom:new{
                        w = inner_w,
                        h = Size.line.thin,
                    },
                },
            },
        })
    end

    self[1] = group
    self.dimen = Geom:new{
        w = self.width,
        h = math.max(min_h, group:getSize().h),
    }
    self.enabled = enabled

    self.ges_events = {
        TapItem = {
            GestureRange:new{
                ges = "tap",
                range = self.dimen,
            },
        },
        HoldItem = {
            GestureRange:new{
                ges = "hold",
                range = self.dimen,
            },
        },
    }
end

function MenuItemCard:onTapItem(_, ges)
    if not self.enabled then
        return true
    end
    if self.menu then
        self.menu:onMenuSelect(self.item)
    end
    return true
end

function MenuItemCard:onHoldItem(_, ges)
    if not self.enabled then
        return true
    end
    if self.menu then
        self.menu:onMenuHold(self.item)
    end
    return true
end

return MenuItemCard
