# Ilha

Floating island bar for [Omarchy](https://omarchy.org). At rest it is a clock. Under the pointer it becomes one tight status line. Panels open one at a time, in the same pill.

Documentação em português: [LEIA-ME.md](LEIA-ME.md).

Ilha replaces the bar (`kinds: ["bar"]`, id `esegnorelli.ilha`). It is not a widget inside the default bar. Colors, corners, glass, and the font follow the Omarchy theme, and a click in Estilo paints the pill before the rest of the desktop finishes switching.

## Install

```bash
omarchy plugin add https://github.com/Esegnorelli/omarchy-ilha.git --enable
```

`--enable` switches the bar to Ilha. Omarchy asks you to confirm, because a plugin runs inside the long-lived shell. There is no extra package and no sudo: everything Ilha uses ships with Omarchy. `omarchy plugin add` only clones the repo and validates `manifest.json`, so Ilha finishes its own setup the first time it loads (`setup/setup.sh`, safe to run again). It writes `~/.local/state/omarchy/toggles/hypr/zz-ilha.lua`, which Omarchy loads at the end of the Hyprland config and which runs `hypr/init.lua` from the plugin: window transparency and the `Super+Z` binding. It checks the commands the panels call and reloads Hyprland only when something changed. Nothing in `~/.config/hypr` is edited.

If the bar was hidden, show it again with `omarchy toggle bar`.

## Update

```bash
omarchy plugin update esegnorelli.ilha
```

With no id, `omarchy plugin update` updates every git-managed plugin. It shows the diff and refuses to fast-forward over local edits.

## Remove

Switch back to the default bar and keep Ilha installed:

```bash
omarchy bar use omarchy.bar
```

`uninstall.sh` does the same thing and also undoes the setup (`setup/setup.sh remove`). Run it before `omarchy plugin remove`; if you forget, the loader left behind does nothing once the plugin folder is gone.

Delete the checkout (the GitHub repo stays):

```bash
omarchy plugin remove esegnorelli.ilha
```

If Ilha fails to load, Omarchy falls back to `omarchy.bar` on its own.

## What you see

The pill floats 10 px from the top edge, on the overlay layer, and does not reserve screen space. Windows do not move when it grows. It stays above fullscreen.

| State | What is on the pill |
|---|---|
| Rest | The clock, in a capsule. If something is on (recording, Do not disturb, stay awake, a reminder, …) a single mark sits with the time. |
| Hover | One line: workspaces 1–5, the time, the appearance palette, and at most two live indicators. The pill width follows that line. |
| Panel | The same line stays on top. One panel opens under it. |

Move the pointer into the top-center strip (600 px) or onto the pill to open the line. Leave, and it returns to the clock. Nothing rotates on its own.

| Place | Content | Click |
|---|---|---|
| Left | Workspaces 1–5 on this monitor. The active number uses the theme accent and shows the layout: a square for tiling, a circle for scrolling, a triangle for floating. Occupied numbers are bright. Empty numbers are quiet. | Click the active number to cycle those three layouts. Click another number to focus that workspace |
| Center | Time | Open Tempo |
| Appearance | Palette, in the accent color | Open Estilo |
| Right | Up to two live indicators, icon only | Turn it off, or open its panel |

Apps, Controle, Captura, Ferramentas, and Energia are not drawn on the pill. Each one opens in the pill, one at a time. When more than two indicators are active, rest shows a dot and hover keeps the first two icons.

## Panels

Every panel uses the same 4-column grid, the same width, and a fixed height, so the pill does not jump when the contents change.

| Key | Panel | What is inside |
|---|---|---|
| 0 | Tempo | The month. Page Up and Page Down change it. Home returns to today |
| 1 | Apps | App search. Arrows, Enter. Esc clears, then closes |
| 2 | Controle | Microphone, Do not disturb, night light, stay awake, animations, game mode, Wi-Fi and Bluetooth when present, volume, the current network, speed test |
| 3 | Captura | Region, screen, window, or scrolling screenshot. Recording with system audio and microphone. OCR, QR code, color picker |
| 4 | Estilo | Themes are a compact strip: search, five cards, each with that theme's image and its palette, the middle one outlined. Arrows choose. Enter, or a click on the middle card, applies. Backgrounds are a carousel of that theme: search, five thumbnails, the chosen one raised and the neighbors lower and quieter. The name sits on the thumbnail. The background in use stays bright. Enter, or a click on the raised thumbnail, applies. A click on a neighbor only selects it. All themes hides the other controls. Esc clears the search, then returns. Next background, pick, colors from the wallpaper, corners, transparency, font |
| 5 | Ferramentas | Clipboard, emoji, shortcuts, the Omarchy menu, notifications, about, updates, and Plugins |
| 6 | Energia | Lock, suspend, hibernate. Log out, reboot, and power off ask for a second press |
| — | Plugins | Search the shell plugins. Enter turns one on or off. Switching the bar asks for a second press. The wheel reaches it after Energia |
| — | OSD | Volume, brightness, and other notices sent to the island |
| — | Notification | Click the bell on the status line. The newest one opens inside the pill: icon, app, and summary on one line. It does not appear on its own. Tap the pill to return to the clock. Omarchy's cards stay, because they carry the actions |

Omarchy panel shortcuts land on the matching state: audio, Bluetooth, and network open Controle, the clock opens Tempo, power opens Energia.

## Mouse and keyboard

- Scroll on the status line changes the panel. The first notch while the line is only a line opens Tempo. Later notches walk Tempo, Apps, Controle, Captura, Estilo, Ferramentas, Energia, Plugins. Scroll down goes forward. Scroll up goes back. The line stays at the top of an open panel so the wheel still hits it.
- Lists and sliders keep their own wheel. Volume lives in Controle.
- `0`–`6` or `Alt`+digit select the same panels. `Ctrl+Tab` and `Ctrl+Shift+Tab` walk them.
- Arrow keys move, Enter and Space activate.
- Letters follow the grid: `Q W E R`, `A S D F`, `Z X C V`. The letter is drawn on the control. The same letters work on a QWERTY or ABNT2 keyboard.
- In Estilo, `[` and `]` only highlight a font. Enter or a click applies it. Icon fonts stay out of the list.
- Esc cancels a confirmation, then clears search, then closes.
- A click outside closes the panel.
- Confirmations (reboot, power off, log out) turn the control red and read "Confirm?" for 4 seconds. A second press sooner than 350 ms is ignored.

`Super+Z` opens and closes the last panel. Ilha registers it itself (`hypr/bindings.lua`); it is free in the default Omarchy bindings (`Super+Ctrl+Z` is zoom). If you already use `Super+Z`, setup leaves it alone. To pick another key, add it to `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + ALT + Z", "Ilha", "omarchy-shell ilha toggle last")
```

## Appearance

Estilo applies to the pill at the click. The system command still runs after that.

- **Theme.** The pill reads that theme's `colors.toml` (your overlay, then the stock theme) and recolors immediately. `omarchy theme set` is debounced by 280 ms, so a fast series of clicks does not stack theme switches. Wallpaper, terminals, and borders follow the command. If the system theme never arrives, the pill returns to the theme that is actually current.
- **Corners.** Rounded keeps the capsule (a panel caps the radius at 28) and rounds the windows with it. Sharp squares the shell, the inner controls, and the windows, including terminals. Theme uses the current Hyprland radius. A no-gap desktop does not flatten a rounded choice. `omarchy hyprland corners`.
- **Glass.** Opaque is solid. Glassy paints the theme at 0.4 on the capsule and 0.58 on a panel, over the blur Omarchy already applies to the `omarchy-bar` namespace. Transparent is 0.34 and 0.42, just above the point where that blur cuts a hole. The rim light follows. Buttons, cards, chips, and the calendar use that same alpha, so a selected control does not turn into a solid plate. A floating workspace forces windows opaque; `hypr/transparency.lua`, loaded through the setup above, applies the choice again to every window after the floating setup, and does nothing while another bar is active. Glassy keeps terminals at full window opacity so their own glass background leaves the text sharp, and other windows use 0.75. `omarchy hyprland window transparency`.
- **Font.** The clicked family is used on the pill at once. `omarchy font set` still restarts the shell when it rewrites fontconfig.
- **Motion.** The pill sizes with a critically damped spring, and fades are short. `omarchy toggle animations` off makes every change instant.
- **Color source.** The pill uses `Commons.Color` only. There is no private palette.

Game mode, in Controle, is a separate action. Turning it on can disable animations, remove gaps, and set windows opaque, and turning it off puts back what it changed.

## IPC

```bash
omarchy-shell ilha open <launcher|control|capture|style|tools|plugins|calendar|power|last>
omarchy-shell ilha toggle <view|last>
omarchy-shell ilha run <view> <key>     # example: run calendar pgdn, run control q
omarchy-shell ilha close
omarchy-shell ilha osd '{"icon":"volume-high","value":"55","progressText":"55%","max":"100"}'
omarchy-shell ilha closeOsd
omarchy-shell ilha state
```

`open` and `toggle` both open that panel, and close it when it is already open. `state` prints JSON (`view`, `lastView`, `keyboard`, `osd`, `hidden`, `screen`).

## Languages

Strings live in `i18n/en.json` and `i18n/pt-BR.json` and follow Setup → Language without a shell restart. A missing string falls back to English.

## Dependencies

Omarchy, with its shell. No extra packages. Ilha does not install a blur plugin and does not fetch anything on its own. Buttons call the Omarchy commands they name (`omarchy theme`, `omarchy font`, `omarchy capture`, `omarchy hyprland corners`, `omarchy hyprland window transparency`, and the matching panel services).

A replacement bar can show installed widgets, but a third-party widget that needs another plugin's live service can be limited here. Switch back with `omarchy bar use omarchy.bar` when that widget needs the default bar.

## Files

| File | Role |
|---|---|
| `manifest.json` | Plugin id, version, and the `bar` entry |
| `Island.qml` | One window per monitor, the pill, panels, and IPC |
| `Strip.qml` | The status line: workspaces, clock, palette, indicators |
| `Indicators.qml` | Live status marks |
| `ContinuousRect.qml` | Capsule and card |
| `Metrics.qml` | Grid sizes, radii, durations |
| `Tile.qml`, `TileArm.js`, `KeyBadge.qml` | Grid control and its letter |
| `GridRow.qml`, `PanelGrid.qml`, `LabeledRow.qml`, `InfoRow.qml`, `PanelFooter.qml` | Rows, keyboard navigation, footer |
| `IconButton.qml`, `Icon.qml` | Button and Material Symbols icon |
| `Launcher.qml`, `ControlPanel.qml`, `CaptureMenu.qml`, `StyleMenu.qml`, `ToolsMenu.qml`, `PluginsMenu.qml`, `CalendarView.qml`, `PowerMenu.qml`, `OsdView.qml` | Panels |
| `i18n/` | English and Brazilian Portuguese |
| `setup/setup.sh` | Setup Ilha runs when it loads; `remove` undoes it |
| `hypr/` | Hyprland side: `init.lua` (entry), `transparency.lua`, `bindings.lua` |
| `install.sh`, `uninstall.sh` | Optional helpers. Omarchy does not run them |

A panel receives `active`, colors, `shell`, and `metrics`, and reports size with `implicitWidth` and `implicitHeight`. It can implement `closeRequested()`, `navigate(target)`, `handleKey`, `handleEscape`, and `focusFirst`.

## Troubleshooting

- The new checkout did not become the bar. Run `omarchy restart shell`, then `omarchy plugin enable esegnorelli.ilha`.
- The shell logged `bar option esegnorelli.ilha failed to load, falling back to omarchy.bar`. Run `omarchy plugin validate ~/.config/omarchy/plugins/esegnorelli.ilha` and read `journalctl --user -t omarchy-shell`.
- The pill color waits on the wallpaper. It should not. Estilo reads `colors.toml` before `omarchy theme set`. Wallpaper and terminals still follow the command.
- `omarchy plugin update` refuses to pull. The checkout has local edits. Commit or stash them in `~/.config/omarchy/plugins/esegnorelli.ilha`.

## License

[MIT](LICENSE). Copyright 2026 Evandro Segnorelli.
