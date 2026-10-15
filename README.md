<p align="center"><img src="Resources/AppIcon.png" width="128" alt="Panespace icon"></p>

# Panespace

An i3-style tiling window manager for macOS. It reads i3's config syntax, so an existing i3 config mostly just works. It needs no SIP changes, no window-server patching and no Dock injection; it runs on the Accessibility permission alone.

- **i3 tree layout.** Windows split horizontally or vertically, plus tabbed and stacking layouts (shown accordion-style, with slivers of the neighbouring windows visible). `split`, `focus parent`/`focus child`, and i3's `move` rules: windows swap, join neighbouring containers, and change the workspace orientation.
- **Menu bar.** A native-looking indicator: a segmented control with the focused workspace as a solid pill, tinted like the system icons. Click it to switch workspaces, toggle immersive mode or edit the config.
- **Immersive mode.** Auto-hides the macOS menu bar and Dock so tiles and fullscreen windows use the whole display, Omarchy-style.
- **Instant workspaces.** panespace keeps its own workspaces, independent of macOS Spaces. Windows on inactive workspaces are parked off-screen, so switching takes no animation and no Mission Control.
- **Multi-monitor.** Focus and move across displays, `move workspace to output`, and pinning workspaces to monitors.
- **Familiar i3 extras.** Scratchpad, binding modes (resize mode included), `for_window`/`assign` rules, `workspace back_and_forth`, gaps, `smart_gaps`, and an optional focus border.
- **Mouse.** Drag a window edge to resize the split; drop a window on another to swap them. With i3's `floating_modifier` held, left-drag moves any window (tiled ones swap where you drop them) and right-drag resizes from the nearest corner (tiled splits resize live).
- **IPC.** A command-line client in the style of `i3-msg`: `panespace msg focus left`, `panespace msg -t get_tree`.

## Install

```sh
make install          # builds, signs, installs Panespace.app and Caps.app (+ panespace, caps CLIs in ~/.local/bin)
open ~/Applications/Panespace.app ~/Applications/Caps.app
```

On first launch, macOS asks for Accessibility access. Grant it in **System Settings → Privacy & Security → Accessibility**; panespace starts on its own once you allow it.

```sh
make login-item       # start at login (launchd agent, log in ~/Library/Logs/panespace.log)
make uninstall
```

**Before you start:**
- **Quit other window managers** (AeroSpace, yabai, Amethyst) and turn off Rectangle's drag-to-snap. Two window managers will fight over the same windows.
- **Use one macOS Space per display.** panespace replaces Spaces with its own workspaces, and windows on other macOS Spaces are invisible to it.
- **Sign the build.** `make app` signs with your Apple Development identity when you have one, which keeps the Accessibility grant across rebuilds. Ad-hoc builds (`SIGN_ID=-`) have to be re-approved after every build.

## Default keys (`$mod` = ⌃⌥ ctrl+alt)

`set $mod caps` makes **Caps Lock** the panespace key instead. panespace remaps Caps Lock with macOS's own `hidutil` while it runs, so no Karabiner or other app is needed, and gives Caps Lock back when it quits. Other choices: `alt`, `cmd`, `hyper`. Plain `alt` takes ⌥ shortcuts and special characters away from apps.

| Keys | Action |
|---|---|
| `$mod+h/j/k/l` or arrows | focus left/down/up/right |
| `$mod+Shift+h/j/k/l` | move window |
| `$mod+1…0` | switch to workspace 1…10 |
| `$mod+Shift+1…0` | move window to workspace |
| `$mod+Tab` | back to the previous workspace |
| `$mod+[` / `$mod+]` | previous/next workspace on this monitor |
| `$mod+b` / `$mod+v` | split horizontal / vertical (the next window opens there) |
| `$mod+e` | toggle split direction |
| `$mod+w` / `$mod+s` | tabbed / stacking layout |
| `$mod+f` | fullscreen (zoom to the monitor) |
| `$mod+Shift+f` | immersive mode: auto-hide the macOS menu bar and Dock (Omarchy-style edge-to-edge) |
| `$mod+Shift+space` | toggle floating |
| `$mod+space` | switch focus between tiled and floating windows |
| `$mod+a` / `$mod+Shift+a` | focus parent / child container |
| `$mod+Shift+-` / `$mod+-` | send to scratchpad / show scratchpad |
| `$mod+Shift+=` | make all splits equal |
| `$mod+r` | resize mode: `hjkl`/arrows to resize, `b` to balance, Esc to leave |
| `$mod+Return` | new terminal |
| `$mod+Shift+q` | close window |
| `$mod+Shift+c` / `$mod+Shift+e` | reload config / quit (puts every window back on screen) |

## Configuration

The config lives in `~/.config/panespace/config` (or `$XDG_CONFIG_HOME/panespace/config`). panespace writes a commented default there on first run. After editing, reload with `$mod+Shift+c`, and check for mistakes with `panespace check-config`.

```
set $mod ctrl+alt                  # caps | alt | cmd | ctrl | hyper | meh, or combos like ctrl+alt
bindsym $mod+Return exec open -na Ghostty
bindsym $mod+Shift+period move workspace to output next

gaps inner 8
gaps outer 8                       # or top/bottom/left/right/horizontal/vertical
smart_gaps on                      # no gaps when a workspace has one window
default_border none                # or "pixel 2" for an outline around the focused window
border_radius 12
client.focused #5294e2 #5294e2 #ffffff #5294e2 #5294e2
default_orientation auto           # horizontal | vertical | auto
workspace_indicator segmented      # menu bar look: segmented | dots | tiles
immersive yes                      # start with the menu bar and Dock auto-hidden
workspace_layout default           # default | tabbed | stacking
workspace_auto_back_and_forth yes
focus_follows_mouse no
mouse_warping output               # output | none
floating_modifier $mod             # $mod+left-drag moves, $mod+right-drag resizes
focus_wrapping yes
accordion_padding 30               # panespace: how far tabbed/stacking neighbours peek out

workspace 9 output secondary primary   # primary | secondary | 1,2,… (left→right) | part of the display name
assign [app="^Slack$"] → 9
for_window [app="^System Settings$"] floating enable
for_window [bundle_id="com.apple.finder" title="Info$"] floating enable

mode "launch" {
    bindsym s exec open -a Safari; mode "default"
    bindsym Escape mode "default"
}
bindsym $mod+o mode "launch"

exec_always ~/bin/on-panespace-start.sh
```

Rules match regular expressions against `app` (aliases: `class`, `instance`), `bundle_id` (alias `app_id`), `title` and `workspace`, and can test the `floating`/`tiling` flags. Run `panespace list-windows` to see the exact names, bundle IDs and titles to match against.

**Commands** (use them in bindings, in rules, or through `panespace msg`, chained with `,` and `;`):
- **Exec, focus, move:** `exec`, `[criteria] focus`, `focus left|right|up|down|parent|child|mode_toggle|floating|tiling|output <dir|next|name>`, `move left|right|up|down [N px]`
- **Move to places:** `move [container] to workspace <name>|number N|next|prev|back_and_forth`, `move to output …`, `move workspace to output …`, `move scratchpad`, `move position center`
- **Workspaces, scratchpad:** `workspace <name>|number N|next|prev|next_on_output|prev_on_output|back_and_forth`, `scratchpad show`
- **Layout:** `split h|v|toggle`, `layout splith|splitv|tabbed|stacking|default|toggle [split|all|<list>]`
- **Window state:** `fullscreen [enable|disable|toggle]`, `floating enable|disable|toggle`, `resize grow|shrink width|height|left|right|up|down [N px] [or M ppt]`, `balance`
- **Session:** `kill`, `mode <name>`, `reload`, `exit`, `nop`

## CLI

```sh
panespace msg workspace 3              # or just: panespace workspace 3
panespace msg '[app="Safari"] focus'   # criteria work here too
panespace msg -t get_tree              # also get_workspaces, get_binding_modes, get_config, get_version
panespace list-windows                 # every window and how panespace classifies it
panespace check-config [path]
```

For debugging, `PANESPACE_DEBUG=1 panespace` logs every key event the tap sees.

## Caps: Caps Lock as a programmable key

`Caps.app` is the companion app. Hold Caps Lock and press a key, and Caps runs whatever you bound to that key: everywhere, or only in certain apps. Keys you didn't bind in Caps pass on to panespace as Caps+key, so `set $mod caps` in panespace keeps working unchanged. Tapping Caps on its own sends Escape.

```
# ~/.config/caps/config (saved changes apply instantly)
tap escape                       # Caps alone → Escape (tap none to turn off)
bind z open Zen                  # open/focus an app; press again to hide it
bind g url https://github.com
bind m exec ~/bin/toggle-mute.sh
app "Zen|Safari|Chrome" {        # regex on the app name or bundle ID
    bind x key cmd+w             # Caps+X closes the tab
    bind , key cmd+shift+[       # previous tab
}
app "Terminal|Ghostty" {
    bind j key down              # held keys repeat
}
```

Actions: `key <combo>`, `open <app>`, `exec <shell>`, `url <link>`, `text "<text>"`, `panespace <command>`, `nothing`.
Priority: an app block beats a global binding, and both beat panespace.
The menu bar item (⇪) lists what Caps does in the app you're in.
`caps check-config` validates your config.

How Caps and panespace share the key:
- Caps's keyboard hook runs first and panespace's runs last.
- Caps swallows the Caps key itself and tags every key and mouse event it passes on while Caps is held. panespace reads that tag, so Caps+drag keeps working.
- Keys Caps generates carry a different tag, so panespace never mistakes them for Caps+key.
- Both apps keep the hidutil remap alive while either is running. When the last one quits, Caps Lock is given back.

## How it works

The design follows research into AeroSpace, yabai, Amethyst and alt-tab (October 2026), checked on macOS 26.7.

- **Layout logic lives in its own module.** `Sources/PanespaceCore` holds the tree, the layout engine, the i3 config and command parsers, and the workspace/monitor model. It doesn't depend on AppKit, and `swift test` covers it with unit tests.
- **panespace reconciles; it doesn't track state.** Accessibility observers, workspace notifications and a 2.5 s safety scan all trigger the same refresh:
  1. Compare the real windows (`kAXWindowsAttribute`, cross-checked against `CGWindowListCopyWindowInfo` to drop ghost windows) with the model.
  2. Pick up focus changes made outside panespace.
  3. Write frames in parallel, one app per thread: size, then position, then size again, with `AXEnhancedUserInterface` turned off so apps don't animate.
- **Threading.** The main thread holds the model and never waits on another app; a command takes about 0.1 ms there. Frame writes and focus changes go to one serial background queue, in order. Window discovery runs on its own queue, with one thread per app. A slow or hung app only delays its own windows. A workspace switch takes about 12 ms end to end, most of it the CLI starting up. When nothing's size changed, each window move is one Accessibility call instead of three.
- **Memory and thread safety.** The code is Swift. The callback pointers handed to C APIs stay valid for the life of the process. The unit tests and the running daemon pass Thread Sanitizer (no data races) and Address Sanitizer (no memory errors) across every command, drags, rescans, IPC and reload.
- **Windows stay where you put them.** If an app is too busy to answer, its windows are kept as they are. Minimized windows and windows of hidden apps return to their own workspace when they come back. Only windows the window server says are gone get dropped. The session (which workspace each window is on) is saved to `/tmp` every two seconds, so restarts and crashes keep your layout.
- **Workspaces work like AeroSpace's.** Hidden windows move to a bottom corner of their monitor, with about 1 px left on screen because macOS won't allow fully off-screen windows. panespace picks the corner that doesn't touch another display. Quitting brings every window back.
- **Hotkeys come from an event tap**, a system hook that intercepts keystrokes, not from Carbon `RegisterEventHotKey`:
  - It runs on its own thread, so a hung app can't delay your typing.
  - It needs only the Accessibility permission.
  - It avoids the Option-only hotkey restriction that macOS 15.0–15.1 placed on Carbon hotkeys.
  - While Secure Input is on (a password field has focus), macOS withholds keystrokes from every app, panespace included. The menu bar shows ⚠︎ when that happens.
- **Focusing another app's window goes through three steps.** SkyLight's `_SLPSSetFrontProcessWithOptions` plus a "make key window" event record, the same approach as yabai and alt-tab; panespace loads it with `dlsym`, so it falls back cleanly if the symbol disappears. Then `kAXRaiseAction`, then `activate`. A second raise follows after 120 ms, because on Tahoe another app's window sometimes stays on top.
- **Window classification follows AeroSpace and yabai.**
  - `AXStandardWindow` windows with an enabled fullscreen button tile.
  - Dialogs, floating panels and fixed-size windows float.
  - Popups and anything above window layer 0 are ignored.
  - Terminals and Chromium-based browsers always tile.

## Not yet supported

- `resize set`, marks, `sticky`, title bars and tab labels.
- Floating windows aren't kept above tiled ones. macOS stacks windows by app, so a floating window can end up behind the app you clicked last.
- Windows on other macOS Spaces, and windows in native fullscreen (panespace's own `fullscreen` fills the monitor).
- Apps with a minimum window size can overflow their tile. AeroSpace has the same limitation.
