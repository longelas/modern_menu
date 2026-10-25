# Changelog

## 1.10.0 — 2026-10-25

The menu is faster on e-ink. Taps and long lists do less work, and the screen refreshes only the part that changed.

### Changes
- A tap updates the row that changed, and leaves the tabs, status bar, and shortcut row alone
- Long lists build the visible rows and a short buffer, instead of every row at once
- Fit-to-content and percentage heights refresh the menu sheet when its size stays the same, instead of the whole screen
- Quick Menu toggles, slider drags, and scrolling each paint once per gesture

## 1.9.0 — 2026-10-20

The status bar can be hidden, and the battery can show as a percentage.

### Changes
- **Hide status bar** removes the clock, contrast, Wi-Fi, and battery row from the menu. The close mark moves to the title row
- **Battery as percentage** shows the charge as a number instead of the battery icon, in the menu and in the file browser

## 1.8.0 — 2026-10-15

Modern Menu now complements [Kobold](https://github.com/unitreign/kobold): the same type and spacing, and a menu that stays available on Kobold’s screens.

### Changes
- The pull-down menu opens on the file browser and on Kobold’s Home, My Books, and More screens, including after you open Kobold from the reader
- A **Kobold** tab, when that plugin is installed, sits after any quick-action tabs and before Library, and opens Kobold Home
- The file-browser shortcut row is pinned at the bottom of the menu, the same way the reader shortcut row is
- Header aligned with the clock: title on the same inset, close with the status icons, back only inside a submenu
- Dialogs opened from the menu stay on top of it. Battery, Wi‑Fi, brightness, and Kobold navigation close the menu first
- Tab icons are centered on their labels and evenly spaced. The selected tab is bold, without an underline, and the labels sit clear of the rule below them
- Defaults match a compact Kobold-style sheet: option padding −4, tab label 12, tab icon 20, height fit to content, and Noto Sans when KOReader includes that face
- Tab label size can go down to 8 and tab icon size down to 10. **Reset to defaults** writes these values

## 1.7.0 — 2026-10-14

Shortcuts Toolbar custom actions run from this menu, and the file-browser status bar is optional.

### Changes
- Custom Shortcuts Toolbar buttons run from the reader row: system actions, menu-path actions, and a shortcut that opens a submenu
- Choosing **Menu action** records a tap in this menu, including items inside a submenu
- The file-browser shortcut row is present when KOReader starts in the file browser
- **Status bar in file browser** is in **Modern Menu** settings and is off until you turn it on. The switch is no longer in the menu header

## 1.6.0 — 2026-10-14

Shortcuts Toolbar in the reader menu, and a tap outside a short menu closes it.

### Changes
- Shortcuts Toolbar’s reader row (back button and shortcut icons) sits at the bottom of the menu when that plugin is enabled
- A tap on the page below the menu closes it when height is fit to content or a percentage. Full-screen height stays open until you close it
- Works with Simple UI, Quick Menu, Neo Quick Settings, and Shortcuts Toolbar. Does not work with Zen OS

## 1.5.0 — 2026-10-14

Custom Neo actions, a Simple UI tab, and a menu that can be shorter than the screen.

### Changes
- Custom Neo Quick Settings buttons run their real action. Exit, restart, dispatcher, and menu-path buttons no longer stop at closing the tab
- Simple UI’s quick-settings tab shows its action buttons, and taps, swipes, and holds on that panel do what Simple UI expects
- **Default tab** picks which tab opens first. Automatic keeps the Quick Menu or Neo default
- **Menu height** can be full screen, fit to content, or a fixed percentage of the screen (40–100). The sheet stays at the top; a tap below it closes the menu
- Fit-content and percentage sheets end on a rule, so the bottom of the menu is visible
- The percentage picker can confirm 70%, the default, without the Set button staying disabled

## 1.4.0 — 2026-10-13

Hosts Neo Quick Settings the same way as Quick Menu, and adds a menu font picker.

### Changes
- Neo Quick Settings is hosted as a tab when that plugin is installed, including its buttons, settings, and brightness and warmth sliders
- Slider drags repaint through the menu, so swiping a slider no longer crashes on Android
- Swipe-to-exit and swipe-to-restart confirmations work from the hosted panel
- Quick Menu’s exit tab leaves the book for the file browser; in the file browser a tap closes the menu and a hold asks before quitting KOReader
- **Menu font** setting lists the same faces KOReader uses for its menus
- Neo Quick Settings grid lines up with the menu’s side inset

## 1.3.0 — 2026-10-12

Hosts Quick Menu as the first tab when that plugin is installed, and refreshes button state as soon as a toggle runs.

### Changes
- Quick Menu panel and footer render inside Modern Menu
- Opens on the Quick Menu tab when “Always start on quick menu tab” is on
- Hold the Quick Menu tab to open its settings
- Button active state, icons, and labels update on toggle

## 1.2.0 — 2026-10-12

Pure black mode and larger default fonts for e-ink readability.

### Changes
- **Pure black (no greys)** setting — solid black ink for tabs, options, separators, toggles, and scrollbars
- Larger default tab label, tab icon, and option font sizes
- Existing size and padding customization unchanged

## 1.1.0 — 2026-10-12

Appearance settings and menu chrome polish.

### Changes
- Configurable tab label size, tab icon size, and icons-only mode
- Configurable option font size and row padding (including tighter and negative padding)
- Reset to defaults in plugin settings
- Clearer header spacing and divider; denser, inset tab bar
- Settings persist across restarts; tab chrome refreshes when settings change

## 1.0.0 — 2026-10-11

Kobo-inspired replacement for KOReader’s stock top menu.

### Changes
- Paginated card UI for the live KOReader menu tree, including submenus, checks, holds, and plugin items
- Touch-first rows and monochrome styling suited to e-ink
- Optional status chrome in the menu
