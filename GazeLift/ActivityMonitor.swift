import AppKit
import CoreGraphics
import Darwin

enum MonotonicClock {
    static func now() -> TimeInterval {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(mach_continuous_time()) * Double(info.numer) / Double(info.denom) / 1_000_000_000
    }
}

@MainActor
final class ActivityMonitor {
    private var locked = false
    private var sleeping = false
    private var inactive = false
    private var screenSleeping = false
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    var onChange: (() -> Void)?

    init() {
        let workspace = NSWorkspace.shared.notificationCenter
        watch(workspace, NSWorkspace.willSleepNotification) { $0.sleeping = true }
        watch(workspace, NSWorkspace.didWakeNotification) { $0.sleeping = false }
        watch(workspace, NSWorkspace.screensDidSleepNotification) { $0.screenSleeping = true }
        watch(workspace, NSWorkspace.screensDidWakeNotification) { $0.screenSleeping = false }
        watch(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.inactive = true }
        watch(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.inactive = false }
        let distributed = DistributedNotificationCenter.default()
        watch(distributed, Notification.Name("com.apple.screenIsLocked")) { $0.locked = true }
        watch(distributed, Notification.Name("com.apple.screenIsUnlocked")) { $0.locked = false }
    }

    func stop() {
        for (center, observer) in observers { center.removeObserver(observer) }
        observers.removeAll()
        onChange = nil
    }

    func sample() -> (idle: TimeInterval?, unavailable: Bool) {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else {
            return (nil, true)
        }
        // The lock notification handles transitions; the session snapshot also
        // handles an app launched while the screen is already locked.
        let sessionLocked = session["CGSSessionScreenIsLocked"] as? Bool ?? false
        let onConsole = session[kCGSessionOnConsoleKey as String] as? Bool ?? true
        let idle = CGEventSource.secondsSinceLastEventType(
            .combinedSessionState, eventType: CGEventType(rawValue: UInt32.max)!)
        return (idle.isFinite && idle >= 0 ? idle : nil,
                locked || sleeping || screenSleeping || inactive || sessionLocked || !onConsole)
    }

    private func watch(_ center: NotificationCenter, _ name: Notification.Name,
                       change: @escaping @MainActor (ActivityMonitor) -> Void) {
        let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                change(self)
                self.onChange?()
            }
        }
        observers.append((center, observer))
    }
}
