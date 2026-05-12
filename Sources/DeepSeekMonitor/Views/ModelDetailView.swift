import SwiftUI

struct ModelDetailView: View {
    @ObservedObject var viewModel: DashboardViewModel
    let model: DeepSeekModel

    @Environment(\.colorScheme) private var colorScheme

    private var summary: ModelUsageSummary? {
        viewModel.summary(for: model)
    }

    private var points: [ModelDailyUsagePoint] {
        expandedPoints(from: viewModel.dailyPoints(for: model))
    }

    private var totalRequests: Int {
        points.reduce(0) { $0 + $1.requestCount }
    }

    private var totalTokens: Int {
        points.reduce(0) { $0 + $1.totalTokens }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                headerCard

                HStack(spacing: 12) {
                    MetricCard(
                        title: "API 请求次数",
                        value: formatNumber(totalRequests),
                        tint: tint
                    )

                    MetricCard(
                        title: "Tokens",
                        value: formatNumber(totalTokens),
                        tint: tint
                    )
                }

                DetailBarChartCard(
                    title: "按日 Token 消耗",
                    subtitle: pointsRangeText,
                    totalText: formattedTokens(totalTokens),
                    points: points.map {
                        ChartValuePoint(
                            dateText: fullDateFormatter.string(from: $0.date),
                            label: $0.label,
                            value: $0.totalTokens,
                            breakdown: ChartBreakdown(
                                totalTokens: $0.totalTokens,
                                inputCacheHitTokens: $0.inputCacheHitTokens,
                                inputCacheMissTokens: $0.inputCacheMissTokens,
                                outputTokens: $0.outputTokens
                            )
                        )
                    },
                    gradient: gradient,
                    emptyText: "当前没有可显示的 Token 数据",
                    valueFormatter: formattedTokens
                )

                DetailBarChartCard(
                    title: "按日 API 请求次数",
                    subtitle: pointsRangeText,
                    totalText: formatNumber(totalRequests),
                    points: points.map {
                        ChartValuePoint(
                            dateText: fullDateFormatter.string(from: $0.date),
                            label: $0.label,
                            value: $0.requestCount,
                            breakdown: nil
                        )
                    },
                    gradient: gradient,
                    emptyText: "当前没有可显示的请求次数",
                    valueFormatter: formatNumber
                )
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.windowBackground(for: colorScheme))
    }

    private var headerCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(gradient.opacity(0.16))
                    .frame(width: 54, height: 54)

                Image(systemName: model.systemImageName)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(model.displayName)
                    .font(.title2.weight(.semibold))

                Text(summary?.costFormatted ?? "暂无费用数据")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(18)
        .background(Theme.cardBackground(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var pointsRangeText: String {
        guard let first = points.first?.label, let last = points.last?.label else {
            return "暂无日期范围"
        }
        return "\(first) - \(last)"
    }

    private var tint: Color {
        switch model {
        case .flash: return Theme.flash
        case .pro:   return Theme.pro
        }
    }

    private var gradient: LinearGradient {
        switch model {
        case .flash: return Theme.flashGradient
        case .pro:   return Theme.proGradient
        }
    }

    private var fullDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    private func expandedPoints(from original: [ModelDailyUsagePoint]) -> [ModelDailyUsagePoint] {
        let lookup = Dictionary(uniqueKeysWithValues: original.map { ($0.date, $0) })
        return viewModel.chartData.map { chartPoint in
            if let point = lookup[chartPoint.date] {
                return point
            }
            return ModelDailyUsagePoint(
                date: chartPoint.date,
                label: chartPoint.dayLabel,
                totalTokens: 0,
                inputCacheHitTokens: 0,
                inputCacheMissTokens: 0,
                outputTokens: 0,
                requestCount: 0
            )
        }
    }

    private func formattedTokens(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.2fM", Double(value) / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return "\(value)"
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let tint: Color

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Theme.cardBackground(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct ChartValuePoint: Identifiable {
    let id = UUID()
    let dateText: String
    let label: String
    let value: Int
    let breakdown: ChartBreakdown?
}

private struct ChartBreakdown {
    let totalTokens: Int
    let inputCacheHitTokens: Int
    let inputCacheMissTokens: Int
    let outputTokens: Int
}

private struct DetailBarChartCard: View {
    let title: String
    let subtitle: String
    let totalText: String
    let points: [ChartValuePoint]
    let gradient: LinearGradient
    let emptyText: String
    let valueFormatter: (Int) -> String

    @Environment(\.colorScheme) private var colorScheme
    @State private var hoveredPointID: ChartValuePoint.ID?

    private var maxValue: Int {
        max(points.map(\.value).max() ?? 0, 1)
    }

    private var hasVisibleData: Bool {
        points.contains { $0.value > 0 }
    }

    private var hoveredPoint: ChartValuePoint? {
        guard let hoveredPointID else { return nil }
        return points.first { $0.id == hoveredPointID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(totalText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if hasVisibleData {
                ZStack(alignment: .topLeading) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .bottom, spacing: 10) {
                            ForEach(points) { point in
                                VStack(spacing: 8) {
                                    Text(point.value > 0 ? valueFormatter(point.value) : "")
                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .frame(height: 14)

                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(gradient)
                                        .frame(width: 18, height: barHeight(for: point.value))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .fill(Color.clear)
                                                .contentShape(Rectangle())
                                                .onHover { isHovering in
                                                    hoveredPointID = isHovering ? point.id : (hoveredPointID == point.id ? nil : hoveredPointID)
                                                }
                                        }

                                    Text(point.label)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.tertiary)
                                }
                                .frame(width: 40)
                            }
                        }
                        .padding(.top, 4)
                        .frame(height: 220, alignment: .bottom)
                    }

                    if let hoveredPoint, let breakdown = hoveredPoint.breakdown {
                        TokenBreakdownTooltip(
                            dateText: hoveredPoint.dateText,
                            totalTokens: breakdown.totalTokens,
                            inputCacheHitTokens: breakdown.inputCacheHitTokens,
                            inputCacheMissTokens: breakdown.inputCacheMissTokens,
                            outputTokens: breakdown.outputTokens
                        )
                        .padding(.top, 6)
                        .padding(.leading, 6)
                    }
                }
            } else {
                HStack {
                    Spacer()
                    Text(emptyText)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(height: 120)
            }
        }
        .padding(18)
        .background(Theme.cardBackground(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func barHeight(for value: Int) -> CGFloat {
        guard value > 0 else { return 10 }
        return max(18, CGFloat(value) / CGFloat(maxValue) * 150)
    }
}

private struct TokenBreakdownTooltip: View {
    let dateText: String
    let totalTokens: Int
    let inputCacheHitTokens: Int
    let inputCacheMissTokens: Int
    let outputTokens: Int

    private var inputCacheMissRateText: String {
        let totalInputTokens = inputCacheHitTokens + inputCacheMissTokens
        guard totalInputTokens > 0 else { return "0%" }
        let percentage = Double(inputCacheMissTokens) / Double(totalInputTokens) * 100
        return String(format: "%.1f%%", percentage)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(dateText)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)

                Spacer(minLength: 12)

                Text("\(formatNumber(totalTokens)) tokens")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }

            tooltipRow(color: Color(red: 0.56, green: 0.79, blue: 0.95), title: "输入（命中缓存）", value: inputCacheHitTokens)
            tooltipRow(
                color: Color(red: 0.40, green: 0.66, blue: 0.96),
                title: "输入（未命中缓存）",
                value: inputCacheMissTokens,
                suffix: inputCacheMissRateText
            )
            tooltipRow(color: Color(red: 0.28, green: 0.47, blue: 0.95), title: "输出", value: outputTokens)
        }
        .padding(16)
        .frame(width: 380)
        .background(Color(white: 0.24).opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .allowsHitTesting(false)
    }

    private func tooltipRow(color: Color, title: String, value: Int, suffix: String? = nil) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(color)
                .frame(width: 18, height: 18)

            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.86))
                    .lineLimit(1)

                if let suffix {
                    Text(suffix)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.52))
                        .lineLimit(1)
                }
            }

            Spacer()

            Text("\(formatNumber(value)) tokens")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
    }
}
