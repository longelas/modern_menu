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

function ModernMenu:init()
    self:_installPackagePath()
    self:onDispatcherRegisterActions()
    self.use_stock_menu = G_reader_settings and G_reader_settings:isTrue("modern_menu_use_stock") or false

    self:_registerMainMenu()

    local function boot()
        self:installMenuHook()
        self:installStatusChrome()
        self:_registerMainMenu()
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
                        if current <= Settings.DEFAULT_TAB_ICON_SIZE then
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
    if menu._modern_menu_hooked then
        return
    end
    menu._modern_menu_hooked = true

    local plugin = self
    local original_on_show_menu = menu.onShowMenu
    menu._modern_menu_original_onShowMenu = original_on_show_menu

    menu.onShowMenu = function(menu_self, tab_index, do_not_show)
        -- Menu search and explicit stock mode keep the classic TouchMenu
        if plugin.use_stock_menu or do_not_show then
            return original_on_show_menu(menu_self, tab_index, do_not_show)
        end
        return plugin:showModernMenu(menu_self, tab_index)
    end

    logger.info("modern_menu: hooked ui.menu.onShowMenu")
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
    if menu_self.tab_item_table == nil and menu_self.setUpdateItemTable then
        menu_self:setUpdateItemTable()
    end
    -- Quick Menu inserts its panel tab from setUpdateItemTable. Sync again
    -- so the tab is present even if that table was built earlier.
    QuickMenuHost.sync(menu_self)
    -- Reader injects the Simple UI tab from onShowMenu, which this hook
    -- replaces. Make sure the tab exists before the opening index is chosen.
    QuickMenuHost.ensureSimpleUITab(menu_self)

    -- Match ReaderMenu: stop selection / close bottom config
    if menu_self.ui and menu_self.ui.keyselection and menu_self.ui.keyselection.stopHighlightIndicator then
        menu_self.ui.keyselection:stopHighlightIndicator(true)
    end
    if menu_self.ui then
        menu_self.ui:handleEvent(Event:new("CloseConfigMenu"))
    end

    -- Real widget container (stock TouchMenu shape). Plain tables crash
    -- UIManager:close when tab callbacks call onCloseReaderMenu / onCloseFileManagerMenu.
    local menu_container = CenterContainer:new{
        covers_header = true,
        ignore = "height",
        dimen = Screen:getSize(),
    }

    local shell = ModernMenuShell:new{
        width = Screen:getWidth(),
        last_index = QuickMenuHost.initialIndex(menu_self, tab_index),
        tab_item_table = menu_self.tab_item_table,
        ui = menu_self.ui or self.ui,
        show_parent = menu_container,
    }

    -- Match stock: close_callback closes menu_container via Reader/FM menu helpers
    shell.close_callback = function()
        if menu_self.onCloseReaderMenu then
            menu_self:onCloseReaderMenu()
        elseif menu_self.onCloseFileManagerMenu then
            menu_self:onCloseFileManagerMenu()
        else
            UIManager:close(menu_container)
            menu_self.menu_container = nil
        end
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
