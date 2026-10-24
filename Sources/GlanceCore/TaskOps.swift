import Foundation

public enum TaskOpsError: Error, Hashable {
  case taskNotFound(TaskID)
  case categoryNotFound(String)
  case categoryExists(String)
  case notASuggestion(TaskID)
  case reservedCategory
  case emptyText
  case multilineText
  case invalidName
  case invalidSource
  case invalidOrder
}

public enum SuggestResult: Hashable, Sendable {
  case added(TaskID)
  case duplicate(of: TaskID)
}

/// Every edit to a document. Each one leaves `id` and `category` on every task up to date.
extension GlanceDocument {
  public static let defaultCategory = "notes"

  @discardableResult
  public mutating func add(_ text: String, category: String? = nil, due: DueDate? = nil) throws
    -> TaskID
  {
    let name = try category.map(validName) ?? firstRegularCategory()
    guard name != Category.suggested else { throw TaskOpsError.reservedCategory }
    return try insert(GlanceTask(text: try validText(text), due: due), into: name, at: nil)
  }

  /// Applies `edit` to the task. `id` and `category` are restored; use `move` to change category.
  @discardableResult
  public mutating func update(_ id: TaskID, _ edit: (inout GlanceTask) -> Void) throws -> TaskID {
    let (cat, row) = try locate(id)
    let original = categories[cat].tasks.first { $0.id == id }!
    var task = original
    edit(&task)
    task.text = try validText(task.text)
    task.id = original.id
    task.category = original.category
    if task.kind != .checklist {
      (task.status, task.doneAt, task.due, task.suggestion) = (.todo, nil, nil, nil)
    }
    categories[cat].entries[row] = .task(task)
    reindex()
    guard case .task(let updated) = categories[cat].entries[row] else { fatalError("just written") }
    return updated.id
  }

  @discardableResult
  public mutating func setStatus(_ id: TaskID, _ status: TaskStatus, today: CalendarDay) throws
    -> TaskID
  {
    try update(id) {
      $0.status = status
      $0.doneAt = status == .completed ? today : nil
    }
  }

  /// Moves the task to `position` among the tasks of `category`, or to its end.
  @discardableResult
  public mutating func move(_ id: TaskID, to category: String, at position: Int? = nil) throws
    -> TaskID
  {
    guard category != Category.suggested else { throw TaskOpsError.reservedCategory }
    guard categories.contains(where: { $0.name == category }) else {
      throw TaskOpsError.categoryNotFound(category)
    }
    let task = try take(id)
    return try insert(task, into: category, at: position)
  }

  public mutating func remove(_ id: TaskID) throws {
    _ = try take(id)
  }

  /// Removes the crossed-out checklist lines of one category and returns how many.
  @discardableResult
  public mutating func removeCompleted(in category: String) throws -> Int {
    let cat = try categoryIndex(category)
    let before = categories[cat].entries.count
    categories[cat].entries.removeAll {
      if case .task(let task) = $0 {
        task.kind == .checklist && task.status.isCrossedOut
      } else {
        false
      }
    }
    reindex()
    return before - categories[cat].entries.count
  }

  /// A page's lines as markdown: tasks without their notes, other lines verbatim, no trailing blanks.
  public func bodyLines(of category: String) -> [String] {
    var lines = (categories.first { $0.name == category }?.entries ?? []).map { entry in
      switch entry {
      case .raw(let line): line
      case .task(let task): MarkdownSerializer.taskLines(task)[0]
      }
    }
    while lines.last == "" { lines.removeLast() }
    return lines
  }

  /// Replaces the page with `lines` (markdown, plain text allowed). A task that keeps its kind and
  /// text keeps its notes, suggestion and, while still crossed out, its done date.
  public mutating func replaceBody(of category: String, with lines: [String]) throws {
    let cat = try categoryIndex(category)
    var old = categories[cat].tasks
    var entries = lines.flatMap { $0.split(separator: "\n", omittingEmptySubsequences: false) }
      .map { line -> Entry in
        let line = String(line)
        guard var task = MarkdownParser.taskLine(line) else {
          // A leading space keeps a typed "## x" from starting a page.
          // shortcut: a plain line shaped like a "  > " note still reads back as a note.
          return .raw(line.hasPrefix("## ") ? " " + line : line)
        }
        if let match = old.firstIndex(where: { $0.kind == task.kind && $0.text == task.text }) {
          let previous = old.remove(at: match)
          task.notes = previous.notes
          task.suggestion = task.suggestion ?? previous.suggestion
          // The editor shows cancelled as ☑ and saves it as [x], so a crossed-out line keeps its old status.
          if task.status.isCrossedOut, previous.status.isCrossedOut {
            task.status = previous.status
            task.doneAt = task.doneAt ?? previous.doneAt
          }
        }
        return .task(task)
      }
    while entries.last == .raw("") { entries.removeLast() }
    categories[cat].entries = entries
    separateCategories()
  }

  public mutating func addCategory(_ name: String) throws {
    let name = try validName(name)
    guard name != Category.suggested else { throw TaskOpsError.reservedCategory }
    guard !categories.contains(where: { $0.name == name }) else {
      throw TaskOpsError.categoryExists(name)
    }
    createCategory(name)
  }

  public mutating func renameCategory(_ old: String, to new: String) throws {
    let new = try validName(new)
    guard new != Category.suggested, old != Category.suggested else {
      throw TaskOpsError.reservedCategory
    }
    guard !categories.contains(where: { $0.name == new }) else {
      throw TaskOpsError.categoryExists(new)
    }
    categories[try categoryIndex(old)].name = new
    reindex()
  }

  /// Removes the category and every task in it.
  public mutating func removeCategory(_ name: String) throws {
    categories.remove(at: try categoryIndex(name))
    reindex()
  }

  /// `names` must list every category exactly once.
  public mutating func reorderCategories(_ names: [String]) throws {
    guard names.sorted() == categories.map(\.name).sorted() else {
      throw TaskOpsError.invalidOrder
    }
    categories = names.map { name in categories.first { $0.name == name }! }
    separateCategories()
  }

  /// Adds the task to `suggested` unless an open task already has the same text.
  public mutating func suggest(
    _ text: String, due: DueDate?, source: String, today: CalendarDay
  ) throws -> SuggestResult {
    let text = try validText(text)
    guard !source.isEmpty, !source.contains(where: \.isWhitespace) else {
      throw TaskOpsError.invalidSource
    }
    let key = Self.dedupeKey(text)
    if let existing = tasks.first(where: {
      ($0.status == .todo || $0.status == .pending) && Self.dedupeKey($0.text) == key
    }) {
      return .duplicate(of: existing.id)
    }
    if !categories.contains(where: \.isSuggested) { createCategory(Category.suggested) }
    let suggestion = Suggestion(source: source, day: today)
    let task = GlanceTask(text: text, due: due, suggestion: suggestion)
    return .added(try insert(task, into: Category.suggested, at: nil))
  }

  @discardableResult
  public mutating func acceptSuggestion(_ id: TaskID, into category: String? = nil) throws
    -> TaskID
  {
    guard task(id)?.suggestion != nil else { throw TaskOpsError.notASuggestion(id) }
    let name = try category.map(validName) ?? firstRegularCategory()
    guard name != Category.suggested else { throw TaskOpsError.reservedCategory }
    var task = try take(id)
    task.suggestion = nil
    return try insert(task, into: name, at: nil)
  }

  public mutating func dismissSuggestion(_ id: TaskID) throws {
    guard task(id)?.suggestion != nil else { throw TaskOpsError.notASuggestion(id) }
    try remove(id)
  }

  // MARK: - Helpers

  static func dedupeKey(_ text: String) -> String {
    text.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
  }

  private func validText(_ text: String) throws -> String {
    let text = text.trimmingCharacters(in: .whitespaces)
    guard !text.isEmpty else { throw TaskOpsError.emptyText }
    guard !text.contains(where: \.isNewline) else { throw TaskOpsError.multilineText }
    return text
  }

  private func validName(_ name: String) throws -> String {
    let name = name.trimmingCharacters(in: .whitespaces)
    guard !name.isEmpty, !name.contains(where: \.isNewline) else { throw TaskOpsError.invalidName }
    return name
  }

  private mutating func firstRegularCategory() -> String {
    if let first = categories.first(where: { !$0.isSuggested }) { return first.name }
    createCategory(Self.defaultCategory)
    return Self.defaultCategory
  }

  private func categoryIndex(_ name: String) throws -> Int {
    guard let index = categories.firstIndex(where: { $0.name == name }) else {
      throw TaskOpsError.categoryNotFound(name)
    }
    return index
  }

  private func locate(_ id: TaskID) throws -> (category: Int, entry: Int) {
    for cat in categories.indices {
      for row in categories[cat].entries.indices {
        if case .task(let task) = categories[cat].entries[row], task.id == id {
          return (cat, row)
        }
      }
    }
    throw TaskOpsError.taskNotFound(id)
  }

  private mutating func take(_ id: TaskID) throws -> GlanceTask {
    let (cat, row) = try locate(id)
    guard case .task(let task) = categories[cat].entries.remove(at: row) else {
      fatalError("located a task")
    }
    reindex()
    return task
  }

  /// Creates the category if needed, then inserts at `position` among its tasks, or after the last one.
  private mutating func insert(_ task: GlanceTask, into name: String, at position: Int?) throws
    -> TaskID
  {
    if !categories.contains(where: { $0.name == name }) { createCategory(name) }
    let cat = try categoryIndex(name)
    let taskRows = categories[cat].entries.indices.filter {
      if case .task = categories[cat].entries[$0] { true } else { false }
    }
    let row: Int =
      if let position, position < taskRows.count {
        taskRows[max(position, 0)]
      } else {
        taskRows.last.map { $0 + 1 } ?? 0
      }
    categories[cat].entries.insert(.task(task), at: row)
    reindex()
    guard case .task(let inserted) = categories[cat].entries[row] else {
      fatalError("just inserted")
    }
    return inserted.id
  }

  /// New categories go before `suggested`, which stays last.
  private mutating func createCategory(_ name: String) {
    let index =
      name == Category.suggested
      ? categories.endIndex
      : categories.firstIndex(where: \.isSuggested) ?? categories.endIndex
    categories.insert(Category(name: name), at: index)
    separateCategories()
  }

  /// Every header after the first follows a blank line, as in the canonical file.
  private mutating func separateCategories() {
    if !preamble.isEmpty, preamble.last != "", !categories.isEmpty { preamble.append("") }
    for cat in categories.indices.dropLast() where categories[cat].entries.last != .raw("") {
      categories[cat].entries.append(.raw(""))
    }
    reindex()
  }
}

public enum Counts {
  /// Open to-do tasks, the number on the ball. Pending tasks and suggestions are not counted.
  public static func todo(_ doc: GlanceDocument) -> Int {
    doc.categories.filter { !$0.isSuggested }.flatMap(\.tasks).count {
      $0.status == .todo && $0.kind == .checklist
    }
  }

  /// Open tasks due today or earlier, which tints the ball.
  public static func dueTodayOrOverdue(
    _ doc: GlanceDocument, now: Date, calendar: Calendar = .current
  ) -> Int {
    let today = CalendarDay(now, calendar: calendar)
    return doc.categories.filter { !$0.isSuggested }.flatMap(\.tasks).count {
      $0.kind == .checklist && ($0.status == .todo || $0.status == .pending)
        && $0.due.map { $0.day <= today } == true
    }
  }
}
