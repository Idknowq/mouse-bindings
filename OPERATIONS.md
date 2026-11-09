# Agent guide: add or modify operations

Use this guide when asked to change what a gesture does, recognize a new gesture,
or send a new kind of action. The app has three separate concepts:

- **Gesture:** input recognized from touch frames or a physical mouse click.
- **Binding:** a saved mapping from a gesture name to a keyboard shortcut or action.
- **Output:** execution of that shortcut/action. Pinch uses a continuous event
  stream rather than a discrete binding.

Keep the change in the layer that owns the requested behavior. A shortcut remap
usually requires only a user-config edit.

## 1. Establish the requested behavior

Identify the input (tap, physical click, swipe, or continuous movement), finger
count, target action/app, trigger moment, and overlapping existing gestures.
For a keyboard action, have the user verify the shortcut in the target app.
For a native action, verify output independently before tuning recognition.

Read the relevant source below and the user's actual configuration at
`~/Library/Application Support/MouseBindings/config.json`. Check which mappings
they removed or calibrated. Stop this step when the input, output, conflicts,
and current mapping are explicit enough to implement one behavior.

| Responsibility | Source |
|---|---|
| Gesture names, binding schema, new-install defaults, validation | [Configuration.swift](Sources/GestureCore/Configuration.swift) |
| Discrete touch recognition, physical click routing, scroll filtering | [GestureEngine.swift](Sources/GestureCore/GestureEngine.swift) |
| Continuous pinch recognition and phases | [Pinch.swift](Sources/GestureCore/Pinch.swift) |
| Input callbacks, lock, output scheduling, pause/reload/reconnect | [Runtime.swift](Sources/MouseBindings/Runtime.swift) |
| Keyboard output and native Mission Control | [KeyboardOutput.swift](Sources/MouseBindings/KeyboardOutput.swift) |
| Native magnification output | [MagnificationOutput.swift](Sources/MouseBindings/MagnificationOutput.swift) |
| User config creation/loading and menu controls | [AppDelegate.swift](Sources/MouseBindings/AppDelegate.swift) |
| Inspector and bounded command-line diagnostics | [Inspector.swift](Sources/MouseBindings/Inspector.swift), [main.swift](Sources/MouseBindings/main.swift), [InputProbe.swift](Sources/MouseBindings/InputProbe.swift) |
| Private hardware ABI and Magic Mouse selection | [MultitouchBridge.c](Sources/MultitouchBridge/MultitouchBridge.c) |

## 2. Choose the smallest change

### Remap an existing gesture

Edit its entry inside the user's `bindings`, preserving other entries and top-level
settings. Use macOS virtual key codes `0…127` and the supported modifier strings
from `Configuration.validate()`. For example, change two-finger double-tap from
area capture to whole-screen capture:

```json
"twoFingerDoubleTap": { "keyCode": 20, "modifiers": ["shift", "command"] }
```

Remove an existing `action` property when replacing a native action with a keyboard
shortcut. Remove a binding to disable a discrete gesture; pinch is disabled with
the separate top-level `pinchEnabled` setting.

Save and select **Reload configuration**. A successful reload and manual action
check complete this branch; no rebuild is needed. Editing
`Configuration.bindings` changes **new-install defaults only**: existing user
files are loaded as saved and are not merged with defaults.

### Add a discrete gesture

1. Add a stable camelCase case to `Gesture` in `Configuration.swift`. Its raw string
   becomes a saved JSON key, so keep existing names compatible. Add a default
   binding only if requested; otherwise supply an opt-in config entry.
2. Implement recognition in `GestureEngine.update(_:at:)` for surface gestures,
   or `mouseDown(button:at:suppressClick:)` for physical clicks. Return the new
   `Gesture`; the existing runtime schedules ordinary outputs automatically.
3. Define when it fires and which input it owns. Follow the state contracts below
   so it does not also become a screenshot, lock, swipe, or pinch.
4. Add focused sequences to `Tests/GestureCoreTests`, then document how to perform
   the gesture and its config entry. Adding a name alone does not recognize it.
5. Add the mapping to an existing user's config only within their requested scope.
   Preserve removed TipTaps, logo bounds, and sensitivity settings.

For example, a requested three-finger **tap** needs a new gesture name and a
release-time rule for three brief stationary touches; the existing
`threeFingerClick` responds to a physical button press. Test staggered landing
and lifting, held fingers, pointer movement, and physical clicks to prove the
two inputs remain distinct.

### Add a native or mouse output action

For a one-shot action, extend `Shortcut.Action`, its validation, and the relevant
output handler. `KeyboardOutput.post` is the current path for keyboard shortcuts
and native Mission Control. Make the action's supported gestures and ignored
shortcut fields explicit, as the existing actions do.

For physical mouse rewriting, use `GestureEngine.ClickDisposition` and
`Runtime.handle` so the original down/drag/up are routed consistently. Command-click
is handled here, rather than generating a second synthetic click. If new mouse
event types are required, include them in the runtime event-tap mask and the probe
when relevant. Keep both left and right button sequences correct.

For continuous output, follow the existing pinch path: a recognizer emits a
phase and amount, the runtime queues it in input order, and an output object owns
the begin/end lifecycle. Read `pinchEvent` immediately after the engine update
that produced it. Use device callback cadence for normal output. Verify that
pause, reload, sleep, connection restart, and conflicting input terminate the
sequence before calling the feature complete.

Ordinary gesture changes belong above the hardware bridge. Modify the private
ABI only when hardware evidence demonstrates that it must change; update
[THIRD_PARTY.md](THIRD_PARTY.md) if using new external implementation references.

## Recognition and runtime contracts

- Match fingers by contact ID, not array order. IDs can change after lift;
  states `3` and `4` count as touching in `Runtime.receive`.
- Touch coordinates are normalized: X left `0` → right `1`, Y tail/logo `0` →
  front `1`. Timing uses monotonic uptime. Pure engine tests supply explicit time.
- `fired` prevents conflicting one-shot actions within a touch session. TipTap
  intentionally allows repeated taps with its resting anchor. Pinch owns its
  session until both fingers lift, even after ending/cancellation.
- Clear pending double-tap state when another gesture takes the touches. A
  physical click must not also count as a surface tap.
- Disabled features must release the input they would otherwise reserve. Test
  removal of a new binding as well as its enabled behavior. Swipe/pinch currently
  reserve two-finger scrolling; one-finger scrolling passes through.
- `clickDispositions` retains an accepted down/drag/up route across pause/reload.
  Clear a button's route on its matching up, rather than in `reset()`.
- Recognition also runs in the paused inspector. Execution is gated by runtime
  enablement, permissions, and `generation`. Keep queued actions from executing
  after pause/reconfiguration.
- Serialize engine access with the existing runtime lock. Queue AppKit/output
  work on the main queue; keep input callbacks short. The private bridge may
  wait for a callback when stopping, so stop it outside the engine lock.
- Validate new settings in `Configuration.validate()`. New optional Codable
  fields plus explicit runtime fallbacks keep old JSON readable. A property
  initializer alone does not supply a missing JSON decoding default.

## 3. Verify recognition and output separately

Run `swift test`. Extend the tests for the requested normal sequence, its nearest
existing conflict, disabled behavior, and reset/cancellation when relevant.
Preserve the recorded double-tap fixture regression. Passing these tests proves
recognition/filtering, not macOS delivery or physical-mouse usability.

When diagnosis needs hardware evidence, ask the user to perform a specific gesture
during a bounded capture. Quit the normal app first, then use the signed binary:

```sh
dist/MouseBindings.app/Contents/MacOS/MouseBindings --probe --seconds 10
dist/MouseBindings.app/Contents/MacOS/MouseBindings --probe-input --seconds 20
```

Run one command at a time. `--probe` reports raw touches; `--probe-input` reports
JSON lines for touches and mouse events without recording keys or sending actions.
Its raw format is not the same as the existing test fixture: normalize timestamps
and adapt fields before adding a focused replay test. Keep temporary recordings
in ignored `.build/`; commit only relevant, reviewed fixtures.

To isolate output from recognition, use `--test-shortcut <gestureName>` or
`--test-pinch in|out`. These **send actions**. Activate the intended app during
the printed delay and check the logged target. A successful post means an event
was sent, not that the target app accepted it. Confirm the visible result.

## 4. Build, activate, and report

For code changes, quit the running app before `./build.sh`, then reopen:

```sh
open dist/MouseBindings.app --args --paused --inspect
```

Use the existing signing identity and app path. Replacing developer signing with
ad-hoc signing can invalidate Accessibility approval. Config-only changes need
reload rather than a build. Source changes do not affect a running old binary.

Enable gestures for the manual check, activate the target app, and verify the
requested operation alongside normal click/drag/one-finger scroll and any nearby
gesture conflict. Reopen the user's normal app after standalone diagnostics.

Completion means tests pass, the intended source/config changes are active, and
the observed manual result is recorded. If manual verification needs the user,
state precisely what remains unverified and request that check. Update the README
for behavior/config changes and report which files changed, the tests run, and
the user's next operating step.
