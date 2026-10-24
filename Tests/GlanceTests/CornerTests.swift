import CoreGraphics
import Testing

@testable import Glance

private let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)

struct CornerTests {
  @Test(arguments: [
    (CGPoint(x: 900, y: 700), Corner.topRight),
    (CGPoint(x: 100, y: 700), .topLeft),
    (CGPoint(x: 100, y: 100), .bottomLeft),
    (CGPoint(x: 900, y: 100), .bottomRight),
  ])
  func snapsToTheNearestCorner(_ point: CGPoint, _ corner: Corner) {
    #expect(Corner.nearest(to: point, in: screen) == corner)
  }

  @Test func tucksAWindowIntoItsCorner() {
    let size = CGSize(width: 50, height: 50)
    #expect(Corner.topRight.origin(for: size, in: screen) == CGPoint(x: 950, y: 750))
    #expect(Corner.bottomLeft.origin(for: size, in: screen) == CGPoint(x: 0, y: 0))
  }

  @Test func clampsAWindowIntoTheScreen() {
    let size = CGSize(width: 50, height: 50)
    #expect(Corner.clamp(CGPoint(x: 990, y: -20), size: size, in: screen) == CGPoint(x: 950, y: 0))
    #expect(
      Corner.clamp(CGPoint(x: 400, y: 300), size: size, in: screen) == CGPoint(x: 400, y: 300))
  }

  @Test func placesThePanelOnTheScreenSideOfTheBall() {
    let size = CGSize(width: 300, height: 400)
    let ball = CGRect(x: 950, y: 750, width: 50, height: 50)
    #expect(Corner.topRight.panelOrigin(for: size, beside: ball) == CGPoint(x: 700, y: 350))
    let low = CGRect(x: 0, y: 0, width: 50, height: 50)
    #expect(Corner.bottomLeft.panelOrigin(for: size, beside: low) == CGPoint(x: 0, y: 50))
  }
}
