# NotchDeck

A mission control for the MacBook notch, in the spirit of Alcove, NotchNook, boring.notch, MewNotch
and Atoll. Hover (or click) the notch and it opens into a themed panel; move away and it folds back.

## Tabs

| Tab | What it does |
|---|---|
| **Home** | Now playing from Spotify or Music (artwork, scrubber, controls, visualiser) beside a widget of your choice: clock with weather and next event, a big weather card, your next event, or system stats |
| **Tray** | Drag files onto the notch to stash them; drag out, double-click to open, AirDrop. Optionally keeps its own copy |
| **Calendar** | Today's and tomorrow's events from every calendar in Calendar.app, colour-coded |
| **Clipboard** | Your recent copies (text, images, files); click to copy again. In memory only, skips password-manager items |
| **Mirror** | The front camera, for a check before calls; off the moment you leave the tab |
| **Controls** | Brightness and volume, a focus timer, CPU/GPU/RAM/disk, Keep Awake, Dark Mode, Hide Desktop, Screenshot, Display Off, Lock |

Each tab except Home can be switched off in Settings → Modules. Two-finger swipe moves between tabs.

## Around the closed notch

- **Music live activity**: album art on the left, a visualiser (bars, wave or dots) on the right.
- **Timer**: a progress ring and the time left while a focus timer runs.
- **Drop-down activities**: charger connected or removed (with level), low battery at 20/10/5%,
  Bluetooth devices connecting (AirPods get their own icon), a calendar event five minutes out,
  timer done.
- **HUD**: replaces the macOS volume and brightness pop-up, as wings or a progress bar.

## Settings

Open from the gear in the panel, the menu bar icon, or ⌘, in its menu.

- **General**: open on hover or click, hover delay, swipe between tabs, haptics, launch at login.
- **Appearance**: seven themes (Midnight, Aurora, Ember, Ocean, Forest, Sakura, Graphite), accent
  from album art / theme / custom colour, corner roundness, shadow, the Home widget.
- **Modules**, **Media & HUD** (visualiser, HUD style, key step size), **Live Activities**,
  **Tray & Clipboard**, **Weather** (city and units), **About** (permission shortcuts).

Every theme is pure black at the top edge so the panel stays seamless with the hardware notch.

## Build and run

Needs macOS 14+ and the Swift toolchain (the Command Line Tools are enough; Xcode is not required).

```bash
scripts/make-signing-identity.sh     # once: a local identity so permissions survive rebuilds
scripts/build-app.sh --install       # build, copy to /Applications, launch
```

Handy flags:

```bash
build/NotchDeck.app/Contents/MacOS/NotchDeck --render-previews previews   # every state, theme and Settings to PNG
open /Applications/NotchDeck.app --args --open calendar                   # open a tab on launch
open /Applications/NotchDeck.app --args --settings                        # open Settings on launch
```

`--render-previews` uses SwiftUI's `ImageRenderer`, which draws the drop target as a yellow
placeholder and skips scroll views (tray, clipboard, calendar lists, Settings panes); the real app has
neither problem.

## Permissions

| Permission | For | Asked when |
|---|---|---|
| Accessibility | replacing the volume/brightness HUD | on launch, if the HUD option is on |
| Automation | Spotify, Music, Dark Mode | first use |
| Calendars | Calendar tab, event reminders | you press Connect |
| Camera | Mirror tab | you open it |
| Bluetooth | device announcements | on launch, if that activity is on |

Weather uses Open-Meteo (no account); only the city name you type leaves the Mac.

## How it works

| Piece | Mechanism |
|---|---|
| Panel | Borderless non-activating `NSPanel` above the menu bar, ignoring the mouse while collapsed |
| Notch size | `NSScreen.safeAreaInsets` plus `auxiliaryTopLeftArea`/`RightArea`; a virtual notch on other Macs |
| Drag detection | the drag pasteboard's `changeCount` while the mouse button is held |
| Now playing | AppleScript against running players only (MediaRemote refuses non-Apple clients since 15.4) |
| Volume | CoreAudio virtual main volume and mute on the default output device, with listeners |
| Brightness | private `DisplayServices` (built-in display only) |
| System HUD | a `CGEventTap` on `NX_SYSDEFINED` media keys; handled keys are swallowed |
| Charging | `IOPSNotificationCreateRunLoopSource` |
| Bluetooth | `IOBluetoothDevice` connect/disconnect notifications |
| Calendar | EventKit; Weather: Open-Meteo; Stats: `host_statistics` (CPU, RAM) and the IOAccelerator `PerformanceStatistics` (GPU); Mirror: AVFoundation |

`@State` is not used: on the macOS 27 SDK it is a macro whose plugin ships only with Xcode, so
view-local state lives in a small `ViewState` box (`Sources/NotchDeck/Views/ViewState.swift`).
