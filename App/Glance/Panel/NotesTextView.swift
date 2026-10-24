import AppKit

/// A page as one text view where every paragraph is a line, with Apple Notes' list behaviours.
final class NotesTextView: NSTextView {
  var onEdit: (() -> Void)?
  var onResign: (() -> Void)?

  static func make() -> NotesTextView {
    // TextKit 1 keeps layout measurement and marker hit-testing simple.
    let view = NotesTextView(usingTextLayoutManager: false)
    view.isRichText = true
    view.allowsUndo = true
    view.drawsBackground = false
    view.isVerticallyResizable = true
    view.isHorizontallyResizable = false
    view.textContainerInset = .zero
    view.isAutomaticQuoteSubstitutionEnabled = false
    view.isAutomaticDashSubstitutionEnabled = false
    view.isAutomaticTextReplacementEnabled = false
    view.typingAttributes = PageText.bodyAttributes
    return view
  }

  var lines: [String] { PageText.lines(from: attributedString()) }
  var doneCount: Int { PageText.doneCount(lines: lines) }

  /// Shows `lines` without counting as an edit or an undo step.
  func load(lines: [String]) {
    textStorage?.setAttributedString(PageText.attributed(from: lines))
    undoManager?.removeAllActions()
    typingAttributes = PageText.bodyAttributes
    needsDisplay = true
  }

  /// Adds lines written elsewhere to the end without moving the cursor or the user's undo steps.
  func append(lines: [String]) {
    guard let storage = textStorage, !lines.isEmpty else { return }
    let selection = selectedRanges
    storage.beginEditing()
    storage.append(NSAttributedString(string: storage.length > 0 ? "\n" : ""))
    storage.append(PageText.attributed(from: lines))
    PageText.restyle(storage)
    storage.endEditing()
    selectedRanges = selection
  }

  // MARK: - Editing

  override func didChangeText() {
    super.didChangeText()
    restyle()
    if string.utf16.count <= 1 { needsDisplay = true }
    onEdit?()
  }

  func restyle() {
    guard let storage = textStorage else { return }
    storage.beginEditing()
    PageText.restyle(storage)
    storage.endEditing()
  }

  override func resignFirstResponder() -> Bool {
    let resigned = super.resignFirstResponder()
    if resigned { onResign?() }
    return resigned
  }

  /// Text stays plain; the editor derives its own look.
  override func paste(_ sender: Any?) { pasteAsPlainText(sender) }

  override func insertText(_ string: Any, replacementRange: NSRange) {
    if string as? String == " ", replacementRange.location == NSNotFound,
      selectedRange().length == 0, applyShortcut()
    {
      return
    }
    super.insertText(string, replacementRange: replacementRange)
  }

  /// "[] ", "- " or "# " typed at the start of a line sets its kind, as in Notes.
  private func applyShortcut() -> Bool {
    let location = selectedRange().location
    let (start, _) = paragraph(at: location)
    let typed = (string as NSString).substring(
      with: NSRange(location: start, length: location - start))
    guard let kind = ["[]": NoteKind.checklist, "-": .bullet, "#": .heading][typed] else {
      return false
    }
    replace(NSRange(location: start, length: typed.utf16.count), with: "")
    setSelectedRange(NSRange(location: start, length: 0))
    convertParagraph(to: kind)
    return true
  }

  override func insertNewline(_ sender: Any?) {
    let selection = selectedRange()
    let level = indentLevel(at: selection.location)
    var split = true
    let (start, end) = paragraph(at: selection.location)
    let line = (string as NSString).substring(with: NSRange(location: start, length: end - start))
    if let marker = PageText.marker(in: line), selection.location >= start + marker.length {
      if line.utf16.count == marker.length {  // a marker-only line ends the list
        replace(NSRange(location: start, length: marker.length), with: "")
        setSelectedRange(NSRange(location: start, length: 0))
        split = false
      } else {
        insertText(marker.kind == .bullet ? "\n• " : "\n☐ ", replacementRange: selection)
      }
    } else {
      super.insertNewline(sender)
    }
    typingAttributes = PageText.bodyAttributes
    let cursor = paragraph(at: selectedRange().location).start
    if split, cursor > 0 { setIndent(level, at: cursor - 1) }
    setIndent(level, at: cursor)
  }

  // MARK: - Indent

  override func insertTab(_ sender: Any?) { shiftIndent(by: 1) }
  override func insertBacktab(_ sender: Any?) { shiftIndent(by: -1) }

  override func deleteBackward(_ sender: Any?) {
    let selection = selectedRange()
    if selection.length == 0 {
      let (start, end) = paragraph(at: selection.location)
      let line = (string as NSString).substring(with: NSRange(location: start, length: end - start))
      if indentLevel(at: start) > 0,
        selection.location == start
          || selection.location == start + (PageText.marker(in: line)?.length ?? -1)
      {
        shiftIndent(by: -1)  // outdent first, then the next backspace follows the usual rules
        return
      }
      if let marker = PageText.marker(in: line), selection.location == start + marker.length {
        replace(NSRange(location: start, length: marker.length), with: "")
        setSelectedRange(NSRange(location: start, length: 0))
        typingAttributes = PageText.bodyAttributes
        return
      }
      if start == end, start > 0 {  // an empty line goes, and the cursor ends the line above
        replace(NSRange(location: start - 1, length: 1), with: "")
        setSelectedRange(NSRange(location: start - 1, length: 0))
        return
      }
    }
    super.deleteBackward(sender)
  }

  // MARK: - Line kinds

  /// Flips the box on the line containing `location` and keeps the cursor where it was.
  func toggleChecklist(at location: Int) {
    let (start, end) = paragraph(at: location)
    guard end > start else { return }
    let glyph = (string as NSString).substring(with: NSRange(location: start, length: 1))
    guard glyph == "☐" || glyph == "☑" else { return }
    let selection = selectedRange()
    replace(NSRange(location: start, length: 1), with: glyph == "☐" ? "☑" : "☐")
    setSelectedRange(selection)
  }

  /// Sets the kind of the line holding the cursor.
  func convertParagraph(to kind: NoteKind) {
    let location = selectedRange().location
    let level = indentLevel(at: location)
    let (start, end) = paragraph(at: location)
    let line = (string as NSString).substring(with: NSRange(location: start, length: end - start))
    let old = PageText.marker(in: line)
    if old?.kind == kind && kind != .heading { return }
    let marker =
      switch kind {
      case .checklist: "☐ "
      case .bullet: "• "
      case .plain, .heading: ""
      }
    let oldLength = old?.length ?? 0
    if oldLength > 0 || !marker.isEmpty {
      replace(NSRange(location: start, length: oldLength), with: marker)
    }
    let content = paragraph(at: start)
    let range = NSRange(location: start, length: content.end - start)
    textStorage?.removeAttribute(.glanceHeading, range: range)
    if kind == .heading, range.length > 0 {
      textStorage?.addAttribute(.glanceHeading, value: true, range: range)
    }
    restyle()
    let floor = start + marker.utf16.count
    setSelectedRange(
      NSRange(location: max(floor, location + marker.utf16.count - oldLength), length: 0))
    typingAttributes = kind == .heading ? PageText.headingAttributes : PageText.bodyAttributes
    if kind != .heading { setIndent(level, at: start) }
  }

  /// Removes every crossed-out line.
  func removeDone() {
    let all = lines
    let kept = all.filter { !PageText.isDone($0) }
    guard kept.count != all.count else { return }
    // Keep the cursor on the line it was in (or the next kept one), not at the end of the page.
    let text = string as NSString
    let cursor = selectedRange().location
    let row = text.substring(to: min(cursor, text.length)).count { $0 == "\n" }
    let column = cursor - paragraph(at: cursor).start
    let removedRow = row < all.count && PageText.isDone(all[row])
    let newRow = all.prefix(row).count { !PageText.isDone($0) }
    guard replace(NSRange(location: 0, length: text.length), with: PageText.attributed(from: kept))
    else { return }
    let paragraphs = string.components(separatedBy: "\n")
    let start = paragraphs.prefix(newRow).reduce(0) { $0 + ($1 as NSString).length + 1 }
    let offset =
      removedRow || newRow >= paragraphs.count
      ? 0 : min(column, (paragraphs[newRow] as NSString).length)
    setSelectedRange(NSRange(location: min(start + offset, (string as NSString).length), length: 0))
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    if flags == [.command, .shift], event.charactersIgnoringModifiers?.lowercased() == "l" {
      let (start, end) = paragraph(at: selectedRange().location)
      let line = (string as NSString).substring(with: NSRange(location: start, length: end - start))
      convertParagraph(to: PageText.marker(in: line)?.kind == .checklist ? .plain : .checklist)
      return true
    }
    return super.performKeyEquivalent(with: event)
  }

  // MARK: - Clicks and drawing

  override func mouseDown(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    if let location = markerLocation(at: point) {
      toggleChecklist(at: location)
    } else {
      super.mouseDown(with: event)
    }
  }

  /// The paragraph start when `point` is on that line's ☐ or ☑.
  private func markerLocation(at point: NSPoint) -> Int? {
    guard let layout = layoutManager, let container = textContainer, string.utf16.count > 0 else {
      return nil
    }
    let origin = textContainerOrigin
    let index = layout.characterIndex(
      for: NSPoint(x: point.x - origin.x, y: point.y - origin.y), in: container,
      fractionOfDistanceBetweenInsertionPoints: nil)
    let (start, end) = paragraph(at: index)
    guard end > start,
      ["☐", "☑"].contains((string as NSString).substring(with: NSRange(location: start, length: 1)))
    else { return nil }
    var rect = layout.boundingRect(
      forGlyphRange: layout.glyphRange(
        forCharacterRange: NSRange(location: start, length: 1), actualCharacterRange: nil),
      in: container)
    rect.origin.x += origin.x
    rect.origin.y += origin.y
    return rect.insetBy(dx: -4, dy: 0).contains(point) ? start : nil
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    guard string.isEmpty else { return }
    "Start typing…".draw(
      at: NSPoint(x: textContainer?.lineFragmentPadding ?? 0, y: 0),
      withAttributes: [
        .font: PageText.font(bold: false), .foregroundColor: NSColor.tertiaryLabelColor,
      ])
  }

  // MARK: - Helpers

  @discardableResult
  func replace(_ range: NSRange, with text: String) -> Bool {
    replace(range, with: NSAttributedString(string: text))
  }

  /// An edit AppKit sees, so it is one undo step and `didChangeText` runs.
  @discardableResult
  private func replace(_ range: NSRange, with text: NSAttributedString) -> Bool {
    guard shouldChangeText(in: range, replacementString: text.string) else { return false }
    textStorage?.replaceCharacters(in: range, with: text)
    didChangeText()
    return true
  }

  /// Where the paragraph holding `location` starts and where its text ends, before the newline.
  func paragraph(at location: Int) -> (start: Int, end: Int) {
    var start = 0
    var end = 0
    var contentsEnd = 0
    (string as NSString).getParagraphStart(
      &start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
    return (start, contentsEnd)
  }
}

extension NotesTextView {
  /// The kind of the line holding the cursor.
  var currentKind: NoteKind {
    let (start, end) = paragraph(at: selectedRange().location)
    guard end > start, let storage = textStorage else {
      return typingAttributes[.glanceHeading] == nil ? .plain : .heading
    }
    if PageText.heading(in: storage, NSRange(location: start, length: end - start)) {
      return .heading
    }
    let line = (string as NSString).substring(with: NSRange(location: start, length: end - start))
    return PageText.marker(in: line)?.kind ?? .plain
  }
}
