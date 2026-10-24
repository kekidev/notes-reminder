import Foundation
import Testing

@testable import GlanceCore

private let text = """
  ## a
  - [ ] keep
    > a note
  - [x] done ✅ 2026-10-21
  - bullet
  ### head
  plain line

  ## b
  - [ ] other

  """

@Test func `bodyLines lists a page's lines without notes or the trailing blank`() {
  let doc = MarkdownParser.parse(text)
  #expect(
    doc.bodyLines(of: "a")
      == ["- [ ] keep", "- [x] done ✅ 2026-10-21", "- bullet", "### head", "plain line"])
}

@Test func `replaceBody keeps ids and notes of unchanged lines`() throws {
  var doc = MarkdownParser.parse(text)
  let before = try #require(doc.task(named: "keep"))
  try doc.replaceBody(
    of: "a", with: ["new", "- [ ] keep", "- [x] done ✅ 2026-10-21", "- bullet", "### head"])
  let after = try #require(doc.task(named: "keep"))
  #expect(after.id == before.id)
  #expect(after.notes == "a note")
  #expect(doc.task(named: "done")?.doneAt == day("2026-10-21"))
  #expect(MarkdownSerializer.serialize(doc).hasSuffix("## b\n- [ ] other\n"))
  #expect(doc.bodyLines(of: "a").first == "new")
}

@Test func `replaceBody turns plain lines into raw entries and drops stale done dates`() throws {
  var doc = MarkdownParser.parse(text)
  try doc.replaceBody(of: "a", with: ["hello", "- [ ] done"])
  #expect(MarkdownSerializer.serialize(doc).hasPrefix("## a\nhello\n- [ ] done\n\n## b"))
  #expect(doc.task(named: "done")?.doneAt == nil)
}

@Test func `replaceBody never lets a newline into a line or a plain line start a page`() throws {
  var doc = MarkdownParser.parse(text)
  try doc.replaceBody(of: "a", with: ["x\ny", "## sneaky"])
  #expect(doc.categories.map(\.name) == ["a", "b"])
  #expect(doc.bodyLines(of: "a") == ["x", "y", " ## sneaky"])
}

@Test func `replaceBody on a missing page throws`() {
  var doc = MarkdownParser.parse(text)
  #expect(throws: TaskOpsError.categoryNotFound("zz")) { try doc.replaceBody(of: "zz", with: []) }
}

@Test func `replaceBody keeps a cancelled line cancelled when saved as checked`() throws {
  var doc = MarkdownParser.parse("## a\n- [-] dropped\n- [ ] keep\n")
  try doc.replaceBody(of: "a", with: ["- [x] dropped", "- [ ] keep", "- [ ] new"])
  #expect(doc.task(named: "dropped")?.status == .cancelled)
  #expect(doc.task(named: "dropped")?.doneAt == nil)
}
