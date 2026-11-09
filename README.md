# Mouse Bindings

Small native macOS menu-bar app for a Bluetooth Magic Mouse. Requires macOS 14+
and Xcode or Apple's Swift toolchain. Developed on Apple Silicon/macOS 26.

## Build and run

```sh
./build.sh
open dist/MouseBindings.app --args --paused --inspect
```

The first run above pauses actions and opens the touch inspector. Check that
one, two and three fingers appear, and note the coordinates just above the Apple
logo. Then use the mouse icon in the menu bar:

1. **Grant Accessibility** and allow MouseBindings in System Settings.
2. If touch frames do not arrive, allow **Input Monitoring**, then retry.
3. Edit **Open configuration** to calibrate the orange lock region; reload it.
4. Turn on **Enable gestures** when ready to test the bindings.

The app keeps working when the inspector closes. Its 15 Hz display timer exists
only while the inspector is open. Input recognition uses device callbacks.
The inspector shows recognized gestures even while paused, without sending
shortcuts. Detecting a physical click in this mode still needs Accessibility.
Its **Last output** line identifies the front app when a shortcut is sent;
click Chrome before testing tab-switching gestures.
To pause actions, uncheck Enable gestures; Quit stops all monitoring.

Keep the `.app` at a fixed path when granting permissions. The build script uses
an available Apple Development identity for stable signing (or `SIGN_ID` if set),
falling back to ad-hoc signing when none exists. Ad-hoc rebuilds may invalidate
Accessibility approval even if its switch remains on. When changing from ad-hoc
to developer signing, quit the app, remove its old Accessibility entry, and add
the current `.app` again. Quit before changing a granted permission.
To start at login, add the app in System Settings → General → Login
Items. No installer, network access, or paid developer account is required.

## Default bindings

| Gesture | Shortcut |
|---|---|
| Two-finger swipe up or down | Native Mission Control action (toggles overview) |
| Tap left while a right finger rests | Option-Command-Left |
| Tap right while a left finger rests | Option-Command-Right |
| Physical click with two fingers | Command + left click (including hold/drag) |
| Two-finger double-tap | Shift-Command-4 (select a screenshot area) |
| Spread two fingers / pinch them together | Continuous native zoom in / out |
| Physical click with three fingers | Command-W |
| Short tap just above the Apple logo | Control-Command-Q (lock) |

TipTap requires one stationary finger already resting for 0.12 seconds, then
a short tap on its other side. Physical clicking is different from tapping.
The close shortcut targets the front app's window/tab, not necessarily the window
under the pointer. Both vertical swipe directions toggle Mission Control once per swipe.
For double-tap, tap both fingers together twice, lifting both between taps,
without pressing the mouse button. Timing uses your macOS double-click interval.
The fingers may land up to 0.16 seconds apart. Disabled TipTap bindings do not
reserve those touches. Each tap still needs to be short and stationary.

For zoom, place the pointer over content, rest two fingers on the mouse, then
slide them apart or together without clicking. You can reverse direction while
they stay down. Lifting either finger ends zoom; lift both before starting again.
Moving the two fingers together vertically still invokes Mission Control.
Clicking during a pinch cancels zoom and consumes that click. A physical click
before a pinch retains its normal configured action.

## Configuration

Created on first app launch at:

`~/Library/Application Support/MouseBindings/config.json`

Each binding contains `keyCode` (macOS virtual key code) and `modifiers`
(`command`, `option`, `control`, `shift`). Remove a binding to disable that gesture.
The file also contains tap/swipe thresholds and `logoRegion` bounds. Coordinates
are normalized: X is left 0 → right 1, Y is tail 0 → front 1. Default logo bounds
are provisional; calibrate them using the inspector before enabling lock.
Invalid configuration pauses actions and displays the error in the menu.
Swipe bindings use `"action": "missionControl"` to open the native overview
without relying on the system's keyboard shortcut. Remove `action` to use
that binding's `keyCode` and `modifiers` instead.

To tune two-finger double-tap sensitivity, add `"doubleTapMaxStagger": 0.16`
at the top level, alongside `tapMaxDuration`, then reload the configuration.
Increasing it (for example to `0.20`) allows the fingers to land farther apart
in time; `tapMaxDuration` still limits how long each finger may stay down.
Omitting the setting uses `0.16`. This does not alter the logo-tap limits or
the macOS interval between the two taps.
`"doubleTapMaxPointerMovement": 8` allows up to eight pixels of total pointer
jitter across both taps and the gap between them. Larger movement cancels the
double-tap. Zero-displacement mouse-move events are ignored. The logo lock tap
still rejects any actual pointer movement.

Native pinch zoom is separate from keyboard bindings. These top-level settings
enable it and control its response:

```json
"pinchEnabled": true,
"pinchThreshold": 0.035,
"pinchSensitivity": 1.0
```

`pinchThreshold` is the minimum change in normalized finger separation required
to begin zoom. Lower values start sooner, but may confuse touch jitter with a
pinch. `pinchSensitivity` controls how much zoom each movement produces; try
`1.5` for faster zoom or `0.7` for slower zoom. The threshold must be above zero
and at most 1; sensitivity must be above zero and at most 5. Missing threshold
and sensitivity use the values above. New configurations enable pinch; existing
configurations need an explicit `"pinchEnabled": true`. Set it to `false` to
disable zoom, then reload. Pause, reload, sleep, and connection restart cancel
an ongoing zoom. The inspector displays pinch phases and the output target.

An example binding:

```json
"tipTapLeft": { "keyCode": 123, "modifiers": ["option", "command"] }
```

To add these operations to an older configuration, add entries inside `bindings`
(separate entries with commas), then choose **Reload configuration**:

```json
"twoFingerClick": { "keyCode": 0, "modifiers": ["command"], "action": "commandClick" },
"twoFingerDoubleTap": { "keyCode": 21, "modifiers": ["shift", "command"] }
```

`commandClick` applies Command to the actual mouse down/drag/up and changes a
right-button click into a left-button click. Its `keyCode` and `modifiers` are
unused. Remove `action` to map the two-finger click to a keyboard shortcut.
Other existing gestures can be customized by editing their entries; adding an
entirely new gesture type also requires a recognizer in `GestureCore`.

The first version supports customizing these gesture bindings. Recognizers for
new gesture types can be added in `GestureCore`; Magic Keyboard remapping is not
implemented yet.

## Verify

```sh
swift test
dist/MouseBindings.app/Contents/MacOS/MouseBindings --probe --seconds 10
dist/MouseBindings.app/Contents/MacOS/MouseBindings --probe-input --seconds 20
dist/MouseBindings.app/Contents/MacOS/MouseBindings --test-shortcut tipTapRight
dist/MouseBindings.app/Contents/MacOS/MouseBindings --test-pinch in
```

`--probe` logs raw contact IDs, states and positions without installing an event
tap, sending shortcuts, or creating preferences. States 3 and 4 count as touching.
`--probe-input` records timestamped touch frames and mouse movement/click/scroll
events as JSON lines using a read-only event tap. Quit the normal app first;
run the probe on its own, then reopen the app when recording ends. It does not
record keyboard input or execute gesture actions and needs the app's existing
Accessibility / Input Monitoring approval.
Tests exercise real gesture sequences and event filtering without injecting input.
`--test-shortcut` sends a configured action after three seconds, independently
of recognition; activate the intended app during the delay.
`--test-pinch in` (or `out`) sends a short native magnification sequence after
two seconds. Quit the normal app first, activate the target app, and place the
pointer over its content. Reopen the normal app after the test.

On the actual mouse, check all bindings, normal one-finger scrolling/clicking/
dragging, no extra click when closing, no foreground scroll during two-finger
swipes, no locks from resting/scrolling, and recovery after Bluetooth reconnect
and Mac wake. Check pinch in an app that supports trackpad magnification and
confirm the double-tap screenshot still works after lifting both fingers.

## Limits

The private MultitouchSupport API and undocumented Quartz magnification fields
can change after macOS upgrades. The app selects Magic Mouse family 112 and
uses public Quartz APIs for event filtering/shortcuts.
Quartz events do not expose a reliable physical mouse ID: clicking another input
device while two or three fingers rest on Magic Mouse can be mistaken for its click.
Two-finger scrolling is reserved while swipe bindings or pinch zoom are enabled;
use one finger for normal scrolling. Remove both swipe bindings and set
`pinchEnabled` to `false` to restore two-finger scrolling. Native zoom depends
on the target app supporting magnification; it may zoom a page or image without
changing the app's keyboard zoom percentage. Disable any overlapping built-in
gestures if they cause duplicate actions during testing.

See [PLAN.md](PLAN.md), [research-magic-mouse.md](research-magic-mouse.md), and
[THIRD_PARTY.md](THIRD_PARTY.md).
