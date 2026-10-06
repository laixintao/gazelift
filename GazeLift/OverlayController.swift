import AppKit
import SwiftUI

final class BorderView: NSView {
    var progress: Double = 0 { didSet { needsDisplay = true } }
    override var isOpaque: Bool { false }

    static func thickness(size: CGSize, progress: Double) -> CGFloat {
        let limit = min(size.width, size.height) / 2
        return min(limit, 3 + (limit - 3) * min(1, max(0, progress)))
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill(using: .copy)
        let thickness = Self.thickness(size: bounds.size, progress: progress)
        let shape = NSBezierPath(rect: bounds)
        let interior = bounds.insetBy(dx: thickness, dy: thickness)
        if interior.width > 0 && interior.height > 0 { shape.appendRect(interior) }
        shape.windingRule = .evenOdd
        NSColor(srgbRed: 0.09, green: 0.40, blue: 0.35, alpha: 1).setFill()
        shape.fill()
    }
}

private final class BorderPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class ControlPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class OverlayController {
    private(set) var panels: [NSPanel] = []
    private(set) var controls: NSPanel?
    private var animationTimer: Timer?
    private var screenObserver: NSObjectProtocol?
    private var start: TimeInterval?
    private var controlScreenNumber: NSNumber?
    private let rest: () -> Void
    private let snooze: () -> Void
    private let presentsWindows: Bool

    init(presentsWindows: Bool = true, rest: @escaping () -> Void, snooze: @escaping () -> Void) {
        self.presentsWindows = presentsWindows
        self.rest = rest
        self.snooze = snooze
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.start != nil else { return }
                self.rebuild()
            }
        }
    }

    func show(startedAt: TimeInterval) {
        guard start != startedAt else { return }
        hide()
        start = startedAt
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        controlScreenNumber = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        rebuild()
        animationTimer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.animate() }
        }
        animationTimer?.tolerance = 0.01
        if let animationTimer { RunLoop.main.add(animationTimer, forMode: .common) }
    }

    func hide() {
        animationTimer?.invalidate()
        animationTimer = nil
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
        controls?.orderOut(nil)
        controls = nil
        start = nil
    }

    func stop() {
        hide()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
    }

    private func configure(_ panel: NSPanel, controls: Bool) {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = controls
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .canJoinAllApplications, .ignoresCycle]
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + (controls ? 2 : 1))
        panel.ignoresMouseEvents = !controls
        panel.isMovable = false
    }

    private func rebuild() {
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
        controls?.orderOut(nil)
        for screen in NSScreen.screens {
            let panel = BorderPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                                    backing: .buffered, defer: false)
            configure(panel, controls: false)
            panel.contentView = BorderView(frame: CGRect(origin: .zero, size: screen.frame.size))
            panel.setFrame(screen.frame, display: true)
            if presentsWindows { panel.orderFrontRegardless() }
            panels.append(panel)
        }
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber) == controlScreenNumber
        } ?? NSScreen.main
        if let screen {
            let host = FirstMouseHostingView(rootView: ReminderView(rest: rest, snooze: snooze))
            let size = host.fittingSize
            let area = screen.visibleFrame
            let rect = CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2,
                              width: size.width, height: size.height)
            let panel = ControlPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            configure(panel, controls: true)
            panel.becomesKeyOnlyIfNeeded = true
            panel.contentView = host
            if presentsWindows { panel.orderFrontRegardless() }
            controls = panel
        }
        animate()
    }

    private func animate() {
        guard let start else { return }
        var progress = min(1, max(0, (MonotonicClock.now() - start) / TimingSettings.expansionSeconds))
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { progress = floor(progress * 6) / 6 }
        for panel in panels { (panel.contentView as? BorderView)?.progress = progress }
        if progress >= 1 {
            animationTimer?.invalidate()
            animationTimer = nil
        }
    }
}
