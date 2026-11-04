# Ilha

Floating island bar for [Omarchy](https://omarchy.org). At rest it is only the time. Under the pointer it becomes one capsule with the monitor's workspaces, the clock, and the icons of Ilha's screens; a click on the clock or a gap opens level 2, which adds Omarchy's bar widgets in a row underneath. Each screen opens inside the same pill.

Documentação em português: [LEIA-ME.md](LEIA-ME.md).

Ilha replaces the bar (`kinds: ["bar"]`, id `esegnorelli.ilha`, version 2.4.0). It is not a widget inside the default bar. Colors follow the Omarchy theme, and the text follows the Omarchy language.

> After an update, if the pill says "Restart the shell to finish updating Ilha", tap it or run `omarchy restart shell`.

## Install

```bash
omarchy plugin add https://github.com/Esegnorelli/omarchy-ilha.git --enable
```

`omarchy plugin add` clones the repo and validates `manifest.json`. `--enable` then switches the bar to Ilha. Omarchy asks you to confirm first, because a plugin runs as unsandboxed code inside the long-lived shell (`--yes` skips the questions). There is no extra package, no sudo, and no setup step. Ilha runs no install script and writes nothing when it starts.

Outside its own folder, Ilha writes only these:

- Its settings, in Omarchy's own `~/.config/omarchy/shell.json` under `bar.ilha`, through the host's plugin API (`mutateShellConfig`). Only when you flip a switch or run `ilha setting` (see Settings).
- Its own state, in `~/.local/state/esegnorelli.ilha/` (`$XDG_STATE_HOME` when set): `state.json` (when you last pressed Clear in the notifications, and the night light temperature) and `game-mode.json` while Game Mode is on.
- The answer to Omarchy's background switcher, in the two reply files that script creates and waits on (see Theme and wallpaper keys).
- What an Omarchy widget in the hover capsule saves for itself. Ilha passes its calls on to the host (`updateEntryInline`, `mutateShellConfig`), as the default bar does.

If the bar was hidden, show it again with `omarchy toggle bar`.

## Update

```bash
omarchy plugin update esegnorelli.ilha
```

With no id, `omarchy plugin update` updates every git-managed plugin. It shows the diff and refuses to fast-forward over local edits. Then Omarchy rescans its plugins.

Omarchy does not clear its QML cache. Ilha compares the version in `manifest.json` with the version of the code the shell has loaded. When they differ, the pill shows "Restart the shell to finish updating Ilha" for 8 seconds, once per session, about 2 seconds after Ilha loads. It waits, up to about a minute, while a screen, a hover level, or another OSD is up. A tap runs `omarchy-restart-shell`. `omarchy restart shell` does the same. With the bar hidden, the notice shows in Omarchy's OSD instead.

From 1.x:

- The 2.0 code lives in `ui/`, a folder 1.x never had, and the bar now starts from `ui/Ilha.qml`. The 1.x QML files at the root are gone. Because every file is new, the shell loads 2.0 right away, with no restart.
- `focusedOnly` and `livePeek` in `bar.ilha` keep their values. `level2Dwell` is gone. Ilha ignores the old key and removes it the next time it saves a setting.
- The Tempo, Captura, Estilo, Ferramentas, and Plugins panels are gone, and with Estilo the corner, transparency, and font controls.

## Remove

Switch back to the default bar and keep Ilha installed:

```bash
omarchy bar use omarchy.bar
```

`uninstall.sh` does the same thing.

Delete the checkout (the GitHub repo stays):

```bash
omarchy plugin remove esegnorelli.ilha
```

Ilha's state folder, `~/.local/state/esegnorelli.ilha/`, stays. Delete it by hand if you want.

If Ilha fails to load, Omarchy falls back to `omarchy.bar` on its own.

## What you see

One island per monitor, centred at the top. It floats over the windows: nothing is reserved at the top, so windows use the whole screen and the pill sits on top of them. Set `reserveTop` (see Settings) to reserve 48 px instead, like a regular bar, so windows start below it. Either way the pill grows over the windows; they do not move. Omarchy's notifications and popups still keep 48 px clear of the top. The island sits on the top layer. A screen opened over a fullscreen window moves to the overlay layer, so it shows above it.

With the bar hidden (`omarchy toggle bar`), the pill (and the 48 px, with `reserveTop`) goes away. Screens opened by a key or by IPC still appear.

| State | What is on the pill |
|---|---|
| Rest | Only the time, in a capsule 32 px tall, 10 px from the top edge. While recording, a red mark and the elapsed time sit beside it. |
| Icons | The pointer is on the pill. A capsule 42 px tall, as wide as its content: the workspaces, the clock, and the seven screens as icons. |
| Level 2 | A tap on the recording mark, a tap on the live notice for a recording, a reminder, or an update, a click on the clock or a gap in the icons, or `ilha hover 2`. The top band fits its content (context, clock, and status, and the module row when there is one): the focused app over the workspaces, a large clock with the date, and the status line. With Omarchy modules, the pill grows 40 px and they sit in a row underneath. |
| Live notice | Something just turned on. One short line, 40 px tall. |
| OSD | `ilha osd`, the resolution prompt, or the restart notice. 40 px tall. |
| Screen | One of the screens, in the same shape. |

### Rest

Only the time: `HH:mm` in the language's digits. It is 12-hour (`h:mm`, with no AM/PM) when the `omarchy.clock` entry in the bar layout of `shell.json` has a `format` with `AP`.

The one exception is recording, for privacy: a red mark and the elapsed time (`0:42`) sit beside the clock (on its left; on its right in right-to-left languages). With the pointer over the mark, the pill stays at rest so a tap lands on it; the tap opens level 2 pinned on the recording, where a click stops it. Other states (Do not disturb, night light, stay awake, reminders, updates) show as a live notice when they turn on, and on level 2.

### Icons

The pointer on the pill, in the gap above it, or on the top strip turns the clock into one capsule with three groups, split by thin lines:

- The monitor's numbered workspaces: at least five, up to the highest one that exists in the monitor's block. The active one is filled with the accent color, an occupied one is tinted, an empty one is faint, and an urgent one takes the urgent color. A click focuses the workspace. The workspace under the pointer lightens.
- The clock in the middle. A click on it, or on a gap, opens level 2. Screen icons are Omarchy's menu glyphs, in the shell font, so a menu update does not leave Ilha with a missing glyph.
- The icons of Ilha's seven screens, in the order of Alt+1–7: Apps, Calendar, Themes (with wallpapers), Capture, Omarchy, Control Center, Power. A tap on an icon opens that screen.

A click on the clock at rest (a touch screen has no hover), a right click, or a long press (0.5 s) also shows the icons. Opened that way, they close by themselves 2.6 s later if the pointer never reaches them, or 0.7 s after it leaves. They do not open while a screen is open or while the bar is hidden.

### Level 2

A tap on the recording mark, or on the live notice for a recording, a reminder, or an update, opens it with that status line pinned. A click on the clock or a gap in the icons opens it too. `ilha hover 2` holds it on the focused monitor until `ilha hover 0`. Otherwise it stays while the pointer is on it, resting on a module, or while a module panel is open, and closes 2.5 s after the pointer leaves. Super+Ctrl+Alt+D no longer opens it: that key opens the Calendar.

- Left: the focused window's app icon and name, or "Desktop" when the workspace has no window. When the focused window is the music player, its title and artist. Under it, the workspaces, larger.
- Centre: the clock, larger, and the date in the language's own format.
- Right: the status line, over Ilha's own network and battery. Those two hide when the matching `omarchy.network` or `omarchy.power` module is in the row below.
- Below, when there are Omarchy modules: the widgets of `bar.layout`, in the default bar's order (left, centerBegin, center, centerEnd, right), grouped by section with a divider. The menu, workspaces, and clock widgets are left out: Ilha draws those itself. A widget that hides itself takes no room. The indicators (Do not disturb, night light, stay awake, and the rest) all show at once, the active ones bright and the others dimmed, and a click toggles each. Glyphs use the island's ink, so they do not vanish on a light theme. A click opens the widget's panel just below level 2. The pointer in the panel, or resting on the module, holds level 2.

A capsule focuses its workspace. The app line opens Apps (Media when it shows the player). The clock and date open the Control Center. The status line runs its action. Empty space shows the icons.

The status line shows the first match:

| State | Text | Click |
|---|---|---|
| Remote session | "Remote session", or "Remote session · " and who is connected | Nothing |
| Recording | "Recording 0:42" | Stops the recording |
| Passwordless sudo | "Passwordless sudo on" | Turns it off |
| Notifications on screen | "3 notifications" | Control Center |
| Reminder | "Reminder in 15 min" | Runs `omarchy-reminder show` |
| Update | "Update available" | Opens `omarchy-update` in a floating terminal |
| Stay awake | "Staying awake" | Turns stay awake off |
| A track is loaded | "Title · Artist" | Media |
| Do not disturb | "Do not disturb" | Turns it off |
| Nothing | "All caught up" | Control Center |

### Top edge

A 3 px invisible strip along the central 600 px of the top edge (less on narrow screens) shows the icons, never level 2. Over the recording mark, the pill stays at rest instead, so pushing the pointer to the top over the mark and clicking opens level 2.

### Live notice

When something turns on, the pill on the focused monitor becomes one short line, then returns to the clock.

| Trigger | Line | Tap |
|---|---|---|
| A recording starts | "Recording 0:42" (keeps counting) | Level 2, pinned on the recording |
| A reminder is set, and once more when 5 minutes are left | "Reminder in 15 min", or "Reminder in 15 min · " and its message | Level 2, pinned on the reminder |
| An update becomes available | "Update available" | Level 2, pinned on the update |
| Do not disturb turns on | "Do not disturb on" | Control Center |
| Night light turns on | "Night light on" | Control Center |
| Stay awake turns on | "Stay awake on" | Control Center › Display, Stay awake card highlighted |
| An urgent notification arrives | The app and the summary | Control Center, with that notification highlighted |

- It stays 2.6 s (an urgent notification 4 s) and ends early if the state turns off. The pointer on it pauses the count; after the pointer leaves, it stays 1 s more. A right click dismisses it.
- Only a change counts. States already on when Ilha starts, or that change in its first 4 seconds, raise nothing. Remote session and passwordless sudo never raise one; they show on level 2.
- While Do not disturb is on, only the Do not disturb, recording, and urgent notices appear.
- No notice appears while a screen or the picker is open, or while a window is fullscreen on the focused monitor. While the focused pill shows the icons, level 2, or an OSD, the notice waits up to 5 s for it to return to rest.
- A notice of equal or higher priority replaces the one on screen (urgent, recording, reminder, update, Do not disturb, night light, stay awake). An OSD on the same monitor ends it.
- With Live notice off in Ilha settings, no notice appears.

Regular notifications never show in the pill. Omarchy's own cards stay, because they carry the actions.

## Screens

Seven screens, in one order: Apps, Calendar, Themes (with wallpapers), Capture, Omarchy, Control Center, Power. The icons, Alt+1–7, Ctrl+Tab, the wheel, and the navigation capsule all use it. Media is a screen outside that order (see Media). A screen opens in the pill, on the focused monitor for keys and IPC, or on the monitor you clicked. Screens opened by a key, by IPC, or by a takeover start in keyboard mode. Focus rings show only in keyboard mode.

### Navigation

Under every open screen sits a small capsule that rides the screen's bottom edge: Back, then the seven screens in the order above, with the open one marked in the accent color. A click on a screen icon switches to it. Back goes, in this order: out of a Control Center page or popover (in the Omarchy screen: clears the search, then goes up a level), to the screen you were on before, or, with nowhere left to go, closes the island. Alt+← and the mouse's back button do the same. Closing the island clears the history. In right-to-left languages the capsule mirrors, and Back sits on the right.

### Control Center

514 × 588. Two rows of controls, then four cards.

| Place | Control | Click |
|---|---|---|
| Row 1 | Wi-Fi tile (network name, "Not connected", "Off", "Unavailable", or "Ethernet") | The tile opens the Wi-Fi popover. The icon circle turns Wi-Fi on or off |
| Row 1 | Focus tile | Turns Do not disturb on or off |
| Row 1 | Lock (round) | Closes the island and runs `omarchy system lock` |
| Row 2 | Bluetooth tile ("On", "Off", "2 connected", or "No Bluetooth adapter") | The tile opens the Bluetooth popover. The icon circle turns Bluetooth on or off |
| Row 2 | Game Mode tile | On, it turns off animations, removes gaps, and makes windows opaque, saving what it changed. Off, it puts back only what it changed |
| Row 2 | Night Light (round) | Turns night light on or off, at the temperature set in Display |
| Card | Sound | Volume bar: drag or click. A tap on its icon mutes. The arrow opens the Sound page |
| Card | Display | Brightness of the focused monitor ("Brightness unavailable" when it has no control). The arrow opens the Display page |
| Card | Now playing | The cover, the title, and the artist (or the player's name), then previous, play/pause, and next. With no player: "Nothing playing". A tap on the cover or the text opens Media |
| Card | Notifications | See below |

**Notifications.** On-screen notifications first, with an accent dot, then those closed in the last 24 hours since the last Clear, newest first, at most 30. "Clear" dismisses them all. A click on the newest on-screen one clicks it, as Omarchy's card would, and closes the island. Hovering an on-screen one shows a button to dismiss it. With none: "No notifications". The settings button in the header corner opens Ilha settings. Apps, Themes, Wallpapers, and Power are not repeated here: they are already in the icons and the navigation.

**Popovers and pages.** Each one grows out of the control that opened it and dims the grid. The back button, Esc, or a press outside the card returns.

- Wi-Fi: a switch for the radio, the connected network with Disconnect, then "Networks" with Connect. It scans only while open. Five rows show, then the list scrolls. A secured network asks for its password in the row ("Wrong password" on failure). A known network shows a button to forget it. An enterprise (802.1X) network opens `nmtui` in a terminal.
- Bluetooth: a switch, "Saved" devices with Connect or Disconnect, then "Nearby" devices with Pair. It looks for devices only while open. Connecting headphones moves the audio output to them.
- Sound: "Output" devices and the output volume, then "Input" devices and the input volume. A row sets the default device.
- Display: one card per monitor, with brightness, scale (1.0× to 2.0×, the ones that fit the monitor), and Resolution (up to 6 modes). A new resolution asks "Keep this resolution? Reverting in 10 s", with Keep and Revert, and reverts on its own. If the Control Center closes, the countdown moves to the pill, and a tap keeps the resolution. Then Night Light (a switch and the temperature, 2500–5800 K) and Stay awake ("Screen won't dim, lock or sleep").
- Ilha: the two switches. See Settings.

**Keys.** The arrows move by position. Tab and Shift+Tab move in order. Home goes to Wi-Fi, End to the notifications. Enter runs the main action. Space presses a tile's icon circle, or mutes on the Sound bar. On a bar, Left and Right change it by 5 % (Shift: 1 %). M mutes on the Sound card. On the Now playing card, the cover and text, previous, play/pause, and next are four stops in one row. On a notification, Delete dismisses an on-screen one, and Enter on the newest on-screen one clicks it. In the popovers and pages, Up and Down move, Enter and Space choose or toggle, Space turns the radio on or off in Wi-Fi and Bluetooth, Delete forgets a known Wi-Fi network, Left and Right change bars by 5 % (Shift: 1 %), and M mutes the focused section in Sound. Esc closes the password field or an open list, then the popover or page, then the island.

### Apps

514 × 368. The app search: "Search…" at the top, six rows below.

- With nothing typed, every visible app, A to Z. Typing ranks by fuzzy match. No match: "No apps found".
- Hidden entries follow Omarchy's own rules.
- The highlight follows the pointer only when the pointer moves. The wheel scrolls.
- Terminal apps open through `omarchy-launch-tui`, the rest through `uwsm-app -- gtk-launch`. When no window appears within 2 s, Omarchy's OSD says "Launching Firefox…" (with the app's name) until it does, for at most 15 s.
- Keys: Up and Down, Tab and Shift+Tab (they wrap around), Page Up and Page Down by 6. Enter opens the app and closes. Esc clears, then closes.

### Calendar

514 × 420. The month, the year and life bars, other time zones, and reminders. Super+Ctrl+Alt+D (Omarchy's calendar key) and `omarchy-shell omarchy.clock open` open it too.

- Header: the month and year, then "Back to today" (only while another day is selected), previous month, and next month.
- Bars: how much of the year has passed, and life. Life uses `birthYear` and `lifeExpectancy` (90 by default) from the `omarchy.clock` entry in `bar.layout`. Without a valid `birthYear`, the life bar goes and the year bar takes the whole line. Both follow today, not the month on screen.
- Grid: always six weeks, with the ISO week number in a column on the side. The week starts on that entry's `weekStartDay`, or on the language's first day, or on Monday. Today is an accent circle; the selected day has a ring. Days of other months are faint, weekends dimmer. A dot marks a day with a reminder. A click selects a day; a day of another month goes to that month. The wheel over the grid changes the month.
- Time zones: up to four cities from the `omarchy.elsewhen` entry in `bar.layout` (`cities`, or the older `zones`), each with its time and "+1 day" or "-1 day" when it is on another date. The city of the local time zone is left out. With no cities, the row goes.
- Reminders, from `omarchy-reminder show --json`: those of the selected day, with the date as the title; with none that day, "Upcoming reminders"; with none at all, "No outstanding reminders". Each row has the time, the message, and the time left. When more exist than fit, the title adds the count. "Set reminder" closes the island and runs `omarchy-reminder -i`.
- Keys: the arrows move the day (Left and Right follow the screen direction). Page Up and Page Down change the month (Shift: the year). Home goes back to today, End to the last day of the month. Tab and Shift+Tab go through the grid, "Back to today", the two month buttons, and "Set reminder". Enter and Space press the focused button. Esc closes.

### Themes and wallpapers

One screen, two rows, as wide as 2 to 5 wallpaper thumbnails fit on the screen (32 + 196 px each), 412 tall. ↑ and ↓ move between the rows; the pointer over a row makes it the active one. Only the active row shows its accent border. `ilha open wallpapers` (and the aliases `wallpaper` and `background`) open the same screen on the bottom row.

Top row, the themes:

- A search field ("Search themes…") and a counter (`3/18`). No match: "No themes match". The field keeps the keyboard, so typing always filters the themes.
- Each card shows the theme's own preview image, its six palette colors, and its name in its text color, over a band of the theme's background. A theme with no preview shows its background with larger dots. The centre card is the selected one: it lifts and, in the active row, gets an accent border. A small dot marks the theme in use.
- Enter runs `omarchy-theme-set`. The dot moves at once. The screen stays open and moves to the bottom row, which then shows the new theme's wallpapers. The island's colors cross-fade in 150 ms when the new palette arrives.
- Themes come from `~/.config/omarchy/themes` and from Omarchy's own themes. Yours wins on the same name. The preview is the theme's `preview.png` (or `.jpg`, `.jpeg`, `.webp`), the same file Omarchy's theme switcher uses.

Bottom row, the wallpapers of the theme in use:

- "Wallpaper" and the theme name at the top. The selected thumbnail sits in the centre. A small dot marks the wallpaper in use. Under the strip: the file name, the counter, and "Enter to apply".
- The current theme's backgrounds plus `~/.config/omarchy/backgrounds/<theme>`. Enter runs `omarchy-theme-bg-set`; the screen stays open, so you can try another. None: "No wallpapers for this theme".
- Opened by Omarchy's background keys: see Theme and wallpaper keys. That request closes the screen once you choose.
- Video wallpapers use their cached thumbnail.

Mouse: a click centres a card or thumbnail. A click on the centre one, or a double click, applies. The wheel moves one per notch. Keys in the active row: Left and Right (they follow the screen direction), Tab and Shift+Tab, Page Up and Page Down, Home, End, Enter applies. Esc clears the search, then closes.

### Capture

514 × 236. Omarchy's Capture menu in the pill. On top, five buttons in the order of Omarchy's menu: Screenshot, Screenrecord, Text, QR Code, Color. Below them, the options of the chosen button. Every action closes the island first and runs 180 ms later, so the island stays out of the capture.

- Screenshot: the button runs `omarchy-capture-screenshot`. Its options are Region, Window, and Full screen (`omarchy-capture-screenshot region`, `windows`, `fullscreen`).
- Screenrecord: the button does not record; it moves to the modes. With no audio (`omarchy-capture-screenrecording`), With desktop audio (`--with-desktop-audio`), With desktop + microphone audio (`--with-desktop-audio --with-microphone-audio`), and With desktop + microphone audio + webcam (`omarchy-capture-screenrecording-with-webcam`, dimmed when `omarchy-hw-webcam` finds no webcam).
- While recording, the second button becomes "Stop recording", with the elapsed time. The screen opens on it, so Enter stops the recording (`omarchy-capture-screenrecording --stop-recording`).
- Text (`omarchy-capture-text`), QR Code (`omarchy-capture-qr`), and Color (`hyprpicker -a`; a running hyprpicker closes instead) have no modes. Below them: Share the clipboard, a file, or a folder (`omarchy-menu-share clipboard`, `file`, `folder`), and Clipboard History (`omarchy-shell shell summon omarchy.clipboard`).
- The labels come from Omarchy's own menu catalog, in the Omarchy language. Region, Window, and Full screen are Ilha's.
- Mouse: hovering selects, a click runs. Keys: Left and Right (they follow the screen direction), Down into the options, Up back, Tab and Shift+Tab within the row, Home, End, 1 to 5 run a button, Enter and Space run. Esc closes.

### Omarchy

514 × 460. The whole Omarchy menu in the pill, one level at a time.

- It reads the same files as Omarchy's menu: `$OMARCHY_PATH/default/omarchy/omarchy-menu.jsonc`, with your extension `~/.config/omarchy/extensions/omarchy-menu.jsonc` merged on top, field by field. Labels use Omarchy's translations (`default/i18n/<language>/menu.json`). Changes on disk show while the screen is open.
- `when`, `checked`, and `disabled` run as shell commands, as in Omarchy. A false `when` hides the row. `checked` and `disabled` show a ✓; `disabled` also dims the row, and the selection skips it. A › marks a submenu.
- Providers: fonts, power profiles, kernels, and languages run the same scripts as Omarchy's menu, and a ✓ marks the current value. Apps opens Ilha's Apps screen. A provider Ilha does not know opens Omarchy's own menu at that point.
- Search: the field at the top searches everything under the open level (the whole menu at the root), direct children first. Each result shows its path under it. Apps show up in the search too, and open directly. Dimmed rows are left out.
- Path: under the search, for example "Omarchy › Trigger › Capture". A click on an upper level goes there. Outside the root, a Back button starts the path.
- An action closes the island and runs its command as Omarchy would, 180 ms later.
- Keys: Up and Down, Tab and Shift+Tab (they wrap around), Page Up and Page Down by 6. Enter enters or runs. With the search empty, Right enters or runs, Left and Backspace go up a level, and Home and End go to the first and last rows. Left and Right follow the reading direction. Esc clears the search, then closes. The mouse: a click enters or runs; the wheel scrolls.

### Media

514 × 218. The active MPRIS player, from Omarchy's media service.

- The cover, the title, the artist, and the player's name. With more than one player, the name is a button that switches player.
- The seek bar, with elapsed and remaining time. Click or drag it when the player allows.
- Shuffle, previous, play/pause, next, repeat (off, playlist, track). Shuffle and repeat work when the player supports them.
- With no player: "Nothing playing" and "Play something in any player", at the same size.
- Keys: Space or Enter play/pause, Left and Right seek 5 s, Shift+Left and Shift+Right previous and next, S shuffle, R repeat, P next player.

It is not among the icons. It opens from the Control Center's Now playing card, the level 2 app and status lines, a media OSD, and `ilha open media`.

## Mouse and keyboard

- The wheel switches screens only while a screen is open, on the band across the screen's width in the top 24 px of the monitor: the gap above the screen and its top padding. Each notch (120 units) moves one screen, in the order above. Down goes forward, up goes back. A partial scroll resets after 200 ms without wheel events, or when the direction flips, so slow trackpad drift never switches. Right-to-left languages do not flip it. At rest, with the icons, on level 2, on a notice, or on an OSD, the wheel does not switch screens. Lists, carousels, and sliders keep their own wheel.
- The pointer on the pill shows the icons. A click on the clock at rest, a right click, or a long press (0.5 s) shows them too. In the icons, a click on the clock or a gap opens level 2; a right click closes them. On a live notice it dismisses it.
- A click outside an open screen closes it.
- Keys work only while a screen is open. The icons, level 2, and the notices never take the keyboard.
- Ctrl+Tab and Ctrl+Shift+Tab walk the screens. Alt+1–7 open them directly: Apps, Calendar, Themes (with wallpapers), Capture, Omarchy, Control Center, Power.
- Alt+← and the mouse's back button go back (see Navigation).
- Esc first goes to the screen (it clears a search, closes a popover or page, cancels a confirmation), then closes the island.
- Any key turns keyboard mode on. Moving the pointer more than 8 px turns it off.

### Omarchy keys

A panel key opens Omarchy's own panel for that widget, under level 2, when the widget is in `bar.layout`; level 2 opens on the focused monitor and the row is the anchor. Without the widget, the key opens Ilha's screen. `omarchy.clock` and `omarchy.media` always open Ilha's Calendar and Media. The same key again closes what it opened.

| Key | Omarchy name | In Ilha |
|---|---|---|
| Super+Ctrl+A | Audio | Omarchy's audio panel, with the mixer. Without the widget: Control Center › Sound |
| Super+Ctrl+B | Bluetooth | Omarchy's Bluetooth panel. Without the widget: Control Center › Bluetooth |
| Super+Ctrl+N | Network | Omarchy's network panel. Without the widget: Control Center › Wi-Fi |
| Super+Ctrl+D | Display | Omarchy's display panel. Without the widget: Control Center › Display |
| Super+Ctrl+P | Power | Omarchy's power and battery panel. Without the widget: Power |
| Super+Ctrl+Alt+D | Calendar | Calendar |
| Super+Ctrl+Alt+E | World clock | Omarchy's Elsewhen panel. Without the widget: Control Center |
| Super+Ctrl+1 to 9 | Bar panel 1–9 | The same panels as in the default bar: the visible panels of the `right` section, in `bar.layout` order, without the tray. A number past the last does nothing |
| Super+Ctrl+T, Super+Shift+Ctrl+Space | Theme menu | Themes |
| Super+Ctrl+W, Super+Ctrl+Space | Background switcher | Wallpapers |

### Theme and wallpaper keys

Ilha takes over Omarchy's two image pickers. No key and no menu entry is rebound: the same keys and entries open Ilha's screens.

- **Wallpapers.** Super+Ctrl+W, Super+Ctrl+Space, and Menu › Appearance › Background run Omarchy's background switcher, which asks the shell's `image-selector` target for a picker. Ilha answers that target ahead of Omarchy's picker. When every image in the request is in the theme's backgrounds (`~/.local/state/omarchy/current/theme/backgrounds/`) or in `~/.config/omarchy/backgrounds/`, the Themes and wallpapers screen opens on its wallpaper row, with the request's images. Enter writes the choice to the reply file the script waits on, and Omarchy's script applies it. Esc, a click outside, or another screen hands back an empty choice, so the script never waits forever.
- **Themes.** Super+Ctrl+T, Super+Shift+Ctrl+Space, and Menu › Appearance › Theme open Omarchy's theme picker. When that picker opens without a request Ilha passed on, Ilha hides it and opens the Themes and wallpapers screen on its theme row. Omarchy's picker maps transparent at first, so it is hidden before it shows a frame.
- Any other request, such as images from another folder, goes to Omarchy's own picker unchanged.
- Both takeovers end when you switch back to the default bar.

### Optional bindings

Add them to `~/.config/hypr/bindings.lua`. Check what is taken first with `omarchy menu keybindings --print`.

`Super+Z` is free in the default Omarchy bindings. `Super+Ctrl+Z` is zoom, so leave that one alone.

```lua
o.bind("SUPER + Z", "Ilha", "omarchy-shell ilha toggle last")
```

This one replaces Omarchy's own Apps grid (from the dock) with Ilha's Apps:

```lua
o.rebind("SUPER + ALT + SPACE", "Apps", "omarchy-shell ilha toggle launcher")
```

## OSD

The host does not give its OSD to third-party plugins. System keys (volume, brightness, media) keep showing Omarchy's own OSD.

The pill shows:

- `ilha osd '<json>'`, with the same fields as `omarchy-shell osd show`: `icon`, `message`, `value`, `max`, `progressText`, and `duration` in ms (default 1200; `0` or `sticky` hands it to Omarchy's OSD, since the pill keeps only its own fixed notices). A value with no message draws an icon, a bar, and the value. A message draws one line. A `media` or `player` icon draws the cover with the title and artist.
- "Keep this resolution? Reverting in 10 s", while the Display page is not on screen. A tap keeps the resolution.
- The restart notice (see Update).

When the pill cannot draw (the bar is hidden, a window is fullscreen on the focused monitor, or a screen other than the Control Center is open), `ilha osd` goes to Omarchy's OSD instead. With the Control Center open, a volume or brightness OSD is not drawn while its slider is on screen; anything else goes to Omarchy's OSD.

The OSD shows on the focused monitor. A tap on a volume OSD opens Control Center › Sound, on a brightness OSD Control Center › Display, on a media OSD Media. Any other tap dismisses it.

## Appearance

- **Colors.** Ilha reads the Omarchy theme's background, text, accent, and urgent colors. The island is always dark: its surface is the darker of background and text, at 10 % over black. Cards and rows are lighter steps of the text color. The accent is moved toward the text color until it reads on the surface (3:1 for fills, 4.5:1 for text), and so is the urgent color. A theme change cross-fades in 150 ms. Ilha writes no palette. Glyphs of the widgets in the level 2 row use the island's ink; text inside their panels keeps the Omarchy bar colors.
- **Shape.** A capsule with a 1 px rim and a soft shadow. When Omarchy's glassy toggles are on (`~/.local/state/omarchy/toggles/hypr/bar-glassy.lua` or `window-glassy.lua`), the shadow is lighter. The island stays opaque.
- **Position.** Always at the top. Omarchy's bar position and bar background settings do not apply to Ilha.
- **Fonts.** Text uses the bundled Inter subset; other scripts fall back to the system fonts. Icons use the bundled Material Symbols Rounded subset. The Omarchy screen draws the menu's own glyphs in the shell's font.
- **Motion.** The shape moves on springs and the content fades in at its final layout. With Hyprland's animations off (`omarchy toggle animations`, or Game Mode), every change is instant.

## Settings

Two switches, in Control Center › Ilha settings (the settings button in the Notifications card header), or with `omarchy-shell ilha open settings`:

- **Focused monitor only** (`focusedOnly`, off by default): "Other monitors show no pill". Only Hyprland's focused monitor draws the pill at rest. The other monitors draw nothing and take no input until the focus moves there. With `reserveTop`, every monitor keeps its 48 px, so windows do not move when the focus moves.
- **Live notice** (`livePeek`, on by default): "A short sentence when something turns on". Off, no live notice appears.

One more key has no switch: **`reserveTop`** (off by default). On, Ilha reserves 48 px at the top of each monitor and windows start below it. Off, the island floats over the windows. Turn it on with `omarchy-shell ilha setting reserveTop true`; it applies at once.

The page also shows the version.

Ilha stores the keys in `~/.config/omarchy/shell.json`, under `bar.ilha`, through the host's plugin API (`mutateShellConfig`), which writes the file atomically. It changes only the key you flipped, and only when you flip a switch or run `ilha setting`. Nothing is written at install or at start. The pill reads them live, so a hand edit of `shell.json` counts too. Without the host API, a choice lasts until the shell restarts, and the page says "Saved until the shell restarts".

```json
"bar": { "ilha": { "focusedOnly": false, "livePeek": true, "reserveTop": false } }
```

```bash
omarchy-shell ilha setting livePeek false
omarchy-shell ilha setting focusedOnly toggle
```

## IPC

```bash
omarchy-shell ilha open <screen>           # opens a screen, in keyboard mode
omarchy-shell ilha toggle <screen>         # opens it, or closes it when that exact screen is open
omarchy-shell ilha close                   # closes the open screen and the picker
omarchy-shell ilha back                    # goes back: a Control Center page, the previous screen, or closes
omarchy-shell ilha run <screen> <key>      # opens in keyboard mode and sends one key, e.g. run themes right
omarchy-shell ilha picker                  # toggles the icons (the picker) on the focused monitor
omarchy-shell ilha hover <0|1|2>           # holds the icons (1) or level 2 (2) on the focused monitor; 0 releases it
omarchy-shell ilha peek <key>              # shows a live notice now
omarchy-shell ilha osd '<json>'            # shows an OSD in the pill
omarchy-shell ilha closeOsd                # hides the pill's OSD
omarchy-shell ilha setting <key> <value>   # focusedOnly | livePeek | reserveTop; true | false | toggle
omarchy-shell ilha state                   # prints the state as JSON
```

- Screens: `launcher`, `calendar`, `themes`, `capture`, `menu`, `control`, `power`, `media`; `wallpapers` opens `themes` on the wallpaper row. Control Center parts: `sound`, `display`, `wifi`, `bluetooth`, `settings`. Aliases: `apps` (launcher), `clock` and `time` (calendar), `theme` and `look` (themes), `screenshot` and `record` (capture), `omarchy` (menu), `cc` and `controls` (control), `wallpaper`, `background`, and `backgrounds` (the wallpaper row), `last` (the last screen opened).
- `run` keys: a letter or digit, `enter`, `space`, `esc`, `tab`, `up`, `down`, `left`, `right`, `pgup`, `pgdn`, `home`, `end`, `delete`, with an optional `shift+`, `ctrl+`, or `alt+` in front. The key goes once the screen is ready (3 s at most).
- `peek` keys: `recording`, `reminder`, `update`, `dnd`, `nightlight`, `stayAwake`, `urgent`. It shows even when that state is off, but not with Live notice off. `urgent` uses the newest on-screen notification.
- Answers: `open` and `toggle` print `ok` or `unknown`; `run` prints `ok`, `unknown`, or `invalid-key`; `picker` prints `open`, `closed`, or `busy`; `peek` prints `shown`, `queued`, `off`, `busy`, `quiet`, `unknown`, or `empty`; `osd` prints `ok`, `invalid`, or `off`; `setting` prints `ok`, `unknown`, or `invalid`.
- `state` includes the open screen, each monitor's face, the OSD, the live notice, the picker, the settings (with `canPersist`), the takeovers, the hosted Omarchy widgets, and both versions.

Ilha also answers the targets the default bar registered, so Omarchy's own scripts keep working:

```bash
omarchy-shell omarchy.clock <open|show|close|hide|toggle|refresh>   # open and show: the Calendar; close and hide: close it
omarchy-shell omarchy.bar syncHidden
omarchy-shell omarchy.indicators refresh
omarchy-shell omarchy.system-update <refresh|clear>
omarchy-shell omarchy.workspaces refresh
```

The `osd` target stays Omarchy's.

## Languages

Ilha ships a catalog in `i18n/` for each of the 50 languages Omarchy offers. It follows Setup › Language live, without a shell restart. Numbers use the language's digits: the clock, the workspaces, the recording time, the calendar, and the percentages. The level 2 date uses each language's own pattern and its day and month names, and so does the Calendar. The Calendar, Capture, and Omarchy screens also use Omarchy's own translations for the text Omarchy already has. A missing string falls back to English.

Right-to-left languages (Arabic, Persian, Hebrew, Urdu) mirror the whole island. The mark sits right of the clock, the icon capsule starts with the workspaces on the right and the clock in the middle, and the notice icon is on the right. Left and Right follow the screen direction. The clock, the recording time, the network bars, the battery, and the Media seek bar, times, and transport buttons stay left to right on purpose.

## Dependencies

Omarchy, with its shell. No extra packages. The fonts ship in `fonts/`. Buttons call the Omarchy commands and services they name (`omarchy-theme-set`, `omarchy-theme-bg-set`, `omarchy-system`, `omarchy-brightness-display`, `omarchy-bluetooth-power`, `omarchy-audio-output-set-default`, `omarchy-capture-screenshot`, `omarchy-reminder`, and so on). Ilha runs Omarchy's own update check (`omarchy-update-available`) 5 s after it starts, every 6 hours, and when Omarchy asks.

The level 2 row hosts the widgets of `bar.layout`, the tray included, with the components the host gives a bar. The menu, workspaces, and clock widgets are not hosted: Ilha draws its own. A key for a panel that is neither a hosted widget nor an Ilha screen does nothing. Switch back with `omarchy bar use omarchy.bar` when you need the default bar.

## Files

| Path | Role |
|---|---|
| `manifest.json` | Plugin id, version 2.4.0, and the `bar` entry `ui/Ilha.qml` |
| `ui/Ilha.qml` | Entry point: host contract, navigation, services, settings, IPC, the hosted widgets and their panels |
| `ui/IslandWindow.qml` | One window per monitor: the shape, the faces, the input mask, the keys |
| `ui/HoverBar.qml`, `RestMark.qml`, `ScreenPicker.qml`, `ScreenNav.qml`, `HeroClock.qml`, `Workspaces.qml` | Level 2, the rest mark, the screen picker, the navigation under a screen, the clock, the workspaces |
| `ui/OmarchyWidgets.qml`, `BarFacade.qml` | Omarchy's bar widgets in the level 2 row, and the `bar` object each one receives |
| `ui/PeekBridge.qml`, `PeekFace.qml` | Live notice |
| `ui/OsdBridge.qml`, `OsdFace.qml` | OSD in the pill, resolution prompt, restart notice |
| `ui/PickerBridge.qml` | Theme and wallpaper takeovers |
| `ui/ScreenStack.qml` | Loads and switches the screens |
| `ui/ControlCenter.qml`, `WifiCard.qml`, `BluetoothCard.qml`, `SoundPage.qml`, `DisplayPage.qml`, `IlhaPage.qml`, `MediaCard.qml`, `NotificationsCard.qml` | Control Center |
| `ui/CalendarScreen.qml`, `CalendarSvc.qml` | Calendar, with its reminders, time zones, and the clock settings it reads |
| `ui/CaptureScreen.qml`, `CaptureSvc.qml` | Capture, with Omarchy's labels, the webcam check, and the commands |
| `ui/MenuScreen.qml`, `MenuSvc.qml`, `OmarchyMenu.js` | The Omarchy screen and the menu as data. `OmarchyMenu.js` is an MIT port of Omarchy's `MenuModel.js` |
| `ui/LauncherScreen.qml`, `MediaScreen.qml`, `LookScreen.qml` (with its rows `ThemeScreen.qml` and `WallpaperScreen.qml`), `PowerScreen.qml` | The other screens |
| The other `ui/*Svc.qml`, `StateStore.qml`, `AppSearch.js` | Status, audio, network, monitors, media, apps, themes, settings (`PrefsSvc.qml`), own state |
| `ui/Theme.qml`, `Motion.js`, `Morph.qml`, `SpringValue.qml` | Colors, sizes, geometry of each face, springs, timings |
| The rest of `ui/` | Controls: `IlhaSwitch`, `IlhaSlider`, `IlhaRoundButton`, `ToggleTile`, `Carousel`, `CircleButton`, and others |
| `fonts/` | `InterIlha2.ttf` (Inter subset, OFL, `LICENSE-Inter.txt`) and `MaterialSymbolsRoundedIlha2.ttf` (Material Symbols Rounded subset, Apache 2.0, `LICENSE-MaterialSymbols.txt`) |
| `i18n/` | One catalog per Omarchy language |
| `dev/` | Development only; Omarchy never loads it. `harness.sh` runs a separate Quickshell instance that never touches the running shell; the Python scripts check catalogs, icons, names, and contrast, and build the font subsets |
| `uninstall.sh` | Switches back to the default bar. Omarchy does not run it |

A screen receives `island`, `theme`, `strings`, `morph`, `payload`, `current`, and `keyboardMode`, and reports its size with `implicitWidth` and `implicitHeight`. It implements `opened(payload)`, `closed()`, `handleKey(event)`, and `handleEscape()`, and can emit `navigate(id, payload)` and `closeRequested()`. Nothing in a screen runs before `opened()` or after `closed()`.

## Troubleshooting

- The new checkout did not become the bar. Run `omarchy restart shell`, then `omarchy plugin enable esegnorelli.ilha`.
- The shell logged `bar option esegnorelli.ilha failed to load, falling back to omarchy.bar`. Run `omarchy plugin validate ~/.config/omarchy/plugins/esegnorelli.ilha` and read `journalctl -t omarchy-shell`.
- The pill says "Restart the shell to finish updating Ilha". The shell still runs older Ilha code. Tap the notice, or run `omarchy restart shell`.
- Volume and brightness keys show Omarchy's OSD, not the pill. That is expected: the host does not give its OSD to third-party plugins.
- A bar widget is missing from the level 2 row. Ilha shows only the widgets in `bar.layout` of `~/.config/omarchy/shell.json`, minus the menu, the workspaces, and the clock. A widget that hides itself (such as the update or keyboard layout widget) takes no room.
- `omarchy plugin update` refuses to pull. The checkout has local edits. Commit or stash them in `~/.config/omarchy/plugins/esegnorelli.ilha`.

## License

[MIT](LICENSE). Copyright 2026 Evandro Segnorelli.
