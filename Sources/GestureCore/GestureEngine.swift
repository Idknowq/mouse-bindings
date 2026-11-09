import Foundation

public struct Contact: Equatable {
    public let id: Int32
    public let x: Double
    public let y: Double
    public init(id: Int32, x: Double, y: Double) { self.id = id; self.x = x; self.y = y }
}

// Pure recognizer/filter state. The app serializes access across input callbacks.
public final class GestureEngine {
    public enum ClickDisposition { case passthrough, suppress, commandLeft }
    public private(set) var configuration: Configuration
    public private(set) var pinchEvent: PinchEvent?
    private let pinch = PinchRecognizer()
    private let doubleTapInterval: Double
    private struct Track {
        var start: Contact
        var latest: Contact
        var began: Double
        var movement: Double = 0
        var invalidTap = false
        var lastPointerMotion = -Double.infinity
    }
    private struct TipTap {
        var anchor: Int32
        var tapped: Int32
        var gesture: Gesture
    }
    private var tracks: [Int32: Track] = [:]
    private var tipTap: TipTap?
    private var swipeOrigins: [Int32: Contact] = [:]
    private var peakCount = 0
    private var fired = false
    private var lastFrameTime = -Double.infinity
    private var clickDispositions: [Int: ClickDisposition] = [:]
    private var tapBegan: Double = 0
    private var releasedTapCount = 0
    private var sessionTapValid = true
    private var pendingTwoFingerTap: Double?
    private var sessionPointerMovement: Double = 0
    private var pendingPointerMovement: Double = 0
    private var capturedScroll = false
    private var lastSuppressedScroll = -Double.infinity

    public init(configuration: Configuration = Configuration(), doubleTapInterval: Double = 0.5) {
        self.configuration = configuration
        self.doubleTapInterval = doubleTapInterval
    }

    public func reconfigure(_ value: Configuration) {
        configuration = value
        reset()
    }

    public func reset() {
        pinchEvent = pinch.reset()
        tracks.removeAll(); tipTap = nil; swipeOrigins.removeAll()
        peakCount = 0; fired = false; lastFrameTime = -Double.infinity
        capturedScroll = false
        releasedTapCount = 0; sessionTapValid = true; pendingTwoFingerTap = nil
        sessionPointerMovement = 0; pendingPointerMovement = 0
        // Finish already routed down/drag/up pairs even after pause or reload.
    }

    public func update(_ contacts: [Contact], at time: Double) -> Gesture? {
        let previous = tracks
        let ids = Set(contacts.map(\.id))
        // Fresh contacts end a previous gesture's momentum suppression.
        if previous.isEmpty && !contacts.isEmpty {
            capturedScroll = false
            tapBegan = time
            sessionPointerMovement = 0
        }
        lastFrameTime = time
        peakCount = max(peakCount, contacts.count)
        for contact in contacts {
            if var track = tracks[contact.id] {
                track.latest = contact
                track.movement = max(track.movement, hypot(contact.x - track.start.x, contact.y - track.start.y))
                tracks[contact.id] = track
            } else {
                tracks[contact.id] = Track(start: contact, latest: contact, began: time)
            }
        }

        pinchEvent = pinch.update(contacts, configuration: configuration, canBegin: !fired)
        if pinch.ownsTouches || pinchEvent != nil {
            fired = true; sessionTapValid = false; pendingTwoFingerTap = nil; tipTap = nil
        }

        if previous.count == 1, contacts.count == 2, let anchor = previous.values.first,
           ids.contains(anchor.start.id), time - anchor.began >= configuration.restingMinDuration,
           anchor.movement <= configuration.tapMaxMovement,
           time - anchor.lastPointerMotion >= configuration.restingMinDuration,
           let tapped = contacts.first(where: { $0.id != anchor.start.id }),
           abs(tapped.x - anchor.latest.x) > 0.08,
           configuration.shortcut(for: tapped.x < anchor.latest.x ? .tipTapLeft : .tipTapRight) != nil {
            tipTap = TipTap(anchor: anchor.start.id, tapped: tapped.id,
                            gesture: tapped.x < anchor.latest.x ? .tipTapLeft : .tipTapRight)
            sessionTapValid = false
        }

        if contacts.count == 2, let first = tracks[contacts[0].id], let second = tracks[contacts[1].id] {
            if abs(first.began - second.began) > (configuration.doubleTapMaxStagger ?? 0.16) {
                sessionTapValid = false
            }
        }
        for track in tracks.values where !ids.contains(track.start.id) {
            releasedTapCount += 1
            sessionTapValid = sessionTapValid && isSurfaceTap(track, at: time)
        }

        var result: Gesture?
        if !fired, peakCount == 2, let chord = tipTap,
           !ids.contains(chord.tapped), ids.contains(chord.anchor),
           let tap = tracks[chord.tapped], let anchor = tracks[chord.anchor],
           isTap(tap, at: time),
           anchor.movement <= configuration.tapMaxMovement {
            result = chord.gesture
        }
        if !fired, contacts.isEmpty, peakCount == 1, let tap = previous.values.first,
           isTap(tap, at: time), configuration.logoRegion.contains(tap.start) {
            result = .logoTap
        }
        if contacts.isEmpty && !previous.isEmpty {
            if !fired, peakCount == 2, releasedTapCount == 2, sessionTapValid,
               sessionPointerMovement <= (configuration.doubleTapMaxPointerMovement ?? 8),
               configuration.shortcut(for: .twoFingerDoubleTap) != nil {
                if let firstTap = pendingTwoFingerTap, tapBegan - firstTap <= doubleTapInterval {
                    result = .twoFingerDoubleTap
                    pendingTwoFingerTap = nil
                } else {
                    pendingTwoFingerTap = tapBegan
                    pendingPointerMovement = sessionPointerMovement
                }
            } else { pendingTwoFingerTap = nil }
        }
        tracks = tracks.filter { ids.contains($0.key) }

        if contacts.count == 2 && peakCount == 2 {
            if swipeOrigins.isEmpty { swipeOrigins = Dictionary(uniqueKeysWithValues: contacts.map { ($0.id, $0) }) }
            if !fired, result == nil, swipeOrigins.count == 2,
               contacts.allSatisfy({ swipeOrigins[$0.id] != nil }) {
                let dy = contacts.map { $0.y - swipeOrigins[$0.id]!.y }
                let mostlyVertical = contacts.allSatisfy {
                    abs($0.x - swipeOrigins[$0.id]!.x) < configuration.swipeDistance
                }
                if mostlyVertical && dy.allSatisfy({ $0 >= configuration.swipeDistance }) { result = .swipeUp }
                if mostlyVertical && dy.allSatisfy({ $0 <= -configuration.swipeDistance }) { result = .swipeDown }
            }
        } else { swipeOrigins.removeAll() }

        if let gesture = result, configuration.shortcut(for: gesture) != nil {
            fired = true
            pendingTwoFingerTap = nil
            if gesture == .tipTapLeft || gesture == .tipTapRight {
                tipTap = nil
                fired = false // The resting finger can anchor successive TipTaps.
            }
        } else { result = nil }
        if contacts.isEmpty {
            peakCount = 0; fired = false; tipTap = nil
            releasedTapCount = 0; sessionTapValid = true
            sessionPointerMovement = 0
        }
        return result
    }

    private func isTap(_ track: Track, at time: Double) -> Bool {
        !track.invalidTap && isSurfaceTap(track, at: time)
    }

    private func isSurfaceTap(_ track: Track, at time: Double) -> Bool {
        time - track.began <= configuration.tapMaxDuration &&
        track.movement <= configuration.tapMaxMovement
    }

    public func pointerMoved(at time: Double? = nil, distance: Double? = nil) {
        // Unmeasured motion (including a physical click) retains strict cancellation.
        let movement = distance ?? .infinity
        guard movement > 0 else { return }
        if !tracks.isEmpty { sessionPointerMovement += movement }
        if pendingTwoFingerTap != nil {
            pendingPointerMovement += movement
            if pendingPointerMovement > (configuration.doubleTapMaxPointerMovement ?? 8) {
                pendingTwoFingerTap = nil
            }
        }
        for id in Array(tracks.keys) {
            tracks[id]?.invalidTap = true
            tracks[id]?.lastPointerMotion = time ?? lastFrameTime
        }
    }

    // Physical clicks reserve the matching drag/up, independently of later touch frames.
    public func mouseDown(button: Int, at time: Double, suppressClick: Bool = true) -> Gesture? {
        let pinchOwned = pinch.ownsTouches
        pinchEvent = pinch.cancel()
        if pinchOwned {
            pointerMoved()
            if suppressClick { clickDispositions[button] = .suppress }
            return nil
        }
        let gesture: Gesture? = tracks.count == 2 ? .twoFingerClick : tracks.count == 3 ? .threeFingerClick : nil
        let fresh = time - lastFrameTime < 0.3
        pointerMoved() // A physical click cannot also become a touch tap.
        if fresh, let gesture, let shortcut = configuration.shortcut(for: gesture) {
            fired = true
            if suppressClick {
                clickDispositions[button] = shortcut.action == .commandClick ? .commandLeft : .suppress
            }
            return gesture
        }
        return nil
    }

    public func clickDisposition(button: Int, ending: Bool = false) -> ClickDisposition {
        if ending { return clickDispositions.removeValue(forKey: button) ?? .passthrough }
        return clickDispositions[button] ?? .passthrough
    }

    public func suppressScroll(at time: Double, momentum: Int64, phase: Int64) -> Bool {
        let twoFingerBinding = configuration.shortcut(for: .swipeUp) != nil ||
            configuration.shortcut(for: .swipeDown) != nil || configuration.pinchEnabled == true
        let candidate = tracks.count == 2 && peakCount == 2 && time - lastFrameTime < 0.3 && twoFingerBinding
        // Tail events can arrive after the fingers lift. A new scroll begin or a
        // new one-finger contact starts a normal scroll again.
        let tail = capturedScroll && tracks.isEmpty && time - lastSuppressedScroll < 0.5 && phase != 1
        guard candidate || tail else { capturedScroll = false; return false }
        capturedScroll = true
        lastSuppressedScroll = time
        // An ended finger-scroll can be followed by a momentum begin.
        if momentum == 3 || phase == 8 { capturedScroll = false }
        return true
    }
}
