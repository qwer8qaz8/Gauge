import SwiftUI

// MARK: - Provider

enum Provider: String, Codable, CaseIterable, Identifiable, Hashable {
    case antigravity
    case copilot

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .antigravity: "Antigravity"
        case .copilot: "GitHub Copilot"
        }
    }

    var shortName: String {
        switch self {
        case .antigravity: "AG"
        case .copilot: "CP"
        }
    }

    var symbol: String {
        switch self {
        case .antigravity: "atom"
        case .copilot: "chevron.left.forwardslash.chevron.right"
        }
    }

    var colors: [Color] {
        switch self {
        case .antigravity: [Color(red: 0.26, green: 0.52, blue: 0.96), Color(red: 0.62, green: 0.36, blue: 0.98)]
        case .copilot: [Color(red: 0.55, green: 0.33, blue: 0.95), Color(red: 0.13, green: 0.75, blue: 0.70)]
        }
    }

    var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var tint: Color { colors[0] }
}

// MARK: - Quota window

enum QuotaWindow: String, Codable, Hashable {
    case fiveHour, daily, weekly, monthly, other

    init(raw: String?) {
        switch raw?.lowercased() ?? "" {
        case "5h", "five_hour", "fivehour": self = .fiveHour
        case "daily", "day", "24h": self = .daily
        case "weekly", "week", "7d": self = .weekly
        case "monthly", "month": self = .monthly
        default: self = .other
        }
    }

    var label: String {
        switch self {
        case .fiveHour: "5-Hour"
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        case .other: "Limit"
        }
    }

    var symbol: String {
        switch self {
        case .fiveHour: "clock"
        case .daily: "sun.max"
        case .weekly: "calendar"
        case .monthly: "calendar.badge.clock"
        case .other: "gauge.with.dots.needle.50percent"
        }
    }
}

// MARK: - Quota bucket

struct QuotaBucket: Identifiable, Codable, Hashable {
    let id: String
    let provider: Provider
    let group: String
    var groupDetail: String? = nil
    let name: String
    var detail: String? = nil
    let window: QuotaWindow
    /// 0...1 fraction of the quota still available.
    let remaining: Double
    let resetTime: Date?
    /// Optional human readable usage, e.g. "112 / 300 requests".
    var usageText: String? = nil

    var used: Double { 1 - remaining }
    var title: String { "\(group) · \(name)" }
}

// MARK: - Provider state

struct ProviderState {
    var buckets: [QuotaBucket] = []
    var lastUpdated: Date?
    var error: String?
    var isLoading = false
    var summary: String?
    /// Non-error info shown as a subtle note (e.g. "using local estimate").
    var note: String?

    /// The most constrained bucket (lowest remaining).
    var tightest: QuotaBucket? { buckets.min { $0.remaining < $1.remaining } }
}

// MARK: - Copilot report

struct ModelUsage: Identifiable, Hashable {
    var id: String { model }
    let model: String
    let quantity: Double
    let netAmount: Double
}

struct CopilotReport {
    let login: String
    let used: Double
    let allowance: Double
    let today: Double?
    let overageCost: Double
    let unit: String
    let models: [ModelUsage]
    let resetTime: Date
    /// True when computed from local CLI sessions rather than GitHub's billing API.
    var isEstimate = false
}

// MARK: - History

struct HistoryPoint: Codable, Identifiable, Hashable {
    let date: Date
    let bucketID: String
    let label: String
    let provider: Provider
    let remaining: Double

    var id: String { "\(bucketID)@\(date.timeIntervalSince1970)" }
}

// MARK: - Styling helpers

enum QuotaLevel {
    static func color(for remaining: Double) -> Color {
        switch remaining {
        case 0.5...: Color(red: 0.20, green: 0.78, blue: 0.60)
        case 0.25..<0.5: Color(red: 0.98, green: 0.74, blue: 0.20)
        case 0.10..<0.25: Color(red: 0.98, green: 0.52, blue: 0.20)
        default: Color(red: 0.95, green: 0.30, blue: 0.34)
        }
    }

    static func label(for remaining: Double) -> String {
        switch remaining {
        case 0.5...: "Healthy"
        case 0.25..<0.5: "Moderate"
        case 0.10..<0.25: "Low"
        case 0.005..<0.10: "Critical"
        default: "Depleted"
        }
    }
}

enum Format {
    static func percent(_ fraction: Double) -> String {
        if fraction > 0, fraction < 0.005 { return "<1%" }
        return "\(Int((fraction * 100).rounded()))%"
    }

    static func countdown(to date: Date?, now: Date = .now) -> String {
        guard let date else { return "—" }
        let interval = date.timeIntervalSince(now)
        if interval <= 0 { return "now" }
        let minutes = Int(interval / 60)
        let days = minutes / 1440
        let hours = (minutes % 1440) / 60
        let mins = minutes % 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(mins)m" }
        return "\(max(mins, 1))m"
    }

    static func resetDate(_ date: Date?) -> String {
        guard let date else { return "" }
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            return "Today " + date.formatted(date: .omitted, time: .shortened)
        }
        if cal.isDateInTomorrow(date) {
            return "Tomorrow " + date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
    }

    static func number(_ value: Double) -> String {
        value.rounded() == value ? "\(Int(value))" : String(format: "%.1f", value)
    }

    static func currency(_ value: Double) -> String {
        value.formatted(.currency(code: "USD"))
    }
}
