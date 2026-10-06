import Foundation

@main
struct UsageEngineTests {
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        guard value() else { fatalError(message) }
    }

    static func working() -> UsageEngine {
        var engine = UsageEngine(now: 100)
        engine.observe(now: 100, idleSeconds: 0)
        expect(engine.phase == .working, "Active startup begins a work cycle")
        return engine
    }

    static func reminding() -> UsageEngine {
        var engine = working()
        engine.observe(now: 1900, idleSeconds: 0)
        expect(engine.phase == .reminding, "Work deadline triggers reminder")
        return engine
    }

    static func main() {
        var engine = working()
        engine.observe(now: 1899.99, idleSeconds: 0)
        expect(engine.phase == .working, "No early reminder")
        engine.observe(now: 1900, idleSeconds: 0)
        expect(engine.phase == .reminding, "Exact deadline triggers reminder")
        expect(engine.expansion(at: 1930) == 0.5, "Halfway expansion")
        expect(engine.expansion(at: 2000) == 1, "Expansion stays at full coverage")
        engine.observe(now: 1901, idleSeconds: 0)
        expect(engine.reminderStartedAt == 1900, "Polling doesn't restart animation")

        engine = working()
        engine.observe(now: 1900, idleSeconds: 30)
        expect(engine.phase == .away, "Idle wins over work deadline")
        engine.observe(now: 1901, idleSeconds: 31)
        expect(engine.phase == .away, "Elapsed time cannot count as returned activity")
        engine.observe(now: 1902, idleSeconds: 0)
        expect(engine.phase == .working && engine.deadline == 3702, "Return starts a full cycle")

        engine = reminding()
        engine.snooze(at: 1901)
        expect(engine.phase == .snoozed && engine.deadline == 2201, "Snooze lasts five minutes")
        engine.observe(now: 2200, idleSeconds: 0)
        expect(engine.phase == .snoozed, "No early snooze expiry")
        engine.observe(now: 2201, idleSeconds: 0)
        expect(engine.phase == .reminding && engine.reminderStartedAt == 2201, "Snooze starts a new animation")
        engine.snooze(at: 2202)
        engine.observe(now: 2232, idleSeconds: 30)
        expect(engine.phase == .away, "Natural rest cancels snooze")
        engine.observe(now: 2233, idleSeconds: 0)
        expect(engine.deadline == 4033, "Return after snooze gets a full work cycle")

        engine = working()
        engine.beginRest(at: 120)
        engine.observe(now: 149, idleSeconds: 0)
        expect(engine.phase == .restGrace, "Early input is ignored during grace")
        engine.observe(now: 150, idleSeconds: 1)
        expect(engine.phase == .away, "Grace ends without treating earlier input as return")
        engine.observe(now: 160, idleSeconds: 11)
        expect(engine.phase == .away, "Recent but pre-cutoff input isn't a new event")
        engine.observe(now: 161, idleSeconds: 0)
        expect(engine.phase == .working && engine.deadline == 1961, "New post-grace input restarts")

        engine = reminding()
        engine.observe(now: 1901, idleSeconds: 0, unavailable: true)
        expect(engine.phase == .away && engine.reminderStartedAt == nil, "Lock immediately hides reminder")
        engine.observe(now: 5000, idleSeconds: 0, unavailable: true)
        expect(engine.phase == .away, "Lock screen input never resumes work")
        engine.observe(now: 5001, idleSeconds: 0)
        expect(engine.phase == .away, "Unlock waits for subsequent activity")
        engine.observe(now: 5002, idleSeconds: 0)
        expect(engine.deadline == 6802, "Post-unlock return starts fresh")

        engine = UsageEngine(now: 0)
        engine.observe(now: 0, idleSeconds: 0, unavailable: true)
        engine.observe(now: 1, idleSeconds: 0)
        expect(engine.phase == .away, "Locked startup must not take active-startup shortcut")
        engine.observe(now: 2, idleSeconds: 0)
        expect(engine.phase == .working, "Activity after locked startup resumes")

        engine = working()
        engine.beginRest(at: 120)
        engine.observe(now: 121, idleSeconds: 0, unavailable: true)
        engine.observe(now: 500, idleSeconds: 0)
        expect(engine.phase == .away, "Wake after grace still awaits fresh input")
        engine.observe(now: 501, idleSeconds: 0)
        expect(engine.phase == .working, "Grace survives sleep without a stuck state")

        engine = working()
        engine.configure(TimingSettings(workSeconds: 600, idleSeconds: 60, graceSeconds: 10))
        expect(engine.deadline == 1900 && engine.settings.idleSeconds == 30, "Settings deferred for current cycle")
        engine.observe(now: 200, idleSeconds: 30)
        engine.observe(now: 201, idleSeconds: 0)
        expect(engine.deadline == 801 && engine.settings.idleSeconds == 60, "Next cycle adopts settings")
        engine.pause()
        engine.observe(now: 9000, idleSeconds: 0)
        expect(engine.phase == .paused, "Activity doesn't resume explicit pause")
        engine.resume(at: 9001)
        engine.observe(now: 9002, idleSeconds: 2)
        expect(engine.phase == .away, "Resume requires fresh activity")
        engine.observe(now: 9003, idleSeconds: 0)
        expect(engine.deadline == 9603, "Resume starts a new cycle")

        for invalid: Double? in [nil, .nan, .infinity, -1] {
            engine = reminding()
            engine.observe(now: 1901, idleSeconds: invalid)
            expect(engine.phase == .away, "Invalid activity data suppresses reminder")
        }
        let settings = TimingSettings(workSeconds: .nan, idleSeconds: -10, graceSeconds: .infinity).validated
        expect(settings.workSeconds == 1800 && settings.idleSeconds == 5 && settings.graceSeconds == 30,
               "Invalid settings recover to bounded defaults")
        print("PASS: work, idle, grace, new activity, snooze, lock/sleep, pause, settings and invalid samples")
    }
}
