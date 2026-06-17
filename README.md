# VolumeLite

A tiny macOS menu-bar app that lets you change the system volume by scrolling the mouse wheel along the **bottom edge of the screen** — a lightweight take on the edge-scroll volume control popularized by [Volume²](https://github.com/irzyxa/Volume2) on Windows.

![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5-orange)
![License](https://img.shields.io/badge/license-MIT-green)

<img width="329" height="189" alt="image" src="https://github.com/user-attachments/assets/fe591fa2-cb28-4013-b0c0-a831c98e393d" />
<img width="334" height="205" alt="image" src="https://github.com/user-attachments/assets/f46a2b9c-a448-45f6-bc55-c06a6c3daad9" />



## Features

- **Edge-scroll volume control** — roll the scroll wheel while the cursor is near the bottom of any screen to raise or lower the system volume.
- **Lives in the menu bar** — no Dock icon, no window. The menu-bar icon shows a speaker glyph and the current percentage, updated live.
- **On-screen HUD** — a small panel appears at the bottom-center of the active screen showing the current level whenever you change it, then fades away.
- **Quick menu** — click the menu-bar icon for a volume slider, mute, and an invert-scroll-direction toggle.
- **Multi-monitor aware** — the bottom edge of whichever screen the cursor is on triggers the change, and the HUD appears on that screen.
- Uses CoreAudio directly — no helper processes, and it follows your current default output device.

## Requirements

- macOS 13 (Ventura) or later
- Xcode 15+ (to build)
- Two system permissions (see [Permissions](#permissions))

## Permissions

This app needs two things that are non-negotiable for the global edge-scroll feature to work:

1. **Accessibility access.** The app installs a system-wide scroll-event tap, which macOS gates behind Accessibility. On first launch you'll be prompted; enable **VolumeLite** under *System Settings ▸ Privacy & Security ▸ Accessibility*, then relaunch if it doesn't activate within a couple of seconds.
2. **App Sandbox must be OFF.** A sandboxed app is not allowed to create a global event tap, so the capability has to be removed from the target. Because of this, VolumeLite cannot be distributed through the Mac App Store — it's intended as a personal/local utility.

The menu-bar menu shows the current status on its top line ("Active", "turn off App Sandbox", or "Grant Accessibility access") so you can tell at a glance whether the tap is running.

## Build V1 for ARM

https://github.com/animhotep/volumeLite/blob/main/VolumeLite.app/Contents/MacOS/VolumeLite


## Building

### With Xcode

1. Create a new project: **File ▸ New ▸ Project ▸ macOS ▸ App** — name it `VolumeLite`, Interface **SwiftUI**, Language **Swift**.
2. Replace the generated `VolumeLiteApp.swift`, delete the generated `ContentView.swift`, and add the source files below.
3. In **Signing & Capabilities**, remove the **App Sandbox** capability.
4. (Optional) In the target's Info tab add **Application is agent (UIElement) = YES** to avoid a brief Dock flash on launch.
5. Build and run (⌘R). To keep a standalone copy, expand **Products** in the navigator, right-click `VolumeLite.app ▸ Show in Finder`, and drag it to `/Applications`.

### From the command line

A `build.sh` script is included that compiles the sources with `swiftc`, assembles a proper `.app` bundle with an `Info.plist`, and ad-hoc code-signs it:

```bash
chmod +x build.sh
./build.sh
open ./VolumeLite.app
```

> Note: each ad-hoc rebuild gets a fresh signature, and macOS ties the Accessibility grant to the signature — so after rebuilding you may need to re-enable VolumeLite in the Accessibility list. Signing with a stable Developer ID avoids this.

## Usage

- **Change volume:** push the pointer to the bottom edge of the screen and scroll. The trigger zone is the bottom ~100px.
- **See the level:** glance at the menu-bar icon, or watch the HUD that pops up at the bottom-center when you change the volume.
- **Menu:** click the menu-bar icon for a slider, **Mute**, **Invert scroll direction**, and **Quit**.
- The HUD does not appear for changes made with the keyboard's volume keys — macOS shows its own HUD for those.

## Configuration

Most of the behavior lives in a few constants you can tweak in source:

| What | File | Constant / value |
| --- | --- | --- |
| Height of the bottom trigger zone | `GlobalScrollMonitor.swift` | `bandHeight` (default `100`) |
| Scroll sensitivity (mouse wheel) | `GlobalScrollMonitor.swift` | `lineSensitivity` (default `0.04`) |
| Scroll sensitivity (trackpad) | `GlobalScrollMonitor.swift` | `pixelSensitivity` (default `0.0015`) |
| HUD size / corner radius | `VolumeHUD.swift` | `panelSize`, layer `cornerRadius` |
| HUD position above bottom edge | `VolumeHUD.swift` | `f.minY + 120` |
| HUD on-screen duration | `VolumeHUD.swift` | `asyncAfter(... + 1.2)` |
| HUD opacity | `VolumeHUD.swift` | `window.alphaValue` |

## Project structure

| File | Responsibility |
| --- | --- |
| `VolumeLiteApp.swift` | App entry point; hosts the app delegate, no window. |
| `AppDelegate.swift` | Menu-bar status item, menu, permission handling, wiring. |
| `VolumeController.swift` | Reads/writes the default output device volume via CoreAudio. |
| `GlobalScrollMonitor.swift` | System-wide scroll-event tap and bottom-edge detection. |
| `VolumeHUD.swift` | The on-screen volume overlay. |
| `build.sh` | Command-line build into a signed `.app`. |

## How it works

- **Volume** is read and set through CoreAudio (`kAudioDevicePropertyVolumeScalar` / `kAudioDevicePropertyMute`) on the system's default output device, falling back to per-channel control on devices without a master channel.
- **Edge scrolling** uses a `CGEvent` session tap listening for `scrollWheel` events. When the cursor sits within the bottom band of its display, the scroll delta is converted into a volume nudge and the event is consumed so the window underneath doesn't also scroll.
- **The app** runs as an `NSApplication` accessory (agent) with an `NSStatusItem`; there is no main window.

## Limitations

- Requires Accessibility access and a non-sandboxed build, so it can't ship on the Mac App Store.
- The volume HUD intentionally does not show for hardware volume-key presses (macOS already shows one).
- Scroll events at the very bottom edge are consumed, so content that sits flush against the bottom edge won't scroll there.

## Credits

Inspired by [Volume²](https://github.com/irzyxa/Volume2) by irzyxa, a feature-rich volume control for Windows. VolumeLite reimplements only the edge-scroll idea for macOS and is not affiliated with that project.

## License

```
MIT License

Copyright (c) 2026 animhotep
```
