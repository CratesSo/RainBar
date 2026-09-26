# RainBar

RainBar is a native macOS menu bar app that draws rain or snow over the active window or its display.

This project is distributed as source code; Build locally with Xcode.

## Requirements

- macOS 26.0 or newer
- Xcode 26 or newer with the macOS SDK; Xcode Command Line Tools alone are insufficient

The app uses Swift, SwiftUI, AppKit, Core Graphics, and QuartzCore. There are no third-party dependencies or package downloads. The project uses local ad-hoc signing and does not require an Apple Developer account or signing team.

## Build and run

Download or clone the repository, then run these commands from its root directory.

```sh
xcodebuild build \
  -project RainBar.xcodeproj \
  -scheme RainBar \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath build

open "build/Build/Products/Release/RainBar.app"
```

Alternatively, open `RainBar.xcodeproj` in Xcode, select the shared `RainBar` scheme and **My Mac**, then choose **Product → Run**. The app appears in the menu bar and has no Dock icon.

If `xcodebuild` reports that the active developer directory points to Command Line Tools, select the full Xcode installation in **Xcode → Settings → Locations → Command Line Tools**.

For regular use, copy the app you built to a stable location, such as `~/Applications`, and launch that copy before granting Accessibility access.

## Usage

- **Rain** or **Snow** starts the selected effect; **Off** stops either effect.
- The fullscreen button switches between the target window and the display containing its center.
- The gear button expands or collapses effect controls.
- The power button quits the app.

Use **+** button to create a new preset. The save button overwrites a modified custom preset. The built-in **Default** preset cannot be overwritten or deleted.

Rain and Snow have separate presets and can each use the same preset name. Startup and mode changes restore that mode's last selected saved preset, or Default. Unsaved adjustments are discarded on startup or a mode change.

## Permissions and local data

RainBar checks Accessibility access when you click **Rain** or **Snow**. If access has not been granted, it shows the macOS permission prompt at most once per launch. Follow the prompt to **System Settings → Privacy & Security → Accessibility** and enable RainBar. If the app is not listed, add the built app with **+**.

The request does not block the effect. Until access is granted, or if the focused window cannot be read through Accessibility, RainBar falls back to the first eligible visible window. If no target window is found at startup, the effect does not start. If the target disappears while running, including during a Space switch, the overlay hides and resumes automatically when a target becomes available. After granting access, click **Rain** or **Snow** again if the effect is stopped.

Rebuilding or moving an ad-hoc-signed app may require removing its old Accessibility entry and adding the current copy again.

Settings and presets are stored locally using `UserDefaults`. The app has no network requests, analytics, accounts, or telemetry.

## Development and Useless Slop Tests

Run the test suite from the repository root:

```sh
xcodebuild test \
  -project RainBar.xcodeproj \
  -scheme RainBar \
  -destination 'platform=macOS' \
  -derivedDataPath build
```

Tests cover preset persistence, mode isolation, compatibility with older presets, fullscreen preferences, and menu expansion. Test preferences use isolated temporary domains that are removed after each test. Animation appearance, click-through behavior, Accessibility, and Spaces transitions still need manual testing on macOS.

For UI or rendering changes, check both Rain and Snow, window and fullscreen modes, and preset switching. Include the macOS and Xcode versions when reporting a bug.

Generated apps, build output, test results, and local signing material are excluded from version control.

## Limitations

- Fullscreen and Spaces behavior is best effort. Fullscreen covers one target display, not every connected display.
- Window selection depends on Accessibility and the visible-window fallback; some apps or system windows may not provide a usable target.

## License

MIT. See [LICENSE](LICENSE).
