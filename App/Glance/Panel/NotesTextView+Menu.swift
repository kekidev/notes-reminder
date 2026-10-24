import AppKit

extension NotesTextView {
  func deleteLine() {
    let location = selectedRange().location
    let (start, end) = paragraph(at: location)
    let length = (string as NSString).length
    // The last line takes the newline above it, so no empty line is left behind.
    let range =
      end < length
      ? NSRange(location: start, length: end - start + 1)
      : NSRange(location: max(start - 1, 0), length: end - max(start - 1, 0))
    replace(range, with: "")
  }

  override func menu(for event: NSEvent) -> NSMenu? {
    let menu = super.menu(for: event) ?? NSMenu()
    let point = convert(event.locationInWindow, from: nil)
    setSelectedRange(NSRange(location: characterIndexForInsertion(at: point), length: 0))
    menu.insertItem(.separator(), at: 0)
    let titles: [(String, NoteKind)] = [
      ("Checklist", .checklist), ("Bullet", .bullet), ("Heading", .heading), ("Plain Text", .plain),
    ]
    for (title, kind) in titles.reversed() {
      let item = NSMenuItem(title: title, action: #selector(convertFromMenu(_:)), keyEquivalent: "")
      item.tag = kind.rawValue
      menu.insertItem(item, at: 0)
    }
    menu.insertItem(
      NSMenuItem(
        title: "Delete Line", action: #selector(deleteLineFromMenu(_:)), keyEquivalent: ""),
      at: 4)
    return menu
  }

  @objc func convertFromMenu(_ item: NSMenuItem) {
    convertParagraph(to: NoteKind(rawValue: item.tag) ?? .plain)
  }

  @objc func deleteLineFromMenu(_ item: NSMenuItem) { deleteLine() }
}
