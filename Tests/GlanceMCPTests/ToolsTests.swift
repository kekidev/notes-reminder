import Foundation
import GlanceCore
import GlanceMCP
import MCP
import Testing

private let seed = """
  ---
  glance: 1
  ---

  intro line nobody parses

  ## work
  - [ ] weekly report
  - [/] conference 📅 2026-10-21
    > early-bird
  random unknown line

  ## life
  - [ ] dentist 📅 2026-10-22 14:30
  - [ ] book flight 📅 2026-10-26
  - [x] buy cases ✅ 2026-10-21
  - [-] old thing
  <!-- keep me -->

  ## suggested
  - [ ] book friday dinner 🤖 claude-desktop 2026-10-20

  """

private let now = Calendar.current.date(
  from: DateComponents(year: 2026, month: 10, day: 22, hour: 12))!

private struct Fixture {
  let url: URL
  let store: FileStore

  init() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: "glance-mcp-\(UUID())")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    url = dir.appending(path: "todo.md")
    try seed.write(to: url, atomically: true, encoding: .utf8)
    store = FileStore(url: url)
  }

  var contents: String { (try? String(contentsOf: url, encoding: .utf8)) ?? "" }

  /// Calls the tool and returns its decoded JSON, failing the test on an error result.
  func call(_ name: String, _ arguments: [String: Value] = [:]) throws -> Value {
    let result = GlanceTools.handle(name, arguments, store: store, now: now)
    let text = try #require(Self.text(result))
    #expect(result.isError != true, "\(name) failed: \(text)")
    return try JSONDecoder().decode(Value.self, from: Data(text.utf8))
  }

  /// Calls the tool, expects an error result, and returns its message.
  func error(_ name: String, _ arguments: [String: Value] = [:]) throws -> String {
    let result = GlanceTools.handle(name, arguments, store: store, now: now)
    #expect(result.isError == true)
    return try #require(Self.text(result))
  }

  private static func text(_ result: CallTool.Result) -> String? {
    guard case .text(let text, _, _)? = result.content.first else { return nil }
    return text
  }
}

private func ids(_ value: Value) -> [String] {
  (value.arrayValue ?? []).compactMap { $0.objectValue?["id"]?.stringValue }
}

private func assertUnknownLinesKept(_ text: String) {
  for line in ["intro line nobody parses", "random unknown line", "<!-- keep me -->"] {
    #expect(text.contains(line))
  }
}

@Test func `tool list names every tool`() {
  #expect(
    GlanceTools.all.map(\.name) == [
      "list_tasks", "get_summary", "add_task", "suggest_tasks", "update_task", "complete_task",
      "cancel_task", "list_categories", "add_category",
    ])
  let add = GlanceTools.all.first { $0.name == "add_task" }
  #expect(add?.description?.contains("suggest_tasks") == true)
}

@Test func `list_tasks returns every task as JSON`() throws {
  let tasks = try Fixture().call("list_tasks")
  #expect(tasks.arrayValue?.count == 7)
  let conference = try #require(tasks.arrayValue?.first { $0.objectValue?["text"] == "conference" })
  #expect(
    conference
      == .object([
        "id": "work/conference#0", "text": "conference", "status": "pending", "category": "work",
        "due": "2026-10-21", "doneAt": .null, "notes": "early-bird", "suggested": false,
        "kind": "checklist",
        "indent": 0,
      ]))
  let dentist = try #require(tasks.arrayValue?.first { $0.objectValue?["text"] == "dentist" })
  #expect(dentist.objectValue?["due"] == "2026-10-22 14:30")
  let cases = try #require(tasks.arrayValue?.first { $0.objectValue?["text"] == "buy cases" })
  #expect(cases.objectValue?["doneAt"] == "2026-10-21")
  #expect(ids(tasks).contains("suggested/book friday dinner#0"))
  #expect(
    tasks.arrayValue?.first { $0.objectValue?["category"] == "suggested" }?.objectValue?[
      "suggested"] == true)
}

@Test func `list_tasks filters by status, category, and due`() throws {
  let store = try Fixture()
  #expect(
    ids(try store.call("list_tasks", ["status": "todo"])) == [
      "work/weekly report#0", "life/dentist#0", "life/book flight#0",
      "suggested/book friday dinner#0",
    ])
  #expect(ids(try store.call("list_tasks", ["category": "life"])).count == 4)
  #expect(
    ids(try store.call("list_tasks", ["due": "today"])) == [
      "work/conference#0", "life/dentist#0",
    ])
  #expect(ids(try store.call("list_tasks", ["due": "upcoming"])) == ["life/book flight#0"])
  #expect(
    ids(try store.call("list_tasks", ["due": "none"])) == [
      "work/weekly report#0", "life/buy cases#0", "life/old thing#0",
      "suggested/book friday dinner#0",
    ])
  #expect(
    ids(try store.call("list_tasks", ["status": "todo", "category": "life", "due": "today"]))
      == ["life/dentist#0"])
}

@Test func `list_tasks rejects an unknown status or due filter`() throws {
  let store = try Fixture()
  let status = try store.error("list_tasks", ["status": "done"])
  #expect(status.contains("status") && status.contains("todo, pending, completed, cancelled"))
  let due = try store.error("list_tasks", ["due": "tomorrow"])
  #expect(due.contains("due") && due.contains("today, upcoming, none"))
}

@Test func `get_summary counts to-do tasks and lists what is due`() throws {
  let summary = try Fixture().call("get_summary").objectValue
  #expect(summary?["todo"] == 3)
  #expect(summary?["dueTodayOrOverdue"] == 2)
  #expect(ids(summary?["dueTasks"] ?? .null) == ["work/conference#0", "life/dentist#0"])
}

@Test func `add_task writes the task and keeps unknown lines`() throws {
  let store = try Fixture()
  let task = try store.call(
    "add_task", ["text": "call mom", "category": "life", "due": "2026-10-30 09:15"])
  #expect(task.objectValue?["id"] == "life/call mom#0")
  #expect(store.contents.contains("- [-] old thing\n- [ ] call mom 📅 2026-10-30 09:15\n"))
  assertUnknownLinesKept(store.contents)

  _ = try store.call("add_task", ["text": "no category"])
  #expect(store.contents.contains("- [ ] no category\n"))
}

@Test func `add_task rejects bad input and leaves the file alone`() throws {
  let store = try Fixture()
  for due in ["10/25", "2026-10-25 9:00", "2026-02-30", "2026-10-25 25:00"] {
    let message = try store.error("add_task", ["text": "hw", "due": .string(due)])
    #expect(message.contains("due") && message.contains("YYYY-MM-DD HH:mm"), "\(due)")
  }
  #expect(try store.error("add_task", ["text": "   "]).contains("text"))
  #expect(try store.error("add_task", [:]).contains("text"))
  #expect(try store.error("add_task", ["text": 5]).contains("text"))
  #expect(try store.error("add_task", ["text": "x", "category": "suggested"]).contains("suggest"))
  #expect(store.contents == seed)
}

@Test func `suggest_tasks adds to suggested, stores the reason, and skips duplicates`() throws {
  let store = try Fixture()
  let result = try store.call(
    "suggest_tasks",
    [
      "tasks": [
        ["text": "Book  Friday dinner"],
        ["text": "call plumber", "due": "2026-10-24", "reason": "mentioned a leak"],
      ]
    ]
  ).objectValue
  #expect(result?["added"] == ["suggested/call plumber#0"])
  #expect(
    result?["skipped"] == [
      ["text": "Book  Friday dinner", "duplicateOf": "suggested/book friday dinner#0"]
    ])
  #expect(
    store.contents.hasSuffix(
      "- [ ] call plumber 📅 2026-10-24 🤖 claude-desktop 2026-10-22\n  > mentioned a leak\n"))
  assertUnknownLinesKept(store.contents)

  _ = try store.call("suggest_tasks", ["tasks": [["text": "water plants"]], "source": "chatgpt"])
  #expect(store.contents.hasSuffix("- [ ] water plants 🤖 chatgpt 2026-10-22\n"))
}

@Test func `suggest_tasks validates every task before writing`() throws {
  let store = try Fixture()
  #expect(try store.error("suggest_tasks", [:]).contains("tasks"))
  let bad = try store.error(
    "suggest_tasks", ["tasks": [["text": "ok"], ["text": "bad", "due": "soon"]]])
  #expect(bad.contains("due"))
  #expect(try store.error("suggest_tasks", ["tasks": [["text": ""]]]).contains("text"))
  #expect(
    try store.error("suggest_tasks", ["tasks": [["text": "x"]], "source": "two words"])
      .contains("source"))
  #expect(store.contents == seed)
}

@Test func `update_task edits fields and moves categories`() throws {
  let store = try Fixture()
  let task = try store.call(
    "update_task",
    [
      "id": "work/weekly report#0", "text": "weekly report v2", "category": "life",
      "due": "2026-11-01", "notes": "draft\nsecond line", "status": "pending",
    ])
  #expect(task.objectValue?["id"] == "life/weekly report v2#0")
  #expect(task.objectValue?["status"] == "pending")
  #expect(
    store.contents.contains(
      "- [/] weekly report v2 📅 2026-11-01\n  > draft\n  > second line\n<!-- keep me -->"))

  let cleared = try store.call("update_task", ["id": "life/weekly report v2#0", "due": ""])
  #expect(cleared.objectValue?["due"] == .null)
  let nulled = try store.call("update_task", ["id": "life/dentist#0", "due": .null, "notes": ""])
  #expect(nulled.objectValue?["due"] == .null)
  #expect(store.contents.contains("- [ ] dentist\n"))
  assertUnknownLinesKept(store.contents)
}

@Test func `update_task keeps due and notes it was not given`() throws {
  let store = try Fixture()
  _ = try store.call("update_task", ["id": "life/dentist#0", "notes": "bring insurance card"])
  _ = try store.call("update_task", ["id": "life/dentist#0", "text": "dentist checkup"])
  #expect(
    store.contents.contains("- [ ] dentist checkup 📅 2026-10-22 14:30\n  > bring insurance card"))
  _ = try store.call("update_task", ["id": "life/dentist checkup#0", "category": "work"])
  #expect(
    store.contents.contains("- [ ] dentist checkup 📅 2026-10-22 14:30\n  > bring insurance card"))
}

@Test func `update_task cannot move a suggestion out of suggested`() throws {
  let store = try Fixture()
  #expect(
    try store.error("update_task", ["id": "suggested/book friday dinner#0", "category": "life"])
      == "Suggestions can only be accepted in the Glance app.")
  #expect(store.contents == seed)
  let edited = try store.call(
    "update_task", ["id": "suggested/book friday dinner#0", "text": "book saturday dinner"])
  #expect(edited.objectValue?["suggested"] == true)
}

@Test func `update_task rejects an unknown id, status, or category`() throws {
  let store = try Fixture()
  #expect(try store.error("update_task", ["id": "work/nope#0"]).contains("work/nope#0"))
  #expect(try store.error("update_task", [:]).contains("id"))
  #expect(
    try store.error("update_task", ["id": "work/weekly report#0", "status": "done"])
      .contains("status"))
  #expect(
    try store.error("update_task", ["id": "work/weekly report#0", "category": "errands"])
      .contains("errands"))
  #expect(
    try store.error("update_task", ["id": "work/weekly report#0", "text": ""]).contains("text"))
  #expect(store.contents == seed)
}

@Test func `complete_task and cancel_task set the status`() throws {
  let store = try Fixture()
  let done = try store.call("complete_task", ["id": "work/weekly report#0"])
  #expect(done.objectValue?["status"] == "completed")
  #expect(done.objectValue?["doneAt"] == "2026-10-22")
  let cancelled = try store.call("cancel_task", ["id": "life/book flight#0"])
  #expect(cancelled.objectValue?["status"] == "cancelled")
  #expect(store.contents.contains("- [x] weekly report ✅ 2026-10-22\n"))
  #expect(store.contents.contains("- [-] book flight 📅 2026-10-26\n"))
  #expect(try store.error("complete_task", ["id": "x"]).contains("No task"))
}

@Test func `list_categories and add_category`() throws {
  let store = try Fixture()
  #expect(try store.call("list_categories") == ["work", "life", "suggested"])
  #expect(
    try store.call("add_category", ["name": "study"]) == ["work", "life", "study", "suggested"])
  #expect(try store.call("list_categories") == ["work", "life", "study", "suggested"])
  #expect(try store.error("add_category", ["name": "work"]).contains("already exists"))
  #expect(try store.error("add_category", ["name": " "]).contains("name"))
  assertUnknownLinesKept(store.contents)
}

@Test func `unknown tool is an error`() throws {
  #expect(try Fixture().error("delete_everything").contains("delete_everything"))
}
