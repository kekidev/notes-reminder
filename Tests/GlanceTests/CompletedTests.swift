import Foundation
import GlanceCore
import Testing

@testable import Glance

private let sample = """
  ## work
  - [x] old ✅ 2026-10-01
  - [ ] open
  - [x] new ✅ 2026-10-20
    - [x] nested ✅ 2026-10-10

  ## home
  - [x] undated
  - [x] newest ✅ 2026-10-22
  - note line

  """

private func state() throws -> AppState {
  let dir = FileManager.default.temporaryDirectory.appending(path: "glance-\(UUID())")
  try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  let url = dir.appending(path: "todo.md")
  try sample.write(to: url, atomically: true, encoding: .utf8)
  return AppState(url: url)
}

struct CompletedTests {
  @Test func listsCrossedOutLinesOfEveryPageNewestFirstUndatedLast() throws {
    let items = completedItems(try state().document)
    #expect(items.map(\.task.text) == ["newest", "new", "nested", "old", "undated"])
    #expect(items.map(\.page) == ["home", "work", "work", "work", "home"])
  }

  @Test func restoringALineBringsItBackInPlaceAndOutOfTheList() throws {
    let state = try state()
    let id = try #require(completedItems(state.document).first { $0.task.text == "new" }).id
    state.perform { try $0.setStatus(id, .todo, today: CalendarDay(.now)) }
    #expect(state.document.bodyLines(of: "work")[1...2] == ["- [ ] open", "- [ ] new"])
    #expect(completedItems(state.document).count == 4)
  }

  @Test func deletingRemovesOneLine() throws {
    let state = try state()
    let id = try #require(completedItems(state.document).first { $0.task.text == "old" }).id
    state.perform { try $0.remove(id) }
    #expect(completedItems(state.document).count == 4)
  }

  @Test func clearAllRemovesEveryPagesCrossedOutLinesAndKeepsTheRest() throws {
    let state = try state()
    state.perform { try clearCompleted(&$0) }
    #expect(completedItems(state.document).isEmpty)
    #expect(state.document.bodyLines(of: "work") == ["- [ ] open"])
    #expect(state.document.bodyLines(of: "home") == ["- note line"])
  }

  @Test func crossedOutLinesDoNotCount() throws {
    #expect(try state().todoCount == 2)
  }
}
