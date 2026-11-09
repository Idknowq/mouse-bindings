import XCTest
@testable import GestureCore

final class GestureEngineTests: XCTestCase {
    private func contact(_ id: Int32, _ x: Double, _ y: Double) -> Contact { Contact(id: id, x: x, y: y) }

    func testBothVerticalSwipesFireOnceAndPreserveOneFingerScrolling() {
        for direction in [1.0, -1.0] {
            let engine = GestureEngine()
            XCTAssertNil(engine.update([contact(1, 0.3, 0.5), contact(2, 0.7, 0.5)], at: 0))
            XCTAssertTrue(engine.suppressScroll(at: 0.01, momentum: 0, phase: 1))
            XCTAssertEqual(engine.update([contact(1, 0.3, 0.5 + direction * 0.1), contact(2, 0.7, 0.5 + direction * 0.1)], at: 0.1),
                           direction > 0 ? .swipeUp : .swipeDown)
            XCTAssertNil(engine.update([contact(1, 0.3, 0.5), contact(2, 0.7, 0.5)], at: 0.15))
            XCTAssertNil(engine.update([], at: 0.2))
            XCTAssertTrue(engine.suppressScroll(at: 0.21, momentum: 0, phase: 4))
            XCTAssertTrue(engine.suppressScroll(at: 0.25, momentum: 1, phase: 0))
            XCTAssertTrue(engine.suppressScroll(at: 0.3, momentum: 3, phase: 0))
            XCTAssertNil(engine.update([contact(3, 0.3, 0.5)], at: 0.4))
            XCTAssertFalse(engine.suppressScroll(at: 0.45, momentum: 0, phase: 1))
        }
    }

    func testRestingFingerAndSideTapsDoNotTriggerOperations() {
        for left in [true, false] {
            let engine = GestureEngine()
            let resting = contact(1, left ? 0.7 : 0.3, 0.6)
            let tapped = contact(2, left ? 0.3 : 0.7, 0.6)
            XCTAssertNil(engine.update([resting], at: 0))
            for time in [0.3, 0.5] {
                XCTAssertNil(engine.update([tapped, resting], at: time))
                XCTAssertNil(engine.update([resting], at: time + 0.05))
                XCTAssertNil(engine.pinchEvent)
            }
            XCTAssertNil(engine.update([], at: 0.6))
        }
    }

    func testTwoFingerSwipeWorksAfterPointerMotionWhileFingersRemainDown() {
        for direction in [1.0, -1.0] {
            let engine = GestureEngine()
            _ = engine.update([contact(1, 0.3, 0.5), contact(2, 0.7, 0.5)], at: 0)
            engine.pointerMoved() // Slight mouse movement is independent of surface sliding.
            XCTAssertEqual(engine.update([contact(1, 0.3, 0.5 + direction * 0.1),
                                          contact(2, 0.7, 0.5 + direction * 0.1)], at: 0.1),
                           direction > 0 ? .swipeUp : .swipeDown)
        }
    }

    func testThreeFingerClickSwallowsMatchingUpEvenAfterReloadOrPause() {
        let engine = GestureEngine()
        _ = engine.update([contact(1, 0.2, 0.6), contact(2, 0.5, 0.6), contact(3, 0.8, 0.6)], at: 1)
        XCTAssertEqual(engine.mouseDown(button: 0, at: 1.1), .threeFingerClick)
        XCTAssertTrue(engine.clickDisposition(button: 0) == .suppress)
        XCTAssertEqual(engine.clickDisposition(button: 1, ending: true), .passthrough)
        engine.reconfigure(Configuration())
        XCTAssertEqual(engine.clickDisposition(button: 0, ending: true), .suppress)
        XCTAssertEqual(engine.clickDisposition(button: 0, ending: true), .passthrough)
    }

    func testStaleThreeFingerFrameCannotCloseWindow() {
        let engine = GestureEngine()
        _ = engine.update([contact(1, 0.2, 0.6), contact(2, 0.5, 0.6), contact(3, 0.8, 0.6)], at: 0)
        XCTAssertNil(engine.mouseDown(button: 0, at: 1))
        XCTAssertEqual(engine.clickDisposition(button: 0, ending: true), .passthrough)
    }

    func testReadOnlyInspectorDetectsThreeFingerClickWithoutSwallowingIt() {
        let engine = GestureEngine()
        _ = engine.update([contact(1, 0.2, 0.6), contact(2, 0.5, 0.6), contact(3, 0.8, 0.6)], at: 1)
        XCTAssertEqual(engine.mouseDown(button: 0, at: 1.1, suppressClick: false), .threeFingerClick)
        XCTAssertEqual(engine.clickDisposition(button: 0, ending: true), .passthrough)
    }

    func testOnlyShortStationaryLogoTapLocks() {
        let engine = GestureEngine()
        _ = engine.update([contact(1, 0.5, 0.2)], at: 0)
        XCTAssertEqual(engine.update([], at: 0.1), .logoTap)
        _ = engine.update([contact(1, 0.5, 0.2)], at: 1)
        XCTAssertNil(engine.update([], at: 2)) // Resting a finger is not a tap.
        _ = engine.update([contact(1, 0.5, 0.2)], at: 3)
        _ = engine.update([contact(1, 0.5, 0.3)], at: 3.05)
        XCTAssertNil(engine.update([], at: 3.1)) // A scroll is not a tap.
        _ = engine.update([contact(1, 0.1, 0.2)], at: 4)
        XCTAssertNil(engine.update([], at: 4.1))
        _ = engine.update([contact(1, 0.5, 0.2)], at: 5)
        engine.pointerMoved()
        XCTAssertNil(engine.update([], at: 5.1))
        _ = engine.update([contact(1, 0.5, 0.2)], at: 6)
        XCTAssertNil(engine.mouseDown(button: 0, at: 6.05))
        XCTAssertNil(engine.update([], at: 6.1)) // Physical click must not additionally lock.
    }

    func testDisabledBindingsDoNotSwallowNormalInput() {
        var config = Configuration()
        config.bindings.removeAll()
        config.pinchEnabled = false
        let engine = GestureEngine(configuration: config)
        _ = engine.update([contact(1, 0.3, 0.5), contact(2, 0.7, 0.5)], at: 0)
        XCTAssertFalse(engine.suppressScroll(at: 0.1, momentum: 0, phase: 1))
        XCTAssertNil(engine.update([contact(1, 0.3, 0.7), contact(2, 0.7, 0.7)], at: 0.2))
        _ = engine.update([contact(1, 0.2, 0.6), contact(2, 0.5, 0.6), contact(3, 0.8, 0.6)], at: 1)
        XCTAssertNil(engine.mouseDown(button: 0, at: 1.1))
        XCTAssertEqual(engine.clickDisposition(button: 0, ending: true), .passthrough)
    }

    func testBadConfigurationIsRejectedBeforeUse() throws {
        let original = Configuration()
        let decoded = try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(original))
        try decoded.validate()
        XCTAssertEqual(decoded.bindings.count, 6)
        var invalid = original
        invalid.logoRegion.minX = 0.9
        invalid.logoRegion.maxX = 0.1
        XCTAssertThrowsError(try invalid.validate())
        invalid = original
        invalid.bindings["logoTap"] = Shortcut(keyCode: 12, modifiers: ["typo"])
        XCTAssertThrowsError(try invalid.validate())
        invalid = original
        invalid.bindings["logoTap"] = Shortcut(keyCode: 0, modifiers: [], action: .commandClick)
        XCTAssertThrowsError(try invalid.validate())
        invalid = original
        invalid.doubleTapMaxStagger = .nan
        XCTAssertThrowsError(try invalid.validate())
        invalid = original
        invalid.doubleTapMaxPointerMovement = -1
        XCTAssertThrowsError(try invalid.validate())
    }

    private func twoFingerTap(_ engine: GestureEngine, at time: Double, id: Int32 = 1) -> Gesture? {
        _ = engine.update([contact(id, 0.3, 0.6)], at: time)
        _ = engine.update([contact(id, 0.3, 0.6), contact(id + 1, 0.7, 0.6)], at: time + 0.02)
        _ = engine.update([contact(id + 1, 0.7, 0.6)], at: time + 0.08)
        return engine.update([], at: time + 0.1)
    }

    func testDoubleTapAcceptsStaggeredLandingAndReleaseWithNewContactIDs() {
        let engine = GestureEngine(doubleTapInterval: 0.4)
        XCTAssertNil(twoFingerTap(engine, at: 0))
        XCTAssertEqual(twoFingerTap(engine, at: 0.25, id: 10), .twoFingerDoubleTap)
        XCTAssertNil(twoFingerTap(engine, at: 0.5, id: 20)) // A third tap is not another double-tap.
    }

    func testDoubleTapAcceptsNaturalFingerStagger() {
        for delay in [0.1, 0.15] {
            for leftFirst in [true, false] {
                let engine = GestureEngine()
                for (index, time) in [0.0, 0.3].enumerated() {
                    let first = contact(Int32(index * 2 + 1), leftFirst ? 0.3 : 0.7, 0.6)
                    let second = contact(Int32(index * 2 + 2), leftFirst ? 0.7 : 0.3, 0.6)
                    XCTAssertNil(engine.update([first], at: time))
                    XCTAssertNil(engine.update([first, second], at: time + delay))
                    XCTAssertNil(engine.update([second], at: time + 0.2))
                    XCTAssertEqual(engine.update([], at: time + 0.23), index == 0 ? nil : .twoFingerDoubleTap)
                }
            }
        }
    }

    func testDoubleTapStaggerLimitIsConfigurableAndRejectsSeparateTouches() {
        for limit in [0.08, 0.16] {
            var config = Configuration()
            config.doubleTapMaxStagger = limit
            let engine = GestureEngine(configuration: config)
            for time in [0.0, 0.3] {
                let first = contact(1, 0.3, 0.6)
                let second = contact(2, 0.7, 0.6)
                _ = engine.update([first], at: time)
                _ = engine.update([first, second], at: time + 0.2)
                XCTAssertNil(engine.update([], at: time + 0.23))
            }
        }
        var config = Configuration()
        config.doubleTapMaxStagger = 0.01
        let engine = GestureEngine(configuration: config)
        XCTAssertNil(twoFingerTap(engine, at: 0)) // Its 20 ms stagger exceeds the chosen 10 ms.
        XCTAssertNil(twoFingerTap(engine, at: 0.3))
    }

    func testDoubleTapUsesSystemIntervalAndClearsOnPauseOrReload() {
        let engine = GestureEngine(doubleTapInterval: 0.2)
        XCTAssertNil(twoFingerTap(engine, at: 0))
        XCTAssertNil(twoFingerTap(engine, at: 0.5)) // Too late: becomes a new first tap.
        engine.reset()
        XCTAssertNil(twoFingerTap(engine, at: 0.65))
        engine.reconfigure(Configuration())
        XCTAssertNil(twoFingerTap(engine, at: 0.8))
        XCTAssertEqual(twoFingerTap(engine, at: 0.95), .twoFingerDoubleTap)
    }

    func testHeldMovingAndPointerMovingTouchesCannotStartDoubleTap() {
        for mode in 0..<3 {
            let engine = GestureEngine()
            _ = engine.update([contact(1, 0.3, 0.6), contact(2, 0.7, 0.6)], at: 0)
            if mode == 1 {
                _ = engine.update([contact(1, 0.35, 0.6), contact(2, 0.75, 0.6)], at: 0.05)
            } else if mode == 2 { engine.pointerMoved() }
            XCTAssertNil(engine.update([], at: mode == 0 ? 0.3 : 0.1))
            XCTAssertNil(twoFingerTap(engine, at: 0.35))
        }
    }

    func testPhysicalClickCannotCompletePendingDoubleTap() {
        let engine = GestureEngine()
        XCTAssertNil(twoFingerTap(engine, at: 0))
        _ = engine.update([contact(1, 0.3, 0.6), contact(2, 0.7, 0.6)], at: 0.2)
        XCTAssertEqual(engine.mouseDown(button: 0, at: 0.25), .twoFingerClick)
        XCTAssertEqual(engine.clickDisposition(button: 0, ending: true), .commandLeft)
        XCTAssertNil(engine.update([], at: 0.3))
        XCTAssertNil(twoFingerTap(engine, at: 0.4))
    }

    func testSwipesAndSingleFingerTapClearPendingDoubleTap() {
        for swipe in [true, false] {
            let engine = GestureEngine()
            XCTAssertNil(twoFingerTap(engine, at: 0))
            if swipe {
                _ = engine.update([contact(1, 0.3, 0.5), contact(2, 0.7, 0.5)], at: 0.2)
                XCTAssertEqual(engine.update([contact(1, 0.3, 0.65), contact(2, 0.7, 0.65)], at: 0.25), .swipeUp)
            } else { _ = engine.update([contact(1, 0.1, 0.6)], at: 0.2) }
            XCTAssertNil(engine.update([], at: 0.3))
            XCTAssertNil(twoFingerTap(engine, at: 0.4))
        }
    }

    func testTwoFingerClickRoutesLeftAndRightInputThroughLiftAndReset() {
        for button in [0, 1] {
            let engine = GestureEngine()
            _ = engine.update([contact(1, 0.3, 0.6), contact(2, 0.7, 0.6)], at: 0)
            XCTAssertEqual(engine.mouseDown(button: button, at: 0.1), .twoFingerClick)
            XCTAssertEqual(engine.clickDisposition(button: button), .commandLeft)
            XCTAssertNil(engine.update([], at: 0.2))
            engine.reconfigure(Configuration())
            XCTAssertEqual(engine.clickDisposition(button: button), .commandLeft)
            XCTAssertEqual(engine.clickDisposition(button: 1 - button, ending: true), .passthrough)
            XCTAssertEqual(engine.clickDisposition(button: button, ending: true), .commandLeft)
            XCTAssertEqual(engine.clickDisposition(button: button, ending: true), .passthrough)
        }
    }

    func testTwoFingerPhysicalClickCanUseAKeyboardBindingInstead() {
        var config = Configuration()
        config.bindings["twoFingerClick"] = Shortcut(keyCode: 13, modifiers: ["command"])
        let engine = GestureEngine(configuration: config)
        _ = engine.update([contact(1, 0.3, 0.6), contact(2, 0.7, 0.6)], at: 0)
        XCTAssertEqual(engine.mouseDown(button: 0, at: 0.1), .twoFingerClick)
        XCTAssertEqual(engine.clickDisposition(button: 0), .suppress)
        XCTAssertEqual(engine.clickDisposition(button: 0, ending: true), .suppress)
    }

    func testRestingFingersCanCommandClickRepeatedlyWithoutLifting() {
        let engine = GestureEngine()
        let contacts = [contact(1, 0.3, 0.6), contact(2, 0.7, 0.6)]
        _ = engine.update(contacts, at: 0)
        XCTAssertEqual(engine.mouseDown(button: 0, at: 0.1), .twoFingerClick)
        XCTAssertEqual(engine.clickDisposition(button: 0, ending: true), .commandLeft)
        _ = engine.update(contacts, at: 0.3)
        XCTAssertEqual(engine.mouseDown(button: 0, at: 0.4), .twoFingerClick)
        XCTAssertEqual(engine.clickDisposition(button: 0, ending: true), .commandLeft)
        XCTAssertNil(engine.update([], at: 0.45))
    }

    func testOrdinaryStaleDisabledAndInspectorClicksStayUnmodified() {
        for mode in 0..<4 {
            var config = Configuration()
            if mode == 2 { config.bindings.removeValue(forKey: "twoFingerClick") }
            let engine = GestureEngine(configuration: config)
            _ = engine.update(mode == 0 ? [contact(1, 0.3, 0.6)] :
                [contact(1, 0.3, 0.6), contact(2, 0.7, 0.6)], at: 0)
            XCTAssertEqual(engine.mouseDown(button: 0, at: mode == 1 ? 1 : 0.1, suppressClick: mode != 3),
                           mode == 3 ? .twoFingerClick : nil)
            XCTAssertEqual(engine.clickDisposition(button: 0), .passthrough)
            XCTAssertEqual(engine.clickDisposition(button: 0, ending: true), .passthrough)
        }
    }

    func testDisabledDoubleTapDoesNotRecognize() {
        var config = Configuration()
        config.bindings.removeValue(forKey: "twoFingerDoubleTap")
        let engine = GestureEngine(configuration: config)
        XCTAssertNil(twoFingerTap(engine, at: 0))
        XCTAssertNil(twoFingerTap(engine, at: 0.2))
    }

    func testRecordedDoubleTapsWithZeroMotionAndPointerJitter() throws {
        let url = Bundle.module.url(forResource: "double-tap-pointer-motion", withExtension: "json", subdirectory: "Fixtures")!
        let traces = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [[String: Any]]
        for trace in traces {
            let engine = GestureEngine()
            var gestures: [Gesture] = []
            for event in trace["events"] as! [[String: Any]] {
                let time = event["time"] as! Double
                if event["kind"] as! String == "mouse" {
                    let distance = event["distance"] as! Double
                    engine.pointerMoved(distance: distance)
                } else {
                    let contacts = (event["contacts"] as! [[String: Any]]).filter {
                        let state = ($0["state"] as! NSNumber).intValue
                        return state == 3 || state == 4
                    }.map {
                        contact(($0["id"] as! NSNumber).int32Value, ($0["x"] as! NSNumber).doubleValue,
                                ($0["y"] as! NSNumber).doubleValue)
                    }
                    if let gesture = engine.update(contacts, at: time) { gestures.append(gesture) }
                    XCTAssertNil(engine.pinchEvent, trace["name"] as! String)
                }
            }
            XCTAssertEqual(gestures, [.twoFingerDoubleTap], trace["name"] as! String)
        }
    }

    func testDoubleTapPointerBudgetIncludesBothTapsAndTheGap() {
        let engine = GestureEngine()
        let contacts = [contact(1, 0.3, 0.6), contact(2, 0.7, 0.6)]
        _ = engine.update(contacts, at: 0)
        engine.pointerMoved(distance: 3)
        XCTAssertNil(engine.update([], at: 0.1))
        engine.pointerMoved(distance: 4)
        _ = engine.update(contacts, at: 0.2)
        engine.pointerMoved(distance: 2) // Nine pixels in total exceeds the eight-pixel budget.
        XCTAssertNil(engine.update([], at: 0.3))
    }

    func testIntentionalPointerMovementCancelsDoubleTapDuringAndBetweenTaps() {
        for during in [true, false] {
            let engine = GestureEngine()
            let contacts = [contact(1, 0.3, 0.6), contact(2, 0.7, 0.6)]
            _ = engine.update(contacts, at: 0)
            if during { engine.pointerMoved(distance: 9) }
            XCTAssertNil(engine.update([], at: 0.1))
            if !during { engine.pointerMoved(distance: 9) }
            XCTAssertNil(twoFingerTap(engine, at: 0.2))
        }
    }

    func testLogoTapStillRejectsRealPointerMovementAndIgnoresZeroEvents() {
        for distance in [0.0, 1.0] {
            let engine = GestureEngine()
            _ = engine.update([contact(1, 0.5, 0.2)], at: 0)
            engine.pointerMoved(distance: distance)
            XCTAssertEqual(engine.update([], at: 0.1), distance == 0 ? .logoTap : nil)
        }
    }

    func testDoubleTapPointerToleranceIsConfigurable() {
        var config = Configuration()
        config.doubleTapMaxPointerMovement = 0
        let engine = GestureEngine(configuration: config)
        _ = engine.update([contact(1, 0.3, 0.6), contact(2, 0.7, 0.6)], at: 0)
        engine.pointerMoved(distance: 1)
        XCTAssertNil(engine.update([], at: 0.1))
        XCTAssertNil(twoFingerTap(engine, at: 0.2))
    }
}
