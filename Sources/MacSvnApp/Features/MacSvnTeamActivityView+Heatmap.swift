import SwiftUI
import MacSvnCore

/// 日历式提交热力图（FR-EX-06）：列=周，行=周内日。
public struct TeamActivityHeatmapView: View {
    private let days: [TeamActivityDay]
    private let weeks: Int
    private let builder: TeamActivityHeatmapBuilder

    public init(
        days: [TeamActivityDay],
        weeks: Int = 12,
        calendar: Calendar = .current
    ) {
        self.days = days
        self.weeks = weeks
        self.builder = TeamActivityHeatmapBuilder(calendar: calendar)
    }

    public var body: some View {
        let grid = builder.build(from: days, weeks: weeks)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 3) {
                weekdayLabels
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 3) {
                        ForEach(Array(grid.weeks.enumerated()), id: \.offset) { _, column in
                            VStack(spacing: 3) {
                                ForEach(Array(column.enumerated()), id: \.offset) { _, cell in
                                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                                        .fill(color(for: cell.intensity))
                                        .frame(width: 12, height: 12)
                                        .help(helpText(for: cell))
                                        .accessibilityLabel(helpText(for: cell))
                                }
                            }
                        }
                    }
                }
            }

            HStack(spacing: 4) {
                Text("少")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                ForEach(0..<5, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(color(for: level))
                        .frame(width: 10, height: 10)
                }
                Text("多")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if grid.maxCommitCount > 0 {
                    Text("峰值 \(grid.maxCommitCount) 次/日")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 8)
                }
            }
        }
    }

    private var weekdayLabels: some View {
        let labels = builder.weekdayLabels()
        return VStack(alignment: .trailing, spacing: 3) {
            ForEach(Array(labels.enumerated()), id: \.offset) { _, label in
                Text(label)
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 12, alignment: .trailing)
            }
        }
    }

    private func color(for intensity: Int) -> Color {
        switch intensity {
        case 0:
            return Color.secondary.opacity(0.12)
        case 1:
            return Color.green.opacity(0.35)
        case 2:
            return Color.green.opacity(0.55)
        case 3:
            return Color.green.opacity(0.75)
        default:
            return Color.green.opacity(0.95)
        }
    }

    private func helpText(for cell: TeamActivityHeatmapCell) -> String {
        let dateText = cell.date.formatted(date: .abbreviated, time: .omitted)
        if cell.commitCount == 0 {
            return "\(dateText)：无提交"
        }
        return "\(dateText)：\(cell.commitCount) 次提交"
    }
}
