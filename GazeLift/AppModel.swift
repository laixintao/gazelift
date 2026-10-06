import AppKit
import Combine

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var engine: UsageEngine
    @Published private(set) var now: TimeInterval
    @Published private(set) var activityAvailable = true
    let settings: SettingsStore
    var onUpdate: (() -> Void)?
    private var timer: Timer?
    private var monitor: ActivityMonitor?

    init(settings: SettingsStore = SettingsStore()) {
        self.settings = settings
        let timestamp = MonotonicClock.now()
        now = timestamp
        engine = UsageEngine(settings: settings.timing, now: timestamp)
        settings.onTimingChange = { [weak self] value in self?.engine.configure(value) }
    }

    func start() {
        monitor = ActivityMonitor()
        monitor?.onChange = { [weak self] in self?.refresh() }
        refresh()
        timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer?.tolerance = 0.15
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        monitor?.stop()
        monitor = nil
    }

    func beginRest() {
        now = MonotonicClock.now()
        engine.beginRest(at: now)
        onUpdate?()
    }

    func snooze() {
        now = MonotonicClock.now()
        engine.snooze(at: now)
        onUpdate?()
    }

    func togglePause() {
        now = MonotonicClock.now()
        if engine.phase == .paused { engine.resume(at: now) }
        else { engine.pause() }
        onUpdate?()
    }

    var status: String {
        if !activityAvailable && engine.phase != .paused { return L10n.text("status.unavailable") }
        switch engine.phase {
        case .working: return L10n.text("status.working")
        case .reminding: return L10n.text("status.reminding")
        case .snoozed: return L10n.text("status.snoozed")
        case .restGrace: return L10n.text("status.resting")
        case .away: return L10n.text("status.away")
        case .paused: return L10n.text("status.paused")
        }
    }

    var timeLabel: String {
        switch engine.phase {
        case .working, .snoozed, .restGrace: return L10n.clock(engine.remaining(at: now))
        case .reminding: return L10n.text("time.lookaway")
        case .away: return L10n.text("time.breathe")
        case .paused: return "—"
        }
    }

    private func refresh() {
        guard let sample = monitor?.sample() else { return }
        acceptSample(now: MonotonicClock.now(), idleSeconds: sample.idle, unavailable: sample.unavailable)
    }

    func acceptSample(now: TimeInterval, idleSeconds: TimeInterval?, unavailable: Bool = false) {
        self.now = now
        activityAvailable = idleSeconds != nil
        engine.observe(now: now, idleSeconds: idleSeconds, unavailable: unavailable)
        onUpdate?()
    }
}
