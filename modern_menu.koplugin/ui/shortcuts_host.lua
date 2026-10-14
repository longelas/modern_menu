--[[--
Host for xusoo/shortcutstoolbar.koplugin inside the reader menu.

That plugin inserts its home panel by patching TouchMenu. Modern Menu never
opens TouchMenu, so the reader shortcut row would not appear. When the plugin
is enabled, this builds the same bottom row (back button and shortcut icons)
and the shell pins it under the list.

Nothing here runs unless that plugin is loaded. Its own checkout is not modified.
@module modern_menu.ui.shortcuts_host
--]]

local logger = require("logger")
local Screen = require("device").screen

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

--- Reader shortcut row, or nil when the plugin is absent or the reader bar is off.
-- Book info and the corner clock stay out: this menu already has its own list
-- and status bar. The back button and shortcut icons are the bottom row the
-- plugin shows when the reader menu opens.
function ShortcutsHost.build(menu)
    if not (menu and menu.ui and menu.ui.document) then
        return nil
    end
    local plugin = ShortcutsHost.findPlugin(menu.ui)
    if not plugin then
        return nil
    end
    local ToolbarSettings, HomeContent = load_api(plugin)
    if not ToolbarSettings then
        return nil
    end
    local ok_cfg, cfg = pcall(ToolbarSettings.readConfig, "reader")
    if not ok_cfg or type(cfg) ~= "table" or not cfg.enabled then
        return nil
    end
    local has_icons = type(cfg.items) == "string" and cfg.items:find("%S")
    if not has_icons and cfg.show_back_button == false then
        return nil
    end

    menu.width = (menu.dimen and menu.dimen.w) or Screen:getWidth()
    -- Reuse the plugin's layout, but only its bottom row.
    local bar_cfg = {
        view = "reader",
        spacing = cfg.spacing,
        enabled = true,
        icon_size = cfg.icon_size,
        items = cfg.items or "",
        show_book_info = false,
        show_time_and_battery = false,
        show_back_button = cfg.show_back_button ~= false,
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
