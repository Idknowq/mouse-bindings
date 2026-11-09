import AppKit
import ApplicationServices
import GestureCore
import MultitouchBridge

if CommandLine.arguments.contains("--probe-input") {
    let index = CommandLine.arguments.firstIndex(of: "--seconds")
    let seconds = index.flatMap { $0 + 1 < CommandLine.arguments.count ? Double(CommandLine.arguments[$0 + 1]) : nil } ?? 20
    if !InputProbe().run(seconds: max(1, min(seconds, 60))) { exit(1) }
} else if CommandLine.arguments.contains("--probe") {
    // Read-only hardware verification: no event tap, shortcuts, or app preferences.
    let started = MBStart({ contacts, count, timestamp, _ in
        let raw = contacts.map { Array(UnsafeBufferPointer(start: $0, count: Int(count))) } ?? []
        let line = raw.map { "id=\($0.identifier) state=\($0.state) x=\(String(format: "%.3f", $0.x)) y=\(String(format: "%.3f", $0.y))" }
            .joined(separator: "; ")
        print("\(String(format: "%.3f", timestamp)) count=\(count) \(line)")
        fflush(stdout)
    }, nil)
    if !started {
        fputs("\(String(cString: MBLastError()))\n", stderr)
        exit(1)
    }
    let index = CommandLine.arguments.firstIndex(of: "--seconds")
    let seconds = index.flatMap { $0 + 1 < CommandLine.arguments.count ? Double(CommandLine.arguments[$0 + 1]) : nil } ?? 10
    RunLoop.main.run(until: Date(timeIntervalSinceNow: max(1, min(seconds, 60))))
    MBStop()
} else if let index = CommandLine.arguments.firstIndex(of: "--test-pinch") {
    guard index + 1 < CommandLine.arguments.count,
          ["in", "out"].contains(CommandLine.arguments[index + 1]) else {
        fputs("Usage: --test-pinch in|out\n", stderr); exit(1)
    }
    guard AXIsProcessTrusted(), CGPreflightPostEventAccess() else {
        fputs("Accessibility permission is missing for this build.\n", stderr); exit(1)
    }
    let output = MagnificationOutput()
    let delta = CommandLine.arguments[index + 1] == "in" ? 0.01 : -0.01
    print("Sending a native pinch in two seconds. Place the pointer over the target content.")
    Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { _ in
        print("Target: \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "unknown")")
        output.post(PinchEvent(phase: .began))
        var frame = 0
        Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { timer in
            if frame < 36 {
                output.post(PinchEvent(phase: .changed, magnification: delta))
                frame += 1
            } else {
                print("Posted native pinch: \(output.post(PinchEvent(phase: .ended)))")
                timer.invalidate()
            }
        }
    }
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 4))
    output.cancel()
} else if let index = CommandLine.arguments.firstIndex(of: "--test-shortcut"),
          index + 1 < CommandLine.arguments.count,
          let gesture = Gesture(rawValue: CommandLine.arguments[index + 1]) {
    // Output-only diagnostic; activate the target app during this three-second delay.
    guard AXIsProcessTrusted(), CGPreflightPostEventAccess() else {
        fputs("Accessibility permission is missing for this build.\n", stderr); exit(1)
    }
    let configURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/MouseBindings/config.json")
    let config = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: configURL))
    try config.validate()
    guard let shortcut = config.shortcut(for: gesture) else { exit(1) }
    let targetIndex = CommandLine.arguments.firstIndex(of: "--target")
    let target = targetIndex.flatMap { $0 + 1 < CommandLine.arguments.count ? Int32(CommandLine.arguments[$0 + 1]) : nil }
    print("Sending \(gesture.rawValue) in three seconds. Activate the target app.")
    Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { _ in
        print("Target: \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "unknown")")
        print("Posted: \(KeyboardOutput.post(shortcut, target: target))")
    }
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 4))
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
