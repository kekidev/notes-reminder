import Foundation

public enum MarkdownParser {
  public static func parse(_ text: String) -> GlanceDocument {
    var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    if lines.last == "" { lines.removeLast() }

    var doc = GlanceDocument()
    for line in lines {
      if let name = categoryName(line) {
        doc.categories.append(Category(name: name))
      } else if doc.categories.isEmpty {
        doc.preamble.append(line)
      } else {
        doc.categories[doc.categories.endIndex - 1].append(line)
      }
    }
    doc.reindex()
    return doc
  }

  private static func categoryName(_ line: String) -> String? {
    guard line.hasPrefix("## ") else { return nil }
    let name = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
    return name.isEmpty ? nil : name
  }

  static func noteLine(_ line: String) -> String? {
    guard let match = line.wholeMatch(of: /\s+> ?(.*)/) else { return nil }
    return String(match.1)
  }

  static func taskLine(_ line: String) -> GlanceTask? {
    // Odd or deeper spacing doesn't match below, so such a line stays raw and round-trips.
    let spaces = line.prefix { $0 == " " }.count
    let indent = min(spaces / 2, GlanceTask.maxIndent)
    let line = String(line.dropFirst(indent * 2))
    var task: GlanceTask
    if let match = line.wholeMatch(of: /- \[([ \/xX-])\] (.*)/),
      let status = TaskStatus(rawValue: match.1.lowercased())
    {
      task = GlanceTask(text: String(match.2), status: status, indent: indent)
    } else if indent == 0, let match = line.wholeMatch(of: /### (\S.*)/) {
      return GlanceTask(text: String(match.1), kind: .heading)
    } else if let match = line.wholeMatch(of: /- ([^\s\[].*)/) {
      return GlanceTask(text: String(match.1), kind: .bullet, indent: indent)
    } else {
      return nil
    }

    // Tokens are read only from the end, in canonical order, so an odd token stays in the text.
    if let found = task.text.firstMatch(of: /(?<rest>.*) 🤖 (?<source>\S+) (?<day>\S+)$/),
      let suggested = calendarDay(found.day)
    {
      task.suggestion = Suggestion(source: String(found.source), day: suggested)
      task.text = String(found.rest)
    }
    if let found = task.text.firstMatch(of: /(?<rest>.*) ✅ (?<day>\S+)$/),
      let done = calendarDay(found.day)
    {
      task.doneAt = done
      task.text = String(found.rest)
    }
    if let found = task.text.firstMatch(
      of: /(?<rest>.*) 📅 (?<day>\S+)(?: (?<hour>\d\d):(?<minute>\d\d))?$/),
      let due = calendarDay(found.day)
    {
      let time = found.hour.flatMap { hour in
        found.minute.flatMap { TimeOfDay(hour: Int(hour)!, minute: Int($0)!) }
      }
      if found.hour == nil || time != nil {
        task.due = DueDate(day: due, time: time)
        task.text = String(found.rest)
      }
    }
    return task
  }

  static func calendarDay(_ text: Substring) -> CalendarDay? {
    guard let date = text.wholeMatch(of: /(\d{4})-(\d{2})-(\d{2})/) else { return nil }
    return CalendarDay(year: Int(date.1)!, month: Int(date.2)!, day: Int(date.3)!)
  }
}

extension Category {
  /// Indented `> ` lines directly under a task become its notes; anything else is an entry.
  fileprivate mutating func append(_ line: String) {
    if let note = MarkdownParser.noteLine(line), case .task(var task)? = entries.last {
      task.notes = task.notes.map { $0 + "\n" + note } ?? note
      entries[entries.endIndex - 1] = .task(task)
    } else {
      entries.append(MarkdownParser.taskLine(line).map(Entry.task) ?? .raw(line))
    }
  }
}

public enum MarkdownSerializer {
  public static func serialize(_ doc: GlanceDocument) -> String {
    var lines = doc.preamble
    for category in doc.categories {
      lines.append("## \(category.name)")
      for entry in category.entries {
        switch entry {
        case .raw(let line): lines.append(line)
        case .task(let task): lines.append(contentsOf: taskLines(task))
        }
      }
    }
    return lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
  }

  static func taskLines(_ task: GlanceTask) -> [String] {
    var line =
      switch task.kind {
      case .heading: "### \(task.text)"
      case .bullet: "- \(task.text)"
      case .checklist: "- [\(task.status.rawValue)] \(task.text)"
      }
    if task.kind != .heading { line = String(repeating: "  ", count: task.indent) + line }
    if task.kind == .checklist {  // other kinds carry no tokens
      if let due = task.due { line += " 📅 \(due.day)" + (due.time.map { " \($0)" } ?? "") }
      if let done = task.doneAt { line += " ✅ \(done)" }
      if let suggestion = task.suggestion { line += " 🤖 \(suggestion.source) \(suggestion.day)" }
    }
    let notes = task.notes.map { $0.split(separator: "\n", omittingEmptySubsequences: false) } ?? []
    return [line] + notes.map { $0.isEmpty ? "  >" : "  > \($0)" }
  }
}
