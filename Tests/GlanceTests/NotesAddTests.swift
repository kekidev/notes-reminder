import Foundation
import GlanceCore
import Testing

@testable import Glance

private let utc: Calendar = {
  var cal = Calendar(identifier: .gregorian)
  cal.timeZone = TimeZone(identifier: "UTC")!
  return cal
}()

/// 2026-10-22 12:00 UTC.
private let now = Date(timeIntervalSince1970: 1_792_670_400)

private func parsed(_ input: String) -> (text: String, due: String?) {
  let result = parseQuickAdd(input, now: now, calendar: utc)
  return (result.text, result.due.map { "\($0.day)\($0.time.map { " \($0)" } ?? "")" })
}

struct QuickAddTests {
  @Test func ddlTokenSetsNextOccurrence() {
    #expect(parsed("Hw 6 ddl 10/25") == ("Hw 6", "2026-10-25"))
    #expect(parsed("x ddl 10/22") == ("x", "2026-10-22"))
    #expect(parsed("x ddl 1/5") == ("x", "2027-01-05"))
  }

  @Test func timeIsKept() {
    #expect(parsed("x ddl 10/25 14:30") == ("x", "2026-10-25 14:30"))
  }

  @Test func emojiTokenIsExact() {
    #expect(parsed("x 📅 2026-11-01") == ("x", "2026-11-01"))
    #expect(parsed("x 📅 2026-11-01 09:05") == ("x", "2026-11-01 09:05"))
  }

  @Test func invalidOrAbsentLeavesTextAlone() {
    #expect(parsed("x ddl 13/45") == ("x ddl 13/45", nil))
    #expect(parsed("x ddl 10/25 25:00") == ("x ddl 10/25 25:00", nil))
    #expect(parsed("plain") == ("plain", nil))
  }
}
