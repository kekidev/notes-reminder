import GlanceCore
import SwiftUI

struct CompletedItem: Identifiable {
  let task: GlanceTask
  let page: String
  var id: TaskID { task.id }
}

/// Every crossed-out checklist line on a regular page, newest done first; undated ones last.
func completedItems(_ document: GlanceDocument) -> [CompletedItem] {
  let items = document.categories.filter { !$0.isSuggested }.flatMap { category in
    category.tasks.filter { $0.kind == .checklist && $0.status.isCrossedOut }
      .map { CompletedItem(task: $0, page: category.name) }
  }
  return items.enumerated().sorted { lhs, rhs in
    switch (lhs.element.task.doneAt, rhs.element.task.doneAt) {
    case (let left?, let right?) where left != right: left > right
    case (_?, nil): true
    case (nil, _?): false
    default: lhs.offset < rhs.offset
    }
  }.map(\.element)
}

/// Removes the crossed-out lines of every regular page.
func clearCompleted(_ document: inout GlanceDocument) throws {
  for category in document.categories where !category.isSuggested {
    try document.removeCompleted(in: category.name)
  }
}

/// The Completed tab: a read-only view over the file's crossed-out lines, which stay in their pages.
struct CompletedView: View {
  let state: AppState

  var body: some View {
    let items = completedItems(state.document)
    VStack(alignment: .leading, spacing: 10) {
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          if items.isEmpty {
            Text("Nothing completed yet").foregroundStyle(.secondary)
          }
          ForEach(items) { item in row(item) }
        }
        .font(.mono(13))
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      HStack {
        Spacer()
        if !items.isEmpty {
          Button("Clear all") { state.perform { try clearCompleted(&$0) } }
            .buttonStyle(.plain)
            .font(.mono(11))
            .foregroundStyle(.secondary)
        }
      }
    }
  }

  private func row(_ item: CompletedItem) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      Button {
        let today = CalendarDay(state.now, calendar: .current)
        state.perform { try $0.setStatus(item.id, .todo, today: today) }
      } label: {
        Image(systemName: "checkmark.square.fill").foregroundStyle(.secondary)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Restore \(item.task.text)")
      .help("Restore")
      VStack(alignment: .leading, spacing: 1) {
        Text(item.task.text).strikethrough().foregroundStyle(.secondary)
        Text(item.page).font(.mono(10)).foregroundStyle(.tertiary)
      }
    }
    .contextMenu {
      Button("Delete", role: .destructive) { state.perform { try $0.remove(item.id) } }
    }
  }
}
