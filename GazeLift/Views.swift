import AppKit
import ServiceManagement
import SwiftUI

enum Palette {
    static let teal = Color(red: 0.09, green: 0.40, blue: 0.35)
    static let mint = Color(red: 0.72, green: 0.91, blue: 0.80)
    static let ink = Color(red: 0.06, green: 0.22, blue: 0.19)
}

struct BrandMark: View {
    var size: CGFloat = 34
    var body: some View {
        Image(systemName: "eye")
            .font(.system(size: size * 0.53, weight: .medium))
            .foregroundStyle(Palette.mint)
            .frame(width: size, height: size)
            .background(Palette.ink.gradient, in: RoundedRectangle(cornerRadius: size * 0.28))
            .accessibilityHidden(true)
    }
}

struct MenuView: View {
    @ObservedObject var model: AppModel
    var showSettings: () -> Void
    var quit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 10) {
                BrandMark()
                Text("GazeLift").font(.system(size: 17, weight: .semibold, design: .rounded))
                Spacer()
                Text(L10n.text("brand.eyecare"))
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text(model.status).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.mint)
                Text(model.timeLabel)
                    .font(.system(size: 38, weight: .light, design: .rounded)).monospacedDigit()
                    .foregroundStyle(.white).minimumScaleFactor(0.65).lineLimit(1)
                Text(L10n.text(model.engine.phase == .away || model.engine.phase == .restGrace
                               ? "menu.return" : "menu.distance"))
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.76))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(20)
            .background(Palette.ink.gradient, in: RoundedRectangle(cornerRadius: 16))

            VStack(spacing: 10) {
                Button(action: model.beginRest) {
                    Label(L10n.text("action.rest"), systemImage: "leaf")
                        .frame(maxWidth: .infinity).padding(.vertical, 5)
                }
                .buttonStyle(.borderedProminent).tint(Palette.teal)
                .disabled(model.engine.phase == .paused || model.engine.phase == .restGrace || model.engine.phase == .away)
                Button(action: model.togglePause) {
                    Label(L10n.text(model.engine.phase == .paused ? "action.resume" : "action.pause"),
                          systemImage: model.engine.phase == .paused ? "play" : "pause")
                        .frame(maxWidth: .infinity).padding(.vertical, 3)
                }.buttonStyle(.bordered)
            }
            Divider()
            HStack {
                Button(action: showSettings) {
                    Label(L10n.text("action.settings"), systemImage: "gearshape")
                }
                Spacer()
                Button(L10n.text("action.quit"), action: quit)
            }
            .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .padding(20).frame(width: 320)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct SettingsView: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                BrandMark(size: 52)
                VStack(alignment: .leading, spacing: 5) {
                    Text("GazeLift").font(.system(size: 24, weight: .semibold, design: .rounded))
                    Text(L10n.text("settings.tagline")).font(.callout).foregroundStyle(.secondary)
                }
            }.padding(26)

            Form {
                Section {
                    timingRow("settings.work", value: $store.workMinutes, range: 1...180, step: 1, unit: "unit.minutes")
                    timingRow("settings.idle", value: $store.idleSeconds, range: 5...300, step: 5, unit: "unit.seconds")
                    timingRow("settings.grace", value: $store.graceSeconds, range: 5...300, step: 5, unit: "unit.seconds")
                } header: {
                    Text(L10n.text("settings.rhythm"))
                } footer: {
                    Text(L10n.text("settings.timing.help")).font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading).multilineTextAlignment(.leading)
                }

                Section {
                    Toggle(L10n.text("settings.login"), isOn: Binding(
                        get: { store.loginEnabled }, set: { store.setLoginEnabled($0) }))
                    if store.loginNeedsApproval {
                        Button(L10n.text("settings.login.approval")) { SMAppService.openSystemSettingsLoginItems() }
                    }
                    if let error = store.loginError { Text(error).font(.caption).foregroundStyle(.red) }
                } header: {
                    Text(L10n.text("settings.general"))
                } footer: {
                    Text(L10n.text("settings.login.help")).font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading).multilineTextAlignment(.leading)
                }
            }.formStyle(.grouped)

            HStack {
                Text(L10n.text("settings.local"))
                Spacer()
                Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0")")
            }
            .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 26).padding(.vertical, 18)
        }
        .frame(width: 520, height: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { store.refreshLoginStatus() }
    }

    private func timingRow(_ key: String, value: Binding<Double>, range: ClosedRange<Double>,
                           step: Double, unit: String) -> some View {
        HStack {
            Text(L10n.text(key))
            Spacer()
            Text(L10n.format(unit, Int(value.wrappedValue)))
                .monospacedDigit().foregroundStyle(.secondary).frame(minWidth: 75, alignment: .trailing)
            Stepper(L10n.text(key), value: value, in: range, step: step)
                .labelsHidden().fixedSize().accessibilityValue(L10n.format(unit, Int(value.wrappedValue)))
        }.padding(.vertical, 5)
    }
}

struct ReminderView: View {
    var rest: () -> Void
    var snooze: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                Image(systemName: "eye")
                Text(L10n.text("reminder.eyebrow")).tracking(1.3)
            }.font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.mint)
            Text(L10n.text("reminder.title"))
                .font(.system(size: 29, weight: .medium, design: .rounded))
                .lineSpacing(2).fixedSize(horizontal: false, vertical: true)
            Text(L10n.text("reminder.subtitle"))
                .font(.system(size: 13)).foregroundStyle(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                ReminderButton(title: L10n.text("action.rest"), primary: true, action: rest)
                    .frame(width: 132, height: 38)
                ReminderButton(title: L10n.text("action.snooze"), primary: false, action: snooze)
                    .frame(maxWidth: .infinity).frame(height: 38)
            }
        }
        .foregroundStyle(.white).padding(28).frame(width: 410)
        .background(Palette.ink.gradient, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.12), lineWidth: 1))
        .padding(1)
    }
}
