import Foundation

public enum Gesture: String, Codable, CaseIterable {
    case swipeUp, swipeDown, tipTapLeft, tipTapRight, twoFingerClick, twoFingerDoubleTap, threeFingerClick, logoTap
}

public struct Shortcut: Codable, Equatable {
    public var keyCode: UInt16
    public var modifiers: [String]
    public var action: Action?

    public enum Action: String, Codable { case missionControl, commandClick }

    public init(keyCode: UInt16, modifiers: [String], action: Action? = nil) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.action = action
    }
}

public struct Region: Codable {
    public var minX: Double = 0.35
    public var maxX: Double = 0.65
    public var minY: Double = 0.12
    public var maxY: Double = 0.32
    public init() {}

    public func contains(_ contact: Contact) -> Bool {
        (minX...maxX).contains(contact.x) && (minY...maxY).contains(contact.y)
    }
}

public struct Configuration: Codable {
    public var tapMaxDuration: Double = 0.25
    public var tapMaxMovement: Double = 0.035
    // Optional so configurations created before this setting remain readable.
    public var doubleTapMaxStagger: Double?
    public var doubleTapMaxPointerMovement: Double?
    public var pinchEnabled: Bool? = true
    public var pinchThreshold: Double?
    public var pinchSensitivity: Double?
    public var restingMinDuration: Double = 0.12
    public var swipeDistance: Double = 0.08
    public var logoRegion = Region()
    public var bindings: [String: Shortcut] = [
        Gesture.swipeUp.rawValue: Shortcut(keyCode: 126, modifiers: ["control"], action: .missionControl),
        Gesture.swipeDown.rawValue: Shortcut(keyCode: 126, modifiers: ["control"], action: .missionControl),
        Gesture.tipTapLeft.rawValue: Shortcut(keyCode: 123, modifiers: ["option", "command"]),
        Gesture.tipTapRight.rawValue: Shortcut(keyCode: 124, modifiers: ["option", "command"]),
        Gesture.twoFingerClick.rawValue: Shortcut(keyCode: 0, modifiers: ["command"], action: .commandClick),
        Gesture.twoFingerDoubleTap.rawValue: Shortcut(keyCode: 21, modifiers: ["shift", "command"]),
        Gesture.threeFingerClick.rawValue: Shortcut(keyCode: 13, modifiers: ["command"]),
        Gesture.logoTap.rawValue: Shortcut(keyCode: 12, modifiers: ["control", "command"])
    ]

    public init() {}
    public func shortcut(for gesture: Gesture) -> Shortcut? { bindings[gesture.rawValue] }

    public func validate() throws {
        let thresholds = [tapMaxDuration, tapMaxMovement, restingMinDuration, swipeDistance] +
            [doubleTapMaxStagger].compactMap { $0 }
        guard thresholds.allSatisfy({ $0.isFinite && $0 > 0 && $0 <= 1 }),
              restingMinDuration <= tapMaxDuration,
              [logoRegion.minX, logoRegion.maxX, logoRegion.minY, logoRegion.maxY]
                .allSatisfy({ $0.isFinite && (0...1).contains($0) }),
              logoRegion.minX < logoRegion.maxX, logoRegion.minY < logoRegion.maxY else {
            throw ConfigurationError.invalid("Thresholds must be between 0 and 1; logo bounds must form a rectangle within 0…1.")
        }
        if let movement = doubleTapMaxPointerMovement, !movement.isFinite || movement < 0 {
            throw ConfigurationError.invalid("doubleTapMaxPointerMovement must be a finite, non-negative distance.")
        }
        if let threshold = pinchThreshold, !threshold.isFinite || threshold <= 0 || threshold > 1 {
            throw ConfigurationError.invalid("pinchThreshold must be between 0 and 1.")
        }
        if let sensitivity = pinchSensitivity, !sensitivity.isFinite || sensitivity <= 0 || sensitivity > 5 {
            throw ConfigurationError.invalid("pinchSensitivity must be between 0 and 5.")
        }
        let modifiers = Set(["command", "option", "control", "shift"])
        for (name, shortcut) in bindings {
            guard Gesture(rawValue: name) != nil, shortcut.keyCode < 128,
                  shortcut.modifiers.allSatisfy(modifiers.contains) else {
                throw ConfigurationError.invalid("Invalid binding '\(name)'. Use a known gesture, keyCode 0…127, and command/option/control/shift modifiers.")
            }
            if shortcut.action == .commandClick && name != Gesture.twoFingerClick.rawValue {
                throw ConfigurationError.invalid("commandClick is supported only for twoFingerClick.")
            }
        }
    }
}

public enum ConfigurationError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? {
        switch self { case .invalid(let message): return message }
    }
}
