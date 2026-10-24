import Testing

@testable import GlanceCore

@Test func `canonical file round-trips byte for byte`() throws {
  let text = try fixture("canonical")
  #expect(MarkdownSerializer.serialize(MarkdownParser.parse(text)) == text)
}

@Test func `canonical file parses every field`() throws {
  let doc = MarkdownParser.parse(try fixture("canonical"))
  #expect(doc.categories.map(\.name) == ["work", "life", "study", "suggested"])

  let conference = try #require(doc.task(named: "register for Physical AI conference"))
  #expect(conference.status == .pending)
  #expect(conference.category == "work")
  #expect(conference.notes == "early-bird ends 11/01\nhttps://example.com/conf")

  let dentist = try #require(doc.task(named: "dentist"))
  #expect(dentist.due == DueDate(day: day("2026-10-28"), time: TimeOfDay(hour: 14, minute: 30)))

  let flight = try #require(doc.task(named: "book flight ticket"))
  #expect(flight.due == DueDate(day: day("2026-10-26")))

  let cases = try #require(doc.task(named: "buy iphone duo cases"))
  #expect(cases.status == .completed)
  #expect(cases.doneAt == day("2026-10-21"))

  #expect(doc.task(named: "old reading list")?.status == .cancelled)

  let dinner = try #require(doc.task(named: "book friday dinner"))
  #expect(dinner.suggestion == Suggestion(source: "claude-desktop", day: day("2026-10-20")))
  #expect(doc.categories.last?.isSuggested == true)
}

@Test(arguments: TaskStatus.allCases)
func `every status marker round-trips`(status: TaskStatus) {
  let text = "## a\n- [\(status.rawValue)] thing\n"
  let doc = MarkdownParser.parse(text)
  #expect(doc.tasks.map(\.status) == [status])
  #expect(MarkdownSerializer.serialize(doc) == text)
}

@Test func `empty file has no categories and stays empty`() {
  let doc = MarkdownParser.parse("")
  #expect(doc.categories.isEmpty)
  #expect(MarkdownSerializer.serialize(doc) == "")
}

@Test func `hand-edited file keeps every line that is not a task`() throws {
  let text = try fixture("messy")
  let output = MarkdownSerializer.serialize(MarkdownParser.parse(text))
  let outputLines = Set(output.split(separator: "\n", omittingEmptySubsequences: false))
  let kept = [
    "Some notes I typed before any header.",
    "* a star bullet I wrote by hand",
    "  - [ ] an indented subtask",
    "### a deeper heading",
    "-[ ] missing space is not a task",
    "##notaheader",
    "- [?] unknown marker",
    "- [ ] bad date stays text 📅 2026-13-45",
  ]
  for line in kept {
    #expect(outputLines.contains(Substring(line)), "lost: \(line)")
  }
}

@Test func `hand-edited file parses leniently`() throws {
  let doc = MarkdownParser.parse(try fixture("messy"))
  #expect(doc.categories.map(\.name) == ["work", "life"])
  #expect(doc.task(named: "shipped the deck")?.status == .completed)

  let outOfOrder = try #require(doc.task(named: "two tokens out of order ✅ 2026-10-21"))
  #expect(outOfOrder.due == DueDate(day: day("2026-10-26")))
  #expect(outOfOrder.doneAt == nil)

  #expect(doc.task(named: "bad date stays text 📅 2026-13-45")?.due == nil)

  let notes = doc.tasks.filter { $0.text == "same name" }.map(\.notes)
  #expect(notes == [nil, " indented note with extra spaces\n\nafter an empty note line"])
}

@Test func `hand-edited file is stable after one canonical pass`() throws {
  let once = MarkdownSerializer.serialize(MarkdownParser.parse(try fixture("messy")))
  #expect(MarkdownSerializer.serialize(MarkdownParser.parse(once)) == once)
  #expect(MarkdownParser.parse(once) == MarkdownParser.parse(try fixture("messy")))
}

@Test func `missing trailing newline is added and nothing else changes`() throws {
  let text = try fixture("no-newline")
  #expect(MarkdownSerializer.serialize(MarkdownParser.parse(text)) == text + "\n")
}

@Test func `duplicate texts in one category get distinct ids`() throws {
  let doc = MarkdownParser.parse(try fixture("messy"))
  let ids = doc.tasks.filter { $0.text == "same name" }.map(\.id.rawValue)
  #expect(ids == ["work/same name#0", "work/same name#1"])
}
