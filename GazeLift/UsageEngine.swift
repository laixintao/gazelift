import Foundation

struct TimingSettings: Equatable {
    var workSeconds: TimeInterval = 30 * 60
    var idleSeconds: TimeInterval = 30
    var graceSeconds: TimeInterval = 30
    static let snoozeSeconds: TimeInterval = 5 * 60
    static let expansionSeconds: TimeInterval = 60

    var validated: Self {
        Self(workSeconds: Self.clamp(workSeconds, 60...10_800, fallback: 1_800),
             idleSeconds: Self.clamp(idleSeconds, 5...300, fallback: 30),
             graceSeconds: Self.clamp(graceSeconds, 5...300, fallback: 30))
    }

    private static func clamp(_ value: Double, _ range: ClosedRange<Double>, fallback: Double) -> Double {
        value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
    }
}

enum UsagePhase: Equatable {
    case working, reminding, snoozed, restGrace, away, paused
}

/// Pure state machine. All timestamps belong to the injected monotonic clock.
struct UsageEngine {
    private(set) var phase: UsagePhase = .away
    private(set) var settings: TimingSettings
    private(set) var pendingSettings: TimingSettings
    private(set) var deadline: TimeInterval?
    private(set) var reminderStartedAt: TimeInterval?
    private(set) var returnAfter: TimeInterval
    private var unavailable = false
    private var hasObserved = false

    init(settings: TimingSettings = TimingSettings(), now: TimeInterval) {
        self.settings = settings.validated
        self.pendingSettings = settings.validated
        self.returnAfter = now
    }

    mutating func configure(_ value: TimingSettings) { pendingSettings = value.validated }

    mutating func observe(now: TimeInterval, idleSeconds: TimeInterval?, unavailable: Bool = false) {
        guard phase != .paused else { return }
        guard !unavailable, let idle = idleSeconds, idle.isFinite, idle >= 0 else {
            // Never display over a locked session or infer a return from missing data.
            self.unavailable = true
            hasObserved = true
            if phase != .restGrace { enterAway(after: now) }
            return
        }
        if self.unavailable {
            self.unavailable = false
            returnAfter = max(returnAfter, now)
            if phase != .restGrace { enterAway(after: now) }
        }

        let lastInput = now - idle
        if !hasObserved {
            hasObserved = true
            if idle < settings.idleSeconds && phase == .away && lastInput <= returnAfter && !self.unavailable {
                // An active session at first launch starts a fresh work cycle.
                // Subsequent transitions require genuinely new input.
                startWork(at: now)
            }
        }

        if phase == .restGrace {
            guard now >= returnAfter else { return }
            phase = .away
            deadline = nil
        }
        if phase == .away {
            if lastInput > returnAfter && idle < pendingSettings.idleSeconds {
                startWork(at: now)
            }
            return
        }
        // Rest takes precedence over reminder / snooze deadlines.
        if idle >= settings.idleSeconds {
            enterAway(after: now)
            return
        }
        if (phase == .working || phase == .snoozed), let deadline, now >= deadline {
            phase = .reminding
            reminderStartedAt = now
            self.deadline = nil
        }
    }

    mutating func beginRest(at now: TimeInterval) {
        guard phase != .paused else { return }
        phase = .restGrace
        returnAfter = now + settings.graceSeconds
        deadline = returnAfter
        reminderStartedAt = nil
        hasObserved = true
    }

    mutating func snooze(at now: TimeInterval) {
        guard phase == .reminding else { return }
        phase = .snoozed
        deadline = now + TimingSettings.snoozeSeconds
        reminderStartedAt = nil
    }

    mutating func pause() {
        phase = .paused
        deadline = nil
        reminderStartedAt = nil
    }

    mutating func resume(at now: TimeInterval) {
        settings = pendingSettings
        hasObserved = true
        enterAway(after: now)
    }

    func remaining(at now: TimeInterval) -> TimeInterval { max(0, (deadline ?? now) - now) }
    func expansion(at now: TimeInterval) -> Double {
        guard let start = reminderStartedAt else { return 0 }
        return min(1, max(0, (now - start) / TimingSettings.expansionSeconds))
    }

    private mutating func startWork(at now: TimeInterval) {
        settings = pendingSettings
        phase = .working
        deadline = now + settings.workSeconds
        reminderStartedAt = nil
    }

    private mutating func enterAway(after now: TimeInterval) {
        phase = .away
        returnAfter = now
        deadline = nil
        reminderStartedAt = nil
    }
}
