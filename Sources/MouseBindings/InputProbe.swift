import AppKit
import ApplicationServices
import MultitouchBridge

// Bounded, read-only diagnosis of touch frames and mouse events. No key events.
final class InputProbe {
    private let lock = NSLock()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    private func record(_ value: [String: Any]) {
        lock.lock(); defer { lock.unlock() }
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: .sortedKeys),
              let line = String(data: data, encoding: .utf8) else { return }
        print(line)
        fflush(stdout)
    }

    func run(seconds: Double) -> Bool {
        let context = Unmanaged.passUnretained(self).toOpaque()
        let types: [CGEventType] = [.mouseMoved, .leftMouseDragged, .rightMouseDragged,
                                    .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .scrollWheel]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                               options: .listenOnly, eventsOfInterest: mask, callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let probe = Unmanaged<InputProbe>.fromOpaque(context).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                probe.record(["kind": "gap", "time": ProcessInfo.processInfo.systemUptime])
                if let tap = probe.tap { CGEvent.tapEnable(tap: tap, enable: true) }
            } else {
                probe.record(["kind": "mouse", "time": ProcessInfo.processInfo.systemUptime,
                    "type": type.rawValue,
                    "dx": event.getIntegerValueField(.mouseEventDeltaX),
                    "dy": event.getIntegerValueField(.mouseEventDeltaY),
                    "phase": event.getIntegerValueField(.scrollWheelEventScrollPhase),
                    "momentum": event.getIntegerValueField(.scrollWheelEventMomentumPhase)])
            }
            return Unmanaged.passUnretained(event)
        }, userInfo: context)
        guard let tap else {
            fputs("Cannot monitor mouse events with this build's current permissions.\n", stderr)
            return false
        }
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
        CGEvent.tapEnable(tap: tap, enable: true)
        let started = MBStart({ contacts, count, _, context in
            guard let context else { return }
            let probe = Unmanaged<InputProbe>.fromOpaque(context).takeUnretainedValue()
            let raw = contacts.map { Array(UnsafeBufferPointer(start: $0, count: Int(count))) } ?? []
            probe.record(["kind": "touch", "time": ProcessInfo.processInfo.systemUptime,
                "contacts": raw.map { ["id": $0.identifier, "state": $0.state,
                                        "x": $0.x, "y": $0.y] as [String: Any] }])
        }, context)
        defer {
            MBStop()
            if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
            CFMachPortInvalidate(tap)
        }
        guard started else {
            fputs("\(String(cString: MBLastError()))\n", stderr)
            return false
        }
        record(["kind": "start", "time": ProcessInfo.processInfo.systemUptime,
                "seconds": seconds, "doubleTapInterval": NSEvent.doubleClickInterval])
        RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds))
        record(["kind": "end", "time": ProcessInfo.processInfo.systemUptime])
        return true
    }
}
