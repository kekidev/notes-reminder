import Foundation
import GlanceCore

/// `Hw 6 – ddl 10/25`, as in the reference screenshot.
func dueLabel(_ task: GlanceTask) -> String {
  guard let due = task.due else { return task.text }
  let time = due.time.map { " \($0)" } ?? ""
  return "\(task.text) – ddl \(due.day.month)/\(due.day.day)\(time)"
}

func headerDate(_ date: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
  let formatter = DateFormatter()
  formatter.locale = locale
  formatter.timeZone = timeZone
  formatter.dateFormat = "MMMM d, EEEE"
  return formatter.string(from: date)
}

/// Strips a trailing `ddl M/D [HH:mm]` or `📅 YYYY-MM-DD [HH:mm]` and returns it as the due date.
/// A token that isn't a real date or time stays in the text.
func parseQuickAdd(_ input: String, now: Date, calendar: Calendar) -> (text: String, due: DueDate?)
{
  let today = CalendarDay(now, calendar: calendar)
  let day: CalendarDay?
  let hour: Substring?
  let minute: Substring?
  let start: String.Index
  if let hit = input.firstMatch(of: /\s+ddl (\d{1,2})\/(\d{1,2})(?: (\d{1,2}):(\d{2}))?$/) {
    let (month, dom) = (Int(hit.1) ?? 0, Int(hit.2) ?? 0)
    // Next occurrence on or after today.
    day =
      CalendarDay(year: today.year, month: month, day: dom).flatMap { $0 >= today ? $0 : nil }
      ?? CalendarDay(year: today.year + 1, month: month, day: dom)
    (hour, minute, start) = (hit.3, hit.4, hit.range.lowerBound)
  } else if let hit = input.firstMatch(of: /\s+📅 (\d{4})-(\d{2})-(\d{2})(?: (\d{1,2}):(\d{2}))?$/) {
    day = CalendarDay(year: Int(hit.1) ?? 0, month: Int(hit.2) ?? 0, day: Int(hit.3) ?? 0)
    (hour, minute, start) = (hit.4, hit.5, hit.range.lowerBound)
  } else {
    return (input, nil)
  }
  let time = hour.flatMap { hrs in
    minute.flatMap { TimeOfDay(hour: Int(hrs) ?? 0, minute: Int($0) ?? 0) }
  }
  guard let day, time != nil || hour == nil else { return (input, nil) }
  return (
    String(input[..<start]).trimmingCharacters(in: .whitespaces), DueDate(day: day, time: time)
  )
}
