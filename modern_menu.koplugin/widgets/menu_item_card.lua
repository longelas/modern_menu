--[[--
Menu row: white, inset like Kobold, one light-gray rule under each option.
@module modern_menu.widgets.menu_item_card
--]]

local Blitbuffer = require("ffi/blitbuffer")
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

local function row_face(item, size)
    if item and item.font_func then
        local ok, face = pcall(item.font_func, size)
        if ok and face then
            return face
        end
    end
    return Settings.face(size)
end

local function item_checked(item)
    if item.checked_func then
        local ok, checked = pcall(item.checked_func)
        if ok then return checked end
    end
    return item.checked
end

local function trailing_kind(item, checked)
    if has_submenu(item) then
        return "sub"
    end
    if checked ~= nil then
        if item.radio then
            return checked and "radio-on" or "radio-off"
        end
        return checked and "toggle-on" or "toggle-off"
    end
    return "none"
end

local function make_trailing(item, checked, option_font)
    if has_submenu(item) then
        return TextWidget:new{
            text = "›",
            face = Settings.face(math.max(20, option_font + 4), "cfont"),
            fgcolor = Settings.getMutedFg(),
        }
    end
    if checked ~= nil then
        if item.radio then
            return TextWidget:new{
                text = checked and "◉" or "○",
                face = Settings.face(math.max(16, option_font - 1)),
                fgcolor = Settings.getMutedFg(),
            }
        end
        return ToggleSwitch:new{ checked = checked }
    end
    return TextWidget:new{
        text = "",
        face = Settings.face(16),
    }
end

function MenuItemCard:init()
    local item = self.item or {}
    local side_margin = self.side_margin or Screen:scaleBySize(30)
    self.width = self.width or Screen:getWidth()
    local option_font = Settings.getOptionFontSize()
    local v_pad_raw = Settings.getOptionPaddingPx()
    -- FrameContainer padding must stay >= 0; negative settings shrink min row height.
    local v_pad = math.max(0, v_pad_raw)
    local base_min = Screen:scaleBySize(56)
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

    local title_max = row_w - trailing_w - icon_slot - Screen:scaleBySize(8)
    local title = TextWidget:new{
        text = text,
        face = row_face(item, option_font),
        fgcolor = fg,
        max_width = title_max,
    }
    table.insert(leading, title)
    self._leading = leading
    self._title = title
    self._title_index = #leading
    self._title_max = title_max
    self._option_font = option_font

    local trailing = make_trailing(item, checked, option_font)
    self._trailing = trailing
    self._trailing_kind = trailing_kind(item, checked)

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
    self._trailing_slot = row[2]

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
                        h = Screen:scaleBySize(2),
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

--- Flip a check, radio, or label without rebuilding the row chrome.
-- Returns true when the label, check, radio, or enabled state changed.
function MenuItemCard:updateState()
    local item = self.item or {}
    local option_font = self._option_font or Settings.getOptionFontSize()
    local enabled = item_enabled(item)
    local checked = item_checked(item)
    local text = item_text(item)
    local fg = enabled and Blitbuffer.COLOR_BLACK or Settings.getDisabledFg()
    local changed = self.enabled ~= enabled
    if self._title and (self._title.text ~= text or self._title.fgcolor ~= fg) then
        changed = true
        local updated = TextWidget:new{
            text = text,
            face = row_face(item, option_font),
            fgcolor = fg,
            max_width = self._title_max,
        }
        if self._leading and self._title_index then
            self._leading[self._title_index] = updated
        end
        if self._title.free then
            self._title:free()
        end
        self._title = updated
        if self._leading and self._leading.resetLayout then
            self._leading:resetLayout()
        end
    end
    local kind = trailing_kind(item, checked)
    if kind ~= self._trailing_kind then
        changed = true
        local toggle_flip = kind:sub(1, 6) == "toggle" and self._trailing_kind
            and self._trailing_kind:sub(1, 6) == "toggle"
        local radio_flip = kind:sub(1, 5) == "radio" and self._trailing_kind
            and self._trailing_kind:sub(1, 5) == "radio"
        if toggle_flip and self._trailing then
            self._trailing.checked = checked and true or false
        elseif radio_flip and self._trailing and self._trailing.setText then
            self._trailing:setText(checked and "◉" or "○")
        else
            local trailing = make_trailing(item, checked, option_font)
            if self._trailing and self._trailing.free then
                self._trailing:free()
            end
            self._trailing = trailing
            if self._trailing_slot then
                self._trailing_slot[1] = trailing
                if self._trailing_slot.resetLayout then
                    self._trailing_slot:resetLayout()
                end
            end
        end
        self._trailing_kind = kind
    end
    self.enabled = enabled
    return changed
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
