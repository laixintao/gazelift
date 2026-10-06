import AppKit
import SwiftUI

final class MemoryDefaults: UserDefaults, @unchecked Sendable {
    private var values: [String: Any] = [:]
    override func object(forKey key: String) -> Any? { values[key] }
    override func set(_ value: Any?, forKey key: String) { values[key] = value }
}

@main
@MainActor
struct UITests {
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        guard value() else { fatalError(message) }
    }

    static func main() throws {
        NSApplication.shared.setActivationPolicy(.accessory)
        let defaults = MemoryDefaults()
        let store = SettingsStore(defaults: defaults)
        expect(store.workMinutes == 30 && store.idleSeconds == 30 && store.graceSeconds == 30, "Settings defaults")
        var changed: TimingSettings?
        store.onTimingChange = { changed = $0 }
        store.workMinutes = 45
        expect(changed?.workSeconds == 2700, "Settings notify the engine")
        expect(SettingsStore(defaults: defaults).workMinutes == 45, "Settings persist")
        defaults.set(Double.nan, forKey: "workMinutes")
        expect(SettingsStore(defaults: defaults).workMinutes == 30, "Corrupt preferences recover")
        store.workMinutes = 30

        expect(BorderView.thickness(size: CGSize(width: 1440, height: 900), progress: 0) == 3, "Initial border is thin")
        expect(BorderView.thickness(size: CGSize(width: 1440, height: 900), progress: 1) == 450, "Landscape fully covered")
        expect(BorderView.thickness(size: CGSize(width: 900, height: 1440), progress: 1) == 450, "Portrait fully covered")
        expect(L10n.text("action.rest") != "action.rest", "Localized strings packaged")
        testOverlay()

        let language = Bundle.main.preferredLocalizations.first ?? "en"
        let output = URL(fileURLWithPath: "build/qa")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for dark in [false, true] {
            let suffix = "\(language)-\(dark ? "dark" : "light")"
            let scheme: ColorScheme = dark ? .dark : .light
            try snapshot(SettingsView(store: store).environment(\.colorScheme, scheme),
                         size: CGSize(width: 520, height: 560), name: "settings-\(suffix)")
            try snapshot(ReminderView(rest: {}, snooze: {}).environment(\.colorScheme, scheme),
                         size: CGSize(width: 412, height: 300), name: "reminder-\(suffix)")
            let model = AppModel(settings: store)
            model.acceptSample(now: MonotonicClock.now(), idleSeconds: 0)
            try snapshot(MenuView(model: model, showSettings: {}, quit: {}).environment(\.colorScheme, scheme),
                         size: CGSize(width: 320, height: 430), name: "menu-\(suffix)")
        }
        for progress in [0.0, 0.5, 1.0] {
            let border = BorderView(frame: CGRect(x: 0, y: 0, width: 720, height: 450))
            border.progress = progress
            try save(view: border, name: "border-\(Int(progress * 100))")
        }
        print("PASS: native settings, localization, border geometry and rendered UI snapshots (\(language))")
    }

    private static func testOverlay() {
        var rested = false
        var snoozed = false
        let overlay = OverlayController(presentsWindows: false, rest: { rested = true }, snooze: { snoozed = true })
        overlay.show(startedAt: MonotonicClock.now() - 30)
        expect(overlay.panels.count == NSScreen.screens.count, "Exactly one border per display")
        for (panel, screen) in zip(overlay.panels, NSScreen.screens) {
            expect(panel.frame == screen.frame, "Borders cover the physical screen including menu and Dock edges")
            expect(panel.ignoresMouseEvents && !panel.canBecomeKey, "Borders pass clicks through without taking focus")
            expect(panel.collectionBehavior.contains(.fullScreenAuxiliary), "Overlay supports native fullscreen")
        }
        guard let controls = overlay.controls, let view = controls.contentView else { fatalError("Missing controls") }
        expect(!controls.ignoresMouseEvents, "Controls receive clicks")
        expect(view.acceptsFirstMouse(for: nil), "A first click works without activating the app")
        expect(controls.canBecomeKey, "Controls can accept keyboard focus when requested")
        expect(overlay.panels.allSatisfy { $0.level.rawValue < controls.level.rawValue }, "Controls always above all borders")
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        let buttons = findButtons(in: view)
        expect(buttons.count == 2, "Two native reminder controls are realized")
        for label in [L10n.text("action.rest"), L10n.text("action.snooze")] {
            guard let button = buttons.first(where: { $0.title == label }) else { fatalError("Missing \(label)") }
            expect(button.accessibilityRole() == .button && button.accessibilityLabel() == label,
                   "Reminder controls have native accessible roles and localized labels")
            expect(button.acceptsFirstMouse(for: nil), "Buttons accept first click without activation")
            button.performClick(nil)
        }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        expect(rested && snoozed, "Native reminder controls invoke both callbacks")
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        expect(overlay.panels.count == NSScreen.screens.count, "Display changes rebuild the overlay")
        overlay.hide()
        expect(overlay.panels.isEmpty && overlay.controls == nil, "Dismissal releases all overlay windows")
        overlay.stop()
    }

    private static func findButtons(in view: NSView) -> [NSButton] {
        (view as? NSButton).map { [$0] } ?? view.subviews.flatMap { findButtons(in: $0) }
    }

    private static func snapshot<V: View>(_ view: V, size: CGSize, name: String) throws {
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.contentView = host
        window.setContentSize(size)
        host.layoutSubtreeIfNeeded()
        // Let SwiftUI realize Form/scroll content even though the test window stays hidden.
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        try save(view: host, name: name)
        window.orderOut(nil)
    }

    private static func save(view: NSView, name: String) throws {
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fatalError("No bitmap") }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("No PNG") }
        try data.write(to: URL(fileURLWithPath: "build/qa/\(name).png"))
    }
}
