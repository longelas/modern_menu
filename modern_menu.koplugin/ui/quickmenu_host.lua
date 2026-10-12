--[[--
Host for jbreizh/quickmenu.koplugin inside Modern Menu.

Quick Menu inserts a tab whose body is a `panel` widget and then patches
TouchMenu to paint it. Modern Menu never opens TouchMenu, so this module
builds the TouchMenu-shaped object Quick Menu's panel and footer expect
and forwards the slider gestures TouchMenu would have forwarded.

The Quick Menu plugin itself is not bundled. Nothing here runs unless that
plugin is installed and has registered its tab.
@module modern_menu.ui.quickmenu_host
--]]

local BD = require("ui/bidi")
local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Event = require("ui/event")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconButton = require("ui/widget/iconbutton")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local datetime = require("datetime")
local logger = require("logger")
local Screen = Device.screen
local _ = require("gettext")

local QuickMenuHost = {}

local function is_quickmenu(value)
    return type(value) == "table" and (
        value.name == "quickmenu"
        or (type(value.config) == "table"
            and value.config.section_order
            and value.config.add_quickmenu_tab ~= nil)
    )
end

local function plugin_from_panel(panel_fn)
    if type(panel_fn) ~= "function" or not debug or not debug.getupvalue then
        return nil
    end
    local index = 1
    while true do
        local ok, name, value = pcall(debug.getupvalue, panel_fn, index)
        if not ok or not name then
            return nil
        end
        if is_quickmenu(value) then
            return value
        end
        index = index + 1
    end
end

--- Locate the installed Quick Menu plugin instance, if any.
function QuickMenuHost.findPlugin(ui, tab)
    if ui and is_quickmenu(ui.quickmenu) then
        return ui.quickmenu
    end
    local menu = ui and ui.menu
    local registered = menu and menu.registered_widgets
    if registered then
        for _, widget in ipairs(registered) do
            if is_quickmenu(widget) then
                return widget
            end
        end
    end
    if tab and tab.panel then
        return plugin_from_panel(tab.panel)
    end
    return nil
end

--- Re-run Quick Menu's tab insert so the panel tab exists even when
-- setUpdateItemTable ran before that plugin finished patching.
function QuickMenuHost.sync(menu_self)
    if not menu_self or not menu_self.tab_item_table then
        return
    end
    local plugin = QuickMenuHost.findPlugin(menu_self.ui, nil)
    if not plugin then
        return
    end
    local ok_req, QuickMenu = pcall(require, "quickmenu")
    if not ok_req or type(QuickMenu.updateTab) ~= "function" then
        return
    end
    plugin.menu_instance = menu_self
    plugin.is_filemanager = menu_self.onCloseFileManagerMenu ~= nil
    local ok_up, err = pcall(QuickMenu.updateTab, plugin)
    if not ok_up then
        logger.warn("modern_menu: quickmenu updateTab failed: " .. tostring(err))
    end
end

--- Tab to open. Quick Menu's default (`open_on_start`) forces its tab,
-- which it expresses as `remember()` returning false.
function QuickMenuHost.initialIndex(menu_self, tab_index)
    local tabs = menu_self and menu_self.tab_item_table or {}
    for i, tab in ipairs(tabs) do
        if tab.id == "quick_menu_tab" and type(tab.remember) == "function" then
            local ok, remember = pcall(tab.remember)
            if ok and not remember then
                return i
            end
            break
        end
    end

    local saved = G_reader_settings and G_reader_settings:readSetting("filemanagermenu_tab_index")
    local index = tab_index or (menu_self and menu_self.last_tab_index) or saved or 1
    if index < 1 then
        index = 1
    end
    if #tabs > 0 and index > #tabs then
        index = 1
    end
    local tab = tabs[index]
    if tab and tab.id == "exit_tab" then
        index = math.max(1, index - 1)
    end
    return index
end

-- Quick Menu stores these on the touch menu as `_qs_*`. Older snapshots
-- used `_qm_*`. Read either so a toggle still finds the live panel.
local function qm_refs(touch_menu)
    if not touch_menu then
        return nil
    end
    return touch_menu._qs_refs or touch_menu._qm_refs
end

local function qm_locked(touch_menu)
    return touch_menu
        and (touch_menu._qs_slider_locked or touch_menu._qm_slider_locked)
        or false
end

local function set_locked(touch_menu, locked)
    if not touch_menu then
        return
    end
    local on = locked and true or false
    touch_menu._qs_slider_locked = on
    touch_menu._qm_slider_locked = on
end

local function slider_list(touch_menu)
    local refs = qm_refs(touch_menu)
    local sliders = {}
    if not refs then
        return sliders
    end
    for _, entry in ipairs(refs.sliders or {}) do
        local widget = entry.slider or entry.widget or entry
        if type(widget) == "table" and (widget.handlePan or widget.handleTap or widget.handleHold) then
            sliders[#sliders + 1] = widget
        end
    end
    return sliders
end

local function in_scroll_area(shell, ges)
    local dimen = shell.scroll_container and shell.scroll_container.dimen
    return ges and ges.pos and dimen and ges.pos.intersectWith and ges.pos:intersectWith(dimen)
end

--- Forward a gesture to Quick Menu sliders. Returns true when the shell
-- should consume the event (slider handled it, or it must not scroll).
function QuickMenuHost.dispatch(shell, kind, ges)
    local touch_menu = shell and shell._qm_touch
    if not touch_menu or not qm_refs(touch_menu) or not in_scroll_area(shell, ges) then
        return false
    end

    if kind == "pan" then
        if qm_locked(touch_menu) then
            touch_menu._qm_opening_pan = true
            touch_menu._qs_opening_pan = true
            return true
        end
        touch_menu._qm_opening_pan = false
        touch_menu._qs_opening_pan = false
        for _, slider in ipairs(slider_list(touch_menu)) do
            if slider.handlePan and slider:handlePan(ges) then
                return true
            end
        end
        local dir = ges.direction
        if dir == "east" or dir == "west" then
            return true
        end
        return false
    end

    if kind == "pan_release" then
        if qm_locked(touch_menu) or touch_menu._qm_opening_pan or touch_menu._qs_opening_pan then
            touch_menu._qm_opening_pan = false
            touch_menu._qs_opening_pan = false
            return true
        end
        for _, slider in ipairs(slider_list(touch_menu)) do
            if slider.handlePanRelease and slider:handlePanRelease(ges, shell.show_parent, shell.dimen) then
                return true
            end
        end
        return false
    end

    if kind == "tap" or kind == "hold" then
        if qm_locked(touch_menu) then
            return true
        end
        local method = kind == "tap" and "handleTap" or "handleHold"
        for _, slider in ipairs(slider_list(touch_menu)) do
            if slider[method] and slider[method](slider, ges) then
                return true
            end
        end
        return false
    end

    if kind == "swipe" then
        if qm_locked(touch_menu) then
            return true
        end
        for _, slider in ipairs(slider_list(touch_menu)) do
            if slider.handleSwipe and slider:handleSwipe(ges, shell.show_parent, shell.dimen) then
                return true
            end
        end
        local dir = ges.direction
        local scrollable = shell.scroll_container and shell.scroll_container._is_scrollable
        if (dir == "north" or dir == "south") and scrollable then
            return false
        end
        if dir == "north" then
            shell:closeMenu()
        end
        return true
    end

    if kind == "multiswipe" then
        for _, slider in ipairs(slider_list(touch_menu)) do
            if slider.handleMultiSwipe and slider:handleMultiSwipe(ges, shell.show_parent, shell.dimen) then
                return true
            end
        end
        return true
    end

    return false
end

local GestureLayer = InputContainer:extend{
    shell = nil,
}

function GestureLayer:init()
    local child = self[1]
    local size = child and child.getSize and child:getSize()
    self.dimen = Geom:new{
        w = (size and size.w) or Screen:getWidth(),
        h = (size and size.h) or 0,
    }
    local range = Geom:new{
        x = 0, y = 0,
        w = Screen:getWidth(),
        h = Screen:getHeight(),
    }
    self.ges_events = {
        QuickMenuTap = { GestureRange:new{ ges = "tap", range = range } },
        QuickMenuHold = { GestureRange:new{ ges = "hold", range = range } },
        QuickMenuPan = { GestureRange:new{ ges = "pan", range = range } },
        QuickMenuPanRelease = { GestureRange:new{ ges = "pan_release", range = range } },
        QuickMenuSwipe = { GestureRange:new{ ges = "swipe", range = range } },
        QuickMenuMultiSwipe = { GestureRange:new{ ges = "multiswipe", range = range } },
    }
end

function GestureLayer:onQuickMenuTap(_, ges)
    return QuickMenuHost.dispatch(self.shell, "tap", ges)
end

function GestureLayer:onQuickMenuHold(_, ges)
    return QuickMenuHost.dispatch(self.shell, "hold", ges)
end

function GestureLayer:onQuickMenuPan(_, ges)
    return QuickMenuHost.dispatch(self.shell, "pan", ges)
end

function GestureLayer:onQuickMenuPanRelease(_, ges)
    return QuickMenuHost.dispatch(self.shell, "pan_release", ges)
end

function GestureLayer:onQuickMenuSwipe(_, ges)
    return QuickMenuHost.dispatch(self.shell, "swipe", ges)
end

function GestureLayer:onQuickMenuMultiSwipe(_, ges)
    return QuickMenuHost.dispatch(self.shell, "multiswipe", ges)
end

local function make_shim(shell, tab)
    local shim = {
        show_parent = shell.show_parent or shell,
        dimen = shell.dimen,
        width = shell.list_content_w or shell.dimen.w,
        padding = Size.padding.default,
        bordersize = 0,
        item_table = tab,
        page = 1,
        page_num = 1,
        fface = Font:getFace("ffont"),
    }
    shim.item_width = math.max(
        Screen:scaleBySize(120),
        shim.width - shim.padding * 2
    )

    function shim:updateItems()
        if shell._closing then
            return
        end
        -- Plugin writes `_qs_full_refresh`. A nested toggle during rebuild
        -- must not be dropped or the button keeps the previous snapshot.
        local full = self._qs_full_refresh or self._qm_full_refresh or false
        self._qs_full_refresh = false
        self._qm_full_refresh = false
        self._qs_pending_refresh = false
        self._qm_pending_refresh = false
        if shell._qm_updating then
            shell._qm_refresh_pending = true
            if full then
                shell._qm_refresh_full = true
            end
            return
        end
        shell._qm_updating = true
        local ok, err = pcall(function()
            if shell.refreshQuickMenu then
                shell:refreshQuickMenu()
            else
                shell:refresh()
            end
        end)
        shell._qm_updating = false
        if not ok then
            logger.warn("modern_menu: quickmenu refresh failed: " .. tostring(err))
        end
        if full or shell._qm_refresh_full then
            shell._qm_refresh_full = false
            UIManager:setDirty("all", "full")
        else
            -- show_parent is the window. "all" covers the case where a
            -- button highlight already drained that dirty flag mid-tap.
            UIManager:setDirty(shell.show_parent or "all", "ui")
            UIManager:setDirty("all", "ui")
        end
        if shell._qm_followup then
            return
        end
        shell._qm_followup = true
        UIManager:nextTick(function()
            shell._qm_followup = false
            if shell._closing then
                return
            end
            if shell._qm_refresh_pending then
                shell._qm_refresh_pending = false
                shim:updateItems()
                return
            end
            -- One more paint after the tap returns, so a stock Button
            -- forceRePaint cannot leave the pre-toggle glyph on screen.
            UIManager:setDirty(shell.show_parent or "all", "ui")
        end)
    end

    function shim:backToUpperMenu(no_close)
        return shell:backToUpperMenu(no_close)
    end

    function shim:closeMenu()
        return shell:closeMenu()
    end

    function shim:onPrevPage()
        local sc = shell.scroll_container
        if sc and sc.onScrollPageUp then
            return sc:onScrollPageUp()
        end
        return true
    end

    function shim:onNextPage()
        local sc = shell.scroll_container
        if sc and sc.onScrollPageDown then
            return sc:onScrollPageDown()
        end
        return true
    end

    shim.onFirstPage = shim.onPrevPage
    shim.onLastPage = shim.onNextPage
    shim.close_callback = function()
        shell:closeMenu()
    end
    shim.touch_menu_callback = shell.touch_menu_callback

    local chevron_left = "chevron.left"
    local chevron_right = "chevron.right"
    if BD.mirroredUILayout() then
        chevron_left, chevron_right = chevron_right, chevron_left
    end
    shim.page_info_left_chev = Button:new{
        icon = chevron_left,
        callback = function() shim:onPrevPage() end,
        hold_callback = function() shim:onFirstPage() end,
        bordersize = 0,
        show_parent = shim.show_parent,
    }
    shim.page_info_right_chev = Button:new{
        icon = chevron_right,
        callback = function() shim:onNextPage() end,
        hold_callback = function() shim:onLastPage() end,
        bordersize = 0,
        show_parent = shim.show_parent,
    }
    shim.page_info_left_chev:hide()
    shim.page_info_right_chev:hide()
    shim.page_info_text = TextWidget:new{
        text = "",
        face = shim.fface,
    }
    shim.page_info = HorizontalGroup:new{
        shim.page_info_left_chev,
        shim.page_info_text,
        shim.page_info_right_chev,
    }
    shim.time_info = Button:new{
        text = "",
        face = shim.fface,
        text_font_bold = false,
        bordersize = 0,
        show_parent = shim.show_parent,
        callback = function()
            UIManager:show(InfoMessage:new{
                text = datetime.secondsToDateTime(nil, nil, true),
            })
        end,
        hold_callback = function()
            UIManager:broadcastEvent(Event:new("ShowBatteryStatistics"))
        end,
    }
    shim.device_info = HorizontalGroup:new{
        shim.time_info,
        HorizontalSpan:new{ width = Size.span.horizontal_default },
    }

    local footer_width = shim.width - shim.padding * 2
    shim.up_button = IconButton:new{
        icon = "chevron.up",
        show_parent = shim.show_parent,
        padding_left = math.floor(footer_width * 0.33 * 0.1),
        padding_right = math.floor(footer_width * 0.33 * 0.1),
        callback = function()
            shim:backToUpperMenu()
        end,
    }
    local footer_height = shim.up_button:getSize().h + Size.line.thick
    local column_w = math.floor(footer_width * 0.33)
    shim.footer = HorizontalGroup:new{
        LeftContainer:new{
            dimen = Geom:new{ w = column_w, h = footer_height },
            shim.up_button,
        },
        CenterContainer:new{
            dimen = Geom:new{ w = column_w, h = footer_height },
            shim.page_info,
        },
        RightContainer:new{
            dimen = Geom:new{ w = column_w, h = footer_height },
            shim.device_info,
        },
    }
    return shim
end

local function bind_one(shell, plugin, shim)
    if not is_quickmenu(plugin) then
        return
    end
    -- Button callbacks read ctx.touch_menu at tap time. That has to be this
    -- shim, including when the panel closure and ui.quickmenu differ.
    plugin.touch_menu = shim
    if shell.ui and shell.ui.menu then
        plugin.menu_instance = plugin.menu_instance or shell.ui.menu
    end
end

local function bind_plugin(shell, tab, shim)
    local from_panel = tab and plugin_from_panel(tab.panel)
    local from_ui = QuickMenuHost.findPlugin(shell.ui, nil)
    bind_one(shell, from_panel, shim)
    if from_ui ~= from_panel then
        bind_one(shell, from_ui, shim)
    end
    return from_panel or from_ui
end

local function sync_shim(shim, shell, tab)
    shim.show_parent = shell.show_parent or shell
    shim.dimen = shell.dimen
    shim.width = shell.list_content_w or (shell.dimen and shell.dimen.w) or shim.width
    shim.padding = shim.padding or Size.padding.default
    shim.item_table = tab
    shim.item_width = math.max(
        Screen:scaleBySize(120),
        shim.width - shim.padding * 2
    )
    shim.touch_menu_callback = shell.touch_menu_callback
end

local function build_panel(tab, shim)
    local panel_fn = tab.panel
    local ok, result
    if type(panel_fn) == "function" then
        ok, result = pcall(panel_fn, shim)
    else
        ok, result = true, panel_fn
    end
    if not ok then
        return nil, result
    end
    if result and result.paintTo then
        return result
    end
    return nil, "panel did not return a widget"
end

local function build_footer(plugin, shim)
    local ok_req, QuickMenu = pcall(require, "quickmenu")
    if not ok_req or type(QuickMenu.createFooter) ~= "function" then
        return nil
    end
    local ok, err = pcall(QuickMenu.createFooter, plugin)
    if not ok then
        logger.warn("modern_menu: quickmenu footer failed: " .. tostring(err))
        return nil
    end
    return shim.footer
end

--- Build the Quick Menu body for the current tab.
-- @return widget|nil, footer|nil, err|nil
function QuickMenuHost.fill(shell)
    local tab = shell.tab_item_table and shell.tab_item_table[shell.last_index]
    local nested = shell.item_table_stack and #shell.item_table_stack > 0
    local show_panel = tab and tab.panel ~= nil and not nested
    local plugin = QuickMenuHost.findPlugin(shell.ui, tab)
    local footer_cfg = plugin and plugin.config and plugin.config.sections and plugin.config.sections.footer
    local show_footer = false
    if footer_cfg and (show_panel or footer_cfg.show_all_tab) then
        show_footer = true
    elseif show_panel then
        show_footer = true
    end
    if not show_panel and not show_footer then
        return nil, nil, nil
    end

    -- One shim for the life of the shell. Delayed updateMenu closures
    -- (wifi, save-and-refresh) keep calling this object, and its _qs_* flags
    -- stay on the instance Quick Menu mutates.
    local shim = shell._qm_touch
    if not shim or type(shim.updateItems) ~= "function" then
        shim = make_shim(shell, tab)
    else
        sync_shim(shim, shell, tab)
    end
    plugin = bind_plugin(shell, tab, shim) or plugin
    shell._qm_touch = shim
    -- Stock TouchMenu sets this before the footer build. Without it the
    -- footer skips the status buttons and keeps the previous labels.
    shim._qs_quickmenu_tab = show_panel and true or false
    shim._qm_quickmenu_tab = shim._qs_quickmenu_tab

    -- Swallow the gesture that opened the menu so it does not move a slider.
    if show_panel and not shell._qm_slider_lock_armed then
        shell._qm_slider_lock_armed = true
        shell._qm_slider_locked = true
        set_locked(shim, true)
        UIManager:scheduleIn(0.35, function()
            shell._qm_slider_locked = false
            set_locked(shell._qm_touch, false)
        end)
    end
    set_locked(shim, shell._qm_slider_locked)

    local panel_widget, panel_err
    if show_panel then
        panel_widget, panel_err = build_panel(tab, shim)
        if panel_err then
            logger.warn("modern_menu: quickmenu panel failed: " .. tostring(panel_err))
        end
    end

    local footer_widget
    if show_footer and plugin then
        footer_widget = build_footer(plugin, shim)
        if shim.footer and shim.footer.resetLayout then
            shim.footer:resetLayout()
        end
    end

    if panel_widget then
        local content_w = shell.list_content_w or shell.dimen.w
        local size = panel_widget:getSize()
        panel_widget = GestureLayer:new{
            shell = shell,
            CenterContainer:new{
                dimen = Geom:new{
                    w = content_w,
                    h = size and size.h or 0,
                },
                panel_widget,
            },
        }
    end

    return panel_widget, footer_widget, panel_err
end

function QuickMenuHost.failureMessage()
    return _("Quick Menu could not be loaded.")
end

return QuickMenuHost
