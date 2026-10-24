import AppKit
import GlanceCore
import SwiftUI

/// Lets the page's other controls reach its text view.
final class EditorHandle {
  fileprivate weak var view: NotesTextView?

  /// Focuses the editor with the cursor at the end of the page.
  func focusEnd() {
    guard let view else { return }
    view.window?.makeFirstResponder(view)
    view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
    view.scrollRangeToVisible(view.selectedRange())
  }

  var kind: NoteKind { view?.currentKind ?? .plain }

  /// Sets the current line's kind; a line already of that kind goes back to plain.
  func setKind(_ kind: NoteKind) {
    guard let view else { return }
    view.window?.makeFirstResponder(view)
    view.convertParagraph(to: view.currentKind == kind ? .plain : kind)
  }
}

/// One page as an editable text view. Edits save about half a second after typing stops, and on blur.
struct PageEditor: NSViewRepresentable {
  let state: AppState
  /// nil until the first page exists; the first save makes it.
  let page: String?
  /// The page in the document, shown whenever the user isn't editing.
  let lines: [String]
  let handle: EditorHandle

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  func makeNSView(context: Context) -> NotesTextView {
    let view = NotesTextView.make()
    view.load(lines: PageText.visible(lines))
    context.coordinator.base = GlanceDocument.shown(PageText.visible(lines))
    view.onEdit = { [coordinator = context.coordinator] in coordinator.edited() }
    view.onResign = { [coordinator = context.coordinator] in coordinator.flush() }
    context.coordinator.view = view
    handle.view = view
    return view
  }

  func updateNSView(_ view: NotesTextView, context: Context) {
    handle.view = view
    view.setAccessibilityLabel("Page \(page ?? "")")
    context.coordinator.update(self)
  }

  static func dismantleNSView(_ view: NotesTextView, coordinator: Coordinator) {
    coordinator.flush()
  }

  func sizeThatFits(_ proposal: ProposedViewSize, nsView view: NotesTextView, context: Context)
    -> CGSize?
  {
    let width = proposal.width ?? 300
    guard let layout = view.layoutManager, let container = view.textContainer else { return nil }
    container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
    layout.ensureLayout(for: container)
    // Tall enough that a click below the last line still lands in the editor.
    return CGSize(width: width, height: max(ceil(layout.usedRect(for: container).height), 160))
  }

  final class Coordinator {
    var parent: PageEditor
    weak var view: NotesTextView?
    private var page: String?
    private var unsaved = false
    /// The page as last loaded or saved, to spot lines another writer (MCP) added meanwhile.
    var base: [String] = []
    /// The one pending save; nothing runs while idle.
    private var pending: Task<Void, Never>?
    /// The one pending hide of crossed-out lines; nothing runs while idle.
    private var hiding: Task<Void, Never>?

    init(_ parent: PageEditor) {
      self.parent = parent
      page = parent.page
      // Quitting tears nothing down, so the last half second of typing would otherwise be lost.
      NotificationCenter.default.addObserver(
        forName: NSApplication.willTerminateNotification, object: nil, queue: .main
      ) { [weak self] _ in MainActor.assumeIsolated { self?.flush() } }
    }

    func edited() {
      unsaved = true
      pending?.cancel()
      pending = Task { @MainActor [weak self] in
        try? await Task.sleep(for: .milliseconds(500))
        if !Task.isCancelled { self?.flush() }
      }
      if hiding == nil, let view, view.doneCount > 0 {
        // A crossed-out line stays for a moment so a mis-click can be undone.
        hiding = Task { @MainActor [weak self] in
          try? await Task.sleep(for: .seconds(2))
          if !Task.isCancelled { self?.hideDone() }
        }
      }
    }

    private func hideDone() {
      hiding = nil
      flush()
      guard let view else { return }
      // The file keeps these lines; the next save puts them back after the lines they follow.
      base = base.filter { !PageText.isDone($0) }
      view.removeDone()
    }

    func flush() {
      pending?.cancel()
      pending = nil
      guard unsaved, let view else { return }
      unsaved = false
      save(view.lines, to: page, base: base)
    }

    func update(_ new: PageEditor) {
      parent = new
      guard let view else { return }
      if new.page != page {
        if unsaved {
          // Saving changes observed state, which a view update must not do.
          let (lines, old, oldBase) = (view.lines, page, base)
          unsaved = false
          pending?.cancel()
          Task { @MainActor in self.save(lines, to: old, base: oldBase) }
        }
        page = new.page
        hiding?.cancel()
        hiding = nil
        reload(PageText.visible(new.lines))
      } else if !unsaved, hiding == nil, view.window?.firstResponder !== view,
        view.lines != GlanceDocument.shown(PageText.visible(new.lines))
      {
        reload(PageText.visible(new.lines))
      }
    }

    private func reload(_ lines: [String]) {
      view?.load(lines: lines)
      base = GlanceDocument.shown(lines)
    }

    /// Merges against the file as it is at write time, so a line MCP just added is kept, not overwritten.
    private func save(_ lines: [String], to page: String?, base: [String]) {
      var added: [String] = []
      parent.state.perform { doc in
        added = try doc.savePage(
          page ?? GlanceDocument.defaultCategory, edited: lines, base: base,
          today: CalendarDay(.now, calendar: .current))
      }
      guard page == self.page else { return }
      // Crossed-out lines stay hidden; everything else another writer added shows up.
      let shown = PageText.visible(added)
      self.base = lines + shown
      view?.append(lines: shown)
    }
  }
}
