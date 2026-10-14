--[[--
Persisted Modern Menu preferences (G_reader_settings).
@module modern_menu.settings
--]]

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Screen = Device.screen

local Settings = {}

local KEY_TAB_FONT_SIZE = "modern_menu_tab_font_size"
local KEY_TAB_ICONS_ONLY = "modern_menu_tab_icons_only"
local KEY_TAB_ICON_SIZE = "modern_menu_tab_icon_size"
local KEY_OPTION_FONT_SIZE = "modern_menu_option_font_size"
local KEY_OPTION_PADDING = "modern_menu_option_padding"
local KEY_PURE_BLACK = "modern_menu_pure_black"
local KEY_MENU_FONT = "modern_menu_font"
local KEY_DEFAULT_TAB = "modern_menu_default_tab"
local KEY_MENU_HEIGHT_MODE = "modern_menu_height_mode"
local KEY_MENU_HEIGHT_PERCENT = "modern_menu_height_percent"

-- Defaults tuned for phone / e-ink readability.
Settings.DEFAULT_TAB_FONT_SIZE = 17
Settings.MIN_TAB_FONT_SIZE = 12
Settings.MAX_TAB_FONT_SIZE = 26

Settings.DEFAULT_TAB_ICON_SIZE = 26
Settings.DEFAULT_TAB_ICON_SIZE_ICONS_ONLY = 32
Settings.MIN_TAB_ICON_SIZE = 20
Settings.MAX_TAB_ICON_SIZE = 40

Settings.DEFAULT_OPTION_FONT_SIZE = 22
Settings.MIN_OPTION_FONT_SIZE = 8
Settings.MAX_OPTION_FONT_SIZE = 28

-- Vertical padding inside each option row (unscaled logical units).
-- Negative values tighten rows below the default minimum height.
Settings.DEFAULT_OPTION_PADDING = 6
Settings.MIN_OPTION_PADDING = -10
Settings.MAX_OPTION_PADDING = 20

-- How tall the drop-down menu is. "full" fills the screen.
Settings.MENU_HEIGHT_FULL = "full"
Settings.MENU_HEIGHT_CONTENT = "content"
Settings.MENU_HEIGHT_PERCENT = "percent"
Settings.DEFAULT_MENU_HEIGHT_PERCENT = 70
Settings.MIN_MENU_HEIGHT_PERCENT = 40
Settings.MAX_MENU_HEIGHT_PERCENT = 100

local ALL_KEYS = {
    KEY_TAB_FONT_SIZE,
    KEY_TAB_ICONS_ONLY,
    KEY_TAB_ICON_SIZE,
    KEY_OPTION_FONT_SIZE,
    KEY_OPTION_PADDING,
    KEY_PURE_BLACK,
    KEY_MENU_FONT,
    KEY_DEFAULT_TAB,
    KEY_MENU_HEIGHT_MODE,
    KEY_MENU_HEIGHT_PERCENT,
}

local function read(key, default)
    if not G_reader_settings then
        return default
    end
    local value = G_reader_settings:readSetting(key)
    if value == nil then
        return default
    end
    return value
end

local function write(key, value)
    if not G_reader_settings then
        return
    end
    -- Flush immediately so values survive AppImage/SDL quits that skip a clean exit.
    G_reader_settings:saveSetting(key, value)
    G_reader_settings:flush()
end

local function del(key)
    if not G_reader_settings then
        return
    end
    G_reader_settings:delSetting(key)
end

local function clamp_int(value, min_v, max_v, default)
    local n = tonumber(value)
    if not n then
        return default
    end
    return math.max(min_v, math.min(max_v, math.floor(n)))
end

function Settings.getTabFontSize()
    return clamp_int(
        read(KEY_TAB_FONT_SIZE, Settings.DEFAULT_TAB_FONT_SIZE),
        Settings.MIN_TAB_FONT_SIZE,
        Settings.MAX_TAB_FONT_SIZE,
        Settings.DEFAULT_TAB_FONT_SIZE
    )
end

function Settings.setTabFontSize(size)
    write(KEY_TAB_FONT_SIZE, clamp_int(
        size,
        Settings.MIN_TAB_FONT_SIZE,
        Settings.MAX_TAB_FONT_SIZE,
        Settings.DEFAULT_TAB_FONT_SIZE
    ))
end

function Settings.getTabIconsOnly()
    return read(KEY_TAB_ICONS_ONLY, false) and true or false
end

function Settings.setTabIconsOnly(enabled)
    write(KEY_TAB_ICONS_ONLY, enabled and true or false)
end

function Settings.getTabIconSize()
    local default = Settings.getTabIconsOnly()
        and Settings.DEFAULT_TAB_ICON_SIZE_ICONS_ONLY
        or Settings.DEFAULT_TAB_ICON_SIZE
    return clamp_int(
        read(KEY_TAB_ICON_SIZE, default),
        Settings.MIN_TAB_ICON_SIZE,
        Settings.MAX_TAB_ICON_SIZE,
        default
    )
end

function Settings.setTabIconSize(size)
    write(KEY_TAB_ICON_SIZE, clamp_int(
        size,
        Settings.MIN_TAB_ICON_SIZE,
        Settings.MAX_TAB_ICON_SIZE,
        Settings.DEFAULT_TAB_ICON_SIZE
    ))
end

--- Scaled icon pixel size for IconWidget.
function Settings.getTabIconPx()
    return Screen:scaleBySize(Settings.getTabIconSize())
end

function Settings.getOptionFontSize()
    return clamp_int(
        read(KEY_OPTION_FONT_SIZE, Settings.DEFAULT_OPTION_FONT_SIZE),
        Settings.MIN_OPTION_FONT_SIZE,
        Settings.MAX_OPTION_FONT_SIZE,
        Settings.DEFAULT_OPTION_FONT_SIZE
    )
end

function Settings.setOptionFontSize(size)
    write(KEY_OPTION_FONT_SIZE, clamp_int(
        size,
        Settings.MIN_OPTION_FONT_SIZE,
        Settings.MAX_OPTION_FONT_SIZE,
        Settings.DEFAULT_OPTION_FONT_SIZE
    ))
end

function Settings.getOptionPadding()
    return clamp_int(
        read(KEY_OPTION_PADDING, Settings.DEFAULT_OPTION_PADDING),
        Settings.MIN_OPTION_PADDING,
        Settings.MAX_OPTION_PADDING,
        Settings.DEFAULT_OPTION_PADDING
    )
end

function Settings.setOptionPadding(padding)
    write(KEY_OPTION_PADDING, clamp_int(
        padding,
        Settings.MIN_OPTION_PADDING,
        Settings.MAX_OPTION_PADDING,
        Settings.DEFAULT_OPTION_PADDING
    ))
end

--- Scaled vertical padding for option rows (preserves sign for negative values).
function Settings.getOptionPaddingPx()
    local pad = Settings.getOptionPadding()
    if pad == 0 then
        return 0
    end
    local scaled = Screen:scaleBySize(math.abs(pad))
    return pad < 0 and -scaled or scaled
end

--- Stable id for a menu tab. Nil when the tab has neither id nor icon.
function Settings.tabKey(tab)
    if type(tab) ~= "table" then
        return nil
    end
    if type(tab.id) == "string" and tab.id ~= "" then
        return tab.id
    end
    if type(tab.icon) == "string" and tab.icon ~= "" then
        return "icon:" .. tab.icon
    end
    return nil
end

--- Tab to show when the menu opens. Nil means the existing automatic choice
-- (Neo / Quick Menu defaults, then the last KOReader tab).
function Settings.getDefaultTabId()
    local id = read(KEY_DEFAULT_TAB, nil)
    if type(id) ~= "string" or id == "" then
        return nil
    end
    return id
end

--- "full", "content" (as tall as the rows, capped at the screen), or "percent".
function Settings.getMenuHeightMode()
    local mode = read(KEY_MENU_HEIGHT_MODE, Settings.MENU_HEIGHT_FULL)
    if mode == Settings.MENU_HEIGHT_CONTENT or mode == Settings.MENU_HEIGHT_PERCENT then
        return mode
    end
    return Settings.MENU_HEIGHT_FULL
end

function Settings.setMenuHeightMode(mode)
    if mode ~= Settings.MENU_HEIGHT_CONTENT and mode ~= Settings.MENU_HEIGHT_PERCENT then
        mode = Settings.MENU_HEIGHT_FULL
    end
    write(KEY_MENU_HEIGHT_MODE, mode)
end

function Settings.getMenuHeightPercent()
    return clamp_int(
        read(KEY_MENU_HEIGHT_PERCENT, Settings.DEFAULT_MENU_HEIGHT_PERCENT),
        Settings.MIN_MENU_HEIGHT_PERCENT,
        Settings.MAX_MENU_HEIGHT_PERCENT,
        Settings.DEFAULT_MENU_HEIGHT_PERCENT
    )
end

function Settings.setMenuHeightPercent(percent)
    write(KEY_MENU_HEIGHT_PERCENT, clamp_int(
        percent,
        Settings.MIN_MENU_HEIGHT_PERCENT,
        Settings.MAX_MENU_HEIGHT_PERCENT,
        Settings.DEFAULT_MENU_HEIGHT_PERCENT
    ))
end

function Settings.setDefaultTabId(id)
    if type(id) ~= "string" or id == "" then
        del(KEY_DEFAULT_TAB)
        if G_reader_settings then
            G_reader_settings:flush()
        end
        return
    end
    write(KEY_DEFAULT_TAB, id)
end

--- Face name from KOReader's font menu. Nil means the stock UI font.
function Settings.getMenuFont()
    local name = read(KEY_MENU_FONT, nil)
    if type(name) ~= "string" or name == "" then
        return nil
    end
    return name
end

function Settings.setMenuFont(name)
    Settings._font_file = nil
    if type(name) ~= "string" or name == "" then
        del(KEY_MENU_FONT)
        if G_reader_settings then
            G_reader_settings:flush()
        end
        return
    end
    write(KEY_MENU_FONT, name)
end

local function resolve_menu_font()
    local name = Settings.getMenuFont()
    if not name then
        return nil, nil
    end
    if Settings._font_file and Settings._font_file.name == name then
        return Settings._font_file.file, Settings._font_file.index
    end
    local ok, cre = pcall(function()
        return require("document/credocument"):engineInit()
    end)
    if not ok or not cre or not cre.getFontFaceFilenameAndFaceIndex then
        return nil, nil
    end
    local file, index = cre.getFontFaceFilenameAndFaceIndex(name)
    if not file then
        file, index = cre.getFontFaceFilenameAndFaceIndex(name, nil, true)
    end
    Settings._font_file = { name = name, file = file, index = index }
    return file, index
end

--- A face at `size`, using the chosen menu font when one is set.
function Settings.face(size, fallback)
    local file, index = resolve_menu_font()
    if file then
        local face = Font:getFace(file, size, index)
        if face then
            return face
        end
    end
    return Font:getFace(fallback or "smallinfofont", size)
end

--- KOReader font-menu entries: face names and display labels.
function Settings.fontChoices()
    if Settings._font_choices then
        return Settings._font_choices.faces, Settings._font_choices.labels
    end
    local ok_list, FontList = pcall(require, "fontlist")
    if not ok_list or not FontList or not FontList.getFontArgFunc then
        return {}, {}
    end
    local ok, faces, labels = pcall(function()
        return FontList:getFontArgFunc()
    end)
    if not ok or type(faces) ~= "table" then
        return {}, {}
    end
    labels = labels or faces
    Settings._font_choices = { faces = faces, labels = labels }
    return faces, labels
end

function Settings.getPureBlack()
    return read(KEY_PURE_BLACK, false) and true or false
end

function Settings.setPureBlack(enabled)
    write(KEY_PURE_BLACK, enabled and true or false)
end

--- Secondary / unselected text. Pure black mode uses solid black.
function Settings.getMutedFg()
    if Settings.getPureBlack() then
        return Blitbuffer.COLOR_BLACK
    end
    return Blitbuffer.COLOR_GRAY_3
end

--- Disabled option text.
function Settings.getDisabledFg()
    if Settings.getPureBlack() then
        return Blitbuffer.COLOR_BLACK
    end
    return Blitbuffer.COLOR_DARK_GRAY
end

--- Hairline separators between options.
function Settings.getSeparatorFg()
    if Settings.getPureBlack() then
        return Blitbuffer.COLOR_BLACK
    end
    return Blitbuffer.COLOR_GRAY
end

--- Tab / section divider rule under the tab bar.
function Settings.getRuleFg()
    if Settings.getPureBlack() then
        return Blitbuffer.COLOR_BLACK
    end
    return Blitbuffer.COLOR_GRAY_5
end

--- Scrollbar ink.
function Settings.getScrollbarFg()
    if Settings.getPureBlack() then
        return Blitbuffer.COLOR_BLACK
    end
    return Blitbuffer.COLOR_DARK_GRAY
end

--- Toggle switch chrome.
function Settings.getToggleFg()
    if Settings.getPureBlack() then
        return Blitbuffer.COLOR_BLACK
    end
    return Blitbuffer.COLOR_DARK_GRAY
end

--- Category zebra stripe (disabled in pure black for max contrast).
function Settings.getStripeBg()
    if Settings.getPureBlack() then
        return Blitbuffer.COLOR_WHITE
    end
    return Blitbuffer.COLOR_GRAY_E
end

-- Back-compat alias used by older call sites.
Settings.UNSELECTED_FG = Blitbuffer.COLOR_GRAY_3

--- Remove all Modern Menu preference keys so getters return defaults.
function Settings.resetToDefaults()
    for _, key in ipairs(ALL_KEYS) do
        del(key)
    end
    if G_reader_settings then
        G_reader_settings:flush()
    end
end

return Settings
