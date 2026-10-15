--[[--
Host for xusoo/shortcutstoolbar.koplugin inside the reader menu.

That plugin inserts its home panel by patching TouchMenu. Modern Menu never
opens TouchMenu, so the reader shortcut row would not appear. When the plugin
is enabled, this builds the same bottom row (back button and shortcut icons)
and the shell pins it under the list.

Nothing here runs unless that plugin is loaded. Its own checkout is not modified.
@module modern_menu.ui.shortcuts_host
--]]

local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local InfoMessage = require("ui/widget/infomessage")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local logger = require("logger")
local Screen = require("device").screen
local _ = require("gettext")

local ShortcutsHost = {}

-- ReaderUI:registerModule rewrites instance.name to "reader" .. name, and
-- FileManager does the same with a "filemanager" prefix. The field on the
-- UI stays ui.shortcutstoolbar.
local function is_shortcuts(value)
    if type(value) ~= "table" then
        return false
    end
    local name = value.name
    return name == "shortcutstoolbar"
        or name == "readershortcutstoolbar"
        or name == "filemanagershortcutstoolbar"
end

--- Locate the loaded Shortcuts Toolbar instance, if the plugin is enabled.
function ShortcutsHost.findPlugin(ui)
    if is_shortcuts(ui and ui.shortcutstoolbar) then
        return ui.shortcutstoolbar
    end
    if ui then
        for _, child in ipairs(ui) do
            if is_shortcuts(child) then
                return child
            end
        end
    end
    local registered = ui and ui.menu and ui.menu.registered_widgets
    if registered then
        for _, widget in ipairs(registered) do
            if is_shortcuts(widget) then
                return widget
            end
        end
    end
    local ok_loader, PluginLoader = pcall(require, "pluginloader")
    if ok_loader and PluginLoader.getPluginInstance then
        local instance = PluginLoader:getPluginInstance("shortcutstoolbar")
        if is_shortcuts(instance) then
            return instance
        end
    end
    return nil
end

local function ensure_plugin_path(plugin)
    local dir = plugin and plugin.path
    if type(dir) ~= "string" or dir == "" then
        return
    end
    if dir:sub(-1) ~= "/" then
        dir = dir .. "/"
    end
    local needle = dir .. "?.lua"
    if not package.path:find(needle, 1, true) then
        package.path = needle .. ";" .. package.path
    end
end

local function load_api(plugin)
    ensure_plugin_path(plugin)
    local ok_settings, ToolbarSettings = pcall(require, "toolbar_settings")
    local ok_home, HomeContent = pcall(require, "home_content")
    if not (ok_settings and ok_home) then
        return nil
    end
    if type(ToolbarSettings.readConfig) ~= "function"
            or type(HomeContent.createHomeContent) ~= "function" then
        return nil
    end
    return ToolbarSettings, HomeContent
end

local function item_text(item)
    local text = item.text
    if type(text) == "function" then
        text = text()
    end
    if not text and item.text_func then
        text = item.text_func()
    end
    return type(text) == "string" and text or ""
end

local function find_item(tbl, id, index, text)
    tbl = tbl or {}
    if id then
        for _, item in ipairs(tbl) do
            if item.menu_item_id and item.menu_item_id == id then
                return item
            end
        end
    end
    if text and text ~= "" then
        local wanted = text:lower()
        for _, item in ipairs(tbl) do
            if item_text(item):lower() == wanted then
                return item
            end
        end
    end
    if index and tbl[index] then
        return tbl[index]
    end
end

local function replay_notice(text)
    UIManager:show(InfoMessage:new{
        text = text,
        timeout = 3,
    })
    return false
end

--- Run a Shortcuts Toolbar menu-path shortcut on this shell.
-- The plugin replays those paths through TouchMenu. This menu is not a
-- TouchMenu, so the recorded tab and submenu are applied here, then the
-- menu is dropped before the action so sendEvent reaches the book.
local function replay_on_shell(menu, path_record)
    if not path_record then
        return false
    end
    if path_record.view == "reader" then
        local ok, ReaderUI = pcall(require, "apps/reader/readerui")
        if not (ok and ReaderUI.instance and not ReaderUI.instance.tearing_down) then
            return replay_notice(_("This shortcut only works while reading a book."))
        end
    elseif path_record.view == "fb" then
        local on_file_manager = menu and menu.name == "modern_menu_shell"
            and menu.ui and not menu.ui.document
        if not on_file_manager then
            local ok, FileManager = pcall(require, "apps/filemanager/filemanager")
            if not (ok and FileManager.instance and not FileManager.instance.tearing_down
                    and FileManager.instance.menu) then
                return replay_notice(_("This shortcut only works in the file browser."))
            end
            FileManager.instance.menu:onShowMenu(path_record.tab_index)
            local container = FileManager.instance.menu.menu_container
            menu = container and container[1]
            if not (menu and menu.name == "modern_menu_shell") then
                return replay_notice(_("Could not open menu to run shortcut."))
            end
        end
    elseif not (menu and menu.name == "modern_menu_shell") then
        return false
    end

    local tab = menu.tab_item_table and menu.tab_item_table[path_record.tab_index]
    if not tab then
        return replay_notice(_("Could not navigate to shortcut — menu layout may have changed."))
    end
    menu.item_table_stack = {}
    menu.title_stack = {}
    menu.item_table = tab
    menu.last_index = path_record.tab_index
    menu.cur_tab = path_record.tab_index

    for _, step in ipairs(path_record.nav_path or {}) do
        local item = find_item(menu.item_table, step.id, step.index, step.text)
        local sub = item and (
            (item.sub_item_table_func and item.sub_item_table_func())
            or item.sub_item_table
        )
        if not item or type(sub) ~= "table" or #sub == 0 then
            return replay_notice(_("Could not navigate to shortcut — menu layout may have changed."))
        end
        table.insert(menu.item_table_stack, menu.item_table)
        local title = item_text(item)
        if title ~= "" then
            -- gsub also returns a match count. Parentheses keep that count
            -- from being read as the insert position.
            title = (title:gsub("%s*:%s*.*$", ""))
            table.insert(menu.title_stack, title)
        end
        menu.item_table = sub
    end

    if path_record.is_menu then
        -- Refresh rebuilds the shortcut row. Doing that inside the icon tap
        -- frees the button before its handler returns, so paint on the next tick.
        UIManager:nextTick(function()
            if menu._closing then
                return
            end
            if menu.tab_bar and menu.tab_bar.setSelected then
                menu.tab_bar:setSelected(menu.last_index, true)
            end
            menu:refresh()
        end)
        return true
    end

    local leaf_ref = path_record.item or {}
    local leaf = find_item(menu.item_table, leaf_ref.id, leaf_ref.index, leaf_ref.text)
    if not leaf then
        return replay_notice(_("Could not find shortcut item — menu layout may have changed."))
    end
    local callback = (leaf.callback_func and leaf.callback_func()) or leaf.callback
    menu:closeMenu()
    if callback then
        callback(menu)
    end
    return true
end

local function menu_is_visible(menu)
    local target = menu and menu.show_parent
    local stack = UIManager._window_stack
    if not target or not stack then
        return false
    end
    for _, win in ipairs(stack) do
        if win.widget == target then
            return true
        end
    end
    return false
end

local function copy_nav(nav_path)
    local copy = {}
    for i, step in ipairs(nav_path or {}) do
        copy[i] = { id = step.id, index = step.index, text = step.text }
    end
    return copy
end

local function pick_menu_label(menu, pick)
    if pick.nav_path and #pick.nav_path > 0 then
        return pick.nav_path[#pick.nav_path].text
    end
    local index = pick.tab_index or menu.last_index or 1
    local tab = menu.tab_item_table and menu.tab_item_table[index]
    if menu._tabTitle then
        return menu:_tabTitle(tab, index, false)
    end
    return _("Menu")
end

--- Stop recording a menu action and tell the shortcut editor what happened.
function ShortcutsHost.finishPick(menu, kind, path_record)
    local pick = menu and menu._shortcut_pick
    if not pick then
        return
    end
    menu._shortcut_pick = nil
    if kind == "done" and pick.on_done then
        pick.on_done(path_record)
    elseif pick.on_cancel then
        pick.on_cancel()
    end
end

--- A menu row was tapped while a shortcut is being recorded.
-- Submenus stay browsable. A leaf is stored and not run.
function ShortcutsHost.onPickSelect(menu, item)
    local pick = menu and menu._shortcut_pick
    if not pick or pick._entering or not item then
        return false
    end
    local sub = (item.sub_item_table_func and item.sub_item_table_func())
        or item.sub_item_table
    local item_index
    for i, it in ipairs(menu.item_table or {}) do
        if it == item then
            item_index = i
            break
        end
    end
    if type(sub) == "table" and #sub > 0 then
        table.insert(pick.nav_path, {
            id = item.menu_item_id,
            index = item_index,
            text = item_text(item),
        })
        pick._entering = true
        menu:onMenuSelect(item)
        pick._entering = false
        return true
    end
    local label = item_text(item)
    if label == "" then
        label = pick.slot_key or _("Menu")
    end
    ShortcutsHost.finishPick(menu, "done", {
        tab_index = pick.tab_index or menu.last_index or 1,
        display_label = label,
        nav_path = copy_nav(pick.nav_path),
        view = pick.view,
        item = {
            id = item.menu_item_id,
            index = item_index,
            text = label,
        },
    })
    return true
end

--- "Use this menu" and "Cancel" rows shown under the list while picking.
function ShortcutsHost.pickBars(menu)
    local pick = menu and menu._shortcut_pick
    if not pick then
        return nil
    end
    local width = menu.list_content_w or (menu.dimen and menu.dimen.w) or Screen:getWidth()
    local select_bar = Button:new{
        text = _("Tap here to use this menu as the action"),
        width = width,
        text_font_bold = false,
        bordersize = Size.border.thick,
        show_parent = menu.show_parent,
        callback = function()
            local session = menu._shortcut_pick
            if not session then
                return
            end
            ShortcutsHost.finishPick(menu, "done", {
                tab_index = session.tab_index or menu.last_index or 1,
                display_label = pick_menu_label(menu, session),
                nav_path = copy_nav(session.nav_path),
                view = session.view,
                is_menu = true,
            })
        end,
    }
    if select_bar.frame then
        select_bar.frame.color = Blitbuffer.COLOR_LIGHT_GRAY
        select_bar.frame.radius = Size.radius.button
    end
    local cancel_bar = Button:new{
        text = _("Tap here to cancel"),
        width = width,
        text_font_bold = true,
        bordersize = Size.border.thin,
        background = Blitbuffer.COLOR_LIGHT_GRAY,
        show_parent = menu.show_parent,
        callback = function()
            ShortcutsHost.finishPick(menu, "cancel")
        end,
    }
    local group = VerticalGroup:new{ align = "left" }
    table.insert(group, VerticalSpan:new{ width = Size.padding.default })
    table.insert(group, select_bar)
    table.insert(group, VerticalSpan:new{ width = Size.padding.default })
    table.insert(group, cancel_bar)
    table.insert(group, VerticalSpan:new{ width = Size.padding.default })
    return group
end

--- Browse this menu and record a path instead of running items.
-- The shortcut plugin's picker drives stock TouchMenu, which has a tab bar
-- named `bar`. This shell does not, so picking stays here.
function ShortcutsHost.beginPick(menu, slot_key, on_done, on_cancel, view)
    menu._shortcut_pick = {
        slot_key = slot_key,
        on_done = on_done,
        on_cancel = on_cancel,
        view = view or "reader",
        tab_index = 1,
        nav_path = {},
    }
    if not menu_is_visible(menu) and menu.show_parent then
        UIManager:show(menu.show_parent)
    end
    if menu.switchMenuTab then
        menu:switchMenuTab(1)
    elseif menu.refresh then
        menu:refresh()
    end
    if not menu._shortcut_pick then
        return
    end
    UIManager:show(InfoMessage:new{
        text = _("Tap any menu item to assign it as a shortcut."),
        timeout = 3,
    })
end

--- Menu-path custom shortcuts call the picker's replay. Point that at this shell.
function ShortcutsHost.installReplayHook(ui)
    if ShortcutsHost._replay_hooked then
        return
    end
    local plugin = ShortcutsHost.findPlugin(ui)
    if plugin then
        ensure_plugin_path(plugin)
    end
    local ok, Picker = pcall(require, "custom_shortcut_picker")
    if not ok or type(Picker.replayShortcut) ~= "function" then
        return
    end
    ShortcutsHost._replay_hooked = true
    local orig_start = Picker.startPicking
    if type(orig_start) == "function" then
        function Picker.startPicking(menu, slot_key, on_done, on_cancel, view)
            if menu and menu.name == "modern_menu_shell" then
                ShortcutsHost.beginPick(menu, slot_key, on_done, on_cancel, view)
                return
            end
            return orig_start(menu, slot_key, on_done, on_cancel, view)
        end
    end
    local orig = Picker.replayShortcut
    local function opens_modern_file_menu(menu, path_record)
        if not path_record or path_record.view == "reader" then
            return false
        end
        local ok_fm, FileManager = pcall(require, "apps/filemanager/filemanager")
        local fm = ok_fm and FileManager.instance
        local plugin = fm and fm.modern_menu
        if not (plugin and not plugin.use_stock_menu and not fm.tearing_down) then
            return false
        end
        if path_record.view == "fb" then
            return true
        end
        -- Older shortcuts have no view and a stub menu with no tab table.
        return not path_record.view
            and not (menu and menu.tab_item_table and #menu.tab_item_table > 0)
    end
    function Picker.replayShortcut(menu, path_record)
        local on_shell = menu and menu.name == "modern_menu_shell"
        if on_shell or opens_modern_file_menu(menu, path_record) then
            local ran, result = pcall(replay_on_shell, menu, path_record)
            if not ran then
                logger.warn("modern_menu: shortcut replay failed: " .. tostring(result))
                return false
            end
            return result
        end
        return orig(menu, path_record)
    end
end

--- Put the file-browser shortcut row above the file list.
-- The plugin schedules this during its own init, before FileManager.instance
-- exists, and does not retry. Call again once the file chooser is live, and
-- after a layout rebuild replaces that chooser.
function ShortcutsHost.ensureFileBrowserBar(ui)
    local function inject_now()
        local plugin = ShortcutsHost.findPlugin(ui)
        if not plugin then
            local ok_fm, FileManager = pcall(require, "apps/filemanager/filemanager")
            plugin = ShortcutsHost.findPlugin(ok_fm and FileManager.instance)
        end
        if not plugin then
            return
        end
        ensure_plugin_path(plugin)
        local ok_settings, ToolbarSettings = pcall(require, "toolbar_settings")
        local ok_bar, PersistentBar = pcall(require, "fb_persistent_bar")
        if not (ok_settings and ok_bar and ToolbarSettings.readConfig and PersistentBar.inject) then
            return
        end
        local ok_cfg, cfg = pcall(ToolbarSettings.readConfig, "fb")
        if not ok_cfg or type(cfg) ~= "table" or not cfg.enabled or cfg.placement ~= "persistent" then
            return
        end
        PersistentBar.inject(cfg)
    end

    local ok_fm, FileManager = pcall(require, "apps/filemanager/filemanager")
    local fm = ok_fm and FileManager.instance
    if fm and fm.file_chooser and fm.file_chooser.content_group then
        inject_now()
        return
    end
    UIManager:nextTick(inject_now)
end

--- Shortcut row for the bottom of this menu, or nil when that bar is off.
-- Reader: back button and shortcut icons, without the plugin's book info
-- or clock (this menu already has a list and a status bar).
-- File browser: the same plugin's file-browser icons, centered, so they
-- stay reachable when Simple UI or Kobold covers the file list.
function ShortcutsHost.build(menu)
    if not (menu and menu.ui) then
        return nil
    end
    local plugin = ShortcutsHost.findPlugin(menu.ui)
    if not plugin then
        return nil
    end
    ShortcutsHost.installReplayHook(menu.ui)
    local ToolbarSettings, HomeContent = load_api(plugin)
    if not ToolbarSettings then
        return nil
    end
    local in_reader = menu.ui.document ~= nil
    local view = in_reader and "reader" or "fb"
    local ok_cfg, cfg = pcall(ToolbarSettings.readConfig, view)
    if not ok_cfg or type(cfg) ~= "table" or not cfg.enabled then
        return nil
    end
    local has_icons = type(cfg.items) == "string" and cfg.items:find("%S")
    if in_reader then
        if not has_icons and cfg.show_back_button == false then
            return nil
        end
    elseif not has_icons then
        return nil
    end

    menu.width = (menu.dimen and menu.dimen.w) or Screen:getWidth()
    -- Reuse the plugin's layout, but only its icon row.
    local bar_cfg = {
        view = view,
        spacing = cfg.spacing,
        enabled = true,
        icon_size = cfg.icon_size,
        items = cfg.items or "",
        align = cfg.align or (in_reader and "right" or "center"),
        show_book_info = false,
        show_time_and_battery = false,
        show_back_button = in_reader and cfg.show_back_button ~= false,
    }
    local ok_bar, bar = pcall(HomeContent.createHomeContent, menu, bar_cfg, function()
        if menu.refresh then
            menu:refresh()
        end
    end)
    if not ok_bar or not bar then
        logger.warn("modern_menu: shortcuts toolbar row failed: " .. tostring(bar))
        return nil
    end
    return bar
end

return ShortcutsHost
