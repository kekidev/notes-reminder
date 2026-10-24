import Foundation
import Testing

@testable import GlanceCore

func fixture(_ name: String) throws -> String {
  let url = try #require(
    Bundle.module.url(forResource: name, withExtension: "md", subdirectory: "Fixtures"))
  return try String(contentsOf: url, encoding: .utf8)
}

func day(_ text: String) -> CalendarDay {
  let parts = text.split(separator: "-").map { Int($0)! }
  return CalendarDay(year: parts[0], month: parts[1], day: parts[2])!
}

extension GlanceDocument {
  func task(named text: String) -> GlanceTask? { tasks.first { $0.text == text } }
}
