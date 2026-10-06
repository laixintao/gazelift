import AppKit
import Combine
import ServiceManagement

@MainActor
final class SettingsStore: ObservableObject {
    private let defaults: UserDefaults
    @Published var workMinutes: Double { didSet { save() } }
    @Published var idleSeconds: Double { didSet { save() } }
    @Published var graceSeconds: Double { didSet { save() } }
    @Published private(set) var loginEnabled = false
    @Published private(set) var loginNeedsApproval = false
    @Published var loginError: String?
    var onTimingChange: ((TimingSettings) -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let value = TimingSettings(
            workSeconds: (defaults.object(forKey: "workMinutes") as? Double ?? 30) * 60,
            idleSeconds: defaults.object(forKey: "idleSeconds") as? Double ?? 30,
            graceSeconds: defaults.object(forKey: "graceSeconds") as? Double ?? 30).validated
        workMinutes = value.workSeconds / 60
        idleSeconds = value.idleSeconds
        graceSeconds = value.graceSeconds
        refreshLoginStatus()
    }

    var timing: TimingSettings {
        TimingSettings(workSeconds: workMinutes * 60, idleSeconds: idleSeconds, graceSeconds: graceSeconds).validated
    }

    func refreshLoginStatus() {
        loginEnabled = SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval
        loginNeedsApproval = SMAppService.mainApp.status == .requiresApproval
    }

    func setLoginEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch { loginError = error.localizedDescription }
        refreshLoginStatus()
    }

    private func save() {
        let value = timing
        defaults.set(value.workSeconds / 60, forKey: "workMinutes")
        defaults.set(value.idleSeconds, forKey: "idleSeconds")
        defaults.set(value.graceSeconds, forKey: "graceSeconds")
        onTimingChange?(value)
    }
}
