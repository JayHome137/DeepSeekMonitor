import WidgetKit
import SwiftUI

// MARK: - Widget Colors

private let brandBlue = Color(red: 0.302, green: 0.420, blue: 0.996)
private let flashColor = Color.blue
private let proColor = Color.purple
private let costOrange = Color.orange

// MARK: - Widget Configuration

struct DeepSeekWidget: Widget {
    let kind: String = "com.deepseek.monitor.widget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            DeepSeekWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("DeepSeek Monitor")
        .description("查看余额和模型用量")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Entry View

struct DeepSeekWidgetEntryView: View {
    var entry: WidgetEntry

    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(entry: entry)
        case .systemMedium:
            MediumWidgetView(entry: entry)
        default:
            SmallWidgetView(entry: entry)
        }
    }
}

// MARK: - Small Widget

private struct SmallWidgetView: View {
    var entry: WidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerLabel

            Spacer(minLength: 0)

            balanceText

            Spacer(minLength: 0)

            dayCostRow
        }
        .padding(16)
        .containerBackground(.ultraThinMaterial, for: .widget)
        .widgetURL(URL(string: "deepseekmonitor://flash"))
    }

    private var headerLabel: some View {
        HStack(spacing: 6) {
            Text("DeepSeek")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)

            Circle()
                .fill(entry.isAvailable ? Color.green : Color.red)
                .frame(width: 6, height: 6)
        }
    }

    private var balanceText: some View {
        Group {
            if entry.hasData {
                Text(String(format: "¥%.2f", entry.balance))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(entry.isAvailable ? brandBlue : .red)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            } else {
                Text("¥--")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
        }
    }

    private var dayCostRow: some View {
        HStack(spacing: 4) {
            Text("今日")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(entry.hasData
                 ? String(format: "¥%.2f", entry.dayCost)
                 : "¥--")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(costOrange)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

// MARK: - Medium Widget

private struct MediumWidgetView: View {
    var entry: WidgetEntry

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            leftColumn
            rightColumn
        }
        .padding(16)
        .containerBackground(.ultraThinMaterial, for: .widget)
    }

    // MARK: Left Column

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerLabel
                .padding(.bottom, 8)

            balanceText
                .padding(.bottom, 10)

            costsRow

            Spacer(minLength: 0)

            if entry.hasData {
                Text("更新 \(entry.lastUpdated.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headerLabel: some View {
        HStack(spacing: 6) {
            Text("DeepSeek Monitor")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 4)

            Circle()
                .fill(entry.isAvailable ? Color.green : Color.red)
                .frame(width: 6, height: 6)
        }
    }

    private var balanceText: some View {
        Group {
            if entry.hasData {
                Text(String(format: "¥%.2f", entry.balance))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(entry.isAvailable ? brandBlue : .red)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            } else {
                Text("¥--")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
        }
    }

    private var costsRow: some View {
        HStack(spacing: 12) {
            costItem(label: "今日", value: entry.hasData ? entry.dayCost : nil)
            costItem(label: "本月", value: entry.hasData ? entry.monthCost : nil)
        }
    }

    private func costItem(label: String, value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(.secondary)
            Text(value.map { String(format: "¥%.2f", $0) } ?? "¥--")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(costOrange)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    // MARK: Right Column

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("模型用量")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)

            modelRow(
                label: "V4 Flash",
                costCents: entry.flashCostCents,
                color: flashColor,
                url: "deepseekmonitor://flash"
            )
            .padding(.bottom, 8)

            modelRow(
                label: "V4 Pro",
                costCents: entry.proCostCents,
                color: proColor,
                url: "deepseekmonitor://pro"
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func modelRow(label: String, costCents: Int, color: Color, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)

                Text(label)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                if entry.hasData {
                    Text(costFormatted(costCents))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                } else {
                    Text("--")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func costFormatted(_ cents: Int) -> String {
        String(format: "¥%.2f", Double(cents) / 100.0)
    }
}

// MARK: - Preview

#Preview(as: .systemSmall) {
    DeepSeekWidget()
} timeline: {
    WidgetEntry.placeholder
    WidgetEntry(
        date: Date(),
        balance: 1234.56,
        isAvailable: true,
        dayCost: 12.34,
        monthCost: 98.76,
        flashTokens: 150000,
        flashCostCents: 560,
        proTokens: 85000,
        proCostCents: 1230,
        lastUpdated: Date(),
        hasData: true
    )
}

#Preview(as: .systemMedium) {
    DeepSeekWidget()
} timeline: {
    WidgetEntry.placeholder
    WidgetEntry(
        date: Date(),
        balance: 1234.56,
        isAvailable: true,
        dayCost: 12.34,
        monthCost: 98.76,
        flashTokens: 150000,
        flashCostCents: 560,
        proTokens: 85000,
        proCostCents: 1230,
        lastUpdated: Date(),
        hasData: true
    )
}
