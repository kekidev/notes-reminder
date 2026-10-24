import AppKit
import GlanceCore
import Testing

@testable import Glance

struct IndentTextTests {
  @Test func leadingPairsBecomeTheAttributeAndComeBack() {
    let lines = ["- [ ] a", "  - [ ] b", "    - c", "      plain", "   odd", "  ### h", "  ", ""]
    let text = PageText.attributed(from: lines)
    #expect(text.string == "☐ a\n☐ b\n• c\nplain\n odd\n  ### h\n  \n")
    #expect(PageText.lines(from: text) == lines)
    #expect(text.attribute(.glanceIndent, at: 4, effectiveRange: nil) as? Int == 1)
    let style = text.attribute(.paragraphStyle, at: 4, effectiveRange: nil) as? NSParagraphStyle
    #expect(style?.firstLineHeadIndent == 20)
    #expect(GlanceDocument.shown(lines) == lines)
  }
}

/// Drives the text view in code, the way keystrokes reach it.
struct IndentEditorTests {
  private func editor(_ lines: [String], cursor: Int? = nil, length: Int = 0) -> NotesTextView {
    let view = NotesTextView.make()
    view.load(lines: lines)
    view.setSelectedRange(NSRange(location: cursor ?? view.string.utf16.count, length: length))
    return view
  }

  @Test func tabIndentsTheLineWithoutInsertingATab() {
    let view = editor(["- [ ] a", "b"], cursor: 3)
    view.insertTab(nil)
    #expect(view.lines == ["  - [ ] a", "b"])
    #expect(!view.string.contains("\t"))
    #expect(view.selectedRange() == NSRange(location: 3, length: 0))
  }

  @Test func tabStopsAtFourAndBacktabStopsAtZero() {
    let view = editor(["a"], cursor: 0)
    for _ in 0..<6 { view.insertTab(nil) }
    #expect(view.lines == ["        a"])
    for _ in 0..<6 { view.insertBacktab(nil) }
    #expect(view.lines == ["a"])
  }

  @Test func tabIndentsEveryTouchedLineButNotAHeading() {
    let view = editor(["- a", "### h", "b", "c"], cursor: 0, length: 7)
    view.insertTab(nil)
    #expect(view.lines == ["  - a", "### h", "  b", "c"])
  }

  @Test func aSelectionEndingAtALineStartLeavesThatLine() {
    let view = editor(["a", "b"], cursor: 0, length: 2)
    view.insertTab(nil)
    #expect(view.lines == ["  a", "b"])
  }

  @Test func indentingIsOneUndoStep() throws {
    let view = editor(["a", "b"], cursor: 0, length: 3)
    let window = NSWindow(
      contentRect: .init(x: 0, y: 0, width: 200, height: 100), styleMask: [], backing: .buffered,
      defer: true)
    window.contentView = view  // an undo manager needs a window
    let undo = try #require(view.undoManager)
    undo.groupsByEvent = false
    undo.beginUndoGrouping()
    view.insertTab(nil)
    undo.endUndoGrouping()
    #expect(view.lines == ["  a", "  b"])
    undo.undo()
    #expect(view.lines == ["a", "b"])
  }

  @Test func returnKeepsTheIndent() {
    let view = editor(["  - [ ] a", "    plain"], cursor: 3)
    view.insertNewline(nil)
    #expect(view.lines == ["  - [ ] a", "  - [ ] ", "    plain"])
    view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
    view.insertNewline(nil)
    // A blank line keeps no indent when saved.
    #expect(view.lines == ["  - [ ] a", "  - [ ] ", "    plain", ""])
  }

  @Test func returnAtTheEndOfAnIndentedLineStartsAnIndentedLine() {
    let view = editor(["  one"])
    view.insertNewline(nil)
    for character in "two" {
      view.insertText(String(character), replacementRange: NSRange(location: NSNotFound, length: 0))
    }
    #expect(view.lines == ["  one", "  two"])
  }

  @Test func backspaceOutdentsBeforeAnythingElse() {
    let view = editor(["    - a", "    b"], cursor: 2)
    view.deleteBackward(nil)
    #expect(view.lines == ["  - a", "    b"])
    view.deleteBackward(nil)
    #expect(view.lines == ["- a", "    b"])
    view.deleteBackward(nil)
    #expect(view.lines == ["a", "    b"])
    view.setSelectedRange(NSRange(location: 2, length: 0))
    view.deleteBackward(nil)
    #expect(view.lines == ["a", "  b"])
  }

  @Test func backspaceInsideTextOfAnIndentedLineJustDeletes() {
    let view = editor(["  ab"], cursor: 1)
    view.deleteBackward(nil)
    #expect(view.lines == ["  b"])
  }
}
