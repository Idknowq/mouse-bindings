import AppKit
import ApplicationServices
import GestureCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let runtime = Runtime()
    private var inspector: Inspector!
    private var statusItem: NSStatusItem!
    private var pauseItem: NSMenuItem!
    private var statusLine: NSMenuItem!
    private var configError: String?
    private let configURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/MouseBindings/config.json")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        inspector = Inspector(runtime: runtime)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "computermouse", accessibilityDescription: "Mouse Bindings")
        let menu = NSMenu()
        menu.delegate = self
        statusLine = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
        menu.addItem(statusLine)
        menu.addItem(.separator())
        pauseItem = add("Enable gestures", action: #selector(toggle), to: menu)
        add("Touch inspector…", action: #selector(showInspector), to: menu)
        menu.addItem(.separator())
        add("Grant Accessibility…", action: #selector(grantAccessibility), to: menu)
        add("Input Monitoring settings…", action: #selector(inputMonitoring), to: menu)
        add("Retry connection / permissions", action: #selector(retry), to: menu)
        menu.addItem(.separator())
        add("Open configuration…", action: #selector(openConfiguration), to: menu)
        add("Reload configuration", action: #selector(reloadConfiguration), to: menu)
        menu.addItem(.separator())
        add("Quit", action: #selector(quit), to: menu)
        statusItem.menu = menu
        runtime.statusChanged = { [weak self] in self?.updateMenu() }
        loadConfiguration()
        if CommandLine.arguments.contains("--paused") { runtime.setEnabled(false) }
        runtime.beginWatching()
        if CommandLine.arguments.contains("--inspect") { inspector.show() }
    }

    @discardableResult private func add(_ title: String, action: Selector, to menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self; menu.addItem(item); return item
    }

    private func updateMenu() {
        statusLine.title = configError ?? runtime.status
        statusLine.toolTip = statusLine.title
        pauseItem.state = runtime.wantsEnabled ? .on : .off
        statusItem.button?.appearsDisabled = !runtime.wantsEnabled
    }

    func menuWillOpen(_ menu: NSMenu) { runtime.retry(); updateMenu() }
    @objc private func toggle() { runtime.setEnabled(!runtime.wantsEnabled) }
    @objc private func showInspector() { inspector.show() }
    @objc private func retry() { runtime.retry() }

    @objc private func grantAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openSettings("Privacy_Accessibility")
    }

    @objc private func inputMonitoring() {
        runtime.setEnabled(false)
        openSettings("Privacy_ListenEvent")
    }

    private func openSettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openConfiguration() { NSWorkspace.shared.open(configURL) }
    @objc private func reloadConfiguration() { loadConfiguration(); runtime.retry() }

    private func loadConfiguration() {
        do {
            if !FileManager.default.fileExists(atPath: configURL.path) {
                try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(Configuration()).write(to: configURL, options: .atomic)
            }
            let value = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: configURL))
            try value.validate()
            runtime.setConfiguration(value)
            configError = nil
        } catch {
            configError = "Configuration error: \(error.localizedDescription)"
            runtime.setEnabled(false)
        }
        updateMenu()
    }

    @objc private func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) { runtime.stop() }
}
