import CoreGraphics
import Foundation

/// The list panel's content size: 320x400 to 640x900, never bigger than the visible screen.
enum PanelSize {
  static let key = "listPanelSize"
  static let minimum = CGSize(width: 320, height: 400)
  static let maximum = CGSize(width: 640, height: 900)

  /// `size` limited to the range and to `screen` less the invisible buffer around the content.
  static func clamp(_ size: CGSize, in screen: CGRect, buffer: CGFloat) -> CGSize {
    func limit(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat, _ room: CGFloat) -> CGFloat {
      max(low, min(value, high, room))
    }
    return CGSize(
      width: limit(size.width, minimum.width, maximum.width, screen.width - 2 * buffer),
      height: limit(size.height, minimum.height, maximum.height, screen.height - 2 * buffer))
  }

  /// The saved size, or `fallback`, clamped.
  static func load(
    _ defaults: UserDefaults, fallback: CGSize, in screen: CGRect, buffer: CGFloat
  ) -> CGSize {
    let saved = defaults.string(forKey: key).map(NSSizeFromString)
    return clamp(saved.flatMap { $0 == .zero ? nil : $0 } ?? fallback, in: screen, buffer: buffer)
  }
}
