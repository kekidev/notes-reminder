import GlanceCore
import SwiftUI

/// The AI's suggestions: always shown while there are any.
struct SuggestedSection: View {
  let state: AppState
  let tasks: [GlanceTask]
  /// Where ✓ files a suggestion.
  let defaultCategory: String?
  let categories: [String]

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(GlanceCore.Category.suggested).font(.mono(13, bold: true))
      ForEach(tasks) { task in
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Button {
            accept(task, into: defaultCategory)
          } label: {
            Image(systemName: "checkmark").font(.system(size: 13))
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Accept \(task.text)")
          VStack(alignment: .leading, spacing: 2) {
            Text(dueLabel(task)).font(.mono(13))
            if let notes = task.notes {
              Text(notes).font(.system(size: 11)).foregroundStyle(.secondary)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          Button {
            state.perform { try $0.dismissSuggestion(task.id) }
          } label: {
            Image(systemName: "xmark").font(.system(size: 13))
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Dismiss \(task.text)")
        }
        .contextMenu {
          Menu("Accept into") {
            ForEach(categories, id: \.self) { name in
              Button(name) { accept(task, into: name) }
            }
          }
        }
      }
      .padding(.leading, 16)
    }
  }

  private func accept(_ task: GlanceTask, into category: String?) {
    state.perform { try $0.acceptSuggestion(task.id, into: category) }
  }
}
