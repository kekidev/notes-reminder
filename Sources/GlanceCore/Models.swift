import Foundation

public enum TaskStatus: String, Sendable, CaseIterable {
  case todo = " "
  case pending = "/"
  case completed = "x"
  case cancelled = "-"

  /// Completed and old cancelled lines both read as crossed out.
  public var isCrossedOut: Bool { self == .completed || self == .cancelled }
}

/// A calendar date with no time zone, so it round-trips through the file unchanged.
public struct CalendarDay: Hashable, Comparable, Sendable, CustomStringConvertible {
  public let year: Int
  public let month: Int
  public let day: Int

  public init?(year: Int, month: Int, day: Int) {
    let components = DateComponents(year: year, month: month, day: day)
    guard components.isValidDate(in: Calendar(identifier: .gregorian)) else { return nil }
    self.year = year
    self.month = month
    self.day = day
  }

  public init(_ date: Date, calendar: Calendar = .current) {
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    self.year = parts.year!
    self.month = parts.month!
    self.day = parts.day!
  }

  public static func < (lhs: Self, rhs: Self) -> Bool {
    (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
  }

  public var description: String {
    String(format: "%04d-%02d-%02d", year, month, day)
  }
}

public struct TimeOfDay: Hashable, Comparable, Sendable, CustomStringConvertible {
  public let hour: Int
  public let minute: Int

  public init?(hour: Int, minute: Int) {
    guard (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
    self.hour = hour
    self.minute = minute
  }

  public static func < (lhs: Self, rhs: Self) -> Bool {
    (lhs.hour, lhs.minute) < (rhs.hour, rhs.minute)
  }

  public var description: String { String(format: "%02d:%02d", hour, minute) }
}

public struct DueDate: Hashable, Sendable {
  public var day: CalendarDay
  public var time: TimeOfDay?

  public init(day: CalendarDay, time: TimeOfDay? = nil) {
    self.day = day
    self.time = time
  }
}

/// Marks a task an AI proposed; it lives in the reserved `suggested` category.
public struct Suggestion: Hashable, Sendable {
  public var source: String
  public var day: CalendarDay

  public init(source: String, day: CalendarDay) {
    self.source = source
    self.day = day
  }
}

/// Derived from category, text, and occurrence index; never written to the file.
public struct TaskID: Hashable, Sendable, CustomStringConvertible {
  public let rawValue: String

  public init(rawValue: String) { self.rawValue = rawValue }

  public var description: String { rawValue }
}

/// `- [ ] text`, `- text`, or `### text`.
public enum LineKind: String, Sendable, CaseIterable {
  case checklist, bullet, heading
}

public struct GlanceTask: Identifiable, Hashable, Sendable {
  public internal(set) var id: TaskID
  public internal(set) var category: String
  public var text: String
  public var status: TaskStatus
  public var due: DueDate?
  public var doneAt: CalendarDay?
  public var notes: String?
  public var suggestion: Suggestion?
  /// Only a checklist line has a status, due date, or suggestion, and only it is counted.
  public var kind: LineKind
  /// Nesting level, 0...4, written as two leading spaces each. A heading never indents.
  public var indent: Int

  static let maxIndent = 4

  init(
    text: String, status: TaskStatus = .todo, due: DueDate? = nil, doneAt: CalendarDay? = nil,
    notes: String? = nil, suggestion: Suggestion? = nil, kind: LineKind = .checklist,
    indent: Int = 0
  ) {
    self.kind = kind
    self.indent = indent
    self.id = TaskID(rawValue: "")
    self.category = ""
    self.text = text
    self.status = status
    self.due = due
    self.doneAt = doneAt
    self.notes = notes
    self.suggestion = suggestion
  }
}

/// One line of the file inside a category: a task, or anything else kept verbatim.
enum Entry: Hashable, Sendable {
  case task(GlanceTask)
  case raw(String)
}

public struct Category: Hashable, Sendable {
  public static let suggested = "suggested"

  public internal(set) var name: String
  var entries: [Entry]

  init(name: String, entries: [Entry] = []) {
    self.name = name
    self.entries = entries
  }

  public var tasks: [GlanceTask] {
    entries.compactMap { if case .task(let task) = $0 { task } else { nil } }
  }

  public var isSuggested: Bool { name == Self.suggested }
}

public struct GlanceDocument: Hashable, Sendable {
  public static let formatVersion = 1

  /// Lines before the first `## ` header, front matter included, kept verbatim.
  var preamble: [String]
  public internal(set) var categories: [Category]

  init(preamble: [String] = [], categories: [Category] = []) {
    self.preamble = preamble
    self.categories = categories
    reindex()
  }

  public var tasks: [GlanceTask] { categories.flatMap(\.tasks) }

  public func task(_ id: TaskID) -> GlanceTask? { tasks.first { $0.id == id } }

  /// Recomputes every task's `category` and `id`. Call after any structural change.
  mutating func reindex() {
    for cat in categories.indices {
      var seen: [String: Int] = [:]
      let name = categories[cat].name
      for row in categories[cat].entries.indices {
        guard case .task(var task) = categories[cat].entries[row] else { continue }
        let occurrence = seen[task.text, default: 0]
        seen[task.text] = occurrence + 1
        task.category = name
        task.id = TaskID(rawValue: "\(name)/\(task.text)#\(occurrence)")
        categories[cat].entries[row] = .task(task)
      }
    }
  }
}
