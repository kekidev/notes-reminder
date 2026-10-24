import SwiftUI

/// Liquid Glass in `shape`, or a solid fill when Reduce Transparency is on. With `fill`, clear
/// glass under a fill of that opacity (0 clear, 1 solid).
struct GlassBackground<S: Shape>: ViewModifier {
  let shape: S
  var fill: Double?
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  func body(content: Content) -> some View {
    if reduceTransparency {
      content.background(.background, in: shape)
    } else {
      if let fill {
        content.background(Color(nsColor: .windowBackgroundColor).opacity(fill), in: shape)
          .glassEffect(.clear, in: shape)
      } else {
        content.glassEffect(.regular, in: shape)
      }
    }
  }
}
