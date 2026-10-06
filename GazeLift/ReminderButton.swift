import AppKit
import SwiftUI

/// Real AppKit controls retain first-click, keyboard and accessibility behavior
/// inside a nonactivating panel, even when the frontmost app belongs to someone else.
struct ReminderButton: NSViewRepresentable {
    let title: String
    let primary: Bool
    let action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeNSView(context: Context) -> TintedButton {
        let button = TintedButton()
        button.setButtonType(.momentaryPushIn)
        button.isBordered = false
        button.focusRingType = .exterior
        button.target = context.coordinator
        button.action = #selector(Coordinator.invoke)
        updateNSView(button, context: context)
        return button
    }

    func updateNSView(_ button: TintedButton, context: Context) {
        context.coordinator.action = action
        button.title = title
        button.primary = primary
        button.needsDisplay = true
    }

    @MainActor final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func invoke() { action() }
    }
}

final class TintedButton: NSButton {
    var primary = false
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 38) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { title }
    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        performClick(nil)
        return true
    }
    override var focusRingMaskBounds: NSRect { bounds }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10).fill()
    }

    override func draw(_ dirtyRect: NSRect) {
        let fill = primary ? NSColor(srgbRed: 0.72, green: 0.91, blue: 0.80, alpha: 1)
                           : NSColor.white.withAlphaComponent(0.10)
        (isHighlighted ? fill.blended(withFraction: 0.15, of: .black) ?? fill : fill).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: primary ? .semibold : .regular),
            .foregroundColor: primary ? NSColor(srgbRed: 0.06, green: 0.22, blue: 0.19, alpha: 1) : NSColor.white,
        ]
        let label = NSAttributedString(string: title, attributes: attributes)
        let size = label.size()
        label.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
    }
}
