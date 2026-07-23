import Foundation
import UserNotifications

/// Local-only reminders via `UNUserNotificationCenter` — no APNs/server
/// push in v1 (see the brief's Notifications section).
@MainActor
final class NotificationScheduler {
    static let shared = NotificationScheduler()

    private let center: UNUserNotificationCenter
    private let identifier = "com.jakubsvehla.vocab.daily-reminder"

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    /// Requests permission only if not already determined — callers trigger
    /// this contextually (after a first successful practice session, per
    /// the brief), never at cold launch. Returns whether notifications are
    /// authorized, whether that was already true or just newly granted.
    @discardableResult
    func requestAuthorizationIfNeeded() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    /// Replaces any existing reminder with a daily repeat at `hour:minute`.
    /// `streak` is baked into the body at schedule time — a repeating
    /// trigger's content is fixed once set, so callers reschedule after
    /// every successful session (and whenever the reminder time changes in
    /// Settings) to keep the count from going stale.
    func scheduleDailyReminder(hour: Int, minute: Int, streak: Int) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = "Vocab"
        content.body = streak > 0
            ? "Time to review — keep your \(streak)-day streak!"
            : "Time to review your words."
        content.sound = .default

        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)

        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    func cancelDailyReminder() {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}
