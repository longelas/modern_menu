--[[--
Persisted Modern Menu preferences (G_reader_settings).
@module modern_menu.settings
--]]

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Screen = Device.screen

local Settings = {}

local KEY_TAB_FONT_SIZE = "modern_menu_tab_font_size"
local KEY_TAB_ICONS_ONLY = "modern_menu_tab_icons_only"
local KEY_TAB_ICON_SIZE = "modern_menu_tab_icon_size"
local KEY_OPTION_FONT_SIZE = "modern_menu_option_font_size"
local KEY_OPTION_PADDING = "modern_menu_option_padding"
local KEY_PURE_BLACK = "modern_menu_pure_black"

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

local ALL_KEYS = {
    KEY_TAB_FONT_SIZE,
    KEY_TAB_ICONS_ONLY,
    KEY_TAB_ICON_SIZE,
    KEY_OPTION_FONT_SIZE,
    KEY_OPTION_PADDING,
    KEY_PURE_BLACK,
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
