import Foundation
import GlanceCore
import UserNotifications
import os

/// Keeps the system's pending notifications equal to `reminderPlan` of the file.
@MainActor final class Reminders {
  private static let prefix = "glance."
  private let log = Logger(subsystem: "app.glance.Glance", category: "reminders")
  private var task: Task<Void, Never>?
  private var asked = false

  init() { UserDefaults.standard.register(defaults: ["notificationsEnabled": true]) }

  func reschedule(_ doc: GlanceDocument) {
    let enabled = UserDefaults.standard.bool(forKey: "notificationsEnabled")
    let plan = enabled ? reminderPlan(doc, now: .now, calendar: .current) : []
    task?.cancel()
    task = Task {
      let center = UNUserNotificationCenter.current()
      if enabled, !asked {
        asked = true
        do {
          _ = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
          log.error("authorization failed: \(error)")
        }
      }
      let stale = await center.pendingNotificationRequests().map(\.identifier).filter {
        $0.hasPrefix(Self.prefix)
      }
      center.removePendingNotificationRequests(withIdentifiers: stale)
      for reminder in plan {
        guard !Task.isCancelled else { return }
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default
        let parts = Calendar.current.dateComponents(
          [.year, .month, .day, .hour, .minute], from: reminder.fire)
        let request = UNNotificationRequest(
          identifier: reminder.id, content: content,
          trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
        do {
          try await center.add(request)
        } catch {
          log.error("add \(reminder.id) failed: \(error)")
        }
      }
    }
  }
}
