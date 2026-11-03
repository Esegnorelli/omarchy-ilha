# Ilha

Floating island bar for [Omarchy](https://omarchy.org). At rest it is a clock. Under the pointer it becomes one tight status line. Panels open one at a time, in the same pill.

Documentação em português: [LEIA-ME.md](LEIA-ME.md).

Ilha replaces the bar (`kinds: ["bar"]`, id `esegnorelli.ilha`). It is not a widget inside the default bar. Colors, corners, glass, and the font follow the Omarchy theme, and a click in Estilo paints the pill before the rest of the desktop finishes switching.

## Install

```bash
omarchy plugin add https://github.com/Esegnorelli/omarchy-ilha.git --enable
```

`--enable` switches the bar to Ilha. Omarchy asks you to confirm, because a plugin runs inside the long-lived shell. There is no extra package, no sudo, and no setup step: everything Ilha uses ships with Omarchy. `omarchy plugin add` only clones the repo and validates `manifest.json`, and that is all Ilha needs. Outside its own folder it writes only the three Estilo switches (see Appearance), inside Omarchy's own `~/.config/omarchy/shell.json`, through the host's plugin API (`mutateShellConfig`).

If the bar was hidden, show it again with `omarchy toggle bar`.

## Update

```bash
omarchy plugin update esegnorelli.ilha
```

With no id, `omarchy plugin update` updates every git-managed plugin. It shows the diff and refuses to fast-forward over local edits.

Omarchy keeps the previous Ilha in its QML cache, so after an update or a reinstall run `omarchy restart shell` to see the new version.

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

If Ilha fails to load, Omarchy falls back to `omarchy.bar` on its own.

## What you see

The pill floats 12 px from the top edge, on the overlay layer, and does not reserve screen space. Windows do not move when it grows. It stays above fullscreen. The size it publishes to the shell (`barSize`) is 50.

| State | What is on the pill |
|---|---|
| Rest | The clock, in a true capsule of 108 × 38. When something is on, a mark sits beside the time and the capsule grows to fit it: the icon of the highest-priority active indicator, in its own color, in this order: recording, reminder, update, Do not disturb, night light, stay awake. While recording, the elapsed time follows the icon and counts seconds (only then; the clock itself stays in minutes). While music plays, three small accent bars sit beside the icon, or alone when nothing else is on. Notifications on screen do not count here; they live on the bell. |
| Hover | Level 1: the clock between two groups, the workspaces as numbered capsules on one side (the active one wider, in the accent, workspace 10 shown as 0), network bars, battery, and up to two status marks on the other. While music plays, a now-playing element (the cover, or a note, and the short title) sits before the workspaces. |
| Hover, held | Level 2, after the pointer rests still on the pill for 1.6 s: the pill widens to three columns, at most 640 × 64. Left, the focused app over the workspaces. Centre, a big clock with the date beside it. Right, the notification status (the count, or "All caught up", and the bell) over network, battery, and the status marks. With a track loaded (playing or paused), the focused-app line becomes "title — artist" with a small play/pause button. |
| Picker | The six panel icons in one row of 236 × 46, each with its digit underneath. See below. |
| Live notice | One short line that grows out of the pill and returns: "Recording 0:42", "Reminder in 15 min", or an urgent notification. See below. |
| Panel | The same object morphs into one panel. There is no header line on top of it. |

There are two hover levels. A 3 px invisible strip across the central 600 px of the top edge, the 12 px gap under it, or the pill itself opens level 1, the line. Level 2 opens only when the pointer rests still on the pill itself: 1.6 s without moving more than 4 px (moving further restarts the count). The strip and the gap never open level 2, so passing over the top edge does not unfold the pill, and Estilo can turn level 2 off. Leave, and it returns to the clock. Nothing rotates on its own. A click on the now-playing element, at either level, opens Media. With no player, none of the music parts appear. The first time the pointer opens the line in a session, a short hint shows under the pill for 3 s: "0 time · 1 apps · scroll switches".

At rest, a tap on the mark opens the panel that owns it: recording opens Captura, a reminder Tempo, an update Ferramentas, and Do not disturb, night light, and stay awake open Controle. The music bars open Media, and a tap elsewhere on the capsule opens Tempo. With the pointer on the mark the line does not open, so the tap lands on the mark, and its short name shows in a tooltip.

| Place | Content | Click |
|---|---|---|
| Left | Workspaces for this monitor as numbered capsules: the first five of the monitor's block, plus any higher one that exists. The active one is wider, filled with the theme accent. Occupied ones are brighter. Empty ones are quiet. | Click a capsule to focus that workspace. Click the active one to cycle its layout (Tiling, Scrolling, Floating); its name shows in a tooltip |
| Center | Time | Open Tempo |
| Right | Network bars and battery, the battery filled in the accent, then up to two status marks in the same order as the rest mark, notifications last | Network or battery opens Controle. A mark acts on its own: recording stops; Do not disturb, night light, and stay awake turn off; a reminder opens Tempo; an update opens Ferramentas; the bell opens the newest notification |

Apps, Controle, Captura, Estilo, Ferramentas, and Energia are not drawn on the line. They appear together only in the picker. Each panel opens in the pill, one at a time.

**Picker.** Long press or right click on the capsule (or on the line) shows the six panel icons: Apps, Controle, Captura, Estilo, Ferramentas, Energia, each with its digit underneath. Resting on an icon shows "name · digit"; a tap opens that panel. The picker goes away on its own: 2.6 s without the pointer on it, or 0.7 s after the pointer has been on it and left. Another right click on the same monitor hides it. It does not open while a panel is open.

**Live notice.** When an indicator turns on, the pill grows into one short line, in the notification format with the indicator's icon and color: "Recording 0:42" (the time keeps counting), "Reminder in 15 min", "Update available", "Do not disturb on", "Night light on", "Stay awake on". It stays 2.6 s, and only while the indicator is still on, then returns to the clock. An urgent notification shows the same way, as one line (icon, app, summary), for 4 s. Resting the pointer on the notice pauses the count; after the pointer leaves, it stays 1 s more. A tap opens the owning panel, or, for a notification, opens it in the pill as the bell does. With a panel open, an indicator does not raise a notice, and indicators already on when Ilha loads do not raise one either. With Live notice off in Estilo, a new indicator shows the line for 2.6 s instead, and urgent notifications do not appear on their own.

## Panels

Every panel uses the same 4-column grid and a fixed height per page, so the pill does not jump when the contents change. The width hugs the panel: 564 for most, 498 for Controle, 468 for Media. With the mouse a panel shows only its controls; the key letters and the footer line (status on the left, hints on the right) appear in keyboard mode only.

| Key | Panel | What is inside |
|---|---|---|
| 0 | Tempo | The month. Page Up and Page Down change it. Home returns to today |
| 1 | Apps | App search. Arrows, Enter. Esc clears, then closes |
| 2 | Controle | Three rows of 56 px, each two capsule tiles (icon circle, name, state) and one round tile (icon only; its name shows in a small tooltip on hover, or in the footer in keyboard mode). `Q` Wi-Fi, `W` Do not disturb, `E` microphone; `A` Bluetooth, `S` game mode, `D` night light; `Z` stay awake, `X` animations, `C` speed test. Without Wi-Fi the first slot becomes Screensaver; without Bluetooth, Suspend. On lights only the icon circle in the accent; Wi-Fi or Bluetooth on but not connected shows a faint accent veil instead. Below the tiles, the Sound card: a volume bar (`-`/`=` ±5 %, `M` or a tap on the icon mutes) whose chevron, or Enter, opens the Sound subpage (outputs, input); a round Back button or Esc returns. Last, the network row: interface and type, IPv4 address, and a Wi-Fi QR button (`V`) when on Wi-Fi. The speed test and the QR close the island and open Omarchy's own panels |
| 3 | Captura | Region, screen, window, or scrolling screenshot, and Smart at `V`. Recording with system audio and microphone. OCR, QR code, color picker |
| 4 | Estilo | Three pages under tabs at the top: Theme, Background, and Windows and font. `Tab` and `Shift+Tab` switch pages; the width stays put and only the height changes. **Theme**: a carousel of 140 × 80 swatches, each the theme's own background with its palette as dots and its name in its text color; the cursor card sits in the centre, outlined, and the neighbors fade toward the edges. A small accent dot marks the theme in use. Arrows choose; Enter, or a click on the centre card, applies; a click on a neighbor only selects it. Under the strip, the current theme and `n/N`. The grid button in the header, or `R`, opens All themes (a 4-column grid). **Background**: a carousel of that theme's wallpapers, the chosen one 160 × 90 in the centre with an accent outline, the neighbors smaller and quieter; the wallpaper in use keeps an accent dot. Under it, the file name and `n/N`, then three compact buttons: Next wallpaper, Pick wallpaper, and From wallpaper colors (`Q W E`). The header shows the theme the wallpapers belong to. **Windows and font**: Corners (From theme, Sharp, Rounded; `W E R`), Transparency (Opaque, Transparent, Glass; `S D F`), Font, and, under Island, three switches (`Z X C`): Level 2 on rest, Focused monitor only, and Live notice (see Appearance). On Theme and Background, `/` starts a search that takes the place of the tabs; the shortcut letters and digits keep working until you type. Esc clears the search, closes All themes, returns to the Theme page, then closes |
| 5 | Ferramentas | Clipboard, emoji, shortcuts, the Omarchy menu, notifications, about, updates, and Plugins. The update check runs at most every 10 minutes and gives up after 30 seconds |
| 6 | Energia | A row of rounded square buttons, icon and label: lock, suspend, hibernate. Log out, reboot, and power off ask for a second press |
| — | Plugins | Search the shell plugins. Enter turns one on or off. Switching the bar asks for a second press. The wheel reaches it after Energia |
| — | Media | A compact mini player, 440 × 98 inside a 468 × 126 island, for the active MPRIS player (Omarchy's media service when present). Top row: a 64 px cover, title over "artist · album", and previous, play/pause, next. Bottom row: elapsed time, progress bar, total time. Click or drag the bar to seek when the player allows. Shuffle and repeat (off, playlist, track) sit at the ends of the bar only when the player supports them. Chips to switch players appear under the artist line when there is more than one. Keys: Space or `K` play/pause, `←`/`J` previous, `→`/`L` next, `,` and `.` seek 10 s, `S` shuffle, `R` repeat, `P` next player. Nothing playing shows an empty state at the same height |
| — | OSD | Volume, brightness, and other notices sent to the island |
| — | Notification | Click the bell on the status line (a status mark on level 1, the notification status on level 2). The newest one opens inside the pill: icon, app, and summary on one line. A regular notification does not appear on its own; an urgent one arrives as a live notice, and a tap on it opens this same line. Tap the pill to return to the clock. Omarchy's cards stay, because they carry the actions |

Omarchy panel shortcuts land on the matching state: audio, Bluetooth, and network open Controle, the clock opens Tempo, power opens Energia, media opens Media.

## Mouse and keyboard

- The wheel switches panels only while a panel is open, on its top edge (the 14 px padding, full width). On the line and at rest it does nothing. Each notch (120 units) moves one panel: Tempo, Apps, Controle, Captura, Estilo, Ferramentas, Energia, Plugins, and Media when a track is loaded. Scroll down goes forward. Scroll up goes back. A partial scroll resets after 200 ms without wheel events, or when the direction flips, so slow trackpad drift never switches.
- Long press or right click on the capsule shows the picker; a tap on an icon opens that panel.
- Lists and sliders keep their own wheel. Volume lives in Controle.
- `0`–`6` or `Alt`+digit select the same panels. `Ctrl+Tab` and `Ctrl+Shift+Tab` walk them, Media included only when a track is loaded.
- Arrow keys move, Enter and Space activate.
- Letters follow the grid: `Q W E R`, `A S D F`, `Z X C V`. The letter shows on the control in keyboard mode only. The footer line with status and hints also appears only in keyboard mode; with the mouse a panel ends with the same padding as its top. The focus outline appears only after you navigate with the keyboard. The same letters work on a QWERTY or ABNT2 keyboard.
- In Estilo, `[` and `]` only highlight a font. Enter or a click applies it. Icon fonts stay out of the list.
- Esc cancels a confirmation, then clears search, then closes.
- A click outside closes the panel.
- Confirmations (reboot, power off, log out) turn the control red and read "Confirm?" for 4 seconds. A second press sooner than 350 ms is ignored.

Optional binding, in `~/.config/hypr/bindings.lua`. `Super+Z` is free in the default Omarchy bindings. `Super+Ctrl+Z` is zoom, so leave that one alone.

```lua
o.bind("SUPER + Z", "Ilha", "omarchy-shell ilha toggle last")
```

## Appearance

Estilo applies to the pill at the click. The system command still runs after that.

- **Theme.** The pill reads that theme's `colors.toml` (your overlay, then the stock theme) and recolors immediately. `omarchy theme set` is debounced by 280 ms, so a fast series of clicks does not stack theme switches. Wallpaper, terminals, and borders follow the command. If the system theme never arrives, the pill returns to the theme that is actually current.
- **Corners.** Rounded uses capsules plus a panel corner of 32, and rounds the windows with it. Sharp squares the shell, the inner controls, and the windows, including terminals. Theme follows the current Hyprland rounding; a theme with rounding 0 falls back to the rounded look instead of squaring the island. A no-gap desktop does not flatten a rounded choice. `omarchy hyprland corners`.
- **Glass.** The island surface is the theme background taken almost to black (on a light theme, one step toward the text color), so the pill keeps its shape over a terminal in the same theme. On a dark theme the surface is the theme background at 28 % (Tokyo Night gives `#07080b`); on a light theme it is the background moved 6 % toward the text color. Opaque is solid (alpha 1). Glass paints that surface at 0.94 on the capsule and 0.92 on a panel, over the blur Omarchy already applies to the `omarchy-bar` namespace. Transparent is 0.84 and 0.82. Opaque and Glass have no rim on a dark theme; Transparent, and every light theme, keep a 1 px rim in the text color at low alpha so the edge does not vanish. There is no shadow. Buttons, cards, chips, and the calendar use the panel alpha, so a selected control does not turn into a solid plate. The exception is the small accent marks (active icon circles, slider fill, today, the active workspace, the battery): they stay solid accent even in glass. The same choice sets window opacity through Omarchy itself; Ilha adds no window rules. `omarchy hyprland window transparency`.
- **Font.** The clicked family is used on the pill at once. `omarchy font set` still restarts the shell when it rewrites fontconfig.
- **Motion.** The pill morphs in a fixed 200 ms when it grows and 160 ms when it shrinks, with a decelerating curve, and the content crossfades. Moving between panels never closes and reopens the pill. `omarchy toggle animations` off makes every change instant.
- **Color source.** The pill uses `Commons.Color` only. There is no private palette.
- **Island switches.** Estilo › Windows and font › Island holds three switches. Level 2 on rest (`level2Dwell`, on by default) lets a still pointer on the pill open level 2; off, the line stays at level 1. Focused monitor only (`focusedOnly`, off) draws the capsule only on Hyprland's focused monitor; another monitor shows the pill only while it is showing something (a panel, the OSD, a notification, a live notice, or the picker). Live notice (`livePeek`, on) turns the live notice on. They are stored in `~/.config/omarchy/shell.json` under `bar.ilha`, through the Omarchy plugin API (`mutateShellConfig`), which writes the file atomically. Only the key that changed is written. The pill reads them live, so a hand edit of `shell.json` counts too, and `omarchy bar reset` puts them back to the defaults. Without the host, or if the write is refused, a choice lasts only until the shell restarts.

```json
"bar": { "ilha": { "level2Dwell": true, "focusedOnly": false, "livePeek": true } }
```

Game mode, in Controle, is a separate action. Turning it on can disable animations, remove gaps, and set windows opaque, and turning it off puts back what it changed.

## IPC

```bash
omarchy-shell ilha open <launcher|control|capture|style|tools|plugins|calendar|power|media|last>
omarchy-shell ilha toggle <view|last>
omarchy-shell ilha run <view> <key>     # example: run calendar pgdn, run control q
omarchy-shell ilha close
omarchy-shell ilha osd '{"icon":"volume-high","value":"55","progressText":"55%","max":"100"}'
omarchy-shell ilha closeOsd
omarchy-shell ilha state
```

`open` and `toggle` both open that panel, and close it when it is already open. `open media` works even with nothing playing. `state` prints JSON (`view`, `lastView`, `keyboard`, `osd`, `hidden`, `screen`).

## Languages

Ilha ships a catalog in `i18n/` for every language Omarchy offers. It follows Setup → Language live, without a shell restart, numbers and the clock included. A missing string falls back to English. Right-to-left languages (Arabic, Persian, Hebrew, Urdu) mirror the whole island. The clock, the recording time, the network bars, the battery, and the Media progress and transport buttons stay left to right on purpose.

## Dependencies

Omarchy, with its shell. No extra packages. Ilha does not install a blur plugin and does not fetch anything on its own. Buttons call the Omarchy commands they name (`omarchy theme`, `omarchy font`, `omarchy capture`, `omarchy hyprland corners`, `omarchy hyprland window transparency`, and the matching panel services).

A replacement bar can show installed widgets, but a third-party widget that needs another plugin's live service can be limited here. Switch back with `omarchy bar use omarchy.bar` when that widget needs the default bar.

## Files

| File | Role |
|---|---|
| `manifest.json` | Plugin id, version, and the `bar` entry |
| `Island.qml` | One window per monitor, the pill, panels, and IPC |
| `Strip.qml` | The status line, levels 1 and 2: workspaces, clock, network, battery, status marks, notification status, now playing; and the picker |
| `Indicators.qml` | Live status: the rest mark, the status marks, the live notice text, the media source |
| `NoticeView.qml` | The one-line notification and live notice |
| `Prefs.qml` | The three Estilo switches, read from and written to `bar.ilha` in `shell.json` |
| `ContinuousRect.qml` | Capsule and card |
| `Metrics.qml` | Grid sizes, radii, durations |
| `Tile.qml`, `TileArm.js`, `KeyBadge.qml` | Grid control and its letter |
| `GridRow.qml`, `PanelGrid.qml`, `LabeledRow.qml`, `InfoRow.qml`, `PanelFooter.qml` | Rows, keyboard navigation, footer |
| `IconButton.qml`, `Icon.qml` | Button and Material Symbols icon |
| `Launcher.qml`, `ControlPanel.qml`, `CaptureMenu.qml`, `StyleMenu.qml`, `ToolsMenu.qml`, `PluginsMenu.qml`, `CalendarView.qml`, `PowerMenu.qml`, `MediaPanel.qml`, `OsdView.qml` | Panels |
| `i18n/` | One catalog per Omarchy language |
| `install.sh`, `uninstall.sh` | Optional helpers. Omarchy does not run them |

A panel receives `active`, colors, `shell`, and `metrics`, and reports size with `implicitWidth` and `implicitHeight`. It can implement `closeRequested()`, `navigate(target)`, `handleKey`, `handleEscape`, and `focusFirst`.

## Troubleshooting

- The new checkout did not become the bar. Run `omarchy restart shell`, then `omarchy plugin enable esegnorelli.ilha`.
- The shell logged `bar option esegnorelli.ilha failed to load, falling back to omarchy.bar`. Run `omarchy plugin validate ~/.config/omarchy/plugins/esegnorelli.ilha` and read `journalctl --user -t omarchy-shell`.
- The pill color waits on the wallpaper. It should not. Estilo reads `colors.toml` before `omarchy theme set`. Wallpaper and terminals still follow the command.
- `omarchy plugin update` refuses to pull. The checkout has local edits. Commit or stash them in `~/.config/omarchy/plugins/esegnorelli.ilha`.

## License

[MIT](LICENSE). Copyright 2026 Evandro Segnorelli.
