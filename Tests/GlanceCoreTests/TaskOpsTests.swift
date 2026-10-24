import Foundation
import Testing

@testable import GlanceCore

private let today = day("2026-10-22")

private func canonical() throws -> GlanceDocument { MarkdownParser.parse(try fixture("canonical")) }

private func id(_ doc: GlanceDocument, _ text: String) throws -> TaskID {
  try #require(doc.task(named: text)).id
}

@Test func `add appends after the last task, before the blank line`()
  throws
{
  var doc = try canonical()
  let added = try doc.add("call mom", category: "work")
  #expect(doc.task(added)?.category == "work")
  #expect(
    MarkdownSerializer.serialize(doc).contains(
      "  > https://example.com/conf\n- [ ] call mom\n\n## life"))
}

@Test func `add with no category uses the first one, and a new name creates the category`() throws {
  var doc = try canonical()
  let first = try doc.add("a")
  #expect(doc.task(first)?.category == "work")
  let errand = try doc.add("b", category: "errands", due: DueDate(day: today))
  #expect(doc.task(errand)?.due?.day == today)
  #expect(doc.categories.map(\.name) == ["work", "life", "study", "errands", "suggested"])

  var empty = MarkdownParser.parse("")
  let inbox = try empty.add("first")
  #expect(empty.task(inbox)?.category == "notes")
}

@Test func `add rejects blank text, multi-line text, and the suggested category`() throws {
  var doc = try canonical()
  #expect(throws: TaskOpsError.emptyText) { try doc.add("   ") }
  #expect(throws: TaskOpsError.multilineText) { try doc.add("a\nb") }
  #expect(throws: TaskOpsError.reservedCategory) { try doc.add("x", category: "suggested") }
}

@Test func `update edits fields but cannot change identity`() throws {
  var doc = try canonical()
  let newID = try doc.update(try id(doc, "weekly report")) {
    $0.text = "weekly report v2"
    $0.notes = "draft in drive"
    $0.category = "life"
  }
  let task = try #require(doc.task(newID))
  #expect(task.text == "weekly report v2")
  #expect(task.notes == "draft in drive")
  #expect(task.category == "work")
  #expect(throws: TaskOpsError.emptyText) { try doc.update(newID) { $0.text = "" } }
  #expect(throws: TaskOpsError.taskNotFound(TaskID(rawValue: "nope"))) {
    try doc.update(TaskID(rawValue: "nope")) { _ in }
  }
}

@Test func `completing stamps the day and reopening clears it`() throws {
  var doc = try canonical()
  let done = try doc.setStatus(try id(doc, "get groceries"), .completed, today: today)
  #expect(doc.task(done)?.doneAt == today)
  let reopened = try doc.setStatus(done, .pending, today: today)
  #expect(doc.task(reopened)?.doneAt == nil)
  #expect(doc.task(reopened)?.status == .pending)
}

@Test func `move reorders within a category and across categories`() throws {
  var doc = try canonical()
  _ = try doc.move(try id(doc, "traffic analysis"), to: "work", at: 0)
  #expect(doc.categories[0].tasks.map(\.text).prefix(2) == ["traffic analysis", "weekly report"])

  let moved = try doc.move(try id(doc, "Hw 6"), to: "life", at: 1)
  #expect(doc.categories[1].tasks.map(\.text)[1] == "Hw 6")
  #expect(doc.task(moved)?.category == "life")
  #expect(throws: TaskOpsError.categoryNotFound("nowhere")) { try doc.move(moved, to: "nowhere") }
  #expect(throws: TaskOpsError.reservedCategory) { try doc.move(moved, to: "suggested") }
}

@Test func `remove deletes the task and its notes`() throws {
  var doc = try canonical()
  try doc.remove(try id(doc, "register for Physical AI conference"))
  #expect(!MarkdownSerializer.serialize(doc).contains("early-bird"))
}

@Test func `categories can be added, renamed, reordered, and removed`() throws {
  var doc = try canonical()
  try doc.addCategory("content")
  #expect(doc.categories.map(\.name) == ["work", "life", "study", "content", "suggested"])
  #expect(
    MarkdownSerializer.serialize(doc).contains(
      "- [-] old reading list\n\n## content\n\n## suggested"))
  #expect(throws: TaskOpsError.categoryExists("work")) { try doc.addCategory("work") }
  #expect(throws: TaskOpsError.invalidName) { try doc.addCategory(" ") }
  #expect(throws: TaskOpsError.reservedCategory) { try doc.addCategory("suggested") }

  try doc.renameCategory("life", to: "home")
  #expect(doc.task(named: "dentist")?.id.rawValue == "home/dentist#0")
  #expect(throws: TaskOpsError.categoryExists("work")) {
    try doc.renameCategory("home", to: "work")
  }

  try doc.reorderCategories(["suggested", "study", "content", "home", "work"])
  #expect(doc.categories.map(\.name) == ["suggested", "study", "content", "home", "work"])
  #expect(throws: TaskOpsError.invalidOrder) { try doc.reorderCategories(["work"]) }
  let text = MarkdownSerializer.serialize(doc)
  #expect(MarkdownParser.parse(text) == doc)
  #expect(
    text.components(separatedBy: "\n## ").count == text.components(separatedBy: "\n\n## ").count,
    "every header follows a blank line")

  try doc.removeCategory("study")
  #expect(doc.task(named: "Hw 6") == nil)
  #expect(throws: TaskOpsError.categoryNotFound("study")) { try doc.removeCategory("study") }
}

@Test func `suggest dedupes against open tasks and earlier suggestions`() throws {
  var doc = try canonical()
  let fresh = try doc.suggest("Plan  the trip", due: nil, source: "claude-desktop", today: today)
  guard case .added(let newID) = fresh else {
    Issue.record("expected added")
    return
  }
  #expect(doc.task(newID)?.suggestion == Suggestion(source: "claude-desktop", day: today))
  #expect(doc.task(newID)?.category == "suggested")

  #expect(
    try doc.suggest("get Groceries ", due: nil, source: "x", today: today)
      == .duplicate(of: try id(doc, "get groceries")))
  #expect(
    try doc.suggest("plan the trip", due: nil, source: "x", today: today) == .duplicate(of: newID))
  if case .added = try doc.suggest("buy iphone duo cases", due: nil, source: "x", today: today) {
  } else {
    Issue.record("a completed task is not a duplicate")
  }

  #expect(throws: TaskOpsError.emptyText) {
    try doc.suggest(" ", due: nil, source: "x", today: today)
  }
  #expect(throws: TaskOpsError.invalidSource) {
    try doc.suggest("a", due: nil, source: "two words", today: today)
  }

  var empty = MarkdownParser.parse("")
  _ = try empty.suggest("first", due: nil, source: "x", today: today)
  #expect(empty.categories.map(\.name) == ["suggested"])
}

@Test func `accepting a suggestion moves it into a category and drops the marker`() throws {
  var doc = try canonical()
  let accepted = try doc.acceptSuggestion(try id(doc, "book friday dinner"), into: "life")
  let task = try #require(doc.task(accepted))
  #expect(task.category == "life")
  #expect(task.suggestion == nil)
  #expect(doc.categories.last?.tasks.isEmpty == true)
  #expect(throws: TaskOpsError.notASuggestion(accepted)) { try doc.acceptSuggestion(accepted) }
}

@Test func `dismissing a suggestion removes it, and only suggestions can be dismissed`() throws {
  var doc = try canonical()
  try doc.dismissSuggestion(try id(doc, "book friday dinner"))
  #expect(doc.task(named: "book friday dinner") == nil)
  let report = try id(doc, "weekly report")
  #expect(throws: TaskOpsError.notASuggestion(report)) { try doc.dismissSuggestion(report) }
}

@Test func `counts ignore suggestions and closed tasks`() throws {
  let doc = try canonical()
  #expect(Counts.todo(doc) == 6)
  let calendar = Calendar(identifier: .gregorian)
  let noonOn = { (text: String) in
    calendar.date(from: DateComponents(year: 2026, month: 10, day: Int(text)!, hour: 12))!
  }
  #expect(Counts.dueTodayOrOverdue(doc, now: noonOn("24"), calendar: calendar) == 0)
  #expect(Counts.dueTodayOrOverdue(doc, now: noonOn("25"), calendar: calendar) == 1)
  #expect(Counts.dueTodayOrOverdue(doc, now: noonOn("28"), calendar: calendar) == 3)
}
