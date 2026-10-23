# NotchDeck

A mission control for the MacBook notch, in the spirit of Alcove. Hover the notch and it opens
into a panel; move away and it folds back.

**Home**: what's playing in Spotify or Music (artwork, scrubber, play/pause/skip), the time and date,
and a shortcut to the tray.
**Tray**: drag any file onto the notch (it opens as a drop target mid-drag) and it waits there.
Drag files back out, double-click to open, right-click to reveal or remove, AirDrop the lot.
**Controls**: brightness and volume sliders, plus Keep Awake, Dark Mode, Hide Desktop icons,
Screenshot, Display Off and Lock.

While collapsed, the notch shows a live activity when music plays (artwork on the left, a visualiser
on the right) and a brief volume or brightness HUD when you press the keys.

## Build and run

Needs macOS 14+ and the Swift toolchain (the Command Line Tools are enough; Xcode is not required).

```bash
./scripts/build-app.sh            # builds build/NotchDeck.app
./scripts/build-app.sh --install  # also copies it to /Applications and launches it
```

The menu bar icon (a laptop) opens any tab, toggles Launch at Login (works once the app is in
/Applications), and quits.

## Permissions

- **Automation** (asked on first use): to read and control Spotify/Music and to toggle Dark Mode
  through System Events. If you rebuild, macOS may ask again because the ad-hoc signature changes.
- Nothing else: mouse tracking uses global mouse monitors, which need no Accessibility access.

## How it works

| Piece | Mechanism |
|---|---|
| Panel | Borderless non-activating `NSPanel` above the menu bar, ignoring the mouse while collapsed |
| Notch size | `NSScreen.safeAreaInsets` plus `auxiliaryTopLeftArea`/`RightArea`; a virtual notch on other Macs |
| Drag detection | the drag pasteboard's `changeCount` while the mouse button is held |
| Now playing | AppleScript against running players only (MediaRemote refuses non-Apple clients since 15.4) |
| Volume | CoreAudio virtual main volume and mute on the default output device, with listeners |
| Brightness | private `DisplayServices` (built-in display only; external monitors need DDC) |
| Keep Awake | an `IOPMAssertion` that prevents display sleep |
| Lock | private `SACLockScreenImmediate`, falling back to `pmset displaysleepnow` |

`@State` is not used: on the macOS 27 SDK it is a macro whose plugin ships only with Xcode, so
view-local state lives in a small `ViewState` box (`Sources/NotchDeck/Views/ViewState.swift`).

## Ideas for next

Calendar's next event (EventKit), a clipboard history tab, browser media through the
`mediaremote-adapter` approach, a charging live activity, external display brightness over DDC,
a global hotkey, and a settings window.
