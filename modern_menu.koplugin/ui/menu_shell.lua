--[[--
Modern full-screen replacement for KOReader TouchMenu.
Kobo-inspired chrome: clean header, underline tabs, scrollable list.

Exposes TouchMenu-compatible closeMenu()/updateItems() for menu callbacks.
@module modern_menu.ui.menu_shell
--]]

local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
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
local RightContainer = require("ui/widget/container/rightcontainer")
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

local function chrome_button(text, callback, dirty_parent, width, height)
    -- Large fixed tap target; glyph stays visually light via modest padding.
    return Button:new{
        text = text,
        bordersize = 0,
        radius = 0,
        padding = 0,
        padding_h = Screen:scaleBySize(10),
        padding_v = Screen:scaleBySize(8),
        margin = 0,
        width = width,
        height = height,
        text_font_face = "smallinfofont",
        text_font_size = 26,
        text_font_bold = true,
        callback = callback,
        show_parent = dirty_parent,
    }
end

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
    self.side_margin = Screen:scaleBySize(36)
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

    -- Prefer a phone-comfortable hit target over a tiny glyph-sized button.
    local chrome_btn_w = Screen:scaleBySize(56)
    local chrome_btn_h = Screen:scaleBySize(48)
    self.back_button = chrome_button("‹", function() self:backToUpperMenu() end, dirty_parent, chrome_btn_w, chrome_btn_h)
    self.close_button = chrome_button("✕", function() self:closeMenu() end, dirty_parent, chrome_btn_w, chrome_btn_h)
    self:_applyChromeFont()

    -- Keep title between the enlarged chrome buttons; small outer pad so back
    -- sits near the left edge for easier reach.
    local chrome_edge_pad = Screen:scaleBySize(8)
    local title_w = content_w - chrome_edge_pad * 2 - chrome_btn_w * 2

    self.breadcrumb = Breadcrumb:new{
        crumbs = {},
        width = title_w,
        show_parent = dirty_parent,
        on_select = function(index)
            self:goToCrumb(index)
        end,
    }

    self.header = FrameContainer:new{
        bordersize = 0,
        padding_top = Screen:scaleBySize(6),
        -- Extra bottom margin so the title row reads as its own band.
        padding_bottom = Screen:scaleBySize(14),
        padding_left = chrome_edge_pad,
        padding_right = chrome_edge_pad,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        width = content_w,
        HorizontalGroup:new{
            align = "center",
            LeftContainer:new{
                dimen = Geom:new{ w = chrome_btn_w, h = chrome_btn_h },
                self.back_button,
            },
            CenterContainer:new{
                dimen = Geom:new{
                    w = title_w,
                    h = chrome_btn_h,
                },
                self.breadcrumb,
            },
            RightContainer:new{
                dimen = Geom:new{ w = chrome_btn_w, h = chrome_btn_h },
                self.close_button,
            },
        },
    }

    self.tab_defs = self:_buildTabDefs()
    self.tab_bar = TabBar:new{
        tabs = self.tab_defs,
        selected = self.last_index,
        width = content_w,
        -- Same inset as the grey rule so tabs sit in the content box.
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

    -- Slightly heavier rule with breathing room — clear without shouting.
    local rule_w = content_w - 2 * self.side_margin
    self.tab_rule_line = LineWidget:new{
        background = Settings.getRuleFg(),
        dimen = Geom:new{
            w = rule_w,
            h = math.max(Size.line.thick, Screen:scaleBySize(2)),
        },
    }
    self.tab_rule = VerticalGroup:new{
        align = "left",
        VerticalSpan:new{ width = Screen:scaleBySize(4) },
        HorizontalGroup:new{
            HorizontalSpan:new{ width = self.side_margin },
            self.tab_rule_line,
        },
        VerticalSpan:new{ width = Screen:scaleBySize(8) },
    }

    self.status_bar = StatusBar.make{
        ui = self.ui,
        show_parent = dirty_parent,
        menu_shell = self, -- enables chrome toggle left of icons
        width = content_w,
        side_margin = self.side_margin,
        -- Match list right margin (scrollbar gutter)
        right_inset = self.scrollbar_gutter,
    }
    self.status_h = self.status_bar.height

    -- Fixed list viewport under chrome; scroll when items overflow
    local header_h = chrome_btn_h + Screen:scaleBySize(20)
    local tabs_h = self.tab_bar.height + Screen:scaleBySize(4)
    local rule_h = Screen:scaleBySize(4) + math.max(Size.line.thick, Screen:scaleBySize(2)) + Screen:scaleBySize(8)
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
        },
    }

    -- Generous corner hit zones (wider than the visible button) for thumbs.
    local chrome_zone = chrome_edge_pad + chrome_btn_w + Screen:scaleBySize(12)
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
    self.chrome_hit.onTapChromeHit = function(_, ges)
        if not ges or not ges.pos then
            return false
        end
        -- Header band only (status bar handles its own taps)
        if ges.pos.y < chrome_top or ges.pos.y > chrome_top + self.chrome_h then
            return false
        end
        if ges.pos.x >= self.dimen.w - chrome_zone then
            self:closeMenu()
            return true
        end
        if ges.pos.x <= chrome_zone then
            self:backToUpperMenu()
            return true
        end
        return false
    end

    -- chrome_hit first so the enlarged corner zones win over the glyph button.
    self[1] = OverlapGroup:new{
        dimen = self.dimen,
        allow_mirroring = false,
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
        table.insert(self.qm_footer_slot, VerticalSpan:new{ width = Size.span.vertical_default })
        table.insert(self.qm_footer_slot, footer_widget)
    end

    local footer_h = 0
    if self.qm_footer_slot and (footer_widget or pinned) then
        local slot_size = self.qm_footer_slot:getSize()
        footer_h = slot_size and slot_size.h or 0
    end
    if self.list_h_base and self.list_dimen and self.scroll_container then
        local list_h = math.max(Screen:scaleBySize(80), self.list_h_base - footer_h)
        self.list_dimen.h = list_h
        self.scroll_container.dimen.h = list_h
    end

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

    -- Reset scroll state so the next paint recomputes overflow + scrollbar.
    -- A live _bb would blit the previous button glyphs over the new panel.
    self.scroll_container[1] = content
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
    UIManager:setDirty(self:_dirtyTarget(), "ui")
end

function ModernMenuShell:_applyChromeFont()
    local function apply(button)
        local label = button and button.label_widget
        if not label then
            return
        end
        label.face = Settings.face(button.text_font_size, "smallinfofont")
        label._face_adjusted = nil
        label:free()
    end
    apply(self.back_button)
    apply(self.close_button)
end

function ModernMenuShell:refresh()
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
    UIManager:setDirty(self:_dirtyTarget(), "ui")
end

function ModernMenuShell:closeMenu()
    if self._closing then
        return true
    end
    self._closing = true

    local cb = self.close_callback
    self.close_callback = nil

    -- Defer so we don't tear down widgets mid-gesture dispatch.
    -- close_callback (Reader/FM onClose*Menu) closes the CenterContainer parent.
    UIManager:nextTick(function()
        if cb then
            cb()
        else
            UIManager:close(self.show_parent or self, "ui")
        end
        UIManager:setDirty("all", "ui")
    end)
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
