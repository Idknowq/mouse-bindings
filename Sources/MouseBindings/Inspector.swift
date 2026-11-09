import AppKit
import GestureCore

final class TouchView: NSView {
    var snapshot = TouchSnapshot()
    var region = Region()
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        let surface = NSRect(x: 32, y: 20, width: 200, height: 300)
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(roundedRect: surface, xRadius: 65, yRadius: 65).fill()
        NSColor.separatorColor.setStroke()
        NSBezierPath(roundedRect: surface, xRadius: 65, yRadius: 65).stroke()
        let logo = NSRect(x: surface.minX + region.minX * surface.width,
                          y: surface.minY + (1 - region.maxY) * surface.height,
                          width: (region.maxX - region.minX) * surface.width,
                          height: (region.maxY - region.minY) * surface.height)
        NSColor.systemOrange.withAlphaComponent(0.25).setFill()
        NSBezierPath(rect: logo).fill()
        let fresh = Runtime.now - snapshot.receivedAt < 0.5
        if fresh {
            for contact in snapshot.contacts {
                let point = NSPoint(x: surface.minX + contact.x * surface.width,
                                    y: surface.minY + (1 - contact.y) * surface.height)
                NSColor.systemBlue.setFill()
                NSBezierPath(ovalIn: NSRect(x: point.x - 8, y: point.y - 8, width: 16, height: 16)).fill()
                drawText("\(contact.id)", at: NSPoint(x: point.x + 10, y: point.y - 7))
            }
        }
        var text = "Top = front of mouse\nOrange = lock tap region\n\nFrames received: \(snapshot.frameCount)\n"
        text += snapshot.frameCount == 0 ? "Waiting for touch input…\n" : "Last frame: \(String(format: "%.1f", Runtime.now - snapshot.receivedAt))s ago\n"
        text += "Last gesture: \(snapshot.lastGesture)\n\n"
        text += "Last output: \(snapshot.lastOutput)\n\n"
        for contact in snapshot.contacts {
            text += "ID \(contact.id)  x=\(String(format: "%.3f", contact.x))  y=\(String(format: "%.3f", contact.y))\n"
        }
        text += "\nRaw ID:state: \(snapshot.rawStates)\n\nX: left 0 → right 1\nY: tail 0 → front 1\n\nPause gestures while calibrating."
        drawText(text, at: NSPoint(x: 260, y: 30))
    }

    private func drawText(_ text: String, at point: NSPoint) {
        (text as NSString).draw(at: point, withAttributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.labelColor
        ])
    }
}

final class Inspector: NSObject, NSWindowDelegate {
    private let runtime: Runtime
    private var window: NSWindow?
    private var view: TouchView?
    private var timer: Timer?

    init(runtime: Runtime) { self.runtime = runtime }

    func show() {
        if window == nil {
            let view = TouchView(frame: NSRect(x: 0, y: 0, width: 670, height: 350))
            let window = NSWindow(contentRect: view.frame, styleMask: [.titled, .closable, .miniaturizable],
                                  backing: .buffered, defer: false)
            window.title = "Magic Mouse touch inspector"
            window.contentView = view
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.view = view; self.window = window
        }
        runtime.setInspecting(true)
        update()
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15, repeats: true) { [weak self] _ in self?.update() }
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func update() {
        view?.snapshot = runtime.readSnapshot()
        view?.region = runtime.configuration.logoRegion
        view?.needsDisplay = true
    }

    func windowWillClose(_ notification: Notification) {
        timer?.invalidate(); timer = nil
        runtime.setInspecting(false)
    }
}
