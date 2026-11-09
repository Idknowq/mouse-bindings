import CoreGraphics
import AppKit
import GestureCore

enum KeyboardOutput {
    static func post(_ shortcut: Shortcut, target: pid_t? = nil) -> Bool {
        // Command-click is handled in the event tap to retain the physical click pair.
        if shortcut.action == .commandClick { return false }
        if shortcut.action == .missionControl {
            let options = NSWorkspace.OpenConfiguration()
            options.activates = false
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Mission Control.app"),
                                               configuration: options) { _, error in
                if let error { NSLog("Mission Control: %@", error.localizedDescription) }
            }
            return true
        }
        let modifiers: [String: CGEventFlags] = ["command": .maskCommand, "option": .maskAlternate,
                                               "control": .maskControl, "shift": .maskShift]
        let flags = shortcut.modifiers.reduce(CGEventFlags()) { $0.union(modifiers[$1]!) }
        let source = CGEventSource(stateID: .privateState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: false) else { return false }
        down.flags = flags; up.flags = flags
        if let target {
            down.postToPid(target); up.postToPid(target)
        } else {
            down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
        }
        return true
    }
}
