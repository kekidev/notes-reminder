import Foundation
import Testing

@testable import GlanceCore

private let today = day("2026-10-23")
private let file = [
  "### h", "- [ ] a", "- [x] done1 ✅ 2026-10-01", "  - [x] done2 ✅ 2026-10-02", "- [ ] b",
  "- [x] done1 ✅ 2026-10-03",
]
/// What the editor shows of `file`: crossed-out lines are hidden.
private let visible = ["### h", "- [ ] a", "- [ ] b"]

private func page(_ lines: [String]) -> GlanceDocument {
  MarkdownParser.parse((["## p"] + lines).joined(separator: "\n") + "\n")
}

private func save(_ edited: [String], over lines: [String] = file, base: [String] = visible)
  throws -> (lines: [String], added: [String])
{
  var doc = page(lines)
  let added = try doc.savePage("p", edited: edited, base: base, today: today)
  return (doc.bodyLines(of: "p"), added)
}

@Test func `a save keeps every hidden line in place`() throws {
  #expect(try save(visible).lines == file)
}

@Test func `edits around hidden lines keep them`() throws {
  let out = try save(["### h", "- [ ] a2", "- [ ] b", "- [ ] new"]).lines
  #expect(out.count { $0.hasPrefix("- [x] done1 ✅") } == 2)
  #expect(out.contains("  - [x] done2 ✅ 2026-10-02"))
}

@Test func `indenting a visible line keeps hidden lines`() throws {
  #expect(
    try save(["### h", "  - [ ] a", "- [ ] b"]).lines
      == [
        "### h", "  - [ ] a", "- [x] done1 ✅ 2026-10-01", "  - [x] done2 ✅ 2026-10-02",
        "- [ ] b", "- [x] done1 ✅ 2026-10-03",
      ])
}

@Test func `emptying the editor keeps hidden lines`() throws {
  #expect(try save([]).lines == Array(file.filter { $0.contains("✅") }))
}

@Test func `a line another writer added survives and is returned`() throws {
  let out = try save(
    ["- [ ] a", "- [ ] mine"], over: ["- [ ] a", "- [ ] from claude"], base: ["- [ ] a"])
  #expect(out.lines == ["- [ ] a", "- [ ] from claude", "- [ ] mine"])
  #expect(out.added == ["- [ ] from claude"])
}

@Test func `nothing is added back when only the editor changed`() throws {
  #expect(try save(["- [ ] a"], over: ["- [ ] a"], base: ["- [ ] a"]).added.isEmpty)
}

@Test func `a crossed-out line still shown can be deleted`() throws {
  let shown = ["- [ ] a", "- [x] mis"]
  #expect(try save(["- [ ] a"], over: shown, base: shown).lines == ["- [ ] a"])
}

@Test func `unchecking a shown line keeps it as a todo`() throws {
  let out = try save(
    ["- [ ] a", "- [ ] mis"],
    over: ["- [ ] a", "- [x] mis ✅ 2026-10-22", "- [x] old ✅ 2026-10-01"],
    base: ["- [ ] a", "- [x] mis"])
  #expect(out.lines == ["- [ ] a", "- [ ] mis", "- [x] old ✅ 2026-10-01"])
}

@Test func `a line checked in the editor gets today's done date and old dates stay`() throws {
  let lines = ["- [ ] a", "- [x] b ✅ 2026-10-01"]
  let out = try save(["- [x] a", "- [x] b"], over: lines, base: ["- [ ] a", "- [x] b"])
  #expect(out.lines == ["- [x] a ✅ \(today)", "- [x] b ✅ 2026-10-01"])
}

@Test func `a hidden cancelled line stays cancelled through a save`() throws {
  var doc = page(["- [-] dropped", "- [ ] a"])
  try doc.savePage("p", edited: ["- [ ] a", "- [ ] new"], base: ["- [ ] a"], today: today)
  #expect(doc.task(named: "dropped")?.status == .cancelled)
  #expect(doc.task(named: "dropped")?.doneAt == nil)
}

@Test func `saving a page that doesn't exist creates it`() throws {
  var doc = MarkdownParser.parse("## other\n")
  try doc.savePage("notes", edited: ["- [ ] first"], base: [], today: today)
  #expect(doc.bodyLines(of: "notes") == ["- [ ] first"])
}
