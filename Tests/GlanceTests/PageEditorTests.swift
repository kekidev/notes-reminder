import AppKit
import GlanceCore
import Testing

@testable import Glance

struct PageTextTests {
  /// Core's `shown` must match what the editor actually round-trips to.
  @Test func coreShownMatchesTheEditorsRoundTrip() {
    let lines = [
      "### work", "- [ ] a 📅 2026-10-26", "- [x] b ✅ 2026-10-21", "- [X] c", "- [-] d",
      "  - [x] e ✅ 2026-10-21", "   - [X] odd", "- a bullet", "☐ typed", "• typed", "plain",
      "", "  ", "  ### h", "### ", "- [", "- [/] pending",
    ]
    #expect(GlanceDocument.shown(lines) == PageText.lines(from: PageText.attributed(from: lines)))
  }

  @Test func theEditorShowsOnlyLinesThatAreNotCrossedOut() {
    let file = ["### h", "- [ ] a", "- [x] done1", "  - [x] done2", "- [ ] b", "- [-] gone"]
    #expect(PageText.visible(file) == ["### h", "- [ ] a", "- [ ] b"])
  }

  @Test func markdownLinesSurviveAToAttributedAndBack() {
    let lines = [
      "### work", "- [ ] weekly report 📅 2026-10-26", "- [x] buy cases",
      "- a bullet", "just a plain line", "", "- [", "- ",
    ]
    #expect(PageText.lines(from: PageText.attributed(from: lines)) == lines)
  }

  @Test func theDoneStampIsHiddenOnScreen() {
    #expect(PageText.attributed(from: ["- [x] b ✅ 2026-10-21"]).string == "☑ b")
  }

  @Test func markersShowAsGlyphsAndHeadingsAreMarked() {
    let text = PageText.attributed(from: ["### h", "- [ ] a", "- [x] b", "- c"])
    #expect(text.string == "h\n☐ a\n☑ b\n• c")
    #expect(text.attribute(.glanceHeading, at: 0, effectiveRange: nil) != nil)
  }

  @Test func aDoneLineIsStruckThroughAndADueTokenIsDimmed() {
    let text = PageText.attributed(from: ["- [x] b", "- [ ] c 📅 2026-10-26"])
    #expect(text.attribute(.strikethroughStyle, at: 3, effectiveRange: nil) != nil)
    #expect(text.attribute(.strikethroughStyle, at: 10, effectiveRange: nil) == nil)
    let token = (text.string as NSString).range(of: "📅").location
    #expect(
      text.attribute(.foregroundColor, at: token, effectiveRange: nil) as? NSColor
        == .secondaryLabelColor)
  }

  @Test func noTextIsNoLines() {
    #expect(PageText.lines(from: NSAttributedString()).isEmpty)
    #expect(PageText.attributed(from: []).length == 0)
  }
}

/// Drives the text view in code, the way keystrokes reach it.
struct NotesTextViewTests {
  private func editor(_ lines: [String], cursor: Int? = nil) -> NotesTextView {
    let view = NotesTextView.make()
    view.load(lines: lines)
    view.setSelectedRange(NSRange(location: cursor ?? view.string.utf16.count, length: 0))
    return view
  }

  private func type(_ text: String, into view: NotesTextView) {
    for character in text {
      view.insertText(String(character), replacementRange: NSRange(location: NSNotFound, length: 0))
    }
  }

  @Test func undoIsOn() {
    #expect(editor([]).allowsUndo)
  }

  @Test func backspaceOnAnEmptyLineDeletesItAndLandsAtTheEndOfTheLineAbove() {
    let view = editor(["abc", "", "def"], cursor: 4)
    view.deleteBackward(nil)
    #expect(view.string == "abc\ndef")
    #expect(view.selectedRange() == NSRange(location: 3, length: 0))
  }

  @Test func backspaceAfterAMarkerRemovesTheMarker() {
    let view = editor(["- [ ] a", "- b"], cursor: 2)
    view.deleteBackward(nil)
    #expect(view.string == "a\n• b")
    #expect(view.selectedRange() == NSRange(location: 0, length: 0))
    view.setSelectedRange(NSRange(location: 4, length: 0))
    view.deleteBackward(nil)
    #expect(view.string == "a\nb")
  }

  @Test func backspaceElsewhereJoinsLinesNatively() {
    let view = editor(["abc", "def"], cursor: 4)
    view.deleteBackward(nil)
    #expect(view.string == "abcdef")
  }

  @Test func returnInAChecklistLineStartsAnUncheckedOne() {
    let view = editor(["- [x] a"])
    view.insertNewline(nil)
    #expect(view.string == "☑ a\n☐ ")
    #expect(view.selectedRange() == NSRange(location: 6, length: 0))
  }

  @Test func returnInABulletContinuesTheBullet() {
    let view = editor(["- a"])
    view.insertNewline(nil)
    #expect(view.string == "• a\n• ")
  }

  @Test func returnOnAMarkerOnlyLineRemovesTheMarker() {
    let view = editor(["- [ ] a", "- [ ] "])
    view.insertNewline(nil)
    #expect(view.string == "☐ a\n")
    #expect(view.selectedRange() == NSRange(location: 4, length: 0))
  }

  @Test func returnOnAPlainLineIsAPlainNewline() {
    let view = editor(["abc"])
    view.insertNewline(nil)
    #expect(view.string == "abc\n")
  }

  @Test func returnAfterAHeadingStartsAPlainLine() {
    let view = editor(["### h"])
    view.insertNewline(nil)
    type("x", into: view)
    #expect(PageText.lines(from: view.attributedString()) == ["### h", "x"])
  }

  @Test func typingBracketsAndASpaceMakesAChecklist() {
    let view = editor([])
    type("[] milk", into: view)
    #expect(view.string == "☐ milk")
    #expect(PageText.lines(from: view.attributedString()) == ["- [ ] milk"])
  }

  @Test func typingADashAndASpaceMakesABullet() {
    let view = editor(["a"])
    view.insertNewline(nil)
    type("- milk", into: view)
    #expect(view.string == "a\n• milk")
  }

  @Test func typingAHashAndASpaceMakesAHeading() {
    let view = editor([])
    type("# Work", into: view)
    #expect(view.string == "Work")
    #expect(PageText.lines(from: view.attributedString()) == ["### Work"])
  }

  @Test func midLinePrefixesAreLeftAlone() {
    let view = editor([])
    type("a - b", into: view)
    #expect(view.string == "a - b")
  }

  @Test func togglingAMarkerStrikesTheLineThroughAndBack() {
    let view = editor(["- [ ] a"], cursor: 3)
    view.toggleChecklist(at: 0)
    #expect(view.string == "☑ a")
    #expect(view.textStorage?.attribute(.strikethroughStyle, at: 2, effectiveRange: nil) != nil)
    #expect(view.selectedRange() == NSRange(location: 3, length: 0))
    view.toggleChecklist(at: 0)
    #expect(view.string == "☐ a")
    #expect(view.textStorage?.attribute(.strikethroughStyle, at: 2, effectiveRange: nil) == nil)
  }

  @Test func convertingALineChangesItsMarker() {
    let view = editor(["- [ ] a", "b"], cursor: 5)
    view.convertParagraph(to: .bullet)
    #expect(view.string == "☐ a\n• b")
    view.convertParagraph(to: .plain)
    #expect(view.string == "☐ a\nb")
  }

  @Test func clearingDoneRemovesCrossedOutLines() {
    let view = editor(["- [x] a", "- [ ] b", "- [x] c"])
    #expect(view.doneCount == 2)
    view.removeDone()
    #expect(view.string == "☐ b")
  }
}

struct IndentedDoneTests {
  @Test func indentedCrossedOutLinesCountAsDone() {
    #expect(PageText.doneCount(lines: ["- [x] a", "  - [x] b", "    - [ ] c", "  - d"]) == 2)
  }
}

@MainActor struct RemoveDoneCursorTests {
  @Test func theCursorStaysOnItsLineWhenDoneLinesVanish() {
    let view = NotesTextView.make()
    view.load(lines: ["- [x] a", "- [ ] typing here", "- [x] b"])
    let line = (view.string as NSString).range(of: "typing")
    view.setSelectedRange(NSRange(location: line.location + 3, length: 0))
    view.removeDone()
    #expect(view.string == "☐ typing here")
    #expect(
      view.selectedRange()
        == NSRange(location: (view.string as NSString).range(of: "typing").location + 3, length: 0))
  }
}
