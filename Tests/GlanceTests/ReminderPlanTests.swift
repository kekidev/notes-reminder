import Foundation
import GlanceCore
import Testing

@testable import Glance

private let calendar: Calendar = {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
  return calendar
}()

private func date(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
  calendar.date(
    from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
}

private let now = date(10, 22, 10)

private func plan(_ text: String) -> [Reminder] {
  reminderPlan(MarkdownParser.parse(text), now: now, calendar: calendar)
}

struct ReminderPlanTests {
  @Test func dateOnlyFiresAtNineLocal() {
    let plan = plan("## work\n- [ ] report 📅 2026-10-25\n")
    #expect(plan.map(\.fire) == [date(10, 25, 9)])
    #expect(plan.first?.title == "report")
    #expect(plan.first?.body == "work · due 10/25")
    #expect(plan.first?.id.hasPrefix("glance.") == true)
  }

  @Test func timedTaskFiresAtItsTime() {
    let plan = plan("## life\n- [/] call 📅 2026-10-23 14:30\n")
    #expect(plan.map(\.fire) == [date(10, 23, 14, 30)])
    #expect(plan.first?.body == "life · due 10/23 14:30")
  }

  @Test func pastFireTimesAreDropped() {
    #expect(plan("## work\n- [ ] late 📅 2026-10-22\n- [ ] exactly 📅 2026-10-22 10:00\n").isEmpty)
  }

  @Test func closedSuggestedAndUndatedAreSkipped() {
    let text = """
      ## work
      - [x] done 📅 2026-10-25
      - [-] dropped 📅 2026-10-25
      - [ ] no date

      ## suggested
      - [ ] idea 📅 2026-10-25 🤖 claude 2026-10-20

      """
    #expect(plan(text).isEmpty)
  }

  @Test func sortedByFireTimeAndCappedAtSixty() {
    let lines = (0..<70).reversed().map {
      "- [ ] t\($0) 📅 2026-11-01 \(String(format: "%02d:%02d", 10 + $0 / 60, $0 % 60))"
    }
    let plan = plan("## work\n" + lines.joined(separator: "\n") + "\n")
    #expect(plan.count == 60)
    #expect(plan.map(\.fire) == plan.map(\.fire).sorted())
    #expect(plan.first?.title == "t0")
    #expect(plan.last?.title == "t59")
  }
}
