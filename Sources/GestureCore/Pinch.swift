import Foundation

public struct PinchEvent: Equatable {
    public enum Phase: Int64 { case began = 1, changed = 2, ended = 4, cancelled = 8 }
    public let phase: Phase
    public let magnification: Double

    public init(phase: Phase, magnification: Double = 0) {
        self.phase = phase
        self.magnification = magnification
    }
}

// One pair owns a pinch until both fingers lift. Device callbacks supply the cadence.
final class PinchRecognizer {
    private var origins: [Int32: Contact] = [:]
    private var lastDistance: Double = 0
    private var active = false
    private var blocked = false
    private(set) var ownsTouches = false

    func reset() -> PinchEvent? {
        let ending = active ? PinchEvent(phase: .cancelled) : nil
        origins.removeAll(); active = false; blocked = false; ownsTouches = false
        return ending
    }

    func cancel() -> PinchEvent? {
        let ending = active ? PinchEvent(phase: .cancelled) : nil
        active = false; blocked = true
        return ending
    }

    func update(_ contacts: [Contact], configuration: Configuration, canBegin: Bool) -> PinchEvent? {
        if contacts.isEmpty {
            let ending = active ? PinchEvent(phase: .ended) : nil
            _ = reset()
            return ending
        }
        guard configuration.pinchEnabled == true else { return reset() }
        guard !blocked else { return nil }
        guard contacts.count == 2 else {
            if active {
                let ending = cancel()
                return contacts.count == 1 ? PinchEvent(phase: .ended) : ending
            }
            origins.removeAll()
            return nil
        }
        let first = contacts[0], second = contacts[1]
        // A small floor handles fingers meeting without dividing by zero or amplifying noise.
        let distance = max(0.05, hypot(first.x - second.x, first.y - second.y))
        guard let startFirst = origins[first.id], let startSecond = origins[second.id] else {
            if active { return cancel() } // Never join a replacement contact to an ongoing pinch.
            origins = [first.id: first, second.id: second]
            lastDistance = distance
            return nil
        }
        if active {
            let amount = pow(distance / lastDistance, configuration.pinchSensitivity ?? 1) - 1
            lastDistance = distance
            return amount == 0 ? nil : PinchEvent(phase: .changed, magnification: amount)
        }
        let initialDistance = max(0.05, hypot(startFirst.x - startSecond.x, startFirst.y - startSecond.y))
        let separationChange = abs(distance - initialDistance)
        let centerMovement = hypot((first.x + second.x - startFirst.x - startSecond.x) / 2,
                                   (first.y + second.y - startFirst.y - startSecond.y) / 2)
        guard canBegin, separationChange >= (configuration.pinchThreshold ?? 0.035),
              separationChange > centerMovement * 1.5 else { return nil }
        active = true; ownsTouches = true
        lastDistance = distance // Begin at zero; subsequent frames zoom without an initial jump.
        return PinchEvent(phase: .began)
    }
}
