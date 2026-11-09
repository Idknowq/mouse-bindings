# Mouse Bindings

A small macOS menu-bar app for customizing Magic Mouse gestures. It runs locally,
uses touch callbacks, and has no third-party package dependencies or background
network service. Settings live in one JSON file.

Requires **macOS 14+**, a Magic Mouse connected over **Bluetooth**, and Xcode or
Apple's Swift toolchain to build. Developed on Apple Silicon with a USB-C Magic
Mouse on macOS 26; other models and macOS versions need testing. Magic Keyboard
remapping is not implemented.

## Get started

1. In Terminal, change to this repository's directory and build:

   ```sh
   ./build.sh
   ```

   This creates `dist/MouseBindings.app`. If the Swift toolchain is missing,
   run `xcode-select --install`, finish installation, then build again.

2. Launch with actions paused and the touch inspector open:

   ```sh
   open dist/MouseBindings.app --args --paused --inspect
   ```

   Flags apply at launch. If the app is already running, choose **Quit** from
   its menu before running this command again.

3. Click the **mouse icon in the menu bar** → **Grant Accessibility…**. In
   **System Settings → Privacy & Security → Accessibility**, allow
   `MouseBindings.app`. Return to the app and choose **Retry connection / permissions**.
   If the inspector receives no touches, also allow the app under **Input Monitoring**.
   Quit before changing a permission, then reopen with the command above.

4. Rest one, two, then three fingers on the mouse. The inspector should display
   their positions. A contact ID identifies a finger during one touch; it can
   change after you lift that finger.

5. Calibrate the lock area before enabling actions. Use **Open configuration…**
   and edit `logoRegion` to cover the area just above the Apple logo, using
   coordinates shown in the inspector. X runs left `0` → right `1`; Y runs
   tail/logo `0` → front `1`. Remove `logoTap` from `bindings` to disable lock
   while calibrating. Save, then choose **Reload configuration**.

6. Select **Enable gestures**. The menu should say **Gestures enabled**.
   Activate the app you want to control and try a gesture. Close the inspector
   when finished; gestures keep working.

Uncheck **Enable gestures** to pause. **Quit** stops monitoring. A normal launch
enables configured actions; the previous paused state is not saved:

```sh
open dist/MouseBindings.app
```

To start at login, add this app under **System Settings → General → Login Items**.

## Gestures

These are the defaults for a **new** configuration. An existing configuration
keeps its saved mappings, including any gestures you removed.

| Gesture | How to perform it | Default result |
|---|---|---|
| Two-finger swipe up or down | Slide both fingers vertically together | Toggle Mission Control (window/desktop overview) |
| Two-finger click | Physically press the mouse with two fingers resting | Command + left click, including hold/drag |
| Two-finger double-tap | Tap both fingers twice, lifting both between taps; do not click | Select a screenshot area (Shift-Command-4); Escape cancels |
| Pinch / spread | Slide two fingers together / apart without clicking | Continuous native zoom out / in |
| Three-finger click | Physically press with three fingers resting | Close the front app's window/tab (Command-W) |
| Logo tap | Briefly tap inside the calibrated `logoRegion` | Lock screen (Control-Command-Q) |
| Left TipTap | Rest a right finger for at least 0.12 seconds, then tap to its left | Option-Command-Left |
| Right TipTap | Rest a left finger for at least 0.12 seconds, then tap to its right | Option-Command-Right |

**Tapping** touches the surface; **clicking** presses the physical button.
TipTap bindings are optional: remove `tipTapLeft` and `tipTapRight` if unwanted.
Keyboard actions target the active app, which may differ from the window under
the pointer.

Use **one finger for normal scrolling**. Two-finger scroll is captured while
either swipe binding or pinch zoom is enabled. To restore two-finger scrolling,
remove both swipe bindings and set `pinchEnabled` to `false`.

For pinch, place the pointer over the content you want to zoom. You can reverse
direction without lifting. Lifting either finger ends zoom; lift both before
starting again. Clicking during a pinch cancels zoom and consumes that click.
Native zoom requires support from the target app and may leave its keyboard zoom
percentage unchanged. Pinch recognition has automated tests; visible Chrome
zoom and physical gesture calibration still need confirmation.

## Customize operations

Open **mouse menu → Open configuration…**. The file is created on first launch at:

```text
~/Library/Application Support/MouseBindings/config.json
```

Edit, save, then select **Reload configuration**. Invalid JSON or settings pause
actions and show an error in the menu. After fixing the file and reloading,
select **Enable gestures** again.

### Change or remove a shortcut

Entries inside `bindings` use a macOS virtual `keyCode` and a list of modifiers:
`command`, `option`, `control`, `shift`. For example, changing the double-tap to
capture the whole screen (Shift-Command-3) requires only this binding:

```json
"twoFingerDoubleTap": { "keyCode": 20, "modifiers": ["shift", "command"] }
```

This is an entry inside the existing `bindings` object, not a complete file.
Remove an entry to disable that gesture. Adding an unrecognized gesture name
requires code; see [OPERATIONS.md](OPERATIONS.md) for the agent extension guide.

Two actions have special handling:

- `"action": "missionControl"` opens the native overview. Its `keyCode` and
  `modifiers` are ignored. Remove `action` to send the configured shortcut instead.
- `"action": "commandClick"` works only with `twoFingerClick`. It adds Command
  to the actual down/drag/up sequence and converts a right click to a left click.
  Its `keyCode` and `modifiers` are ignored. Remove `action` to use a keyboard shortcut.

### Tune double-tap or pinch

These settings belong at the top level, alongside `bindings`:

| Setting | Value when omitted | What to adjust |
|---|---|---|
| `doubleTapMaxStagger` | `0.16` seconds | Try `0.20` if the two fingers land slightly apart in time |
| `doubleTapMaxPointerMovement` | `8` pixels | Total pointer jitter allowed across both taps and their gap; intentional movement cancels |
| `tapMaxDuration` | Required; new config uses `0.25` seconds | Maximum duration of each touch; also affects logo tap |
| `tapMaxMovement` | Required; new config uses `0.035` | Maximum surface movement per touch; also affects logo tap |
| `pinchEnabled` | Off in older configs; on in new configs | Set `true` to enable native pinch zoom |
| `pinchThreshold` | `0.035` | Lower starts zoom sooner but may respond to jitter |
| `pinchSensitivity` | `1.0` | Try `1.5` for faster zoom or `0.7` for slower zoom |

Double-tap uses your macOS double-click interval for the gap between taps.
Zero-displacement mouse events are ignored. The logo tap still rejects actual
pointer movement. Duration/movement thresholds must be above `0` and at most `1`;
pinch sensitivity must be above `0` and at most `5`; pointer tolerance must be
finite and non-negative.

## Troubleshooting

| What you see | What to do |
|---|---|
| **Needs Accessibility permission** | Quit, approve the current `.app` under Accessibility, reopen, and retry |
| Touch positions never appear | Confirm Bluetooth connection; approve Input Monitoring; reopen and retry |
| **Last gesture** never changes | Check that the binding exists, distinguish tap from click, and check touch positions/timing |
| Gesture appears but nothing happens | Activate the target app, check **Last output**, and verify the mapped shortcut manually |
| Config error | Check JSON commas/braces and values; reload, then enable gestures |
| Old behavior after editing | Save the actual user config and choose **Reload configuration** |
| Duplicate system actions | Disable the overlapping gesture in macOS Mouse settings |
| Gestures stop after reconnect/wake | Choose **Retry connection / permissions** |

Keep the `.app` at the same path when granting permissions. The build script uses
an available Apple Development signing identity, or `SIGN_ID` when supplied.
With no identity it uses ad-hoc signing, which may require renewing Accessibility
approval after each rebuild. If approval looks enabled but actions fail after
rebuilding, quit, remove the stale Accessibility entry, add the current app, and
reopen. Building locally does not require a paid developer account.

To update the app: **Quit → `./build.sh` → reopen**. Your config lives outside
the repository and is preserved across builds.

## Development and diagnostics

Run recognizer/filter tests without injecting input:

```sh
swift test
```

For hardware or output diagnostics, quit the normal app first and run **one**
command at a time from the repository directory:

```sh
# Read touch IDs, states and positions for 10 seconds.
dist/MouseBindings.app/Contents/MacOS/MouseBindings --probe --seconds 10

# Record touch and mouse events for 20 seconds; no keyboard input is recorded.
dist/MouseBindings.app/Contents/MacOS/MouseBindings --probe-input --seconds 20

# Send Mission Control after three seconds, independent of recognition.
dist/MouseBindings.app/Contents/MacOS/MouseBindings --test-shortcut swipeUp

# Send native zoom after two seconds; activate the target and point at content.
dist/MouseBindings.app/Contents/MacOS/MouseBindings --test-pinch in
```

`--probe-input` uses a read-only event tap and needs the app's permissions.
The output tests **execute actions**; `--test-pinch out` tests zoom out. Reopen
the normal app after a diagnostic finishes.

## Compatibility and reference

The app uses Apple's private MultitouchSupport framework and undocumented native
magnification event fields. macOS updates can break these interfaces. Physical
mouse events have no reliable device ID, so clicking another input device while
fingers rest on the Magic Mouse can be interpreted as a Magic Mouse click.

- [OPERATIONS.md](OPERATIONS.md): instructions for agents adding or modifying operations.
- [PLAN.md](PLAN.md): implementation plan and verification status.
- [research-magic-mouse.md](research-magic-mouse.md): feasibility research and sources.
- [THIRD_PARTY.md](THIRD_PARTY.md): third-party references and license notices.
