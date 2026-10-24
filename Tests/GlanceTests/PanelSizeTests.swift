import Foundation
import Testing

@testable import Glance

struct PanelSizeTests {
  private let screen = CGRect(x: 0, y: 0, width: 1440, height: 800)

  @Test func sizeStaysBetweenTheMinimumAndMaximum() {
    let small = PanelSize.clamp(CGSize(width: 10, height: 10), in: screen, buffer: 6)
    #expect(small == CGSize(width: 320, height: 400))
    let big = PanelSize.clamp(CGSize(width: 5000, height: 5000), in: .infinite, buffer: 6)
    #expect(big == CGSize(width: 640, height: 900))
  }

  @Test func sizeFitsTheVisibleScreenLessTheBuffer() {
    let size = PanelSize.clamp(CGSize(width: 600, height: 900), in: screen, buffer: 6)
    #expect(size == CGSize(width: 600, height: 788))
  }

  @Test func theSavedSizeIsClampedAndMissingOrBrokenFallsBack() throws {
    let defaults = try #require(UserDefaults(suiteName: "glance-\(UUID())"))
    let fallback = CGSize(width: 400, height: 560)
    #expect(PanelSize.load(defaults, fallback: fallback, in: screen, buffer: 6) == fallback)
    defaults.set("garbage", forKey: PanelSize.key)
    #expect(PanelSize.load(defaults, fallback: fallback, in: screen, buffer: 6) == fallback)
    defaults.set(NSStringFromSize(CGSize(width: 2000, height: 450)), forKey: PanelSize.key)
    #expect(
      PanelSize.load(defaults, fallback: fallback, in: screen, buffer: 6)
        == CGSize(width: 640, height: 450))
  }
}
