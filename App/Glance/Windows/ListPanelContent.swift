import SwiftUI

/// What the list panel's SwiftUI content needs from `WindowController`.
@Observable final class ListPanelModel {
  var shown = false
  var corner = Corner.topRight
  var size = ListPanelContent.size
  /// Asks the controller for a new content size; it clamps, resizes the window and re-places it.
  var resize: (CGSize) -> Void = { _ in }
  var resizeEnded: () -> Void = {}
}

/// Hosts T3's `PanelView` in a glass card that grows out of the ball's corner.
struct ListPanelContent: View {
  /// The default size; the dragged size lives in `ListPanelModel.size`.
  static let size = CGSize(width: 400, height: 560)

  let state: AppState
  let model: ListPanelModel
  @AppStorage(PanelOpacity.key) private var opacity = PanelOpacity.fallback

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: 18)
    ZStack {
      if model.shown {
        PanelView(state: state)
          .scrollContentBackground(.hidden)
          .clipShape(shape)
          .modifier(GlassBackground(shape: shape, fill: opacity))
          .overlay(alignment: .topLeading) { ResizeGrip(model: model) }
          .transition(.scale(scale: 0.15, anchor: anchor).combined(with: .opacity))
      }
    }
    .frame(width: model.size.width, height: model.size.height)
    .padding(WindowController.buffer)
    .hitArea()
  }

  private var anchor: UnitPoint {
    switch model.corner {
    case .topLeft: .topLeading
    case .topRight: .topTrailing
    case .bottomLeft: .bottomLeading
    case .bottomRight: .bottomTrailing
    }
  }
}

/// Drag the panel's top-left corner to resize it. Dragging left or up grows the panel.
private struct ResizeGrip: View {
  let model: ListPanelModel
  @State private var start: (mouse: CGPoint, size: CGSize)?

  var body: some View {
    Image(systemName: "arrow.up.left.and.arrow.down.right")
      .font(.system(size: 9, weight: .semibold))
      .foregroundStyle(.tertiary)
      .frame(width: 22, height: 22)
      .contentShape(Rectangle())
      .pointerStyle(.frameResize(position: .topLeading))
      .accessibilityLabel("Resize panel")
      .help("Drag to resize")
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { _ in
            // The window moves under the pointer, so measure against the screen, not the view.
            let mouse = NSEvent.mouseLocation
            let origin = start ?? (mouse, model.size)
            start = origin
            model.resize(
              CGSize(
                width: origin.size.width - (mouse.x - origin.mouse.x),
                height: origin.size.height + (mouse.y - origin.mouse.y)))
          }
          .onEnded { _ in
            start = nil
            model.resizeEnded()
          })
  }
}

extension View {
  /// The window server skips fully clear pixels, so the buffer gets a fill too faint to see.
  func hitArea() -> some View { background(Color.black.opacity(0.001)) }
}
