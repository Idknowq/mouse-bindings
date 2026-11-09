import AppKit
import ApplicationServices
import GestureCore
import MultitouchBridge

struct TouchSnapshot {
    var contacts: [Contact] = []
    var rawStates: String = "No touch frames received yet"
    var receivedAt: Double = 0
    var frameCount = 0
    var lastGesture = "None"
    var lastOutput = "None"
}

final class Runtime {
    private let lock = NSLock()
    private var engine = GestureEngine(doubleTapInterval: NSEvent.doubleClickInterval)
    private let magnificationOutput = MagnificationOutput()
    private var snapshot = TouchSnapshot()
    private var enabled = false
    private var generation = 0
    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private var observers: [NSObjectProtocol] = []
    private var sleeping = false
    private var inspecting = false
    private(set) var configuration = Configuration()
    private(set) var status = "Paused"
    private(set) var wantsEnabled = true
    var statusChanged: (() -> Void)?

    static var now: Double { ProcessInfo.processInfo.systemUptime }

    func beginWatching() {
        MBWatchDevices({ context in
            guard let context else { return }
            let runtime = Unmanaged<Runtime>.fromOpaque(context).takeUnretainedValue()
            // Bluetooth device initialization can precede the usable touch service.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { runtime.retry() }
        }, Unmanaged.passUnretained(self).toOpaque())
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.sleeping = true
            self.suspend()
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.sleeping = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.retry() }
        })
        retry()
    }

    func setConfiguration(_ value: Configuration) {
        magnificationOutput.cancel()
        configuration = value
        lock.lock()
        engine.reconfigure(value)
        generation += 1
        lock.unlock()
    }

    func setEnabled(_ value: Bool) {
        wantsEnabled = value
        if !value { suspend() }
        else { lock.lock(); engine.reset(); generation += 1; lock.unlock() }
        retry()
    }

    func setInspecting(_ value: Bool) {
        inspecting = value
        retry()
    }

    func retry() {
        guard !sleeping else { return }
        let permission = AXIsProcessTrusted() && CGPreflightPostEventAccess()
        if (wantsEnabled || inspecting) && permission && tap == nil { createEventTap() }
        let canRun = wantsEnabled && permission && tap != nil
        if !canRun { magnificationOutput.cancel() }
        lock.lock()
        enabled = canRun
        lock.unlock()
        if (canRun || inspecting) && !MBIsRunning() {
            magnificationOutput.cancel()
            lock.lock(); engine.reset(); snapshot = TouchSnapshot(); generation += 1; lock.unlock()
            _ = MBStart({ contacts, count, _, context in
                guard let context else { return }
                Unmanaged<Runtime>.fromOpaque(context).takeUnretainedValue().receive(contacts, count: count)
            }, Unmanaged.passUnretained(self).toOpaque())
        } else if !canRun && !inspecting { MBStop() }
        if wantsEnabled && !permission {
            status = "Needs Accessibility permission"
        } else if wantsEnabled && tap == nil {
            status = "Cannot filter events. Check Accessibility / Input Monitoring and retry."
        } else if !MBIsRunning() && (canRun || inspecting) {
            status = String(cString: MBLastError())
        } else {
            status = canRun ? "Gestures enabled" : "Paused"
        }
        statusChanged?()
    }

    private func suspend() {
        magnificationOutput.cancel()
        lock.lock(); enabled = false; generation += 1; engine.reset(); lock.unlock()
        MBStop()
        status = "Paused"
        statusChanged?()
    }

    func stop() {
        suspend()
        MBUnwatchDevices()
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
        if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        tapSource = nil; tap = nil
    }

    private func receive(_ raw: UnsafePointer<MBContact>?, count: Int32) {
        let buffer = raw.map { Array(UnsafeBufferPointer(start: $0, count: Int(count))) } ?? []
        let contacts = buffer.filter { ($0.state == 3 || $0.state == 4) && $0.x.isFinite && $0.y.isFinite }
            .map { Contact(id: $0.identifier, x: Double($0.x), y: Double($0.y)) }
        lock.lock()
        snapshot.contacts = contacts
        snapshot.receivedAt = Self.now
        snapshot.frameCount += 1
        snapshot.rawStates = buffer.map { "\($0.identifier):\($0.state)" }.joined(separator: "  ")
        // The inspector recognizes gestures while paused, without executing them.
        let gesture = engine.update(contacts, at: Self.now)
        let token = generation
        if let gesture { snapshot.lastGesture = gesture.rawValue }
        if let pinch = engine.pinchEvent {
            snapshot.lastGesture = pinch.phase == .changed ?
                (pinch.magnification > 0 ? "pinch → zoom in" : "pinch → zoom out") : "pinch \(pinch.phase)"
            // Queue under the input lock so begin/change/end preserve callback order.
            enqueuePinch(pinch, generation: token)
        }
        lock.unlock()
        if let gesture { schedule(gesture, generation: token) }
    }

    func readSnapshot() -> TouchSnapshot {
        lock.lock(); defer { lock.unlock() }
        return snapshot
    }

    private func createEventTap() {
        let types: [CGEventType] = [.leftMouseDown, .leftMouseUp, .leftMouseDragged,
                                    .rightMouseDown, .rightMouseUp, .rightMouseDragged,
                                    .mouseMoved, .scrollWheel]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                               options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let runtime = Unmanaged<Runtime>.fromOpaque(context).takeUnretainedValue()
            return runtime.handle(type, event: event) ? Unmanaged.passUnretained(event) : nil
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        if let tap {
            tapSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), tapSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    private func handle(_ type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            magnificationOutput.cancel()
            // Recognition resets after a gap; never execute an old queued action.
            lock.lock(); engine.reset(); generation += 1; lock.unlock()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return true
        }
        lock.lock()
        let button = type == .rightMouseDown || type == .rightMouseUp || type == .rightMouseDragged ? 1 : 0
        let pointerDistance = hypot(Double(event.getIntegerValueField(.mouseEventDeltaX)),
                                    Double(event.getIntegerValueField(.mouseEventDeltaY)))
        var suppress = false
        var disposition = GestureEngine.ClickDisposition.passthrough
        var gesture: Gesture?
        switch type {
        case .leftMouseUp, .rightMouseUp:
            disposition = engine.clickDisposition(button: button, ending: true)
        case .leftMouseDragged, .rightMouseDragged:
            disposition = engine.clickDisposition(button: button)
            if enabled { engine.pointerMoved(at: Self.now, distance: pointerDistance) }
        case .leftMouseDown where enabled || inspecting, .rightMouseDown where enabled || inspecting:
            gesture = engine.mouseDown(button: button, at: Self.now, suppressClick: enabled)
            disposition = engine.clickDisposition(button: button)
            if let pinch = engine.pinchEvent { enqueuePinch(pinch, generation: generation) }
        case .mouseMoved where enabled || inspecting:
            engine.pointerMoved(at: Self.now, distance: pointerDistance)
        case .scrollWheel where enabled:
            suppress = engine.suppressScroll(at: Self.now,
                momentum: event.getIntegerValueField(.scrollWheelEventMomentumPhase),
                phase: event.getIntegerValueField(.scrollWheelEventScrollPhase))
        default: break
        }
        let token = generation
        if let gesture { snapshot.lastGesture = gesture.rawValue }
        if disposition == .commandLeft {
            event.flags.insert(.maskCommand)
            event.setIntegerValueField(.mouseEventButtonNumber, value: 0)
            switch type {
            case .rightMouseDown: event.type = .leftMouseDown
            case .rightMouseUp: event.type = .leftMouseUp
            case .rightMouseDragged: event.type = .leftMouseDragged
            default: break
            }
            snapshot.lastOutput = "twoFingerClick → Command + left click"
        }
        lock.unlock()
        if let gesture, disposition != .commandLeft { schedule(gesture, generation: token) }
        return !suppress && disposition != .suppress
    }

    private func schedule(_ gesture: Gesture, generation token: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let valid = self.enabled && self.generation == token
            self.lock.unlock()
            guard valid, AXIsProcessTrusted(), CGPreflightPostEventAccess(),
                  let shortcut = self.configuration.shortcut(for: gesture) else { return }
            let target = NSWorkspace.shared.frontmostApplication?.localizedName ?? "front app"
            let sent = KeyboardOutput.post(shortcut)
            self.lock.lock()
            self.snapshot.lastOutput = sent ? "\(gesture.rawValue) → \(target)" : "Cannot create keyboard events"
            self.lock.unlock()
        }
    }

    private func enqueuePinch(_ pinch: PinchEvent, generation token: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let valid = self.enabled && self.generation == token
            self.lock.unlock()
            guard valid else { return }
            let sent = self.magnificationOutput.post(pinch)
            self.lock.lock()
            self.snapshot.lastOutput = sent ? "Smooth zoom → \(self.magnificationOutput.targetName)" :
                "Cannot send native magnification"
            self.lock.unlock()
        }
    }
}
