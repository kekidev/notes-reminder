import CoreGraphics

/// A screen corner. It picks which side of the ball the list opens on.
enum Corner {
  case topLeft, topRight, bottomLeft, bottomRight

  var isTop: Bool { self == .topLeft || self == .topRight }
  var isRight: Bool { self == .topRight || self == .bottomRight }

  static func nearest(to point: CGPoint, in rect: CGRect) -> Corner {
    switch (point.y >= rect.midY, point.x >= rect.midX) {
    case (true, true): .topRight
    case (true, false): .topLeft
    case (false, true): .bottomRight
    case (false, false): .bottomLeft
    }
  }

  /// The origin that puts a window of `size` into this corner of `rect`.
  func origin(for size: CGSize, in rect: CGRect) -> CGPoint {
    CGPoint(
      x: isRight ? rect.maxX - size.width : rect.minX,
      y: isTop ? rect.maxY - size.height : rect.minY)
  }

  /// The origin that hangs a panel of `size` off `ball`, toward the middle of the screen.
  func panelOrigin(for size: CGSize, beside ball: CGRect) -> CGPoint {
    CGPoint(
      x: isRight ? ball.maxX - size.width : ball.minX,
      y: isTop ? ball.minY - size.height : ball.maxY)
  }

  /// `origin` moved the least needed to keep a window of `size` inside `rect`.
  static func clamp(_ origin: CGPoint, size: CGSize, in rect: CGRect) -> CGPoint {
    CGPoint(
      x: min(max(origin.x, rect.minX), max(rect.minX, rect.maxX - size.width)),
      y: min(max(origin.y, rect.minY), max(rect.minY, rect.maxY - size.height)))
  }
}
