--[[--
Typography tab: font size, margins, line spacing.
@module modern_menu.ui.tabs.type
--]]

local Device = require("device")
local Font = require("ui/font")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen
local _ = require("gettext")

local Slider = require("widgets/slider")
local ToggleCard = require("widgets/toggle_card")

local TypeTab = {}

local function get_document(parent)
    local ui = parent and parent.ui
    return ui and ui.document or nil
end

local function get_font_size(doc)
    if not doc then return 22 end
    if doc.getFontSize then
        return doc:getFontSize() or 22
    end
    if doc.configurable and doc.configurable.font_size then
        return doc.configurable.font_size
    end
    return 22
end

function TypeTab:build(parent)
    local width = Screen:getWidth() - Screen:scaleBySize(32)
    local doc = get_document(parent)
    local content = VerticalGroup:new{ align = "left" }

    if not doc then
        table.insert(content, TextWidget:new{
            text = _("Open a document to adjust typography."),
            face = require("settings").face(18),
            max_width = width,
        })
        return content
    end

    local font_size = get_font_size(doc)
    local size_slider = Slider:new{
        title = _("Font size"),
        value = font_size,
        value_min = 12,
        value_max = 50,
        value_step = 1,
        width = width,
        show_parent = parent,
        callback = function(val)
            if doc.setFontSize then
                doc:setFontSize(val)
            elseif parent.ui and parent.ui.font then
                -- ReaderFont module path used by some builds
                if parent.ui.font.onSetFontSize then
                    parent.ui.font:onSetFontSize(val)
                end
            end
            if parent.ui and parent.ui.paging then
                -- Soft refresh of page view without full UI churn
            end
        end,
    }
    table.insert(content, size_slider)
    table.insert(content, VerticalSpan:new{ width = Size.span.vertical_default })

    local line_spacing = 100
    if doc.configurable and doc.configurable.line_space_percent then
        line_spacing = doc.configurable.line_space_percent
    end

    local spacing = Slider:new{
        title = _("Line spacing (%)"),
        value = line_spacing,
        value_min = 50,
        value_max = 200,
        value_step = 5,
        width = width,
        show_parent = parent,
        callback = function(val)
            if doc.setInterlineSpacePercent then
                doc:setInterlineSpacePercent(val)
            elseif doc.configurable then
                doc.configurable.line_space_percent = val
            end
        end,
    }
    table.insert(content, spacing)
    table.insert(content, VerticalSpan:new{ width = Size.span.vertical_default })

    local margin = 10
    if doc.configurable and doc.configurable.h_page_margins then
        local m = doc.configurable.h_page_margins
        if type(m) == "table" then
            margin = m[1] or margin
        end
    end

    local margins = Slider:new{
        title = _("Horizontal margins"),
        value = margin,
        value_min = 0,
        value_max = 50,
        value_step = 1,
        width = width,
        show_parent = parent,
        callback = function(val)
            if doc.setPageMargins then
                doc:setPageMargins(val, val, val, val)
            elseif doc.configurable then
                doc.configurable.h_page_margins = { val, val }
            end
        end,
    }
    table.insert(content, margins)
    table.insert(content, VerticalSpan:new{ width = Size.span.vertical_default })

    local embedded = ToggleCard:new{
        title = _("Embedded styles"),
        subtitle = _("Honor publisher CSS when available"),
        checked = (doc.configurable and doc.configurable.embedded_css == 1) or false,
        width = width,
        show_parent = parent,
        callback = function(checked)
            if doc.configurable then
                doc.configurable.embedded_css = checked and 1 or 0
            end
            if doc.setEmbeddedStyleSheet then
                doc:setEmbeddedStyleSheet(checked and 1 or 0)
            end
        end,
    }
    table.insert(content, embedded)

    return content
end

return TypeTab
