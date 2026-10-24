import AppKit
import SwiftUI

/// Borderless panels refuse key status by default. The list panel opts in so its text field can
/// take typing; the ball never does, so it never steals focus.
final class GlancePanel: NSPanel {
  var keyable = false
  override var canBecomeKey: Bool { keyable }
  override func animationResizeTime(_ newFrame: NSRect) -> TimeInterval { 0.2 }
}

/// Drags its window with the mouse. Reports moves and the drop, or a click if the mouse barely moved.
final class DragHostingView<Content: View>: NSHostingView<Content> {
  var onMove: () -> Void = {}
  var onDrop: () -> Void = {}
  var onClick: () -> Void = {}
  private var dragged = false
  private var start: (mouse: CGPoint, origin: CGPoint)?

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func mouseDown(with event: NSEvent) {
    start = (NSEvent.mouseLocation, window?.frame.origin ?? .zero)
    dragged = false
  }

  override func mouseDragged(with event: NSEvent) {
    guard let start else { return }
    let mouse = NSEvent.mouseLocation
    if !dragged && hypot(mouse.x - start.mouse.x, mouse.y - start.mouse.y) <= 3 { return }
    dragged = true
    window?.setFrameOrigin(
      CGPoint(
        x: start.origin.x + mouse.x - start.mouse.x, y: start.origin.y + mouse.y - start.mouse.y)
    )
    onMove()
  }

  override func mouseUp(with event: NSEvent) {
    start = nil
    if dragged { onDrop() } else { onClick() }
  }
}

/// Owns the ball and list panels. Clicking the ball opens and closes the list.
@Observable final class WindowController: NSObject {
  /// Invisible hit area around each panel's content, so the ball's edge is easy to hit.
  static let buffer: CGFloat = 6
  static let originKey = "ballOrigin"

  private let defaults: UserDefaults
  private let ball: GlancePanel
  private let list: GlancePanel
  private let model = ListPanelModel()
  private var open = false
  private(set) var hidden = false

  init(state: AppState, defaults: UserDefaults = .standard) {
    self.defaults = defaults
    let ballView = DragHostingView(rootView: BallView(state: state).padding(Self.buffer).hitArea())
    ball = Self.panel(
      ballView, size: CGSize(width: 56 + 2 * Self.buffer, height: 56 + 2 * Self.buffer))
    let listView = NSHostingView(rootView: ListPanelContent(state: state, model: model))
    let size = PanelSize.load(
      defaults, fallback: ListPanelContent.size, in: Self.screenRect(NSScreen.main),
      buffer: Self.buffer)
    list = Self.panel(
      listView,
      size: CGSize(width: size.width + 2 * Self.buffer, height: size.height + 2 * Self.buffer))
    super.init()

    ball.level = NSWindow.Level(NSWindow.Level.floating.rawValue + 1)
    list.keyable = true
    list.setAccessibilityLabel("Glance list")
    list.becomesKeyOnlyIfNeeded = true  // only a click in the text field takes focus
    model.size = size
    model.resize = { [weak self] in self?.resizeList(to: $0) }
    model.resizeEnded = { [weak self] in
      guard let self else { return }
      self.defaults.set(NSStringFromSize(self.model.size), forKey: PanelSize.key)
    }
    ballView.onMove = { [weak self] in self?.placeList() }
    ballView.onDrop = { [weak self] in self?.drop() }
    ballView.onClick = { [weak self] in self?.toggle() }

    let rect = Self.screenRect(NSScreen.main)
    let saved = defaults.string(forKey: Self.originKey).map(NSPointFromString)
    ball.setFrameOrigin(
      Corner.clamp(
        saved ?? Corner.topRight.origin(for: ball.frame.size, in: rect),
        size: ball.frame.size, in: rect))
    ball.orderFrontRegardless()
  }

  private static func panel(_ view: NSView, size: CGSize) -> GlancePanel {
    let panel = GlancePanel(
      contentRect: CGRect(origin: .zero, size: size),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered, defer: false)
    panel.contentView = view
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = false
    panel.hidesOnDeactivate = false
    return panel
  }

  private static func screenRect(_ screen: NSScreen?) -> CGRect {
    (screen?.visibleFrame ?? .zero).insetBy(dx: 4, dy: 4)
  }

  private static var reduceMotion: Bool {
    NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
  }

  // MARK: Ball position

  private func placeList() {
    let rect = Self.screenRect(ball.screen)
    let corner = Corner.nearest(to: CGPoint(x: ball.frame.midX, y: ball.frame.midY), in: rect)
    model.corner = corner
    list.setFrameOrigin(
      Corner.clamp(
        corner.panelOrigin(for: list.frame.size, beside: ball.frame),
        size: list.frame.size, in: rect))
  }

  /// Resizes the list, then hangs it off the ball again.
  private func resizeList(to wanted: CGSize) {
    let size = PanelSize.clamp(wanted, in: Self.screenRect(list.screen), buffer: Self.buffer)
    model.size = size
    list.setContentSize(
      CGSize(width: size.width + 2 * Self.buffer, height: size.height + 2 * Self.buffer))
    placeList()
  }

  private func drop() {
    let rect = Self.screenRect(ball.screen)
    ball.setFrameOrigin(Corner.clamp(ball.frame.origin, size: ball.frame.size, in: rect))
    defaults.set(NSStringFromPoint(ball.frame.origin), forKey: Self.originKey)
    placeList()
  }

  // MARK: List

  /// Show or hide both panels. The list comes back only if it was open.
  func toggleVisible() {
    hidden.toggle()
    if hidden {
      ball.orderOut(nil)
      list.orderOut(nil)
    } else {
      ball.orderFrontRegardless()
      if open { list.orderFront(nil) }
    }
  }

  func toggle() {
    open.toggle()
    if open {
      placeList()
      list.orderFrontRegardless()
      withAnimation(Self.reduceMotion ? nil : .easeOut(duration: 0.18)) { model.shown = true }
    } else {
      model.shown = false
      list.orderOut(nil)
    }
  }

  /// Opens the list now and tells the add field to take focus.
  func summon() {
    if hidden { toggleVisible() }
    if !open { toggle() }
    list.makeKey()
    NotificationCenter.default.post(name: Notification.Name("GlanceFocusAddField"), object: nil)
  }
}
