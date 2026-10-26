import Foundation

/// UserDefaults keys used across the app (shared with `@AppStorage`).
enum Prefs {
    static let refreshMinutes = "refreshMinutes"
    static let showInDock = "showInDock"
    static let menuBarStyle = "menuBarStyle"
    static let pinnedBucket = "pinnedBucket"
    static let agyPath = "agyPath"
    static let copilotAllowance = "copilotAllowance"
    static let copilotEnabled = "copilotEnabled"
    static let antigravityEnabled = "antigravityEnabled"
    static let notificationsEnabled = "notificationsEnabled"
    static let notify50 = "notify50"
    static let notify25 = "notify25"
    static let notify10 = "notify10"
    static let notifyEmpty = "notifyEmpty"
    static let notifyReset = "notifyReset"
    static let alertLevels = "alertLevels"
    static let appearance = "appearance"
    static let copilotCLIDir = "copilotCLIDir"
    static let cliStatsEnabled = "cliStatsEnabled"
    static let useGhToken = "useGhToken"
    static let historyDays = "historyDays"
    static let statsRangeDays = "statsRangeDays"
    static let showBadges = "showBadges"

    static func register() {
        UserDefaults.standard.register(defaults: [
            refreshMinutes: 5,
            showInDock: true,
            menuBarStyle: MenuBarStyle.iconAndPercent.rawValue,
            pinnedBucket: "auto",
            agyPath: "",
            copilotAllowance: 300.0,
            copilotEnabled: true,
            antigravityEnabled: true,
            notificationsEnabled: true,
            notify50: false,
            notify25: true,
            notify10: true,
            notifyEmpty: true,
            notifyReset: true,
            appearance: "system",
            copilotCLIDir: "",
            cliStatsEnabled: true,
            useGhToken: true,
            historyDays: 30,
            statsRangeDays: 30,
            showBadges: true,
        ])
    }

    static var defaults: UserDefaults { .standard }
}

enum MenuBarStyle: String, CaseIterable, Identifiable {
    case iconAndPercent
    case iconOnly
    case bothServices

    var id: String { rawValue }

    var label: String {
        switch self {
        case .iconAndPercent: "Gauge + percent"
        case .iconOnly: "Gauge only"
        case .bothServices: "Both services"
        }
    }
}
