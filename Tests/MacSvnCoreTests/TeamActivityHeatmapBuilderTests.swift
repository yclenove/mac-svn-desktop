import XCTest
@testable import MacSvnCore

final class TeamActivityHeatmapBuilderTests: XCTestCase {
    func testBuildFillsCalendarGridAndMapsIntensityLevels() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2 // 周一

        // 2026-06-01 周一 … 覆盖约两周
        let day: (Int) -> Date = { d in
            calendar.date(from: DateComponents(year: 2026, month: 6, day: d))!
        }
        let days = [
            TeamActivityDay(date: day(1), commitCount: 1),
            TeamActivityDay(date: day(2), commitCount: 3),
            TeamActivityDay(date: day(8), commitCount: 10),
        ]

        let builder = TeamActivityHeatmapBuilder(calendar: calendar)
        // 锚定到数据区间末，避免「今天」把窗口拉出测试日期
        let grid = builder.build(from: days, weeks: 2, endDate: day(8))

        XCTAssertEqual(grid.weeks.count, 2)
        XCTAssertEqual(grid.weeks[0].count, 7)
        XCTAssertEqual(grid.maxCommitCount, 10)

        let flat = grid.weeks.flatMap { $0 }
        let june1 = flat.first { calendar.isDate($0.date, inSameDayAs: day(1)) }
        let june2 = flat.first { calendar.isDate($0.date, inSameDayAs: day(2)) }
        let june8 = flat.first { calendar.isDate($0.date, inSameDayAs: day(8)) }
        XCTAssertEqual(june1?.commitCount, 1)
        XCTAssertEqual(june1?.intensity, 1)
        XCTAssertEqual(june2?.commitCount, 3)
        XCTAssertEqual(june2?.intensity, 2)
        XCTAssertEqual(june8?.commitCount, 10)
        XCTAssertEqual(june8?.intensity, 4)

        // 无提交日 intensity 为 0
        let empty = flat.first { $0.commitCount == 0 }
        XCTAssertEqual(empty?.intensity, 0)
    }

    func testBuildEmptyDaysProducesZeroIntensityGrid() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let builder = TeamActivityHeatmapBuilder(calendar: calendar)
        let grid = builder.build(from: [], weeks: 1, endDate: calendar.date(from: DateComponents(year: 2026, month: 7, day: 10))!)
        XCTAssertEqual(grid.weeks.count, 1)
        XCTAssertEqual(grid.maxCommitCount, 0)
        XCTAssertTrue(grid.weeks[0].allSatisfy { $0.intensity == 0 && $0.commitCount == 0 })
    }

    func testDefaultEndAnchorsToTodayWhenLastCommitIsOld() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        let old = calendar.date(from: DateComponents(year: 2025, month: 1, day: 6))!
        let days = [TeamActivityDay(date: old, commitCount: 5)]
        let builder = TeamActivityHeatmapBuilder(calendar: calendar)
        let grid = builder.build(from: days, weeks: 2)
        let flat = grid.weeks.flatMap { $0 }
        let today = calendar.startOfDay(for: Date())
        XCTAssertTrue(flat.contains { calendar.isDate($0.date, inSameDayAs: today) })
        // 旧提交不在近 2 周窗口内 → 峰值 0
        XCTAssertEqual(grid.maxCommitCount, 0)
    }

    func testWeekdayLabelsFollowFirstWeekday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = 1 // 周日
        let builder = TeamActivityHeatmapBuilder(calendar: calendar)
        let labels = builder.weekdayLabels(locale: Locale(identifier: "en_US_POSIX"))
        XCTAssertEqual(labels.count, 7)
        XCTAssertEqual(labels.first, calendar.veryShortWeekdaySymbols[0])
    }

    func testDuplicateDaysAreMergedWithoutTrap() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1))!
        let builder = TeamActivityHeatmapBuilder(calendar: calendar)
        let grid = builder.build(
            from: [
                TeamActivityDay(date: day, commitCount: 2),
                TeamActivityDay(date: day, commitCount: 3),
            ],
            weeks: 1,
            endDate: day
        )
        let cell = grid.weeks.flatMap { $0 }.first { calendar.isDate($0.date, inSameDayAs: day) }
        XCTAssertEqual(cell?.commitCount, 5)
    }
}
