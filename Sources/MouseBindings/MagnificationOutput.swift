import AppKit
import CoreGraphics
import GestureCore

final class MagnificationOutput {
    private let source = CGEventSource(stateID: .privateState)
    private var anchor: CGPoint?
    private(set) var targetName = "front app"

    @discardableResult
    func post(_ update: PinchEvent) -> Bool {
        if update.phase == .began {
            anchor = CGEvent(source: nil)?.location
            targetName = NSWorkspace.shared.frontmostApplication?.localizedName ?? "front app"
        }
        guard let anchor, let event = CGEvent(source: source) else { return false }
        event.location = anchor
        event.flags = []
        // Undocumented Quartz gesture fields: native magnification, not wheel/key zoom.
        event.type = CGEventType(rawValue: 29)!
        event.setIntegerValueField(CGEventField(rawValue: 110)!, value: 8)
        event.setIntegerValueField(CGEventField(rawValue: 132)!, value: update.phase.rawValue)
        event.setDoubleValueField(CGEventField(rawValue: 113)!, value: update.magnification)
        event.post(tap: .cghidEventTap)
        if update.phase == .ended || update.phase == .cancelled { self.anchor = nil }
        return true
    }

    func cancel() {
        if anchor != nil { post(PinchEvent(phase: .cancelled)) }
    }
}
