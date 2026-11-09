import XCTest
@testable import GestureCore

final class PinchTests: XCTestCase {
    private func pair(_ distance: Double, y: Double = 0.6) -> [Contact] {
        [Contact(id: 1, x: 0.5 - distance / 2, y: y),
         Contact(id: 2, x: 0.5 + distance / 2, y: y)]
    }

    func testSpreadAndContractProduceContinuousReversibleZoom() {
        for direction in [1.0, -1.0] {
            let engine = GestureEngine()
            _ = engine.update(pair(0.4), at: 0)
            XCTAssertNil(engine.pinchEvent)
            _ = engine.update(pair(0.4 + direction * 0.05), at: 0.1)
            XCTAssertEqual(engine.pinchEvent, PinchEvent(phase: .began))
            _ = engine.update(pair(0.4 + direction * 0.1).reversed(), at: 0.12)
            XCTAssertEqual(engine.pinchEvent?.phase, .changed)
            XCTAssertEqual(engine.pinchEvent!.magnification,
                           (0.4 + direction * 0.1) / (0.4 + direction * 0.05) - 1, accuracy: 0.0001)
            _ = engine.update(pair(0.4 + direction * 0.06), at: 0.14)
            XCTAssertEqual(engine.pinchEvent?.phase, .changed)
            XCTAssertLessThan(engine.pinchEvent!.magnification * direction, 0)
            XCTAssertNil(engine.update([], at: 0.16))
            XCTAssertEqual(engine.pinchEvent, PinchEvent(phase: .ended))
            _ = engine.update([], at: 0.18)
            XCTAssertNil(engine.pinchEvent)
        }
    }

    func testJitterAndParallelSwipesDoNotBecomePinches() {
        let engine = GestureEngine()
        _ = engine.update(pair(0.4), at: 0)
        _ = engine.update(pair(0.42, y: 0.61), at: 0.03)
        XCTAssertNil(engine.pinchEvent)
        // A mostly parallel swipe may change spacing slightly.
        XCTAssertEqual(engine.update(pair(0.44, y: 0.7), at: 0.1), .swipeUp)
        XCTAssertNil(engine.pinchEvent)
        _ = engine.update(pair(0.6, y: 0.7), at: 0.12)
        XCTAssertNil(engine.pinchEvent) // Mission Control already owns this touch session.
    }

    func testPinchPreventsSwipeAndScreenshotUntilBothFingersLift() {
        let engine = GestureEngine()
        _ = engine.update(pair(0.4), at: 0)
        _ = engine.update(pair(0.45), at: 0.05)
        XCTAssertEqual(engine.pinchEvent?.phase, .began)
        XCTAssertNil(engine.update(pair(0.5, y: 0.8), at: 0.08))
        XCTAssertEqual(engine.pinchEvent?.phase, .changed)
        let remaining = pair(0.5)[0]
        XCTAssertNil(engine.update([remaining], at: 0.1))
        XCTAssertEqual(engine.pinchEvent?.phase, .ended)
        _ = engine.update(pair(0.4), at: 0.12)
        _ = engine.update(pair(0.6), at: 0.14)
        XCTAssertNil(engine.pinchEvent) // Replacing the lifted finger cannot restart zoom.
        XCTAssertNil(engine.update([], at: 0.16))
        _ = engine.update(pair(0.4), at: 0.2)
        XCTAssertNil(engine.update([], at: 0.3)) // This is a first tap, not a screenshot.
        _ = engine.update(pair(0.4), at: 0.4)
        _ = engine.update(pair(0.45), at: 0.45)
        XCTAssertEqual(engine.pinchEvent?.phase, .began) // A fresh session can zoom.
    }

    func testThirdOrReplacementFingerCancelsPinch() {
        for third in [true, false] {
            let engine = GestureEngine()
            _ = engine.update(pair(0.4), at: 0)
            _ = engine.update(pair(0.45), at: 0.05)
            let extra = Contact(id: 3, x: 0.8, y: 0.6)
            _ = engine.update(third ? pair(0.45) + [extra] : [pair(0.45)[0], extra], at: 0.08)
            XCTAssertEqual(engine.pinchEvent?.phase, .cancelled)
            _ = engine.update(pair(0.6), at: 0.1)
            XCTAssertNil(engine.pinchEvent)
            _ = engine.update([], at: 0.15)
            XCTAssertNil(engine.pinchEvent)
        }
    }

    func testClickBeforePinchKeepsCommandClickAndClickDuringPinchCancels() {
        for pinching in [true, false] {
            let engine = GestureEngine()
            _ = engine.update(pair(0.4), at: 0)
            if pinching { _ = engine.update(pair(0.45), at: 0.05) }
            XCTAssertEqual(engine.mouseDown(button: 0, at: 0.08), pinching ? nil : .twoFingerClick)
            XCTAssertEqual(engine.pinchEvent?.phase, pinching ? .cancelled : nil)
            XCTAssertEqual(engine.clickDisposition(button: 0), pinching ? .suppress : .commandLeft)
            _ = engine.update(pair(0.6), at: 0.1)
            XCTAssertNil(engine.pinchEvent)
            engine.reset()
            XCTAssertEqual(engine.clickDisposition(button: 0, ending: true), pinching ? .suppress : .commandLeft)
        }
    }

    func testResetAndReloadCancelActivePinch() {
        let engine = GestureEngine()
        for reload in [true, false] {
            _ = engine.update(pair(0.4), at: 0)
            _ = engine.update(pair(0.45), at: 0.05)
            if reload { engine.reconfigure(Configuration()) } else { engine.reset() }
            XCTAssertEqual(engine.pinchEvent?.phase, .cancelled)
            _ = engine.update(pair(0.6), at: 0.1)
            XCTAssertNil(engine.pinchEvent) // The first frame establishes a fresh baseline.
            engine.reset()
        }
    }

    func testPinchOnlyReservesTwoFingerScrollAndCanBeDisabled() {
        var config = Configuration()
        config.bindings.removeAll()
        let engine = GestureEngine(configuration: config)
        _ = engine.update(pair(0.4), at: 0)
        XCTAssertTrue(engine.suppressScroll(at: 0.01, momentum: 0, phase: 1))
        _ = engine.update([pair(0.4)[0]], at: 0.02)
        XCTAssertFalse(engine.suppressScroll(at: 0.03, momentum: 0, phase: 1))
        config.pinchEnabled = false
        engine.reconfigure(config)
        _ = engine.update(pair(0.4), at: 0.04)
        _ = engine.update(pair(0.6), at: 0.06)
        XCTAssertNil(engine.pinchEvent)
        XCTAssertFalse(engine.suppressScroll(at: 0.07, momentum: 0, phase: 1))
    }

    func testPinchConfigurationAndOlderConfigCompatibility() throws {
        var config = Configuration()
        for threshold in [0.0, -0.1, 1.1, Double.infinity] {
            config.pinchThreshold = threshold
            XCTAssertThrowsError(try config.validate())
        }
        config.pinchThreshold = 0.035
        for sensitivity in [0.0, -1, 6, Double.nan] {
            config.pinchSensitivity = sensitivity
            XCTAssertThrowsError(try config.validate())
        }
        config.pinchSensitivity = 1
        try config.validate()
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as! [String: Any]
        for field in ["pinchEnabled", "pinchThreshold", "pinchSensitivity"] { json.removeValue(forKey: field) }
        let old = try JSONDecoder().decode(Configuration.self, from: JSONSerialization.data(withJSONObject: json))
        try old.validate()
        XCTAssertNil(old.pinchEnabled) // Upgrading alone does not enable a new gesture.
    }
}
