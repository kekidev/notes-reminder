import AppKit
import GlanceCore
import SwiftUI

private let focusNewLine = Notification.Name("GlanceFocusAddField")

/// A page shown as a document: one editable text view, above the format bar.
struct NotepadView<Below: View>: View {
  let state: AppState
  /// nil means the first page, made on the first save.
  let category: String?
  let lines: [String]
  /// Scrolls with the page, above the format bar (the Suggested section).
  @ViewBuilder let below: Below
  @State private var handle = EditorHandle()
  @State private var kind = NoteKind.plain

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      // The page scrolls; the format bar stays pinned to the bottom of the panel, as in Notes.
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          PageEditor(
            state: state, page: category, lines: lines, handle: handle)
          below
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      formatBar
    }
    .onReceive(NotificationCenter.default.publisher(for: NSTextView.didChangeSelectionNotification))
    { _ in
      kind = handle.kind
    }
    .background {
      Button("Focus page") { handle.focusEnd() }
        .keyboardShortcut(.space, modifiers: .option)
        .opacity(0).accessibilityHidden(true)
    }
    .onReceive(NotificationCenter.default.publisher(for: focusNewLine)) { _ in
      handle.focusEnd()
    }
  }

  private var formatBar: some View {
    HStack(spacing: 4) {
      formatButton("checklist", .checklist, label: "Checklist")
      formatButton("list.bullet", .bullet, label: "Bullet")
      formatButton("textformat.size", .heading, label: "Heading")
      Spacer()
    }
  }

  private func formatButton(_ symbol: String, _ target: NoteKind, label: String) -> some View {
    let active = kind == target
    return Button {
      handle.setKind(target)
    } label: {
      Image(systemName: symbol).font(.system(size: 13)).frame(width: 26, height: 22)
        .foregroundStyle(active ? Color.primary : Color.secondary)
        .background(
          active ? Color.primary.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(label)
    .accessibilityAddTraits(active ? .isSelected : [])
    .help(label)
  }
}
