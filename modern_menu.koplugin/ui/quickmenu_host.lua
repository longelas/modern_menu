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
local Settings = require("settings")
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

--- Neo stores this beside KOReader settings. Missing file means the
-- plugin default, which is to open on its tab.
local function neo_opens_by_default()
    local ok_ds, DataStorage = pcall(require, "datastorage")
    local ok_ls, LuaSettings = pcall(require, "luasettings")
    if not (ok_ds and ok_ls and DataStorage.getSettingsDir) then
        return true
    end
    local ok, settings = pcall(function()
        return LuaSettings:open(DataStorage:getSettingsDir() .. "/neo_quicksettings.lua")
    end)
    if not ok or not settings or not settings.readSetting then
        return true
    end
    local cfg = settings:readSetting("config")
    if type(cfg) ~= "table" or cfg.open_by_default == nil then
        return true
    end
    return cfg.open_by_default == true
end

--- Tab to open. Quick Menu's default (`open_on_start`) forces its tab,
-- which it expresses as `remember()` returning false. Neo Quick Settings
-- uses its own "show as default tab" flag and wins only when Quick Menu
-- is not forcing its tab.
function QuickMenuHost.initialIndex(menu_self, tab_index)
    local tabs = menu_self and menu_self.tab_item_table or {}
    -- An explicit Modern Menu choice wins over Neo and Quick Menu defaults.
    local wanted = Settings.getDefaultTabId()
    if wanted then
        for i, tab in ipairs(tabs) do
            if Settings.tabKey(tab) == wanted then
                return i
            end
        end
    end
    for i, tab in ipairs(tabs) do
        if tab.id == "quick_menu_tab" and type(tab.remember) == "function" then
            local ok, remember = pcall(tab.remember)
            if ok and not remember then
                return i
            end
            break
        end
    end

    local neo_index
    for i, tab in ipairs(tabs) do
        if tab.id == "neo_quicksettings" then
            neo_index = i
            break
        end
    end
    local neo_default = neo_index and neo_opens_by_default()
    if neo_default then
        return neo_index
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
    -- Kobold Home is a button, not a page. Open the menu on the next page.
    tab = tabs[index]
    if tab and tab.id == "kobold_home" then
        if index < #tabs then
            index = index + 1
        elseif index > 1 then
            index = index - 1
        end
    end
    -- Neo inserts itself first but, when it is not the default opener,
    -- stock TouchMenu steps past that slot.
    if neo_index and index == neo_index and not neo_default then
        index = neo_index < #tabs and (neo_index + 1) or math.max(1, neo_index - 1)
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

--- Neo Quick Settings stores action buttons as plain frames plus callbacks
-- in `_qs_refs.buttons`. TouchMenu hit-tests them. Quick Menu's own
-- buttons are real tap widgets and are left to handle themselves.
local function press_ref_button(touch_menu, ges, is_hold)
    local refs = qm_refs(touch_menu)
    local buttons = refs and refs.buttons
    if type(buttons) ~= "table" or not ges or not ges.pos or not ges.pos.intersectWith then
        return false
    end
    -- Neo hit-tests the icon circle only. The caption sits just under it, so a
    -- tap on the label would otherwise miss. Prefer a circle hit; otherwise the
    -- closest caption under a circle.
    local label_h = Screen:scaleBySize(22)
    local fallback, fallback_dist
    for _, btn_ref in ipairs(buttons) do
        if type(btn_ref) == "table" then
            local widget = btn_ref.widget or btn_ref
            local dimen = widget and widget.dimen
            if dimen then
                local on_circle = ges.pos:intersectWith(dimen)
                local on_label = not on_circle and ges.pos:intersectWith(Geom:new{
                    x = dimen.x,
                    y = dimen.y + dimen.h,
                    w = dimen.w,
                    h = label_h,
                })
                if on_circle or on_label then
                    local function fire(ref)
                        local callback = is_hold and ref.hold_callback or ref.callback
                        if callback then
                            local ok, err = pcall(callback, touch_menu)
                            if not ok then
                                logger.warn("modern_menu: quick panel button failed: " .. tostring(err))
                            end
                        end
                        return true
                    end
                    if on_circle then
                        return fire(btn_ref)
                    end
                    local cx = dimen.x + dimen.w / 2
                    local cy = dimen.y + dimen.h + label_h / 2
                    local dist = (ges.pos.x - cx) ^ 2 + (ges.pos.y - cy) ^ 2
                    if not fallback or dist < fallback_dist then
                        fallback = btn_ref
                        fallback_dist = dist
                    end
                end
            end
        end
    end
    if not fallback then
        return false
    end
    local callback = is_hold and fallback.hold_callback or fallback.callback
    if callback then
        local ok, err = pcall(callback, touch_menu)
        if not ok then
            logger.warn("modern_menu: quick panel button failed: " .. tostring(err))
        end
    end
    return true
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

local function module_upvalue(fn, wanted)
    if type(fn) ~= "function" or not debug or not debug.getupvalue then
        return nil
    end
    local index = 1
    while true do
        local ok, name, value = pcall(debug.getupvalue, fn, index)
        if not ok or not name then
            return nil
        end
        if name == wanted then
            return value
        end
        index = index + 1
    end
end

--- Simple UI builds its quick-action row inside a patched TouchMenu.
-- Those two locals are upvalues of the patched methods.
local function simpleui_builders()
    local ok, TouchMenu = pcall(require, "ui/widget/touchmenu")
    if not ok or not TouchMenu then
        return nil, nil
    end
    local build = module_upvalue(TouchMenu.updateItems, "buildPanel")
    local gesture = module_upvalue(TouchMenu.onTapCloseAllMenus, "handleGesture")
    if type(build) ~= "function" then
        return nil, nil
    end
    return build, gesture
end

--- FileManager injects the tab from setUpdateItemTable. Reader injects it
-- from onShowMenu, which this menu replaces. Call the same inject when
-- the tab is missing so a chosen default still exists.
function QuickMenuHost.ensureSimpleUITab(menu_self)
    local tabs = menu_self and menu_self.tab_item_table
    if type(tabs) ~= "table" then
        return
    end
    for _, tab in ipairs(tabs) do
        if tab._sui_qs_panel then
            return
        end
    end
    local inject
    local ok_fm, FMMenu = pcall(require, "apps/filemanager/filemanagermenu")
    if ok_fm and FMMenu then
        inject = module_upvalue(FMMenu.setUpdateItemTable, "injectPanelTab")
    end
    if type(inject) ~= "function" then
        local ok_rm, RMenu = pcall(require, "apps/reader/modules/readermenu")
        if ok_rm and RMenu then
            inject = module_upvalue(RMenu.onShowMenu, "injectPanelTab")
        end
    end
    if type(inject) == "function" then
        local ok, err = pcall(inject, menu_self)
        if not ok then
            logger.warn("modern_menu: simpleui tab inject failed: " .. tostring(err))
        end
    end
end

local function press_sui(touch_menu, ges, kind)
    if not touch_menu or not touch_menu._sui_qs_refs or not ges then
        return false
    end
    if kind == "hold" then
        local panel = touch_menu._sui_qs_panel_widget
        if type(panel) ~= "table" or type(panel.onHoldPanel) ~= "function" then
            return false
        end
        local dimen = panel.dimen
        if dimen and ges.pos and ges.pos.intersectWith and not ges.pos:intersectWith(dimen) then
            return false
        end
        local ok, handled = pcall(panel.onHoldPanel, panel)
        if not ok then
            logger.warn("modern_menu: simpleui hold failed: " .. tostring(handled))
            return false
        end
        return handled == true
    end
    local gesture = touch_menu._sui_qs_gesture
    if type(gesture) ~= "function" then
        return false
    end
    local ok, handled, stay_open = pcall(gesture, touch_menu, ges)
    if not ok then
        logger.warn("modern_menu: simpleui button failed: " .. tostring(handled))
        return false
    end
    if not handled then
        return false
    end
    -- The action schedules itself. Drop the window now so that work does
    -- not land on this menu. In-place actions ask to stay open.
    if stay_open ~= true and touch_menu.closeMenu then
        touch_menu:closeMenu()
    end
    return true
end

local function in_scroll_area(shell, ges)
    local dimen = shell.scroll_container and shell.scroll_container.dimen
    return ges and ges.pos and dimen and ges.pos.intersectWith and ges.pos:intersectWith(dimen)
end

--- Forward a gesture to Quick Menu sliders. Returns true when the shell
-- should consume the event (slider handled it, or it must not scroll).
function QuickMenuHost.dispatch(shell, kind, ges)
    local touch_menu = shell and shell._qm_touch
    if touch_menu and (kind == "tap" or kind == "hold" or kind == "swipe") then
        if press_sui(touch_menu, ges, kind) then
            return true
        end
    end
    if not touch_menu or not qm_refs(touch_menu) then
        return false
    end
    local in_area = in_scroll_area(shell, ges)
    -- Both plugins paint the track straight onto Screen.bb while _dragging,
    -- then refresh with setDirty(nil). On a phone that refresh already holds
    -- the framebuffer mutex, so the paint crashes. Move the value with
    -- _dragging left off and let the menu repaint normally.
    local function move_slider(slider, abs_x, coalesce)
        if not slider or type(slider.applyPosition) ~= "function" or not abs_x then
            return false
        end
        -- Leave _dragging off. These plugins paint the track onto Screen.bb
        -- and then refresh while the framebuffer lock is held.
        slider._dragging = false
        slider.hide_knob = false
        local ok, err = pcall(slider.applyPosition, slider, abs_x)
        if not ok then
            logger.warn("modern_menu: slider update failed: " .. tostring(err))
            return false
        end
        -- One paint while the finger is down, and always one when it lifts.
        if coalesce then
            if not shell._qm_slider_paint then
                shell._qm_slider_paint = true
                UIManager:setDirty(shell.show_parent or "all", "ui")
            end
        else
            shell._qm_slider_paint = nil
            UIManager:setDirty(shell.show_parent or "all", "ui")
        end
        return true
    end
    local function slider_at(pos)
        if not pos or not pos.intersectWith then
            return nil
        end
        for _, slider in ipairs(slider_list(touch_menu)) do
            if slider.dimen and pos:intersectWith(slider.dimen) then
                return slider
            end
        end
        return nil
    end

    if kind == "pan" then
        local dir = ges and ges.direction
        if qm_locked(touch_menu) then
            touch_menu._qm_opening_pan = true
            touch_menu._qs_opening_pan = true
            shell._qm_slider_drag = nil
            if not in_area then
                return false
            end
            -- The opening tap must not move a slider. A vertical drag still
            -- scrolls so the button grid can move.
            if dir == "north" or dir == "south" then
                return false
            end
            return true
        end
        touch_menu._qm_opening_pan = false
        touch_menu._qs_opening_pan = false
        local active = shell._qm_slider_drag
        if not active and ges and ges.pos then
            active = slider_at(ges.pos)
        end
        if active and ges and ges.pos then
            shell._qm_slider_drag = active
            return move_slider(active, ges.pos.x, true)
        end
        if not in_area then
            return false
        end
        if dir == "east" or dir == "west" then
            return true
        end
        return false
    end

    if kind == "pan_release" then
        local active = shell._qm_slider_drag
        shell._qm_slider_drag = nil
        if qm_locked(touch_menu) or touch_menu._qm_opening_pan or touch_menu._qs_opening_pan then
            touch_menu._qm_opening_pan = false
            touch_menu._qs_opening_pan = false
            return in_area
        end
        if active and ges and ges.pos then
            return move_slider(active, ges.pos.x, false)
        end
        return false
    end

    if kind == "tap" or kind == "hold" then
        if qm_locked(touch_menu) then
            return in_area
        end
        if kind == "tap" then
            for _, slider in ipairs(slider_list(touch_menu)) do
                if slider.handleTap and slider:handleTap(ges) then
                    return true
                end
            end
        end
        -- Button frames are in screen space, so a stale scroll dimen must not
        -- hide a tap that landed on one.
        if press_ref_button(touch_menu, ges, kind == "hold") then
            return true
        end
        return false
    end

    if kind == "swipe" then
        if qm_locked(touch_menu) then
            return in_area
        end
        local dir = ges and ges.direction
        local sign = 0
        if dir == "east" or dir == "northeast" or dir == "southeast" then
            sign = 1
        elseif dir == "west" or dir == "northwest" or dir == "southwest" then
            sign = -1
        end
        local active = shell._qm_slider_drag
        shell._qm_slider_drag = nil
        if not active and ges and ges.pos then
            active = slider_at(ges.pos)
        end
        if active and sign ~= 0 and ges and ges.pos then
            return move_slider(active, ges.pos.x + sign * (ges.distance or 0), false)
        end
        if not in_area then
            return false
        end
        if dir == "north" or dir == "south" then
            return false
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

-- The scroller asks us for height. A CenterContainer reports the dimen we
-- gave it; measure the panel inside so a later layout change is included.
-- A bare group (the pinned slider block) is measured as a whole.
-- Width stays at the centering box. Shrinking it to the panel's own width
-- zeroes the centering offset and the grid paints against the left edge.
function GestureLayer:getSize()
    local child = self[1]
    local size
    if child and child.dimen and child[1] and child[1].getSize then
        size = child[1]:getSize()
    elseif child and child.getSize then
        size = child:getSize()
    end
    if size and size.h and size.h > 0 and self.dimen then
        self.dimen.h = size.h
        if child.dimen then
            child.dimen.h = size.h
        end
    end
    return self.dimen
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

-- Tabs and menu rows are inset by side_margin. The quick panel uses
-- item_width as its painted width, so that has to be the same column.
local function panel_column(shell)
    local full = (shell and (shell.list_content_w or (shell.dimen and shell.dimen.w)))
        or Screen:getWidth()
    local inset = (shell and shell.side_margin) or 0
    return math.max(Screen:scaleBySize(120), full - inset * 2)
end

local function make_shim(shell, tab)
    local shim = {
        show_parent = shell.show_parent or shell,
        dimen = shell.dimen,
        padding = Size.padding.default,
        bordersize = 0,
        item_table = tab,
        page = 1,
        page_num = 1,
        fface = Font:getFace("ffont"),
    }
    shim.item_width = panel_column(shell)
    -- Stock TouchMenu: item_width = width - padding * 2. Footer uses width.
    shim.width = shim.item_width + shim.padding * 2

    function shim:updateItems()
        if shell._closing then
            return
        end
        -- Settings (and any other submenu) assigns this shim's item_table,
        -- then asks for a refresh. The shell is what paints that list.
        if self.item_table and shell.item_table ~= self.item_table then
            shell.item_table = self.item_table
        end
        local stack = shell.item_table_stack
        local titles = shell.title_stack
        if stack and titles then
            while #titles < #stack do
                titles[#titles + 1] = _("Settings")
            end
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
            local full_paint = full or shell._qm_refresh_full
            shell._qm_refresh_full = false
            if shell.refreshQuickMenu then
                -- refreshQuickMenu paints once. A full refresh is that one paint.
                shell:refreshQuickMenu(full_paint)
            else
                shell:refresh()
                if full_paint then
                    UIManager:setDirty("all", "full")
                end
            end
        end)
        shell._qm_updating = false
        if not ok then
            logger.warn("modern_menu: quickmenu refresh failed: " .. tostring(err))
        end
        if not shell._qm_refresh_pending or shell._qm_followup then
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
            end
        end)
    end

    function shim:backToUpperMenu(no_close)
        return shell:backToUpperMenu(no_close)
    end

    -- Custom buttons call this, then Dispatcher:execute (sendEvent).
    -- sendEvent only reaches the app once this window is no longer on top.
    -- Stock TouchMenu closes immediately; the shell defers so a card tap
    -- does not free widgets mid-gesture. Drop the window now, and free it
    -- on the next tick after this handler has returned.
    function shim:closeMenu()
        if shell._closing then
            return true
        end
        shell._closing = true
        local cb = shell.close_callback
        shell.close_callback = nil
        local parent = shell.show_parent or shell
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
        UIManager:nextTick(function()
            Settings.flushPending()
            if cb then
                cb()
            else
                UIManager:close(parent, "ui")
            end
            UIManager:setDirty("all", "ui")
        end)
        return true
    end

    -- Simple UI's quick-settings hold calls onClose, then opens its window.
    function shim:onClose()
        return shim:closeMenu()
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
    shim.padding = shim.padding or Size.padding.default
    shim.item_width = panel_column(shell)
    shim.width = shim.item_width + shim.padding * 2
    -- Same stack the shell pops on Back. Neo's settings button no-ops without it.
    shim.item_table_stack = shell.item_table_stack
    local nested = shell.item_table_stack and #shell.item_table_stack > 0
    if nested then
        -- Card navigation writes the shell. A button callback writes the shim
        -- first; updateItems copies that onto the shell before we get here.
        if shell.item_table then
            shim.item_table = shell.item_table
        end
    else
        shim.item_table = tab
    end
    shim.touch_menu_callback = shell.touch_menu_callback
end

-- Neo asks IconWidget for names like "quick_wifi" and "quick_connections_new".
-- Those files live under icons/Dark_icons/ (often without the _new suffix), so
-- the name lookup misses and the circle is drawn empty.
local icons_ready = false
local function publish_plugin_icons(panel_fn)
    if icons_ready or type(panel_fn) ~= "function" or not debug or not debug.getinfo then
        return
    end
    local ok_info, info = pcall(debug.getinfo, panel_fn, "S")
    if not ok_info or not info or type(info.source) ~= "string" then
        return
    end
    local src = info.source
    if src:sub(1, 1) == "@" then
        src = src:sub(2)
    end
    local root = src:match("^(.*)/[^/]+$")
    if not root then
        return
    end
    local ok_lfs, lfs = pcall(require, "libs/libkoreader-lfs")
    if not ok_lfs or not lfs then
        return
    end
    local icons_dir = root .. "/icons/"
    if lfs.attributes(icons_dir, "mode") ~= "directory" then
        return
    end
    local iw = require("ui/widget/iconwidget")
    local init_fn = rawget(iw, "init") or iw.init
    if type(init_fn) ~= "function" or not debug.getupvalue then
        return
    end
    local icons_path, icons_dirs
    for i = 1, 64 do
        local uname, uval = debug.getupvalue(init_fn, i)
        if not uname then
            break
        end
        if uname == "ICONS_PATH" and type(uval) == "table" then
            icons_path = uval
        elseif uname == "ICONS_DIRS" and type(uval) == "table" then
            icons_dirs = uval
        end
    end
    if not icons_path then
        return
    end
    local function stock_has(name)
        if not icons_dirs then
            return false
        end
        for _, dir in ipairs(icons_dirs) do
            for _, ext in ipairs({ ".svg", ".png" }) do
                if lfs.attributes(dir .. "/" .. name .. ext, "mode") == "file" then
                    return true
                end
            end
        end
        return false
    end
    local found = {}
    local function scan(dir, depth)
        for file in lfs.dir(dir) do
            if file ~= "." and file ~= ".." then
                local path = dir .. file
                local mode = lfs.attributes(path, "mode")
                if mode == "file" then
                    local name = file:match("^(.+)%.[^.]+$")
                    if name and not found[name] then
                        found[name] = path
                    end
                elseif mode == "directory" and depth < 2 then
                    scan(path .. "/", depth + 1)
                end
            end
        end
    end
    local ok_scan, err = pcall(scan, icons_dir, 0)
    if not ok_scan then
        logger.warn("modern_menu: icon index failed: " .. tostring(err))
        return
    end
    for name, path in pairs(found) do
        if not icons_path[name] and not stock_has(name) then
            icons_path[name] = path
        end
    end
    -- Button defs ask for quick_connections_new while the file is quick_connections.
    for name, path in pairs(found) do
        if not name:match("_new$") then
            local newer = name .. "_new"
            if not found[newer] and not icons_path[newer] and not stock_has(newer) then
                icons_path[newer] = path
            end
        end
    end
    icons_ready = true
end

local function tree_has_method(widget, method, seen)
    if type(widget) ~= "table" or seen[widget] then
        return false
    end
    seen[widget] = true
    if type(widget[method]) == "function" then
        return true
    end
    for i = 1, #widget do
        if tree_has_method(widget[i], method, seen) then
            return true
        end
    end
    return false
end

local function any_window_handles(method)
    local stack = UIManager._window_stack
    if not stack then
        return false
    end
    local seen = {}
    for i = 1, #stack do
        local entry = stack[i]
        local widget = entry and (entry.widget or entry)
        if tree_has_method(widget, method, seen) then
            return true
        end
    end
    return false
end

local function is_sort_widget(widget)
    return type(widget) == "table"
        and type(widget.moveItem) == "function"
        and type(widget._populateItems) == "function"
        and type(widget.item_table) == "table"
        and widget.main_content ~= nil
end

local function sort_item_at(widget, pos)
    local content = widget.main_content
    if not content or not pos or not pos.intersectWith then
        return nil
    end
    for _, child in ipairs(content) do
        if child.index and child.dimen and pos:intersectWith(child.dimen) then
            return child.index
        end
    end
    return nil
end

local function patch_sort_rows(widget)
    local content = widget.main_content
    if not content then
        return
    end
    for _, child in ipairs(content) do
        if child.index then
            -- Stock rows only highlight on tap. Hold starts a drag.
            child.onHoldTouch = function(row)
                widget.marked = row.index
                widget._mm_dragging = true
                widget:_populateItems()
                return true
            end
        end
    end
end

-- Neo's exit and restart buttons open a swipe-to-confirm dialog. A phone
-- flick is often a swipe, and that dialog only listened for a slow pan, so
-- the knob never moved. A horizontal swipe now drives the same track.
local function is_slide_confirm(widget)
    return type(widget) == "table"
        and widget.track
        and type(widget.onPan) == "function"
        and widget.on_confirm
end

local function arm_slide_confirm(widget)
    widget._mm_slide = true
    widget.modal = true
    local range = Geom:new{
        x = 0, y = 0,
        w = Screen:getWidth(),
        h = Screen:getHeight(),
    }
    widget.ges_events = widget.ges_events or {}
    widget.ges_events.Swipe = {
        GestureRange:new{ ges = "swipe", range = range },
    }
    function widget:onSwipe(_, ges)
        local track = self.track
        if not track or not ges or not ges.pos then
            return true
        end
        local dir = ges.direction
        local sign = 0
        if dir == "east" or dir == "northeast" or dir == "southeast" then
            sign = 1
        elseif dir == "west" or dir == "northwest" or dir == "southwest" then
            sign = -1
        end
        if sign ~= 0 then
            local end_x = ges.pos.x + sign * (ges.distance or 0)
            local end_ges = { pos = { x = end_x, y = ges.pos.y }, direction = dir }
            if track.onPan then
                track:onPan(nil, end_ges)
            end
            if track.onPanRelease then
                track:onPanRelease(nil, end_ges)
            end
        end
        return true
    end
end

local function raise_window(widget)
    local stack = UIManager._window_stack
    if not stack then
        return
    end
    for i = #stack, 1, -1 do
        if stack[i].widget == widget then
            if i < #stack then
                local window = table.remove(stack, i)
                stack[#stack + 1] = window
            end
            return
        end
    end
end

-- Lua functions cannot hold fields. Same table main.lua uses to unlink
-- the menu's show wrapper when this layer is stacked above it.
local function show_links()
    local links = UIManager._mm_show_links
    if not links then
        links = setmetatable({}, { __mode = "k" })
        UIManager._mm_show_links = links
    end
    return links
end

-- Neo labels this "Drag & Drop" and opens KOReader's SortWidget. That widget
-- is not modal, so it was inserted under this menu and never saw the drag.
-- Hold a row, then drag it to a new slot. Tap still selects; the arrows still move.
local function install_sort_drag()
    if UIManager._mm_sort_installed then
        return
    end
    UIManager._mm_sort_installed = true
    -- Call the previous show through the link table so a later wrapper can
    -- be unlinked without leaving this closure holding the open menu.
    local function sort_show(self, widget, ...)
        if is_slide_confirm(widget) and not widget._mm_slide then
            arm_slide_confirm(widget)
        end
        if is_sort_widget(widget) and not widget._mm_drag then
            widget._mm_drag = true
            widget.modal = true
            local range = widget.dimen or Geom:new{
                x = 0, y = 0,
                w = Screen:getWidth(),
                h = Screen:getHeight(),
            }
            widget.ges_events = widget.ges_events or {}
            widget.ges_events.ModernSortPan = {
                GestureRange:new{ ges = "hold_pan", range = range },
            }
            widget.ges_events.ModernSortRelease = {
                GestureRange:new{ ges = "hold_release", range = range },
            }
            function widget:onModernSortPan(_, ges)
                if not self._mm_dragging or not ges or not ges.pos then
                    return false
                end
                local idx = sort_item_at(self, ges.pos)
                if idx and idx ~= self.marked then
                    self:moveItem(idx - self.marked)
                end
                return true
            end
            function widget:onModernSortRelease()
                self._mm_dragging = false
                return true
            end
            local orig_populate = widget._populateItems
            function widget:_populateItems(...)
                orig_populate(self, ...)
                patch_sort_rows(self)
            end
            patch_sort_rows(widget)
        end
        local prev = show_links()[sort_show].prev
        local shown = prev(self, widget, ...)
        if is_slide_confirm(widget) then
            raise_window(widget)
            UIManager:setDirty(widget, "ui")
        end
        return shown
    end
    show_links()[sort_show] = { prev = UIManager.show, layer = "sort" }
    UIManager.show = sort_show
end

-- KOReader's SSH plugin handles ToggleSSHServer. Neo broadcasts ToggleSshServer.
-- FileBrowser+ uses the name Neo already sends; if that plugin is not loaded the
-- tap would otherwise do nothing.
local function install_event_aliases()
    if UIManager._mm_neo_broadcast then
        return
    end
    local orig = UIManager.broadcastEvent
    UIManager._mm_neo_broadcast = orig
    local alias = {
        ToggleSshServer = "ToggleSSHServer",
    }
    local missing = {
        ToggleSshServer = {
            methods = { "onToggleSshServer", "onToggleSSHServer" },
            text = _("SSH plugin is not installed."),
        },
        ToggleFilebrowserPlusServer = {
            methods = { "onToggleFilebrowserPlusServer" },
            text = _("FileBrowser+ plugin is not installed."),
        },
    }
    function UIManager:broadcastEvent(event)
        local handled = orig(self, event)
        local name = event and event.handler and event.handler:sub(3)
        local alt = name and alias[name]
        if alt then
            local extra = Event:new(alt)
            extra.args = event.args
            if orig(self, extra) then
                handled = true
            end
        end
        local note = name and missing[name]
        if note then
            local present = false
            for _, method in ipairs(note.methods) do
                if any_window_handles(method) then
                    present = true
                    break
                end
            end
            if not present then
                UIManager:show(InfoMessage:new{
                    text = note.text,
                    timeout = 2,
                })
            end
        end
        return handled
    end
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

local function widget_contains(root, target, seen)
    if root == target then
        return true
    end
    if type(root) ~= "table" then
        return false
    end
    seen = seen or {}
    if seen[root] then
        return false
    end
    seen[root] = true
    for _, child in ipairs(root) do
        if widget_contains(child, target, seen) then
            return true
        end
    end
    return false
end

-- Neo appends brightness and warmth under the button rows. Pull those
-- blocks out so the shell can pin them under the list instead of cropping
-- them. A favorite-group frame replaces them, and then this is a no-op.
local function detach_slider_blocks(panel, refs)
    local sliders = refs and refs.sliders
    if not panel or not sliders or #sliders == 0 then
        return nil
    end
    local keep, blocks = {}, {}
    for _, child in ipairs(panel) do
        local holds = false
        for _, entry in ipairs(sliders) do
            local slider = type(entry) == "table" and (entry.slider or entry) or nil
            if slider and widget_contains(child, slider) then
                holds = true
                break
            end
        end
        if holds then
            blocks[#blocks + 1] = child
        else
            keep[#keep + 1] = child
        end
    end
    if #blocks == 0 then
        return nil
    end
    for i = #panel, 1, -1 do
        panel[i] = nil
    end
    for i, child in ipairs(keep) do
        panel[i] = child
    end
    if panel.resetLayout then
        panel:resetLayout()
    end
    local group = VerticalGroup:new{ align = "center" }
    for _, block in ipairs(blocks) do
        table.insert(group, block)
    end
    return group
end

local function wrap_panel(shell, panel)
    local content_w = shell.list_content_w or shell.dimen.w
    local size = panel.getSize and panel:getSize()
    return GestureLayer:new{
        shell = shell,
        CenterContainer:new{
            dimen = Geom:new{
                w = content_w,
                h = size and size.h or 0,
            },
            panel,
        },
    }
end

--- Simple UI's tab has no item list. The buttons live in buildPanel.
-- @return widget|false, footer|nil, err|nil  false means this is not that tab
local function fill_simpleui(shell, tab)
    local nested = shell.item_table_stack and #shell.item_table_stack > 0
    if nested or not tab or not tab._sui_qs_panel then
        return false
    end
    local build, gesture = simpleui_builders()
    local shim = shell._qm_touch
    if not shim or type(shim.updateItems) ~= "function" then
        shim = make_shim(shell, tab)
    end
    sync_shim(shim, shell, tab)
    shell._qm_touch = shim
    -- A previous Neo visit leaves slider refs on this shim. A tap must not
    -- hit those after the page has switched to Simple UI.
    shim._qs_refs = nil
    shim._qm_refs = nil
    shim._sui_qs_gesture = gesture
    if type(build) ~= "function" then
        shim._sui_qs_refs = nil
        shim._sui_qs_panel_widget = nil
        logger.warn("modern_menu: simpleui panel builder missing")
        return nil, nil, "simpleui panel unavailable"
    end
    local ok, panel, refs = pcall(build, shim)
    if not ok or type(panel) ~= "table" or not panel.paintTo then
        shim._sui_qs_refs = nil
        shim._sui_qs_panel_widget = nil
        logger.warn("modern_menu: simpleui panel failed: " .. tostring(panel))
        return nil, nil, panel
    end
    shim._sui_qs_refs = refs
    shim._sui_qs_panel_widget = panel
    return wrap_panel(shell, panel), nil, nil
end

--- Build the Quick Menu body for the current tab.
-- @return widget|nil, footer|nil, err|nil
function QuickMenuHost.fill(shell)
    shell._qm_pinned_sliders = nil
    local tab = shell.tab_item_table and shell.tab_item_table[shell.last_index]
    local sui_panel, sui_footer, sui_err = fill_simpleui(shell, tab)
    if sui_panel ~= false then
        return sui_panel, sui_footer, sui_err
    end
    if shell._qm_touch then
        shell._qm_touch._sui_qs_refs = nil
        shell._qm_touch._sui_qs_gesture = nil
        shell._qm_touch._sui_qs_panel_widget = nil
    end
    local nested = shell.item_table_stack and #shell.item_table_stack > 0
    local show_panel = tab and tab.panel ~= nil and not nested
    local quick_tab = tab and tab.id == "quick_menu_tab"
    local plugin = QuickMenuHost.findPlugin(shell.ui, tab)
    local footer_cfg = plugin and plugin.config and plugin.config.sections and plugin.config.sections.footer
    local show_footer = false
    if footer_cfg and (quick_tab or footer_cfg.show_all_tab) then
        show_footer = true
    elseif quick_tab then
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
    end
    -- The first build used to skip this. Neo's settings button checks
    -- item_table_stack and does nothing until a later tab switch synced it.
    sync_shim(shim, shell, tab)
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
        if tab.id == "neo_quicksettings" then
            install_event_aliases()
            install_sort_drag()
            publish_plugin_icons(tab.panel)
        end
        panel_widget, panel_err = build_panel(tab, shim)
        if panel_err then
            logger.warn("modern_menu: quickmenu panel failed: " .. tostring(panel_err))
        end
        if panel_widget and tab.id == "neo_quicksettings" then
            local blocks = detach_slider_blocks(panel_widget, shim._qs_refs or shim._qm_refs)
            if blocks then
                local content_w = shell.list_content_w or shell.dimen.w
                local block_size = blocks:getSize()
                shell._qm_pinned_sliders = GestureLayer:new{
                    shell = shell,
                    CenterContainer:new{
                        dimen = Geom:new{
                            w = content_w,
                            h = block_size and block_size.h or 0,
                        },
                        blocks,
                    },
                }
            end
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
