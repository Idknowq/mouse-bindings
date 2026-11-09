# Magic Mouse tool plan

Build a small native Swift menu-bar app for this Mac and USB-C Magic Mouse.

1. Read finger IDs and positions through an isolated MultitouchSupport bridge; provide a read-only touch inspector.
2. Recognize two-finger vertical swipes, left/right TipTap, three-finger physical click, and a tap above the Apple logo.
3. Send the requested shortcuts; suppress the original three-finger click and two-finger scroll. Both swipe directions toggle native Mission Control.
4. Add Pause, permissions, configuration reload, and Quit. Store bindings and calibration thresholds in JSON.
5. Build a local `.app`, test recognition/filtering with recorded-style input sequences, then calibrate on the actual mouse.

Keep processing callback-driven. No network service, keyboard driver, or broad settings UI. Reconnect after Bluetooth loss and Mac wake. Private API compatibility and real-device calibration remain limitations until tested.

## Native pinch zoom

1. Verify a native magnification sequence in Chrome independently of recognition.
2. Track two contact IDs and their separation. Spread zooms in; contraction zooms out. Ignore small jitter and prefer vertical translation for Mission Control.
3. Send begin/change/end events at the touch callback cadence. End on finger lift; cancel on click, a third/replaced finger, pause, reload, sleep, or connection restart.
4. Preserve existing bindings and calibration. Add an enable switch, start threshold, and sensitivity to JSON; show pinch activity in the inspector.
5. Run gesture conflict tests, rebuild with stable signing, then verify the physical gesture on the mouse.

Use the existing menu-bar app and input pipeline. No zoom animation timer,
keyboard zoom fallback, or new dependency is needed for normal operation.

Implemented and signed on 2026-11-06. All 36 recognizer/filter tests pass,
including recorded double-taps with pinch enabled. macOS converts the generated
packet into an `NSEvent` magnification with the expected phase and amount.
Visible Chrome zoom and physical-mouse calibration still need confirmation;
automated foreground activation did not succeed during output testing.
