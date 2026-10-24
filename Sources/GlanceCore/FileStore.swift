import CoreServices
import CryptoKit
import Foundation
import Synchronization

/// The one way to read and write `todo.md`, shared by the app and `glance-mcp`.
public final class FileStore: Sendable {
  public enum Error: Swift.Error { case contended }

  private static let template =
    "---\nglance: 1\n---\n\n## work\n\n## life\n\n## content\n\n## study\n"

  private let url: URL
  /// For each `changes` stream, the hash of the content it last yielded or this store wrote.
  private let seen = Mutex<[UUID: String]>([:])

  public init(url: URL) { self.url = url }

  public func read() throws -> (GlanceDocument, hash: String) {
    let (data, doc) = try load()
    return (doc, Self.hash(data))
  }

  /// Applies `transform` to the latest file under a cross-process lock and swaps the result in.
  @discardableResult
  public func write<T>(_ transform: (inout GlanceDocument) throws -> T) throws -> T {
    let dir = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let lock = open(url.path + ".lock", O_CREAT | O_RDWR, 0o644)
    guard lock >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    defer { close(lock) }
    guard flock(lock, LOCK_EX) == 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    for _ in 0..<5 {
      var (data, doc) = try load()
      let result = try transform(&doc)
      let output = Data(MarkdownSerializer.serialize(doc).utf8)
      // An editor that ignores the lock may have saved while the transform ran.
      guard try load().data == data else { continue }
      guard output != data else { return result }

      // Recorded before the swap so the watcher can never see our write as external.
      let written = Self.hash(output)
      seen.withLock { $0 = $0.mapValues { _ in written } }
      let temp = dir.appending(path: ".\(url.lastPathComponent).\(UUID().uuidString)")
      defer { try? FileManager.default.removeItem(at: temp) }
      try output.write(to: temp)
      _ = try FileManager.default.replaceItemAt(url, withItemAt: temp)
      return result
    }
    throw Error.contended
  }

  /// Documents saved by anyone else, delivered within about 0.1 s of the save.
  public var changes: AsyncStream<GlanceDocument> {
    AsyncStream { continuation in
      let id = UUID()
      seen.withLock { $0[id] = (try? read())?.hash }
      let queue = DispatchQueue(label: "FileStore.changes")
      // FSEvents cannot watch a directory that does not exist yet.
      try? FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      let onEvent = Callback { [self] in
        // A delete-then-recreate save would otherwise flash the empty template.
        guard FileManager.default.fileExists(atPath: url.path),
          let (doc, hash) = try? read(),
          seen.withLock({ $0.updateValue(hash, forKey: id) != hash })
        else { return }
        continuation.yield(doc)
      }
      var context = FSEventStreamContext(
        version: 0, info: Unmanaged.passRetained(onEvent).toOpaque(), retain: nil,
        release: { Unmanaged<Callback>.fromOpaque($0!).release() }, copyDescription: nil)
      // File-level events on the directory catch both in-place writes and rename-over saves.
      nonisolated(unsafe) let stream = FSEventStreamCreate(
        nil,
        { _, info, _, _, _, _ in Unmanaged<Callback>.fromOpaque(info!).takeUnretainedValue().run()
        },
        &context, [url.deletingLastPathComponent().path] as CFArray,
        FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.05,
        FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents))!
      FSEventStreamSetDispatchQueue(stream, queue)
      FSEventStreamStart(stream)
      continuation.onTermination = { _ in
        // On the event queue, so no callback can run after the entry is removed.
        queue.async { [self] in
          FSEventStreamStop(stream)
          FSEventStreamInvalidate(stream)
          FSEventStreamRelease(stream)
          seen.withLock { $0[id] = nil }
        }
      }
    }
  }

  /// A missing file reads as empty bytes and the new-list template.
  private func load() throws -> (data: Data, doc: GlanceDocument) {
    let data: Data
    do {
      data = try Data(contentsOf: url)
    } catch CocoaError.fileReadNoSuchFile {
      return (Data(), MarkdownParser.parse(Self.template))
    }
    // Refuse rather than write back a lossy decode.
    guard let text = String(data: data, encoding: .utf8) else {
      throw CocoaError(.fileReadInapplicableStringEncoding)
    }
    return (data, MarkdownParser.parse(text))
  }

  private static func hash(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}

private final class Callback: Sendable {
  let run: @Sendable () -> Void
  init(_ run: @escaping @Sendable () -> Void) { self.run = run }
}
