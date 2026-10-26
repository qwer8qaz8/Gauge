import Foundation
import UserNotifications

/// Sends threshold and reset notifications, de-duplicated per bucket and reset cycle.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    private let center = UNUserNotificationCenter.current()
    private let stateKey = "notifierState"

    /// bucketID -> lowest threshold already notified this cycle (e.g. 0.25).
    private var notified: [String: Double] = [:]
    /// bucketID -> last seen remaining fraction.
    private var lastRemaining: [String: Double] = [:]

    private struct Stored: Codable {
        var notified: [String: Double]
        var lastRemaining: [String: Double]
    }

    override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: stateKey),
           let s = try? JSONDecoder().decode(Stored.self, from: data) {
            notified = s.notified
            lastRemaining = s.lastRemaining
        }
    }

    func setUp() {
        center.delegate = self
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    private var thresholds: [Double] {
        let d = UserDefaults.standard
        var t: [Double] = []
        if d.bool(forKey: Prefs.notify50) { t.append(0.50) }
        if d.bool(forKey: Prefs.notify25) { t.append(0.25) }
        if d.bool(forKey: Prefs.notify10) { t.append(0.10) }
        if d.bool(forKey: Prefs.notifyEmpty) { t.append(0.005) }
        return t
    }

    func evaluate(_ buckets: [QuotaBucket]) {
        let d = UserDefaults.standard
        guard d.bool(forKey: Prefs.notificationsEnabled) else {
            buckets.forEach { lastRemaining[$0.id] = $0.remaining }
            persist()
            return
        }

        for bucket in buckets {
            let previous = lastRemaining[bucket.id]
            lastRemaining[bucket.id] = bucket.remaining

            // Reset detection: remaining jumped up meaningfully.
            if let previous, bucket.remaining - previous > 0.15 {
                notified[bucket.id] = nil
                if d.bool(forKey: Prefs.notifyReset), previous < 0.5 {
                    post(
                        id: "reset.\(bucket.id)",
                        title: "\(bucket.provider.displayName) quota refreshed",
                        body: "\(bucket.title) is back to \(Format.percent(bucket.remaining)) available."
                    )
                }
            }

            // Threshold crossings (lowest crossed threshold only).
            let crossed = thresholds.filter { bucket.remaining <= $0 }.min()
            guard let crossed else { continue }
            if let already = notified[bucket.id], already <= crossed { continue }
            // Don't spam on first launch for levels that were already crossed long ago:
            // still notify once, that's useful context.
            notified[bucket.id] = crossed

            let title: String
            let body: String
            if crossed < 0.01 {
                title = "\(bucket.provider.displayName) limit reached"
                body = "\(bucket.title) is used up. Resets in \(Format.countdown(to: bucket.resetTime))."
            } else {
                title = "\(bucket.provider.displayName) running low"
                body = "\(bucket.title): \(Format.percent(bucket.remaining)) left. Resets in \(Format.countdown(to: bucket.resetTime))."
            }
            post(id: "low.\(bucket.id).\(crossed)", title: title, body: body)
        }
        persist()
    }

    func sendTest() {
        post(id: "test.\(UUID().uuidString)", title: "Gauge notifications are on",
             body: "You'll be alerted when a quota runs low or refreshes.")
    }

    private func post(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let req = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        center.add(req)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(Stored(notified: notified, lastRemaining: lastRemaining)) {
            UserDefaults.standard.set(data, forKey: stateKey)
        }
    }

    // Show banners even while the app is frontmost.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}
