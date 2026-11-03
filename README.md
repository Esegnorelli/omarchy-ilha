# Ilha

Floating island bar for [Omarchy](https://omarchy.org). At rest it is a clock. Under the pointer it becomes one tight status line. Panels open one at a time, in the same pill.

Documentação em português: [LEIA-ME.md](LEIA-ME.md).

Ilha replaces the bar (`kinds: ["bar"]`, id `esegnorelli.ilha`). It is not a widget inside the default bar. Colors, corners, glass, and the font follow the Omarchy theme, and a click in Estilo paints the pill before the rest of the desktop finishes switching.

## Install

```bash
omarchy plugin add https://github.com/Esegnorelli/omarchy-ilha.git --enable
```

`--enable` switches the bar to Ilha. Omarchy asks you to confirm, because a plugin runs inside the long-lived shell. There is no extra package, no sudo, and no setup step: everything Ilha uses ships with Omarchy. `omarchy plugin add` only clones the repo and validates `manifest.json`, and that is all Ilha needs. It writes nothing outside its own folder.

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
| Rest | The clock, in a true capsule of 108 × 38. If something is on (recording, Do not disturb, stay awake, a reminder, …) a single mark sits with the time. When music is playing and nothing else is on, the mark is three small accent bars. |
| Hover | Level 1: the clock fixed at the centre, the workspaces as small numbered capsules on one side (the active one filled with the accent), network bars and battery on the other. While music plays, a now-playing element (the cover, or a note, and the short title) sits before the workspaces. |
| Hover, held | Level 2, after resting the pointer for about 1.6 s: the pill widens to three columns, at most 640 × 64. Left, the focused app over the workspaces. Centre, a big clock over the date. Right, the notification status over network and battery. With a track loaded (playing or paused), the focused-app line becomes "title — artist" with a small play/pause button. |
| Panel | The same object morphs into one panel. There is no header line on top of it. |

There are two hover levels. Move the pointer into the top-center strip (600 px) or onto the pill to open level 1, the line. Rest it there for about 1.6 s and level 2 follows, so passing over the top edge does not unfold the pill. Leave, and it returns to the clock. Nothing rotates on its own. A click on the now-playing element, at either level, opens Media. With no player, none of the music parts appear.

| Place | Content | Click |
|---|---|---|
| Left | Workspaces for this monitor, each a small capsule with its number. The active one is filled with the theme accent. Occupied ones are bright. Empty ones are quiet. | Click a capsule to focus that workspace |
| Center | Time | Open Tempo |
| Right | Network bars and battery, the battery filled in the accent | Open Controle |

Apps, Controle, Captura, Estilo, Ferramentas, and Energia are not drawn on the pill. The palette is gone from the line: Estilo stays on key `4` and on the wheel. Each panel opens in the pill, one at a time. When something is on, rest shows a single dot.

## Panels

Every panel uses the same 4-column grid and a fixed height per page, so the pill does not jump when the contents change. The width hugs the panel: 564 for most, 498 for Controle, 468 for Media. With the mouse a panel shows only its controls; the key letters and the footer line (status on the left, hints on the right) appear in keyboard mode only.

| Key | Panel | What is inside |
|---|---|---|
| 0 | Tempo | The month. Page Up and Page Down change it. Home returns to today |
| 1 | Apps | App search. Arrows, Enter. Esc clears, then closes |
| 2 | Controle | Three rows of 56 px, each two capsule tiles (icon circle, name, state) and one round tile (icon only; its name shows in a small tooltip on hover, or in the footer in keyboard mode). `Q` Wi-Fi, `W` Do not disturb, `E` microphone; `A` Bluetooth, `S` game mode, `D` night light; `Z` stay awake, `X` animations, `C` speed test. Without Wi-Fi the first slot becomes Screensaver; without Bluetooth, Suspend. On lights only the icon circle in the accent; Wi-Fi or Bluetooth on but not connected shows a faint accent veil instead. Below the tiles, the Sound card: a volume bar (`-`/`=` ±5 %, `M` or a tap on the icon mutes) whose chevron, or Enter, opens the Sound subpage (outputs, input); a round Back button or Esc returns. Last, the network row: interface and type, IPv4 address, and a Wi-Fi QR button (`V`) when on Wi-Fi. The speed test and the QR close the island and open Omarchy's own panels |
| 3 | Captura | Region, screen, window, or scrolling screenshot, and Smart at `V`. Recording with system audio and microphone. OCR, QR code, color picker |
| 4 | Estilo | Three pages under tabs at the top: Theme, Background, and Windows and font. `Tab` and `Shift+Tab` switch pages; the width stays put and only the height changes. **Theme**: a carousel of 140 × 80 swatches, each the theme's own background with its palette as dots and its name in its text color; the cursor card sits in the centre, outlined, and the neighbors fade toward the edges. A small accent dot marks the theme in use. Arrows choose; Enter, or a click on the centre card, applies; a click on a neighbor only selects it. Under the strip, the current theme and `n/N`. The grid button in the header, or `R`, opens All themes (a 4-column grid). **Background**: a carousel of that theme's wallpapers, the chosen one 160 × 90 in the centre with an accent outline, the neighbors smaller and quieter; the wallpaper in use keeps an accent dot. Under it, the file name and `n/N`, then three compact buttons: Next wallpaper, Pick wallpaper, and From wallpaper colors (`Q W E`). The header shows the theme the wallpapers belong to. **Windows and font**: Corners (From theme, Sharp, Rounded), Transparency (Opaque, Transparent, Glass), and Font. On Theme and Background, `/` starts a search that takes the place of the tabs; the shortcut letters and digits keep working until you type. Esc clears the search, closes All themes, returns to the Theme page, then closes |
| 5 | Ferramentas | Clipboard, emoji, shortcuts, the Omarchy menu, notifications, about, updates, and Plugins. The update check runs at most every 10 minutes and gives up after 30 seconds |
| 6 | Energia | A row of rounded square buttons, icon and label: lock, suspend, hibernate. Log out, reboot, and power off ask for a second press |
| — | Plugins | Search the shell plugins. Enter turns one on or off. Switching the bar asks for a second press. The wheel reaches it after Energia |
| — | Media | A compact mini player, 440 × 98 inside a 468 × 126 island, for the active MPRIS player (Omarchy's media service when present). Top row: a 64 px cover, title over "artist · album", and previous, play/pause, next. Bottom row: elapsed time, progress bar, total time. Click or drag the bar to seek when the player allows. Shuffle and repeat (off, playlist, track) sit at the ends of the bar only when the player supports them. Chips to switch players appear under the artist line when there is more than one. Keys: Space or `K` play/pause, `←`/`J` previous, `→`/`L` next, `,` and `.` seek 10 s, `S` shuffle, `R` repeat, `P` next player. Nothing playing shows an empty state at the same height |
| — | OSD | Volume, brightness, and other notices sent to the island |
| — | Notification | Click the bell on the status line. The newest one opens inside the pill: icon, app, and summary on one line. It does not appear on its own. Tap the pill to return to the clock. Omarchy's cards stay, because they carry the actions |

Omarchy panel shortcuts land on the matching state: audio, Bluetooth, and network open Controle, the clock opens Tempo, power opens Energia, media opens Media.

## Mouse and keyboard

- Scroll on the status line changes the panel. The first notch while the line is only a line opens Tempo. Later notches walk Tempo, Apps, Controle, Captura, Estilo, Ferramentas, Energia, Plugins, and Media when a track is loaded. Scroll down goes forward. Scroll up goes back. An open panel has no line on top, but the wheel on its top edge still cycles panels.
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

Ilha ships a catalog in `i18n/` for every language Omarchy offers. It follows Setup → Language live, without a shell restart, numbers and the clock included. A missing string falls back to English. Right-to-left languages (Arabic, Persian, Hebrew, Urdu) mirror the whole island. The clock, the network bars, the battery, and the Media progress and transport buttons stay left to right on purpose.

## Dependencies

Omarchy, with its shell. No extra packages. Ilha does not install a blur plugin and does not fetch anything on its own. Buttons call the Omarchy commands they name (`omarchy theme`, `omarchy font`, `omarchy capture`, `omarchy hyprland corners`, `omarchy hyprland window transparency`, and the matching panel services).

A replacement bar can show installed widgets, but a third-party widget that needs another plugin's live service can be limited here. Switch back with `omarchy bar use omarchy.bar` when that widget needs the default bar.

## Files

| File | Role |
|---|---|
| `manifest.json` | Plugin id, version, and the `bar` entry |
| `Island.qml` | One window per monitor, the pill, panels, and IPC |
| `Strip.qml` | The status line, levels 1 and 2: workspaces, clock, network, battery, notification status, now playing |
| `Indicators.qml` | Live status marks |
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
