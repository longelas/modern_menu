--[[--
Modern full-screen replacement for KOReader TouchMenu.
Kobo-inspired chrome: clean header, underline tabs, scrollable list.

Exposes TouchMenu-compatible closeMenu()/updateItems() for menu callbacks.
@module modern_menu.ui.menu_shell
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
local Input = Device.input
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalScrollBar = require("ui/widget/verticalscrollbar")
local VerticalSpan = require("ui/widget/verticalspan")
local logger = require("logger")
local Screen = Device.screen
local _ = require("gettext")

local QuickMenuHost = require("ui/quickmenu_host")
local ShortcutsHost = require("ui/shortcuts_host")
local TabBar = require("ui/tab_bar")
local Breadcrumb = require("widgets/breadcrumb")
local MenuItemCard = require("widgets/menu_item_card")
local Settings = require("settings")
local StatusBar = require("widgets/status_bar")

local ICON_TITLES = {
    ["appbar.navigation"] = _("Navigate"),
    ["appbar.typeset"] = _("Typography"),
    ["appbar.settings"] = _("Settings"),
    ["appbar.tools"] = _("Tools"),
    ["appbar.search"] = _("Search"),
    ["appbar.filebrowser"] = _("Files"),
    ["appbar.menu"] = _("Home"),
    ["appbar.filemanager"] = _("Files"),
    ["appbar.plus"] = _("New"),
    ["appbar.bookshelf"] = _("Library"),
}

local ID_TITLES = {
    navi = _("Navigate"),
    typeset = _("Typography"),
    setting = _("Settings"),
    tools = _("Tools"),
    search = _("Search"),
    filemanager = _("Files"),
    filemanager_settings = _("Library"),
    main = _("Home"),
    plus_menu = _("New"),
    quick_menu_tab = _("Quick menu"),
    exit_tab = _("Exit"),
    neo_quicksettings = _("Neo Quick"),
    _sui_qs_panel = _("Simple UI"),
    kobold_home = _("Kobold"),
}

local ID_TAB_LABELS = {
    navi = _("Nav"),
    typeset = _("Type"),
    setting = _("Settings"),
    tools = _("Tools"),
    search = _("Search"),
    filemanager = _("Files"),
    filemanager_settings = _("Library"),
    main = _("Home"),
    plus_menu = _("New"),
    quick_menu_tab = _("Quick"),
    exit_tab = _("Exit"),
    neo_quicksettings = _("Neo"),
    _sui_qs_panel = _("Simple"),
    kobold_home = _("Kobold"),
}

local ModernMenuShell = InputContainer:extend{
    name = "modern_menu_shell",
    modal = true,
    covers_fullscreen = true,
    tab_item_table = nil,
    last_index = 1,
    show_parent = nil,
    close_callback = nil,
    touch_menu_callback = nil,
    ui = nil,
    item_table = nil,
    item_table_stack = nil,
    title_stack = nil,
    cropping_widget = nil, -- required by UIManager for ScrollableContainer
}

function ModernMenuShell:init()
    self.dimen = Geom:new{
        x = 0, y = 0,
        w = Screen:getWidth(),
        h = Screen:getHeight(),
    }
    self.show_parent = self.show_parent or self
    self.tab_item_table = self.tab_item_table or {}
    self.item_table_stack = {}
    self.title_stack = {}
    self.side_margin = Screen:scaleBySize(30)
    self.chrome_h = Screen:scaleBySize(56)
    self.last_index = self.last_index or 1
    if self.last_index < 1 then self.last_index = 1 end
    if self.last_index > #self.tab_item_table then
        self.last_index = math.max(1, #self.tab_item_table)
    end

    local dirty_parent = self.show_parent or self
    local content_w = self.dimen.w
    -- Reserve v-scrollbar gutter so list width never triggers a fake h-scrollbar
    self.scrollbar_gutter = ScrollableContainer:getScrollbarWidth()
    self.list_content_w = content_w - self.scrollbar_gutter

    -- Title row. Close lives in the status bar, top right, with the other
    -- status icons. The back chevron is only here once a submenu is open,
    -- and it uses the same type as the title so it sits on the baseline.
    self._back_icon = TextWidget:new{
        text = "‹",
        face = Settings.face(18, "cfont"),
        fgcolor = Blitbuffer.COLOR_BLACK,
    }
    self._back_placeholder = HorizontalSpan:new{ width = 0 }
    local back_w = self._back_icon:getSize().w
    local chrome_btn_h = math.max(self._back_icon:getSize().h, Screen:scaleBySize(22))
    -- The title starts on the same inset as the clock.
    local chrome_edge_pad = self.side_margin
    local chrome_gap = Screen:scaleBySize(8)
    self._chrome_icon_px = back_w
    self._chrome_gap = chrome_gap
    self._chrome_edge_pad = chrome_edge_pad
    local title_w = content_w - chrome_edge_pad * 2 - back_w - chrome_gap
    self._title_w = math.max(0, title_w)

    self.breadcrumb = Breadcrumb:new{
        crumbs = {},
        width = math.max(0, title_w),
        show_parent = dirty_parent,
        on_select = function(index)
            self:goToCrumb(index)
        end,
    }

    self.header_row = HorizontalGroup:new{
        align = "center",
        self._back_placeholder,
        HorizontalSpan:new{ width = 0 },
        LeftContainer:new{
            dimen = Geom:new{
                w = math.max(0, title_w),
                h = chrome_btn_h,
            },
            self.breadcrumb,
        },
    }
    self.header = FrameContainer:new{
        bordersize = 0,
        padding_top = Screen:scaleBySize(2),
        padding_bottom = Screen:scaleBySize(2),
        padding_left = chrome_edge_pad,
        padding_right = chrome_edge_pad,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        width = content_w,
        self.header_row,
    }
    self:_applyChromeFont()

    self.tab_defs = self:_buildTabDefs()
    self.tab_bar = TabBar:new{
        tabs = self.tab_defs,
        selected = self.last_index,
        width = content_w,
        -- Same inset as the clock, the title, and the close mark.
        side_margin = self.side_margin,
        show_parent = dirty_parent,
        on_change = function(_, index)
            self:switchMenuTab(index)
        end,
        -- Quick Menu opens its settings from a hold on the tab icon.
        on_hold = function(_, index)
            local tab = self.tab_item_table[index]
            if tab and tab.id == "exit_tab" then
                return self:_holdExitTab()
            end
            if not tab or type(tab.hold_callback) ~= "function" then
                return false
            end
            local ok, err = pcall(tab.hold_callback)
            if not ok then
                logger.warn("modern_menu: tab hold failed: " .. tostring(err))
            end
            return true
        end,
    }

    -- Light rule under the tabs, on the same inset as the clock and close mark.
    -- A gap above the line keeps the tab labels clear of it.
    local rule_w = content_w - 2 * self.side_margin
    local rule_line_h = Screen:scaleBySize(2)
    self._tab_rule_gap = Screen:scaleBySize(6)
    self.tab_rule_line = LineWidget:new{
        background = Settings.getRuleFg(),
        dimen = Geom:new{
            w = rule_w,
            h = rule_line_h,
        },
    }
    self.tab_rule = VerticalGroup:new{
        align = "left",
        VerticalSpan:new{ width = self._tab_rule_gap },
        HorizontalGroup:new{
            HorizontalSpan:new{ width = self.side_margin },
            self.tab_rule_line,
        },
        VerticalSpan:new{ width = Screen:scaleBySize(6) },
    }

    self.status_bar = StatusBar.make{
        ui = self.ui,
        show_parent = dirty_parent,
        width = content_w,
        side_margin = self.side_margin,
        on_dismiss = function()
            self:closeMenu()
        end,
        show_close = true,
    }
    self.status_h = self.status_bar.height

    -- Fixed list viewport under chrome; scroll when items overflow
    local header_h = chrome_btn_h + Screen:scaleBySize(4)
    self._header_h = header_h
    local tabs_h = self.tab_bar.height + Screen:scaleBySize(4)
    local rule_h = Screen:scaleBySize(2) + self._tab_rule_gap + Screen:scaleBySize(6)
    local list_h = math.max(
        Screen:scaleBySize(120),
        self.dimen.h - self.status_h - header_h - tabs_h - rule_h - Screen:scaleBySize(4)
    )
    -- Scroll height before an optional Quick Menu footer is subtracted.
    self.list_h_base = list_h
    self.list_dimen = Geom:new{
        w = content_w,
        h = list_h,
    }

    self.item_table = self.tab_item_table[self.last_index] or {}
    self.list_group = VerticalGroup:new{ align = "left" }

    self.scroll_container = ScrollableContainer:new{
        dimen = self.list_dimen,
        show_parent = dirty_parent,
        swipe_full_view = true,
        -- Let menu rows receive long-press (e.g. book-specific style tweak editor)
        ignore_events = { "hold", "hold_pan", "hold_release" },
        self.list_group,
    }
    -- Vertical-only scrolling; gray scrollbar to match toggles
    self.scroll_container.initState = function(sc)
        local content_size = sc[1]:getSize()
        sc._max_scroll_offset_x = 0
        sc._max_scroll_offset_y = math.max(0, content_size.h - sc.dimen.h)
        sc._h_scroll_bar = nil
        sc._crop_dx = 0
        if sc._max_scroll_offset_y == 0 then
            sc._is_scrollable = false
            sc._v_scroll_bar = nil
            sc._crop_w = sc.dimen.w
            sc._crop_h = sc.dimen.h
        else
            sc._is_scrollable = true
            local scroll_ink = Settings.getScrollbarFg()
            sc._v_scroll_bar = VerticalScrollBar:new{
                width = sc.scroll_bar_width,
                height = sc.dimen.h,
                bordercolor = scroll_ink,
                rectcolor = scroll_ink,
                scroll_callback = function(ratio)
                    sc:scrollToRatio(nil, ratio)
                end,
            }
            sc._crop_w = sc.dimen.w - 3 * sc.scroll_bar_width
            sc._crop_h = sc.dimen.h
            if sc.step_scroll_grid_func then
                sc.step_scroll_grid = sc.step_scroll_grid_func()
            end
            if sc.step_scroll_grid then
                sc:_scrollBy(0, 0, true)
            end
            sc:_hideTruncatedGridItemsIfRequested()
            sc:_updateScrollBars()
        end
    end
    self.cropping_widget = self.scroll_container
    -- Quick Menu footer sits under the list and is empty on other tabs.
    self.qm_footer_slot = VerticalGroup:new{ align = "center" }
    -- Bottom edge of a short sheet. Full screen hides the gap and the line.
    self._sheet_edge_gap = Screen:scaleBySize(10)
    self._sheet_edge_h = math.max(Size.line.thick, Screen:scaleBySize(3))
    self.sheet_edge_gap = VerticalSpan:new{ width = 0 }
    self.sheet_edge = LineWidget:new{
        -- Always black so the end of the sheet stays obvious on a light page.
        background = Blitbuffer.COLOR_BLACK,
        dimen = Geom:new{
            w = content_w,
            h = 0,
        },
    }

    self.panel = FrameContainer:new{
        bordersize = 0,
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        width = self.dimen.w,
        height = self.dimen.h,
        VerticalGroup:new{
            align = "left",
            self.status_bar,
            self.header,
            self.tab_bar,
            self.tab_rule,
            self.scroll_container,
            self.qm_footer_slot,
            self.sheet_edge_gap,
            self.sheet_edge,
        },
    }

    -- Wide hit target for the back chevron. Close is a status-bar icon.
    local chrome_zone = chrome_edge_pad + back_w + chrome_gap + Screen:scaleBySize(16)
    self._chrome_zone = chrome_zone
    local chrome_top = self.status_h or 0
    self.chrome_h = header_h
    local chrome_dimen = Geom:new{
        x = 0, y = chrome_top,
        w = self.dimen.w,
        h = self.chrome_h,
    }
    self.chrome_hit = InputContainer:new{
        dimen = chrome_dimen,
        skip_paint = true,
        ges_events = {
            TapChromeHit = {
                GestureRange:new{
                    ges = "tap",
                    range = chrome_dimen,
                },
            },
        },
    }
    -- Gesture handlers are called as (self, args, ges). The gesture is third.
    self.chrome_hit.onTapChromeHit = function(_, _, ges)
        if not ges or not ges.pos then
            return false
        end
        if ges.pos.y < chrome_top or ges.pos.y > chrome_top + self.chrome_h then
            return false
        end
        if #self.item_table_stack > 0 and ges.pos.x <= chrome_zone then
            self:backToUpperMenu()
            return true
        end
        return false
    end

    -- Full-screen catcher under the sheet. A tap below a short menu closes it.
    -- Inside the sheet this returns false so the rows still receive the tap.
    -- Full-screen height has no outside area, so those taps stay with the rows.
    self._sheet_h = self.dimen.h
    local dismiss_range = Geom:new{
        x = 0, y = 0,
        w = self.dimen.w,
        h = self.dimen.h,
    }
    self.dismiss_hit = InputContainer:new{
        dimen = dismiss_range,
        skip_paint = true,
        ges_events = {
            TapDismissMenu = {
                GestureRange:new{
                    ges = "tap",
                    range = dismiss_range,
                },
            },
        },
    }
    -- Gesture handlers are (arg, ges). The gesture is the second argument.
    self.dismiss_hit.onTapDismissMenu = function(_, _, ges)
        if Settings.getMenuHeightMode() == Settings.MENU_HEIGHT_FULL then
            return false
        end
        local sheet = self._sheet_h or self.dimen.h
        if not ges or not ges.pos or ges.pos.y < sheet then
            return false
        end
        self:closeMenu()
        return true
    end

    -- dismiss_hit first so a tap below the sheet closes before the rows see it.
    -- chrome_hit stays ahead of the panel so the corner zones win over the glyphs.
    self[1] = OverlapGroup:new{
        dimen = self.dimen,
        allow_mirroring = false,
        self.dismiss_hit,
        self.chrome_hit,
        self.panel,
    }

    self:_rebuildContent()

    if Device:hasKeys() then
        self.key_events = {
            Close = { { "Menu" } },
            Back = { { Input.group.Back } },
        }
    end
end

function ModernMenuShell:_tabTitle(tab, index, for_strip)
    if not tab then return tostring(index) end
    if for_strip then
        if tab.id and ID_TAB_LABELS[tab.id] then return ID_TAB_LABELS[tab.id] end
        if tab.icon and ICON_TITLES[tab.icon] then
            local full = ICON_TITLES[tab.icon]
            if full == _("Typography") then return _("Type") end
            if full == _("Navigate") then return _("Nav") end
            return full
        end
    end
    if tab.text and tab.text ~= "" then return tab.text end
    if tab.id and ID_TITLES[tab.id] then return ID_TITLES[tab.id] end
    if tab.icon and ICON_TITLES[tab.icon] then return ICON_TITLES[tab.icon] end
    if tab.icon then
        local short = tab.icon:match("([^.]+)$") or tab.icon
        return short:gsub("^%l", string.upper)
    end
    return _("Menu")
end

function ModernMenuShell.tabCaption(tab, index, for_strip)
    return ModernMenuShell._tabTitle(ModernMenuShell, tab, index, for_strip)
end

function ModernMenuShell:_buildTabDefs()
    local defs = {}
    for i, tab in ipairs(self.tab_item_table) do
        defs[#defs + 1] = {
            id = tab.id or ("tab_" .. i),
            title = self:_tabTitle(tab, i, true),
            icon = tab.icon,
        }
    end
    if #defs == 0 then
        defs[1] = { id = "empty", title = _("Menu") }
    end
    return defs
end

function ModernMenuShell:_breadcrumbCrumbs()
    local tab = self.tab_item_table[self.last_index]
    local crumbs = { self:_tabTitle(tab, self.last_index, false) }
    for _, name in ipairs(self.title_stack) do
        crumbs[#crumbs + 1] = name
    end
    return crumbs
end

function ModernMenuShell:goToCrumb(index)
    if not index or index < 1 then
        return
    end
    -- crumb 1 = tab root; crumb k maps to title_stack depth k-1
    local target_depth = index - 1
    while #self.title_stack > target_depth do
        self.item_table = table.remove(self.item_table_stack)
        table.remove(self.title_stack)
    end
    local pick = self._shortcut_pick
    if pick and pick.nav_path then
        while #pick.nav_path > #self.title_stack do
            table.remove(pick.nav_path)
        end
    end
    self:refresh()
end

function ModernMenuShell:_visibleItems()
    local items = {}
    for _, item in ipairs(self.item_table or {}) do
        if item and item.text ~= "KOMenu:separator" then
            items[#items + 1] = item
        end
    end
    return items
end

function ModernMenuShell:_dirtyTarget()
    return self.show_parent or self
end

function ModernMenuShell:_clearGroup(group)
    if not group then
        return
    end
    if group.clear then
        group:clear()
    else
        for i = #group, 1, -1 do
            group[i] = nil
        end
    end
end

function ModernMenuShell:_emptyNotice(text)
    return FrameContainer:new{
        bordersize = 0,
        padding = self.side_margin,
        background = Blitbuffer.COLOR_WHITE,
        TextWidget:new{
            text = text,
            face = Settings.face(18),
            fgcolor = Settings.getMutedFg(),
        },
    }
end

--- Status bar, title, tabs, and the rule under them.
function ModernMenuShell:_chromeHeight()
    local header_h = self._header_h or 0
    local tabs_h = (self.tab_bar and self.tab_bar.height or 0) + Screen:scaleBySize(4)
    local rule_h = Screen:scaleBySize(2) + (self._tab_rule_gap or Screen:scaleBySize(6)) + Screen:scaleBySize(6)
    return (self.status_h or 0) + header_h + tabs_h + rule_h + Screen:scaleBySize(4)
end

--- White sheet height. Full screen, a percentage of the screen, or the rows.
-- The list scrolls when the rows are taller than the sheet. A short sheet
-- stays at the top; a tap below it closes the menu.
function ModernMenuShell:_applySheetHeight(footer_h)
    footer_h = footer_h or 0
    local screen_h = (self.dimen and self.dimen.h) or Screen:getHeight()
    local chrome_h = self:_chromeHeight()
    local mode = Settings.getMenuHeightMode()
    local edge_h = 0
    local edge_gap = 0
    local edge_line = 0
    if mode ~= Settings.MENU_HEIGHT_FULL then
        edge_gap = self._sheet_edge_gap or 0
        edge_line = self._sheet_edge_h or 0
        edge_h = edge_gap + edge_line
    end
    if self.sheet_edge_gap then
        self.sheet_edge_gap.width = edge_gap
    end
    if self.sheet_edge and self.sheet_edge.dimen then
        self.sheet_edge.dimen.h = edge_line
        self.sheet_edge.background = Blitbuffer.COLOR_BLACK
    end
    local min_list = Screen:scaleBySize(mode == Settings.MENU_HEIGHT_FULL and 120 or 80)
    local max_list = math.max(min_list, screen_h - chrome_h - footer_h - edge_h)
    local list_h = max_list
    if mode == Settings.MENU_HEIGHT_PERCENT then
        local sheet = math.floor(screen_h * Settings.getMenuHeightPercent() / 100)
        sheet = math.max(chrome_h + min_list + edge_h, math.min(screen_h, sheet))
        list_h = math.max(min_list, sheet - chrome_h - footer_h - edge_h)
    elseif mode == Settings.MENU_HEIGHT_CONTENT then
        local content_h = 0
        local body = self.scroll_container and self.scroll_container[1]
        if body and body.getSize then
            local size = body:getSize()
            content_h = size and size.h or 0
        end
        if content_h < 1 then
            content_h = min_list
        end
        list_h = math.min(max_list, math.max(min_list, content_h))
    end
    local sheet_h = math.min(screen_h, chrome_h + list_h + footer_h + edge_h)
    list_h = math.max(1, sheet_h - chrome_h - footer_h - edge_h)
    self._sheet_h = sheet_h
    if self.list_dimen then
        self.list_dimen.h = list_h
    end
    if self.scroll_container and self.scroll_container.dimen then
        self.scroll_container.dimen.h = list_h
    end
    if self.panel then
        self.panel.height = sheet_h
        if self.panel.dimen then
            self.panel.dimen.h = sheet_h
        end
    end
end

function ModernMenuShell:_dirtyMenu()
    -- A short sheet must repaint the app underneath the area it no longer covers.
    if Settings.getMenuHeightMode() == Settings.MENU_HEIGHT_FULL then
        UIManager:setDirty(self:_dirtyTarget(), "ui")
    else
        UIManager:setDirty("all", "ui")
    end
end

function ModernMenuShell:_rebuildContent()
    self:_clearGroup(self.list_group)
    self:_clearGroup(self.qm_footer_slot)

    local panel_widget, footer_widget, panel_err
    local ok_qm, err_qm = pcall(function()
        panel_widget, footer_widget, panel_err = QuickMenuHost.fill(self)
    end)
    if not ok_qm then
        logger.warn("modern_menu: quickmenu host failed: " .. tostring(err_qm))
        panel_widget, footer_widget, panel_err = nil, nil, err_qm
    end

    -- Brightness and warmth sit under the button grid in Neo's panel. This
    -- shell's list is shorter than stock TouchMenu, so those rows were
    -- cropped away. They are lifted out and pinned under the scroller.
    local pinned = panel_widget and self._qm_pinned_sliders
    if pinned and self.qm_footer_slot then
        table.insert(self.qm_footer_slot, pinned)
    end
    if footer_widget and self.qm_footer_slot then
        local footer_size = footer_widget:getSize()
        local footer_box = CenterContainer:new{
            dimen = Geom:new{
                w = self.list_content_w or self.dimen.w,
                h = footer_size and footer_size.h or 0,
            },
            footer_widget,
        }
        table.insert(self.qm_footer_slot, VerticalSpan:new{ width = Size.span.vertical_default })
        table.insert(self.qm_footer_slot, footer_box)
    end

    -- Shortcuts Toolbar paints this row into stock TouchMenu. Pin the same
    -- back button and icons under the reader list when that plugin is on.
    local shortcuts_bar
    local ok_sc, sc_result = pcall(function()
        return ShortcutsHost.build(self)
    end)
    if not ok_sc then
        logger.warn("modern_menu: shortcuts toolbar host failed: " .. tostring(sc_result))
    else
        shortcuts_bar = sc_result
    end
    if shortcuts_bar and self.qm_footer_slot then
        table.insert(self.qm_footer_slot, LineWidget:new{
            background = Settings.getRuleFg(),
            dimen = Geom:new{
                w = self.dimen.w,
                h = math.max(Size.line.thick, Screen:scaleBySize(1)),
            },
        })
        -- The row already pads itself, and the black edge has a gap below.
        -- Match that gap above so the icons sit in the middle of the band.
        table.insert(self.qm_footer_slot, VerticalSpan:new{
            width = self._sheet_edge_gap or 0,
        })
        table.insert(self.qm_footer_slot, shortcuts_bar)
    end

    local footer_h = 0
    if self.qm_footer_slot and self.qm_footer_slot[1] then
        local slot_size = self.qm_footer_slot:getSize()
        footer_h = slot_size and slot_size.h or 0
    end
    self._pending_footer_h = footer_h

    local content = self.list_group
    if panel_widget then
        content = panel_widget
    else
        local tab = self.tab_item_table and self.tab_item_table[self.last_index]
        local nested = self.item_table_stack and #self.item_table_stack > 0
        if tab and tab.panel and not nested then
            table.insert(self.list_group, self:_emptyNotice(QuickMenuHost.failureMessage()))
        else
            local items = self:_visibleItems()
            -- Leave room for the v-scrollbar so content never overflows horizontally
            local width = self.list_content_w or (self.dimen.w - (self.scrollbar_gutter or 0))
            local dirty_parent = self:_dirtyTarget()

            if #items == 0 then
                table.insert(self.list_group, self:_emptyNotice(_("No items in this menu.")))
            else
                -- Alternate white / light-gray by stock category (item.separator ends a group)
                local stripe = 0
                for i, item in ipairs(items) do
                    table.insert(self.list_group, MenuItemCard:new{
                        item = item,
                        width = width,
                        side_margin = self.side_margin,
                        show_parent = dirty_parent,
                        menu = self,
                        index = i,
                        show_separator = i < #items,
                        stripe = stripe,
                    })
                    if item.separator then
                        stripe = 1 - stripe
                    end
                end
            end
        end
    end

    if self._shortcut_pick then
        local bars = ShortcutsHost.pickBars(self)
        if bars then
            local wrapped = VerticalGroup:new{ align = "left" }
            table.insert(wrapped, content)
            table.insert(wrapped, bars)
            content = wrapped
        end
    end

    -- Reset scroll state so the next paint recomputes overflow + scrollbar.
    -- A live _bb would blit the previous button glyphs over the new panel.
    self.scroll_container[1] = content
    -- Size the sheet after the rows exist so "fit content" can measure them.
    self:_applySheetHeight(self._pending_footer_h or 0)
    if self.scroll_container.reset then
        self.scroll_container:reset()
    else
        self.scroll_container._scroll_offset_x = 0
        self.scroll_container._scroll_offset_y = 0
        if self.scroll_container._bb then
            self.scroll_container._bb:free()
            self.scroll_container._bb = nil
        end
        self.scroll_container._is_scrollable = nil
    end
    self.scroll_container._v_scroll_bar = nil
    self.scroll_container._h_scroll_bar = nil

    local column = self.panel and self.panel[1]
    if column and column.resetLayout then
        column:resetLayout()
    end

    if self.breadcrumb then
        self.breadcrumb:setCrumbs(self:_breadcrumbCrumbs())
    end
end

--- Rebuild the Quick Menu body without reloading tab chrome.
-- A toggle only needs new button glyphs. Reloading the tab bar first
-- can paint the shell while those glyphs still show the previous state.
function ModernMenuShell:refreshQuickMenu()
    self:_rebuildContent()
    self:_dirtyMenu()
end

function ModernMenuShell:_applyChromeFont()
    -- The chevron belongs to a submenu. The root title starts at the left inset.
    if not self.header_row then
        return
    end
    local nested = #(self.item_table_stack or {}) > 0
    self.header_row[1] = nested and self._back_icon or self._back_placeholder
    if self.header_row[2] then
        self.header_row[2].width = nested and (self._chrome_gap or 0) or 0
    end
    -- The title slot grows into the chevron's space while the menu is at its root.
    local title_slot = self.header_row[3]
    if title_slot and title_slot.dimen and self._title_w then
        local extra = nested and 0 or ((self._chrome_icon_px or 0) + (self._chrome_gap or 0))
        title_slot.dimen.w = self._title_w + extra
    end
    -- The row caches its offsets. Without this, the title stays where it
    -- was at the root and draws underneath the chevron.
    if self.header_row.resetLayout then
        self.header_row:resetLayout()
    end
end

function ModernMenuShell:refresh()
    -- A shortcut tap closes first, then runs the action. Rebuilding here
    -- would free that icon while its handler is still on the stack.
    if self._closing then
        return
    end
    -- Tab chrome caches sizes at init; reload so tab font/icon settings
    -- refresh instantly the same way option rows do.
    if self.tab_bar and self.tab_bar.reloadFromSettings then
        local old_h = self.tab_bar.height
        self.tab_bar:reloadFromSettings()
        local delta = self.tab_bar.height - old_h
        if delta ~= 0 and self.list_h_base then
            self.list_h_base = math.max(Screen:scaleBySize(120), self.list_h_base - delta)
        end
    end
    if self.tab_rule_line then
        self.tab_rule_line.background = Settings.getRuleFg()
    end
    self:_applyChromeFont()
    if self.status_bar and self.status_bar.refresh then
        self.status_bar:refresh()
    end
    self:_rebuildContent()
    self:_dirtyMenu()
end

--- Drop the window now so UIManager:sendEvent can reach the book.
-- Widget teardown stays on the caller: freeing the tree mid-tap would
-- release the shortcut icon while its handler is still running.
function ModernMenuShell:unlinkFromStack()
    local parent = self.show_parent or self
    local stack = UIManager._window_stack
    if stack then
        for i = #stack, 1, -1 do
            if stack[i].widget == parent then
                if UIManager._dirty then
                    UIManager._dirty[parent] = nil
                end
                table.remove(stack, i)
            end
        end
    end
    return parent
end

function ModernMenuShell:closeMenu()
    if self._closing then
        return true
    end
    -- Closing mid-pick is the same as Cancel: return to the shortcut editor.
    local cancel_pick
    if self._shortcut_pick then
        cancel_pick = self._shortcut_pick.on_cancel
        self._shortcut_pick = nil
    end
    self._closing = true

    local cb = self.close_callback
    self.close_callback = nil
    local parent = self:unlinkFromStack()

    -- Shortcut and menu actions call closeMenu(), then UIManager:sendEvent.
    -- sendEvent only reaches the book while this window is no longer on top.
    -- Stock TouchMenu removes it immediately. Freeing the widgets here would
    -- run during the tap, so drop the window now and finish teardown next tick.
    UIManager:nextTick(function()
        if cb then
            cb()
        else
            UIManager:close(parent, "ui")
        end
        UIManager:setDirty("all", "ui")
    end)
    if cancel_pick then
        cancel_pick()
    end
    return true
end

function ModernMenuShell:onCloseWidget()
    if self.status_bar and self.status_bar._unscheduleClock then
        self.status_bar:_unscheduleClock()
    end
end

function ModernMenuShell:updateItems()
    self:refresh()
end

--- Leave the open book and land in the file browser.
-- Quick Menu's exit-tab callback closes over whichever menu first created
-- the tab, so from the reader it often no-ops. This uses the menu that is
-- actually open.
function ModernMenuShell:_goToFileManager()
    local ui = self.ui
    if not (ui and ui.document and ui.onClose and ui.showFileManager) then
        self:closeMenu()
        return
    end
    local file = ui.document.file
    if self._closing then
        return
    end
    self._closing = true
    local cb = self.close_callback
    self.close_callback = nil
    UIManager:nextTick(function()
        if cb then
            pcall(cb)
        end
        pcall(function()
            ui:onClose()
            if file then
                ui:showFileManager(file)
            end
        end)
        UIManager:setDirty("all", "ui")
    end)
end

function ModernMenuShell:_holdExitTab()
    local ConfirmBox = require("ui/widget/confirmbox")
    local ui = self.ui
    local in_reader = ui and ui.document and ui.showFileManager
    local file = in_reader and ui.document.file
    self:closeMenu()
    if in_reader then
        UIManager:show(ConfirmBox:new{
            text = _("Are you sure you want to exit book ?"),
            ok_text = _("Exit"),
            ok_callback = function()
                ui:onClose()
                if file then
                    ui:showFileManager(file)
                end
            end,
        })
    else
        UIManager:show(ConfirmBox:new{
            text = _("Are you sure you want to exit KOReader ?"),
            ok_text = _("Exit"),
            ok_callback = function()
                UIManager:broadcastEvent(Event:new("Exit"))
            end,
        })
    end
    return true
end

function ModernMenuShell:switchMenuTab(tab_num)
    if self.touch_menu_callback then
        self.touch_menu_callback()
    end
    local tab = self.tab_item_table[tab_num]
    if not tab then return end
    -- Recording a shortcut should not leave the book or run a tab action.
    local pick = self._shortcut_pick
    if pick and (tab.id == "exit_tab" or tab.id == "filemanager"
            or (tab.callback and tab.remember == false)) then
        return
    end

    -- Exit tab (and the file-browser tab it replaces) must use this menu.
    -- A tap in the reader leaves the book for the file browser.
    -- A tap in the file browser just dismisses the menu; hold quits KOReader.
    if tab.id == "exit_tab" or tab.id == "filemanager" then
        if tab.id == "exit_tab" and not (self.ui and self.ui.document) then
            self:closeMenu()
        else
            self:_goToFileManager()
        end
        return
    end

    -- Action tabs (e.g. Files → leave reader): run callback and stop.
    -- remember=false means the tab is not a browsable menu page.
    if tab.callback then
        tab.callback()
        if tab.remember == false then
            return
        end
    end

    if pick then
        pick.tab_index = tab_num
        pick.nav_path = {}
    end
    self.last_index = tab_num
    self.item_table_stack = {}
    self.title_stack = {}
    self.item_table = tab
    if self.tab_bar and self.tab_bar.selected ~= tab_num then
        self.tab_bar:setSelected(tab_num, true)
    end
    self:refresh()
end

function ModernMenuShell:backToUpperMenu(no_close)
    local pick = self._shortcut_pick
    if pick then
        if #self.item_table_stack > 0 then
            if pick.nav_path and #pick.nav_path > 0 then
                table.remove(pick.nav_path)
            end
        else
            ShortcutsHost.finishPick(self, "cancel")
        end
    end
    if #self.item_table_stack > 0 then
        self.item_table = table.remove(self.item_table_stack)
        table.remove(self.title_stack)
        self:refresh()
        return true
    end
    if not no_close then
        self:closeMenu()
    end
    return true
end

function ModernMenuShell:onMenuSelect(item)
    if self._shortcut_pick and not self._shortcut_pick._entering then
        if ShortcutsHost.onPickSelect(self, item) then
            return true
        end
    end
    if self.touch_menu_callback then
        self.touch_menu_callback()
    end
    if not item then return true end

    if item.tap_input or item.tap_input_func then
        if not item.keep_menu_open then
            self:closeMenu()
        end
        local input = item.tap_input or (item.tap_input_func and item.tap_input_func())
        if input and self.onInput then
            self:onInput(input)
        end
        return true
    end

    local sub_item_table = item.sub_item_table_func and item.sub_item_table_func() or item.sub_item_table
    if sub_item_table then
        if #sub_item_table > 0 then
            table.insert(self.item_table_stack, self.item_table)
            local title = item.text_func and item.text_func() or item.text or item.title or _("Menu")
            title = title:gsub("%s*:%s*.*$", "")
            table.insert(self.title_stack, title)
            self.item_table = sub_item_table
            self:refresh()
        end
        return true
    end

    local callback = item.callback_func and item.callback_func() or item.callback
    if callback then
        -- Pass our shell as touchmenu_instance (closeMenu / updateItems)
        local stack_n = UIManager._window_stack and #UIManager._window_stack or 0
        callback(self)
        local opened_dialog = UIManager._window_stack
            and #UIManager._window_stack > stack_n
        if item.checked or item.checked_func then
            if not (item.check_callback_updates_menu or item.check_callback_closes_menu) then
                self:updateItems()
            end
        elseif not opened_dialog and not item.keep_menu_open then
            self:closeMenu()
        end
    end
    return true
end

function ModernMenuShell:onMenuHold(item)
    if self._shortcut_pick then
        return true
    end
    if self.touch_menu_callback then
        self.touch_menu_callback()
    end
    if not item then return true end

    if item.hold_input or item.hold_input_func then
        if item.hold_keep_menu_open == false then
            self:closeMenu()
        end
        local input = item.hold_input or item.hold_input_func()
        if input and self.onInput then
            self:onInput(input)
        end
        return true
    end

    local hold_callback = item.hold_callback_func and item.hold_callback_func() or item.hold_callback
    if hold_callback then
        -- TouchMenu default: keep menu open on hold
        if item.hold_keep_menu_open == false then
            self:closeMenu()
        end
        hold_callback(self)
        return true
    end

    local help = item.help_text_func and item.help_text_func(self) or item.help_text
    if help then
        local InfoMessage = require("ui/widget/infomessage")
        UIManager:show(InfoMessage:new{ text = help })
    end
    return true
end

function ModernMenuShell:onBack()
    return self:backToUpperMenu()
end

function ModernMenuShell:onClose()
    return self:closeMenu()
end

function ModernMenuShell:onShow()
    if self.ui then
        self.ui:handleEvent(Event:new("CloseConfigMenu"))
    end
    UIManager:setDirty(self:_dirtyTarget(), "ui")
    return true
end

return ModernMenuShell
