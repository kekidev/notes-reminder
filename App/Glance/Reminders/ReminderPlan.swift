import Foundation
import GlanceCore

struct Reminder: Equatable {
  var id: String
  var fire: Date
  var title: String
  var body: String
}

/// macOS keeps at most 64 pending requests; 60 leaves room.
private let maxReminders = 60

/// A notification for each open, dated, non-suggested task that is still in the future.
/// A date-only task fires at 09:00 local.
func reminderPlan(_ doc: GlanceDocument, now: Date, calendar: Calendar) -> [Reminder] {
  let tasks = doc.categories.filter { !$0.isSuggested }.flatMap(\.tasks)
  let reminders: [Reminder] = tasks.compactMap { task in
    guard task.status == .todo || task.status == .pending, let due = task.due,
      let fire = calendar.date(
        from: DateComponents(
          year: due.day.year, month: due.day.month, day: due.day.day,
          hour: due.time?.hour ?? 9, minute: due.time?.minute ?? 0)),
      fire > now
    else { return nil }
    let when = "\(due.day.month)/\(due.day.day)" + (due.time.map { " \($0)" } ?? "")
    return Reminder(
      id: "glance." + task.id.rawValue, fire: fire, title: task.text,
      body: "\(task.category) · due \(when)")
  }
  return Array(reminders.sorted { $0.fire < $1.fire }.prefix(maxReminders))
}
