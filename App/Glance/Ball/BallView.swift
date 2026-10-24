import SwiftUI

struct BallView: View {
  let state: AppState
  @State private var scale = 1.0

  var body: some View {
    ZStack {
      if state.dueCount > 0 {
        Circle().fill(Color(red: 0xE8 / 255, green: 0xA0 / 255, blue: 0xB4 / 255).opacity(0.35))
      }
      Text("\(state.todoCount)")
        .font(.custom("JetBrainsMono-Regular", size: 16))
    }
    .frame(width: 56, height: 56)
    .modifier(GlassBackground(shape: Circle()))
    .scaleEffect(scale)
    .onChange(of: state.todoCount) {
      guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
      withAnimation(.easeOut(duration: 0.175), completionCriteria: .logicallyComplete) {
        scale = 1.08
      } completion: {
        withAnimation(.easeIn(duration: 0.175)) { scale = 1 }
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      "\(state.todoCount) to-do tasks" + (state.dueCount > 0 ? ", \(state.dueCount) due" : "")
    )
    .accessibilityHint("Click to open your list")
  }
}
