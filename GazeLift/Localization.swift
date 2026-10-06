import Foundation

enum L10n {
    static func text(_ key: String) -> String {
        NSLocalizedString(key, bundle: .main, comment: "")
    }
    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: Locale.current, arguments: arguments)
    }
    static func clock(_ seconds: TimeInterval) -> String {
        let value = Int(ceil(max(0, seconds)))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}
