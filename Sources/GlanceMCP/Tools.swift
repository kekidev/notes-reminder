import Foundation
import GlanceCore
import MCP

/// The MCP tools, callable without a transport.
public enum GlanceTools {
  /// Runs one tool call. Failures come back as an `isError` result with a readable message.
  public static func handle(
    _ name: String, _ arguments: [String: Value]?, store: FileStore, now: Date
  ) -> CallTool.Result {
    do {
      let value = try run(name, Args(arguments ?? [:]), store, CalendarDay(now), now)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
      return .init(content: [text(String(bytes: try encoder.encode(value), encoding: .utf8)!)])
    } catch {
      return .init(content: [text(message(for: error))], isError: true)
    }
  }

  // swiftlint:disable:next cyclomatic_complexity function_body_length
  private static func run(
    _ name: String, _ args: Args, _ store: FileStore, _ today: CalendarDay, _ now: Date
  ) throws -> Value {
    switch name {
    case "list_tasks":
      let status = try args.string("status").map(parseStatus)
      let category = try args.string("category")
      let due = try args.string("due")
      guard due == nil || ["today", "upcoming", "none"].contains(due) else {
        throw ToolError("due must be one of: today, upcoming, none.")
      }
      return .array(
        try store.read().0.tasks.filter { task in
          let dueMatches =
            switch due {
            case "today": isDue(task, today)
            case "upcoming": task.due.map { $0.day > today } == true
            case "none": task.due == nil
            default: true
            }
          return (status ?? task.status) == task.status
            && (category ?? task.category) == task.category && dueMatches
        }.map(json))

    case "get_summary":
      let doc = try store.read().0
      return [
        "todo": .int(Counts.todo(doc)),
        "dueTodayOrOverdue": .int(Counts.dueTodayOrOverdue(doc, now: now)),
        // Same rule as the count: suggestions are not on the list yet.
        "dueTasks": .array(
          doc.tasks.filter { $0.category != Category.suggested && isDue($0, today) }.map(json)),
      ]

    case "add_task":
      let text = try args.required("text")
      let category = try args.string("category")
      let due = try parseDue(args.string("due"), field: "due")
      return try store.write { doc in
        let id = try doc.add(text, category: category, due: due)
        return json(doc.task(id)!)
      }

    case "suggest_tasks":
      guard case .array(let items)? = args.values["tasks"], !items.isEmpty else {
        throw ToolError("tasks must be a non-empty array of {text, due?, reason?}.")
      }
      let source = try args.string("source") ?? "claude-desktop"
      // Validate the whole batch before writing any of it.
      let suggestions = try items.enumerated().map { index, item in
        guard case .object(let fields) = item else {
          throw ToolError("tasks[\(index)] must be an object.")
        }
        let item = Args(fields, prefix: "tasks[\(index)].")
        return (
          text: try item.required("text"),
          due: try parseDue(item.string("due"), field: "tasks[\(index)].due"),
          reason: try item.string("reason")
        )
      }
      return try store.write { doc in
        var added: [Value] = []
        var skipped: [Value] = []
        for item in suggestions {
          switch try doc.suggest(item.text, due: item.due, source: source, today: today) {
          case .added(let id):
            if let reason = item.reason, !reason.isEmpty {
              try doc.update(id) { $0.notes = reason }
            }
            added.append(.string(id.rawValue))
          case .duplicate(let id):
            skipped.append(["text": .string(item.text), "duplicateOf": .string(id.rawValue)])
          }
        }
        return ["added": .array(added), "skipped": .array(skipped)]
      }

    case "update_task":
      let id = TaskID(rawValue: try args.required("id"))
      let text = try args.string("text")
      let status = try args.string("status").map(parseStatus)
      let category = try args.string("category")
      // Outer nil: leave alone. Inner nil: clear.
      // A bare `nil` in the ternary becomes `.some(nil)` and clears the field, so spell out `.none`.
      let due: DueDate?? =
        args.has("due") ? .some(try parseDue(args.string("due"), field: "due")) : .none
      let notes: String?? = args.has("notes") ? .some(try args.string("notes")) : .none
      return try store.write { doc in
        if category != nil, doc.task(id)?.suggestion != nil {
          throw ToolError("Suggestions can only be accepted in the Glance app.")
        }
        var id = try doc.update(id) { task in
          if let text { task.text = text }
          if let due { task.due = due }
          if let notes { task.notes = notes?.isEmpty == false ? notes : nil }
        }
        if let status { id = try doc.setStatus(id, status, today: today) }
        if let category, category != doc.task(id)?.category {
          id = try doc.move(id, to: category)
        }
        return json(doc.task(id)!)
      }

    case "complete_task", "cancel_task":
      let id = TaskID(rawValue: try args.required("id"))
      let status: TaskStatus = name == "complete_task" ? .completed : .cancelled
      return try store.write { doc in
        let id = try doc.setStatus(id, status, today: today)
        return json(doc.task(id)!)
      }

    case "list_categories":
      return .array(try store.read().0.categories.map { .string($0.name) })

    case "add_category":
      let name = try args.required("name")
      return try store.write { doc in
        try doc.addCategory(name)
        return .array(doc.categories.map { .string($0.name) })
      }

    default:
      throw ToolError("Unknown tool \"\(name)\".")
    }
  }

  // MARK: - Arguments

  private struct ToolError: Error {
    let message: String
    init(_ message: String) { self.message = message }
  }

  private struct Args {
    let values: [String: Value]
    var prefix = ""

    init(_ values: [String: Value], prefix: String = "") {
      self.values = values
      self.prefix = prefix
    }

    func has(_ key: String) -> Bool { values[key] != nil }

    /// Nil when the key is missing or null.
    func string(_ key: String) throws -> String? {
      switch values[key] {
      case nil, .null?: return nil
      case .string(let value)?: return value
      default: throw ToolError("\(prefix)\(key) must be a string.")
      }
    }

    func required(_ key: String) throws -> String {
      guard let value = try string(key) else { throw ToolError("\(prefix)\(key) is required.") }
      return value
    }
  }

  private static func parseStatus(_ text: String) throws -> TaskStatus {
    guard let status = TaskStatus.allCases.first(where: { "\($0)" == text }) else {
      let names = TaskStatus.allCases.map { "\($0)" }.joined(separator: ", ")
      throw ToolError("status must be one of: \(names). Got \"\(text)\".")
    }
    return status
  }

  /// Nil or "" means no due date.
  private static func parseDue(_ text: String?, field: String) throws -> DueDate? {
    guard let text, !text.isEmpty else { return nil }
    let invalid = ToolError(
      "\(field) must be \"YYYY-MM-DD\" or \"YYYY-MM-DD HH:mm\" (24-hour). Got \"\(text)\".")
    guard let match = text.wholeMatch(of: /(\d{4})-(\d{2})-(\d{2})(?: (\d{2}):(\d{2}))?/),
      let day = CalendarDay(year: Int(match.1)!, month: Int(match.2)!, day: Int(match.3)!)
    else { throw invalid }
    guard let hour = match.4, let minute = match.5 else { return DueDate(day: day) }
    guard let time = TimeOfDay(hour: Int(hour)!, minute: Int(minute)!) else { throw invalid }
    return DueDate(day: day, time: time)
  }

  // MARK: - Results

  private static func isDue(_ task: GlanceTask, _ today: CalendarDay) -> Bool {
    (task.status == .todo || task.status == .pending) && task.due.map { $0.day <= today } == true
  }

  private static func json(_ task: GlanceTask) -> Value {
    [
      "id": .string(task.id.rawValue),
      "text": .string(task.text),
      "status": .string("\(task.status)"),
      "category": .string(task.category),
      "due": task.due.map { .string("\($0.day)" + ($0.time.map { " \($0)" } ?? "")) } ?? .null,
      "doneAt": task.doneAt.map { .string("\($0)") } ?? .null,
      "notes": task.notes.map(Value.string) ?? .null,
      "suggested": .bool(task.suggestion != nil),
      "kind": .string(task.kind.rawValue),
      "indent": .int(task.indent),
    ]
  }

  private static func text(_ text: String) -> Tool.Content {
    .text(text: text, annotations: nil, _meta: nil)
  }

  // swiftlint:disable:next cyclomatic_complexity
  private static func message(for error: any Error) -> String {
    switch error {
    case let error as ToolError: error.message
    case let error as TaskOpsError:
      switch error {
      case .taskNotFound(let id): "No task with id \"\(id)\". Call list_tasks for current ids."
      case .categoryNotFound(let name):
        "No category named \"\(name)\". Call list_categories, or add_category first."
      case .categoryExists(let name): "Category \"\(name)\" already exists."
      case .notASuggestion(let id): "Task \"\(id)\" is not a suggestion."
      case .reservedCategory:
        "The \"suggested\" category is reserved. Use suggest_tasks to propose tasks."
      case .emptyText: "text must not be empty."
      case .multilineText: "text must be a single line. Put extra detail in notes."
      case .invalidName: "Category name must be non-empty and a single line."
      case .invalidSource: "source must be one word with no spaces."
      case .invalidOrder: "Category order must list every category once."
      }
    case FileStore.Error.contended: "todo.md kept changing during the write. Try again."
    default: "\(error.localizedDescription)"
    }
  }
}
