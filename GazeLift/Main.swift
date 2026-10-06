import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var item: NSStatusItem?
    private let popover = NSPopover()
    private var settingsWindow: NSWindow?
    private lazy var overlay = OverlayController(rest: { [weak self] in self?.model.beginRest() },
                                                 snooze: { [weak self] in self?.model.snooze() })

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.item = item
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        item.button?.image = NSImage(systemSymbolName: "eye", accessibilityDescription: "GazeLift")
        item.button?.image?.isTemplate = true
        item.button?.imagePosition = .imageLeading
        item.button?.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MenuView(
            model: model, showSettings: { [weak self] in self?.showSettings() },
            quit: { NSApplication.shared.terminate(nil) }))
        model.onUpdate = { [weak self] in self?.update() }
        model.start()
        if ProcessInfo.processInfo.arguments.contains("--settings") { showSettings() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
        overlay.stop()
        if let item { NSStatusBar.system.removeStatusItem(item) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    @objc private func togglePopover() {
        if popover.isShown { popover.performClose(nil) }
        else if let button = item?.button { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY) }
    }

    private func update() {
        item?.button?.toolTip = "GazeLift · \(model.status)"
        let phase = model.engine.phase
        item?.button?.title = [.working, .snoozed, .restGrace].contains(phase) ? " \(model.timeLabel)" : ""
        if phase == .reminding, let start = model.engine.reminderStartedAt { overlay.show(startedAt: start) }
        else { overlay.hide() }
    }

    private func showSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 520, height: 560),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "GazeLift · \(L10n.text("action.settings"))"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(store: model.settings))
            window.center()
            settingsWindow = window
        }
        model.settings.refreshLoginStatus()
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

@main
struct GazeLiftApplication {
    @MainActor static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        // CI runs this entry point from the exact packaged executable on both architectures.
        if ProcessInfo.processInfo.arguments.contains("--smoke-test") {
            let info = Bundle.main.infoDictionary ?? [:]
            guard info["CFBundleIdentifier"] as? String == "io.xbin.gazelift",
                  Bundle.main.path(forResource: "GazeLift", ofType: "icns") != nil,
                  L10n.text("action.rest") != "action.rest" else {
                FileHandle.standardError.write(Data("Invalid application bundle or missing resources\n".utf8))
                exit(1)
            }
            let host = NSHostingView(rootView: ReminderView(rest: {}, snooze: {}))
            guard host.fittingSize.width > 0, host.fittingSize.height > 0 else { exit(1) }
            print("PASS: packaged GazeLift executable, AppKit/SwiftUI and localized resources")
            return
        }
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
