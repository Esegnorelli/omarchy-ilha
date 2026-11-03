# Ilha

Floating island bar for [Omarchy](https://omarchy.org). At rest it is a clock. Under the pointer it becomes the workspace line, and a click opens the full line. Six screens open inside the same pill: Control Center, Apps, Media, Themes, Wallpapers, and Power.

Documentação em português: [LEIA-ME.md](LEIA-ME.md).

Ilha replaces the bar (`kinds: ["bar"]`, id `esegnorelli.ilha`, version 2.0.0). It is not a widget inside the default bar. Colors follow the Omarchy theme, and the text follows the Omarchy language.

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
| Icons | The pointer is on the pill. The six screens as icons, in a 236 × 42 capsule. |
| Level 2 | Super+Ctrl+Alt+D (Omarchy's calendar key) or a tap on the recording mark. A 718 × 75 pill: the focused app over the workspaces, a large clock with the date, and the status line over network and battery. |
| Live notice | Something just turned on. One short line, 40 px tall. |
| OSD | `ilha osd`, the resolution prompt, or the restart notice. 40 px tall. |
| Screen | One of the six screens, in the same shape. |

### Rest

Only the time: `HH:mm` in the language's digits. It is 12-hour (`h:mm`, with no AM/PM) when the `omarchy.clock` entry in the bar layout of `shell.json` has a `format` with `AP`.

The one exception is recording, for privacy: a red mark and the elapsed time (`0:42`) sit beside the clock (on its left; on its right in right-to-left languages). With the pointer over the mark, the pill stays at rest so a tap lands on it; the tap opens level 2 pinned on the recording, where a click stops it. Other states (Do not disturb, night light, stay awake, reminders, updates) show as a live notice when they turn on, and on level 2.

### Icons

The pointer on the pill, in the gap above it, or on the top strip turns the clock into six icons: Apps, Themes, Wallpapers, Media, Control Center, Power. That is the same order as Alt+1–6. A tap on an icon opens that screen. Media is always there; with no player it opens "Nothing playing". Leave for 250 ms and the pill returns to the clock.

A click on the clock (a touch screen has no hover), a right click, or a long press (0.5 s) also shows the icons. Opened that way, they close by themselves 2.6 s later if the pointer never reaches them, or 0.7 s after it leaves. They do not open while a screen is open or while the bar is hidden.

### Level 2

### Level 2

Super+Ctrl+Alt+D (Omarchy's calendar key) toggles it on the focused monitor. A tap on the recording mark, or on the live notice for a recording, a reminder, or an update, opens it with that status line pinned. It stays while the pointer is on it and closes 2.5 s after the pointer leaves.

- Left: the focused window's app icon and name, or "Desktop" when the workspace has no window. When the focused window is the music player, its title and artist. Under it, the workspaces, larger.
- Centre: the clock, larger, and the date in the language's own format.
- Right: the status line, over network and battery.

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
- Only a change counts. States already on when Ilha starts, or that change in its first 4 seconds, raise nothing. Remote session and passwordless sudo never raise one; they show in the mark and on level 2.
- While Do not disturb is on, only the Do not disturb, recording, and urgent notices appear.
- No notice appears while a screen or the picker is open, or while a window is fullscreen on the focused monitor. While the focused pill shows the icons, level 2, or an OSD, the notice waits up to 5 s for it to return to rest.
- A notice of equal or higher priority replaces the one on screen (urgent, recording, reminder, update, Do not disturb, night light, stay awake). An OSD on the same monitor ends it.
- With Live notice off in Ilha settings, no notice appears.

Regular notifications never show in the pill. Omarchy's own cards stay, because they carry the actions.

## Screens

Six screens, in one order: Apps, Themes, Wallpapers, Media, Control Center, Power. The picker, Alt+1–6, Ctrl+Tab, and the wheel all use it. Ctrl+Tab and the wheel skip Media when no player exists. A screen opens in the pill, on the focused monitor for keys and IPC, or on the monitor you clicked. Screens opened by a key, by IPC, or by a takeover start in keyboard mode. Focus rings show only in keyboard mode.

### Navigation

Under every open screen sits a small capsule that rides the screen's bottom edge: Back, then the six screens in the order above, with the open one marked in the accent color. A click on a screen icon switches to it. Back goes, in this order: out of a Control Center page or popover, to the screen you were on before, or, with nowhere left to go, closes the island. Alt+← and the mouse's back button do the same. Closing the island clears the history. In right-to-left languages the capsule mirrors, and Back sits on the right.

### Control Center

514 × 513. Two rows of controls, then three cards.

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
| Card | Notifications | See below |

**Notifications.** On-screen notifications first, with an accent dot, then those closed in the last 24 hours since the last Clear, newest first, at most 30. "Clear" dismisses them all. A click on the newest on-screen one clicks it, as Omarchy's card would, and closes the island. Hovering an on-screen one shows a button to dismiss it. With none: "No notifications". With the pointer on the card, or in keyboard mode, a row of shortcuts appears in its header: Ilha settings, Apps, Themes, Wallpapers, Power.

**Popovers and pages.** Each one grows out of the control that opened it and dims the grid. The back button, Esc, or a press outside the card returns.

- Wi-Fi: a switch for the radio, the connected network with Disconnect, then "Networks" with Connect. It scans only while open. Five rows show, then the list scrolls. A secured network asks for its password in the row ("Wrong password" on failure). A known network shows a button to forget it. An enterprise (802.1X) network opens `nmtui` in a terminal.
- Bluetooth: a switch, "Saved" devices with Connect or Disconnect, then "Nearby" devices with Pair. It looks for devices only while open. Connecting headphones moves the audio output to them.
- Sound: "Output" devices and the output volume, then "Input" devices and the input volume. A row sets the default device.
- Display: one card per monitor, with brightness, scale (1.0× to 2.0×, the ones that fit the monitor), and Resolution (up to 6 modes). A new resolution asks "Keep this resolution? Reverting in 10 s", with Keep and Revert, and reverts on its own. If the Control Center closes, the countdown moves to the pill, and a tap keeps the resolution. Then Night Light (a switch and the temperature, 2500–5800 K) and Stay awake ("Screen won't dim, lock or sleep").
- Ilha: the two switches. See Settings.

**Keys.** The arrows move by position. Tab and Shift+Tab move in order. Home goes to Wi-Fi, End to the notifications. Enter runs the main action. Space presses a tile's icon circle, or mutes on the Sound bar. On a bar, Left and Right change it by 5 % (Shift: 1 %). M mutes on the Sound card. On a notification, Delete dismisses an on-screen one, and Enter on the newest on-screen one clicks it. In the popovers and pages, Up and Down move, Enter and Space choose or toggle, Space turns the radio on or off in Wi-Fi and Bluetooth, Delete forgets a known Wi-Fi network, Left and Right change bars by 5 % (Shift: 1 %), and M mutes the focused section in Sound. Esc closes the password field or an open list, then the popover or page, then the island.

### Apps

514 × 368. The app search: "Search…" at the top, six rows below.

- With nothing typed, every visible app, A to Z. Typing ranks by fuzzy match. No match: "No apps found".
- Hidden entries follow Omarchy's own rules.
- The highlight follows the pointer only when the pointer moves. The wheel scrolls.
- Terminal apps open through `omarchy-launch-tui`, the rest through `uwsm-app -- gtk-launch`. When no window appears within 2 s, Omarchy's OSD says "Launching Firefox…" (with the app's name) until it does, for at most 15 s.
- Keys: Up and Down, Tab and Shift+Tab (they wrap around), Page Up and Page Down by 6. Enter opens the app and closes. Esc clears, then closes.

### Media

514 × 218. The active MPRIS player, from Omarchy's media service.

- The cover, the title, the artist, and the player's name. With more than one player, the name is a button that switches player.
- The seek bar, with elapsed and remaining time. Click or drag it when the player allows.
- Shuffle, previous, play/pause, next, repeat (off, playlist, track). Shuffle and repeat work when the player supports them.
- With no player: "Nothing playing" and "Play something in any player", at the same size.
- Keys: Space or Enter play/pause, Left and Right seek 5 s, Shift+Left and Shift+Right previous and next, S shuffle, R repeat, P next player.

It also opens from the level 2 app and status lines, a media OSD, and Super+Ctrl+4.

### Themes

As wide as 2 to 4 cards fit on the screen (30 + 194 px per card), 222 tall.

- A search field ("Search themes…") and a counter (`3/18`). No match: "No themes match".
- Each card shows the theme's background, six dots of its palette, and its name in its text color. The centre card is the selected one: it lifts and gets an accent border. A small dot marks the theme in use.
- "Enter to apply". Enter runs `omarchy-theme-set`. The dot moves at once. The screen closes when the theme is in use, or 1.5 s later. There is no live preview. The island's colors cross-fade in 150 ms when the new palette arrives.
- Mouse: a click centres a card. A click on the centre card, or a double click, applies. The wheel moves one card per notch.
- Keys: the arrows (Left and Right follow the screen direction), Tab and Shift+Tab, Page Up and Page Down by 4, Home, End, Enter applies. Esc clears the search, then closes.
- Themes come from `~/.config/omarchy/themes` and from Omarchy's own themes. Yours wins on the same name.

### Wallpapers

As wide as 2 to 5 thumbnails fit on the screen (32 + 196 px per thumbnail), 232 tall.

- "Wallpaper" and the theme name at the top. The selected thumbnail sits in the centre with an accent border. A small dot marks the wallpaper in use. Under the strip: the file name, the counter, and "Enter to apply".
- Opened by Ilha (picker, Alt+3, Ctrl+Tab, `ilha open wallpapers`): the current theme's backgrounds plus `~/.config/omarchy/backgrounds/<theme>`. Enter runs `omarchy-theme-bg-set` and closes when it finishes (at most 1.2 s). None: "No wallpapers for this theme".
- Opened by Omarchy's background keys: see Theme and wallpaper keys.
- Video wallpapers use their cached thumbnail.
- Mouse as in Themes. Keys: the arrows, Tab and Shift+Tab, Page Up and Page Down by one screenful, Home, End, Enter applies, Esc closes.

### Power

514 × 112. Five buttons: Lock, Suspend, Log Out, Reboot, Power Off.

- Lock is selected when it opens. The pointer selects, a click presses.
- Log Out, Reboot, and Power Off need a second press within 3 s: the label reads "Press again". A second press sooner than 350 ms is ignored.
- Suspend is dimmed when sleep is turned off in Omarchy.
- Keys: Left and Right (they follow the screen direction), Tab and Shift+Tab, Home, End, 1–5 select and press, Enter or Space press. Esc cancels a pending confirmation, then closes.
- The command runs 180 ms after the island closes: `omarchy-system-lock`, `systemctl suspend`, `omarchy-system logout`, `omarchy-system reboot`, or `omarchy-system shutdown`.

## Mouse and keyboard

- The wheel switches screens only while a screen is open, on the band across the screen's width in the top 24 px of the monitor: the gap above the screen and its top padding. Each notch (120 units) moves one screen, in the order above. Down goes forward, up goes back. A partial scroll resets after 200 ms without wheel events, or when the direction flips, so slow trackpad drift never switches. Right-to-left languages do not flip it. At rest, on levels 1 and 2, on the picker, on a notice, or on an OSD, the wheel does nothing. Lists, carousels, and sliders keep their own wheel.
- The pointer on the pill shows the icons. A click on the clock, a right click, or a long press (0.5 s) shows them too. On the picker it closes it. On a live notice it dismisses it.
- A click outside an open screen closes it.
- Keys work only while a screen is open. The hover levels, the picker, and the notices never take the keyboard.
- Ctrl+Tab and Ctrl+Shift+Tab walk the screens. Alt+1–6 open them directly: Apps, Themes, Wallpapers, Media, Control Center, Power.
- Alt+← and the mouse's back button go back (see Navigation).
- Esc first goes to the screen (it clears a search, closes a popover or page, cancels a confirmation), then closes the island.
- Any key turns keyboard mode on. Moving the pointer more than 8 px turns it off.

### Omarchy keys

Omarchy's own panel keys land on Ilha's screens. The same key again closes what it opened.

| Key | Omarchy name | In Ilha |
|---|---|---|
| Super+Ctrl+A | Audio | Control Center › Sound |
| Super+Ctrl+B | Bluetooth | Control Center › Bluetooth |
| Super+Ctrl+N | Network | Control Center › Wi-Fi |
| Super+Ctrl+D | Display | Control Center › Display |
| Super+Ctrl+P | Power | Power |
| Super+Ctrl+Alt+D | Calendar | Level 2, on the focused monitor |
| Super+Ctrl+Alt+E | World clock | Control Center |
| Super+Ctrl+1, 2, 3, 4 | Bar panel 1–4 | Control Center › Sound, Control Center › Wi-Fi, Power, Media |
| Super+Ctrl+5 to 9 | Bar panel 5–9 | Nothing |
| Super+Ctrl+T, Super+Shift+Ctrl+Space | Theme menu | Themes |
| Super+Ctrl+W, Super+Ctrl+Space | Background switcher | Wallpapers |

### Theme and wallpaper keys

Ilha takes over Omarchy's two image pickers. No key and no menu entry is rebound: the same keys and entries open Ilha's screens.

- **Wallpapers.** Super+Ctrl+W, Super+Ctrl+Space, and Menu › Appearance › Background run Omarchy's background switcher, which asks the shell's `image-selector` target for a picker. Ilha answers that target ahead of Omarchy's picker. When every image in the request is in the theme's backgrounds (`~/.local/state/omarchy/current/theme/backgrounds/`) or in `~/.config/omarchy/backgrounds/`, the Wallpapers screen opens with the request's images. Enter writes the choice to the reply file the script waits on, and Omarchy's script applies it. Esc, a click outside, or another screen hands back an empty choice, so the script never waits forever.
- **Themes.** Super+Ctrl+T, Super+Shift+Ctrl+Space, and Menu › Appearance › Theme open Omarchy's theme picker. When that picker opens without a request Ilha passed on, Ilha hides it and opens the Themes screen. Omarchy's picker maps transparent at first, so it is hidden before it shows a frame.
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

- **Colors.** Ilha reads the Omarchy theme's background, text, accent, and urgent colors. The island is always dark: its surface is the darker of background and text, at 10 % over black. Cards and rows are lighter steps of the text color. The accent is moved toward the text color until it reads on the surface (3:1 for fills, 4.5:1 for text), and so is the urgent color. A theme change cross-fades in 150 ms. Ilha writes no palette.
- **Shape.** A capsule with a 1 px rim and a soft shadow. When Omarchy's glassy toggles are on (`~/.local/state/omarchy/toggles/hypr/bar-glassy.lua` or `window-glassy.lua`), the shadow is lighter. The island stays opaque.
- **Position.** Always at the top. Omarchy's bar position and bar background settings do not apply to Ilha.
- **Fonts.** Text uses the bundled Inter subset; other scripts fall back to the system fonts. Icons use the bundled Material Symbols Rounded subset.
- **Motion.** The shape moves on springs and the content fades in at its final layout. With Hyprland's animations off (`omarchy toggle animations`, or Game Mode), every change is instant.

## Settings

Two switches, in Control Center › Ilha settings (the first button in the Notifications card's shortcut row), or with `omarchy-shell ilha open settings`:

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
omarchy-shell ilha picker                  # toggles the screen picker on the focused monitor
omarchy-shell ilha hover <0|1|2>           # holds the icons (1) or level 2 (2) on the focused monitor; 0 releases it
omarchy-shell ilha peek <key>              # shows a live notice now
omarchy-shell ilha osd '<json>'            # shows an OSD in the pill
omarchy-shell ilha closeOsd                # hides the pill's OSD
omarchy-shell ilha setting <key> <value>   # focusedOnly | livePeek | reserveTop; true | false | toggle
omarchy-shell ilha state                   # prints the state as JSON
```

- Screens: `launcher`, `control`, `media`, `themes`, `wallpapers`, `power`. Control Center parts: `sound`, `display`, `wifi`, `bluetooth`, `settings`. Aliases: `apps` (launcher), `cc` and `controls` (control), `theme` (themes), `wallpaper` and `background` (wallpapers), `last` (the last screen opened).
- `run` keys: a letter or digit, `enter`, `space`, `esc`, `tab`, `up`, `down`, `left`, `right`, `pgup`, `pgdn`, `home`, `end`, `delete`, with an optional `shift+`, `ctrl+`, or `alt+` in front. The key goes once the screen is ready (3 s at most).
- `peek` keys: `recording`, `reminder`, `update`, `dnd`, `nightlight`, `stayAwake`, `urgent`. It shows even when that state is off, but not with Live notice off. `urgent` uses the newest on-screen notification.
- Answers: `open` and `toggle` print `ok` or `unknown`; `run` prints `ok`, `unknown`, or `invalid-key`; `picker` prints `open`, `closed`, or `busy`; `peek` prints `shown`, `queued`, `off`, `busy`, `quiet`, `unknown`, or `empty`; `osd` prints `ok`, `invalid`, or `off`; `setting` prints `ok`, `unknown`, or `invalid`.
- `state` includes the open screen, each monitor's face, the OSD, the live notice, the picker, the settings (with `canPersist`), the takeovers, and both versions.

Ilha also answers the targets the default bar registered, so Omarchy's own scripts keep working:

```bash
omarchy-shell omarchy.clock <open|show|close|hide|toggle|refresh>   # open and show: level 2; close and hide: back
omarchy-shell omarchy.bar syncHidden
omarchy-shell omarchy.indicators refresh
omarchy-shell omarchy.system-update <refresh|clear>
omarchy-shell omarchy.workspaces refresh
```

The `osd` target stays Omarchy's.

## Languages

Ilha ships a catalog in `i18n/` for each of the 50 languages Omarchy offers. It follows Setup › Language live, without a shell restart. Numbers use the language's digits: the clock, the workspaces, the recording time, and the percentages. The level 2 date uses each language's own pattern and its day and month names. A missing string falls back to English.

Right-to-left languages (Arabic, Persian, Hebrew, Urdu) mirror the whole island. The mark sits right of the clock, the picker starts with Apps on the right, and the notice icon is on the right. Left and Right follow the screen direction. The clock, the recording time, the network bars, the battery, and the Media seek bar, times, and transport buttons stay left to right on purpose.

## Dependencies

Omarchy, with its shell. No extra packages. The fonts ship in `fonts/`. Buttons call the Omarchy commands and services they name (`omarchy-theme-set`, `omarchy-theme-bg-set`, `omarchy-system`, `omarchy-brightness-display`, `omarchy-bluetooth-power`, `omarchy-audio-output-set-default`, and so on). Ilha runs Omarchy's own update check (`omarchy-update-available`) 5 s after it starts, every 6 hours, and when Omarchy asks.

Ilha draws no other bar widget and no tray. A key for a panel Ilha has no screen for does nothing. Switch back with `omarchy bar use omarchy.bar` when you need them.

## Files

| Path | Role |
|---|---|
| `manifest.json` | Plugin id, version 2.0.0, and the `bar` entry `ui/Ilha.qml` |
| `ui/Ilha.qml` | Entry point: host contract, navigation, services, settings, IPC |
| `ui/IslandWindow.qml` | One window per monitor: the shape, the faces, the input mask, the keys |
| `ui/HoverBar.qml`, `RestMark.qml`, `ScreenPicker.qml`, `ScreenNav.qml`, `LineHint.qml`, `HeroClock.qml`, `Workspaces.qml` | Levels 1 and 2, the rest mark, the picker, the navigation under a screen, the line hint, the clock, the workspaces |
| `ui/PeekBridge.qml`, `PeekFace.qml` | Live notice |
| `ui/OsdBridge.qml`, `OsdFace.qml` | OSD in the pill, resolution prompt, restart notice |
| `ui/PickerBridge.qml` | Theme and wallpaper takeovers |
| `ui/ScreenStack.qml` | Loads and switches the screens |
| `ui/ControlCenter.qml`, `WifiCard.qml`, `BluetoothCard.qml`, `SoundPage.qml`, `DisplayPage.qml`, `IlhaPage.qml`, `NotificationsCard.qml` | Control Center |
| `ui/LauncherScreen.qml`, `MediaScreen.qml`, `ThemeScreen.qml`, `WallpaperScreen.qml`, `PowerScreen.qml` | The other screens |
| `ui/*Svc.qml`, `StateStore.qml`, `AppSearch.js` | Status, audio, network, monitors, media, apps, themes, settings (`PrefsSvc.qml`), own state |
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
- The tray, or another bar widget, is missing. Ilha draws none. Use `omarchy bar use omarchy.bar` when you need them.
- `omarchy plugin update` refuses to pull. The checkout has local edits. Commit or stash them in `~/.config/omarchy/plugins/esegnorelli.ilha`.

## License

[MIT](LICENSE). Copyright 2026 Evandro Segnorelli.
