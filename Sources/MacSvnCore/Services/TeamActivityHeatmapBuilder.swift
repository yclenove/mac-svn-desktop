import Foundation

/// 热力图单日格子（强度 0–4，对标 GitHub 贡献图）。
public struct TeamActivityHeatmapCell: Equatable, Sendable {
    public let date: Date
    public let commitCount: Int
    /// 0=无提交；1–4 按相对峰值分档。
    public let intensity: Int

    public init(date: Date, commitCount: Int, intensity: Int) {
        self.date = date
        self.commitCount = commitCount
        self.intensity = intensity
    }
}

/// 按周列、周内日行的日历热力网格。
public struct TeamActivityHeatmapGrid: Equatable, Sendable {
    public let weeks: [[TeamActivityHeatmapCell]]
    public let maxCommitCount: Int

    public init(weeks: [[TeamActivityHeatmapCell]], maxCommitCount: Int) {
        self.weeks = weeks
        self.maxCommitCount = maxCommitCount
    }
}

/// 将按日提交聚合为日历热力图数据（FR-EX-06）。
public struct TeamActivityHeatmapBuilder: Sendable {
    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    /// - Parameters:
    ///   - days: 有提交的日期（可稀疏；同日计数会合并）
    ///   - weeks: 展示周数（列数）
    ///   - endDate: 网格右端参考日；默认 `max(最后提交日, 今天)`，避免久未提交时窗口停在历史
    public func build(
        from days: [TeamActivityDay],
        weeks: Int = 12,
        endDate: Date? = nil
    ) -> TeamActivityHeatmapGrid {
        let weekCount = max(1, weeks)
        var countsByDay: [Date: Int] = [:]
        for day in days {
            let key = calendar.startOfDay(for: day.date)
            countsByDay[key, default: 0] += day.commitCount
        }

        let today = calendar.startOfDay(for: Date())
        let resolvedEnd: Date
        if let endDate {
            resolvedEnd = calendar.startOfDay(for: endDate)
        } else if let last = countsByDay.keys.max() {
            resolvedEnd = max(last, today)
        } else {
            resolvedEnd = today
        }

        let weekStartContainingEnd = startOfWeek(containing: resolvedEnd)
        let firstColumnStart = calendar.date(
            byAdding: .day,
            value: -7 * (weekCount - 1),
            to: weekStartContainingEnd
        ) ?? weekStartContainingEnd

        // 强度峰值仅取可见窗口内，避免窗外历史高峰压低近期档位
        var windowMax = 0
        var weekColumns: [[TeamActivityHeatmapCell]] = []
        weekColumns.reserveCapacity(weekCount)
        var rawCounts: [[(Date, Int)]] = []
        rawCounts.reserveCapacity(weekCount)

        for weekIndex in 0..<weekCount {
            var columnRaw: [(Date, Int)] = []
            columnRaw.reserveCapacity(7)
            for dayOffset in 0..<7 {
                let offset = weekIndex * 7 + dayOffset
                let date = calendar.date(byAdding: .day, value: offset, to: firstColumnStart)
                    ?? firstColumnStart
                let day = calendar.startOfDay(for: date)
                let count = countsByDay[day] ?? 0
                windowMax = max(windowMax, count)
                columnRaw.append((day, count))
            }
            rawCounts.append(columnRaw)
        }

        for columnRaw in rawCounts {
            let column = columnRaw.map { day, count in
                TeamActivityHeatmapCell(
                    date: day,
                    commitCount: count,
                    intensity: Self.intensity(commitCount: count, maxCommitCount: windowMax)
                )
            }
            weekColumns.append(column)
        }

        return TeamActivityHeatmapGrid(weeks: weekColumns, maxCommitCount: windowMax)
    }

    /// 非零提交按相对峰值映射到 1–4；无提交为 0。
    public static func intensity(commitCount: Int, maxCommitCount: Int) -> Int {
        guard commitCount > 0, maxCommitCount > 0 else { return 0 }
        let level = Int((Double(commitCount) / Double(maxCommitCount) * 4.0).rounded(.up))
        return min(4, max(1, level))
    }

    /// 与网格行顺序一致的周内日短标签（跟随 `calendar.firstWeekday`）。
    public func weekdayLabels(locale: Locale = .current) -> [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        guard symbols.count == 7 else {
            return symbols
        }
        let first = max(1, min(7, calendar.firstWeekday)) - 1
        return Array(symbols[first...]) + Array(symbols[..<first])
    }

    private func startOfWeek(containing date: Date) -> Date {
        let day = calendar.startOfDay(for: date)
        var cursor = day
        for _ in 0..<7 {
            if calendar.component(.weekday, from: cursor) == calendar.firstWeekday {
                return cursor
            }
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else {
                return cursor
            }
            cursor = previous
        }
        return day
    }
}
