import Testing

@testable import GlanceCore

@Test func `indent parses from leading pairs and round-trips`() throws {
  let text = try fixture("indent")
  let doc = MarkdownParser.parse(text)
  #expect(MarkdownSerializer.serialize(doc) == text)
  #expect(doc.tasks.map(\.indent) == [0, 1, 2, 1, 4])
  #expect(doc.task(named: "bullet child")?.notes == "a note on the bullet")
  #expect(doc.task(named: "four deep")?.kind == .checklist)
  #expect(doc.task(named: "heading never indents") == nil)
  #expect(Counts.todo(doc) == 3)
}

@Test func `replaceBody keeps indent and the notes of an indented task`() throws {
  var doc = MarkdownParser.parse("## a\n- [ ] x\n  > n\n")
  try doc.replaceBody(of: "a", with: ["  - [ ] x", "- y"])
  #expect(MarkdownSerializer.serialize(doc) == "## a\n  - [ ] x\n  > n\n- y\n")
  #expect(doc.tasks.map(\.indent) == [1, 0])
}
