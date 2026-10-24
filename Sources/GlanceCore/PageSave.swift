import Foundation

/// Whole-page saves from the app's editor, merged against the file as it is at write time.
extension GlanceDocument {
  /// Writes the editor's `edited` lines over page `name`, creating it if needed. Lines in the file
  /// that neither `base` (the page as the editor last loaded or saved it) nor `edited` has, such as
  /// a hidden crossed-out line or one MCP added, go back after the line that preceded them. A line
  /// checked in the editor gets `today` as its done date. `edited` and `base` are in `shown` form.
  /// Returns the lines another writer added.
  @discardableResult
  public mutating func savePage(
    _ name: String, edited: [String], base: [String], today: CalendarDay
  ) throws -> [String] {
    let current = Self.shown(bodyLines(of: name))
    let added = Self.added(current: current, base: base, edited: edited)
    let merged = Self.merged(current: current, edited: edited, added: added)
    guard current != merged else { return added }
    if !categories.contains(where: { $0.name == name }) { try addCategory(name) }
    try replaceBody(of: name, with: merged)
    // Re-read after each stamp, since a stamp may change the line's id.
    while let task = categories.first(where: { $0.name == name })?.tasks.first(where: {
      $0.kind == .checklist && $0.status == .completed && $0.doneAt == nil
    }) {
      try setStatus(task.id, .completed, today: today)
    }
    return added
  }

  /// `lines` as the editor shows and saves them: a crossed-out line reads as `- [x]` without its
  /// done stamp, and a typed ☐/☑/• reads as its markdown. `replaceBody` restores what this drops.
  public static func shown(_ lines: [String]) -> [String] { lines.map(shown) }

  private static func shown(_ line: String) -> String {
    let level = min(line.prefix { $0 == " " }.count / 2, GlanceTask.maxIndent)
    let (pad, rest) = (line.prefix(level * 2), line.dropFirst(level * 2))
    for done in ["- [x] ", "- [X] ", "- [-] "] where rest.hasPrefix(done) {
      let text = rest.dropFirst(done.count).replacing(/\ ✅ \d{4}-\d{2}-\d{2}/, with: "")
      return pad + "- [x] " + text
    }
    for (glyph, markdown) in [("☐ ", "- [ ] "), ("☑ ", "- [x] "), ("• ", "- ")]
    where rest.hasPrefix(glyph) {
      return pad + markdown + rest.dropFirst(glyph.count)
    }
    return line
  }

  /// Lines of `current` that `base` and `edited` together don't account for, in file order.
  private static func added(current: [String], base: [String], edited: [String]) -> [String] {
    var known = base + edited
    return current.filter { line in
      guard let index = known.firstIndex(of: line) else { return true }
      known.remove(at: index)
      return false
    }
  }

  /// `edited` with `added` put back after the line that preceded each in `current`.
  private static func merged(current: [String], edited: [String], added: [String]) -> [String] {
    var pending = added[...]
    var unused = Array(edited.indices)
    var inserts: [Int: [String]] = [:]
    var after = -1
    for line in current {
      if line == pending.first {
        inserts[after, default: []].append(pending.removeFirst())
      } else if let slot = unused.firstIndex(where: { edited[$0] == line }) {
        after = unused.remove(at: slot)
      } else if let next = unused.first(where: { $0 > after }) {
        after = next  // an edited line (indented, reworded) most likely stands where it was
      }
    }
    return inserts[-1, default: []]
      + edited.indices.flatMap { [edited[$0]] + inserts[$0, default: []] }
  }
}
