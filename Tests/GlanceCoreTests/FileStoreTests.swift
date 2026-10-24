import Foundation
import Testing

@testable import GlanceCore

private func tempFile() throws -> URL {
  let dir = FileManager.default.temporaryDirectory.appending(path: "glance-\(UUID())")
  try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  return dir.appending(path: "todo.md")
}

private func contents(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }

private func editInPlace(_ url: URL, _ text: String) throws {
  let handle = try FileHandle(forWritingTo: url)
  try handle.truncate(atOffset: 0)
  try handle.write(contentsOf: Data(text.utf8))
  try handle.close()
}

extension GlanceDocument {
  fileprivate mutating func append(_ text: String) {
    categories[0].entries.append(.task(GlanceTask(text: text)))
  }
}

/// The first value `stream` yields within `timeout`, or nil.
private func next(_ stream: AsyncStream<GlanceDocument>, within timeout: Duration) async
  -> GlanceDocument?
{
  await withTaskGroup(of: GlanceDocument?.self) { group in
    group.addTask { await stream.first { _ in true } }
    group.addTask {
      try? await Task.sleep(for: timeout)
      return nil
    }
    let first = await group.next() ?? nil
    group.cancelAll()
    return first
  }
}

private struct Boom: Error {}

@Test func `missing file reads as the new-list template and write creates it`() throws {
  let url = try tempFile().deletingLastPathComponent().appending(path: "sub/todo.md")
  let store = FileStore(url: url)
  let template = "---\nglance: 1\n---\n\n## work\n\n## life\n\n## content\n\n## study\n"

  let (doc, hash) = try store.read()
  #expect(MarkdownSerializer.serialize(doc) == template)
  // SHA-256 of empty data.
  #expect(hash == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")

  try store.write { $0.append("first") }
  #expect(try contents(url).hasPrefix("---\nglance: 1\n---\n\n## work\n"))
  let (reread, rehash) = try store.read()
  #expect(reread.task(named: "first")?.category == "work")
  #expect(rehash != hash)
}

@Test func `a throwing transform writes nothing`() throws {
  let url = try tempFile()
  let store = FileStore(url: url)
  #expect(throws: Boom.self) { try store.write { _ in throw Boom() } }
  #expect(!FileManager.default.fileExists(atPath: url.path))

  try "## a\n- [ ] keep\n".write(to: url, atomically: true, encoding: .utf8)
  #expect(throws: Boom.self) {
    try store.write { doc in
      doc.append("lost")
      throw Boom()
    }
  }
  #expect(try contents(url) == "## a\n- [ ] keep\n")
}

@Test func `unknown lines survive a write`() throws {
  let url = try tempFile()
  let text = try fixture("messy")
  try text.write(to: url, atomically: true, encoding: .utf8)
  try FileStore(url: url).write { $0.append("added") }

  let written = try contents(url)
  // Known lines are canonicalized (`[X]` becomes `[x]`); everything else must come through as is.
  for line in MarkdownSerializer.serialize(MarkdownParser.parse(text)).split(separator: "\n") {
    #expect(written.contains(line), "lost: \(line)")
  }
  #expect(written.contains("- [ ] added"))
}

@Test func `concurrent writes from two stores lose no update`() async throws {
  let url = try tempFile()
  let stores = [FileStore(url: url), FileStore(url: url)]
  try await withThrowingTaskGroup { group in
    for index in 0..<50 {
      group.addTask { try stores[index % 2].write { $0.append("task \(index)") } }
    }
    try await group.waitForAll()
  }
  let texts = Set(try stores[0].read().0.tasks.map(\.text))
  #expect(texts == Set((0..<50).map { "task \($0)" }))
}

@Test func `a file changed between read and write is re-read and the transform reapplied`()
  throws
{
  let url = try tempFile()
  try "## a\n".write(to: url, atomically: true, encoding: .utf8)
  var calls = 0
  try FileStore(url: url).write { doc in
    calls += 1
    if calls == 1 { try editInPlace(url, "## a\n- [ ] from editor\n") }
    doc.append("ours")
  }
  #expect(calls == 2)
  #expect(try contents(url) == "## a\n- [ ] from editor\n- [ ] ours\n")
}

@Test func `a file that never stops changing fails the write`() throws {
  let url = try tempFile()
  try "## a\n".write(to: url, atomically: true, encoding: .utf8)
  var calls = 0
  #expect(throws: FileStore.Error.contended) {
    try FileStore(url: url).write { _ in
      calls += 1
      try editInPlace(url, "## a\n- [ ] edit \(calls)\n")
    }
  }
  #expect(calls == 5)
}

@Test func `changes yields external edits and ignores our own`() async throws {
  let url = try tempFile()
  let store = FileStore(url: url)
  try store.write { $0.append("start") }

  let inPlace = store.changes
  try editInPlace(url, "## work\n- [ ] in place\n")
  #expect(await next(inPlace, within: .seconds(1))?.task(named: "in place") != nil)

  let replaced = store.changes
  try "## work\n- [ ] replaced\n".write(to: url, atomically: true, encoding: .utf8)
  #expect(await next(replaced, within: .seconds(1))?.task(named: "replaced") != nil)

  let own = store.changes
  try store.write { $0.append("ours") }
  #expect(await next(own, within: .milliseconds(500)) == nil)
}

@Test func `changes works before the data directory exists and skips a deleted file`() async throws
{
  let url = try tempFile().deletingLastPathComponent().appending(path: "not-yet/todo.md")
  let store = FileStore(url: url)

  let created = store.changes
  try FileManager.default.createDirectory(
    at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
  try "## work\n- [ ] first\n".write(to: url, atomically: true, encoding: .utf8)
  #expect(await next(created, within: .seconds(1))?.task(named: "first") != nil)

  let deleted = store.changes
  try FileManager.default.removeItem(at: url)
  #expect(await next(deleted, within: .milliseconds(500)) == nil)
}
