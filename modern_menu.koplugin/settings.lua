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
local KEY_HIDE_STATUS_BAR = "modern_menu_hide_status_bar"
local KEY_BATTERY_PERCENT = "modern_menu_battery_percent"

-- Defaults tuned for a compact header. The minimums sit below those
-- defaults so a smaller label or icon can still be chosen.
Settings.DEFAULT_TAB_FONT_SIZE = 12
Settings.MIN_TAB_FONT_SIZE = 8
Settings.MAX_TAB_FONT_SIZE = 26

Settings.DEFAULT_TAB_ICON_SIZE = 20
Settings.DEFAULT_TAB_ICON_SIZE_ICONS_ONLY = 32
Settings.MIN_TAB_ICON_SIZE = 10
Settings.MAX_TAB_ICON_SIZE = 40

Settings.DEFAULT_OPTION_FONT_SIZE = 17
Settings.MIN_OPTION_FONT_SIZE = 8
Settings.MAX_OPTION_FONT_SIZE = 28

-- Vertical padding inside each option row (unscaled logical units).
-- Negative values tighten rows below the default minimum height.
Settings.DEFAULT_OPTION_PADDING = -4
Settings.MIN_OPTION_PADDING = -10
Settings.MAX_OPTION_PADDING = 20

-- How tall the drop-down menu is. "full" fills the screen.
Settings.MENU_HEIGHT_FULL = "full"
Settings.MENU_HEIGHT_CONTENT = "content"
Settings.MENU_HEIGHT_PERCENT = "percent"
Settings.DEFAULT_MENU_HEIGHT_PERCENT = 70
Settings.MIN_MENU_HEIGHT_PERCENT = 40
Settings.MAX_MENU_HEIGHT_PERCENT = 100

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
    local mode = read(KEY_MENU_HEIGHT_MODE, Settings.MENU_HEIGHT_CONTENT)
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

-- Kobold draws with KOReader's cfont, which ships as Noto Sans.
Settings.KOBOLD_FONT_NAME = "Noto Sans"

local resolve_menu_font_name

--- Noto Sans when KOReader has that face, otherwise nil (plain cfont).
function Settings.defaultMenuFont()
    if Settings._default_menu_font ~= nil then
        if Settings._default_menu_font == false then
            return nil
        end
        return Settings._default_menu_font
    end
    local name = Settings.KOBOLD_FONT_NAME
    local faces = Settings.fontChoices()
    local listed = false
    if type(faces) == "table" then
        for _, face_name in ipairs(faces) do
            if face_name == name then
                listed = true
                break
            end
        end
    end
    local file = select(1, resolve_menu_font_name(name))
    if file or listed then
        Settings._default_menu_font = name
        return name
    end
    -- An empty font list means crengine is not ready yet. Try again later.
    if type(faces) == "table" and #faces > 0 and not file then
        Settings._default_menu_font = false
    end
    return nil
end

--- Face name from KOReader's font menu.
-- Nil means the stock UI font. An unset preference uses Kobold's Noto Sans.
function Settings.getMenuFont()
    local name = read(KEY_MENU_FONT, nil)
    if name == nil then
        return Settings.defaultMenuFont()
    end
    if type(name) ~= "string" or name == "" then
        return nil
    end
    return name
end

function Settings.setMenuFont(name)
    Settings._font_file = nil
    if name == nil or type(name) ~= "string" or name == "" then
        -- Explicit stock UI font, distinct from the unset Kobold default.
        write(KEY_MENU_FONT, "")
        return
    end
    write(KEY_MENU_FONT, name)
end

function resolve_menu_font_name(name)
    if type(name) ~= "string" or name == "" then
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

local function resolve_menu_font()
    return resolve_menu_font_name(Settings.getMenuFont())
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
    return Font:getFace(fallback or "cfont", size)
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

function Settings.getHideStatusBar()
    return read(KEY_HIDE_STATUS_BAR, false) and true or false
end

function Settings.setHideStatusBar(enabled)
    write(KEY_HIDE_STATUS_BAR, enabled and true or false)
end

function Settings.getBatteryPercent()
    return read(KEY_BATTERY_PERCENT, false) and true or false
end

function Settings.setBatteryPercent(enabled)
    write(KEY_BATTERY_PERCENT, enabled and true or false)
end

function Settings.getPureBlack()
    return read(KEY_PURE_BLACK, false) and true or false
end

function Settings.setPureBlack(enabled)
    write(KEY_PURE_BLACK, enabled and true or false)
end

--- Secondary text. Kobold uses a dark gray (0x22), darker than COLOR_DARK_GRAY.
-- Pure black mode uses solid black.
function Settings.getMutedFg()
    if Settings.getPureBlack() then
        return Blitbuffer.COLOR_BLACK
    end
    local ok, color = pcall(function()
        return Blitbuffer.Color8(0x22)
    end)
    if ok and color then
        return color
    end
    return Blitbuffer.COLOR_DARK_GRAY
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
    return Blitbuffer.COLOR_LIGHT_GRAY
end

--- Tab / section divider rule under the tab bar.
function Settings.getRuleFg()
    if Settings.getPureBlack() then
        return Blitbuffer.COLOR_BLACK
    end
    return Blitbuffer.COLOR_LIGHT_GRAY
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

--- Row background. White, including the old zebra stripe, so rows match Kobold.
function Settings.getStripeBg()
    return Blitbuffer.COLOR_WHITE
end

-- Back-compat alias used by older call sites.
Settings.UNSELECTED_FG = Blitbuffer.COLOR_GRAY_3

--- Write the current defaults, including Kobold's Noto Sans when it is installed.
function Settings.resetToDefaults()
    Settings.setTabIconsOnly(false)
    Settings.setTabFontSize(Settings.DEFAULT_TAB_FONT_SIZE)
    Settings.setTabIconSize(Settings.DEFAULT_TAB_ICON_SIZE)
    Settings.setOptionFontSize(Settings.DEFAULT_OPTION_FONT_SIZE)
    Settings.setOptionPadding(Settings.DEFAULT_OPTION_PADDING)
    Settings.setPureBlack(false)
    Settings.setHideStatusBar(false)
    Settings.setBatteryPercent(false)
    Settings.setMenuHeightPercent(Settings.DEFAULT_MENU_HEIGHT_PERCENT)
    Settings.setMenuHeightMode(Settings.MENU_HEIGHT_CONTENT)
    Settings.setDefaultTabId(nil)
    local font = Settings.defaultMenuFont()
    if font then
        Settings.setMenuFont(font)
    else
        Settings.setMenuFont(nil)
    end
end

return Settings
