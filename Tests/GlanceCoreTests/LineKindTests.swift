import Foundation
import Testing

@testable import GlanceCore

@Test func `line kinds round-trip and parse by marker`() throws {
  let text = try fixture("line-kinds")
  let doc = MarkdownParser.parse(text)
  #expect(MarkdownSerializer.serialize(doc) == text)
  #expect(
    doc.tasks.map(\.kind) == [.heading, .checklist, .checklist, .heading, .checklist, .bullet])
  #expect(doc.task(named: "work")?.status == .todo)
}

@Test func `bracket lines that are not checkboxes stay raw`() {
  let text = "## a\n- [\n- [?] x\n- \n"
  let doc = MarkdownParser.parse(text)
  #expect(doc.tasks.isEmpty)
  #expect(MarkdownSerializer.serialize(doc) == text)
}

@Test func `only checklist lines count toward the ball or due`() throws {
  let doc = MarkdownParser.parse(try fixture("line-kinds"))
  #expect(Counts.todo(doc) == 2)
  let now = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 23))!
  #expect(Counts.dueTodayOrOverdue(doc, now: now) == 1)
}

@Test func `a task changes kind and drops its checklist state`() throws {
  var doc = MarkdownParser.parse("## a\n- [ ] x 📅 2026-10-22\n")
  let id = try doc.update(try #require(doc.tasks.first).id) { $0.kind = .bullet }
  #expect(MarkdownSerializer.serialize(doc) == "## a\n- x\n")
  try doc.update(id) { $0.kind = .heading }
  #expect(MarkdownSerializer.serialize(doc) == "## a\n### x\n")
  try doc.update(id) { $0.kind = .checklist }
  #expect(MarkdownSerializer.serialize(doc) == "## a\n- [ ] x\n")
}

@Test func `removeCompleted drops crossed-out checklist lines of one page`() throws {
  var doc = MarkdownParser.parse(
    "## a\n- [x] one\n- [ ] two\n- [-] three\n- bullet\n\n## b\n- [x] other\n")
  #expect(try doc.removeCompleted(in: "a") == 2)
  #expect(MarkdownSerializer.serialize(doc) == "## a\n- [ ] two\n- bullet\n\n## b\n- [x] other\n")
  #expect(try doc.removeCompleted(in: "a") == 0)
  #expect(throws: TaskOpsError.categoryNotFound("zz")) { try doc.removeCompleted(in: "zz") }
}
