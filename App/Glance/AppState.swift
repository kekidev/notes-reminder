import Foundation
import GlanceCore
import Observation

/// The app's one view of `todo.md`. Every edit goes through `perform`.
@Observable final class AppState {
  /// `~/Documents/Glance/todo.md`, unless a list already lives at the original development path.
  static let defaultURL: URL = {
    let legacy = URL.homeDirectory.appending(path: "workspace/notes-reminder/data/todo.md")
    if FileManager.default.fileExists(atPath: legacy.path) { return legacy }
    return URL.homeDirectory.appending(path: "Documents/Glance/todo.md")
  }()

  private(set) var document: GlanceDocument
  private(set) var lastError: (any Error)?
  /// The day `dueCount` is measured against; moves on at local midnight.
  private(set) var now = Date()
  private let store: FileStore
  @ObservationIgnored private var watcher: Task<Void, Never>?
  @ObservationIgnored private var midnight: Task<Void, Never>?

  init(url: URL = defaultURL) {
    store = FileStore(url: url)
    do {
      document = try store.read().0
    } catch {
      document = MarkdownParser.parse("")
      lastError = error
    }
    // The stream is made here so a write right after init is not missed.
    let changes = store.changes
    // An event's payload can be older than a write `perform` made meanwhile, so re-read on delivery.
    watcher = Task { [weak self] in
      for await _ in changes { self?.reload() }
    }
    scheduleMidnight()
  }

  deinit {
    watcher?.cancel()
    midnight?.cancel()
  }

  /// One sleep to just past the next local midnight, then again; no repeating timer.
  private func scheduleMidnight() {
    let next = Calendar.current.nextDate(
      after: .now, matching: DateComponents(hour: 0), matchingPolicy: .nextTime)
    midnight = Task { [weak self] in
      try? await Task.sleep(for: .seconds((next?.timeIntervalSinceNow ?? 3600) + 1))
      guard !Task.isCancelled, let self else { return }
      now = .now
      scheduleMidnight()
    }
  }

  private func reload() {
    do {
      document = try store.read().0
    } catch {
      lastError = error
    }
  }

  /// Every line on a regular page that is not blank, a heading or crossed out.
  var todoCount: Int {
    document.categories.filter { !$0.isSuggested }.flatMap { document.bodyLines(of: $0.name) }
      .filter { line in
        !line.allSatisfy(\.isWhitespace) && !line.hasPrefix("### ") && !PageText.isDone(line)
      }.count
  }
  var dueCount: Int { Counts.dueTodayOrOverdue(document, now: now) }

  /// Applies `edit` to the latest file and shows the result. A thrown error leaves the file as is.
  func perform(_ edit: (inout GlanceDocument) throws -> Void) {
    do {
      document = try store.write { doc in
        try edit(&doc)
        return doc
      }
      lastError = nil
    } catch {
      lastError = error
    }
  }
}
