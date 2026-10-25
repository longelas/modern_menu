--[[--
Modern Menu — replaces KOReader's stock TouchMenu with a card-based shell
that renders the live menu item tree (same callbacks/submenus).
Also mounts a Clara-style status bar in the menu and (optionally) file manager.
Never mounts a status bar in the reader — stock CRE/header customization covers that.

@module koplugin.modern_menu
--]]

local plugin_dir = debug.getinfo(1, "S").source:match("@(.*/)")
if plugin_dir then
    package.path = plugin_dir .. "?.lua;" .. plugin_dir .. "?/init.lua;" .. package.path
end

local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Dispatcher = require("dispatcher")
local Event = require("ui/event")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template
local Screen = Device.screen

local ModernMenuShell = require("ui/menu_shell")
local QuickMenuHost = require("ui/quickmenu_host")
local ShortcutsHost = require("ui/shortcuts_host")
local Settings = require("settings")
local StatusBar = require("widgets/status_bar")

local ModernMenu = InputContainer:extend{
    name = "modern_menu",
    is_doc_only = false,
    -- When true, stock TouchMenu is used (escape hatch via Dispatcher)
    use_stock_menu = false,
}

function ModernMenu:onDispatcherRegisterActions()
    Dispatcher:registerAction("modern_menu_show", {
        category = "none",
        event = "ShowModernMenu",
        title = _("Modern menu"),
        general = true,
    })
    Dispatcher:registerAction("modern_menu_toggle_stock", {
        category = "none",
        event = "ToggleStockMenu",
        title = _("Toggle stock KOReader menu"),
        general = true,
    })
end

--- Open whichever menu is actually alive under a Kobold screen.
-- Opening a book closes the file manager, so Kobold's own top-edge
-- forward has nothing to call and the pull-down stops working.
local function open_menu_on_kobold(ges)
    local menu
    local ok_fm, FileManager = pcall(require, "apps/filemanager/filemanager")
    if ok_fm and FileManager and FileManager.instance and FileManager.instance.menu then
        menu = FileManager.instance.menu
    end
    if not menu then
        local ok_reader, ReaderUI = pcall(require, "apps/reader/readerui")
        if ok_reader and ReaderUI and ReaderUI.instance and ReaderUI.instance.menu then
            menu = ReaderUI.instance.menu
        end
    end
    if not menu then
        return false
    end
    if ges and type(menu.onSwipeShowMenu) == "function" then
        return menu:onSwipeShowMenu(ges) == true
    end
    if type(menu.onShowMenu) == "function" then
        return menu:onShowMenu() == true
    end
    return false
end

local kobold_show_wrapped = false

--- Top-edge swipe and the menu key keep working on every Kobold screen.
function ModernMenu._armKoboldScreen(screen)
    if not screen or screen._mm_kobold_armed or type(screen.registerTouchZones) ~= "function" then
        return
    end
    screen._mm_kobold_armed = true
    screen:registerTouchZones({
        {
            id = "KoboldTopMenu",
            ges = "swipe",
            screen_zone = {
                ratio_x = 0,
                ratio_y = 0,
                ratio_w = 1,
                ratio_h = 1 / 8,
            },
            handler = function(ges)
                if not ges or ges.direction ~= "south" then
                    return false
                end
                return open_menu_on_kobold(ges)
            end,
        },
    })
    screen.key_events = screen.key_events or {}
    screen.key_events.OpenModernMenu = { { "Menu" } }
    screen.onOpenModernMenu = function()
        return open_menu_on_kobold()
    end
end

function ModernMenu:_installKoboldMenuAccess()
    if kobold_show_wrapped then
        return
    end
    kobold_show_wrapped = true
    local orig_show = UIManager.show
    UIManager.show = function(ui_mgr, widget, ...)
        orig_show(ui_mgr, widget, ...)
        if widget and widget.kobold_tab then
            ModernMenu._armKoboldScreen(widget)
        end
    end
end

function ModernMenu:init()
    self:_installKoboldMenuAccess()
    self:_installPackagePath()
    self:onDispatcherRegisterActions()
    self.use_stock_menu = G_reader_settings and G_reader_settings:isTrue("modern_menu_use_stock") or false

    self:_registerMainMenu()

    local function boot()
        self:installMenuHook()
        self:installStatusChrome()
        self:_hookFileManagerMenuGesture()
        self:_registerMainMenu()
        ShortcutsHost.installReplayHook(self.ui)
        ShortcutsHost.ensureFileBrowserBar(self.ui)
    end

    -- FileManager: postInit runs after setupLayout (title bar exists).
    -- Fallback to nextTick if postInit already flushed.
    if self.ui and self.ui.registerPostInitCallback and self.ui.postInitCallback then
        self.ui:registerPostInitCallback(boot)
    else
        UIManager:nextTick(boot)
    end
end

local function menu_font_items()
    local Font = require("ui/font")
    local cre
    local ok_cre, engine = pcall(function()
        return require("document/credocument"):engineInit()
    end)
    if ok_cre then
        cre = engine
    end
    local function file_for(name)
        if not cre or not cre.getFontFaceFilenameAndFaceIndex then
            return nil, nil
        end
        local file, index = cre.getFontFaceFilenameAndFaceIndex(name)
        if not file then
            file, index = cre.getFontFaceFilenameAndFaceIndex(name, nil, true)
        end
        return file, index
    end
    local items = {
        {
            text = _("KOReader default"),
            radio = true,
            keep_menu_open = true,
            checked_func = function()
                return Settings.getMenuFont() == nil
            end,
            callback = function(touchmenu_instance)
                Settings.setMenuFont(nil)
                if touchmenu_instance then
                    touchmenu_instance:updateItems()
                end
            end,
        },
    }
    local faces, labels = Settings.fontChoices()
    for i, face_name in ipairs(faces) do
        local file, index = file_for(face_name)
        items[#items + 1] = {
            text = labels[i] or face_name,
            radio = true,
            keep_menu_open = true,
            checked_func = function()
                return Settings.getMenuFont() == face_name
            end,
            -- Draw the row in the font it names, the same way KOReader's font menu does.
            font_func = function(size)
                if file then
                    return Font:getFace(file, size, index)
                end
            end,
            callback = function(touchmenu_instance)
                Settings.setMenuFont(face_name)
                if touchmenu_instance then
                    touchmenu_instance:updateItems()
                end
            end,
        }
    end
    if #faces == 0 then
        items[#items + 1] = {
            text = _("No additional fonts found"),
            enabled = false,
        }
    end
    return items
end

function ModernMenu:_defaultTabItems()
    local items = {
        {
            text = _("Automatic"),
            checked_func = function()
                return Settings.getDefaultTabId() == nil
            end,
            radio = true,
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                Settings.setDefaultTabId(nil)
                if touchmenu_instance then
                    touchmenu_instance:updateItems()
                end
            end,
        },
    }
    local menu = self.ui and self.ui.menu
    local tabs = menu and menu.tab_item_table
    if type(tabs) ~= "table" then
        return items
    end
    for i, tab in ipairs(tabs) do
        local key = Settings.tabKey(tab)
        if key then
            items[#items + 1] = {
                text = ModernMenuShell.tabCaption(tab, i, false),
                checked_func = function()
                    return Settings.getDefaultTabId() == key
                end,
                radio = true,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    Settings.setDefaultTabId(key)
                    if touchmenu_instance then
                        touchmenu_instance:updateItems()
                    end
                end,
            }
        end
    end
    return items
end

function ModernMenu:addToMainMenu(menu_items)
    menu_items.modern_menu = {
        text = _("Modern Menu"),
        sorting_hint = "more_tools",
        sub_item_table = {
            {
                text = _("Status bar in file browser"),
                checked_func = function()
                    return StatusBar.elsewhereEnabled()
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    StatusBar.setElsewhereEnabled(not StatusBar.elsewhereEnabled())
                    if touchmenu_instance then
                        touchmenu_instance:updateItems()
                    end
                end,
            },
            {
                text = _("Hide status bar"),
                checked_func = function()
                    return Settings.getHideStatusBar()
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    Settings.setHideStatusBar(not Settings.getHideStatusBar())
                    if touchmenu_instance then
                        touchmenu_instance:updateItems()
                    end
                end,
            },
            {
                text = _("Battery as percentage"),
                checked_func = function()
                    return Settings.getBatteryPercent()
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    Settings.setBatteryPercent(not Settings.getBatteryPercent())
                    if touchmenu_instance then
                        touchmenu_instance:updateItems()
                    end
                    -- The file-browser bar is a separate widget. Refresh it
                    -- now so the icon and the percentage do not wait on Wi-Fi.
                    if self.status_bar and self.status_bar.refresh then
                        self.status_bar:refresh()
                    end
                end,
            },
            {
                text_func = function()
                    local name = Settings.getMenuFont()
                    if not name then
                        return _("Menu font: KOReader default")
                    end
                    return T(_("Menu font: %1"), name)
                end,
                sub_item_table_func = menu_font_items,
            },
            {
                text_func = function()
                    return T(_("Tab label size: %1"), Settings.getTabFontSize())
                end,
                enabled_func = function()
                    return not Settings.getTabIconsOnly()
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local SpinWidget = require("ui/widget/spinwidget")
                    UIManager:show(SpinWidget:new{
                        title_text = _("Tab label size"),
                        info_text = _("Font size for tab titles in the menu header."),
                        value = Settings.getTabFontSize(),
                        value_min = Settings.MIN_TAB_FONT_SIZE,
                        value_max = Settings.MAX_TAB_FONT_SIZE,
                        default_value = Settings.DEFAULT_TAB_FONT_SIZE,
                        value_step = 1,
                        value_hold_step = 2,
                        ok_text = _("Set"),
                        callback = function(spin)
                            if not spin then return end
                            Settings.setTabFontSize(spin.value)
                            if touchmenu_instance then
                                touchmenu_instance:updateItems()
                            end
                        end,
                    })
                end,
            },
            {
                text = _("Icons only (hide tab labels)"),
                checked_func = function()
                    return Settings.getTabIconsOnly()
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    Settings.setTabIconsOnly(not Settings.getTabIconsOnly())
                    -- Prefer a larger icon when switching to icons-only if still on the
                    -- label-mode default, so phones get usable targets immediately.
                    if Settings.getTabIconsOnly() then
                        local current = Settings.getTabIconSize()
                        if current == Settings.DEFAULT_TAB_ICON_SIZE then
                            Settings.setTabIconSize(Settings.DEFAULT_TAB_ICON_SIZE_ICONS_ONLY)
                        end
                    end
                    if touchmenu_instance then
                        touchmenu_instance:updateItems()
                    end
                end,
            },
            {
                text_func = function()
                    return T(_("Tab icon size: %1"), Settings.getTabIconSize())
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local SpinWidget = require("ui/widget/spinwidget")
                    UIManager:show(SpinWidget:new{
                        title_text = _("Tab icon size"),
                        info_text = _("Size of appbar icons in the menu header."),
                        value = Settings.getTabIconSize(),
                        value_min = Settings.MIN_TAB_ICON_SIZE,
                        value_max = Settings.MAX_TAB_ICON_SIZE,
                        default_value = Settings.getTabIconsOnly()
                            and Settings.DEFAULT_TAB_ICON_SIZE_ICONS_ONLY
                            or Settings.DEFAULT_TAB_ICON_SIZE,
                        value_step = 1,
                        value_hold_step = 2,
                        ok_text = _("Set"),
                        callback = function(spin)
                            if not spin then return end
                            Settings.setTabIconSize(spin.value)
                            if touchmenu_instance then
                                touchmenu_instance:updateItems()
                            end
                        end,
                    })
                end,
            },
            {
                text_func = function()
                    return T(_("Option font size: %1"), Settings.getOptionFontSize())
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local SpinWidget = require("ui/widget/spinwidget")
                    UIManager:show(SpinWidget:new{
                        title_text = _("Option font size"),
                        info_text = _("Font size for menu option rows."),
                        value = Settings.getOptionFontSize(),
                        value_min = Settings.MIN_OPTION_FONT_SIZE,
                        value_max = Settings.MAX_OPTION_FONT_SIZE,
                        default_value = Settings.DEFAULT_OPTION_FONT_SIZE,
                        value_step = 1,
                        value_hold_step = 2,
                        ok_text = _("Set"),
                        callback = function(spin)
                            if not spin then return end
                            Settings.setOptionFontSize(spin.value)
                            if touchmenu_instance then
                                touchmenu_instance:updateItems()
                            end
                        end,
                    })
                end,
            },
            {
                text_func = function()
                    return T(_("Option padding: %1"), Settings.getOptionPadding())
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local SpinWidget = require("ui/widget/spinwidget")
                    UIManager:show(SpinWidget:new{
                        title_text = _("Option padding"),
                        info_text = _("Vertical padding inside each menu option row."),
                        value = Settings.getOptionPadding(),
                        value_min = Settings.MIN_OPTION_PADDING,
                        value_max = Settings.MAX_OPTION_PADDING,
                        default_value = Settings.DEFAULT_OPTION_PADDING,
                        value_step = 1,
                        value_hold_step = 2,
                        ok_text = _("Set"),
                        callback = function(spin)
                            if not spin then return end
                            Settings.setOptionPadding(spin.value)
                            if touchmenu_instance then
                                touchmenu_instance:updateItems()
                            end
                        end,
                    })
                end,
            },
            {
                text = _("Pure black (no greys)"),
                checked_func = function()
                    return Settings.getPureBlack()
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    Settings.setPureBlack(not Settings.getPureBlack())
                    if touchmenu_instance then
                        touchmenu_instance:updateItems()
                    end
                end,
            },
            {
                text_func = function()
                    local id = Settings.getDefaultTabId()
                    if not id then
                        return _("Default tab: Automatic")
                    end
                    local menu = self.ui and self.ui.menu
                    local tabs = menu and menu.tab_item_table
                    if type(tabs) == "table" then
                        for i, tab in ipairs(tabs) do
                            if Settings.tabKey(tab) == id then
                                return T(_("Default tab: %1"), ModernMenuShell.tabCaption(tab, i, false))
                            end
                        end
                    end
                    return T(_("Default tab: %1"), id)
                end,
                sub_item_table_func = function()
                    return self:_defaultTabItems()
                end,
            },
            {
                text_func = function()
                    local mode = Settings.getMenuHeightMode()
                    if mode == Settings.MENU_HEIGHT_CONTENT then
                        return _("Menu height: Fit content")
                    end
                    if mode == Settings.MENU_HEIGHT_PERCENT then
                        return T(_("Menu height: %1% of screen"), Settings.getMenuHeightPercent())
                    end
                    return _("Menu height: Full screen")
                end,
                sub_item_table = {
                    {
                        text = _("Full screen"),
                        checked_func = function()
                            return Settings.getMenuHeightMode() == Settings.MENU_HEIGHT_FULL
                        end,
                        radio = true,
                        keep_menu_open = true,
                        callback = function(touchmenu_instance)
                            Settings.setMenuHeightMode(Settings.MENU_HEIGHT_FULL)
                            if touchmenu_instance then
                                touchmenu_instance:updateItems()
                            end
                        end,
                    },
                    {
                        text = _("Fit content"),
                        checked_func = function()
                            return Settings.getMenuHeightMode() == Settings.MENU_HEIGHT_CONTENT
                        end,
                        radio = true,
                        keep_menu_open = true,
                        callback = function(touchmenu_instance)
                            Settings.setMenuHeightMode(Settings.MENU_HEIGHT_CONTENT)
                            if touchmenu_instance then
                                touchmenu_instance:updateItems()
                            end
                        end,
                    },
                    {
                        text_func = function()
                            return T(_("Fixed percentage: %1%"), Settings.getMenuHeightPercent())
                        end,
                        checked_func = function()
                            return Settings.getMenuHeightMode() == Settings.MENU_HEIGHT_PERCENT
                        end,
                        radio = true,
                        keep_menu_open = true,
                        callback = function(touchmenu_instance)
                            local SpinWidget = require("ui/widget/spinwidget")
                            UIManager:show(SpinWidget:new{
                                title_text = _("Menu height"),
                                info_text = _("Height of the menu as a percentage of the screen. The menu stays at the top and scrolls when the rows do not fit."),
                                value = Settings.getMenuHeightPercent(),
                                value_min = Settings.MIN_MENU_HEIGHT_PERCENT,
                                value_max = Settings.MAX_MENU_HEIGHT_PERCENT,
                                default_value = Settings.DEFAULT_MENU_HEIGHT_PERCENT,
                                value_step = 5,
                                value_hold_step = 10,
                                -- Set stays available at 70. That number is both the
                                -- stored default and the value that turns this mode on.
                                ok_always_enabled = true,
                                ok_text = _("Set"),
                                callback = function(spin)
                                    if not spin then return end
                                    Settings.setMenuHeightPercent(spin.value)
                                    Settings.setMenuHeightMode(Settings.MENU_HEIGHT_PERCENT)
                                    if touchmenu_instance then
                                        touchmenu_instance:updateItems()
                                    end
                                end,
                            })
                        end,
                    },
                },
            },
            {
                text = _("Reset to defaults"),
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local ConfirmBox = require("ui/widget/confirmbox")
                    UIManager:show(ConfirmBox:new{
                        text = _("Reset all Modern Menu settings to their defaults?"),
                        ok_text = _("Reset"),
                        ok_callback = function()
                            Settings.resetToDefaults()
                            if touchmenu_instance then
                                touchmenu_instance:updateItems()
                            end
                            local InfoMessage = require("ui/widget/infomessage")
                            UIManager:show(InfoMessage:new{
                                text = _("Modern Menu defaults restored"),
                                timeout = 2,
                            })
                        end,
                    })
                end,
            },
            {
                text = _("Use stock KOReader menu"),
                checked_func = function()
                    return self.use_stock_menu
                end,
                keep_menu_open = true,
                callback = function()
                    self:onToggleStockMenu()
                end,
            },
        },
    }
end

function ModernMenu:_installPackagePath()
    local dir = self.path or plugin_dir
    if not dir then return end
    if dir:sub(-1) ~= "/" then dir = dir .. "/" end
    local needle = dir .. "?.lua"
    if not package.path:find(needle, 1, true) then
        package.path = dir .. "?.lua;" .. dir .. "?/init.lua;" .. package.path
    end
end

function ModernMenu:_registerMainMenu()
    if self._main_menu_registered then
        return
    end
    local menu = self.ui and self.ui.menu
    if menu and menu.registerToMainMenu then
        menu:registerToMainMenu(self)
        self._main_menu_registered = true
    end
end

--- South swipe / top tap that should open the menu, or nil.
-- The zone matches KOReader's default top menu band (1/8 of the screen).
function ModernMenu:_topMenuGesture(event)
    if not event or event.handler ~= "onGesture" then
        return nil
    end
    local ges = event.args and event.args[1]
    if type(ges) ~= "table" or not ges.pos or not ges.ges then
        return nil
    end
    local zone_h = Screen:getHeight() / 8
    if ges.pos.y == nil or ges.pos.y >= zone_h then
        return nil
    end
    return ges
end

function ModernMenu:_activationMode(menu)
    local mode = menu and menu.activation_menu
    if mode == "tap" or mode == "swipe" or mode == "swipe_tap" then
        return mode
    end
    return "swipe_tap"
end

function ModernMenu:_openMenuFromGesture(menu, ges)
    if not menu or self.use_stock_menu then
        return false
    end
    local index
    if menu._getTabIndexFromLocation then
        index = menu:_getTabIndexFromLocation(ges)
    end
    return self:showModernMenu(menu, index)
end

--- Wrap every menu entry point. A later plugin can replace these methods
-- during its own startup, so the wrap is applied again on the next tick.
function ModernMenu:_applyMenuHooks(menu)
    if not menu then
        return
    end
    local plugin = self

    if type(menu.onShowMenu) == "function" and menu.onShowMenu ~= menu._mm_wrap_show then
        local previous = menu.onShowMenu
        menu._modern_menu_original_onShowMenu = previous
        local function wrapped(menu_self, tab_index, do_not_show)
            -- Menu search and explicit stock mode keep the classic TouchMenu.
            if plugin.use_stock_menu or do_not_show then
                return previous(menu_self, tab_index, do_not_show)
            end
            return plugin:showModernMenu(menu_self, tab_index)
        end
        menu._mm_wrap_show = wrapped
        menu.onShowMenu = wrapped
    end

    if type(menu.onSwipeShowMenu) == "function" and menu.onSwipeShowMenu ~= menu._mm_wrap_swipe then
        local previous = menu.onSwipeShowMenu
        local function wrapped(menu_self, ges)
            if plugin.use_stock_menu or plugin:_activationMode(menu_self) == "tap" then
                return previous(menu_self, ges)
            end
            if not ges or ges.direction ~= "south" then
                return previous(menu_self, ges)
            end
            if menu_self.ui then
                menu_self.ui:handleEvent(Event:new("HandledAsSwipe"))
            end
            return plugin:_openMenuFromGesture(menu_self, ges)
        end
        menu._mm_wrap_swipe = wrapped
        menu.onSwipeShowMenu = wrapped
    end

    if type(menu.onTapShowMenu) == "function" and menu.onTapShowMenu ~= menu._mm_wrap_tap then
        local previous = menu.onTapShowMenu
        local function wrapped(menu_self, ges)
            if plugin.use_stock_menu or plugin:_activationMode(menu_self) == "swipe" then
                return previous(menu_self, ges)
            end
            return plugin:_openMenuFromGesture(menu_self, ges)
        end
        menu._mm_wrap_tap = wrapped
        menu.onTapShowMenu = wrapped
    end

    if type(menu.onKeyPressShowMenu) == "function" and menu.onKeyPressShowMenu ~= menu._mm_wrap_key then
        local previous = menu.onKeyPressShowMenu
        local function wrapped(menu_self, ...)
            if plugin.use_stock_menu then
                return previous(menu_self, ...)
            end
            return plugin:showModernMenu(menu_self)
        end
        menu._mm_wrap_key = wrapped
        menu.onKeyPressShowMenu = wrapped
    end

    menu._modern_menu_hooked = true
    logger.info("modern_menu: hooked menu show, swipe, tap, and key")
end

function ModernMenu:installMenuHook()
    local menu = self.ui and self.ui.menu
    if not menu then
        logger.dbg("modern_menu: no ui.menu yet, will retry")
        UIManager:scheduleIn(0.5, function()
            if self.ui and self.ui.menu then
                self:installMenuHook()
            end
        end)
        return
    end
    self:_applyMenuHooks(menu)
    if not menu._modern_menu_rehook_scheduled then
        menu._modern_menu_rehook_scheduled = true
        UIManager:nextTick(function()
            if self.ui and self.ui.menu then
                self:_applyMenuHooks(self.ui.menu)
            end
        end)
    end
end

--- Top-edge swipe and tap on the file browser, before a child widget eats them.
-- Title-bar buttons still receive taps: a tap is opened as the menu only when
-- no child handled it. Sideways swipes are left to the file list.
function ModernMenu:_hookFileManagerMenuGesture()
    local fm = self.ui
    if not self:_isFileManager() or not fm or not fm.handleEvent then
        return
    end
    if fm.handleEvent == fm._mm_wrap_fm_event then
        return
    end
    local plugin = self
    local previous = fm.handleEvent
    local function wrapped(fm_self, event)
        if not plugin.use_stock_menu then
            local ges = plugin:_topMenuGesture(event)
            local menu = fm_self.menu
            if ges and ges.ges == "swipe" and ges.direction == "south"
                    and plugin:_activationMode(menu) ~= "tap" then
                plugin:_openMenuFromGesture(menu, ges)
                return true
            end
            local handled = previous(fm_self, event)
            if ges and ges.ges == "tap" and not handled
                    and plugin:_activationMode(menu) ~= "swipe" then
                plugin:_openMenuFromGesture(menu, ges)
                return true
            end
            return handled
        end
        return previous(fm_self, event)
    end
    fm._mm_wrap_fm_event = wrapped
    fm.handleEvent = wrapped
    fm._modern_menu_gesture_hooked = true
    logger.info("modern_menu: file browser top edge opens the menu")
    if not fm._modern_menu_gesture_rehook then
        fm._modern_menu_gesture_rehook = true
        UIManager:nextTick(function()
            fm._modern_menu_gesture_rehook = nil
            if plugin.ui == fm then
                plugin:_hookFileManagerMenuGesture()
            end
        end)
    end
end

function ModernMenu:_isFileManager()
    local ui = self.ui
    return ui and (ui.file_chooser ~= nil or ui.name == "FileManager")
end

function ModernMenu:_isReader()
    local ui = self.ui
    return ui and ui.document ~= nil
end

--- Mount Clara-style status bar on FileManager only (never in the reader).
function ModernMenu:installStatusChrome()
    if not self.ui then
        UIManager:scheduleIn(0.5, function()
            if self.ui then
                self:installStatusChrome()
            end
        end)
        return
    end

    if self:_isFileManager() then
        self:_hookFileManagerLayout()
        self:_hookFileManagerMenuGesture()
        if StatusBar.elsewhereEnabled() then
            self:_installFileManagerStatusBar()
        else
            self:_removeFileManagerStatusBar()
        end
    elseif self:_isReader() then
        -- Reader uses stock header/footer customization — no modern status bar
        return
    else
        UIManager:scheduleIn(0.5, function()
            self:installStatusChrome()
        end)
    end
end

--- Re-wrap after FileManager:reinit/setupLayout (rotation, keyboard, path rebuild).
function ModernMenu:_hookFileManagerLayout()
    local fm = self.ui
    if not fm or fm._modern_status_layout_hooked or not fm.setupLayout then
        return
    end
    fm._modern_status_layout_hooked = true
    local plugin = self
    local original_setup = fm.setupLayout
    fm.setupLayout = function(fm_self, ...)
        original_setup(fm_self, ...)
        fm_self._modern_status_wrapped = false
        if StatusBar.elsewhereEnabled() then
            plugin:_installFileManagerStatusBar()
        end
        -- A new file chooser drops the shortcut row the plugin inserted earlier.
        ShortcutsHost.ensureFileBrowserBar(fm_self)
    end
end

function ModernMenu:_installFileManagerStatusBar()
    if not StatusBar.elsewhereEnabled() then
        return
    end
    local fm = self.ui
    if not fm or not fm.title_bar or not fm.file_chooser then
        logger.dbg("modern_menu: FM title bar not ready, retry")
        UIManager:scheduleIn(0.3, function()
            if self.ui and self.ui.title_bar and StatusBar.elsewhereEnabled() then
                self:_installFileManagerStatusBar()
            end
        end)
        return
    end

    if fm.title_bar.name == "modern_status_title_stack" then
        self.status_bar = fm.title_bar.status_bar
        fm._modern_status_wrapped = true
        return
    end

    if self.status_bar and self.status_bar._unscheduleClock then
        self.status_bar:_unscheduleClock()
    end

    local original_title = fm.title_bar
    local status_bar = StatusBar.make{
        ui = fm,
        show_parent = fm,
        width = Screen:getWidth(),
    }
    local stack = StatusBar.StatusTitleStack:new{
        status_bar = status_bar,
        title_bar = original_title,
    }

    fm.title_bar = stack
    fm.file_chooser.title_bar = stack
    fm.file_chooser.custom_title_bar = stack
    if fm.file_chooser.content_group then
        fm.file_chooser.content_group[1] = stack
    end
    fm._modern_status_wrapped = true
    self.status_bar = status_bar

    if fm.file_chooser._recalculateDimen then
        fm.file_chooser:_recalculateDimen()
    end
    if fm.file_chooser.updateItems then
        fm.file_chooser:updateItems(1, false)
    end
    UIManager:setDirty(fm, "ui")
    logger.info("modern_menu: FileManager status bar installed")
end

function ModernMenu:_removeFileManagerStatusBar()
    local fm = self.ui
    if not fm or not fm.title_bar then
        return
    end
    if fm.title_bar.name ~= "modern_status_title_stack" then
        fm._modern_status_wrapped = false
        return
    end
    local stack = fm.title_bar
    local original = stack.title_bar
    if stack.status_bar and stack.status_bar._unscheduleClock then
        stack.status_bar:_unscheduleClock()
    end
    fm.title_bar = original
    if fm.file_chooser then
        fm.file_chooser.title_bar = original
        fm.file_chooser.custom_title_bar = original
        if fm.file_chooser.content_group then
            fm.file_chooser.content_group[1] = original
        end
        if fm.file_chooser._recalculateDimen then
            fm.file_chooser:_recalculateDimen()
        end
        if fm.file_chooser.updateItems then
            fm.file_chooser:updateItems(1, false)
        end
    end
    fm._modern_status_wrapped = false
    if self.status_bar == stack.status_bar then
        self.status_bar = nil
    end
    UIManager:setDirty(fm, "ui")
    logger.info("modern_menu: FileManager status bar removed")
end

function ModernMenu:onModernMenuStatusChromeChanged(enabled)
    -- Toggle only affects file browser (never the reader)
    if self:_isFileManager() then
        if enabled then
            self:_installFileManagerStatusBar()
        else
            self:_removeFileManagerStatusBar()
        end
    end
    return true
end

function ModernMenu:showModernMenu(menu_self, tab_index)
    if not menu_self then
        return false
    end
    if menu_self.menu_container then
        return true
    end
    local ok, err = pcall(function()
        self:_buildModernMenu(menu_self, tab_index)
    end)
    if ok then
        return true
    end
    logger.warn("modern_menu: failed to open: " .. tostring(err))
    if menu_self.menu_container then
        pcall(function()
            UIManager:close(menu_self.menu_container)
        end)
        menu_self.menu_container = nil
    end
    local original = menu_self._modern_menu_original_onShowMenu
    if original and not menu_self._modern_menu_fallback then
        menu_self._modern_menu_fallback = true
        local ok_stock, stock_err = pcall(original, menu_self, tab_index)
        menu_self._modern_menu_fallback = false
        if not ok_stock then
            logger.warn("modern_menu: stock menu failed: " .. tostring(stock_err))
            return false
        end
        return true
    end
    return false
end

--- Quick Menu, Neo Quick Settings, and Simple UI stay ahead of Kobold.
local KOBOLD_AFTER_QUICK = {
    quick_menu_tab = true,
    neo_quicksettings = true,
    _sui_qs_panel = true,
}

local function is_quick_action_tab(tab)
    return tab and (KOBOLD_AFTER_QUICK[tab.id] or tab._sui_qs_panel == true)
end

--- Kobold Home sits after any quick-action tabs and before Library.
-- Absent when the Kobold plugin is not loaded.
function ModernMenu:_insertKoboldTab(menu_self)
    local tabs = menu_self and menu_self.tab_item_table
    if type(tabs) ~= "table" then
        return
    end
    local ok_loader, PluginLoader = pcall(require, "pluginloader")
    -- The folder is Kobold.koplugin, so the loader's name is "Kobold".
    local kobold = ok_loader and PluginLoader.getPluginInstance and (
        PluginLoader:getPluginInstance("Kobold")
        or PluginLoader:getPluginInstance("kobold")
    )
    if type(kobold) ~= "table" then
        local ui = menu_self.ui
        kobold = ui and (ui.Kobold or ui.kobold)
    end
    if type(kobold) ~= "table" or type(kobold.showHome) ~= "function" then
        return
    end

    local at = 1
    while tabs[at] and is_quick_action_tab(tabs[at]) do
        at = at + 1
    end

    local existing
    for i, tab in ipairs(tabs) do
        if tab.id == "kobold_home" then
            existing = i
            break
        end
    end
    if existing then
        if existing ~= at then
            local tab = table.remove(tabs, existing)
            if existing < at then
                at = at - 1
            end
            table.insert(tabs, at, tab)
        end
        return
    end

    table.insert(tabs, at, {
        id = "kobold_home",
        text = _("Kobold"),
        icon = "home",
        -- A tap opens Kobold. It is not a page of menu rows.
        remember = false,
        callback = function()
            kobold:showHome()
        end,
    })
    -- Keep the previously selected page. The saved index lives on the menu
    -- and, before the first open this session, in KOReader's own setting.
    local saved = menu_self.last_tab_index
    if type(saved) ~= "number" and G_reader_settings then
        saved = G_reader_settings:readSetting("filemanagermenu_tab_index")
    end
    if type(saved) == "number" and saved >= at then
        menu_self.last_tab_index = saved + 1
    end
end

function ModernMenu:_buildModernMenu(menu_self, tab_index)
    if menu_self.tab_item_table == nil and menu_self.setUpdateItemTable then
        menu_self:setUpdateItemTable()
    end
    -- Quick Menu inserts its panel tab from setUpdateItemTable. Sync again
    -- so the tab is present even if that table was built earlier.
    QuickMenuHost.sync(menu_self)
    -- Reader injects the Simple UI tab from onShowMenu, which this hook
    -- replaces. Make sure the tab exists before the opening index is chosen.
    QuickMenuHost.ensureSimpleUITab(menu_self)
    self:_insertKoboldTab(menu_self)
    ShortcutsHost.installReplayHook(menu_self.ui or self.ui)

    -- Match ReaderMenu: stop selection / close bottom config
    if menu_self.ui and menu_self.ui.keyselection and menu_self.ui.keyselection.stopHighlightIndicator then
        menu_self.ui.keyselection:stopHighlightIndicator(true)
    end
    if menu_self.ui then
        menu_self.ui:handleEvent(Event:new("CloseConfigMenu"))
    end

    -- UIManager only honors modal / covers_fullscreen on the window it is
    -- given. The shell's own flags are ignored, so a library screen stacked
    -- above a plain container never paints this menu.
    local full_height = Settings.getMenuHeightMode() == Settings.MENU_HEIGHT_FULL
    local menu_container = CenterContainer:new{
        covers_header = true,
        ignore = "height",
        dimen = Screen:getSize(),
        modal = true,
        -- A short sheet leaves the library or file list visible underneath.
        covers_fullscreen = full_height and true or false,
    }

    local shell = ModernMenuShell:new{
        width = Screen:getWidth(),
        last_index = QuickMenuHost.initialIndex(menu_self, tab_index),
        tab_item_table = menu_self.tab_item_table,
        ui = menu_self.ui or self.ui,
        show_parent = menu_container,
    }

    local function finish_close()
        if menu_self.onCloseReaderMenu then
            menu_self:onCloseReaderMenu()
        elseif menu_self.onCloseFileManagerMenu then
            menu_self:onCloseFileManagerMenu()
        else
            UIManager:close(menu_container)
            menu_self.menu_container = nil
        end
    end

    -- System shortcuts call close_callback(), then Dispatcher:execute.
    -- The window has to be off the stack before that sendEvent. Full
    -- teardown waits a tick so the icon handler can finish.
    -- A modal menu is painted above ordinary windows, so a font-size dialog
    -- or battery screen opened from it would land underneath and stay hidden.
    -- Keep those windows above this one for as long as the menu is open.
    local orig_show = UIManager.show
    -- Lua functions cannot hold fields. Wrappers share this table so a
    -- later layer (Neo's sort hook) can be spliced out without keeping
    -- the open menu alive.
    local function show_links()
        local links = UIManager._mm_show_links
        if not links then
            links = setmetatable({}, { __mode = "k" })
            UIManager._mm_show_links = links
        end
        return links
    end
    local function menu_stack_index()
        local stack = UIManager._window_stack
        if not stack then
            return nil
        end
        for i = #stack, 1, -1 do
            if stack[i].widget == menu_container then
                return i
            end
        end
    end
    local function lift_above_menu(widget)
        local menu_i = menu_stack_index()
        local stack = UIManager._window_stack
        if not menu_i or not stack or widget == menu_container then
            return
        end
        local widget_i
        for i = #stack, 1, -1 do
            if stack[i].widget == widget then
                widget_i = i
                break
            end
        end
        if not widget_i or widget_i > menu_i then
            return
        end
        local window = table.remove(stack, widget_i)
        table.insert(stack, window)
        UIManager:setDirty(widget, "ui")
    end
    local function wrapped_show(ui_mgr, widget, ...)
        local prev = show_links()[wrapped_show].prev
        prev(ui_mgr, widget, ...)
        if not widget or widget == menu_container or not menu_stack_index() then
            return
        end
        -- Kobold replaces the screen. Drop the menu so it is not left on top.
        if widget.kobold_tab then
            shell:closeMenu()
            return
        end
        lift_above_menu(widget)
    end
    show_links()[wrapped_show] = { prev = orig_show, layer = "menu" }
    UIManager.show = wrapped_show
    local function restore_show()
        local links = show_links()
        if UIManager.show == wrapped_show then
            UIManager.show = orig_show
            links[wrapped_show] = nil
            return
        end
        -- A Neo sort wrapper may have been installed on top of this one.
        -- Splice this layer out so its closure can drop the shell.
        local current = UIManager.show
        local guard = 0
        while type(current) == "function" and guard < 8 do
            local link = links[current]
            local prev = link and link.prev
            if prev == wrapped_show then
                link.prev = orig_show
                links[wrapped_show] = nil
                return
            end
            current = prev
            guard = guard + 1
        end
    end

    shell.close_callback = function()
        restore_show()
        if shell._closing then
            finish_close()
            return
        end
        shell._closing = true
        shell:unlinkFromStack()
        UIManager:nextTick(function()
            finish_close()
            UIManager:setDirty("all", "ui")
        end)
    end

    shell.touch_menu_callback = function()
        if menu_self.ui then
            menu_self.ui:handleEvent(Event:new("CloseConfigMenu"))
        end
    end

    menu_container[1] = shell
    -- ScrollableContainer only crops inner repaints when this sits on the
    -- widget passed to UIManager:show. The shell is not that window.
    menu_container.cropping_widget = shell.scroll_container
    menu_self.menu_container = menu_container
    UIManager:show(menu_container)
    UIManager:setDirty(menu_container, "ui")
    return true
end

function ModernMenu:onShowModernMenu()
    if self.ui and self.ui.menu and self.ui.menu.onShowMenu then
        return self.ui.menu:onShowMenu()
    end
    return true
end

function ModernMenu:onToggleStockMenu()
    self.use_stock_menu = not self.use_stock_menu
    if G_reader_settings then
        G_reader_settings:saveSetting("modern_menu_use_stock", self.use_stock_menu)
        G_reader_settings:flush()
    end
    local InfoMessage = require("ui/widget/infomessage")
    UIManager:show(InfoMessage:new{
        text = self.use_stock_menu
            and _("Stock KOReader menu enabled")
            or _("Modern menu enabled"),
        timeout = 2,
    })
    return true
end

function ModernMenu:onSetDimensions(dimen)
    if self:_isFileManager() then
        self:_hookFileManagerLayout()
        if StatusBar.elsewhereEnabled() then
            if not self.ui.title_bar or self.ui.title_bar.name ~= "modern_status_title_stack" then
                self.ui._modern_status_wrapped = false
                self:_installFileManagerStatusBar()
            elseif self.status_bar then
                self.status_bar.width = Screen:getWidth()
                self.status_bar.dimen.w = Screen:getWidth()
                self.status_bar:refresh()
            end
        else
            self:_removeFileManagerStatusBar()
        end
    elseif self.status_bar then
        self.status_bar.width = Screen:getWidth()
        self.status_bar.dimen.w = Screen:getWidth()
        self.status_bar:refresh()
        if self.dimen then
            self.dimen.w = Screen:getWidth()
            self.dimen.h = self.status_bar.height
        end
    end
    return false
end

function ModernMenu:onCloseWidget()
    if self.status_bar and self.status_bar._unscheduleClock then
        self.status_bar:_unscheduleClock()
    end
end

return ModernMenu
