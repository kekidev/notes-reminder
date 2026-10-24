import AppKit

extension NotesTextView {
  /// Moves every paragraph the selection touches by `delta` levels, as one undo step.
  func shiftIndent(by delta: Int) {
    guard let storage = textStorage else { return }
    let selection = selectedRange()
    let length = (string as NSString).length
    let first = paragraph(at: selection.location).start
    let last = paragraph(at: selection.length > 0 ? selection.upperBound - 1 : selection.location)
    var changes: [(range: NSRange, level: Int)] = []
    var location = first
    while true {
      let (start, end) = paragraph(at: location)
      let whole = NSRange(location: start, length: min(end + 1, length) - start)
      let content = NSRange(location: start, length: end - start)
      if whole.length == 0 {  // an empty last line has no character to hold the level
        setTypingIndent(
          min(max(indentLevel(at: start) + delta, 0), PageText.maxIndent), empty: true)
      } else if !PageText.heading(in: storage, content) {
        let level = PageText.indent(in: storage, whole)
        let moved = min(max(level + delta, 0), PageText.maxIndent)
        if moved != level { changes.append((whole, moved)) }
      }
      if end >= last.end || end + 1 >= length { break }
      location = end + 1
    }
    if let from = changes.first?.range.location,
      let upper = changes.last.map({ NSMaxRange($0.range) }),
      shouldChangeText(in: NSRange(location: from, length: upper - from), replacementString: nil)
    {
      for (range, level) in changes {
        if level > 0 {
          storage.addAttribute(.glanceIndent, value: level, range: range)
        } else {
          storage.removeAttribute(.glanceIndent, range: range)
        }
      }
      didChangeText()
    }
    let cursor = paragraph(at: selectedRange().location)
    if min(cursor.end + 1, length) > cursor.start {
      setTypingIndent(indentLevel(at: cursor.start), empty: false)
    }
  }

  /// The level of the paragraph holding `location`; an empty last line keeps it in the typing attributes.
  func indentLevel(at location: Int) -> Int {
    guard let storage = textStorage else { return 0 }
    let (start, end) = paragraph(at: location)
    let whole = NSRange(location: start, length: min(end + 1, storage.length) - start)
    return whole.length == 0
      ? typingAttributes[.glanceIndent] as? Int ?? 0 : PageText.indent(in: storage, whole)
  }

  /// Sets the level of the paragraph holding `location`, without an undo step of its own.
  func setIndent(_ level: Int, at location: Int) {
    guard let storage = textStorage else { return }
    let (start, end) = paragraph(at: location)
    let whole = NSRange(location: start, length: min(end + 1, storage.length) - start)
    if level > 0 && whole.length > 0 {
      storage.addAttribute(.glanceIndent, value: level, range: whole)
    } else {
      storage.removeAttribute(.glanceIndent, range: whole)
    }
    restyle()
    if paragraph(at: selectedRange().location).start == start {
      setTypingIndent(level, empty: whole.length == 0)
    }
  }

  private func setTypingIndent(_ level: Int, empty: Bool) {
    var attributes = typingAttributes
    attributes[.glanceIndent] = level > 0 ? level : nil
    if empty {  // the caret on a line with no characters draws with the typing style
      let style = NSMutableParagraphStyle()
      style.firstLineHeadIndent = CGFloat(level) * PageText.indentWidth
      style.headIndent = style.firstLineHeadIndent
      attributes[.paragraphStyle] = style
    }
    typingAttributes = attributes
  }
}
