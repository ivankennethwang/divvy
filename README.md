# Divvy Native

A native Apple Silicon rebuild of [Divvy](https://mizage.com/divvy/), the grid-based window manager for macOS.

The last Divvy release (1.5.2, 2019) is Intel-only and runs under Rosetta, which Apple is phasing out. This is an
independent reimplementation in Swift that looks and behaves like the original: open the panel, drag across the grid,
and the frontmost window snaps to that part of the screen.

> Not affiliated with or endorsed by Mizage. "Divvy" is Mizage's trademark. No Mizage code or artwork is included.

## Features

- Translucent grid panel, opened from the menu bar icon or a global shortcut you choose
- Drag across the grid to size the frontmost window, with an on-screen preview of where it will land
- Your own shortcuts for saved positions, either global or active only while the panel is open
- Adjustable grid: ⌘+ / ⌘− add or remove a row, ⌘⇧+ / ⌘⇧− add or remove a column
- Settings on the back of the panel (gear icon or ⌘,): launch at login, menu bar icon, keep the panel open,
  cycle shortcuts across displays, animations, resize preview, window and screen-edge margins, default grid size
- Shortcut editor: name, key combination, cells, enabled and global switches
- The window moves to the display the panel opens on (the one under the mouse)

## Requirements

- macOS 14 Sonoma or later on Apple Silicon
- Xcode Command Line Tools (`xcode-select --install`); the full Xcode app is not needed

## Build and install

```sh
git clone git@github.com:ivankennethwang/divvy.git
cd divvy
./build.sh install
```

This compiles the app into `build/`, copies it to `/Applications/Divvy Native.app` and launches it. To install
somewhere else, set `INSTALL_DIR`, for example `INSTALL_DIR=~/Applications ./build.sh install`.

`./build.sh` on its own only builds, and `./build.sh test` runs the logic tests.

### Grant Accessibility access

Moving other apps' windows needs Accessibility permission. On first launch macOS asks for it; otherwise open
**System Settings → Privacy & Security → Accessibility** and turn on **Divvy Native**.

The build is signed ad hoc (no developer certificate), so macOS treats every rebuild as a new app. After rebuilding,
remove Divvy Native from the Accessibility list with **−** and add it again, even if its switch still shows on.

If the original Divvy is still running, quit it so the two don't compete for the same shortcuts.

## Usage

No shortcuts are set up out of the box. Click the menu bar icon to open the grid, then use the gear to set them up:

- **General → Use global shortcut to display panel**: click the field and press a key combination to open the panel
  from anywhere.
- **Shortcuts → New**: name a position, record its keys, drag across the cells it should cover, and choose whether it
  works everywhere (**Global Shortcut**) or only while the panel is open.

| Where | Keys | Action |
| --- | --- | --- |
| Panel | Drag on the grid | Resize the window to the selected cells |
| Panel | ⌘+ / ⌘− | Add / remove a row |
| Panel | ⌘⇧+ / ⌘⇧− | Add / remove a column |
| Panel | ⌘, | Flip to settings and back |
| Panel | Esc | Close |

Clicking the menu bar icon opens the grid; right-click opens the settings. If you hide the menu bar icon, open the app
again from Finder or Spotlight to get to the settings.

Settings are stored in `~/Library/Application Support/Divvy Native/config.json`. You can edit it by hand while the app
is quit; an unreadable file is kept as `config.json.invalid` and the defaults are used.

## Uninstall

Quit Divvy Native from its settings (General → Quit), then:

```sh
rm -rf "/Applications/Divvy Native.app" ~/Library/Application\ Support/Divvy\ Native
```

and remove it from the Accessibility list in System Settings.

## Project layout

| Path | Contents |
| --- | --- |
| `Sources/AppDelegate.swift` | Menu bar item, global hotkeys, About and Help |
| `Sources/PanelController.swift` | The panel: grid face, flipping to settings, in-panel keys |
| `Sources/SettingsView.swift` | General, Appearance and Shortcuts tabs, shortcut editor |
| `Sources/GridView.swift` | Grid drawing and drag selection, resize preview overlay |
| `Sources/Theme.swift` | Colors, HUD buttons, checkboxes, tab bar, shortcut recorder |
| `Sources/WindowMover.swift` | Accessibility window lookup, grid-to-screen geometry |
| `Sources/HotKeys.swift` | Carbon global hotkey registration |
| `Sources/Config.swift` | Settings model and `config.json` persistence |
| `Tests/main.swift` | Logic tests run by `./build.sh test` |
| `tools/make-icon.swift` | Generates the app icon at build time |

## License

[MIT](LICENSE)
