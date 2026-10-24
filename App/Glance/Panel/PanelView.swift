import GlanceCore
import SwiftUI

extension Font {
  static func mono(_ size: CGFloat, bold: Bool = false) -> Font {
    .custom(bold ? "JetBrainsMono-Bold" : "JetBrainsMono-Regular", size: size)
  }
}

/// The page row shows once there is more than one tab: two pages, or a page and Completed.
func showsPageRow(pageCount: Int, showCompleted: Bool) -> Bool {
  pageCount + (pageCount > 0 && showCompleted ? 1 : 0) > 1
}

/// How solid the panel is: 0 is clear glass, 1 is a solid fill.
enum PanelOpacity {
  static let key = "panelOpacity"
  static let fallback = 0.7
}

/// The panel: date header, an optional row of pages, then the current page as a notepad.
struct PanelView: View {
  let state: AppState
  @Environment(\.openSettings) private var openSettings
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @AppStorage("selectedPage") private var selectedPage = ""
  @AppStorage("showCompleted") private var showCompleted = true
  @State private var onCompleted = false
  @AppStorage(PanelOpacity.key) private var opacity = PanelOpacity.fallback
  @State private var showSlider = false
  /// Non-nil while the "new page" field is open.
  @State private var newName: String?
  @FocusState private var nameFocused: Bool
  /// The page being renamed in its capsule, with the name typed so far.
  @State private var renaming: (page: String, name: String)?

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      header
      if showSlider { slider }
      if newName != nil { newPageField }
      if showsPageRow(pageCount: pages.count, showCompleted: showCompleted) { pageRow }
      if onCompleted && showCompleted {
        CompletedView(state: state)
      } else {
        NotepadView(
          state: state, category: current, lines: state.document.bodyLines(of: current ?? "")
        ) {
          let suggestions = state.document.categories.first { $0.isSuggested }?.tasks ?? []
          if !suggestions.isEmpty {
            SuggestedSection(
              state: state, tasks: suggestions, defaultCategory: current, categories: pages)
          }
        }
      }
      if let error = state.lastError, error as? TaskOpsError != .emptyText {
        Text(String(describing: error)).font(.system(size: 11)).foregroundStyle(.red).lineLimit(2)
      }
    }
    .padding(.horizontal, 22)
    .padding(.vertical, 18)
  }

  private var pages: [String] {
    state.document.categories.filter { !$0.isSuggested }.map(\.name)
  }

  /// The selected page, or the first one when it is gone; nil until the first line makes one.
  private var current: String? { pages.first { $0 == selectedPage } ?? pages.first }

  private func headerButton(
    _ symbol: String, _ label: String, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) { Image(systemName: symbol).foregroundStyle(.secondary) }
      .buttonStyle(.plain)
      .accessibilityLabel(label)
      .help(label)
  }

  private var addPage: some View {
    headerButton("plus", "Add page") { newName = "" }
  }

  private var slider: some View {
    Slider(value: $opacity, in: 0...1)
      .controlSize(.mini)
      .disabled(reduceTransparency)
      .accessibilityLabel("Panel opacity")
  }

  private var newPageField: some View {
    TextField("New page", text: Binding(get: { newName ?? "" }, set: { newName = $0 }))
      .textFieldStyle(.plain)
      .font(.mono(11))
      .focused($nameFocused)
      .onAppear { nameFocused = true }
      .onSubmit { commitNew() }
      .onExitCommand { newName = nil }
  }

  private func commitNew() {
    guard let typed = newName else { return }
    let name = typed.trimmingCharacters(in: .whitespaces)
    newName = nil
    guard !name.isEmpty else { return }
    state.perform { try $0.addCategory(name) }
    if state.lastError == nil { selectedPage = name }
  }

  private func commitRename() {
    guard let (old, typed) = renaming else { return }
    renaming = nil
    let name = typed.trimmingCharacters(in: .whitespaces)
    guard !name.isEmpty, name != old else { return }
    state.perform { try $0.renameCategory(old, to: name) }
    if state.lastError == nil { selectedPage = name }
  }

  private var header: some View {
    ZStack {
      // Redraws each minute so the date turns over at midnight.
      TimelineView(.everyMinute) { context in
        Text(headerDate(context.date)).font(.mono(12)).foregroundStyle(.secondary)
      }
      HStack(spacing: 10) {
        Spacer()
        if !showsPageRow(pageCount: pages.count, showCompleted: showCompleted) { addPage }
        headerButton("circle.lefthalf.filled", "Transparency") { showSlider.toggle() }
        headerButton("gearshape", "Settings") {
          NSApp.activate()
          openSettings()
        }
        headerButton("xmark.circle", "Quit Glance") { NSApp.terminate(nil) }
      }
    }
  }

  /// A capsule per page; the selected one is a white pill. Hover for ✕; right-click to rename.
  private var pageRow: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        HStack(spacing: 0) {
          ForEach(pages, id: \.self) { page in
            PageCapsule(
              page: page, selected: page == current && !(onCompleted && showCompleted),
              renaming: $renaming,
              hasLines: !(state.document.bodyLines(of: page).isEmpty),
              select: {
                selectedPage = page
                onCompleted = false
              }, commitRename: commitRename,
              delete: { state.perform { try $0.removeCategory(page) } })
          }
          if showCompleted {
            CompletedCapsule(
              selected: onCompleted, select: { onCompleted = true },
              hide: { showCompleted = false })
          }
        }
        .padding(2)
        .background(Capsule().fill(.quaternary))
        addPage
      }
    }
  }
}

/// The built-in Completed tab at the end of the row. Hover for ✕, which only hides the tab.
private struct CompletedCapsule: View {
  let selected: Bool
  let select: () -> Void
  let hide: () -> Void
  @State private var hovering = false

  var body: some View {
    HStack(spacing: 4) {
      Button("Completed", action: select).buttonStyle(.plain).lineLimit(1)
      if hovering {
        Button(action: hide) { Image(systemName: "xmark") }
          .buttonStyle(.plain)
          .accessibilityLabel("Hide Completed tab")
          .help("Hide tab (Settings brings it back)")
      }
    }
    .font(.mono(11))
    .foregroundStyle(selected ? Color.black : Color.secondary)
    .padding(.horizontal, 8)
    .padding(.vertical, 5)
    .background {
      if selected {
        Capsule().fill(Color.white.opacity(0.9))
          .shadow(color: .black.opacity(0.1), radius: 1, y: 0.5)
      }
    }
    .onHover { hovering = $0 }
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}

/// One page in the row. An empty page deletes on the first ✕; one with lines asks "Delete?" first.
private struct PageCapsule: View {
  let page: String
  let selected: Bool
  @Binding var renaming: (page: String, name: String)?
  let hasLines: Bool
  let select: () -> Void
  let commitRename: () -> Void
  let delete: () -> Void
  @State private var hovering = false
  @State private var confirming = false
  @FocusState private var focused: Bool

  var body: some View {
    HStack(spacing: 4) {
      if renaming?.page == page {
        TextField(
          "Name",
          text: Binding(get: { renaming?.name ?? "" }, set: { renaming?.name = $0 })
        )
        .textFieldStyle(.plain)
        .focused($focused)
        .onAppear { focused = true }
        .onSubmit(commitRename)
        .onExitCommand { renaming = nil }
        .frame(minWidth: 40)
      } else {
        Button(page, action: select).buttonStyle(.plain).lineLimit(1)
        if confirming {
          Button("Delete?", action: delete).buttonStyle(.plain).foregroundStyle(.red)
        } else if hovering {
          Button(action: requestDelete) { Image(systemName: "xmark") }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete page \(page)")
            .help("Delete page")
        }
      }
    }
    .font(.mono(11))
    // The selected pill is white in both modes, so its text stays black.
    .foregroundStyle(selected ? Color.black : Color.secondary)
    .padding(.horizontal, 8)
    .padding(.vertical, 5)
    .background {
      if selected {
        Capsule().fill(Color.white.opacity(0.9))
          .shadow(color: .black.opacity(0.1), radius: 1, y: 0.5)
      }
    }
    .onHover {
      hovering = $0
      if !$0 { confirming = false }
    }
    .accessibilityAddTraits(selected ? .isSelected : [])
    .accessibilityAction(named: "Delete page", requestDelete)
    .contextMenu {
      Button("Rename…") { renaming = (page, page) }
      Button("Delete…", role: .destructive, action: requestDelete)
    }
  }

  private func requestDelete() {
    if hasLines { confirming = true } else { delete() }
  }
}
