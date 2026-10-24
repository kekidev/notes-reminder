import Foundation
import GlanceCore
import Testing

@testable import Glance

private func tempFile(_ text: String) throws -> URL {
  let dir = FileManager.default.temporaryDirectory.appending(path: "glance-\(UUID())")
  try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  let url = dir.appending(path: "todo.md")
  try text.write(to: url, atomically: true, encoding: .utf8)
  return url
}

private let sample = """
  ## work
  - [ ] report 📅 \(CalendarDay(.now))
  - [/] call
  - [x] done

  ## suggested
  - [ ] idea 🤖 claude 2026-10-20

  """

struct AppStateTests {
  @Test func loadsCountsFromAnExistingFile() throws {
    let state = AppState(url: try tempFile(sample))
    #expect(state.todoCount == 2)
    #expect(state.dueCount == 1)
    #expect(state.document.categories.map(\.name) == ["work", "suggested"])
  }

  @Test func performWritesTheFileAndUpdatesCounts() throws {
    let url = try tempFile(sample)
    let state = AppState(url: url)
    state.perform { _ = try $0.add("groceries", category: "work") }
    #expect(state.todoCount == 3)
    #expect(state.lastError == nil)
    #expect(try String(contentsOf: url, encoding: .utf8).contains("- [ ] groceries"))
  }

  @Test func failedEditLeavesTheFileAloneAndSetsLastError() throws {
    let url = try tempFile(sample)
    let state = AppState(url: url)
    state.perform { _ = try $0.add("", category: "work") }
    #expect(state.lastError != nil)
    #expect(state.todoCount == 2)
    #expect(try String(contentsOf: url, encoding: .utf8) == sample)
  }
}

struct OrbCountTests {
  @Test func countsEveryLineThatIsNotHeadingBlankOrCrossedOut() throws {
    let state = AppState(
      url: try tempFile(
        """
        ## work
        ### Today
        - [ ] a
        - [/] b
        - [x] c ✅ 2026-10-20
        - [-] d
        - bullet
        plain

        ## suggested
        - [ ] idea 🤖 claude 2026-10-20

        """))
    #expect(state.todoCount == 4)
  }
}

/// Polls every 50 ms until `condition` holds or `timeout` passes.
private func eventually(
  _ timeout: Duration = .seconds(2), _ condition: () -> Bool
) async -> Bool {
  let deadline = ContinuousClock.now + timeout
  while ContinuousClock.now < deadline {
    if condition() { return true }
    try? await Task.sleep(for: .milliseconds(50))
  }
  return condition()
}

struct LiveSyncTests {
  @Test func externalAtomicWriteShowsUp() async throws {
    let url = try tempFile(sample)
    let state = AppState(url: url)
    let temp = url.deletingLastPathComponent().appending(path: ".tmp-external")
    try (sample + "- [ ] from outside\n").write(to: temp, atomically: false, encoding: .utf8)
    _ = try FileManager.default.replaceItemAt(url, withItemAt: temp)
    let shown = await eventually {
      state.document.categories.flatMap(\.tasks).contains { $0.text == "from outside" }
    }
    #expect(shown)
  }

  @Test func concurrentWritersLoseNothingAndStateConverges() async throws {
    let url = try tempFile("## work\n")
    let state = AppState(url: url)
    let other = Task.detached {
      let store = FileStore(url: url)
      for index in 0..<20 { try store.write { _ = try $0.add("other \(index)", category: "work") } }
    }
    for index in 0..<20 {
      state.perform { _ = try $0.add("app \(index)", category: "work") }
      await Task.yield()
    }
    try await other.value
    let (fileDoc, _) = try FileStore(url: url).read()
    #expect(fileDoc.categories.flatMap(\.tasks).count == 40)
    let converged = await eventually(.seconds(1)) { state.document == fileDoc }
    #expect(converged)
  }
}
