import AppKit

extension NSAttributedString.Key {
  /// Marks the text of a heading paragraph, which has no marker glyph.
  static let glanceHeading = NSAttributedString.Key("glanceHeading")
  /// The indent level (1...4) on every character of a paragraph, newline included.
  static let glanceIndent = NSAttributedString.Key("glanceIndent")
}

enum NoteKind: Int {
  case plain, checklist, bullet, heading
}

/// Converts between a page's markdown lines and the editor's text: one paragraph per line.
/// `- [ ] ` shows as "☐ ", `- [x] ` as "☑ " (struck through), `- ` as "• ", `### ` as a bold
/// paragraph, and anything else as plain text. Every conversion is lossless.
enum PageText {
  static let size: CGFloat = 13
  static let maxIndent = 4
  static let indentWidth: CGFloat = 20

  /// Markdown prefix and glyph, most specific first. `[X]` and `[-]` read as crossed out and save as `[x]`.
  private static let prefixes: [(markdown: String, glyph: String)] = [
    ("- [ ] ", "☐ "), ("- [x] ", "☑ "), ("- [X] ", "☑ "), ("- [-] ", "☑ "), ("- ", "• "),
  ]

  static func font(bold: Bool) -> NSFont {
    NSFont(name: bold ? "JetBrainsMono-Bold" : "JetBrainsMono-Regular", size: size)
      ?? .monospacedSystemFont(ofSize: size, weight: bold ? .bold : .regular)
  }

  static var bodyAttributes: [NSAttributedString.Key: Any] {
    [.font: font(bold: false), .foregroundColor: NSColor.labelColor]
  }

  static var headingAttributes: [NSAttributedString.Key: Any] {
    [.font: font(bold: true), .foregroundColor: NSColor.labelColor, .glanceHeading: true]
  }

  /// The marker at the start of a paragraph, if any: its kind and length in UTF-16 units.
  static func marker(in line: String) -> (kind: NoteKind, length: Int)? {
    if line.hasPrefix("☐ ") { return (.checklist, 2) }
    if line.hasPrefix("☑ ") { return (.checklist, 2) }
    if line.hasPrefix("• ") { return (.bullet, 2) }
    return nil
  }

  static func display(_ line: String) -> (text: String, heading: Bool) {
    if line.hasPrefix("### "), line.count > 4 { return (String(line.dropFirst(4)), true) }
    for (markdown, glyph) in prefixes where line.hasPrefix(markdown) {
      // The done stamp is clutter on screen; replaceBody restores it from the unchanged line.
      let rest = glyph == "☑ " ? line.replacing(doneStamp, with: "") : line
      return (glyph + rest.dropFirst(markdown.count), false)
    }
    return (line, false)
  }

  private static let doneStamp = /\ ✅ \d{4}-\d{2}-\d{2}/

  /// Leading pairs of spaces become the indent attribute. A line that would change meaning
  /// without them (blank, or a `### ` that stayed plain text) keeps its spaces as text.
  private static func splitIndent(_ line: String) -> (level: Int, rest: String) {
    let level = min(line.prefix { $0 == " " }.count / 2, maxIndent)
    let rest = String(line.dropFirst(level * 2))
    return level == 0 || rest.isEmpty || rest.hasPrefix("### ") ? (0, line) : (level, rest)
  }

  /// The indent level of the paragraph whose characters, newline included, are `whole`.
  static func indent(in text: NSAttributedString, _ whole: NSRange) -> Int {
    guard whole.length > 0 else { return 0 }
    return text.attribute(.glanceIndent, at: NSMaxRange(whole) - 1, effectiveRange: nil) as? Int
      ?? 0
  }

  private static func markdown(_ paragraph: String, heading: Bool) -> String {
    if heading { return "### " + paragraph }
    for (markdown, glyph) in [("- [ ] ", "☐ "), ("- [x] ", "☑ "), ("- ", "• ")]
    where paragraph.hasPrefix(glyph) {
      return markdown + paragraph.dropFirst(glyph.count)
    }
    return paragraph
  }

  static func lines(from text: NSAttributedString) -> [String] {
    guard text.length > 0 else { return [] }
    var location = 0
    return text.string.components(separatedBy: "\n").map { paragraph in
      let length = paragraph.utf16.count
      defer { location += length + 1 }
      let heading = length > 0 && heading(in: text, NSRange(location: location, length: length))
      let whole = NSRange(location: location, length: min(length + 1, text.length - location))
      let pad =
        length > 0 && !heading ? String(repeating: "  ", count: indent(in: text, whole)) : ""
      return pad + markdown(paragraph, heading: heading)
    }
  }

  static func attributed(from lines: [String]) -> NSAttributedString {
    let split = lines.map(splitIndent)
    let shown = split.map { display($0.rest) }
    let text = NSMutableAttributedString(string: shown.map(\.text).joined(separator: "\n"))
    var location = 0
    for (item, indent) in zip(shown, split.map(\.level)) {
      let length = item.text.utf16.count
      if item.heading {
        text.addAttribute(
          .glanceHeading, value: true, range: NSRange(location: location, length: length))
      }
      if indent > 0 {
        let whole = NSRange(location: location, length: min(length + 1, text.length - location))
        text.addAttribute(.glanceIndent, value: indent, range: whole)
      }
      location += length + 1
    }
    restyle(text)
    return text
  }

  /// What the editor shows: crossed-out lines live only in the file and the Completed tab.
  static func visible(_ lines: [String]) -> [String] { lines.filter { !isDone($0) } }

  static func doneCount(lines: [String]) -> Int { lines.count(where: isDone) }

  /// A crossed-out checklist line at any indent.
  static func isDone(_ line: String) -> Bool {
    display(String(line.drop { $0 == " " })).text.hasPrefix("☑ ")
  }

  static func heading(in text: NSAttributedString, _ range: NSRange) -> Bool {
    var found = false
    text.enumerateAttribute(.glanceHeading, in: range) { value, _, stop in
      if value != nil {
        found = true
        stop.pointee = true
      }
    }
    return found
  }

  /// The ☐/☑/• glyph is drawn larger than the text so it reads as a control.
  private static let markerFont = NSFont.systemFont(ofSize: 16)
  private static let checkboxWidth = ("☐" as NSString).size(withAttributes: [.font: markerFont])
    .width
  private static let markerIndent: CGFloat =
    checkboxWidth + (" " as NSString).size(withAttributes: [.font: font(bold: false)]).width

  /// Derives every paragraph's look from its text: heading, marker, done, and date tokens.
  static func restyle(_ text: NSMutableAttributedString) {
    let string = text.string as NSString
    var location = 0
    for paragraph in text.string.components(separatedBy: "\n") {
      let length = paragraph.utf16.count
      let start = location
      let content = NSRange(location: start, length: length)
      let whole = NSRange(location: start, length: min(length + 1, string.length - start))
      location += length + 1
      guard whole.length > 0 else { continue }
      let isHeading = heading(in: text, content)
      let level = isHeading ? 0 : indent(in: text, whole)
      let marker = marker(in: paragraph)
      let done = paragraph.hasPrefix("☑ ")
      let style = NSMutableParagraphStyle()
      style.lineSpacing = 2
      style.paragraphSpacing = 7
      let offset = CGFloat(level) * indentWidth
      style.firstLineHeadIndent = offset
      style.headIndent = offset + (marker != nil ? markerIndent : 0)
      if isHeading { style.paragraphSpacingBefore = 10 }
      var attributes = isHeading ? headingAttributes : bodyAttributes
      attributes[.paragraphStyle] = style
      if done {
        attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        attributes[.foregroundColor] = NSColor.secondaryLabelColor
      }
      if level > 0 { attributes[.glanceIndent] = level }
      text.setAttributes(attributes, range: whole)
      if !isHeading { text.removeAttribute(.glanceHeading, range: whole) }
      if marker != nil {
        let glyph = NSRange(location: start, length: 1)
        // Kerning pads every marker to the checkbox's width, so all line text starts in one column.
        let width = (string.substring(with: glyph) as NSString)
          .size(withAttributes: [.font: markerFont]).width
        text.addAttributes(
          [.font: markerFont, .baselineOffset: -1, .kern: checkboxWidth - width], range: glyph)
        if done {
          text.removeAttribute(.strikethroughStyle, range: NSRange(location: start, length: 2))
        }
      }
      if marker?.kind == .checklist,
        let token = [" 📅 ", " ✅ ", " 🤖 "].compactMap({
          (paragraph as NSString).range(of: $0).location
        })
        .filter({ $0 != NSNotFound }).min()
      {
        text.addAttributes(
          [.foregroundColor: NSColor.secondaryLabelColor, .font: NSFont.systemFont(ofSize: 11)],
          range: NSRange(location: start + token, length: length - token))
      }
    }
  }
}
